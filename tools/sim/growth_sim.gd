extends SceneTree
# 成長模擬（SPEC 1.6「潛力結算」：基礎上限要依不同玩法的次成年期成長決定）。
# 六種玩法（平均、偏追獵、偏強攻、偏潛伏、偏謹慎、只吃小獵物）各跑 RUNS 隻狼，從開局玩到次成年期最後一天，
# 統計各能力的成長、成年時的巔峰上限；ADULT=1 時再接著玩到 5 歲，看各年齡離上限多遠。
# 用法：bash tools/run_sim.sh growth_sim [DAYS 未使用] [RUNS]；ADULT=1 bash tools/run_sim.sh growth_sim 0 10
# 機器人規則見 scripts/core/AutoPlayer.gd（跟 tools/sim 的其他機器人一樣只待在巢穴區）。

const PROFILES := [["average", "all", "average"], ["pursuit", "all", "pursuit"], ["assault", "all", "assault"],
	["stealth", "all", "stealth"], ["cautious", "all", "cautious"], ["small_only", "small_only", "average"],
	["deer_focus", "deer_focus", "average"]]
const STATS := ["speed", "strength", "skill", "perception", "health_max"]
const DENS := ["forest_east", "forest_north", "forest_south", "forest_west"]

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs := _env_int("RUNS", 20)
	var adult := _env_int("ADULT", 0) == 1
	print("== growth_sim：%d 隻 × %d 種玩法（巢穴輪流四區）%s" % [runs, PROFILES.size(), "，成年後玩到 5 歲" if adult else ""])
	print("   %-11s %s" % ["", "  ".join(STATS.map(func(s): return "%-17s" % s))])
	for prof in PROFILES:
		var growth := {}
		var caps := {}
		var later := {}
		var died := 0
		var hunger_sum := 0.0
		for s in STATS:
			growth[s] = []; caps[s] = []
		for r in runs:
			var ap = AP.new(prof[1], prof[2])
			ap.stop_before_adult = true
			ap.start(DENS[r % DENS.size()])
			var guard := 0
			while not ap.done() and guard < 400:
				ap.step(1); guard += 1
			ap.finish()
			var w = GS.wolf
			if not w.alive:
				died += 1
				continue
			hunger_sum += w.hunger
			for s in STATS:
				growth[s].append(float(w.get(s)) - float(w.start_stats[s]))
			# 跨過換季 → 成年，觸發潛力結算
			GS.auto_playing = true
			GS.debug_skip_day()
			GS.auto_playing = false
			for s in STATS:
				caps[s].append(float(w.potential.get(s, 0.0)))
			if adult and w.alive:
				var ap2 = AP.new(prof[1], prof[2])
				ap2.start_from_current()
				for age in [2.0, 3.0, 4.0, 5.0]:
					while not ap2.done() and w.age_years < age:
						ap2.step(1)
					if not w.alive: break
					var row: Array = later.get(age, [])
					for s in STATS:
						var cap := float(w.potential.get(s, 1.0))
						row.append(float(w.get(s)) / max(1.0, cap))
					later[age] = row
				ap2.finish()
		var line := ""
		for s in STATS:
			line += "  %-17s" % ("+%.1f(%.1f~%.1f)→%.0f" % [_avg(growth[s]), _min(growth[s]), _max(growth[s]), _avg(caps[s])])
		print("   %-11s%s  死亡 %d  平均飽食 %.0f" % [prof[0], line, died, hunger_sum / max(1, runs - died)])
		for age in later.keys():
			var row: Array = later[age]
			var per := []
			for i in STATS.size():
				var vals := []
				for j in range(i, row.size(), STATS.size()): vals.append(row[j])
				per.append("%3.0f%%" % (100.0 * _avg(vals)))
			print("      %.0f 歲：能力 / 上限 = %s" % [age, "  ".join(per)])
	quit()
	return true

func _avg(a: Array) -> float:
	if a.is_empty(): return 0.0
	var t := 0.0
	for v in a: t += v
	return t / a.size()

func _min(a: Array) -> float:
	return a.min() if not a.is_empty() else 0.0

func _max(a: Array) -> float:
	return a.max() if not a.is_empty() else 0.0
