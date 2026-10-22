extends SceneTree
# 戰術地圖撲咬資訊的畫面檢查（2026-10-22 試玩回報：機率等資訊顯示不完整；母鹿、幼鹿分不出來）：
# 開主遊戲、對 ANIMAL／STAGE 出手 → 把狼放到目標旁邊、滑鼠停在可以撲的格子 → 截圖。
# 用法：OUT=<輸出路徑前綴> ANIMAL=elk STAGE=juvenile DEN=forest_east xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/tactical_hover_shot.gd
var f := 0
var game
var view
func _process(_d) -> bool:
	f += 1
	var gs = root.get_node("GameState")
	var out: String = OS.get_environment("OUT")
	var animal: String = OS.get_environment("ANIMAL") if OS.get_environment("ANIMAL") != "" else "white_tailed_deer"
	var stage: String = OS.get_environment("STAGE") if OS.get_environment("STAGE") != "" else "adult"
	if f == 2:
		gs.new_game(OS.get_environment("DEN") if OS.get_environment("DEN") != "" else "forest_east")
		gs.debug_force_transition("adult")
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 6:
		var hunt = gs.start_hunt(animal, stage)
		hunt.set_herd(OS.get_environment("HERD") != "")
		game.current_hunt = hunt
		game._open_tactical()
		for c in game.get_children():
			if c.has_method("start_from_game"):
				view = c
	if f == 8:
		var h = view.h
		# 狼放在目標側後方一格，鹿已經在逃（因素最多的情況）
		h.deer_state = "flee"
		h.flee_round = 2
		var cell: Vector2i = h.deer_pos - h.deer_facing
		if not h.in_bounds(cell) or h.deer_cells().has(cell):
			cell = h.deer_pos + Vector2i(1, 1)
		h.wolf_pos = cell + Vector2i(0, 2)
		var targets: Dictionary = h.pounce_targets()
		view.hover = targets.keys()[0] if not targets.is_empty() else cell
		view._after_action()
		view.hover = targets.keys()[0] if not targets.is_empty() else cell
		view._refresh()
		print("可以撲的格子：", targets.size(), "；目標：", h.label(), "；幼獸：", h.is_fawn(h.target))
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png(out + ".png")
		return true
	return false
