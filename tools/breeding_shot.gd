extends SceneTree
# 繁殖與育幼（Phase 3 第 5 步）的畫面檢查：幼狼出生的字卡 → 進食畫面多「叼一段回去給幼狼」→ 巢穴有東西靠近 → 狼群面板（幼狼與存糧），各截一張。
# 用法：OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/breeding_shot.gd
var f := 0
var game
var gs

func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "_" + name + ".png")

func _close() -> void:
	game.card_overlay.visible = false
	game.encounter_overlay.visible = false

func _process(_d) -> bool:
	f += 1
	if f == 2:
		gs = root.get_node("GameState")
		gs.new_game("forest_east")
		gs.wolf.age_years = 3.0
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 6:
		_close()
		gs._spawn_she_wolf()
		gs.she_wolf().territory = gs.current_region
		gs.she_wolf().relation = 8
		gs.she_approach()
		gs.pending_events.clear()
		root.get_node("GameTime").season_index = 0
		gs.breeding()["pregnant"] = true
		gs.breeding()["winter_fed"] = 1.0
		gs._give_birth()
		game._process_events()
	if f == 9:
		_shot("born")
		_close()
		gs.current_region = "forest_north"
		gs.start_feeding("white_tailed_deer", "adult", "forest_edge")
		game._show_feeding()
	if f == 12:
		_shot("feeding")
		_close()
		gs.current_feeding = {}
		gs.current_region = gs.den_region
		gs.pending_events.append({"type": "den_threat", "animal": "coyote"})
		game._process_events()
	if f == 15:
		_shot("threat")
		_close()
		game._show_pack_panel()
	if f == 18:
		_shot("panel")
		print("SHOT done")
		quit()
	return false
