extends SceneTree
# 苔原狼一起狩獵在主遊戲戰術畫面的截圖（Phase 2i）：KIND=join（加入，獵物在逃）／follow（跟上來，觀察 3 回合後出現）
# 用法：KIND=join OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/tundra_joint_shot.gd
var f := 0
var game
var gs
func _process(_d) -> bool:
	f += 1
	var kind: String = OS.get_environment("KIND") if OS.get_environment("KIND") != "" else "join"
	if f == 2:
		gs = root.get_node("GameState")
		gs.new_game("tundra_south")
		gs.debug_force_transition("adult")
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 8:
		gs.pending_events.clear()
		game.encounter_overlay.visible = false
		game.card_overlay.visible = false
		var h = gs.start_hunt("caribou", "adult", -1, false, "open_tundra")
		h.apply_tundra_help(2, kind == "join")
		game.current_hunt = h
		game._open_tactical()
	if f == 12 and kind == "follow":
		var th = game.tactical_view.h
		for i in 3:
			th.observe()
		game.tactical_view._after_action()
	if f == 16:
		root.get_texture().get_image().save_png(OS.get_environment("OUT") + "_" + kind + ".png")
		quit()
	return false
