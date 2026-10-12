extends Control

# 開局：先選地圖（出身），再選第一個巢穴（Phase 2 第 7 步：開局選地圖，各有小小的開局加成，見 balance.start_map）。
const MAPS := ["forest", "tundra", "mountain", "grassland"]

var grid: GridContainer
var map_desc: Label
var map_buttons: Dictionary = {}

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
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var title := Label.new()
	title.text = tr("den.select_map_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var map_center := CenterContainer.new()
	vbox.add_child(map_center)
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 6)
	map_center.add_child(map_row)
	for map_id in MAPS:
		var mb := Button.new()
		mb.text = tr("map." + map_id)
		mb.toggle_mode = true
		mb.custom_minimum_size = Vector2(110, 32)
		mb.pressed.connect(_show_map.bind(map_id))
		map_row.add_child(mb)
		map_buttons[map_id] = mb

	map_desc = Label.new()
	map_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_desc.custom_minimum_size = Vector2(560, 0)
	var desc_center := CenterContainer.new()
	desc_center.add_child(map_desc)
	vbox.add_child(desc_center)

	var sub_title := Label.new()
	sub_title.text = tr("den.select_title")
	sub_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub_title)

	var center := CenterContainer.new()
	vbox.add_child(center)
	grid = GridContainer.new()
	grid.columns = 2
	center.add_child(grid)
	_show_map("forest")

func _show_map(map_id: String) -> void:
	for id in map_buttons.keys():
		map_buttons[id].button_pressed = id == map_id
	map_desc.text = tr("den.map." + map_id + ".desc")
	for c in grid.get_children():
		c.queue_free()
	for region_id in GameData.map_regions(map_id):
		if not bool(GameData.regions().get(region_id, {}).get("can_den", false)):
			continue
		var btn := Button.new()
		# 固定寬度、文字換行：兩欄要放進 640 寬（2026-10-13 xvfb 量到說明長的地圖寬 736）
		btn.custom_minimum_size = Vector2(300, 80)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.text = tr("region." + str(region_id)) + "\n" + tr("den." + str(region_id) + ".desc")
		var tile: Texture2D = ArtLibrary.icon("region_tile." + str(region_id))
		btn.icon = tile if tile != null else PixelArt.make_region_tile(str(region_id), "spring", Vector2i(40, 40))
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.expand_icon = false
		btn.pressed.connect(_on_pick.bind(str(region_id)))
		grid.add_child(btn)

func _on_pick(region_id: String) -> void:
	GameState.new_game(region_id)
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
