extends SceneTree
# 選單式狩獵的畫面檢查（Phase 4a 第 3 步，家畜）：開主遊戲、關掉開局卡片、對 ANIMAL／STAGE 出手，
# 每一步按成功率最高的選項（沒有百分比就按第一個、不放棄）並截圖（最多 6 張），印出畫面上看得到的文字裡有沒有原始翻譯鍵。
# 用法：ANIMAL=cattle STAGE=buck OUT=<輸出路徑前綴> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/hunt_menu_shot.gd
var f := 0
var game
var shot := 0
func _texts(n: Node, out: Array) -> void:
	if n is Label or n is Button or n is RichTextLabel:
		if n.is_visible_in_tree():
			out.append(str(n.text))
	for c in n.get_children():
		_texts(c, out)

func _buttons(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
		_buttons(c, out)

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
		game._begin_hunt(OS.get_environment("ANIMAL"), OS.get_environment("STAGE"))
	if f >= 10 and f % 4 == 2 and shot < 6:
		root.get_viewport().get_texture().get_image().save_png(out + "_%d.png" % shot)
		shot += 1
		var texts: Array = []
		_texts(game, texts)
		for t in texts:
			var re := RegEx.new()
			re.compile("[a-z_]+\\\\.[a-z_.]+")
			if re.search(t) != null:
				print("可能的原始鍵：", t)
		var best: Button = null
		var best_p := -1
		var btns: Array = []
		_buttons(game.hunt_buttons_box, btns)
		for b in btns:
			if not b.disabled and b.is_visible_in_tree():
				var m := RegEx.new()
				m.compile("(\\\\d+)%")
				var r := m.search(b.text)
				var p: int = int(r.get_string(1)) if r != null else 0
				if p > best_p:
					best_p = p
					best = b
		if best == null or best_p <= 0:
			for b in btns:
				if not b.disabled and b.is_visible_in_tree() and not str(b.text).begins_with("放棄"):
					best = b
					break
		if best != null:
			print("選：", best.text)
			best.pressed.emit()
		elif not game.hunt_overlay.visible:
			return true
	return shot >= 6
