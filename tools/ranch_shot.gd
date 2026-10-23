extends SceneTree
# 牧場（Phase 4a 第 1 步）的畫面檢查：除錯開放牧場 → 走到連到牧場的區域（第一次的卡片）→ 關掉看「前往牧場」→ 走進牧場邊緣，各截一張。
# 用法：OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/ranch_shot.gd
var f := 0
var game
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
		gs.pending_events.clear()
		game.encounter_overlay.visible = false
		game.card_overlay.visible = false
		gs.ranch = {"state": "open", "candidate": "A"}
		root.get_node("GameData").set_ranch("A")
		game._on_region_button("forest_south")
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png(out + "_1.png")
		game.encounter_overlay.visible = false
		game.card_overlay.visible = false
		game.rendered_map = ""
		game._refresh()
	if f == 16:
		root.get_viewport().get_texture().get_image().save_png(out + "_2.png")
		game._on_region_button("ranch_edge")
	if f == 22:
		game.encounter_overlay.visible = false
		game.card_overlay.visible = false
		game._refresh()
	if f == 26:
		root.get_viewport().get_texture().get_image().save_png(out + "_3.png")
		gs.ranch = {"state": "clues", "candidate": "A"}
		gs.current_region = "forest_south"
		for i in 50:
			if gs._maybe_ranch_clue():
				break
		game._show_discovery(gs.current_discovery)
	if f == 32:
		root.get_viewport().get_texture().get_image().save_png(out + "_4.png")
		return true
	return false
