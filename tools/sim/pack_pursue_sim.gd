extends SceneTree
# Phase 3d 第 1 步：撞上整群（戰術戰鬥）打贏後追擊帶頭的。你的能力照 2026-11-25 試玩紀錄（3 歲稍弱、4.4 歲），一直正面對打（不因寡不敵眾先撤）。
# 印：打贏、帶頭的示弱（可以追）的比例、剩幾隻家人；追擊：被擋、咬死、逃掉的比例、平均挨的傷。
# 用法：bash tools/run_sim.sh pack_pursue_sim；RUNS=100；YOUNG=1.5,2.0 黑狼一家的年輕成員
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 100
	var young: Array = Array(OS.get_environment("YOUNG").split(",")).map(func(x): return float(x)) if OS.get_environment("YOUNG") != "" else [1.5, 2.0]
	var profiles := {3.0: [85.0, 72.0, 62.0, 52.0, 108.0], 4.4: [99.0, 84.0, 64.0, 54.0, 117.0]}
	print("== 黑狼一家（帶頭＋伴侶＋年輕的 %s）戰術戰鬥打贏後追擊，每格 %d 場" % [str(young), runs])
	for age in [3.0, 4.4]:
		var won := 0
		var outs := {}
		var sub := 0
		var blockers_sum := 0
		var res := {}
		var dmg := 0.0
		for i in runs:
			gs.new_game("forest_east")
			gs.debug_force_transition("adult")
			var pf: Array = profiles[age]
			gs.wolf.age_years = age
			gs.wolf.strength = pf[0]
			gs.wolf.skill = pf[1]
			gs.wolf.speed = pf[2]
			gs.wolf.perception = pf[3]
			gs.wolf.health_max = pf[4]
			gs.wolf.health = pf[4]
			var bp = gs.black_pack
			bp.stage = "pack"
			bp.regions = [gs.current_region]
			bp.mate_age = 4.0
			bp.young = young.duplicate()
			gs.meet_pack_id = "black"
			var tc = gs.start_pack_tactical()
			tc.cfg["ai"]["wolf"]["auto_retreat_pr"] = 0.0
			var g := 0
			while not tc.done and g < 300:
				g += 1
				tc.units[0]["command"] = "duel"
				tc.plan(0, tc.ally_plan(0))
				tc.resolve()
				if not tc.done:
					tc.begin_round() # 對手決定下一回合（同戰鬥畫面的 _resolve_and_next）
			outs[str(tc.outcome)] = int(outs.get(str(tc.outcome), 0)) + 1
			var r: Dictionary = gs.finish_pack_tactical(tc)
			if not bool(r.get("won", false)):
				continue
			won += 1
			if not gs.can_pursue_pack(r):
				continue
			sub += 1
			blockers_sum += int(r.get("blockers", 0))
			var pr: Dictionary = gs.pack_pursue(r)
			res[str(pr["result"])] = int(res.get(str(pr["result"]), 0)) + 1
			dmg += float(pr["dmg"])
		var n: int = maxi(1, sub)
		print("  你 %.1f 歲：打贏 %d%%、帶頭的示弱可以追 %d%%（平均剩 %.1f 隻家人）；追擊後 %s；平均挨 %.1f；戰鬥結局 %s" % [age, roundi(100.0 * won / runs), roundi(100.0 * sub / runs), float(blockers_sum) / n,
			str(res.keys().map(func(k): return "%s %d%%" % [k, roundi(100.0 * int(res[k]) / n)])), dmg / n, str(outs)])
	quit()
	return true
