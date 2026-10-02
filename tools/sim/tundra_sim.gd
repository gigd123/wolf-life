extends SceneTree
# 苔原的事件模擬（1.6 第 6d 步）：自動玩家把巢穴安在苔原（林線、河谷輪流），玩到死，統計
# 暴風雪（每局幾場、怎麼躲、凍傷）、狼獾（交手次數與結果）、渡鴉、白矇天、河冰落水、獵物與死因。
# 另外列出暴風雪各選項的平安率分布。
# 用法：bash tools/run_sim.sh tundra_sim 0 30

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs := _env_int("RUNS", 30)
	var ages := 0.0; var deaths := {}; var prey := {}
	var blizzards := 0; var caught := 0; var bliz_results := {}; var frostbite := 0
	var wolverine := 0; var w_out := {}; var w_dead := 0
	var ravens_seen := 0; var ravens_followed := 0; var whiteouts := 0; var ice := 0
	var winters := 0.0
	for r in runs:
		var ap = AP.new("all", "average")
		ap.start(["tundra_south", "tundra_east"][r % 2])
		while not ap.done(): ap.step(5)
		ap.finish()
		var log: Dictionary = GS.life_log
		ages += GS.wolf.age_years
		winters += GS.wolf.age_years - 0.67
		deaths[GS.wolf.death_cause] = deaths.get(GS.wolf.death_cause, 0) + 1
		for a in log.get("prey_count", {}).keys():
			prey[a] = prey.get(a, 0) + int(log["prey_count"][a])
		for b in log.get("blizzards", []):
			blizzards += 1
			if b.get("in_tundra", false):
				caught += 1
				var k: String = str(b.get("choice", "")) + "/" + str(b.get("result", ""))
				bliz_results[k] = bliz_results.get(k, 0) + 1
		frostbite += int(log.get("frostbite", 0))
		for m in log.get("wolverine_meetings", []):
			wolverine += 1
			w_out[m["outcome"]] = w_out.get(m["outcome"], 0) + 1
		if log.has("wolverine_death"): w_dead += 1
		ravens_seen += int(log.get("ravens_seen", 0)); ravens_followed += int(log.get("ravens_followed", 0))
		whiteouts += int(log.get("whiteouts", 0)); ice += int(log.get("fell_through_ice", 0))
	print("== tundra_sim：%d 隻狼（巢穴在苔原，平均打法，玩到死）" % runs)
	print("   平均壽命 %.1f 歲；死因：%s" % [ages / runs, deaths])
	print("   獵物（每局）：", _per(prey, runs))
	print("   暴風雪：每年 %.2f 場（目標約 0.4），困在風雪裡 %d 場，凍傷 %.2f 次／局" % [blizzards / max(0.1, winters), caught, float(frostbite) / runs])
	print("     怎麼躲／結果：", bliz_results)
	print("   狼獾：每局交手 %.2f 次，結果 %s，牠死掉的局 %d" % [float(wolverine) / runs, w_out, w_dead])
	print("   渡鴉：每局看到 %.1f 次、跟過去 %.1f 次；白矇天每局 %.1f 次；河冰落水每局 %.2f 次" % [float(ravens_seen) / runs, float(ravens_followed) / runs, float(whiteouts) / runs, float(ice) / runs])
	print("   暴風雪選項的結果分布（各 2000 次）：")
	for state in [["健康", 100.0, 80.0, 100.0], ["體力低", 100.0, 20.0, 100.0], ["餓", 100.0, 80.0, 20.0], ["血量一半以下", 40.0, 80.0, 100.0]]:
		var line := "     %-8s" % state[0]
		for kind in ["dig", "den", "retreat"]:
			var counts := {"safe": 0, "light": 0, "heavy": 0}
			for i in 2000:
				GS.new_game("tundra_central")
				GS.auto_playing = true
				GS.den_region = "tundra_central"
				GS.wolf.health_max = 100.0; GS.wolf.health = state[1]; GS.wolf.stamina = state[2]; GS.wolf.hunger = state[3]
				GS.start_blizzard_warning(0)
				GS.blizzard["phase"] = "active"
				var res = GS.blizzard_choose(kind)
				if res.is_empty():
					continue
				counts[res["result"]] += 1
			line += "  %s 平安 %2d%% 輕 %2d%% 重 %2d%%" % [kind, counts["safe"] / 20, counts["light"] / 20, counts["heavy"] / 20]
		print(line)
	GS.auto_playing = false
	quit()
	return true

func _per(d: Dictionary, runs: int) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[k] = snapped(float(d[k]) / runs, 0.1)
	return out
