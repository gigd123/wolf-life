extends Control

const REGION_ORDER := ["forest_north", "forest_east", "forest_west", "forest_south"]
const STAT_KEYS := ["health", "stamina", "hunger", "health_value", "speed", "strength", "skill"]
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
		bar.max_value = 100
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

func _build_encounter_overlay() -> void:
	encounter_overlay = Panel.new()
	encounter_overlay.visible = false
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
	debug_overlay.anchor_right = 1.0
	debug_overlay.anchor_bottom = 1.0
	add_child(debug_overlay)
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(40, 40)
	debug_overlay.add_child(vbox)
	var title := Label.new()
	title.text = tr("ui.debug")
	vbox.add_child(title)
	for key in ["health", "stamina", "speed", "strength", "skill", "hunger", "health_value", "age_years"]:
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var l := Label.new()
		l.text = key
		l.custom_minimum_size = Vector2(100, 0)
		row.add_child(l)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 100 if key != "age_years" else 20
		spin.step = 0.1 if key == "age_years" else 1
		spin.custom_minimum_size = Vector2(100, 0)
		row.add_child(spin)
		var apply_btn := Button.new()
		apply_btn.text = "Set"
		apply_btn.pressed.connect(_on_debug_set.bind(key, spin))
		row.add_child(apply_btn)
		debug_spins[key] = spin

	var skip_day_btn := Button.new()
	skip_day_btn.text = "Skip Day"
	skip_day_btn.pressed.connect(func(): GameState.debug_skip_day())
	vbox.add_child(skip_day_btn)

	var skip_season_btn := Button.new()
	skip_season_btn.text = "Skip Season"
	skip_season_btn.pressed.connect(func(): GameState.debug_skip_to_next_season())
	vbox.add_child(skip_season_btn)

	var time_mode_btn := Button.new()
	time_mode_btn.text = "Toggle Time Mode (normal/test)"
	time_mode_btn.pressed.connect(func():
		GameTime.time_mode = "test" if GameTime.time_mode == "normal" else "normal"
		_log("time_mode = " + GameTime.time_mode)
	)
	vbox.add_child(time_mode_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_toggle_debug)
	vbox.add_child(close_btn)

func _on_debug_set(key: String, spin: SpinBox) -> void:
	GameState.debug_set_stat(key, spin.value)

func _toggle_debug() -> void:
	debug_overlay.visible = not debug_overlay.visible
	if debug_overlay.visible:
		for key in debug_spins.keys():
			debug_spins[key].value = _get_wolf_stat(key)

func _get_wolf_stat(key: String) -> float:
	var w: Wolf = GameState.wolf
	match key:
		"health": return w.health
		"stamina": return w.stamina
		"speed": return w.speed
		"strength": return w.strength
		"skill": return w.skill
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
	_log(tr("log.find_tracks.success") + " " + tr("animal." + animal_id))
	encounter_message.text = tr("log.find_tracks.success") + "\n" + tr("animal." + animal_id)
	encounter_sprite.texture = PixelArt.make_animal_sprite(animal_id, Vector2i(72, 48), _animal_scale(life_stage))
	_clear_children(encounter_buttons_box)
	var hunt_btn := Button.new()
	hunt_btn.text = tr("ui.hunt")
	hunt_btn.pressed.connect(func():
		encounter_overlay.visible = false
		_begin_hunt(animal_id, life_stage)
	)
	encounter_buttons_box.add_child(hunt_btn)
	var ignore_btn := Button.new()
	ignore_btn.text = tr("ui.ignore")
	ignore_btn.pressed.connect(func(): encounter_overlay.visible = false)
	encounter_buttons_box.add_child(ignore_btn)
	encounter_overlay.visible = true

# --- Hunting ---

func _begin_hunt(animal_id: String, life_stage: String) -> void:
	current_hunt = GameState.start_hunt(animal_id, life_stage)
	_render_hunt_stage()

func _render_hunt_stage() -> void:
	if current_hunt == null:
		hunt_overlay.visible = false
		return
	hunt_overlay.visible = true
	_clear_children(hunt_buttons_box)
	var animal_name: String = tr("animal." + current_hunt.animal_id)
	hunt_sprite.texture = PixelArt.make_animal_sprite(current_hunt.animal_id, Vector2i(72, 48), _animal_scale(current_hunt.life_stage))
	match current_hunt.stage:
		HuntSystem.Stage.DISCOVER:
			hunt_message.text = tr("hunt.stage.discover").replace("{animal}", animal_name)
			_add_hunt_choice(tr("hunt.action.observe"), func(): _resolve_stage(current_hunt.do_discover()))
		HuntSystem.Stage.STALK:
			hunt_message.text = tr("hunt.stage.stalk").replace("{animal}", animal_name)
			_add_hunt_choice(tr("hunt.action.low_approach"), func(): _resolve_stage(current_hunt.do_stalk("low")))
			_add_hunt_choice(tr("hunt.action.downwind"), func(): _resolve_stage(current_hunt.do_stalk("downwind")))
			_add_hunt_choice(tr("hunt.action.wait"), func(): _resolve_stage(current_hunt.do_stalk("wait")))
		HuntSystem.Stage.CHASE:
			hunt_message.text = tr("hunt.stage.chase").replace("{animal}", animal_name)
			_add_hunt_choice(tr("hunt.action.sprint"), func(): _resolve_stage(current_hunt.do_chase("sprint")))
			_add_hunt_choice(tr("hunt.action.flank"), func(): _resolve_stage(current_hunt.do_chase("flank")))
			_add_hunt_choice(tr("hunt.action.drive"), func(): _resolve_stage(current_hunt.do_chase("drive")))
		HuntSystem.Stage.FIGHT:
			hunt_message.text = tr("hunt.stage.fight").replace("{animal}", animal_name)
			_add_hunt_choice(tr("hunt.action.bite_throat"), func():
				Audio.play_bite()
				_resolve_stage(current_hunt.do_fight("bite_throat"))
			)
			_add_hunt_choice(tr("hunt.action.bite_leg"), func():
				Audio.play_bite()
				_resolve_stage(current_hunt.do_fight("bite_leg"))
			)
			_add_hunt_choice(tr("hunt.action.pin"), func():
				Audio.play_bite()
				_resolve_stage(current_hunt.do_fight("pin"))
			)
	_add_hunt_choice(tr("ui.give_up"), func():
		current_hunt.give_up()
		_finish_hunt()
	)

func _add_hunt_choice(label: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(callback)
	hunt_buttons_box.add_child(btn)

func _resolve_stage(stage_result: Dictionary) -> void:
	var text_key: String = stage_result.get("text_key", "")
	if text_key != "":
		_log(tr(text_key))
	if current_hunt.stage == HuntSystem.Stage.DONE:
		_finish_hunt()
	else:
		_render_hunt_stage()

func _finish_hunt() -> void:
	if current_hunt.result == HuntSystem.Result.SUCCESS:
		GameState.resolve_hunt_success(current_hunt.animal_id, current_hunt.life_stage)
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
