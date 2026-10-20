extends SceneTree
# 狩獵入口的回歸測試（2026-10-20 試玩：看到一群白尾鹿選「狩獵」沒有進戰術地圖）：
# 實際開主畫面，從「看到獵物」「追蹤成功」「發現足跡」三個入口開始狩獵，
# 白尾鹿、母馬鹿、騾鹿、馴鹿要開戰術地圖；狐狸、公馬鹿照舊走選單。
# 用法：bash tools/run_sim.sh hunt_entry_ui
var gs
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var cases := [["white_tailed_deer", "adult", true], ["white_tailed_deer", "adult", true, true], ["elk", "adult", true], ["mule_deer", "adult", true],
		["caribou", "adult", true], ["red_fox", "adult", false], ["elk", "buck", false]]
	for entry in ["sight", "begin"]:
		for c in cases:
			gs.new_game("forest_east")
			gs.debug_force_transition("adult")
			gs.pending_events.clear()
			change_scene_to_file("res://scenes/Game.tscn")
			await _wait(6)
			var game = current_scene
			game.text_watch_timer = 0.0
			if entry == "sight":
				# 看到獵物（探索結果是「看到」的線索），鹿群照第 4 個欄位
				gs.current_discovery = {"kind": "clue", "clue": "sight", "source": c[0], "source_kind": "prey", "life_stage": c[1], "herd": c.size() > 3}
				game.current_hunt = gs.action_hunt_sighted()
				game._enter_hunt()
			else:
				game._begin_hunt(c[0], c[1])
			await _wait(4)
			var tactical: bool = game.tactical_view != null
			if tactical != bool(c[2]):
				fails += 1
				print("  ✗ %s %s %s%s：戰術地圖 %s（應該 %s）" % [entry, c[0], c[1], "（鹿群）" if c.size() > 3 else "", tactical, c[2]])
			if tactical:
				game.tactical_view.queue_free()
				game.tactical_view = null
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
