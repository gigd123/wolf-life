extends "res://tools/sim/tactical_hunt_sim.gd"
# Phase 2d 第 2 步：馬鹿接進戰術地圖的校準。地圖族 × 狼（普通、快）× 體況（整群都健康／都虛弱），
# 鹿群 4～7 隻（herd_size）、單隻母馬鹿、夏季鹿群（體況照季節比例、有小鹿，先觀察再交給本能）；
# 四種打法取最好的、交給本能，各 RUNS 場；另外列被踢的比例、回合數。白尾鹿同條件一行當對照。
# 目標（選單式 hunt_levels 的馬鹿約是白尾鹿的 0.8 倍）：普通的狼對健康的成鹿約 20～30%、快的狼約 35～45%；虛弱的約 55～75%。
# 用法：bash tools/run_sim.sh tactical_elk_sim 0 40

const FAMILIES := ["open", "edge", "dense", "stream", "logs"]
const WINDS := ["headwind", "crosswind", "tailwind"]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 40
	var h = TH.new()
	var wolves := {"normal": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
		"fast": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100}}
	print("== 馬鹿（每格 %d 場 × 5 個地圖族；風向輪流）：最好的打法（哪一種）／交給本能；被踢的場次、回合數中位數" % runs)
	for row in [["白尾鹿・單隻", "deer", 1, 0], ["馬鹿・單隻", "elk", 1, 0], ["馬鹿・鹿群", "elk", 6, 0]]:
		for wk in ["normal", "fast"]:
			var line := "%-10s %-6s" % [row[0], wk]
			for cond in ["healthy", "weak"]:
				var by_pol := {}
				var kicked := 0
				var rounds: Array = []
				var inst := 0
				var n := 0
				for pol in ["chase", "pace", "stalk", "ambush", ""]:
					var ok := 0
					for fam in FAMILIES:
						for i in runs:
							var ctx := {"family": fam, "seed": i * 7919 + 17, "condition": cond, "wolf": wolves[wk], "wind_relation": WINDS[i % 3], "species": row[1]}
							if int(row[2]) > 1:
								var conds: Array = []
								for k in 4 + (i % 4):
									conds.append(cond)
								ctx["herd"] = {"conditions": conds, "calves": 0}
							h.setup_from_game(ctx)
							if pol == "":
								TacticalInstinct.play(h)
							else:
								_play(h, pol)
							if h.result == "caught":
								ok += 1
							if pol == "":
								n += 1
								rounds.append(h.rounds)
								if h.kicks > 0:
									kicked += 1
					if pol == "":
						inst = ok
					else:
						by_pol[pol] = float(ok) / (runs * FAMILIES.size())
				var best_pol: String = by_pol.keys()[0]
				for k in by_pol.keys():
					if float(by_pol[k]) > float(by_pol[best_pol]):
						best_pol = k
				rounds.sort()
				line += "  %s 最好 %d%%（%s）本能 %d%% 被踢 %d%%（%d 回合）" % [cond, roundi(100.0 * float(by_pol[best_pol])), best_pol, roundi(100.0 * inst / n), roundi(100.0 * kicked / n), rounds[rounds.size() / 2]]
			print(line)
	# 夏季的鹿群：體況照 5/3/2、有 2 隻小鹿；先觀察（標出最弱的）再交給本能；看獵到的是什麼
	var rnd := RandomNumberGenerator.new()
	for wk in ["normal", "fast"]:
		var got := {}
		var tot := 0
		for fam in FAMILIES:
			for i in runs:
				rnd.seed = i * 31 + 7
				var conds: Array = []
				for k in 4 + (i % 4):
					var r := rnd.randf()
					conds.append("healthy" if r < 0.5 else ("average" if r < 0.8 else "weak"))
				h.setup_from_game({"family": fam, "seed": i * 7919 + 17, "condition": conds[0], "wolf": wolves[wk], "wind_relation": WINDS[i % 3], "species": "elk",
					"herd": {"conditions": conds, "calves": 2}})
				h.observe()
				TacticalInstinct.play(h)
				tot += 1
				var key: String = h.result if h.result != "caught" else "caught." + h.caught_kind + "." + str(h.herd[h.target]["condition"])
				got[key] = int(got.get(key, 0)) + 1
		var caught := 0
		for k in got.keys():
			if str(k).begins_with("caught"):
				caught += int(got[k])
		print("  夏季鹿群（觀察後交給本能）%-6s 獵到 %d%%：%s" % [wk, roundi(100.0 * caught / tot), got])
	return true
