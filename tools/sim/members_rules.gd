extends SceneTree
# Phase 3 第 6 步「狼群成員」的回歸測試（SPEC Phase 3「狼群成員」）：
#   1. 繼承：潛力在父母平均的 ±15% 內；個性 1～2 個，黏人和獨立不同時有
#   2. 成長：1 歲長一半、2 歲長滿；長滿之後不再被拉回潛力（老化照常）
#   3. 跟著你狩獵的未滿 2 歲：技巧的潛力多長一點（有上限）
#   4. 個性決定自動的群獵角色
#   5. 上限：未滿 1 歲不算；離群只在秋冬；獨立的比黏人的容易走；超過上限時最年長的先走；離群有字卡、紀錄
#   6. 存檔 → 讀檔：潛力、個性一樣
# 用法：bash tools/run_sim.sh members_rules
var gs
var gt
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _setup():
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	for st in [["speed", 70.0], ["skill", 60.0], ["strength", 72.0], ["perception", 66.0]]:
		gs.debug_set_stat(st[0], st[1])
	gs.pending_events.clear()
	gs._spawn_she_wolf()
	var m = gs.she_wolf()
	m.territory = gs.current_region
	m.relation = 8
	gs.she_approach()
	gs.pending_events.clear()
	gt.season_index = 0
	gs.breeding()["pregnant"] = true
	gs.breeding()["winter_fed"] = 1.0
	gs._give_birth()
	gs.pending_events.clear()
	return m

func _run() -> void:
	var data = root.get_node("GameData")
	var mc: Dictionary = data.balance["members"]
	# 1
	var m = _setup()
	var ok_pot := true
	var ok_traits := true
	for p in gs.pups():
		for st in ["speed", "strength", "skill", "perception"]:
			var avg: float = (float(gs.wolf.get(st)) + float(m.get(st))) / 2.0
			if float(p.potential[st]) < avg * 0.85 - 0.1 or float(p.potential[st]) > avg * 1.15 + 0.1:
				ok_pot = false
		if p.traits.size() < 1 or p.traits.size() > 2 or (p.traits.has("clingy") and p.traits.has("independent")):
			ok_traits = false
	_check(ok_pot, "潛力在父母平均的 ±15% 內")
	_check(ok_traits, "個性 1～2 個，黏人和獨立不同時有")
	# 2
	var pup = gs.pups()[0]
	var base: float = float(pup.potential["_base"]["speed"])
	var pot: float = float(pup.potential["speed"])
	pup.age_years = 1.0
	gs._grow_young()
	_check(absf(pup.speed - (base + pot) / 2.0) <= 0.2, "1 歲長一半（速度 %.1f，出生 %.1f、潛力 %.1f）" % [pup.speed, base, pot])
	pup.age_years = 2.0
	gs._grow_young()
	_check(absf(pup.speed - pot) <= 0.2, "2 歲長滿（%.1f）" % pup.speed)
	pup.age_years = 3.0
	pup.speed = pot - 5.0
	gs._grow_young()
	_check(is_equal_approx(pup.speed, pot - 5.0), "長滿之後不再被拉回潛力")
	# 3
	var p2 = gs.pups()[0]
	p2.task = "follow"
	var sk0: float = float(p2.potential["skill"])
	gs._young_learn_from_hunt()
	_check(float(p2.potential["skill"]) > sk0, "跟著你狩獵：技巧的潛力 %.1f → %.1f" % [sk0, float(p2.potential["skill"])])
	for i in 100:
		gs._young_learn_from_hunt()
	_check(float(p2.potential["skill"]) - sk0 <= float(mc["learn_max"]) + 0.01, "學到的有上限（+%.1f）" % (float(p2.potential["skill"]) - sk0))
	# 4
	p2.traits = ["bold"]
	_check(gs.hunt_role_of(p2) == "drive", "大膽的自動去驅趕")
	p2.traits = ["cautious"]
	_check(gs.hunt_role_of(p2) == "ambush", "謹慎的自動埋伏")
	p2.traits = ["enduring"]
	_check(gs.hunt_role_of(p2) == "chase", "耐跑的自動追擊")
	# 5
	m = _setup()
	var n_pups: int = gs.pups().size()
	_check(gs.pack_counted_size() == 2, "未滿 1 歲不算進上限（%d 隻幼狼，算進 %d）" % [n_pups, gs.pack_counted_size()])
	for p in gs.pups():
		p.age_years = 1.5
	_check(gs.pack_counted_size() == 2 + n_pups, "滿 1 歲算進去（%d）" % gs.pack_counted_size())
	mc["disperse_by_age"] = {"1": 1.0, "2": 1.0, "3": 1.0}
	gt.season_index = 1
	gs._maybe_disperse()
	_check(gs.young_members().size() == n_pups, "夏季不會離群")
	# 獨立的比黏人的容易走
	mc["disperse_by_age"] = {"1": 0.3, "2": 0.3, "3": 0.3}
	mc["crowd_per"] = 0.0
	mc["hungry_bonus"] = 0.0
	var ind := 0
	var cli := 0
	for i in 200:
		m = _setup()
		var ps: Array = gs.pups()
		ps[0].age_years = 1.5
		ps[0].traits = ["independent"]
		ps[1].age_years = 1.5
		ps[1].traits = ["clingy"]
		gt.season_index = 2
		gs._maybe_disperse()
		if ps[0].pack_id == "dispersed":
			ind += 1
		if ps[1].pack_id == "dispersed":
			cli += 1
	_check(ind > cli * 2, "獨立的比黏人的容易走（200 次：%d／%d）" % [ind, cli])
	# 超過上限：最年長的先走
	mc["disperse_by_age"] = {"1": 0.0, "2": 0.0, "3": 0.0}
	mc["over_cap_bonus"] = 1.0
	mc["max_size"] = 4
	m = _setup()
	var all: Array = gs.pups()
	for i in all.size():
		all[i].age_years = 1.0 + 0.25 * i
	gt.season_index = 2
	gs.pending_events.clear()
	gs._maybe_disperse()
	var oldest = all[all.size() - 1]
	_check(gs.pack_counted_size() <= 4 and oldest.pack_id == "dispersed" and all[0].pack_id == "player", "超過上限：最年長的先走（剩 %d）" % gs.pack_counted_size())
	_check(gs.pending_events.any(func(e): return str(e.get("type", "")) == "child_left") and gs.life_events("child.left").size() >= 1 and not (gs.life_log.get("dispersed", []) as Array).is_empty(), "離群有字卡、生命事件、紀錄")
	# 6
	var keep = gs.pups()[0] if not gs.pups().is_empty() else gs.young_members()[0]
	var id: String = keep.id
	var traits: Array = keep.traits.duplicate()
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game("forest_east")
	gs.load_from_dict(d)
	_check(gs.npcs[id].traits == traits and gs.npcs[id].potential.has("speed"), "存檔後潛力、個性一樣")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
