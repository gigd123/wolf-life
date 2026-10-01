extends Control

const REGIONS := ["forest_east", "forest_north", "forest_south", "forest_west"]

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.06)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	var title := Label.new()
	title.text = tr("den.select_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var center := CenterContainer.new()
	vbox.add_child(center)

	var grid := GridContainer.new()
	grid.columns = 2
	center.add_child(grid)

	for region_id in REGIONS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(220, 80)
		btn.text = tr("region." + region_id) + "\n" + tr("den." + region_id + ".desc")
		btn.icon = PixelArt.make_region_tile(region_id, "spring", Vector2i(40, 40))
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.expand_icon = false
		btn.pressed.connect(_on_pick.bind(region_id))
		grid.add_child(btn)

func _on_pick(region_id: String) -> void:
	GameState.new_game(region_id)
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
