extends Control

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.06)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	center.add_child(box)

	var title := Label.new()
	title.text = "Timberline"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("game.subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(spacer)

	var new_game_btn := Button.new()
	new_game_btn.text = tr("menu.new_game")
	new_game_btn.pressed.connect(_on_new_game)
	box.add_child(new_game_btn)

	var continue_btn := Button.new()
	continue_btn.text = tr("menu.continue")
	continue_btn.disabled = not SaveSystem.has_save()
	continue_btn.pressed.connect(_on_continue)
	box.add_child(continue_btn)

	var quit_btn := Button.new()
	quit_btn.text = tr("menu.quit")
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

	var visual_test_spacer := Control.new()
	visual_test_spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(visual_test_spacer)

	var visual_test_btn := Button.new()
	visual_test_btn.text = "3D Visual Test (prototype)"
	visual_test_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://prototypes/visual_test/VisualTest.tscn"))
	box.add_child(visual_test_btn)

func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/DenSelect.tscn")

func _on_continue() -> void:
	if SaveSystem.load_game():
		# 死亡時已經存檔；若當時沒切到一生回顧（例如程式出錯），繼續時直接進一生回顧。
		if GameState.wolf != null and not GameState.wolf.alive:
			get_tree().change_scene_to_file("res://scenes/LifeSummary.tscn")
			return
		get_tree().change_scene_to_file("res://scenes/Game.tscn")
