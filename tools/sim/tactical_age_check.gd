extends SceneTree
# Phase 2c 第 5 步：年齡減成在戰術狩獵裡要扣在哪裡（撲咬＋壓倒＋咬喉 vs 只扣撲咬）。
# 一般成年的狼（能力 60）與老狼（7.5 歲：減成 0.15，速度、力量 −5），各地圖族、體況照 Phase 2b 的比例，交給本能。
# 用法：bash tools/run_sim.sh tactical_age_check 0 60
var f := 0
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var adult := {"speed": 62, "skill": 58, "strength": 62, "perception": 58, "stamina": 80, "health": 105, "health_max": 105}
	var elder := {"speed": 57, "skill": 60, "strength": 57, "perception": 58, "stamina": 80, "health": 100, "health_max": 100}
	var conds := ["healthy", "healthy", "healthy", "healthy", "average", "average", "average", "weak", "weak", "weak"]
	for row in [["成年", adult, 0.0, "all"], ["老年（全扣）", elder, 0.15, "all"], ["老年（只扣撲咬）", elder, 0.15, "pounce"]]:
		var ok := 0
		var n := 0
		for fam in ["open", "edge", "dense", "stream", "logs"]:
			for i in runs:
				var h = TH.new()
				h.setup_from_game({"family": fam, "seed": i * 7919 + 3, "condition": conds[i % conds.size()], "wolf": row[1], "age_penalty": row[2], "wind_relation": ["headwind", "crosswind", "tailwind"][i % 3]})
				h.game_mods["age_scope"] = row[3]
				TacticalInstinct.play(h)
				n += 1
				if h.result == "caught":
					ok += 1
		print("%s：獵到 %d%%（%d 場）" % [row[0], roundi(100.0 * ok / n), n])
	return true
