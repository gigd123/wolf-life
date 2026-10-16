extends SceneTree
# 雪況逐日延續（2026-10-16 方案 A）的模擬：每張地圖跑 YEARS 年（一季 10 天、每年春天擲年況），比較
#   新做法（逐日延續）與舊做法（每天依權重獨立擲）在各季節、早晚段的雪況比例，以及一段雪況平均持續幾天、
#   一夜跳兩級（無雪↔深雪）的次數、冬季第一天沒雪、夏季有雪的天數。
# 用法：bash tools/run_sim.sh snow_sim（環境變數 YEARS，預設 300）
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var years: int = int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 300
	var cfg: Dictionary = root.get_node("GameData").events["snow"]
	var days_per: int = gt._season_day_count()
	gs.new_game("forest_east")
	for map_id in ["forest", "tundra", "mountain", "grassland"]:
		var dist_new := {}; var dist_old := {}
		var runs_new := [0, 0]; var runs_old := [0, 0] # [段數, 天數]
		var jumps := 0; var winter_first_none := 0; var summer_snow := 0
		var cur_old := ""; var last_new := ""
		gs.snow = {}
		gt.season_index = 3 # 從冬季開始，第一次換季就是春天
		for y in years:
			for si in 4:
				gt.season_index = (gt.season_index + 1) % 4
				gt.day = 1
				var season: String = gt.current_season()
				if season == "spring":
					gs._new_year()
				gs.pending_events.clear()
				for d in days_per:
					gt.day = d + 1
					gs._update_snow()
					var s: String = gs.snow[map_id]
					var phase: String = "early" if gt.day <= int(cfg.get("early_days", 4)) else "late"
					var key: String = season + "_" + phase
					var table: Dictionary = cfg["maps"].get(map_id, cfg["maps"]["forest"])
					var w: Dictionary = gs._snow_year_weights(table.get(key, table.get(season, {"none": 1})), season)
					var o: String = str(root.get_node("RNGService").weighted_pick(w))
					if season == "summer":
						key = "summer"
					_add(dist_new, key, s); _add(dist_old, key, o)
					if last_new != "":
						if (last_new == "none" and s == "deep") or (last_new == "deep" and s == "none"):
							jumps += 1
						if s != last_new:
							runs_new[0] += 1
					if cur_old != "" and o != cur_old:
						runs_old[0] += 1
					runs_new[1] += 1; runs_old[1] += 1
					last_new = s; cur_old = o
					if season == "winter" and gt.day == 1 and s == "none":
						winter_first_none += 1
					if season == "summer" and s != "none":
						summer_snow += 1
		print("== %s（%d 年）：一段雪況平均 新 %.1f 天／舊 %.1f 天；一夜跳兩級 %d；冬季第一天沒雪 %d；夏季有雪 %d 天" % [map_id, years,
			float(runs_new[1]) / max(1, runs_new[0]), float(runs_old[1]) / max(1, runs_old[0]), jumps, winter_first_none, summer_snow])
		var mean_run: float = float(runs_new[1]) / max(1, runs_new[0])
		if jumps > 0 or winter_first_none > 0 or summer_snow > 0 or mean_run < 2.5 or mean_run > 7.0:
			fails += 1
			print("  ✗ %s：一夜跳兩級、冬季第一天沒雪、夏季有雪都要是 0，一段雪況平均 2.5～7 天" % map_id)
		for key in ["autumn_early", "autumn_late", "winter_early", "winter_late", "spring_early", "spring_late", "summer"]:
			print("  %-13s 新 %s　舊 %s" % [key, _fmt(dist_new.get(key, {})), _fmt(dist_old.get(key, {}))])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _add(dist: Dictionary, key: String, s: String) -> void:
	if not dist.has(key):
		dist[key] = {}
	dist[key][s] = int(dist[key].get(s, 0)) + 1

func _fmt(d: Dictionary) -> String:
	var total := 0
	for v in d.values():
		total += int(v)
	var parts: Array = []
	for s in ["none", "light", "deep", "crust"]:
		parts.append("%s %2d%%" % [{"none": "無", "light": "淺", "deep": "深", "crust": "殼"}[s], roundi(100.0 * int(d.get(s, 0)) / max(1, total))])
	return " ".join(parts)
