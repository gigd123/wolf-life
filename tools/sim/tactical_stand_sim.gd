extends "res://tools/sim/tactical_hunt_sim.gd"
# Phase 2f：會站定的大型獵物的校準（SPEC「Phase 2f」）。物種（SPECIES，預設 elk_bull）單隻與小群，地圖族（FAMILIES），
# 狼（普通、快）× 體況（健康、虛弱），四種打法取最好的、交給本能；另外列：目標站定過的比例、站定過的獵到幾成、
# 牠不理你走開（放棄）的比例、被衝撞或踢的場次。季節固定春季（秋季公馬鹿站定 ×0.5）。
# 目標：對齊選單式 hunt_levels（公馬鹿：健康 一般成年約 22%、虛弱約 64%）；健康站定的單狼成功率個位數。
# WATER_NEAR=1／0：河狸離水近／遠（2026-10-22）。WOUNDS=n：目標帶著 n 道傷出場（受傷的個體，2026-10-22）。
# 用法：bash tools/run_sim.sh tactical_stand_sim 0 40；SPECIES=moose FAMILIES=dense,edge,stream,logs
const WINDS := ["headwind", "crosswind", "tailwind"]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 40
	var species: String = OS.get_environment("SPECIES") if OS.get_environment("SPECIES") != "" else "elk_bull"
	var fams: PackedStringArray = (OS.get_environment("FAMILIES") if OS.get_environment("FAMILIES") != "" else "open,edge,dense,stream,logs").split(",")
	var herd_n: int = int(OS.get_environment("HERD")) if OS.get_environment("HERD") != "" else 3
	var h = TH.new()
	var wolves := {"normal": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
		"fast": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100}}
	print("== %s（每格 %d 場 × %d 個地圖族）：最好的打法（哪一種）／交給本能；本能那一輪：站定過、站定過獵到、放棄（含牠走開）、被撞或踢" % [species, runs, fams.size()])
	for n_deer in [1, herd_n]:
		for wk in ["normal", "fast"]:
			var line := "%-4s %-6s" % ["單隻" if n_deer == 1 else "%d 隻" % n_deer, wk]
			for cond in ["healthy", "weak"]:
				var by_pol := {}
				var inst := 0
				var stood := 0
				var stood_caught := 0
				var ignored := 0
				var hurt := 0
				var dmg := 0.0
				var rounds_sum := 0
				var n := 0
				for pol in ["chase", "pace", "stalk", "ambush", ""]:
					var ok := 0
					for fam in fams:
						for i in runs:
							var ctx := {"family": fam, "seed": i * 7919 + 17, "condition": cond, "wolf": wolves[wk], "wind_relation": WINDS[i % 3], "species": species, "season": "spring",
									"wounds": int(OS.get_environment("WOUNDS")) if OS.get_environment("WOUNDS") != "" else 0}
							if OS.get_environment("WATER_NEAR") != "":
								ctx["water_near"] = OS.get_environment("WATER_NEAR") == "1"
							if n_deer > 1:
								var conds: Array = []
								for k in n_deer:
									conds.append(cond)
								ctx["herd"] = {"conditions": conds, "calves": 0}
							h.setup_from_game(ctx)
							var did_stand := false
							if pol == "":
								TacticalInstinct.pick_target(h)
								h.game_mods["instinct_penalty"] = float(h.t["game"]["instinct_penalty"])
								var ip: String = TacticalInstinct.pick_policy(h)
								var guard := 0
								while not h.done and guard < 60:
									guard += 1
									TacticalInstinct.step(h, ip)
									if str(h.herd[h.target]["state"]) == "stand":
										did_stand = true
								n += 1
								rounds_sum += int(h.rounds)
								if did_stand:
									stood += 1
									if h.result == "caught":
										stood_caught += 1
								if h.result == "gave_up":
									ignored += 1
								if h.kicks > 0:
									hurt += 1
									dmg += float(h.damage_taken)
							else:
								_play(h, pol)
							if h.result == "caught":
								ok += 1
					if pol == "":
						inst = ok
					else:
						by_pol[pol] = float(ok) / (runs * fams.size())
				var best_pol: String = by_pol.keys()[0]
				for k in by_pol.keys():
					if float(by_pol[k]) > float(by_pol[best_pol]):
						best_pol = k
				line += "  %s 最好 %d%%（%s）本能 %d%%｜站定 %d%%、站定獵到 %d%%、放棄 %d%%、受傷 %d%%（平均 %.0f）、%.1f 回合" % [cond, roundi(100.0 * float(by_pol[best_pol])), best_pol,
					roundi(100.0 * inst / max(1, n)), roundi(100.0 * stood / max(1, n)), roundi(100.0 * stood_caught / max(1, stood)), roundi(100.0 * ignored / max(1, n)), roundi(100.0 * hurt / max(1, n)), dmg / max(1, hurt), float(rounds_sum) / max(1, n)]
			print(line)
	return true
