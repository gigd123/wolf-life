extends SceneTree
# Phase 2c 第 5 步「一場不超過 1～2 分鐘」的估算（2026-10-20）：玩家每做一個動作（移動、撲咬、咬住後的招式、觀察）算一次，
# 用本能的打法（潛近截角、耐力追）代替玩家，數一場要做幾次，分成潛近（鹿還沒逃）、追逐（鹿在逃）、咬住三段。
# 時間的估算：潛近每步 SEC_STALK 秒（要看警覺、風、掩蔽）、追逐每步 SEC_CHASE 秒、咬住每步 SEC_HOLD 秒，再加開場看地圖 SEC_OPEN 秒。
# 這只是粗估，實際以試玩為準。成年的狼（3 歲平均能力值），各地圖族、體況照 Phase 2b 的比例。
# 用法：bash tools/run_sim.sh tactical_action_count 0 60
const SEC_OPEN := 10.0
const SEC_STALK := 6.0
const SEC_CHASE := 4.0
const SEC_HOLD := 4.0
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var wolf := {"speed": 66, "skill": 71, "strength": 77, "perception": 62, "stamina": 80, "health": 110, "health_max": 110}
	var conds := ["healthy", "healthy", "healthy", "healthy", "average", "average", "average", "weak", "weak", "weak"]
	print("== 一場要做幾個動作（每地圖族 %d 場；成年的狼、交給本能的打法，開場先觀察一次）" % runs)
	var all_secs: Array = []
	for fam in ["open", "edge", "dense", "stream", "logs"]:
		var totals: Array = []
		var secs: Array = []
		var phase := {"stalk": 0, "chase": 0, "hold": 0}
		var results := {}
		for i in runs:
			var h = TH.new()
			h.setup_from_game({"family": fam, "seed": i * 7919 + 3, "condition": conds[i % conds.size()], "wolf": wolf,
				"wind_relation": ["headwind", "crosswind", "tailwind"][i % 3], "fawn": i % 7 == 0})
			var pol: String = TacticalInstinct.pick_policy(h)
			var n := {"stalk": 1, "chase": 0, "hold": 0} # 開場觀察一次
			h.observe()
			var guard := 0
			while not h.done and guard < 60:
				guard += 1
				var k: String = "hold" if h.held else ("chase" if h.deer_state == "flee" else "stalk")
				n[k] += 1
				TacticalInstinct.step(h, pol)
			var tot: int = n["stalk"] + n["chase"] + n["hold"]
			totals.append(tot)
			var s: float = SEC_OPEN + n["stalk"] * SEC_STALK + n["chase"] * SEC_CHASE + n["hold"] * SEC_HOLD
			secs.append(s)
			all_secs.append(s)
			for k in phase.keys():
				phase[k] += n[k]
			results[h.result] = int(results.get(h.result, 0)) + 1
		totals.sort()
		secs.sort()
		print("  %-7s 動作 中位數 %d（%d～%d）；平均 潛近 %.1f、追逐 %.1f、咬住 %.1f；估計時間 中位數 %.0f 秒、九成在 %.0f 秒內；%s" % [fam,
			totals[totals.size() / 2], totals[0], totals.back(), float(phase["stalk"]) / runs, float(phase["chase"]) / runs, float(phase["hold"]) / runs,
			secs[secs.size() / 2], secs[int(secs.size() * 0.9)], results])
	all_secs.sort()
	var over := all_secs.filter(func(s): return s > 120.0).size()
	print("  全部：估計時間 中位數 %.0f 秒、九成在 %.0f 秒內、超過 2 分鐘 %d%%" % [all_secs[all_secs.size() / 2], all_secs[int(all_secs.size() * 0.9)], roundi(100.0 * over / all_secs.size())])
	return true
