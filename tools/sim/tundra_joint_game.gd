extends SceneTree
# Phase 2i（苔原狼一起狩獵接進主遊戲）的回歸測試：
#   1. 加入苔原狼的狩獵：走戰術地圖；開局獵物已經在逃、苔原狼（追擊）在目標後方；最多 2 隻上場
#   2. 跟上來：開局只有你；第 follow_delay 回合從你身後出現（追擊、驅趕），紀錄寫一句
#   3. 只有 1 隻成狼：上場 1 隻、單數的寫法
#   4. 一起獵到：照現在的規則分肉（with_tundra）、紀錄一起狩獵
#   5. 沒有苔原狼的狩獵不受影響
# 第 2 步：
#   6. 交給本能挑的打法：鹿群有驅趕的同伴（跟上來）→ 等驅趕；加入（獵物在逃）→ 一起猛追；駝鹿 → 猛追
#   7. 交給本能玩到底：加入、跟上來的馴鹿成功率比單狼高（各 60 場，印出來）
#   8. 畫面：主遊戲的戰術畫面有苔原狼時多一行說明
# 用法：bash tools/run_sim.sh tundra_joint_game
var f := 0
var gs
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _allies(th) -> Array:
	return th.wolves.filter(func(w): return bool(w.get("ally", false)))

func _hunt(animal: String, help: int, joined: bool):
	var h = gs.start_hunt(animal, "adult", -1, false, "open_tundra")
	if help > 0:
		h.apply_tundra_help(help, joined)
	return h

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	gs.new_game("tundra_south")
	gs.debug_force_transition("adult")
	gs.pending_events.clear()
	# 1. 加入
	var ok_join := true
	var fleeing := true
	var near := true
	for i in 20:
		var h = _hunt("caribou", 2 + i % 3, true)
		if not gs.tactical_eligible(h):
			ok_join = false
			break
		var th = gs.start_tactical(h)
		var al: Array = _allies(th)
		if al.size() != 2 or al.any(func(w): return str(w["role"]) != "chase"):
			ok_join = false
		if str(th.herd[th.target]["state"]) != "flee":
			fleeing = false
		for w in al:
			if th.dist(w["pos"], th.herd[th.target]["pos"]) > float(th.t["allies"]["game"]["join_dist"]) + 2.5:
				near = false
	_check(ok_join, "加入：走戰術地圖、上場 2 隻（成狼 2～4 隻時）、都是追擊")
	_check(fleeing, "加入：開局目標已經在逃")
	_check(near, "加入：苔原狼在目標附近（join_dist ＋ 2.5 格內）")
	# 2. 跟上來
	var h2 = _hunt("caribou", 2, false)
	var th2 = gs.start_tactical(h2)
	var start_ok: bool = _allies(th2).is_empty() and th2.pending_allies.size() == 2
	var delay: int = int(th2.t["allies"]["game"]["follow_delay"])
	var arrived_at := -1
	var said := false
	for r in 8:
		if th2.done:
			break
		th2.observe()
		for e in th2.events:
			if str(e).contains("跟上來"):
				said = true
		th2.events = []
		if arrived_at < 0 and _allies(th2).size() == 2:
			arrived_at = th2.rounds
	var roles: Array = _allies(th2).map(func(w): return str(w["role"]))
	_check(start_ok and arrived_at == delay and said and roles.has("chase") and roles.has("drive"),
		"跟上來：開局只有你，第 %d 回合從身後出現（實際第 %d 回合；角色 %s；紀錄 %s）" % [delay, arrived_at, roles, said])
	# 3. 只有 1 隻成狼
	var h3 = _hunt("caribou", 1, true)
	var th3 = gs.start_tactical(h3)
	_check(_allies(th3).size() == 1 and th3.events.any(func(e): return str(e).begins_with("那隻苔原狼")), "只有 1 隻成狼：上場 1 隻、單數的寫法")
	# 4. 一起獵到
	var h4 = _hunt("caribou", 2, true)
	var th4 = gs.start_tactical(h4)
	gs.wolf.hunger = 30.0
	var j0: int = int(gs.life_log.get("joint_hunts", 0))
	th4._finish("caught", "test")
	gs.finish_tactical_hunt(h4, th4)
	_check(bool(gs.current_feeding.get("with_tundra", false)) and int(gs.life_log.get("joint_hunts", 0)) == j0 + 1, "一起獵到：和苔原狼分肉、紀錄一起狩獵")
	gs.current_feeding = {}
	# 5. 沒有苔原狼
	var h5 = _hunt("caribou", 0, false)
	var th5 = gs.start_tactical(h5)
	_check(th5.wolves.size() == 1 and th5.pending_allies.is_empty(), "沒有苔原狼的狩獵：只有你")
	# 加入的入口：GameState.join_tundra_hunt 也帶苔原狼（自動玩家、照常過日子走這裡）
	gs.current_discovery = {"kind": "tundra_hunt", "animal_id": "caribou", "location": "open_tundra"}
	var hj = gs.join_tundra_hunt()
	var thj = gs.start_tactical(hj)
	_check(hj.tundra_joined and _allies(thj).size() == mini(2, gs.tundra_adults()) and gs.tundra_adults() > 0,
		"join_tundra_hunt：加入的狩獵帶苔原狼（成狼 %d 隻，上場 %d 隻）" % [gs.tundra_adults(), _allies(thj).size()])
	# 6. 本能的打法
	var p_follow: String = TacticalInstinct.pick_policy(gs.start_tactical(_hunt("caribou", 2, false)))
	var p_join: String = TacticalInstinct.pick_policy(gs.start_tactical(_hunt("caribou", 2, true)))
	var hm = gs.start_hunt("moose", "adult", -1, false, "open_tundra")
	hm.apply_tundra_help(2, false)
	var p_moose: String = TacticalInstinct.pick_policy(gs.start_tactical(hm))
	_check(p_follow == "hold" and p_join == "chase" and p_moose in ["chase", "stalk"], "本能：跟上來 %s、加入 %s、駝鹿 %s" % [p_follow, p_join, p_moose])
	# 7. 本能玩到底（成年狼常見的能力值；debug_force_transition 只換生命階段，能力還是小狼的）
	for st in [["speed", 66.0], ["skill", 62.0], ["strength", 70.0], ["perception", 70.0], ["age_years", 4.0]]:
		gs.debug_set_stat(st[0], st[1])
	var rate := {}
	for kind in ["solo", "follow", "join"]:
		var ok := 0
		for i in 60:
			gs.wolf.health = gs.wolf.health_max
			var hh = _hunt("caribou", 0 if kind == "solo" else 2, kind == "join")
			var tt = gs.start_tactical(hh)
			TacticalInstinct.play(tt)
			if tt.result == "caught":
				ok += 1
		rate[kind] = ok
	_check(rate["follow"] > rate["solo"] and rate["join"] > rate["solo"], "交給本能（馴鹿，各 60 場）：單狼 %d、跟上來 %d、加入 %d" % [rate["solo"], rate["follow"], rate["join"]])
	# 8. 畫面的說明
	var view = load("res://prototypes/tactical_hunt/TacticalHunt.tscn").instantiate()
	root.add_child(view)
	view.start_from_game(gs.start_tactical(_hunt("caribou", 2, false)), func(_t): pass)
	_check(view.log_box.text.contains("苔原狼和你一起獵"), "畫面：有苔原狼時多一行說明")
	view.queue_free()
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
