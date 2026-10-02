extends SceneTree
# 森林大火模擬（SPEC 1.6「森林大火」）：
# 1. 一生遇到大火的機率：自動玩家（平均打法）玩 RUNS 隻狼到死，統計有幾局遇到大火、每局幾場、燒過幾個區域、逃生結果與死因。
# 2. 逃生選項的平安率：不同狀態的狼（健康、體力低、重傷）在各種逃生方式下的結果分布。
# 用法：bash tools/run_sim.sh fire_sim 0 40

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs := _env_int("RUNS", 40)
	var with_fire := 0; var fires := 0; var burned := 0; var results := {}; var deaths := {}; var noticed := 0
	var ages := 0.0
	for r in runs:
		var ap = AP.new("all", "average")
		ap.start(["forest_east", "forest_north", "forest_south", "forest_west"][r % 4])
		while not ap.done(): ap.step(5)
		ap.finish()
		var list: Array = GS.life_log.get("fires", [])
		if not list.is_empty(): with_fire += 1
		fires += list.size()
		for f in list:
			burned += f["burned"].size()
			var k: String = str(f.get("escape", "")) + "/" + str(f.get("result", ""))
			results[k] = results.get(k, 0) + 1
		deaths[GS.wolf.death_cause] = deaths.get(GS.wolf.death_cause, 0) + 1
		ages += GS.wolf.age_years
	print("== fire_sim：%d 隻狼（平均打法，玩到死）" % runs)
	print("   遇到大火的局 %d%%，每局 %.2f 場，平均壽命 %.1f 歲，每場燒過 %.1f 區" % [100 * with_fire / runs, float(fires) / runs, ages / runs, float(burned) / max(1, fires)])
	print("   逃生（方式/結果；空白 = 沒被困在火裡）：", results)
	print("   死因：", deaths)
	# 逃生選項
	print("   逃生選項的結果分布（各 2000 次）：")
	for state in [["健康", 100.0, 80.0], ["體力低", 100.0, 20.0], ["血量一半以下", 40.0, 80.0]]:
		var line := "     %-8s" % state[0]
		for kind in ["flee", "stream", "den"]:
			var counts := {"safe": 0, "light": 0, "heavy": 0, "death": 0}
			for i in 2000:
				GS.new_game("forest_east")
				GS.auto_playing = true
				GS.wolf.health_max = 100.0; GS.wolf.health = state[1]; GS.wolf.stamina = state[2]
				GS.region_knowledge["forest_north"] = {"visited": true, "features": []}
				GS.fire = {"origin": "forest_east", "phase": "burning", "ignite_at": 0, "noticed": true, "regions": {"forest_east": 0}, "burned": [], "alerted": [], "sheltered": ""}
				var id: String = {"flee": "flee:forest_north", "stream": "stream", "den": "den"}[kind]
				var res = GS.fire_escape(id)
				counts[res["result"]] += 1
			line += "  %s 平安 %2d%% 輕 %2d%% 重 %2d%% 死 %2d%%" % [kind, counts["safe"] / 20, counts["light"] / 20, counts["heavy"] / 20, counts["death"] / 20]
		print(line)
	GS.auto_playing = false
	quit()
	return true
