extends SceneTree
# Phase 2c 第 5 步：次成年 1～2 歲在戰術狩獵裡太弱（使用者：未滿 1 歲弱可以接受，1～2 歲不應該太弱）。
# 用 life_pressure 量到的各年齡平均能力值，各地圖族、體況照 Phase 2b 的比例，交給本能。
# 「成長前移」：假設 2 歲就長到現在 3 歲的能力值。
# 變體：youth = 次成年加成（game_mods.youth_bonus，1 歲 +y、2 歲 0；目前程式沒有這一項，只留給比較用）；
#   flat = 能力差距 ÷k（撲咬、壓倒、咬喉、扯後腿的除數 ×k，以 3 歲的狼為基準補回基礎值）。
# 2026-10-20 結果：現況 1.0／1.5／2.0／3.0／5.0 歲 = 21／38／44／54／65%；次成年 +0.12 遞減 → 1.5 歲 44%；
#   +0.20 → 1.5 歲 53%（比 2 歲強）；能力差距 ÷2 → 1.5 歲 42%（差距多半來自速度、喘）；成長前移 → 1.5 歲 49%、2 歲 54%。
# 用法：bash tools/run_sim.sh tactical_youth_check 0 60
var f := 0
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var ages := {
		"1.0 歲": {"speed": 49, "skill": 45, "strength": 53, "perception": 50, "stamina": 80, "health": 92, "health_max": 92},
		"1.5 歲": {"speed": 53, "skill": 52, "strength": 58, "perception": 54, "stamina": 80, "health": 96, "health_max": 96},
		"2.0 歲": {"speed": 59, "skill": 59, "strength": 67, "perception": 58, "stamina": 80, "health": 103, "health_max": 103},
		"1.5 成長前移": {"speed": 61, "skill": 63, "strength": 70, "perception": 56, "stamina": 80, "health": 103, "health_max": 103},
		"2.0 成長前移": {"speed": 66, "skill": 71, "strength": 77, "perception": 60, "stamina": 80, "health": 110, "health_max": 110},
		"3.0 歲": {"speed": 66, "skill": 71, "strength": 77, "perception": 62, "stamina": 80, "health": 110, "health_max": 110},
		"5.0 歲": {"speed": 70, "skill": 82, "strength": 85, "perception": 66, "stamina": 80, "health": 110, "health_max": 110},
	}
	var conds := ["healthy", "healthy", "healthy", "healthy", "average", "average", "average", "weak", "weak", "weak"]
	# 變體：youth = 次成年加成（1 歲 +y、2 歲 0，中間線性）；flat = 能力差距 ÷k（撲咬、壓倒、咬喉、扯後腿的除數 ×k，以 3 歲的狼為基準補回基礎值）
	var variants := [["現況", 0.0, 1.0]]
	for v in variants:
		var line: String = "%-12s" % v[0]
		for age in ages.keys():
			var ok := 0
			var n := 0
			var hit := 0
			for fam in ["open", "edge", "dense", "stream", "logs"]:
				for i in runs:
					var h = TH.new()
					h.setup_from_game({"family": fam, "seed": i * 7919 + 3, "condition": conds[i % conds.size()], "wolf": ages[age], "wind_relation": ["headwind", "crosswind", "tailwind"][i % 3]})
					var yrs: float = 9.0 if age.contains("成長前移") else float(age.split(" ")[0])
					if yrs < 2.0 and v[1] > 0.0:
						h.game_mods["youth_bonus"] = v[1] * (2.0 - yrs)
					if v[2] != 1.0:
						_flatten(h, v[2])
					TacticalInstinct.play(h)
					n += 1
					if h.result == "caught":
						ok += 1
			line += "  %s %d%%" % [age, roundi(100.0 * ok / n)]
		print(line)
	return true

func _flatten(h, k: float) -> void:
	h.t = h.t.duplicate(true)
	var ref := {"speed": 66.0, "skill": 71.0, "strength": 77.0}
	var p: Dictionary = h.t["pounce"]
	var d: float = float(p["ability_divisor"])
	var term: float = (ref["speed"] + ref["skill"]) * 0.5 - float(h.t["deer"]["speed"])
	p["base"] = float(p["base"]) + term / d - term / (d * k)
	p["ability_divisor"] = d * k
	var hd: Dictionary = h.t["hold"]
	d = float(hd["divisor"])
	hd["takedown_base"] = float(hd["takedown_base"]) + (ref["strength"] - 50.0) / d - (ref["strength"] - 50.0) / (d * k)
	hd["throat_base"] = float(hd["throat_base"]) + (ref["skill"] - 50.0) / d - (ref["skill"] - 50.0) / (d * k)
	hd["divisor"] = d * k
	var hm: Dictionary = hd["hamstring"]
	d = float(hm["divisor"])
	hm["base"] = float(hm["base"]) + (ref["strength"] - 50.0) / d - (ref["strength"] - 50.0) / (d * k)
	hm["divisor"] = d * k
