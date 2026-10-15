extends SceneTree
# 灰熊單挑（2026-10-15 調黑狼與次成年成長時用）：給定能力的狼和灰熊（遭遇、搶食）各打 RUNS 場，一直撲咬、瀕危就撤退。STATS="力量,技巧,速度,血量;..."
# 用法：STATS="70,65,62,105;80,75,65,112" bash tools/run_sim.sh grizzly_duel 0 400
var f := 0
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var GS = root.get_node("GameState")
	var CombatScript = load("res://scripts/core/Combat.gd")
	var FR = load("res://scripts/core/FightRules.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 400
	for spec in OS.get_environment("STATS").split(";"):
		var v: PackedStringArray = spec.split(",")
		var line := "力量 %s 技巧 %s 速度 %s 血量 %s：" % [v[0], v[1], v[2], v[3]]
		for ctx in ["encounter", "carcass"]:
			var wins := 0
			for r in runs:
				GS.new_game("forest_east")
				GS.debug_force_transition("adult")
				var w = GS.wolf
				w.strength = float(v[0]); w.skill = float(v[1]); w.speed = float(v[2]); w.health_max = float(v[3]); w.health = w.health_max
				var c = CombatScript.new(w, "grizzly_bear", "adult", ctx, false)
				var g := 0
				while c.phase != 2 and g < 40:
					g += 1
					var ids: Array = c.options().map(func(o): return o["id"])
					var pick := "bite"
					if c.phase == 0:
						pick = "attack"
					elif FR.in_danger(w):
						pick = "retreat"
					c.choose(pick)
				if c.outcome in ["drove_off", "killed"]:
					wins += 1
			line += "  %s 贏 %d%%" % [ctx, roundi(100.0 * wins / runs)]
		print(line)
	return true
