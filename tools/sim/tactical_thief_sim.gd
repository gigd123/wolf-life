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
	_wolverine(runs)
	quit()

# 第 2 步：狼獾來搶殘骸（苔原；你在吃、牠在旁邊等著 waiting）。交給本能打完，和「讓牠一起吃」比較
func _wolverine(runs: int) -> void:
	for age in [1.0, 3.0]:
		for returning in [false, true]:
			var res := {"n": 0, "left": 0, "start": 0, "dmg": 0.0, "rounds": 0, "outcomes": {}, "died": 0, "knocked": 0, "heavy": 0}
			for s in runs:
				_wolf(age)
				gs.new_game("tundra_central")
				_wolf_stats(age)
				gs.start_feeding("caribou", "adult", "open_tundra")
				gs.current_feeding["segments_left"] = int(gs.current_feeding["segments_left"]) - 1
				var c = gs.start_wolverine_combat(not returning)
				var hp0: float = gs.wolf.health
				var tc
				if s == 0 and age == 3.0 and not returning and OS.get_environment("TRACE") != "":
					tc = _traced(c)
				else:
					tc = gs.auto_tactical_combat(c)
				res["n"] += 1
				res["start"] += int(c.get_meta("tc_start_carcass", 0))
				res["dmg"] += hp0 - gs.wolf.health
				res["rounds"] += tc.rounds
				if tc.outcome == "died" or not gs.wolf.alive:
					res["died"] += 1
				if tc.outcome == "knocked":
					res["knocked"] += 1
				if gs.wolf.health < gs.wolf.health_max * 0.3:
					res["heavy"] += 1
				res["outcomes"][c.outcome] = int(res["outcomes"].get(c.outcome, 0)) + 1
				var h0: float = gs.wolf.hunger
				gs.finish_combat(c)
				# 打完還留給你的：殘骸剩下的段數＋撤出時帶走吃下去的
				res["left"] += (int(gs.current_feeding.get("segments_left", 0)) if not gs.current_feeding.is_empty() else 0) + int(c.get_meta("tc_meat", 0))
			var n: float = float(res["n"])
			print("狼獾 %s 歲、%s：開場 %.1f 段，打完還是你的 %.2f 段；你受傷 %.1f（重傷 %d%%、被打倒 %d、死 %d）；%.1f 回合；結果 %s" % [
				age, "回到殘骸時牠在吃" if returning else "你在吃時牠來了", res["start"] / n, res["left"] / n, res["dmg"] / n,
				int(100.0 * res["heavy"] / n), res["knocked"], res["died"], res["rounds"] / n, str(res["outcomes"])])
	# 對照：選單式（強攻型的自動玩家硬打；其他打法都直接分享）
	for age2 in [1.0, 3.0]:
		var r2 := {"n": 0, "dmg": 0.0, "out": {}}
		var ap = load("res://scripts/core/AutoPlayer.gd").new("all", "assault")
		gs.tactical_combat_off = true
		for s2 in runs:
			gs.new_game("tundra_central")
			_wolf_stats(age2)
			gs.start_feeding("caribou", "adult", "open_tundra")
			var c3 = gs.start_wolverine_combat(true)
			var h3: float = gs.wolf.health
			ap.play_combat(c3)
			r2["n"] += 1
			r2["dmg"] += h3 - gs.wolf.health
			r2["out"][c3.outcome] = int(r2["out"].get(c3.outcome, 0)) + 1
		gs.tactical_combat_off = false
		print("對照 選單式硬打 %s 歲：你受傷 %.1f；結果 %s" % [age2, r2["dmg"] / float(r2["n"]), str(r2["out"])])
	# 讓牠一起吃：結算照選單式的分享（殘骸再少一段、牠離開）
	_wolf(3.0)
	gs.new_game("tundra_central")
	_wolf_stats(3.0)
	gs.start_feeding("caribou", "adult", "open_tundra")
	var seg: int = int(gs.current_feeding["segments_left"])
	var c2 = gs.start_wolverine_combat(true)
	var tc2 = gs.start_tactical_combat(c2)
	tc2.begin_round()
	var opts: Array = tc2.action_options(0).map(func(o): return str(o["id"]))
	tc2.plan(0, {"action": "share"})
	tc2.resolve()
	gs.apply_tactical_combat(c2, tc2)
	gs.finish_combat(c2)
	print("讓牠一起吃：選項裡有 share %s；結果 %s／%s；殘骸 %d → %d 段" % [str(opts.has("share")), tc2.outcome, c2.outcome, seg, int(gs.current_feeding.get("segments_left", 0)) if not gs.current_feeding.is_empty() else 0])

func _wolf_stats(age: float) -> void:
	var adult: bool = age >= 2.0
	gs.wolf.age_years = age
	gs.wolf.health_max = 110.0 if adult else 85.0
	gs.wolf.health = gs.wolf.health_max
	gs.wolf.speed = 62.0 if adult else 55.0
	gs.wolf.strength = 70.0 if adult else 50.0
	gs.wolf.skill = 60.0 if adult else 45.0
	gs.wolf.perception = 60.0 if adult else 50.0
	gs.wolf.hunger = 60.0

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
				line += "  %s@%s hp%d%s" % [u["id"], str(u["pos"]), int(u["hp"]), ("[" + str(it[k]["action"]) + ":" + str(it[k]["why"]) + "]") if it.has(k) else ""]
		print(line)
		var ap: Dictionary = tc.auto_plan(0)
		line += "  你→" + str(ap.get("action", "")) + "@" + str(ap.get("move", ""))
		tc.plan(0, ap)
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
