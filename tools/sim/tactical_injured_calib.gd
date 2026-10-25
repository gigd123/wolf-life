extends SceneTree
# Phase 2i 第 5 步：受傷的個體改走戰術地圖的校準。每種獵物（成體）受傷時：選單式（自動玩家的選法）／戰術地圖（交給本能）。
# 主遊戲開法（GameState.start_hunt(…, injured=true) + start_tactical；受傷 = 體況虛弱、單隻、帶傷 game.injured_wounds）。
# 通過標準（SPEC Phase 2i）：和選單式差 10 個百分點以內。一般的成年狼，夏季，每格 RUNS 場（預設 60）。
# 用法：bash tools/run_sim.sh tactical_injured_calib；RUNS=100；SP=elk,moose 只跑這些；SET='{"injured_wounds": 2}' 覆寫 tactical_hunt.json game
var f := 0

const PREY := [["white_tailed_deer", "adult", "forest_edge", "forest_east"], ["white_tailed_deer", "buck", "forest_edge", "forest_east"],
	["elk", "adult", "clearing", "forest_east"], ["elk", "buck", "clearing", "forest_east"], ["mule_deer", "adult", "rolling_hills", "grassland_hills"],
	["caribou", "adult", "open_tundra", "tundra_south"], ["moose", "adult", "river_willow", "tundra_east"], ["bison", "adult", "prairie", "grassland_plains"],
	["pronghorn", "adult", "prairie", "grassland_plains"], ["bighorn_sheep", "adult", "scree", "mountain_canyon"], ["beaver", "adult", "stream", "forest_east"],
	["hare", "adult", "prairie", "grassland_plains"], ["snowshoe_hare", "adult", "dense_forest", "forest_east"], ["marmot", "adult", "scree", "mountain_canyon"]]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var HS = load("res://scripts/core/HuntSystem.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	var only: Array = Array(OS.get_environment("SP").split(",")) if OS.get_environment("SP") != "" else []
	if OS.get_environment("SET") != "":
		gs.tactical_overrides = {"game": JSON.parse_string(OS.get_environment("SET"))}
	# STATS='{"strength": 84, "skill": 77, "speed": 61, "perception": 70, "age_years": 5}'：換成一生模擬裡的狼（Phase 2i 第 7 步）
	var over: Dictionary = JSON.parse_string(OS.get_environment("STATS")) if OS.get_environment("STATS") != "" else {}
	var ap = AP.new("all", "average")
	ap.tactical = false
	print("== 受傷的個體：選單式 vs 戰術地圖（交給本能），一般的成年狼，夏季，每格 %d 場" % runs)
	for p in PREY:
		if not only.is_empty() and not only.has(p[0]):
			continue
		gs.new_game(p[3])
		gs.debug_force_transition("adult")
		gt.season_index = gt.SEASONS.find("summer")
		var res := {"menu": 0, "tac": 0}
		var hurt := {"menu": 0.0, "tac": 0.0}
		for mode in ["menu", "tac"]:
			for i in runs:
				for st in [["speed", 62.0], ["skill", 58.0], ["strength", 65.0], ["perception", 65.0], ["age_years", 4.0]]:
					gs.debug_set_stat(st[0], float(over.get(st[0], st[1])))
				gs.wolf.stamina = 80.0
				gs.wolf.health = gs.wolf.health_max
				gs.wolf.clear_injury()
				var h = gs.start_hunt(p[0], p[1], -1, false, p[2], true)
				if mode == "menu":
					var hp0: float = gs.wolf.health
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
					hurt[mode] += hp0 - gs.wolf.health
				else:
					var th = gs.start_tactical(h)
					TacticalInstinct.play(th)
					if th.result == "caught":
						res[mode] += 1
					hurt[mode] += th.damage_taken
		print("  %-18s %-6s 選單 %3d%%（傷 %.1f）  戰術 %3d%%（傷 %.1f）  差 %+d" % [p[0], p[1], roundi(100.0 * res["menu"] / runs), hurt["menu"] / runs,
			roundi(100.0 * res["tac"] / runs), hurt["tac"] / runs, roundi(100.0 * (res["tac"] - res["menu"]) / runs)])
	quit()
	return true
