extends SceneTree
# Phase 3c「聞到離群母狼的氣味」的畫面（2026-11-24 試玩回報：探索到 she_scent 時 _discovery_text 當掉）：實際開主畫面
#   1. 牠在這一區、在別區、已經見過牠：卡片的文字各自正確，沒有原始的翻譯鍵，按鈕有「繼續探索」「離開」
#   2. 所有探索結果的 kind（GameState、ExploreSystem 裡設進 current_discovery 的）在 Game.gd 都有處理
# 用法：bash tools/run_sim.sh she_scent_ui
var gs
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _t(key: String) -> String:
	return str(TranslationServer.translate(key))

func _run() -> void:
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.pending_events.clear()
	change_scene_to_file("res://scenes/Game.tscn")
	await _wait(6)
	var game = current_scene
	game.text_watch_timer = 0.0
	for c in [
		[false, "forest_east", _t("she_wolf.sign.scent") + _t("she_wolf.sign.here")],
		[false, "forest_south", _t("she_wolf.sign.scent") + _t("she_wolf.sign.near").replace("{region}", _t("region.forest_south"))],
		[true, "forest_east", _t("she_wolf.sign.scent.known") + _t("she_wolf.sign.here")],
	]:
		gs.life_log["she_met"] = c[0]
		gs.current_region = "forest_east"
		gs.current_discovery = {"kind": "she_scent", "toward": c[1], "location": "clearing"}
		game.encounter_overlay.visible = false
		game._show_discovery(gs.current_discovery)
		await _wait(2)
		_check(game.encounter_overlay.visible, "卡片打開（%s）" % str(c))
		_check(game.encounter_message.text == c[2], "文字（%s）：%s" % [str(c), game.encounter_message.text])
		_check(not game.encounter_message.text.contains("she_wolf.") and not game.encounter_message.text.contains("{"), "沒有原始的翻譯鍵與佔位")
		var leave: Button = null
		for b in game.encounter_buttons_box.get_children():
			if b is Button and not b.is_queued_for_deletion() and (b as Button).text.begins_with(_t("ui.leave")):
				leave = b
		_check(leave != null, "有離開的按鈕")
		if leave != null:
			leave.pressed.emit()
			await _wait(2)
			_check(gs.current_discovery.is_empty() and not game.encounter_overlay.visible, "離開後清掉探索結果")
	# 每一種探索結果畫面都有處理
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/Game.gd")
	var from: int = src.find("func _show_discovery(")
	var body: String = src.substr(from, src.find("\nfunc ", from + 5) - from)
	from = src.find("func _discovery_text(")
	body += src.substr(from, src.find("\nfunc ", from + 5) - from)
	var re := RegEx.create_from_string(r'(?:current_discovery = |return ){"kind": "([a-z_]+)"')
	var kinds: Dictionary = {}
	for m in re.search_all(FileAccess.get_file_as_string("res://scripts/core/GameState.gd").replace('return {"kind"', "")):
		kinds[m.get_string(1)] = true
	for m in re.search_all(FileAccess.get_file_as_string("res://scripts/core/ExploreSystem.gd")):
		kinds[m.get_string(1)] = true
	_check(kinds.size() >= 15 and kinds.has("she_scent"), "讀得到探索結果的種類（%d）" % kinds.size())
	for k in kinds:
		_check(body.contains("\"%s\"" % k), "Game.gd 有處理探索結果 %s" % k)
	print("聞到母狼的氣味：%s（%d 種探索結果）" % ["失敗 %d 項" % fails if fails > 0 else "全部通過", kinds.size()])
	quit()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
