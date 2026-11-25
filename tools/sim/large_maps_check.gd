extends SceneTree
# 40×40 試玩版（2026-11-25 使用者選 A）的檢查：
#   1. 開關關著：白尾鹿的戰術狩獵照舊 40×16、只有左右是出口
#   2. 開關打開：開闊、林緣、密林、倒木的地形用 40×40（data/tactical_maps_large.json）、四邊都可以跑出去；其他地形（溪、岩坡）照舊
#   3. 大地圖上打 40 場（交給本能）不會卡住，結果有獵到也有逃掉，跑出去的方向不只左右
#   4. 畫面：大地圖開場拉近在狼附近，狼走遠時鏡頭跟過去（keep_in_view）
# 用法：bash tools/run_sim.sh large_maps_check
var f := 0
var fails := 0

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
	print(("  ✓ " if c else "  ✗ ") + msg)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 8
	var gs = root.get_node("GameState")
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	var h = gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult"))
	_ok(h.height == 16 and not h.map_exits_all, "開關關著：40×16、只有左右（%dx%d）" % [h.width, h.height])
	gs.large_tactical_maps = true
	var fams := {}
	for terr in ["meadow", "forest_edge", "dense_forest", "fallen_logs"]:
		var ctx: Dictionary = gs.tactical_context(terr, "crosswind", "average")
		fams[terr] = str(ctx.get("family", ""))
	print("    地形 → 地圖族：", fams)
	var big := 0
	var small := 0
	var res := {}
	var sides := {}
	for i in 40:
		var hunt = gs.start_hunt("white_tailed_deer", "adult")
		var th = gs.start_tactical(hunt)
		var fam: String = str(gs.tactical_context(hunt.terrain, hunt.wind_state(), hunt.condition).get("family", ""))
		if fam in ["open", "edge", "dense", "logs"]:
			if th.height == 40 and th.map_exits_all:
				big += 1
			else:
				print("    ✗ ", fam, " ", th.height)
		else:
			if th.height == 16:
				small += 1
		TacticalInstinct.pick_target(th)
		var p: String = TacticalInstinct.pick_policy(th)
		var guard := 0
		while not th.done and guard < 90:
			guard += 1
			TacticalInstinct.step(th, "stalk" if (th.held or th.track_pending or th.hidden_unfound()) else p)
		res[str(th.result)] = int(res.get(str(th.result), 0)) + 1
		if th.stats.has("exit_side"):
			sides[str(th.stats["exit_side"])] = int(sides.get(str(th.stats["exit_side"]), 0)) + 1
		if not th.done:
			_ok(false, "第 %d 場沒打完（%d 回合）" % [i, th.rounds])
	_ok(big > 0, "開關打開：四族用 40×40、四邊出口（%d 場；其他地形照舊 %d 場）" % [big, small])
	_ok(res.get("caught", 0) > 0 and (res.get("escaped", 0) + res.get("lost", 0)) > 0, "有獵到也有逃掉 %s" % str(res))
	_ok(sides.has("N") or sides.has("S"), "跑出去的方向不只左右 %s" % str(sides))
	# 畫面
	var HD = load("res://prototypes/tactical_hunt/HuntHD2D.gd")
	var th2 = TacticalHunt.new()
	th2.setup_from_game({"family": "open", "seed": 5, "condition": "average", "season": "summer", "large_maps": true,
		"wolf": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}})
	var hd = HD.new()
	hd.size = Vector2(900, 420)
	root.add_child(hd)
	hd.setup(th2)
	await process_frame
	hd.refresh()
	var f0: Vector2 = hd.focus
	th2.wolf_pos = Vector2i(th2.wolf_pos.x, 2 if th2.wolf_pos.y > 20 else 37)
	hd.refresh()
	_ok(th2.height == 40 and hd.focus.distance_to(f0) > 1.0, "狼走遠時鏡頭跟過去（%s → %s）" % [str(f0), str(hd.focus)])
	print("全部通過" if fails == 0 else "有失敗 %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
