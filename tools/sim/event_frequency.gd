extends SceneTree
# 主動事件頻率（SPEC「主動事件」）：機器人輪流休息、探索、快轉、睡覺跑 30 天 × 10 次，
# 分「一般」與「一直待在陌生灰狼範圍」兩種情況統計每天的事件數（目標約 1 次、最多 2 次），
# 並檢查暴雨中的線索變化（氣味變少、足跡都是新的）。
# 用法：bash tools/run_sim.sh event_frequency

func _process(_d):
	var GS = root.get_node("GameState"); var GT = root.get_node("GameTime")
	for mode in ["roam", "stay_in_territory"]:
		var counts := {}; var days := 0
		for run in 10:
			GS.new_game("forest_east")
			if mode == "stay_in_territory":
				GS.current_region = GS.stranger_territory
			var start_day: int = GS.life_log["days_lived"]
			var g := 0
			while GS.life_log["days_lived"] - start_day < 30 and g < 5000:
				g += 1
				GS.wolf.hunger = 90; GS.wolf.health = 100
				match g % 4:
					0: GS.action_short_rest()
					1: GS.action_explore(); GS.clear_discovery()
					2: GS.action_rest_until(GT.PERIODS[(GT.period_index + 2) % 5])
					3:
						if GT.current_period() == "predawn": GS.action_sleep()
						else: GS.action_explore(); GS.clear_discovery()
				var ev = GS.pop_event()
				while not ev.is_empty():
					counts[ev["type"]] = counts.get(ev["type"], 0) + 1
					if ev["type"] == "driven_off":
						GS.apply_drive_off()
						if mode == "stay_in_territory": GS.current_region = GS.stranger_territory
					ev = GS.pop_event()
			days += 30
		var per_day := {}
		var total := 0
		for k in counts.keys(): per_day[k] = "%.2f" % (float(counts[k]) / days); total += counts[k]
		print("%s: events/day total %.2f  %s" % [mode, float(total) / days, per_day])
	var ent := {"type": "territory", "animal": "stranger_wolf", "region": GS.stranger_territory}
	print("territory knowledge level ", GS.knowledge_level(ent), " territory ", GS.stranger_territory)
	# storm effects
	GS.new_game("forest_east"); GS.start_storm()
	var scent := 0; var tracks := 0; var stale_tracks := 0
	for i in 400:
		GS.wolf.hunger = 90
		GS.weather = "storm"; GS.weather_until = 999999
		var d = GS.action_explore()
		if d.get("source_kind", "") == "prey":
			if d["clue"] == "scent": scent += 1
			if d["clue"] == "track":
				tracks += 1
				if not d["fresh"]: stale_tracks += 1
		GS.clear_discovery()
	print("storm: scent clues %d, track clues %d (stale %d)" % [scent, tracks, stale_tracks])
	quit(); return true
