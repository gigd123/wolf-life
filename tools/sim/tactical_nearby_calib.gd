extends SceneTree
# Phase 2i 第 5 步：獵物靠近（休息時走到旁邊）改走戰術地圖短版的校準。
# 每種會靠近的獵物（events.json prey_nearby）：選單式（自動玩家的選法）／戰術地圖（交給本能、自己直接撲）；記平均戰術回合數。
# 通過標準（SPEC Phase 2i）：成功率和選單式差 10 個百分點以內；一場不超過約 30 秒（短版，回合數少）。
# 用法：bash tools/run_sim.sh tactical_nearby_calib；RUNS=100；YOUNG=1 用 1 歲的狼
var f := 0

const PREY := [["snowshoe_hare", "adult", "dense_forest", "forest_east"], ["white_tailed_deer", "juvenile", "forest_edge", "forest_east"],
	["mule_deer", "juvenile", "rolling_hills", "grassland_hills"], ["caribou", "juvenile", "open_tundra", "tundra_south"]]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var HS = load("res://scripts/core/HuntSystem.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 80
	var young: bool = OS.get_environment("YOUNG") != ""
	# SET='{"nearby_dist": [3, 4]}'：覆寫 tactical_hunt.json game（nearby_calf_alone 要改資料檔，開場前讀）
	if OS.get_environment("SET") != "":
		gs.tactical_overrides = {"game": JSON.parse_string(OS.get_environment("SET"))}
	var ap = AP.new("all", "average")
	ap.tactical = false
	var stats: Array = [["speed", 52.0], ["skill", 45.0], ["strength", 50.0], ["perception", 50.0], ["age_years", 1.2]] if young else [["speed", 62.0], ["skill", 58.0], ["strength", 65.0], ["perception", 65.0], ["age_years", 4.0]]
	print("== 獵物靠近：選單式 vs 戰術地圖短版（%s，夏季，每格 %d 場）" % ["1 歲的狼" if young else "一般的成年狼", runs])
	for p in PREY:
		gs.new_game(p[3])
		gs.debug_force_transition("adult")
		gt.season_index = gt.SEASONS.find("summer")
		var res := {"menu": 0, "tac": 0}
		var rounds := 0
		for mode in ["menu", "tac"]:
			for i in runs:
				for st in stats:
					gs.debug_set_stat(st[0], st[1])
				gs.wolf.stamina = 80.0
				gs.wolf.health = gs.wolf.health_max
				gs.wolf.clear_injury()
				var h = gs.hunt_nearby_prey({"animal_id": p[0], "life_stage": p[1], "terrain": p[2]})
				if mode == "menu":
					var guard := 0
					while h.stage != HS.Stage.DONE and guard < 25:
						guard += 1
						var opt: Dictionary = ap._pick_option(h)
						if opt.is_empty():
							h.give_up()
							break
						h.choose(str(opt["id"]))
					if h.result == HS.Result.SUCCESS:
						res[mode] += 1
				else:
					var th = gs.start_tactical(h)
					TacticalInstinct.play(th)
					rounds += th.rounds
					if th.result == "caught":
						res[mode] += 1
		print("  %-18s %-9s 選單 %3d%%  戰術 %3d%%（平均 %.1f 回合）  差 %+d" % [p[0], p[1], roundi(100.0 * res["menu"] / runs), roundi(100.0 * res["tac"] / runs),
			float(rounds) / runs, roundi(100.0 * (res["tac"] - res["menu"]) / runs)])
	quit()
	return true
