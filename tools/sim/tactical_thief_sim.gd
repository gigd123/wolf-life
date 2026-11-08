extends SceneTree
# Phase 2l 第 1 步：郊狼一對來偷殘骸的戰術戰鬥（主遊戲的接口；你交給本能）。
# 看：結果（牠們都走了／你撤出）、被偷走的段數、留下的段數、你受的傷、回合數；印一場的逐回合紀錄（郊狼怎麼引開、偷、跑）。
# 年齡：1 歲（次成年）、3 歲（成年）。殘骸：白尾鹿（4 段）、馬鹿（6 段）、雪兔（小、整隻叼走）。
# 用法：RUNS=200 bash tools/run_sim.sh tactical_thief_sim
var gs
var gt

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _wolf(age: float) -> void:
	gs.new_game("grassland_plains")
	gs.wolf.age_years = age
	var adult: bool = age >= 2.0
	gs.wolf.health_max = 110.0 if adult else 85.0
	gs.wolf.health = gs.wolf.health_max
	gs.wolf.speed = 62.0 if adult else 55.0
	gs.wolf.strength = 70.0 if adult else 50.0
	gs.wolf.skill = 60.0 if adult else 45.0
	gs.wolf.perception = 60.0 if adult else 50.0
	gs.wolf.hunger = 60.0

func _run() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 200
	var printed := false
	for age in [1.0, 3.0]:
		for animal in ["white_tailed_deer", "elk"]:
			var res := {"n": 0, "stolen": 0, "left": 0, "start": 0, "dmg": 0.0, "rounds": 0, "outcomes": {}, "stole_any": 0, "dropped": 0}
			for s in runs:
				_wolf(age)
				gs.start_feeding(animal, "adult", "open")
				# 吃了一段之後郊狼來了（進食中）
				gs.current_feeding["segments_left"] = int(gs.current_feeding["segments_left"]) - 1
				var c = gs.start_combat("coyote", "adult", "carcass")
				var hp0: float = gs.wolf.health
				var tc
				if not printed and s == 3:
					printed = true
					tc = _traced(c)
				else:
					tc = gs.auto_tactical_combat(c)
				res["n"] += 1
				res["start"] += int(c.get_meta("tc_start_carcass", 0))
				var st: int = tc.meat_stolen()
				res["stolen"] += st
				if st > 0:
					res["stole_any"] += 1
				res["left"] += int(c.get_meta("tc_left", 0))
				res["dmg"] += hp0 - gs.wolf.health
				res["rounds"] += tc.rounds
				res["outcomes"][tc.outcome] = int(res["outcomes"].get(tc.outcome, 0)) + 1
				gs.finish_combat(c)
			var n: float = float(res["n"])
			print("%s 歲、%s：開場 %.1f 段，被偷走 %.2f 段（有偷到的 %d%%），留下 %.2f 段；你受傷 %.1f；%.1f 回合；結果 %s" % [
				age, animal, res["start"] / n, res["stolen"] / n, int(100.0 * res["stole_any"] / n), res["left"] / n, res["dmg"] / n, res["rounds"] / n, str(res["outcomes"])])
	quit()

# 交給本能打完，逐回合印出每一隻的位置、表態與事件
func _traced(c):
	var tc = gs.start_tactical_combat(c)
	print("--- 一場的紀錄：殘骸在 %s（%d 段）" % [str(tc.carcass.get("pos")), int(tc.carcass.get("segments", 0))])
	var g := 0
	while not tc.done and g < 60:
		g += 1
		var it: Dictionary = tc.begin_round()
		if tc.done:
			break
		var line := "R%d" % tc.rounds
		for k in tc.units.size():
			var u: Dictionary = tc.units[k]
			if tc.active(k):
				line += "  %s@%s%s" % [u["id"], str(u["pos"]), ("[" + str(it[k]["action"]) + ":" + str(it[k]["why"]) + "]") if it.has(k) else ""]
		print(line)
		tc.plan(0, tc.auto_plan(0))
		var evs: Array = tc.resolve()
		var el := "     "
		for e in evs:
			if str(e["kind"]) in ["move", "turn", "wait", "blocked"]:
				continue
			el += str(e["kind"]) + "(" + str(tc.units[int(e.get("who", 0))]["id"]) + ") "
		print(el)
	gs.apply_tactical_combat(c, tc)
	print("  結果 %s、被偷走 %d 段、殘骸剩 %d 段、地上 %d 堆" % [tc.outcome, tc.meat_stolen(), int(tc.carcass.get("segments", 0)), tc.drops.size()])
	return tc
