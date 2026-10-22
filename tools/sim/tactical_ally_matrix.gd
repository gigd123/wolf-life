extends "res://tools/sim/tactical_hunt_sim.gd"
# 苔原狼一起狩獵的對照表（2026-10-22，給使用者和 ChatGPT 討論難度用）：
#   狼（原型的慢／普通／快）× 獵物（白尾鹿、馬鹿、馴鹿、駝鹿）× 目標（成體 健康／普通／虛弱、幼體）× 單狼／有 2 隻苔原狼（驅趕＋追擊）
#   單狼取 chase、pace、stalk、ambush 最好的；有同伴取 stalk、chase、hold 最好的（都是「最好的打法」，真人通常打不到這麼好）。
#   成體：單隻（成群的動物也是單隻，看不出「挑最弱的」）、秋季；幼體：夏季，見 PREY 的第 4 欄。每個地圖族 RUNS 場。
# 輸出 Markdown 表格。用法：bash tools/run_sim.sh tactical_ally_matrix；RUNS=40；PART=0～3 PARTS=4 分成幾份平行跑（每份跑第 PART、PART+PARTS… 隻獵物）
const WINDS := ["headwind", "crosswind", "tailwind"]
const WOLVES := {
	"慢（速 40）": {"speed": 40, "skill": 45, "strength": 45, "perception": 45, "stamina": 80, "health": 100, "health_max": 100},
	"普通（速 60）": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
	"快（速 85）": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100},
}
# [名稱, 物種, 地圖族, 幼體的寫法]：幼體 "fawn" 母親（普通）＋幼體；"herd" 整群 8 隻（普通）＋2 隻小牛；物種名 落單的幼體；"" 沒有幼體
const PREY := [
	["白尾鹿", "deer", ["open", "edge"], "fawn"],
	["騾鹿", "mule_deer", ["slope", "edge"], "fawn"],
	["馬鹿（母）", "elk", ["open", "edge"], "fawn"],
	["公馬鹿", "elk_bull", ["open", "edge"], ""],
	["馴鹿", "caribou", ["tundra"], "fawn"],
	["駝鹿", "moose", ["dense", "edge"], "fawn"],
	["野牛", "bison", ["open", "river"], "herd"],
	["叉角羚", "pronghorn", ["open"], "pronghorn_kid"],
	["大角羊（母）", "bighorn_sheep", ["cliff"], "fawn"],
	["大角羊（公）", "bighorn_ram", ["cliff"], ""],
]
const TARGETS := [["成體・健康", "healthy"], ["成體・普通", "average"], ["成體・虛弱", "weak"], ["幼體", "juvenile"]]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 40
	var h = TH.new()
	var part: int = int(OS.get_environment("PART")) if OS.get_environment("PART") != "" else 0
	var parts: int = int(OS.get_environment("PARTS")) if OS.get_environment("PARTS") != "" else 1
	if part == 0:
		print("| 獵物 | 目標 | " + " | ".join(WOLVES.keys().map(func(k): return k + " 單狼 → 有同伴")) + " |")
		print("| --- | --- | " + " | ".join(WOLVES.keys().map(func(_k): return "---")) + " |")
	for pi in PREY.size():
		if pi % parts != part:
			continue
		var p: Array = PREY[pi]
		for tg in TARGETS:
			var juv: bool = tg[1] == "juvenile"
			if juv and str(p[3]) == "":
				continue
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
								var ctx := {"family": fam, "seed": i * 7919 + 17, "condition": "average" if juv else tg[1], "wolf": (WOLVES[wk] as Dictionary).duplicate(),
									"wind_relation": WINDS[i % 3], "species": p[1], "season": "summer" if juv else "autumn"}
								if juv:
									match str(p[3]):
										"fawn":
											ctx["fawn"] = true
										"herd":
											ctx["herd"] = {"conditions": ["average", "average", "average", "average", "average", "average", "average", "average"], "calves": 2}
										_:
											ctx["species"] = str(p[3])
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
	print("END PART %d" % part)
	return true
