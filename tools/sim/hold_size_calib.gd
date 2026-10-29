extends SceneTree
# 咬住之後的喘依體型（2026-10-29 QA：咬住小河狸卻喘不過氣只能鬆口）：小獵物、幼體，改前（倍率全 1）vs 改後；
# 一生模擬裡常見的狼（力量 86 技巧 80 速度 61 感知 70、5 歲）、體力 STAMINA（預設 45），夏季，交給本能，每格 RUNS 場（預設 120）。
# 記：獵到、咬住後被掙脫（broke_free）、自己鬆口（released，喘不夠時只剩鬆口）。
# 用法：bash tools/run_sim.sh hold_size_calib 0 120
var f := 0

const PREY := [["snowshoe_hare", "adult", "dense_forest", "forest_east"], ["hare", "adult", "prairie", "grassland_plains"], ["beaver", "adult", "stream", "forest_east"],
	["beaver", "juvenile", "stream", "forest_east"], ["marmot", "adult", "scree", "mountain_canyon"], ["pronghorn", "juvenile", "prairie", "grassland_plains"],
	["white_tailed_deer", "juvenile", "forest_edge", "forest_east"], ["white_tailed_deer", "adult", "forest_edge", "forest_east"], ["elk", "adult", "clearing", "forest_east"]]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 120
	var stamina: float = float(OS.get_environment("STAMINA")) if OS.get_environment("STAMINA") != "" else 45.0
	var tun: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical_hunt.json"))
	var ones := {}
	for k in tun["hold"].get("size_mult", {}).keys():
		ones[k] = 1.0
	print("== 咬住之後的喘依體型：改前（倍率 1）vs 改後，體力 %d，每格 %d 場" % [stamina, runs])
	for p in PREY:
		gs.new_game(p[3])
		gt.season_index = gt.SEASONS.find("summer")
		var line := "  %-18s %-9s" % [p[0], p[1]]
		for mode in ["before", "after"]:
			gs.tactical_overrides = {"hold": {"size_mult": ones}} if mode == "before" else {}
			var ok := 0
			var held := 0
			var lost_hold := 0
			for i in runs:
				for st in [["speed", 61.0], ["skill", 80.0], ["strength", 86.0], ["perception", 70.0], ["age_years", 5.0]]:
					gs.debug_set_stat(st[0], st[1])
				gs.wolf.stamina = stamina
				gs.wolf.health = gs.wolf.health_max
				var h = gs.start_hunt(p[0], p[1], -1, false, p[2])
				var th = gs.start_tactical(h)
				TacticalInstinct.play(th)
				var sts: Dictionary = th.stats
				if th.result == "caught":
					ok += 1
				lost_hold += int(sts.get("broke_free", 0))
				held += int(sts.get("released", 0))
			line += "  %s 獵到 %3d%%（掙脫 %d、鬆口 %d）" % ["改前" if mode == "before" else "改後", roundi(100.0 * ok / runs), lost_hold, held]
		print(line)
	gs.tactical_overrides = {}
	quit()
	return true
