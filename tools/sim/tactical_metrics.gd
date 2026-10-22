extends SceneTree
# 試玩紀錄的戰術狩獵細節（2026-10-22 試玩討論第 1 項）：自己撲一下再放棄、交給本能打完各一場，
# 檢查 metrics.tactical_detail：場數、交給本能、撲的次數與命中率、怎麼結束的，以及 metrics_summary 的那一行。
# 用法：bash tools/run_sim.sh tactical_metrics
var gs
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	_run.call_deferred()

func _run() -> void:
	gs.new_game("forest_east")
	gs.pending_events.clear()
	# 1. 自己撲：把狼放到目標旁邊，撲一下；沒結束就放棄
	var hunt = gs.start_hunt("white_tailed_deer", "adult")
	var th = gs.start_tactical(hunt)
	th.deer_state = "flee"
	th.wolf_pos = th.deer_pos + Vector2i(0, 2) if th.in_bounds(th.deer_pos + Vector2i(0, 2)) else th.deer_pos + Vector2i(0, -2)
	var targets: Dictionary = th.pounce_targets()
	_check(not targets.is_empty(), "狼在目標旁邊可以撲")
	if not targets.is_empty():
		th.pounce_at(targets.keys()[0])
	if not th.done:
		if th.held:
			th.hold_action("release")
		if not th.done:
			th.give_up()
	gs.finish_tactical_hunt(hunt, th)
	var row: Dictionary = gs.metrics().get("tactical_detail", {}).get("young", {})
	_check(int(row.get("hunts", 0)) == 1 and int(row.get("pounces", 0)) == 1 and int(row.get("instinct", 0)) == 0, "未滿 1 歲：1 場、撲 1 次、沒交給本能（%s）" % row)
	_check(float(row.get("best", 0.0)) >= float(row.get("chosen", 0.0)) and float(row.get("chosen", 0.0)) > 0.0, "記下選的命中率與可選最高")
	_check((row.get("end", {}) as Dictionary).size() == 1, "記下怎麼結束的（%s）" % row.get("end", {}))
	# 2. 交給本能：不記撲的命中率，算一場本能
	var hunt2 = gs.start_hunt("white_tailed_deer", "adult")
	var th2 = gs.start_tactical(hunt2)
	TacticalInstinct.play(th2)
	gs.finish_tactical_hunt(hunt2, th2)
	row = gs.metrics()["tactical_detail"]["young"]
	_check(int(row["hunts"]) == 2 and int(row["instinct"]) == 1 and int(row["pounces"]) == 1, "交給本能的那場：本能 +1、撲的次數不變（%s）" % row)
	var line: String = str(gs.metrics_summary()["tactical_detail"])
	print("  摘要：", line)
	_check(line.contains("young 2場 本能1 撲1次"), "摘要有這一行")
	# 3. 自動玩家不記
	gs.auto_playing = true
	var hunt3 = gs.start_hunt("white_tailed_deer", "adult")
	var th3 = gs.start_tactical(hunt3)
	th3.give_up()
	gs.finish_tactical_hunt(hunt3, th3)
	gs.auto_playing = false
	_check(int(gs.metrics()["tactical_detail"]["young"]["hunts"]) == 2, "自動玩家（照常過日子）的不記")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
