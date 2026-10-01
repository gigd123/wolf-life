extends Control

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)

	var log_data: Dictionary = GameState.life_log
	var wolf: Wolf = GameState.wolf

	var sprite_center := CenterContainer.new()
	box.add_child(sprite_center)
	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(96, 64)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frame_atlas := AtlasTexture.new()
	frame_atlas.atlas = load("res://assets/sprites/wolf_spritesheet.png")
	frame_atlas.region = Rect2(0, 0, 48, 32)
	sprite.texture = frame_atlas
	sprite.modulate = Color(0.8, 0.8, 0.8, 0.9)
	sprite_center.add_child(sprite)

	var title := Label.new()
	title.text = tr("summary.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	_add_line(box, tr("summary.days_lived").replace("{days}", str(int(log_data.get("days_lived", 0)))))
	if wolf != null:
		_add_line(box, tr("summary.age").replace("{age}", "%.1f" % wolf.age_years))
	_add_line(box, tr("summary.death_cause").replace("{cause}", tr("death." + str(log_data.get("death_cause", "unknown")))))

	var regions_visited: Array = log_data.get("regions_visited", [])
	_add_line(box, tr("summary.regions_visited").replace("{count}", str(regions_visited.size())))

	var prey_count: Dictionary = log_data.get("prey_count", {})
	var total_prey := 0
	for v in prey_count.values():
		total_prey += int(v)
	_add_line(box, tr("summary.prey_total").replace("{count}", str(total_prey)))

	var biggest: String = str(log_data.get("biggest_prey", ""))
	if biggest != "":
		_add_line(box, tr("summary.biggest_prey").replace("{animal}", tr("animal." + biggest)))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(spacer)

	var restart_btn := Button.new()
	restart_btn.text = tr("summary.new_life")
	restart_btn.pressed.connect(func():
		SaveSystem.delete_save()
		get_tree().change_scene_to_file("res://scenes/DenSelect.tscn")
	)
	box.add_child(restart_btn)

	var menu_btn := Button.new()
	menu_btn.text = tr("menu.main_menu")
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	box.add_child(menu_btn)

func _add_line(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
