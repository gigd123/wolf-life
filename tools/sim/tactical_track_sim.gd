extends SceneTree
# Phase 2m 第 1 步：循著足跡追（戰術地圖內）。交給本能玩，看：目標在密林裡不見的比例、追上的機率、選追的比例、追上的比例、
# 追上後獵到的比例、整體獵到率和關掉追蹤時比。季節（夏／冬）× 狼（未滿 1 歲／成年）× 鹿（單隻白尾鹿／馬鹿群）；
# 另外印「每次都追」看機率本身（一般的狼大約三成、雪地或流血明顯比較高）。
# 用法：RUNS=150 bash tools/run_sim.sh tactical_track_sim（BREATH_MULT=1.0、APPEAR=2,3 試其他初始值；ONLY_ALWAYS=1 只跑每次都追）
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 150
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var wolves := {
		"young": {"speed": 55, "skill": 45, "strength": 50, "perception": 50, "stamina": 70, "health": 80, "health_max": 80},
		"adult": {"speed": 66, "skill": 71, "strength": 77, "perception": 62, "stamina": 80, "health": 110, "health_max": 110}}
	for season in ["summer", "winter"]:
		for wk in wolves:
			for prey in ["deer", "elk_herd"]:
				for mode in (["off", "always"] if OS.get_environment("ONLY_ALWAYS") != "" else ["off", "instinct", "always"]):
					var r := {"n": 0, "caught": 0, "pend": 0, "follow": 0, "found": 0, "caught_after": 0, "chance": 0.0}
					for i in runs:
						var ctx := {"family": ["dense", "edge", "logs", "stream"][i % 4], "seed": i * 7919 + 11, "condition": ["healthy", "average", "average", "weak"][i % 4],
							"wolf": wolves[wk], "wind_relation": ["headwind", "crosswind", "tailwind"][i % 3], "season": season}
						if prey == "elk_herd":
							ctx["species"] = "elk"
							ctx["herd"] = {"conditions": ["average", "healthy", "healthy", "average", "weak"], "calves": 0}
						var h = TH.new()
						h.setup_from_game(ctx)
						if season == "winter":
							h.game_mods["snow_slow"] = 0.5
						if OS.get_environment("BREATH_MULT") != "":
							h.t["track"]["breath_mult"] = float(OS.get_environment("BREATH_MULT"))
						if OS.get_environment("APPEAR") != "":
							h.t["track"]["appear_dist"] = Array(OS.get_environment("APPEAR").split(",")).map(func(x): return int(x))
						if mode == "off":
							h.t["track"]["enabled"] = false
						var pol: String = TacticalInstinct.pick_policy(h)
						TacticalInstinct.pick_target(h)
						var g := 0
						var was_found := false
						while not h.done and g < 80:
							g += 1
							if h.track_pending:
								r["pend"] += 1
								r["chance"] += float(h.track_chance()["chance"])
								if mode == "always":
									h.follow_track()
								else:
									TacticalInstinct.step(h, pol)
								if h.track_result in ["found", "lost"]:
									r["follow"] += 1
								if h.track_result == "found":
									r["found"] += 1
									was_found = true
								continue
							TacticalInstinct.step(h, pol)
						r["n"] += 1
						if h.result == "caught":
							r["caught"] += 1
							if was_found:
								r["caught_after"] += 1
					var n: float = float(r["n"])
					var pe: float = maxf(1.0, float(r["pend"]))
					print("%s %s %-8s %-8s：獵到 %d%%；在密林不見 %d%%、平均機率 %d%%、選追 %d%%、追上 %d%%（佔追的）、追上後獵到 %d 場" % [
						season, wk, prey, mode, roundi(100.0 * r["caught"] / n), roundi(100.0 * r["pend"] / n), roundi(100.0 * r["chance"] / pe),
						roundi(100.0 * r["follow"] / pe), roundi(100.0 * r["found"] / maxf(1.0, float(r["follow"]))), r["caught_after"]])
	return true
