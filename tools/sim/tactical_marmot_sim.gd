extends "res://tools/sim/tactical_hunt_sim.gd"
# Phase 2g 第 1 步：旱獺的校準（SPEC「Phase 2g」）。狼（未成年、一般、快）× 離洞近／遠 × 打法：
# dumb_sprint 直線衝過去、chase 猛追、stalk 潛近、ambush 伏擊、cutoff 截斷退路（繞到牠和洞口之間）、本能。
# 每格印三種成功率：遭遇（所有場次裡獵到的）、出手後（撲出去的場次裡獵到的）、平均回合、喘（體力）、被咬到的比例。
# 目標（一般的狼，本能）：離洞近約 25%、遠約 75%；未成年約四成；會選位置的打法（cutoff）要明顯比直衝好。
# 用法：bash tools/run_sim.sh tactical_marmot_sim；RUNS=60 SPECIES=marmot_young
const WINDS := ["headwind", "crosswind", "tailwind"]
const CONDS := ["healthy", "average", "average", "weak"]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	var species: String = OS.get_environment("SPECIES") if OS.get_environment("SPECIES") != "" else "marmot"
	var h = TH.new()
	var wolves := {"normal": {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
		"fast": {"speed": 85, "skill": 60, "strength": 60, "perception": 60, "stamina": 80, "health": 100, "health_max": 100},
		"young": {"speed": 48, "skill": 45, "strength": 52, "perception": 50, "stamina": 70, "health": 90, "health_max": 90}}
	print("== %s（每格 %d 場）：遭遇成功／出手後成功、回合、喘、被咬" % [species, runs])
	for wk in ["young", "normal", "fast"]:
		for near in [true, false]:
			var line := "%-6s %s" % [wk, "近洞" if near else "遠洞"]
			for pol in ["dumb_sprint", "chase", "stalk", "ambush", "cutoff", ""]:
				var ok := 0
				var pounced := 0
				var pounced_ok := 0
				var rounds := 0
				var breath := 0.0
				var bitten := 0
				for i in runs:
					var ctx := {"family": "talus", "seed": i * 7919 + 17, "condition": CONDS[i % CONDS.size()], "wolf": wolves[wk], "wind_relation": WINDS[i % 3], "species": species, "season": "summer", "water_near": near}
					h.setup_from_game(ctx)
					if pol == "":
						h.game_mods["instinct_penalty"] = float(h.t["game"]["instinct_penalty"])
						_play(h, TacticalInstinct.pick_policy(h))
					else:
						_play(h, pol)
					if h.result == "caught":
						ok += 1
					if h.pounced:
						pounced += 1
						if h.result == "caught":
							pounced_ok += 1
					rounds += int(h.rounds)
					breath += float(h.breath_used)
					if h.kicks > 0:
						bitten += 1
				line += "  %s %d%%/%d%% %.1f回 喘%.0f 咬%d%%" % [pol if pol != "" else "本能", roundi(100.0 * ok / runs), roundi(100.0 * pounced_ok / max(1, pounced)), float(rounds) / runs, breath / runs, roundi(100.0 * bitten / runs)]
			print(line)
	return true
