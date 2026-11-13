extends SceneTree
# Phase 2n 第 2 步：避難處有沒有用。同一批地圖、種子，比較：
#   有深水的地圖（pond_*）：stay 原地不動、water 躲進深水等火過去、smart 本能
#   有巢穴的地圖（den）：stay、den 鑽進巢穴（濃煙灌進來才衝出去）、smart
# 印死亡、重傷（≥ 25）、平均傷、濃煙灌進巢穴的比例。
# 用法：RUNS=10 bash tools/run_sim.sh fire_refuge_sim（WARNING=late 很晚才察覺）
const HEAVY := 25.0
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 10
	var warn: String = OS.get_environment("WARNING") if OS.get_environment("WARNING") != "" else "normal"
	var FE = load("res://scripts/core/FireEscape.gd")
	var FI = load("res://scripts/core/FireInstinct.gd")
	var winds := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	for setup in [{"name": "有深水的地圖", "maps": ["pond_1", "pond_2", "pond_3"], "den": false, "pols": ["stay", "water", "smart"]},
			{"name": "有巢穴的地圖", "maps": ["edge_1", "dense_1", "logs_1"], "den": true, "pols": ["stay", "den", "smart"]}]:
		for st in 3:
			var line := "%s %s：" % [setup["name"], ["微風", "中風", "強風"][st]]
			for pol in setup["pols"]:
				var r := {"n": 0, "dead": 0, "heavy": 0, "dmg": 0.0, "den_smoke": 0}
				for mi in (setup["maps"] as Array).size():
					for s in runs:
						var fe = FE.new()
						fe.setup({"hunt_map": setup["maps"][mi], "seed": s * 97 + mi * 13 + 1, "wind": winds[(s + mi) % 4], "strength": st,
							"warning": warn, "den": setup["den"], "ash_patch": false, "wolf": {"perception": 55, "health": 100, "health_max": 100}})
						FI.play(fe, pol)
						r["n"] += 1
						if fe.result == "dead":
							r["dead"] += 1
						elif fe.total_damage() >= HEAVY:
							r["heavy"] += 1
						r["dmg"] += fe.total_damage()
						if fe.den_smoke:
							r["den_smoke"] += 1
				var n: float = float(r["n"])
				line += " %s 死 %d%% 重傷 %d%% 傷 %.0f%s；" % [pol, roundi(100.0 * r["dead"] / n), roundi(100.0 * r["heavy"] / n), r["dmg"] / n,
					("（濃煙灌進 %d%%）" % roundi(100.0 * r["den_smoke"] / n)) if pol == "den" else ""]
			print(line)
	return true
