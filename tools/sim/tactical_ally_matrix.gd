extends "res://tools/sim/tactical_hunt_sim.gd"
# 苔原狼一起狩獵的對照表（2026-10-22，給使用者和 ChatGPT 討論難度用）：
#   狼（原型的慢／普通／快）× 獵物（白尾鹿、馬鹿、馴鹿、駝鹿）× 目標（成體 健康／普通／虛弱、幼體）× 單狼／有 2 隻苔原狼（驅趕＋追擊）
#   單狼取 chase、pace、stalk、ambush 最好的；有同伴取 stalk、chase、hold 最好的（都是「最好的打法」，真人通常打不到這麼好）。
#   成體：單隻、秋季；幼體：母親（普通）＋幼體、夏季，目標是幼體。每個地圖族 RUNS 場。
# 輸出 Markdown 表格。用法：bash tools/run_sim.sh tactical_ally_matrix；RUNS=40
const WINDS := ["headwind", "crosswind", "tailwind"]
const WOLVES := {
	"慢（速 40）": {"speed": 40, "skill": 45, "strength": 45, "perception": 45, "stamina": 80, "health": 100, "health_max": 100},
	"普通（速 60）": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
	"快（速 85）": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100},
}
const PREY := [
	["白尾鹿", "deer", ["open", "edge"]],
	["馬鹿（母）", "elk", ["open", "edge"]],
	["馴鹿", "caribou", ["tundra"]],
	["駝鹿", "moose", ["dense", "edge"]],
]
const TARGETS := [["成體・健康", "healthy", false], ["成體・普通", "average", false], ["成體・虛弱", "weak", false], ["幼體", "average", true]]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 40
	var h = TH.new()
	print("| 獵物 | 目標 | " + " | ".join(WOLVES.keys().map(func(k): return k + " 單狼 → 有同伴")) + " |")
	print("| --- | --- | " + " | ".join(WOLVES.keys().map(func(_k): return "---")) + " |")
	for p in PREY:
		for tg in TARGETS:
			var cells: Array = []
			for wk in WOLVES.keys():
				var res := []
				for setup in [[0, ["chase", "pace", "stalk", "ambush"]], [1, ["stalk", "chase", "hold"]]]:
					var best := 0.0
					for pol in setup[1]:
						var ok := 0
						var n := 0
						for fam in p[2]:
							for i in runs:
								var ctx := {"family": fam, "seed": i * 7919 + 17, "condition": tg[1], "wolf": (WOLVES[wk] as Dictionary).duplicate(),
									"wind_relation": WINDS[i % 3], "species": p[1], "season": "summer" if tg[2] else "autumn", "fawn": tg[2]}
								h.setup_from_game(ctx)
								if int(setup[0]) > 0:
									h.add_ally("drive", h.wolf_pos)
									h.add_ally("chase", h.wolf_pos)
								TacticalInstinct.pick_target(h)
								_play(h, pol)
								n += 1
								if h.result == "caught":
									ok += 1
						best = maxf(best, float(ok) / n)
					res.append(roundi(best * 100.0))
				cells.append("%d%% → %d%%" % [res[0], res[1]])
			print("| %s | %s | %s |" % [p[0], tg[0], " | ".join(cells)])
	return true
