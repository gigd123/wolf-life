extends SceneTree
# 離群母狼（Phase 3 第 2 步）的畫面檢查：成年 → 主畫面（行動欄多了「嚎叫」）→ 徵兆 → 遇上（牠在吃東西）→ 走近 → 伴侶字卡 → 主畫面（伴侶同行、狼群按鈕）→ 狼群面板（第 3 步），各截一張。
# 用法：OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/she_wolf_shot.gd
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
		gs.pending_events.clear()
		game.card_overlay.visible = false
		game.encounter_overlay.visible = false
		game._refresh()
	if f == 9:
		_shot("main")
		gs._spawn_she_wolf()
		game._process_events()
	if f == 12:
		_shot("sign")
		game.encounter_overlay.visible = false
		gs.she_wolf().territory = gs.current_region
		gs.current_discovery = {"kind": "she_wolf", "location": "", "first": true, "eating": true}
		game._show_discovery(gs.current_discovery)
	if f == 15:
		_shot("meet")
		gs.she_wolf().relation = 8
		var ok: bool = gs.she_approach()
		game.encounter_overlay.visible = false
		game._process_events()
	if f == 18:
		_shot("mate")
		game.card_overlay.visible = false
		game._refresh()
	if f == 21:
		_shot("main_mate")
		game._show_pack_panel()
	if f == 24:
		_shot("pack")
		print("SHOT done mate=", gs.has_mate())
		quit()
	return false
