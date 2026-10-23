extends SceneTree
# 牧場的人類遭遇（Phase 4a 第 4 步）的畫面檢查：除錯開放牧場、人在放牧地 → KIND（patrol／hunt／warning）→ 截圖，
# 之後每一步按第一個選項（追獵被狗追上後按「轉身咬退一隻」）再截圖，最多 5 張。
# 用法：KIND=hunt OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/ranch_enc_shot.gd
var f := 0
var game
var shot := 0
func _btns(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		_btns(c, out)

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
		game.card_overlay.visible = false
		game.encounter_overlay.visible = false
		gs.debug_ranch("open")
		gs.ranch["seen"] = true
		gs.current_region = "ranch_pasture"
		game.rendered_map = ""
		game._refresh()
		gs.debug_ranch_humans(OS.get_environment("KIND"))
		game._process_events()
	if f >= 10 and f % 4 == 2 and shot < 5:
		root.get_viewport().get_texture().get_image().save_png(out + "_%d.png" % shot)
		shot += 1
		var bs: Array = []
		_btns(game.encounter_buttons_box, bs)
		var pick: Button = null
		for b in bs:
			if b.is_visible_in_tree() and not b.disabled:
				pick = b
				break
		if pick == null:
			return true
		print("選：", pick.text)
		pick.pressed.emit()
	return shot >= 5
