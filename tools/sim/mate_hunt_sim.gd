extends SceneTree
# Phase 3 第 3 步「伴侶一起狩獵」的模擬（SPEC Phase 3 第 2、3 步的通過標準：有伴侶時大型獵物的成功率高 10～20 個百分點、一場的回合數不超過單狼的 1.5 倍）。
# 成年狼（常見的能力值）交給本能玩到底（每場固定秋季清晨，WHEN=summer_day 夏季白天），每種打法都試、取最好的（表格），另外印本能自己挑的合計：單狼／伴侶驅趕／追擊／埋伏，各獵物 RUNS 場；伴侶用離群母狼的平均能力。
# 用法：bash tools/run_sim.sh mate_hunt_sim 0 60；WHEN=summer_day 改成夏季白天；PREY_ONLY=white_tailed_deer,moose 只跑這些
var SEASON := 2
var PERIOD := 0
const POLS := ["auto", "stalk", "chase", "hold", "pace"]
const PREY := [["white_tailed_deer", "forest_edge", "forest_east"], ["elk", "dense_forest", "forest_north"], ["mule_deer", "forest_edge", "mountain_foothills"], ["caribou", "open_tundra", "tundra_south"], ["moose", "stream", "forest_north"]]
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 40
	# WHEN=summer_day：夏季白天（比較難，避免秋季清晨幾乎都獵得到、看不出差別）
	if OS.get_environment("WHEN") == "summer_day":
		SEASON = 1
		PERIOD = 1
	print("== mate_hunt_sim：成年狼交給本能，各 %d 場（成功率 %%／平均回合）" % runs)
	print("| 獵物 | 單狼 | 驅趕 | 追擊 | 埋伏 |")
	print("| --- | --- | --- | --- | --- |")
	var tot := {}
	var auto_tot := {}
	var only: Array = Array(OS.get_environment("PREY_ONLY").split(",")) if OS.get_environment("PREY_ONLY") != "" else []
	var prey_n := 0
	for p in PREY:
		if not only.is_empty() and not only.has(p[0]):
			continue
		prey_n += 1
		gs.new_game(p[2])
		gs.wolf.age_years = 4.0
		for st in [["speed", 66.0], ["skill", 62.0], ["strength", 70.0], ["perception", 70.0]]:
			gs.debug_set_stat(st[0], st[1])
		gs.pending_events.clear()
		var row: Array = [p[0]]
		for kind in ["solo", "drive", "chase", "ambush"]:
			# 每種打法都試，取最好的（同 tactical_ally_matrix：看角色本身的價值，不受本能挑錯打法影響）；本能自己挑的也記下來
			var best := -1
			var best_rounds := 0
			var best_pol := ""
			for pol in POLS:
				var ok := 0
				var rounds := 0
				for i in runs:
					# 每場固定秋季、清晨（時間會隨狩獵前進，不固定的話各組落在不同季節、時段）
					gt.season_index = SEASON
					gt.day = 3
					gt.period_index = PERIOD
					gt.turn_in_period = 0
					gs.wolf.health = gs.wolf.health_max
					gs.wolf.stamina = 100.0
					gs.wolf.hunger = 60.0
					var h = gs.start_hunt(p[0], "adult", -1, false, p[1])
					if kind != "solo":
						h.mate_help = "she_wolf_sim"
						h.mate_role = kind
						gs.npcs["she_wolf_sim"] = load("res://scripts/core/NpcWolf.gd").create("she_wolf_sim", p[2], "lone_female")
					var th = gs.start_tactical(h)
					TacticalInstinct.play(th, "" if pol == "auto" else pol)
					rounds += th.rounds
					if th.result == "caught":
						ok += 1
				if pol == "auto":
					auto_tot[kind] = int(auto_tot.get(kind, 0)) + ok
				if ok > best:
					best = ok
					best_rounds = rounds
					best_pol = pol
			row.append("%d%%／%.1f（%s）" % [roundi(100.0 * best / runs), float(best_rounds) / runs, best_pol])
			tot[kind] = int(tot.get(kind, 0)) + best
		print("| " + " | ".join(row) + " |")
	var n: int = runs * prey_n
	print("本能自己挑：單狼 %d%%、驅趕 %d%%、追擊 %d%%、埋伏 %d%%" % [roundi(100.0 * auto_tot["solo"] / n), roundi(100.0 * auto_tot["drive"] / n), roundi(100.0 * auto_tot["chase"] / n), roundi(100.0 * auto_tot["ambush"] / n)])
	print("最好的打法：單狼 %d%%、驅趕 %d%%、追擊 %d%%、埋伏 %d%%" % [roundi(100.0 * tot["solo"] / n), roundi(100.0 * tot["drive"] / n), roundi(100.0 * tot["chase"] / n), roundi(100.0 * tot["ambush"] / n)])
	quit()
	return true
