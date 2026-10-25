extends SceneTree
# Phase 2i 第 7 步：牧場的家畜改走戰術地圖的校準。牛犢、一歲牛、成牛、羊：選單式（自動玩家的選法）／戰術地圖（交給本能）。
# 通過標準（SPEC Phase 2i）：和選單式差 10 個百分點以內（Phase 4a 的驗算：成年狼 牛犢約 83%、一歲牛 66%、成牛 17%、羊 85%）。
# 一般的成年狼，夏季，每格 RUNS 場（預設 80）；括號裡是每場平均受的傷。
# 用法：bash tools/run_sim.sh tactical_livestock_calib 0 100；SET='{"species": {"cattle": {...}}}' 覆寫 tactical_hunt.json（整個檔案逐層合併）
var f := 0

const PREY := [["cattle", "juvenile", "prairie"], ["cattle", "adult", "prairie"], ["cattle", "buck", "prairie"], ["sheep", "adult", "clearing"]]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var HS = load("res://scripts/core/HuntSystem.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 80
	if OS.get_environment("SET") != "":
		gs.tactical_overrides = JSON.parse_string(OS.get_environment("SET"))
	# STATS='{"strength": 84, "skill": 77, "speed": 61, "perception": 70, "age_years": 5}'：換成一生模擬裡的狼（Phase 2i 第 7 步）
	var over: Dictionary = JSON.parse_string(OS.get_environment("STATS")) if OS.get_environment("STATS") != "" else {}
	var ap = AP.new("all", "average")
	ap.tactical = false
	print("== 牧場的家畜：選單式 vs 戰術地圖（交給本能），一般的成年狼，夏季，每格 %d 場" % runs)
	gs.new_game("grassland_plains")
	gs.debug_force_transition("adult")
	# SEASON=winter：換季節（冬季有雪，Phase 2i 第 7 步）
	gt.season_index = gt.SEASONS.find(OS.get_environment("SEASON") if OS.get_environment("SEASON") != "" else "summer")
	gs.snow = {}
	for p in PREY:
		var res := {"menu": 0, "tac": 0}
		var hurt := {"menu": 0.0, "tac": 0.0}
		var rounds := 0
		for mode in ["menu", "tac"]:
			for i in runs:
				for st in [["speed", 62.0], ["skill", 58.0], ["strength", 65.0], ["perception", 65.0], ["age_years", 4.0]]:
					gs.debug_set_stat(st[0], float(over.get(st[0], st[1])))
				gs.wolf.stamina = 80.0
				gs.wolf.health = gs.wolf.health_max
				gs.wolf.clear_injury()
				var h = gs.start_hunt(p[0], p[1], -1, false, p[2])
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
					rounds += th.rounds
					if th.result == "caught":
						res[mode] += 1
					hurt[mode] += th.damage_taken
		print("  %-7s %-9s 選單 %3d%%（傷 %.1f）  戰術 %3d%%（傷 %.1f，%.1f 回合）  差 %+d" % [p[0], p[1], roundi(100.0 * res["menu"] / runs), hurt["menu"] / runs,
			roundi(100.0 * res["tac"] / runs), hurt["tac"] / runs, float(rounds) / runs, roundi(100.0 * (res["tac"] - res["menu"]) / runs)])
	quit()
	return true
