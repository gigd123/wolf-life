extends Control

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = UiTheme.color("screen_bg_menu")
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
	title.theme_type_variation = &"MenuTitle"
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
	visual_test_spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(visual_test_spacer)

	# 測試與原型的入口：小按鈕排成兩欄（2026-11-12，五個一排排下去會超出 640×360 的畫面，ui_check OFFSCREEN）
	var tests := GridContainer.new()
	tests.columns = 2
	tests.add_theme_constant_override("h_separation", 6)
	tests.add_theme_constant_override("v_separation", 4)
	box.add_child(tests)

	# 美術測試（插畫風與像素風的比較場景，prototypes/art_test/；和遊戲進度無關）
	var art_test_btn := Button.new()
	art_test_btn.text = tr("menu.art_test")
	art_test_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://prototypes/art_test/ArtTest.tscn"))
	art_test_btn.theme_type_variation = &"SmallButton"
	art_test_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tests.add_child(art_test_btn)

	# 戰術狩獵原型（prototypes/tactical_hunt/；和遊戲進度無關，docs/proposals/tactical-hunt-prototype.md）
	var tactical_btn := Button.new()
	tactical_btn.text = tr("menu.tactical_hunt")
	tactical_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://prototypes/tactical_hunt/TacticalHunt.tscn"))
	tactical_btn.theme_type_variation = &"SmallButton"
	tactical_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tests.add_child(tactical_btn)

	# 戰術戰鬥原型（prototypes/tactical_combat/，docs/proposals/tactical-combat-prototype.md；和遊戲進度無關）
	var tcombat_btn := Button.new()
	tcombat_btn.text = tr("menu.tactical_combat")
	tcombat_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://prototypes/tactical_combat/TacticalCombat.tscn"))
	tcombat_btn.theme_type_variation = &"SmallButton"
	tcombat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tests.add_child(tcombat_btn)

	# HD-2D 戰術場景測試（prototypes/hd2d_tactical/，2026-11-04；和遊戲進度無關）
	var hd2d_btn := Button.new()
	hd2d_btn.text = tr("menu.hd2d_test")
	hd2d_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://prototypes/hd2d_tactical/HD2DTactical.tscn"))
	hd2d_btn.theme_type_variation = &"SmallButton"
	hd2d_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tests.add_child(hd2d_btn)

	# 森林大火逃生地圖的原型（Phase 2n 第 1 步；和遊戲進度無關）
	var fire_btn := Button.new()
	fire_btn.text = tr("menu.fire_escape")
	fire_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://prototypes/fire_escape/FireEscape.tscn"))
	fire_btn.theme_type_variation = &"SmallButton"
	fire_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tests.add_child(fire_btn)

	var visual_test_btn := Button.new()
	visual_test_btn.text = tr("menu.visual_test")
	visual_test_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://prototypes/visual_test/VisualTest.tscn"))
	visual_test_btn.theme_type_variation = &"SmallButton"
	visual_test_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tests.add_child(visual_test_btn)

func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/DenSelect.tscn")

func _on_continue() -> void:
	if SaveSystem.load_game():
		# 死亡時已經存檔；若當時沒切到一生回顧（例如程式出錯），繼續時直接進一生回顧。
		if GameState.wolf != null and not GameState.wolf.alive:
			get_tree().change_scene_to_file("res://scenes/LifeSummary.tscn")
			return
		get_tree().change_scene_to_file("res://scenes/Game.tscn")
