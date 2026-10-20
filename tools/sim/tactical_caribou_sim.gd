extends "res://tools/sim/tactical_hunt_sim.gd"
# Phase 2d 第 4 步：馴鹿的校準。地圖族（tundra 苔原、river 河谷、edge 林線）分開列，鹿群 5～8 隻（馴鹿一律成群）與單隻，
# 狼（普通、快）× 體況（整群健康、整群虛弱），四種打法取最好的（哪一種）、交給本能，各 RUNS 場；
# 另外列：遠遠就被發現（狼還在 6 格外鹿就逃）的比例、逃跑時下過水的比例。白尾鹿在開闊地當對照。
# 目標：選單式馴鹿約和白尾鹿一樣；馴鹿在開闊地圖潛近明顯比白尾鹿難（SPEC Phase 2d）。
# 用法：bash tools/run_sim.sh tactical_caribou_sim 0 40
const WINDS := ["headwind", "crosswind", "tailwind"]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 40
	var h = TH.new()
	var wolves := {"normal": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
		"fast": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100}}
	print("== 馴鹿（每格 %d 場；風向輪流）：最好的打法（哪一種）／交給本能；遠遠被發現、下過水的比例（本能那一輪）" % runs)
	for row in [["白尾鹿", "deer", "open", 1], ["白尾鹿", "deer", "river", 1], ["馴鹿・單隻", "caribou", "tundra", 1], ["馴鹿・鹿群", "caribou", "tundra", 6], ["馴鹿・鹿群", "caribou", "river", 6], ["馴鹿・鹿群", "caribou", "edge", 6]]:
		for wk in ["normal", "fast"]:
			var line := "%-8s %-6s %-6s" % [row[0], row[2], wk]
			for cond in ["healthy", "weak"]:
				var by_pol := {}
				var inst := 0
				var far := 0
				var wet := 0
				for pol in ["chase", "pace", "stalk", "ambush", ""]:
					var ok := 0
					for i in runs:
						var ctx := {"family": row[2], "seed": i * 7919 + 17, "condition": cond, "wolf": wolves[wk], "wind_relation": WINDS[i % 3], "species": row[1]}
						if int(row[3]) > 1:
							var conds: Array = []
							for k in 5 + (i % 4):
								conds.append(cond)
							ctx["herd"] = {"conditions": conds, "calves": 0}
						h.setup_from_game(ctx)
						if pol == "":
							TacticalInstinct.pick_target(h)
							h.game_mods["instinct_penalty"] = float(h.t["game"]["instinct_penalty"])
							var ip: String = TacticalInstinct.pick_policy(h)
							var spotted := false
							var in_water := false
							var guard := 0
							while not h.done and guard < 60:
								guard += 1
								var was: String = h.deer_state
								TacticalInstinct.step(h, ip)
								if not spotted and was != "flee" and h.deer_state == "flee":
									spotted = true
									if h.dist(h.wolf_pos, h.deer_pos) > 6.0:
										far += 1
								if not h.done and h.deer_state == "flee" and h.terrain(h.deer_pos) == "w":
									in_water = true
							if in_water:
								wet += 1
						else:
							_play(h, pol)
						if h.result == "caught":
							ok += 1
					if pol == "":
						inst = ok
					else:
						by_pol[pol] = float(ok) / runs
				var best_pol: String = by_pol.keys()[0]
				for k in by_pol.keys():
					if float(by_pol[k]) > float(by_pol[best_pol]):
						best_pol = k
				line += "  %s 最好 %d%%（%s）本能 %d%% 遠遠被發現 %d%% 下水 %d%%" % [cond, roundi(100.0 * float(by_pol[best_pol])), best_pol, roundi(100.0 * inst / runs), roundi(100.0 * far / runs), roundi(100.0 * wet / runs)]
			print(line)
	return true
