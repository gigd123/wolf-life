extends SceneTree
# 一般鄰群（Phase 3 第 4 步）的畫面檢查：深夜的合嚎 → 探索時的氣味標記 → 地盤被佔走的卡片 → 撞上鄰群（和伴侶一起），各截一張。
# 用法：OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/neighbor_shot.gd
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
		gs.new_game("mountain_foothills")
		gs.wolf.age_years = 3.0
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 6:
		gs.pending_events.clear()
		_close()
		gs.pending_events.append({"type": "neighbor_howl", "region": "mountain_canyon", "pack": "mountain", "many": true})
		game._process_events()
	if f == 9:
		_shot("howl")
		_close()
		game._show_discovery({"kind": "pack_sign", "sign": "border", "pack": "mountain", "location": "", "home": "mountain_canyon"})
	if f == 12:
		_shot("sign")
		_close()
		gs.pending_events.append({"type": "territory_lost", "region": "mountain_meadow"})
		game._process_events()
	if f == 15:
		_shot("lost")
		_close()
		gs._spawn_she_wolf()
		gs.she_wolf().territory = gs.current_region
		gs.she_wolf().relation = 8
		gs.she_approach()
		gs.pending_events.clear()
		gs.debug_neighbor_meet()
		game._process_events()
	if f == 18:
		_shot("meet")
		print("SHOT done")
		quit()
	return false
