extends SceneTree
# 狼群成員（Phase 3 第 6 步）的畫面檢查：狼群面板（伴侶、滿 1 歲的子女逐隻選）→ 子女離群的字卡，各截一張。
# 用法：OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/members_shot.gd
var f := 0
var game
var gs

func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "_" + name + ".png")

func _process(_d) -> bool:
	f += 1
	if f == 2:
		gs = root.get_node("GameState")
		gs.new_game("forest_east")
		gs.wolf.age_years = 3.0
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 6:
		game.card_overlay.visible = false
		game.encounter_overlay.visible = false
		gs._spawn_she_wolf()
		gs.she_wolf().territory = gs.current_region
		gs.she_wolf().relation = 8
		gs.she_approach()
		root.get_node("GameTime").season_index = 0
		gs.breeding()["pregnant"] = true
		gs.breeding()["winter_fed"] = 1.0
		gs._give_birth()
		gs.pending_events.clear()
		var ps: Array = gs.pups()
		for i in ps.size():
			ps[i].age_years = 1.25 if i < 3 else 0.25
		gs._grow_young()
		game._show_pack_panel(ps[1].id)
	if f == 9:
		_shot("panel")
		game.encounter_overlay.visible = false
		gs.pending_events.append({"type": "child_left", "sex": "female", "age": 2.0, "trait": "independent"})
		game._process_events()
	if f == 12:
		_shot("left")
		print("SHOT done")
		quit()
	return false
