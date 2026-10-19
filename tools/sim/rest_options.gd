extends SceneTree
# Phase 2b 第 2 步「休息到…」改版的回歸測試：選項依目的列出（黃昏、清晨，現在就是那個時段時不列；吃撐時有「消化完」）；
# 休息到消化完會停在不再吃撐；休息到黃昏會停在黃昏。
# 用法：bash tools/run_sim.sh rest_options
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	for p in gt.PERIODS.size():
		gt.period_index = p
		gs.wolf.hunger = 80.0
		var ids: Array = gs.rest_options().map(func(o): return str(o.get("period", o["id"])))
		var cur: String = gt.current_period()
		_check(not ids.has(cur), "%s：不列現在的時段（%s）" % [cur, ids])
		_check(not ids.has("digest"), "%s：不吃撐時沒有消化完" % cur)
		for want in ["dusk", "dawn"]:
			_check(ids.has(want) or cur == want, "%s：有 %s" % [cur, want])
		gs.wolf.hunger = 140.0
		_check(gs.rest_options().any(func(o): return o["id"] == "digest"), "%s：吃撐時有消化完" % cur)
	# 消化完
	gt.period_index = 1
	gs.current_region = gs.den_region
	gs.pending_events.clear()
	gs.wolf.hunger = 150.0
	var res: Dictionary = gs.action_rest_digest()
	print("消化完：", res, " 飽食度 ", snapped(gs.wolf.hunger, 0.1))
	_check(str(res["interrupted"]) != "" or not gs.wolf.is_overfed(), "休息到消化完：不再吃撐（或被事件打斷）")
	_check(gs.wolf.hunger > 110.0, "不會休息過頭（飽食度 %.1f）" % gs.wolf.hunger)
	# 黃昏
	gt.period_index = 1
	gs.pending_events.clear()
	gs.wolf.hunger = 80.0
	var r2: Dictionary = gs.action_rest_until("dusk")
	_check(str(r2["interrupted"]) != "" or gt.current_period() == "dusk", "休息到黃昏：停在黃昏（%s）" % gt.current_period())
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
