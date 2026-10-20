extends SceneTree
# 戰術狩獵從主遊戲開的畫面檢查（Phase 2c 第 2 步）：開主遊戲、對白尾鹿出手 → 截圖 → 狼放棄 → 截圖 → 按「繼續」→ 截圖。
# 用法：OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/tactical_game_shot.gd
var f := 0
var game
var view
func _process(_d) -> bool:
	f += 1
	var gs = root.get_node("GameState")
	var out: String = OS.get_environment("OUT")
	if f == 2:
		gs.new_game("forest_east")
		gs.debug_force_transition("adult")
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 6:
		game._begin_hunt("white_tailed_deer", "adult")
		for c in game.get_children():
			if c.has_method("start_from_game"):
				view = c
		print("戰術畫面：", view != null)
	if f == 10:
		root.get_viewport().get_texture().get_image().save_png(out + "_1.png")
		view.h.give_up()
		view._after_action()
	if f == 14:
		root.get_viewport().get_texture().get_image().save_png(out + "_2.png")
		for b in view.buttons.get_children():
			if b is Button and b.text == "繼續":
				b.pressed.emit()
	if f == 20:
		root.get_viewport().get_texture().get_image().save_png(out + "_3.png")
		print("戰術畫面還在：", is_instance_valid(view) and view.is_inside_tree(), "；current_hunt：", game.current_hunt)
		return true
	return false
