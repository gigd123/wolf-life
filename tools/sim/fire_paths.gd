extends SceneTree
# 大火的跨路徑一致性（文案一致性 D，2026-10-16；試玩 BUG-07、08）：起火 → 燃燒 → 熄滅 → 焦黑 → 草木新生，
# 每個時段檢查所有森林區域的火況（burn_state）：
#   1. 和底層資料一致：正在燒 ⇔ 在 fire.regions；焦黑／新生 ⇔ 記在 region_burn
#   2. 存檔 → 讀檔後一樣
#   3. 走進區域時的描述和火況一致（燒過才寫焦黑或新芽、正在燒才跳逃生、平常不寫）
#   4. 「火熄了」卡片列的區域，當下都是焦黑
#   5. 大火結束後再選逃生不會寫壞 fire
#   6. 暴風雪結束後再選也不會寫壞 blizzard
# 走法：留在巢穴、每個時段換一個相鄰區域，兩種都跑；起火點輪流。
# 用法：bash tools/run_sim.sh fire_paths
var f := 0
var fails := 0
var gs
var logs: Array = []
var seen := {"arrive_burning": 0, "arrive_ash": 0, "arrive_regrowth": 0, "arrive_none": 0, "fire_over": 0, "burning_runs": 0, "reloads": 0}

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	gs.log_message.connect(func(m): logs.append(str(m)))
	var forest: Array = ["forest_east", "forest_north", "forest_west", "forest_south"]
	var runs := 0
	for origin in forest:
		for walk in [false, true]:
			for seed in 3:
				runs += 1
				_run(gt, forest, origin, walk, seed)
	print("大火跨路徑：%d 場（起火點 4 × 留在原地／到處走 × 3 種子）；涵蓋：%s" % [runs, seen])
	# 5. 大火結束後再選逃生（巢穴濃煙竄入、火剛好熄了）：不會寫出沒有 phase 的 fire（2026-10-23 牧場模擬發現，之後每個時段報錯）
	gs.new_game("forest_east")
	gs.fire = {}
	var r: Dictionary = gs.fire_escape("den")
	gs._hide_until_fire_passes("den")
	_check(r.is_empty() and gs.fire.is_empty(), "大火結束後選逃生：fire 維持空的（%s）" % str(gs.fire))
	# 6. 暴風雪同樣的情況（2026-10-24 苔原的一生模擬發現）：風雪結束後再選躲或退，不會寫出沒有 phase 的 blizzard
	gs.blizzard = {}
	var rb: Dictionary = gs.blizzard_choose("dig")
	_check(rb.is_empty() and gs.blizzard.is_empty(), "暴風雪結束後再選：blizzard 維持空的（%s）" % str(gs.blizzard))
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _run(gt, forest: Array, origin: String, walk: bool, seed: int) -> void:
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	root.get_node("RNGService").set_seed(seed * 101 + forest.find(origin))
	gs.debug_start_fire(origin)
	var ctx := "起火 %s %s 種子 %d" % [origin, "到處走" if walk else "留在原地", seed]
	var saw_burning := false
	var fire_over_checked := false
	for step in 400:
		if gs.wolf == null or not gs.wolf.alive:
			gs.wolf.alive = true
		gs.wolf.health = gs.wolf.health_max
		gs.wolf.hunger = 80.0
		gs.wolf.stamina = 80.0
		# 走法：每個時段換到一個相鄰區域（只在森林裡走）
		if walk and step % 2 == 0:
			var adj: Array = gs.adjacent_regions().filter(func(r): return forest.has(r))
			if not adj.is_empty():
				var to: String = adj[step / 2 % adj.size()]
				var before_state: String = gs.burn_state(to)
				logs.clear()
				gs.pending_events.clear()
				gs.action_move(to)
				_check_arrival(to, before_state, ctx + " 第 %d 步" % step)
				seen["arrive_" + (before_state if before_state != "" else "none")] += 1
		else:
			gt.advance_turns(1)
		# 火熄了的卡片
		for e in gs.pending_events:
			if e.get("type", "") == "fire_over" and not fire_over_checked:
				fire_over_checked = true
				seen["fire_over"] += 1
				for r in e.get("burned", []):
					_check(gs.burn_state(r) == "ash", "%s：「火熄了」列的 %s 當下是焦黑（實際 %s）" % [ctx, r, gs.burn_state(r)])
		gs.pending_events.clear()
		gs.current_discovery = {}
		var states: Dictionary = {}
		for r in forest:
			var s: String = gs.burn_state(r)
			states[r] = s
			saw_burning = saw_burning or s == "burning"
			var in_fire: bool = gs.fire.get("regions", {}).has(r)
			_check((s == "burning") == in_fire, "%s：%s 的火況 %s 和 fire.regions 不一致" % [ctx, r, s])
			_check(s in ["burning", ""] or gs.region_burn.has(r), "%s：%s 是 %s 卻沒有記在 region_burn" % [ctx, r, s])
		# 存檔 → 讀檔
		if step % 25 == 0:
			var data = JSON.parse_string(JSON.stringify(gs.to_dict()))
			gs.load_from_dict(data)
			seen["reloads"] += 1
			for r in forest:
				_check(gs.burn_state(r) == states[r], "%s 第 %d 步：讀檔後 %s 的火況 %s → %s" % [ctx, step, r, states[r], gs.burn_state(r)])
		if gs.fire.is_empty() and step > 40:
			break
	if saw_burning:
		seen["burning_runs"] += 1
	_check(saw_burning or bool(gs.life_log.get("fires", []).any(func(x): return x.get("result", "") == "rained")), "%s：火有燒起來" % ctx)
	# 之後一路跳到草木新生結束：火況依序 焦黑 → 新生 → 平常，不會倒退
	var order := {"ash": 0, "regrowth": 1, "": 2}
	var last: Dictionary = {}
	for day in 70:
		gs.debug_skip_day()
		gs.pending_events.clear()
		if walk:
			var adj2: Array = gs.adjacent_regions().filter(func(r): return forest.has(r))
			if not adj2.is_empty():
				var to2: String = adj2[day % adj2.size()]
				var st2: String = gs.burn_state(to2)
				logs.clear()
				gs.action_move(to2)
				gs.pending_events.clear()
				_check_arrival(to2, st2, ctx + " 火後第 %d 天" % day)
				seen["arrive_" + (st2 if st2 != "" else "none")] += 1
		for r in forest:
			var s: String = gs.burn_state(r)
			if not gs.region_burn.has(r):
				continue
			_check(s != "burning", "%s：熄滅後 %s 又在燒" % [ctx, r])
			if last.has(r) and order.has(s) and order.has(last[r]):
				_check(int(order[s]) >= int(order[last[r]]), "%s：%s 火況倒退 %s → %s" % [ctx, r, last[r], s])
			last[r] = s

func _check_arrival(to: String, state: String, ctx: String) -> void:
	var fire_lines: Array = logs.filter(func(m): return m.contains("焦") or m.contains("新芽") or m.contains("嫩草"))
	var here_event: bool = gs.pending_events.any(func(e): return e.get("type", "") == "fire_here")
	match state:
		"burning":
			# 走進正在燒的區域：跳逃生（已經在這裡躲過的除外）
			_check(here_event or str(gs.fire.get("sheltered", "")) == to or gs.fire.get("alerted", []).has(to), ctx + "：走進正在燒的 %s 沒有逃生事件" % to)
		"":
			_check(fire_lines.is_empty(), ctx + "：走進平常的 %s 卻寫了火後的描述：%s" % [to, fire_lines])
		"ash":
			_check(not fire_lines.is_empty(), ctx + "：走進焦黑的 %s 沒有描述" % to)
		"regrowth":
			# 新生各描述一次（同一場火）：之後再來不重複，所以這裡只檢查不會寫成焦黑
			_check(not logs.any(func(m): return m.contains("還是一片焦黑")), ctx + "：走進新生的 %s 卻寫還是焦黑" % to)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		if fails <= 30:
			print("  ✗ " + what)
