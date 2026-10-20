extends "res://tools/sim/tactical_hunt_sim.gd"
# Phase 2d 第 2 步：馬鹿在哪一段失敗（撲咬命中、咬住後壓倒／咬喉／被甩開、被踢），單隻母馬鹿、普通的狼、交給本能。
# 用法：bash tools/run_sim.sh tactical_elk_stages 0 60；SPECIES=deer 看白尾鹿
const FAMILIES := ["open", "edge", "dense", "stream", "logs"]
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	var species: String = OS.get_environment("SPECIES") if OS.get_environment("SPECIES") != "" else "elk"
	var wolf := {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}
	for cond in ["healthy", "weak"]:
		var tally := {}
		for fam in FAMILIES:
			for i in runs:
				var h = TH.new()
				h.setup_from_game({"family": fam, "seed": i * 7919 + 17, "condition": cond, "wolf": wolf, "wind_relation": ["headwind", "crosswind", "tailwind"][i % 3], "species": species})
				var guard := 0
				TacticalInstinct.pick_target(h)
				h.game_mods["instinct_penalty"] = float(h.t["game"]["instinct_penalty"])
				var pol: String = TacticalInstinct.pick_policy(h)
				while not h.done and guard < 60:
					guard += 1
					var was_held: bool = h.held
					var e0: int = h.events.size()
					if was_held:
						var o: Dictionary = h.hold_options()
						for k in ["takedown", "throat"]:
							if o.has(k):
								tally["p_" + k] = float(tally.get("p_" + k, 0.0)) + float(o[k]["chance"])
						tally["hold_turns"] = int(tally.get("hold_turns", 0)) + 1
					TacticalInstinct.step(h, pol)
					if not was_held and h.held:
						tally["hit"] = int(tally.get("hit", 0)) + 1
					elif not was_held and h.events.slice(e0).any(func(e): return str(e).contains("撲空")):
						tally["miss"] = int(tally.get("miss", 0)) + 1
					if was_held and not h.held and not h.done:
						tally["broke"] = int(tally.get("broke", 0)) + 1
				tally[h.result] = int(tally.get(h.result, 0)) + 1
				tally["kicks"] = int(tally.get("kicks", 0)) + h.kicks
		var ht: int = max(1, int(tally.get("hold_turns", 0)))
		print("%s %s：%s；咬住時平均 壓倒 %.2f 咬喉 %.2f" % [species, cond, tally, float(tally.get("p_takedown", 0)) / ht, float(tally.get("p_throat", 0)) / ht])
	return true
