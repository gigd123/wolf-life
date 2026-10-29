extends SceneTree
# 威嚇的三段結果（2026-10-29 QA：威嚇黑狼直接被咬；使用者選 A）：每種對手、每種情境，一直威嚇到有結果為止（最多 6 次）：
# 嚇退、僵持幾次、被激怒（打起來）。一生模擬裡常見的成年狼（4 歲，力量 86 技巧 75 速度 62）。
# 另外檢查：僵持不扣血、還在對峙；僵持後下一次威嚇成功率上升、激怒的機率也上升；試探看出動搖時激怒比較少。
# 用法：bash tools/run_sim.sh threaten_outcomes
var f := 0
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	gs.new_game("forest_east")
	var cases := [["stranger_wolf", "territory", "黑狼（牠的地盤）"], ["stranger_wolf", "meet", "黑狼（遇上）"], ["grizzly_bear", "carcass", "灰熊（搶殘骸）"],
		["cougar", "encounter", "美洲獅"], ["black_bear", "carcass", "黑熊（搶殘骸）"], ["coyote", "carcass", "郊狼"], ["red_fox", "carcass", "紅狐"]]
	print("== 威嚇一直到有結果（每格 300 場）：第一次就嚇退／僵持後嚇退／被激怒；第一次的成功率、激怒率")
	for c in cases:
		var first_ok := 0
		var later_ok := 0
		var provoked := 0
		var standoffs := 0
		var p0 := 0.0
		var pv0 := 0.0
		for i in 300:
			for st in [["speed", 62.0], ["skill", 75.0], ["strength", 86.0], ["perception", 70.0], ["age_years", 4.0]]:
				gs.debug_set_stat(st[0], st[1])
			gs.wolf.health = gs.wolf.health_max
			gs.wolf.clear_injury()
			var cb = gs.start_combat(c[0], "adult", c[1])
			if c[0] == "stranger_wolf":
				cb.set_npc(gs.stranger())
			for k in 6:
				var opt: Dictionary = {}
				for o in cb.options():
					if str(o["id"]) == "threaten":
						opt = o
				if opt.is_empty():
					break
				if k == 0:
					p0 += float(opt["chance"])
					pv0 += float(opt.get("provoke", 0.0))
				var hp: float = gs.wolf.health
				cb.choose("threaten")
				if cb.outcome == "drove_off":
					if k == 0:
						first_ok += 1
					else:
						later_ok += 1
					break
				if cb.stage_name() != "standoff":
					provoked += 1
					break
				standoffs += 1
				if gs.wolf.health < hp:
					fails += 1
					print("    僵持卻扣血")
		print("  %-14s 第一次嚇退 %3d%%、僵持後嚇退 %3d%%、被激怒 %3d%%（平均僵持 %.1f 次；第一次的成功率 %d%%、激怒率 %d%%）" % [c[2],
			roundi(100.0 * first_ok / 300), roundi(100.0 * later_ok / 300), roundi(100.0 * provoked / 300), float(standoffs) / 300, roundi(100.0 * p0 / 300), roundi(100.0 * pv0 / 300)])
	# 規則檢查
	var cb2 = gs.start_combat("stranger_wolf", "adult", "territory")
	cb2.set_npc(gs.stranger())
	var o1: Dictionary = cb2.options().filter(func(o): return str(o["id"]) == "threaten")[0]
	cb2.threaten_standoffs = 1
	var o2: Dictionary = cb2.options().filter(func(o): return str(o["id"]) == "threaten")[0]
	_check(float(o2["chance"]) > float(o1["chance"]) and float(o2["provoke"]) > float(o1["provoke"]), "僵持過一次：成功率 %.2f → %.2f、激怒率 %.2f → %.2f" % [o1["chance"], o2["chance"], o1["provoke"], o2["provoke"]])
	cb2.threaten_standoffs = 0
	cb2.probe_reading = "wavering"
	var o3: Dictionary = cb2.options().filter(func(o): return str(o["id"]) == "threaten")[0]
	_check(float(o3["provoke"]) < float(o1["provoke"]), "試探看出動搖：激怒率 %.2f → %.2f" % [o1["provoke"], o3["provoke"]])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
