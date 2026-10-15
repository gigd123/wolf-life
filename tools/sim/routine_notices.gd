extends SceneTree
# 照常過日子（2026-10-15 試玩 BUG-10、12）：季節到期時照常過到睡覺換季才停（不是 0 天就停）；跨進老年時老年卡片留著，結束後顯示。
# 用法：bash tools/run_sim.sh routine_notices
var f := 0
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	# 1. 季節到期時照常過日子
	for i in 3:
		gs.new_game("forest_east")
		gs.debug_force_transition("adult")
		gs.pending_events.clear()
		gt.day = gt._season_day_count() + 1
		var s0: int = gt.season_index
		var r: Dictionary = gs.run_routine(3, "small")
		print("season due: reason=", r["reason"], " days=", r["days"], " season ", s0, "->", gt.season_index, " pending=", gs.pending_events.map(func(e): return e.get("type", "")))
	# 2. 跨進老年
	var hits := 0
	for i in 20:
		gs.new_game("forest_east")
		gs.debug_force_transition("adult")
		gs.wolf.age_years = 5.99
		gt.day = gt._season_day_count()
		gs.pending_events.clear()
		var r: Dictionary = gs.run_routine(10, "small")
		var types: Array = gs.pending_events.map(func(e): return e.get("type", ""))
		if types.has("elder_transition"):
			hits += 1
		if i < 3:
			print("elder: reason=", r["reason"], " days=", r["days"], " age=", snapped(gs.wolf.age_years, 0.01), " pending=", types)
	print("elder card kept ", hits, "/20")
	return true
