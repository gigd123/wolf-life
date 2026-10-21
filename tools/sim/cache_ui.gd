extends SceneTree
# Phase 2e 第 2 步「藏食物的畫面」回歸測試：實際開主畫面
#   1. 進食畫面有「叼一段去藏」，按兩次藏 2 段；兩段都新鮮時第三次灰掉（滑鼠提示「滿了」）
#   2. 離開後主畫面有「吃藏起來的肉（2 段）」，地圖上這一區有 ◆、滑鼠提示寫幾段
#   3. 按「吃藏起來的肉」：少一段、飽食度增加
# 用法：bash tools/run_sim.sh cache_ui
var gs
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.pending_events.clear()
	change_scene_to_file("res://scenes/Game.tscn")
	await _wait(6)
	var game = current_scene
	game.text_watch_timer = 0.0
	gs.start_feeding("elk", "adult", "clearing")
	game._show_feeding()
	await _wait(2)
	for k in 2:
		var btn: Button = _button(game.encounter_buttons_box, TranslationServer.translate("feeding.cache"))
		_check(btn != null and not btn.disabled, "進食畫面有「叼一段去藏」（第 %d 次）" % (k + 1))
		if btn != null:
			btn.pressed.emit()
			await _wait(2)
	_check(gs.cache_pieces().size() == 2, "藏了 2 段（%d）" % gs.cache_pieces().size())
	var full: Button = _button(game.encounter_buttons_box, TranslationServer.translate("feeding.cache"))
	_check(full != null and full.disabled and full.tooltip_text.contains("滿了"), "兩段都新鮮：按鈕灰掉、提示滿了")
	gs.leave_feeding()
	game.encounter_overlay.visible = false
	game._refresh()
	await _wait(2)
	var eat: Button = game.action_buttons["eat_cache"]
	_check(eat.visible and eat.text.contains("2"), "主畫面有「吃藏起來的肉（2 段）」（%s）" % eat.text)
	var slot_ok := false
	for b in game.map_slots:
		if (b as Button).text.contains(TranslationServer.translate("map.cache")) and (b as Button).tooltip_text.contains("2"):
			slot_ok = true
	_check(slot_ok, "地圖上這一區有藏肉的標記與提示")
	gs.wolf.hunger = 30.0
	eat.pressed.emit()
	await _wait(2)
	_check(gs.cache_pieces().size() == 1 and gs.wolf.hunger > 30.0, "吃了一段：剩 1 段、飽食度增加")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

func _button(box: Node, prefix: String) -> Button:
	for n in box.get_children():
		if n is Button and (n as Button).text.begins_with(prefix) and not n.is_queued_for_deletion():
			return n
	return null

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
