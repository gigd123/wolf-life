extends "res://tools/sim/tactical_hunt_sim.gd"
# 苔原狼的群體狩獵實驗（docs/proposals/tundra-joint-tactical.md）：同一場面比較
#   單狼（四種打法最好的、本能）／有同伴但照單狼的打法（stalk、chase）／有同伴、配合同伴（hold：潛近後等同伴趕過來）
# 同伴：ALLIES=drive,chase（預設一隻驅趕、一隻追擊）。一般的狼。
# 通過標準（初始值）：配合同伴明顯比照單狼打好（+15 個百分點以上）；照單狼打也比單狼好一點；
#   和 1～2 隻苔原狼：馴鹿群約 50～65%、健康的駝鹿 15～25%；一場的回合數不超過單狼的 1.5 倍。
# 用法：bash tools/run_sim.sh tactical_ally_sim；RUNS=60
const WINDS := ["headwind", "crosswind", "tailwind"]
const CASES := [
	["caribou", "tundra", 6, "average"],
	["white_tailed_deer", "open", 4, "average"],
	["elk", "edge", 4, "average"],
	["moose", "dense", 1, "healthy"],
	["moose", "dense", 1, "weak"],
]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	var roles: PackedStringArray = (OS.get_environment("ALLIES") if OS.get_environment("ALLIES") != "" else "drive,chase").split(",")
	var wolf := {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}
	var h = TH.new()
	var species_map := {"caribou": "caribou", "white_tailed_deer": "deer", "elk": "elk", "moose": "moose"}
	print("== 群體狩獵實驗（每格 %d 場，同伴 %s）：獵到的比例（平均回合）" % [runs, ",".join(roles)])
	for c in CASES:
		var line := "  %-18s %-7s" % ["%s×%d" % [c[0], c[2]], c[3]]
		for setup in [["單狼最好", 0, ""], ["單狼本能", 0, "instinct"], ["同伴+潛近", 1, "stalk"], ["同伴+猛追", 1, "chase"], ["同伴+等著趕", 1, "hold"]]:
			var best := 0.0
			var best_r := 0.0
			var best_st := {}
			var pols: Array = ["chase", "pace", "stalk", "ambush"] if setup[2] == "" else [setup[2]]
			for pol in pols:
				var ok := 0
				var rsum := 0
				var st := {}
				for i in runs:
					var conds: Array = []
					for k in int(c[2]):
						conds.append(c[3])
					var ctx := {"family": c[1], "seed": i * 7919 + 17, "condition": c[3], "wolf": wolf, "wind_relation": WINDS[i % 3], "species": species_map[c[0]], "season": "autumn"}
					if int(c[2]) > 1:
						ctx["herd"] = {"conditions": conds, "calves": 0}
					h.setup_from_game(ctx)
					if int(setup[1]) > 0:
						for r in roles:
							h.add_ally(r, h.wolf_pos)
					TacticalInstinct.pick_target(h)
					if pol == "instinct":
						h.game_mods["instinct_penalty"] = float(h.t["game"]["instinct_penalty"])
						_play(h, TacticalInstinct.pick_policy(h))
					else:
						_play(h, pol)
					if h.result == "caught":
						ok += 1
					rsum += int(h.rounds)
					for key in h.stats.keys():
						if key not in ["stuck", "toward_wolf"]:
							st[key] = int(st.get(key, 0)) + int(h.stats[key])
				var rate := float(ok) / runs
				if rate >= best:
					best = rate
					best_r = float(rsum) / runs
					best_st = st
			line += "  %s %d%%（%.1f）" % [setup[0], roundi(best * 100.0), best_r]
			if OS.get_environment("DETAIL") != "" and not best_st.is_empty():
				line += str(best_st)
		print(line)
	return true
