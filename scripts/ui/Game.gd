extends Control

const REGION_ORDER := ["forest_north", "forest_east", "forest_west", "forest_south"]
const STAT_KEYS := ["health", "stamina", "hunger", "health_value", "speed", "strength", "skill", "perception"]
const ACTION_ORDER := ["find_tracks", "gather", "find_sleep_spot", "short_rest", "rest_until", "sleep"]
const STATUS_ICON_KINDS := ["injury", "poison", "hunger"]
const LOG_VISIBLE_LINES := 4

var stats_bars: Dictionary = {}
var region_buttons: Dictionary = {}
var action_buttons: Dictionary = {}
var status_icons: Dictionary = {}
var log_box: RichTextLabel
var top_label: Label
var wolf_portrait: AnimatedIcon
var last_rendered_season: String = ""

const WOLF_SHEET_PATH := "res://assets/sprites/wolf_spritesheet.png"
const WOLF_FRAME_SIZE := Vector2i(48, 32)

var encounter_overlay: Panel
var encounter_message: Label
var encounter_sprite: TextureRect
var encounter_buttons_box: HBoxContainer

var hunt_overlay: Panel
var hunt_message: Label
var hunt_sprite: TextureRect
var hunt_buttons_box: VBoxContainer
var current_hunt: HuntSystem = null

var rest_overlay: Panel
var rest_buttons_box: VBoxContainer

var debug_overlay: Panel
var debug_spins: Dictionary = {}

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	GameState.state_changed.connect(_refresh)
	GameState.log_message.connect(_log)
	GameState.wolf_died.connect(_on_wolf_died)
	GameState.encounter_triggered.connect(_on_encounter_triggered)
	GameState.growth_applied.connect(func(): Audio.play_level_up())
	_refresh()
	Audio.play_bgm()
	Audio.play_howl()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.08)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# 整個畫面固定在視窗內（640×360），不用外層捲動，行動紀錄才會一直看得到。
	var root_vbox := VBoxContainer.new()
	root_vbox.anchor_right = 1.0
	root_vbox.anchor_bottom = 1.0
	root_vbox.offset_left = 4
	root_vbox.offset_top = 2
	root_vbox.offset_right = -4
	root_vbox.offset_bottom = -4
	root_vbox.add_theme_constant_override("separation", 2)
	add_child(root_vbox)

	var header_box := HBoxContainer.new()
	root_vbox.add_child(header_box)

	wolf_portrait = AnimatedIcon.new()
	wolf_portrait.custom_minimum_size = Vector2(96, 64)
	wolf_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	wolf_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wolf_portrait.setup(load(WOLF_SHEET_PATH), WOLF_FRAME_SIZE, 0, 4, 5.0)
	header_box.add_child(wolf_portrait)

	var header_text_box := VBoxContainer.new()
	header_text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_text_box.add_theme_constant_override("separation", 0)
	header_box.add_child(header_text_box)

	var top_row := HBoxContainer.new()
	header_text_box.add_child(top_row)

	top_label = Label.new()
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.clip_text = true
	top_row.add_child(top_label)

	var status_row := HBoxContainer.new()
	top_row.add_child(status_row)
	for kind in STATUS_ICON_KINDS:
		var icon_rect := TextureRect.new()
		icon_rect.texture = PixelArt.make_status_icon(kind, Vector2i(16, 16))
		icon_rect.custom_minimum_size = Vector2(20, 20)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.visible = false
		status_row.add_child(icon_rect)
		status_icons[kind] = icon_rect

	var debug_btn := Button.new()
	debug_btn.text = tr("ui.debug")
	debug_btn.pressed.connect(_toggle_debug)
	top_row.add_child(debug_btn)

	var save_quit_btn := Button.new()
	save_quit_btn.text = tr("ui.save_and_exit")
	save_quit_btn.pressed.connect(_on_save_and_exit)
	top_row.add_child(save_quit_btn)

	var stats_box := HBoxContainer.new()
	header_text_box.add_child(stats_box)
	for key in STAT_KEYS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		var l := Label.new()
		l.text = tr("stat." + key)
		col.add_child(l)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = float(GameData.balance.get("hunger_max", 150)) if key == "hunger" else 100.0
		bar.custom_minimum_size = Vector2(0, 12)
		bar.show_percentage = false
		col.add_child(bar)
		stats_box.add_child(col)
		stats_bars[key] = bar

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(middle)

	var map_panel := VBoxContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(map_panel)
	var map_title := Label.new()
	map_title.text = tr("ui.region_map")
	map_panel.add_child(map_title)
	var map_center := CenterContainer.new()
	map_panel.add_child(map_center)
	var map_grid := GridContainer.new()
	map_grid.columns = 2
	map_center.add_child(map_grid)
	for region_id in REGION_ORDER:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(140, 46)
		btn.expand_icon = false
		btn.pressed.connect(_on_region_button.bind(region_id))
		map_grid.add_child(btn)
		region_buttons[region_id] = btn

	# 行動按鈕之後會變多，放在自己的捲動區，不會把行動紀錄擠出畫面。
	var action_scroll := ScrollContainer.new()
	action_scroll.custom_minimum_size = Vector2(280, 0)
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(action_scroll)
	var action_panel := VBoxContainer.new()
	action_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_panel.add_theme_constant_override("separation", 2)
	action_scroll.add_child(action_panel)
	var action_title := Label.new()
	action_title.text = tr("ui.actions")
	action_panel.add_child(action_title)
	var action_grid := GridContainer.new()
	action_grid.columns = 2
	action_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_grid.add_theme_constant_override("h_separation", 2)
	action_grid.add_theme_constant_override("v_separation", 2)
	action_panel.add_child(action_grid)
	for action_id in ACTION_ORDER:
		var btn := Button.new()
		btn.text = tr("action." + action_id)
		btn.custom_minimum_size = Vector2(0, 26)
		btn.pressed.connect(_on_action_button.bind(action_id))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_grid.add_child(btn)
		action_buttons[action_id] = btn

	log_box = RichTextLabel.new()
	# 高度取整數行，避免最上面一行只露出半截。
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0, 0, 0, 0.25)
	log_style.content_margin_left = 4
	log_style.content_margin_right = 4
	log_style.content_margin_top = 2
	log_style.content_margin_bottom = 2
	log_box.add_theme_stylebox_override("normal", log_style)
	var log_font := log_box.get_theme_font("normal_font")
	var log_line_h := log_font.get_height(log_box.get_theme_font_size("normal_font_size")) + log_box.get_theme_constant("line_separation")
	log_box.custom_minimum_size = Vector2(0, log_line_h * LOG_VISIBLE_LINES + 4)
	log_box.scroll_following = true
	log_box.bbcode_enabled = false
	root_vbox.add_child(log_box)

	_build_encounter_overlay()
	_build_hunt_overlay()
	_build_rest_overlay()
	_build_debug_overlay()

# 遭遇、狩獵、休息選單的底色：幾乎不透明，避免和底下的主畫面文字混在一起。
func _overlay_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.06, 0.94)
	return style

func _build_encounter_overlay() -> void:
	encounter_overlay = Panel.new()
	encounter_overlay.visible = false
	encounter_overlay.add_theme_stylebox_override("panel", _overlay_style())
	encounter_overlay.anchor_right = 1.0
	encounter_overlay.anchor_bottom = 1.0
	add_child(encounter_overlay)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	encounter_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	center.add_child(box)
	var sprite_center := CenterContainer.new()
	box.add_child(sprite_center)
	encounter_sprite = TextureRect.new()
	encounter_sprite.custom_minimum_size = Vector2(72, 48)
	encounter_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	encounter_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_center.add_child(encounter_sprite)
	encounter_message = Label.new()
	encounter_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	encounter_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(encounter_message)
	encounter_buttons_box = HBoxContainer.new()
	encounter_buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(encounter_buttons_box)

func _build_hunt_overlay() -> void:
	hunt_overlay = Panel.new()
	hunt_overlay.visible = false
	hunt_overlay.add_theme_stylebox_override("panel", _overlay_style())
	hunt_overlay.anchor_right = 1.0
	hunt_overlay.anchor_bottom = 1.0
	add_child(hunt_overlay)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	hunt_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	center.add_child(box)
	var sprite_center := CenterContainer.new()
	box.add_child(sprite_center)
	hunt_sprite = TextureRect.new()
	hunt_sprite.custom_minimum_size = Vector2(72, 48)
	hunt_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	hunt_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_center.add_child(hunt_sprite)
	hunt_message = Label.new()
	hunt_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hunt_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(hunt_message)
	hunt_buttons_box = VBoxContainer.new()
	box.add_child(hunt_buttons_box)

func _build_rest_overlay() -> void:
	rest_overlay = Panel.new()
	rest_overlay.visible = false
	rest_overlay.add_theme_stylebox_override("panel", _overlay_style())
	rest_overlay.anchor_right = 1.0
	rest_overlay.anchor_bottom = 1.0
	add_child(rest_overlay)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	rest_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(220, 0)
	center.add_child(box)
	var title := Label.new()
	title.text = tr("ui.rest_until.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	rest_buttons_box = VBoxContainer.new()
	box.add_child(rest_buttons_box)
	var cancel_btn := Button.new()
	cancel_btn.text = tr("ui.cancel")
	cancel_btn.pressed.connect(func(): rest_overlay.visible = false)
	box.add_child(cancel_btn)

func _build_debug_overlay() -> void:
	debug_overlay = Panel.new()
	debug_overlay.visible = false
	# 除錯選單蓋住整個畫面，用不透明底色，避免和底下的遊戲畫面混在一起。
	var debug_style := StyleBoxFlat.new()
	debug_style.bg_color = Color(0.06, 0.07, 0.06)
	debug_overlay.add_theme_stylebox_override("panel", debug_style)
	debug_overlay.anchor_right = 1.0
	debug_overlay.anchor_bottom = 1.0
	add_child(debug_overlay)
	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 8
	root.offset_top = 4
	root.offset_right = -8
	root.offset_bottom = -4
	debug_overlay.add_child(root)

	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title := Label.new()
	title.text = tr("ui.debug")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = tr("debug.close")
	close_btn.pressed.connect(_toggle_debug)
	title_row.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	scroll.add_child(columns)

	# 左欄：素質
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	columns.add_child(left)
	left.add_child(_debug_section_label("debug.section.stats"))
	for key in ["health", "stamina", "speed", "strength", "skill", "perception", "hunger", "health_value", "age_years"]:
		var row := HBoxContainer.new()
		left.add_child(row)
		var l := Label.new()
		l.text = tr("debug.age_years") if key == "age_years" else tr("stat." + key)
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 20 if key == "age_years" else (float(GameData.balance.get("hunger_max", 150)) if key == "hunger" else 100)
		spin.step = 0.1 if key == "age_years" else 1
		spin.custom_minimum_size = Vector2(90, 0)
		row.add_child(spin)
		var apply_btn := Button.new()
		apply_btn.text = tr("debug.set")
		apply_btn.pressed.connect(_on_debug_set.bind(key, spin))
		row.add_child(apply_btn)
		debug_spins[key] = spin

	# 右欄：時間、年齡、強制觸發遭遇
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 2)
	columns.add_child(right)
	right.add_child(_debug_section_label("debug.section.time"))
	var time_grid := GridContainer.new()
	time_grid.columns = 2
	right.add_child(time_grid)
	_debug_button(time_grid, tr("debug.skip_day"), func(): GameState.debug_skip_day())
	_debug_button(time_grid, tr("debug.skip_season"), func(): GameState.debug_skip_to_next_season())
	_debug_button(time_grid, tr("debug.add_year"), func(): GameState.debug_add_age(1.0); _sync_debug_spins())
	_debug_button(time_grid, tr("debug.jump_stage").replace("{stage}", tr("stage.adult")),
		func(): GameState.debug_jump_to_stage(Wolf.LifeStage.ADULT); _sync_debug_spins())
	_debug_button(time_grid, tr("debug.jump_stage").replace("{stage}", tr("stage.elder")),
		func(): GameState.debug_jump_to_stage(Wolf.LifeStage.ELDER); _sync_debug_spins())
	_debug_button(right, tr("debug.toggle_time_mode"), func():
		GameTime.time_mode = "test" if GameTime.time_mode == "normal" else "normal"
		_log("time_mode = " + GameTime.time_mode)
	)

	right.add_child(_debug_section_label("debug.section.encounter"))
	var enc_row := HBoxContainer.new()
	right.add_child(enc_row)
	var animal_pick := OptionButton.new()
	for animal_id in GameState.debug_animal_ids():
		animal_pick.add_item(tr("animal." + animal_id))
		animal_pick.set_item_metadata(animal_pick.item_count - 1, animal_id)
	enc_row.add_child(animal_pick)
	var stage_pick := OptionButton.new()
	for stage in ["adult", "juvenile"]:
		stage_pick.add_item(tr("debug.life_stage." + stage))
		stage_pick.set_item_metadata(stage_pick.item_count - 1, stage)
	enc_row.add_child(stage_pick)
	_debug_button(enc_row, tr("debug.trigger"), func():
		_on_debug_force_encounter(
			str(animal_pick.get_item_metadata(animal_pick.selected)),
			str(stage_pick.get_item_metadata(stage_pick.selected)))
	)

func _debug_section_label(key: String) -> Label:
	var l := Label.new()
	l.text = tr(key)
	l.modulate = Color(0.75, 0.85, 0.75)
	return l

func _debug_button(parent: Node, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _on_debug_force_encounter(animal_id: String, life_stage: String) -> void:
	debug_overlay.visible = false
	var result := GameState.debug_force_encounter(animal_id, life_stage)
	if result.get("found", false):
		_show_find_result(result)

func _sync_debug_spins() -> void:
	for key in debug_spins.keys():
		debug_spins[key].value = _get_wolf_stat(key)

func _on_debug_set(key: String, spin: SpinBox) -> void:
	GameState.debug_set_stat(key, spin.value)

func _toggle_debug() -> void:
	debug_overlay.visible = not debug_overlay.visible
	if debug_overlay.visible:
		_sync_debug_spins()

func _get_wolf_stat(key: String) -> float:
	var w: Wolf = GameState.wolf
	match key:
		"health": return w.health
		"stamina": return w.stamina
		"speed": return w.speed
		"strength": return w.strength
		"skill": return w.skill
		"perception": return w.perception
		"hunger": return w.hunger
		"health_value": return w.health_value
		"age_years": return w.age_years
	return 0.0

func _refresh() -> void:
	if GameState.wolf == null:
		return
	var w: Wolf = GameState.wolf
	top_label.text = "%s   %s D%d %s   |   %s" % [
		tr("region." + GameState.current_region),
		tr("season." + GameTime.current_season()),
		GameTime.day,
		tr("period." + GameTime.current_period()),
		tr("stage." + _stage_key(w.life_stage())),
	]
	stats_bars["health"].value = w.health
	stats_bars["stamina"].value = w.stamina
	stats_bars["hunger"].value = w.hunger
	stats_bars["health_value"].value = w.health_value
	stats_bars["speed"].value = w.speed
	stats_bars["strength"].value = w.strength
	stats_bars["skill"].value = w.skill
	stats_bars["perception"].value = w.perception

	var is_elder: bool = w.life_stage() == Wolf.LifeStage.ELDER
	wolf_portrait.modulate = Color(0.82, 0.82, 0.85) if is_elder else Color(1, 1, 1)

	status_icons["injury"].visible = w.injury != Wolf.Injury.NONE
	status_icons["poison"].visible = w.poison_days_remaining > 0
	var hunger_threshold: float = float(GameData.balance.get("hunger_low_threshold", 20))
	status_icons["hunger"].visible = w.hunger <= hunger_threshold

	var season: String = GameTime.current_season()
	if season != last_rendered_season:
		last_rendered_season = season
		for region_id in region_buttons.keys():
			var btn: Button = region_buttons[region_id]
			btn.icon = PixelArt.make_region_tile(region_id, season, Vector2i(18, 18))

	for region_id in region_buttons.keys():
		var btn: Button = region_buttons[region_id]
		var is_adjacent: bool = GameState.adjacent_regions().has(region_id)
		var is_current: bool = region_id == GameState.current_region
		btn.disabled = not is_adjacent or is_current
		var marker: String = " ★" if region_id == GameState.den_region else ""
		var here: String = (" [" + tr("ui.here") + "]") if is_current else ""
		btn.text = tr("region." + region_id) + marker + here

	var available: Array[String] = GameState.available_actions()
	for action_id in action_buttons.keys():
		var btn: Button = action_buttons[action_id]
		btn.visible = available.has(action_id)

func _stage_key(stage: int) -> String:
	match stage:
		Wolf.LifeStage.SUBADULT: return "subadult"
		Wolf.LifeStage.ADULT: return "adult"
		_: return "elder"

func _log(text: String) -> void:
	if text == "":
		return
	log_box.append_text(text + "\n")

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

# --- Region movement ---

func _on_region_button(region_id: String) -> void:
	if region_id == GameState.current_region:
		return
	GameState.action_move(region_id)

# --- Actions ---

func _on_action_button(action_id: String) -> void:
	match action_id:
		"find_tracks":
			var result := GameState.action_find_tracks()
			if result.get("found", false):
				_show_find_result(result)
			else:
				_log(tr("log.find_tracks.fail"))
		"gather":
			var result := GameState.action_gather()
			if result.get("found", false):
				_log(tr("log.gather.success").replace("{item}", tr("item." + str(result["item_id"]))))
			else:
				_log(tr("log.gather.fail"))
		"find_sleep_spot":
			var found := GameState.action_find_sleep_spot()
			_log(tr("log.sleep_spot.success") if found else tr("log.sleep_spot.fail"))
		"short_rest":
			GameState.action_short_rest()
			_log(tr("log.short_rest"))
		"rest_until":
			_show_rest_overlay()
		"sleep":
			GameState.action_sleep()
			_log(tr("log.slept"))

# 依接下來的時段順序列出選項（不含目前時段）。
func _show_rest_overlay() -> void:
	_clear_children(rest_buttons_box)
	var count := GameTime.PERIODS.size()
	for offset in range(1, count):
		var period: String = GameTime.PERIODS[(GameTime.period_index + offset) % count]
		var btn := Button.new()
		btn.text = tr("ui.rest_until.option").replace("{period}", tr("period." + period))
		btn.pressed.connect(_on_rest_until.bind(period))
		rest_buttons_box.add_child(btn)
	rest_overlay.visible = true

func _on_rest_until(period: String) -> void:
	rest_overlay.visible = false
	if GameState.action_rest_until(period):
		_log(tr("log.rest_until").replace("{period}", tr("period." + period)))

func _animal_scale(life_stage: String) -> float:
	return 0.7 if life_stage == "juvenile" else 1.0

func _show_find_result(result: Dictionary) -> void:
	var animal_id: String = result["animal_id"]
	var life_stage: String = result["life_stage"]
	var prey_dir: int = int(result.get("prey_dir", -1))
	var wind_text: String = tr("factor.wind." + str(result.get("wind", "crosswind")))
	_log(tr("log.find_tracks.success") + " " + tr("animal." + animal_id) + "（" + wind_text + "）")
	encounter_message.text = tr("log.find_tracks.success") + "\n" + tr("animal." + animal_id) + "　" + wind_text
	encounter_sprite.texture = PixelArt.make_animal_sprite(animal_id, Vector2i(72, 48), _animal_scale(life_stage))
	_clear_children(encounter_buttons_box)
	var hunt_btn := Button.new()
	hunt_btn.text = tr("ui.hunt")
	hunt_btn.pressed.connect(func():
		encounter_overlay.visible = false
		_begin_hunt(animal_id, life_stage, prey_dir)
	)
	encounter_buttons_box.add_child(hunt_btn)
	var ignore_btn := Button.new()
	ignore_btn.text = tr("ui.ignore")
	ignore_btn.pressed.connect(func(): encounter_overlay.visible = false)
	encounter_buttons_box.add_child(ignore_btn)
	encounter_overlay.visible = true

# --- Hunting ---

func _begin_hunt(animal_id: String, life_stage: String, prey_dir: int = -1) -> void:
	current_hunt = GameState.start_hunt(animal_id, life_stage, prey_dir)
	_render_hunt_stage()

func _render_hunt_stage() -> void:
	if current_hunt == null:
		hunt_overlay.visible = false
		return
	hunt_overlay.visible = true
	_clear_children(hunt_buttons_box)
	var animal_name: String = tr("animal." + current_hunt.animal_id)
	hunt_sprite.texture = PixelArt.make_animal_sprite(current_hunt.animal_id, Vector2i(72, 48), _animal_scale(current_hunt.life_stage))
	var wind_text: String = tr("factor.wind." + current_hunt.wind_state())
	match current_hunt.stage:
		HuntSystem.Stage.DISCOVER:
			hunt_message.text = tr("hunt.stage.discover").replace("{animal}", animal_name) + "　" + wind_text
			_add_hunt_choice(tr("hunt.action.observe"), current_hunt.chance_discover(), func(): _resolve_stage(current_hunt.do_discover()))
		HuntSystem.Stage.STALK:
			hunt_message.text = tr("hunt.stage.stalk").replace("{animal}", animal_name) + "　" + wind_text
			for approach in ["low", "downwind", "wait"]:
				var key: String = "hunt.action.low_approach" if approach == "low" else "hunt.action." + approach
				_add_hunt_choice(tr(key), current_hunt.chance_stalk(approach), func(): _resolve_stage(current_hunt.do_stalk(approach)))
		HuntSystem.Stage.CHASE:
			hunt_message.text = tr("hunt.stage.chase").replace("{animal}", animal_name)
			for tactic in ["sprint", "flank", "drive"]:
				_add_hunt_choice(tr("hunt.action." + tactic), current_hunt.chance_chase(tactic), func(): _resolve_stage(current_hunt.do_chase(tactic)))
		HuntSystem.Stage.FIGHT:
			hunt_message.text = tr("hunt.stage.fight").replace("{animal}", animal_name)
			for move in ["bite_throat", "bite_leg", "pin"]:
				_add_hunt_choice(tr("hunt.action." + move), current_hunt.chance_fight(move), func():
					Audio.play_bite()
					_resolve_stage(current_hunt.do_fight(move))
				)
	_add_hunt_choice(tr("ui.give_up"), {}, func():
		current_hunt.give_up()
		_finish_hunt()
	)

# info 是 HuntSystem.chance_* 的結果：按鈕顯示成功率，下方列出關鍵因素。
func _add_hunt_choice(label: String, info: Dictionary, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	if info.has("chance"):
		btn.text += "　%d%%" % int(round(float(info["chance"]) * 100.0))
	btn.pressed.connect(callback)
	hunt_buttons_box.add_child(btn)
	if info.has("factors"):
		var factor_label := Label.new()
		factor_label.text = _format_factors(info["factors"])
		factor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		factor_label.add_theme_font_size_override("font_size", 12)
		factor_label.modulate = Color(0.8, 0.85, 0.8)
		hunt_buttons_box.add_child(factor_label)

# 感知越高，列出的因素越多（2 個，感知達門檻時 3 個）。
func _format_factors(factors: Array) -> String:
	var cfg: Dictionary = GameData.balance.get("factor_display", {})
	var count: int = int(cfg.get("base_count", 2))
	if GameState.wolf.perception >= float(cfg.get("extra_count_perception", 55)):
		count += 1
	var main: Array = []
	var info: Array = []
	for f in factors:
		(info if f.get("info", false) else main).append(f)
	var parts: Array[String] = []
	for f in HuntSystem.top_factors(main, count) + info:
		var text: String = tr(str(f["key"])).replace("{n}", str(f.get("n", "")))
		parts.append(text if f.get("info", false) else text + (" ✓" if f["good"] else " ✗"))
	return "　".join(parts)

func _resolve_stage(stage_result: Dictionary) -> void:
	GameState.spend_hunt_turns(int(stage_result.get("turns", 0)))
	var animal_name: String = tr("animal." + current_hunt.animal_id)
	if stage_result.get("wind_shifted", false):
		_log(tr("log.wind_shifted").replace("{wind}", tr("factor.wind." + current_hunt.wind_state())))
	var text_key: String = stage_result.get("text_key", "")
	if text_key != "":
		_log(tr(text_key))
	var reason_key: String = stage_result.get("reason_key", "")
	if reason_key != "":
		_log(tr(reason_key).replace("{animal}", animal_name))
	if current_hunt.stage == HuntSystem.Stage.DONE:
		_finish_hunt()
	else:
		_render_hunt_stage()

func _finish_hunt() -> void:
	var succeeded: bool = current_hunt.result == HuntSystem.Result.SUCCESS
	GameState.finish_hunt(current_hunt)
	if succeeded:
		_log(tr("hunt.result.success").replace("{animal}", tr("animal." + current_hunt.animal_id)))
	else:
		_log(tr("hunt.result.fail"))
	hunt_overlay.visible = false
	current_hunt = null
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)

# --- Competitor encounters ---

func _on_encounter_triggered(encounter: Dictionary) -> void:
	var animal_id: String = encounter.get("animal_id", "")
	var life_stage: String = encounter.get("life_stage", "adult")
	_log(tr("encounter.competitor").replace("{animal}", tr("animal." + animal_id)))
	encounter_message.text = tr("encounter.competitor").replace("{animal}", tr("animal." + animal_id))
	encounter_sprite.texture = PixelArt.make_animal_sprite(animal_id, Vector2i(72, 48), _animal_scale(life_stage))
	_clear_children(encounter_buttons_box)
	var fight_btn := Button.new()
	fight_btn.text = tr("ui.fight")
	fight_btn.pressed.connect(func(): _resolve_encounter("fight", encounter))
	encounter_buttons_box.add_child(fight_btn)
	var retreat_btn := Button.new()
	retreat_btn.text = tr("ui.retreat")
	retreat_btn.pressed.connect(func(): _resolve_encounter("retreat", encounter))
	encounter_buttons_box.add_child(retreat_btn)
	encounter_overlay.visible = true

func _resolve_encounter(choice: String, encounter: Dictionary) -> void:
	var result := GameState.resolve_competitor_encounter(choice, encounter)
	var animal_id: String = encounter.get("animal_id", "")
	match result.get("outcome", ""):
		"win":
			_log(tr("encounter.result.win").replace("{animal}", tr("animal." + animal_id)))
		"lose":
			_log(tr("encounter.result.lose").replace("{animal}", tr("animal." + animal_id)))
		"retreat":
			_log(tr("encounter.result.retreat"))
	encounter_overlay.visible = false
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)

# --- Lifecycle ---

func _on_wolf_died(_cause: String) -> void:
	get_tree().change_scene_to_file("res://scenes/LifeSummary.tscn")

func _on_save_and_exit() -> void:
	SaveSystem.save_game()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
