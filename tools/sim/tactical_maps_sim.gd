extends "res://tools/sim/tactical_hunt_sim.gd"
# Phase 2c 第 4 步：每種地形的地圖族（open／edge／dense／stream／logs）× 鹿的體況 × 狼，
# 隨機的地圖、位置與風向（下風、側風、上風輪流），四種打法取最好的、交給本能，各 RUNS 場；看成功率、回合數、卡住。
# 用法：bash tools/run_sim.sh tactical_maps_sim 0 60

const FAMILIES := ["open", "edge", "dense", "stream", "logs"]
const WINDS := ["headwind", "crosswind", "tailwind"]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	var h = TH.new()
	var wolves := {"normal": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
		"fast": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100}}
	print("== 戰術地圖族（每格 %d 場；風向輪流）：最好的打法／交給本能，回合數中位數" % runs)
	var stuck := 0
	for fam in FAMILIES:
		for wk in ["normal", "fast"]:
			var line := "%-6s %-6s" % [fam, wk]
			for cond in ["healthy", "weak"]:
				var best := 0.0
				var rounds: Array = []
				for pol in ["chase", "pace", "stalk", "ambush", ""]:
					var ok := 0
					for i in runs:
						h.setup_from_game({"family": fam, "seed": i * 7919 + 17, "condition": cond, "wolf": wolves[wk], "wind_relation": WINDS[i % 3]})
						if pol == "":
							TacticalInstinct.play(h)
						else:
							_play(h, pol)
						if h.result == "caught":
							ok += 1
						stuck += int(h.stats["stuck"])
						if pol == "":
							rounds.append(h.rounds)
					if pol != "":
						best = max(best, float(ok) / runs)
					else:
						rounds.sort()
						line += "  %s 最好 %d%% 本能 %d%%（%d 回合）" % [cond, roundi(best * 100.0), roundi(100.0 * ok / runs), rounds[rounds.size() / 2]]
			print(line)
	print("鹿卡住 %d 次" % stuck)
	return true
