extends SceneTree
# Phase 2n 第 1 步：火場原型的模擬。
# 每種風力 × 幾張地圖 × RUNS 個種子，每種打法（smart 本能、downwind 往下風、nearest 最近的邊、stay 不動、water 躲最近的水）玩到底：
# 結果（逃出去、等火燒過去、死亡、時間到）、平均受的傷、重傷（≥ HEAVY）、輕傷（≥ LIGHT）的比例。
# 路線：每一張地圖照每個目標（三個不是上風的邊、深水）各走一次（smart 的找路），算「走得通」（逃出去或等到火過去，傷 < HEAVY）的有幾條；
# 再看各種風力下「傷最少的目標」是哪一種（上風側邊、下風、水……），看強風是不是真的改變最好的逃法。
# 用法：RUNS=20 bash tools/run_sim.sh fire_escape_sim（WARNING=early／normal／late；MAPS=edge_1,river_1；POLICIES=smart；NO_ROUTES=1 不算路線）
const HEAVY := 25.0
const LIGHT := 8.0
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 20
	var FE = load("res://scripts/core/FireEscape.gd")
	var FI = load("res://scripts/core/FireInstinct.gd")
	var maps: Array = ["edge_1", "edge_2", "dense_1", "dense_2", "logs_1", "river_1", "pond_1", "stream_1"]
	if OS.get_environment("MAPS") != "":
		maps = OS.get_environment("MAPS").split(",")
	var winds := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	var warn: String = OS.get_environment("WARNING") if OS.get_environment("WARNING") != "" else "normal" # early／normal／late
	for st in 3:
		print("== 風力 %s" % ["微風", "中風", "強風"][st])
		for pol in (OS.get_environment("POLICIES").split(",") if OS.get_environment("POLICIES") != "" else FI.POLICIES):
			var r := {"n": 0, "escaped": 0, "survived": 0, "dead": 0, "timeout": 0, "into_fire": 0, "dmg": 0.0, "heavy": 0, "light": 0, "rounds": 0, "how": {}, "down": 0}
			for mi in maps.size():
				for s in runs:
					var fe = FE.new()
					fe.setup({"hunt_map": maps[mi], "seed": s * 131 + mi * 17 + 5, "wind": winds[(s + mi) % 4], "strength": st, "warning": warn,
						"wolf": {"perception": 55, "health": 100, "health_max": 100}})
					FI.play(fe, pol)
					r["n"] += 1
					r[fe.result] = int(r.get(fe.result, 0)) + 1
					var td: float = fe.total_damage()
					r["dmg"] += td
					r["rounds"] += fe.rounds
					var oc: String = fe.outcome()
					if oc == "heavy":
						r["heavy"] += 1
					elif oc == "light":
						r["light"] += 1
					var sm: Dictionary = fe.summary()
					r["how"][sm["how"]] = int(r["how"].get(sm["how"], 0)) + 1
					if bool(sm["downwind"]):
						r["down"] += 1
			var n: float = float(r["n"])
			print("  %-9s 逃出 %3d%%、等火過去 %3d%%、死亡 %3d%%、時間到 %d%%；重傷 %3d%%、輕傷 %3d%%；平均傷 %.1f、%.1f 回合" % [pol,
				roundi(100.0 * r["escaped"] / n), roundi(100.0 * r["survived"] / n), roundi(100.0 * r["dead"] / n), roundi(100.0 * r["timeout"] / n),
				roundi(100.0 * r["heavy"] / n), roundi(100.0 * r["light"] / n), r["dmg"] / n, r["rounds"] / n])
			if pol == "smart":
				print("            本能怎麼逃的：%s；往下風逃 %d%%" % [str(r["how"]), roundi(100.0 * r["down"] / n)])
		# 路線：每張地圖有幾條走得通；傷最少的是哪一種目標
		if OS.get_environment("NO_ROUTES") != "":
			continue
		var viable_counts := {}
		var best_kind := {}
		var total := 0
		for mi in maps.size():
			for s in mini(runs, 10):
				total += 1
				var ok := 0
				var best := ""
				var bd := 1e9
				var w: Vector2 = winds[(s + mi) % 4]
				var probe = FE.new()
				probe.setup({"hunt_map": maps[mi], "seed": s * 131 + mi * 17 + 5, "wind": w, "strength": st, "warning": warn})
				var up: String = probe.upwind_side()
				var down: String = probe.downwind_side()
				for g in ["n", "e", "s", "w", "water"]:
					if g == up:
						continue
					var fe2 = FE.new()
					fe2.setup({"hunt_map": maps[mi], "seed": s * 131 + mi * 17 + 5, "wind": w, "strength": st, "warning": warn,
						"wolf": {"perception": 55, "health": 100, "health_max": 100}})
					if g == "water" and FI.goals(fe2, "goal:water").is_empty():
						continue
					FI.play(fe2, "goal:" + g)
					var td2: float = fe2.total_damage()
					if fe2.result in ["escaped", "survived"] and td2 < HEAVY:
						ok += 1
					if fe2.result in ["escaped", "survived"] and td2 < bd:
						bd = td2
						best = "下風" if g == down else ("水" if g == "water" else "側邊")
				viable_counts[ok] = int(viable_counts.get(ok, 0)) + 1
				best_kind[best] = int(best_kind.get(best, 0)) + 1
		print("  走得通的路線數（地圖數）：%s；傷最少的目標：%s（共 %d 張）" % [str(viable_counts), str(best_kind), total])
	return true
