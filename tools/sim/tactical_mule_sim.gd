extends "res://tools/sim/tactical_hunt_sim.gd"
# Phase 2d 第 3 步：騾鹿的校準。地圖族（open = 高山草甸、slope = 岩坡、edge = 山腳林緣）分開列，
# 狼（普通、快）× 體況（健康、虛弱），四種打法取最好的（哪一種）、交給本能，各 RUNS 場；另外列逃上岩坡的比例。白尾鹿同條件當對照。
# 目標：選單式騾鹿約白尾鹿的 0.9 倍；騾鹿在草甸明顯比岩坡好抓（SPEC Phase 2d）。
# 用法：bash tools/run_sim.sh tactical_mule_sim 0 40
const WINDS := ["headwind", "crosswind", "tailwind"]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 40
	var h = TH.new()
	var wolves := {"normal": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
		"fast": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100}}
	print("== 騾鹿（每格 %d 場；風向輪流）：最好的打法（哪一種）／交給本能；逃跑時上過岩坡的場次" % runs)
	for row in [["白尾鹿", "deer", "open"], ["白尾鹿", "deer", "slope"], ["騾鹿", "mule_deer", "open"], ["騾鹿", "mule_deer", "slope"], ["騾鹿", "mule_deer", "edge"]]:
		for wk in ["normal", "fast"]:
			var line := "%-4s %-6s %-6s" % [row[0], row[2], wk]
			for cond in ["healthy", "weak"]:
				var by_pol := {}
				var inst := 0
				var rock := 0
				for pol in ["chase", "pace", "stalk", "ambush", ""]:
					var ok := 0
					for i in runs:
						h.setup_from_game({"family": row[2], "seed": i * 7919 + 17, "condition": cond, "wolf": wolves[wk], "wind_relation": WINDS[i % 3], "species": row[1]})
						var on_rock := false
						var guard := 0
						if pol == "":
							TacticalInstinct.pick_target(h)
							h.game_mods["instinct_penalty"] = float(h.t["game"]["instinct_penalty"])
							var ip: String = TacticalInstinct.pick_policy(h)
							while not h.done and guard < 60:
								guard += 1
								TacticalInstinct.step(h, ip)
								if not h.done and h.deer_state == "flee" and h.terrain(h.deer_pos) == "r":
									on_rock = true
						else:
							_play(h, pol)
						if h.result == "caught":
							ok += 1
						if on_rock:
							rock += 1
					if pol == "":
						inst = ok
					else:
						by_pol[pol] = float(ok) / runs
				var best_pol: String = by_pol.keys()[0]
				for k in by_pol.keys():
					if float(by_pol[k]) > float(by_pol[best_pol]):
						best_pol = k
				line += "  %s 最好 %d%%（%s）本能 %d%% 上岩坡 %d%%" % [cond, roundi(100.0 * float(by_pol[best_pol])), best_pol, roundi(100.0 * inst / runs), roundi(100.0 * rock / runs)]
			print(line)
	return true
