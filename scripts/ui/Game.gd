extends Control

const REGION_ORDER := ["forest_north", "forest_east", "forest_west", "forest_south"]
const STAT_KEYS := ["health", "stamina", "hunger", "health_value", "speed", "strength", "skill", "perception"]
const FIRE_TINT := Color(1.0, 0.62, 0.45) # 正在燒的區域：原本的背景加火光
const ACTION_ORDER := ["explore", "explore_modes", "routine", "gather", "find_sleep_spot", "short_rest", "rest_until", "sleep", "return_to_carcass", "eat_cache", "make_den", "mark", "howl", "regurgitate", "lie_down"]
const STATUS_ICON_KINDS := ["injury", "burn", "frostbite", "poison", "hunger", "cold", "gorged"]
const LOG_VISIBLE_LINES := 4

var stats_bars: Dictionary = {}
var stats_labels: Dictionary = {}
var portrait_stage: String = "?"
var region_buttons: Dictionary = {}
# 地圖按鈕的四個位置：依目前所在的大地圖（森林、苔原）換成那張地圖的區域（1.6 第 6 步）。
var map_slots: Array[Button] = []
var map_title: Label
var cross_map_box: HFlowContainer
var rendered_map: String = ""
var action_buttons: Dictionary = {}
var explore_hint_label: Label
var status_icons: Dictionary = {}
var snow_icon: TextureRect # 雪況圖示（2026-10-13）
var sleeping_now: bool = false # 睡覺結算期間（QA-70）
var woken_encounter: Dictionary = {}
var stamina_icon: TextureRect = null # 有圖示時取代文字
var stamina_warning: Label # 頂部「體力不支」（QA-55；最低體力的規則在 1.7 定）
var pack_label: Label # 頂部「伴侶同行」（Phase 3 第 3 步）
var pack_btn: Button # 「狼群」面板（有伴侶之後才出現）
var log_box: RichTextLabel

# 行動訊息（試玩回饋後的改版）：
# - 主畫面的紀錄一次行動一段（main_entries），最新一段亮、舊的變暗；「紀錄」按鈕看完整歷史。
# - 遭遇、狩獵、戰鬥畫面下方有「這場遭遇的紀錄」（session）：每個選擇一段，戰鬥與多回合追擊加上編號。
#   遭遇結束時先在畫面上交代結果、按「繼續」才關掉；主畫面的紀錄只留總結。
var main_entries: Array = [] # [{"time": String, "lines": Array}]
var restored_messages: Array = [] # 讀檔前存下的訊息，接在這次的訊息前面寫回試玩紀錄（QA-74）
var main_entry_open: bool = false
var session_active: bool = false
var session_entries: Array = [] # [{"label": String, "num": int, "lines": Array}]
var session_results: Array[String] = [] # 要留在主畫面總結裡的句子（狩獵與戰鬥的結果、學到的知識）
var session_check_pending: bool = false
var session_result_mode: bool = false
var encounter_strip: RichTextLabel
var hunt_strip: RichTextLabel
var last_injury_sig: String = "" # 受傷提示：上次看到的傷勢（嚴重度|能力）
var choice_label_regex: RegEx
const MAIN_LOG_SHOWN := 30
const MAIN_LOG_KEEP := 400
const STRIP_LINES := 3
# 紀錄的文字色（theme.tres 的 Palette）
var LOG_COLOR_NEW := UiTheme.html("log_new")
var LOG_COLOR_OLD := UiTheme.html("log_old")
var LOG_COLOR_LABEL := UiTheme.html("log_label")
var top_label: Label
var stage_label: Label
var wolf_portrait: AnimatedIcon
var last_rendered_season: String = ""

var region_bg: TextureRect
var encounter_bg: TextureRect
var hunt_bg: TextureRect
var hunt_wolf_sprite: AnimatedIcon

var encounter_overlay: Panel
var encounter_message: Label
var encounter_sprite: AnimatedIcon
var encounter_buttons_box: HFlowContainer
var encounter_detail: Label

var region_info_overlay: Panel
var region_info_text: RichTextLabel

var hunt_overlay: Panel
var hunt_message: Label
var hunt_sprite: AnimatedIcon
var hunt_buttons_box: VBoxContainer
var current_hunt: HuntSystem = null
# 戰鬥模式（1.6 第 3 步）：和狩獵共用同一個畫面（hunt_overlay）。
var current_combat: Combat = null
var combat_notes: Array[String] = []
var combat_intro: String = "" # 戰鬥畫面第一次顯示時，開頭寫出怎麼打起來的（被驚醒、被撞倒）
var level_up_pending: bool = false # 睡覺時長了能力：音效等睡醒卡片（或換季卡片）出現時才播（試玩回報 14）
var combat_wolf_pose: String = "threaten"
var combat_anim: CombatAnimator # 1.9 第 2 步：戰鬥回合的補間動畫
var combat_anim_btn: Button # 動畫速度切換，固定在戰鬥畫面右上角（不占選項列的高度）
# 狩獵、戰鬥畫面照比例顯示（2026-10-13）：灰狼 32 像素高的格子 = hunt_unit_h，對手乘上自己的 display_scale
var hunt_unit_h: float = 40.0
var hunt_opp_scale: float = 1.0
var hunt_opp_frame: Vector2 = Vector2(48, 32)
var combat_opp_action: String = "idle"

var rest_overlay: Panel
var rest_buttons_box: VBoxContainer

var rain: CPUParticles2D
var snow: CPUParticles2D # 苔原的暴風雪、白矇天
var _knowledge_buffer: Array[String] = [] # 這次行動學到的知識，行動的訊息寫完後再補上
var _found_intro: String = "" # 跟著渡鴉發現殘骸的句子，殘骸旁有搶食者時一起放在字卡上（QA-43）

var debug_overlay: Panel
var debug_spins: Dictionary = {}

# 轉變與回饋提示（SPEC 1.6）：全畫面卡片（季節、換日摘要、傾向）、不擋操作的淡入提示、頂部的傾向按鈕。
var card_overlay: Panel
var card_bg: TextureRect
var card_title: Label
var card_wolf: AnimatedIcon
var card_body: RichTextLabel
var card_buttons_box: HBoxContainer
var toast: RichTextLabel
var toast_tween: Tween
var tendency_button: Button

# 除錯「模擬到死亡」
var auto_player: AutoPlayer = null
var auto_status: Label
var npc_status: Label
const AUTO_DAYS_PER_FRAME := 2
# 除錯「跳到次成年期最後一天」的玩法：[名稱, 獵物偏好, 打法]（見 AutoPlayer）
const DEBUG_GROWTH_PROFILES := [["average", "all", "average"], ["pursuit", "all", "pursuit"], ["assault", "all", "assault"],
	["stealth", "all", "stealth"], ["cautious", "all", "cautious"], ["small_only", "small_only", "average"]]

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	# 任何畫面關掉時都接著處理排隊的事件（2026-10-15 試玩回報 16、17：進食結束、離開等 9 處只關畫面、
	# 沒有 _refresh，字卡要等到下一個行動才出現）。_process_events 自己會檢查還有沒有畫面開著。
	for overlay in [encounter_overlay, hunt_overlay, rest_overlay, region_info_overlay, card_overlay, debug_overlay]:
		overlay.visibility_changed.connect(func(): if not overlay.visible: _process_events.call_deferred())
	restored_messages =GameState.life_log.get("recent_messages", []).duplicate()
	GameState.state_changed.connect(_refresh)
	GameState.log_message.connect(_log)
	GameState.wolf_died.connect(_on_wolf_died)
	GameState.encounter_triggered.connect(_on_encounter_triggered)
	GameState.growth_applied.connect(func(): if not GameState.auto_playing: level_up_pending = true)
	# 學到的知識等這次行動的訊息（例如探索的發現）寫完再補上，順序才是「看到 → 學到」（QA-39）
	GameState.knowledge_learned.connect(func(entry):
		_knowledge_buffer.append(tr("log.knowledge_learned") + _knowledge_text(entry))
		_flush_knowledge.call_deferred())
	GameTime.day_changed.connect(func(_d): _show_day_toast.call_deferred())
	_refresh()
	Audio.play_bgm()
	Audio.play_howl()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.color("screen_bg")
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	# 區域背景（依季節換圖、依時段調色），上面蓋一層暗色讓文字好讀
	region_bg = _make_background_rect()
	add_child(region_bg)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, float(GameData.art.get("background_dim", 0.45)))
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

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

	# 狼的頭像，下面是生命階段（放在頂部列會被狩獵傾向、狀態圖示擠掉）
	var portrait_box := VBoxContainer.new()
	portrait_box.add_theme_constant_override("separation", 0)
	header_box.add_child(portrait_box)
	wolf_portrait = AnimatedIcon.new()
	wolf_portrait.custom_minimum_size = Vector2(96, 40)
	wolf_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	wolf_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not ArtLibrary.setup_wolf(wolf_portrait, "idle"):
		wolf_portrait.show_static(PixelArt.make_animal_sprite("gray_wolf"))
	portrait_box.add_child(wolf_portrait)
	stage_label = Label.new()
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.theme_type_variation = &"StageLabel"
	portrait_box.add_child(stage_label)

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

	# 目前的主要狩獵傾向，點了打開說明面板
	tendency_button = Button.new()
	tendency_button.flat = true
	tendency_button.visible = false
	tendency_button.expand_icon = false
	# 狀態圖示多的時候文字會被截掉、只剩圖示（點了照樣打開說明），頂部列才不會把整個畫面撐出 640（ui_check OFFSCREEN）
	tendency_button.clip_text = true
	tendency_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tendency_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tendency_button.size_flags_stretch_ratio = 0.6
	tendency_button.pressed.connect(_show_tendency_panel)
	top_row.add_child(tendency_button)

	var status_row := HBoxContainer.new()
	top_row.add_child(status_row)
	for kind in STATUS_ICON_KINDS:
		var icon_rect := TextureRect.new()
		var status_tex: Texture2D = ArtLibrary.icon("status." + kind)
		icon_rect.texture = status_tex if status_tex != null else PixelArt.make_status_icon(kind, Vector2i(16, 16))
		icon_rect.custom_minimum_size = Vector2(20, 20)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.visible = false
		icon_rect.mouse_filter = Control.MOUSE_FILTER_PASS
		# 點傷勢圖示：彈出傷勢資訊（QA-44，Phase 2 第 7 步）
		if kind in ["injury", "burn", "frostbite"]:
			icon_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			icon_rect.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_show_injury_info())
		status_row.add_child(icon_rect)
		status_icons[kind] = icon_rect
	# 雪況圖示：淺雪、深雪、硬雪殼；滑鼠移上去寫雪況與對狩獵的影響
	snow_icon = TextureRect.new()
	snow_icon.custom_minimum_size = Vector2(20, 20)
	snow_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	snow_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	snow_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	snow_icon.visible = false
	status_row.add_child(snow_icon)
	# 有「體力不支」圖示（status.exhausted）就用圖示，沒有就用文字
	var exhausted_tex: Texture2D = ArtLibrary.icon("status.exhausted")
	if exhausted_tex != null:
		var ex_icon := TextureRect.new()
		ex_icon.texture = exhausted_tex
		# 16×16 的圖放大兩倍顯示，旁邊照樣寫「體力不支」（1.7 試玩：圖太小、看不懂）
		ex_icon.custom_minimum_size = Vector2(28, 28)
		ex_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ex_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ex_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ex_icon.tooltip_text = tr("ui.stamina_low.tip")
		ex_icon.mouse_filter = Control.MOUSE_FILTER_PASS
		ex_icon.visible = false
		status_row.add_child(ex_icon)
		stamina_icon = ex_icon
	stamina_warning = Label.new()
	stamina_warning.text = tr("ui.stamina_low")
	stamina_warning.tooltip_text = tr("ui.stamina_low.tip")
	stamina_warning.mouse_filter = Control.MOUSE_FILTER_PASS
	stamina_warning.theme_type_variation = &"WarningLabel"
	stamina_warning.visible = false
	status_row.add_child(stamina_warning)
	pack_label = Label.new()
	pack_label.text = tr("ui.pack.following")
	pack_label.tooltip_text = tr("ui.pack.following.tip")
	pack_label.mouse_filter = Control.MOUSE_FILTER_PASS
	pack_label.visible = false
	status_row.add_child(pack_label)

	pack_btn = Button.new()
	pack_btn.text = tr("ui.pack")
	pack_btn.pressed.connect(_show_pack_panel)
	pack_btn.visible = false
	top_row.add_child(pack_btn)

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
		stats_labels[key] = l
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

	# 地圖也放在自己的捲動區：跨地圖、冰面捷徑的按鈕變多時只在這裡捲動，
	# 不會撐高中間區域、把底部的行動紀錄擠出視窗。
	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(map_scroll)
	var map_panel := VBoxContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.add_theme_constant_override("separation", 2)
	map_scroll.add_child(map_panel)
	var map_title_row := HBoxContainer.new()
	map_panel.add_child(map_title_row)
	map_title = Label.new()
	map_title.text = tr("ui.region_map")
	map_title_row.add_child(map_title)
	var region_info_btn := Button.new()
	region_info_btn.text = tr("ui.region_info")
	region_info_btn.pressed.connect(_show_region_info)
	map_title_row.add_child(region_info_btn)
	var knowledge_btn := Button.new()
	knowledge_btn.text = tr("ui.knowledge")
	knowledge_btn.pressed.connect(_show_knowledge)
	map_title_row.add_child(knowledge_btn)
	var history_btn := Button.new()
	history_btn.text = tr("ui.log_history")
	history_btn.pressed.connect(_show_log_history)
	map_title_row.add_child(history_btn)
	var map_center := CenterContainer.new()
	map_panel.add_child(map_center)
	var map_grid := GridContainer.new()
	map_grid.columns = 2
	map_center.add_child(map_grid)
	for i in 4:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 40)
		# 標記變多時不要撐寬地圖（超出的字截掉）
		btn.clip_text = true
		btn.expand_icon = false
		btn.pressed.connect(_on_map_slot.bind(i))
		map_grid.add_child(btn)
		map_slots.append(btn)
	# 跨地圖的移動（例如森林北部 → 苔原）
	cross_map_box = HFlowContainer.new()
	cross_map_box.alignment = FlowContainer.ALIGNMENT_CENTER
	map_panel.add_child(cross_map_box)

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
		# 長的按鈕字（「回到獵物殘骸（剩 N 段）」）截成「…」，不撐寬行動欄、把畫面推出 640（ui_check OFFSCREEN）；完整的字在滑鼠提示
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.tooltip_text = btn.text
		btn.pressed.connect(_on_action_button.bind(action_id))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_grid.add_child(btn)
		action_buttons[action_id] = btn
	# 「確定」的獵物出沒知識：在行動按鈕下面寫明這次探索發現某種獵物的機率
	explore_hint_label = Label.new()
	explore_hint_label.theme_type_variation = &"HintLabel"
	explore_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_panel.add_child(explore_hint_label)

	log_box = RichTextLabel.new()
	# 高度取整數行，避免最上面一行只露出半截。
	log_box.theme_type_variation = &"LogBox"
	var log_font := log_box.get_theme_font("normal_font")
	var log_line_h := log_font.get_height(log_box.get_theme_font_size("normal_font_size")) + log_box.get_theme_constant("line_separation")
	log_box.custom_minimum_size = Vector2(0, log_line_h * LOG_VISIBLE_LINES + 4)
	log_box.scroll_following = true
	log_box.bbcode_enabled = true
	root_vbox.add_child(log_box)
	choice_label_regex = RegEx.new()
	# 選項名稱後面的機率（「（35%）」「　成功率 41%」）不寫進紀錄
	choice_label_regex.compile("[（(][^（()）]*%[^（()）]*[）)]|[　 ]+[^　 ]*\\s*\\d+%$")

	_build_encounter_overlay()
	_build_hunt_overlay()
	_build_rest_overlay()
	_build_region_info_overlay()
	_build_rain()
	_build_snow()
	_build_card_overlay()
	_build_toast()
	_build_debug_overlay()

# --- 美術（data/art.json；找不到圖時退回 PixelArt 程式生成的佔位圖） ---

func _make_background_rect(overlay: bool = false) -> TextureRect:
	var rect := TextureRect.new()
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if overlay:
		# 選單底下的地形背景調暗，文字才看得清楚
		var d: float = 1.0 - float(GameData.art.get("overlay_background_dim", 0.4))
		rect.self_modulate = Color(d, d, d, 1.0)
	return rect

# fit_height > 0：縮放到固定高度（狩獵畫面，排版穩定）；0：用原始像素大小顯示
# （遭遇畫面；遠處的灰熊就會比較小，像素比例也和主畫面的狼一致）。
func _make_creature_icon(fit_height: int = 0) -> AnimatedIcon:
	var icon := AnimatedIcon.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if fit_height > 0:
		icon.custom_minimum_size = Vector2(fit_height * 1.8, fit_height)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	else:
		icon.custom_minimum_size = Vector2(48, 32)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	return icon

func _set_creature(icon: AnimatedIcon, animal_id: String, life_stage: String, action: String = "idle", animate: bool = true) -> void:
	if not ArtLibrary.setup_animal(icon, animal_id, life_stage, action, animate):
		var fallback_id: String = "gray_wolf" if animal_id == "stranger_wolf" else animal_id # 狼獾、渡鴉的美術之後補上，先用程式佔位
		icon.show_static(PixelArt.make_animal_sprite(fallback_id, Vector2i(72, 48), _animal_scale(life_stage)))

# animate = false：回合之間的靜止畫面，不播多格動畫（戰鬥動畫播完後重繪時不要再播一次）
func _set_wolf_pose(icon: AnimatedIcon, pose: String, animate: bool = true) -> void:
	var stage: String = _wolf_stage_key()
	# 有正式的多格動畫就用（1.9 第 4 步）
	if animate and ArtLibrary.setup_wolf_strip(icon, pose, stage):
		return
	# 繞圈小跑只有多格動畫，沒有素材時用閃避的單張
	if pose == "circle":
		pose = "dodge"
	# 走路、嚎叫在 spritesheet 裡（wolf_sheet 的列），其他姿勢是單張
	if pose in ["walk", "howl"]:
		if ArtLibrary.setup_wolf(icon, pose, 8.0 if pose == "walk" else 4.0, stage):
			return
	var tex: Texture2D = ArtLibrary.wolf_pose(pose, stage)
	if tex != null:
		icon.show_static(tex)
	elif not ArtLibrary.setup_wolf(icon, "idle", 5.0, stage):
		icon.show_static(PixelArt.make_animal_sprite("gray_wolf"))

func _set_terrain_bg(rect: TextureRect, terrain: String) -> void:
	var burn: String = GameState.burn_state(GameState.current_region)
	rect.texture = ArtLibrary.terrain_background(terrain, GameTime.current_season(), burn == "ash") if terrain != "" else null
	# 正在燒：原本的地形加火光（燒完才是焦黑）
	if burn == "burning":
		rect.modulate = FIRE_TINT
	elif rect.modulate == FIRE_TINT:
		rect.modulate = Color.WHITE

# 遭遇、狩獵、休息選單的底色：幾乎不透明，避免和底下的主畫面文字混在一起。
func _build_encounter_overlay() -> void:
	encounter_overlay = Panel.new()
	encounter_overlay.visible = false
	encounter_overlay.theme_type_variation = &"OverlayPanel"
	encounter_overlay.anchor_right = 1.0
	encounter_overlay.anchor_bottom = 1.0
	add_child(encounter_overlay)
	encounter_bg = _make_background_rect(true)
	encounter_overlay.add_child(encounter_bg)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	encounter_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)
	var sprite_center := CenterContainer.new()
	box.add_child(sprite_center)
	encounter_sprite = _make_creature_icon()
	sprite_center.add_child(encounter_sprite)
	encounter_message = Label.new()
	encounter_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	encounter_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(encounter_message)
	# 按鈕多時自動換行（例如大火的逃生選項、遇上陌生灰狼的四個選擇）
	encounter_buttons_box = HFlowContainer.new()
	encounter_buttons_box.alignment = FlowContainer.ALIGNMENT_CENTER
	encounter_buttons_box.add_theme_constant_override("h_separation", 4)
	encounter_buttons_box.add_theme_constant_override("v_separation", 4)
	box.add_child(encounter_buttons_box)
	encounter_detail = Label.new()
	encounter_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	encounter_detail.theme_type_variation = &"DetailLabel"
	box.add_child(encounter_detail)
	encounter_strip = _make_session_strip()
	box.add_child(encounter_strip)

func _build_hunt_overlay() -> void:
	hunt_overlay = Panel.new()
	hunt_overlay.visible = false
	hunt_overlay.theme_type_variation = &"OverlayPanel"
	hunt_overlay.anchor_right = 1.0
	hunt_overlay.anchor_bottom = 1.0
	add_child(hunt_overlay)
	hunt_bg = _make_background_rect(true)
	hunt_overlay.add_child(hunt_bg)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	hunt_overlay.add_child(center)
	var box := VBoxContainer.new()
	# 固定寬度：選項列的代價、因素文字不能把面板撐出 640（2026-10-13 xvfb 量到戰鬥畫面寬 753）
	box.custom_minimum_size = Vector2(600, 0)
	center.add_child(box)
	var sprite_center := CenterContainer.new()
	box.add_child(sprite_center)
	# 左邊是狼（依階段換姿勢），右邊是獵物
	var sprite_row := HBoxContainer.new()
	sprite_row.add_theme_constant_override("separation", 24)
	sprite_center.add_child(sprite_row)
	hunt_wolf_sprite = _make_creature_icon(40)
	sprite_row.add_child(hunt_wolf_sprite)
	hunt_sprite = _make_creature_icon(40)
	sprite_row.add_child(hunt_sprite)
	# 照比例顯示：固定像素倍率、底部對齊（_set_hunt_sprite_height 依版面調整）
	hunt_wolf_sprite.zoom = 40.0 / 32.0
	hunt_sprite.zoom = 40.0 / 32.0
	combat_anim = CombatAnimator.new()
	add_child(combat_anim)
	combat_anim.wolf_icon = hunt_wolf_sprite
	combat_anim.opp_icon = hunt_sprite
	combat_anim.set_wolf_pose = func(pose: String): _set_wolf_pose(hunt_wolf_sprite, pose)
	combat_anim.set_opp_action = func(action: String):
		if current_combat != null:
			_set_creature(hunt_sprite, current_combat.animal_id, current_combat.life_stage, action)
	hunt_message = Label.new()
	hunt_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hunt_message.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(hunt_message)
	hunt_buttons_box = VBoxContainer.new()
	hunt_buttons_box.add_theme_constant_override("separation", 3)
	box.add_child(hunt_buttons_box)
	hunt_strip = _make_session_strip()
	box.add_child(hunt_strip)
	# 動畫速度（一般／快／略過），按一下切換；播放中按一下略過
	combat_anim_btn = Button.new()
	combat_anim_btn.flat = true
	combat_anim_btn.visible = false
	combat_anim_btn.theme_type_variation = &"SmallButton"
	combat_anim_btn.anchor_left = 1.0
	combat_anim_btn.anchor_right = 1.0
	combat_anim_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	combat_anim_btn.offset_right = -4
	combat_anim_btn.offset_top = 2
	combat_anim_btn.pressed.connect(func():
		if combat_anim.playing:
			combat_anim.skip()
			return
		combat_anim_btn.text = tr("combat.anim." + CombatAnimator.next_mode()))
	hunt_overlay.add_child(combat_anim_btn)

func _build_rest_overlay() -> void:
	rest_overlay = Panel.new()
	rest_overlay.visible = false
	rest_overlay.theme_type_variation = &"OverlayPanel"
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
	debug_overlay.theme_type_variation = &"DebugPanel"
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

	# 兩欄各自捲動：右欄很長，捲到下面時左欄的素質不會跟著捲走、留下一片空白
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)
	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(left_scroll)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(right_scroll)

	# 左欄：素質
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left_scroll.add_child(left)
	left.add_child(_debug_section_label("debug.section.stats"))
	for key in ["health", "health_max", "stamina", "speed", "strength", "skill", "perception", "hunger", "health_value", "age_years"]:
		var row := HBoxContainer.new()
		left.add_child(row)
		var l := Label.new()
		l.text = tr("debug.age_years") if key == "age_years" else tr("stat." + key)
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		var spin := SpinBox.new()
		spin.min_value = 0
		# 血量會超過 100（血量上限成長），兩格都用血量上限的潛力上限，避免顯示被截在 100
		var health_cap: float = float(GameData.balance.get("growth", {}).get("potential", {}).get("max", {}).get("health_max", 120))
		spin.max_value = 20 if key == "age_years" else (float(GameData.balance.get("hunger_max", 150)) if key == "hunger" else (health_cap if key in ["health", "health_max"] else 100))
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
	right_scroll.add_child(right)
	right.add_child(_debug_section_label("debug.section.time"))
	var time_grid := GridContainer.new()
	time_grid.columns = 2
	right.add_child(time_grid)
	_debug_button(time_grid, tr("debug.skip_day"), func(): GameState.debug_skip_day())
	_debug_button(time_grid, tr("debug.skip_season"), func(): GameState.debug_skip_to_next_season())
	_debug_button(time_grid, tr("debug.skip_dry"), func(): GameState.debug_skip_to_dry_season(); _sync_debug_spins())
	_debug_button(time_grid, tr("debug.add_year"), func(): GameState.debug_add_age(1.0); _sync_debug_spins())
	_debug_button(time_grid, tr("debug.jump_stage").replace("{stage}", tr("stage.adult")),
		func(): GameState.debug_jump_to_stage(Wolf.LifeStage.ADULT); _sync_debug_spins())
	_debug_button(time_grid, tr("debug.jump_elder_eve"),
		func(): GameState.debug_jump_to_elder_eve(); _sync_debug_spins())
	# 驗收用（2026-10-16）：年輕的狼現身（老年才有）、直接結束這一生看「最後」字卡
	_debug_button(time_grid, tr("debug.challenger"), func():
		if GameState.wolf.life_stage() != Wolf.LifeStage.ELDER:
			_log(tr("debug.challenger.not_elder"))
			return
		debug_overlay.visible = false
		GameState._ensure_challenger()
		var d := {"kind": "challenger", "location": "", "first": int(GameState.life_log.get("challenger_visits", 0)) == 0,
			"territory": GameState.is_own_territory()}
		GameState.current_discovery = d
		_show_challenger(d, false))
	_debug_button(time_grid, tr("debug.end_life"), func():
		debug_overlay.visible = false
		GameState.debug_end_life("old_age"))
	_debug_button(right, tr("debug.toggle_time_mode"), func():
		GameTime.time_mode = "test" if GameTime.time_mode == "normal" else "normal"
		_log("time_mode = " + GameTime.time_mode)
	)

	right.add_child(_debug_section_label("debug.section.encounter"))
	var enc_row := _debug_row()
	right.add_child(enc_row)
	var animal_pick := OptionButton.new()
	for animal_id in GameState.debug_animal_ids():
		animal_pick.add_item(tr("animal." + animal_id))
		animal_pick.set_item_metadata(animal_pick.item_count - 1, animal_id)
	enc_row.add_child(animal_pick)
	var stage_pick := OptionButton.new()
	for stage in ["adult", "juvenile", "buck"]:
		stage_pick.add_item(tr("debug.life_stage." + stage))
		stage_pick.set_item_metadata(stage_pick.item_count - 1, stage)
	enc_row.add_child(stage_pick)
	_debug_button(enc_row, tr("debug.trigger"), func():
		_on_debug_force_encounter(
			str(animal_pick.get_item_metadata(animal_pick.selected)),
			str(stage_pick.get_item_metadata(stage_pick.selected)))
	)
	# 1.5 新事件（其餘在各自步驟完成後再接上）
	var event_row := _debug_row()
	right.add_child(event_row)
	_debug_button(event_row, tr("debug.event.bear_distant"), func():
		debug_overlay.visible = false
		_show_distant({"encountered": true, "animal_id": "grizzly_bear", "life_stage": "adult", "distant": true})
	)
	_debug_button(event_row, tr("debug.event.stranger_distant"), func():
		debug_overlay.visible = false
		_show_distant({"encountered": true, "animal_id": "stranger_wolf", "life_stage": "adult", "distant": true})
	)
	var event_row2 := _debug_row()
	right.add_child(event_row2)
	_debug_button(event_row2, tr("debug.event.storm"), func():
		debug_overlay.visible = false
		GameState.start_storm()
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.howl"), func():
		debug_overlay.visible = false
		GameState.trigger_howl()
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.driven_off"), func():
		debug_overlay.visible = false
		GameState.pending_events.append({"type": "driven_off"})
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.pack_meet"), func():
		debug_overlay.visible = false
		GameState.debug_pack_meet()
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.pack_remains"), func():
		debug_overlay.visible = false
		GameState.debug_pack_remains()
		_show_discovery(GameState.current_discovery)
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.neighbor_meet"), func():
		debug_overlay.visible = false
		GameState.debug_neighbor_meet()
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.she_wolf"), func():
		debug_overlay.visible = false
		GameState.debug_she_wolf()
		_show_discovery(GameState.current_discovery)
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.she_wolf_closer"), func():
		debug_overlay.visible = false
		GameState.debug_she_wolf_closer()
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.salmon"), func():
		debug_overlay.visible = false
		GameState.debug_salmon()
		_show_discovery(GameState.current_discovery)
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.ranch_clues"), func():
		debug_overlay.visible = false
		GameState.debug_ranch("clues")
		_log(tr("debug.ranch.done").replace("{state}", tr("debug.ranch.clues")).replace("{a}", tr("region." + str(GameState.ranch_linked_regions()[0]))).replace("{b}", tr("region." + str(GameState.ranch_linked_regions()[1]))))
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.ranch_open"), func():
		debug_overlay.visible = false
		GameState.debug_ranch("open")
		_log(tr("debug.ranch.done").replace("{state}", tr("debug.ranch.open")).replace("{a}", tr("region." + str(GameState.ranch_linked_regions()[0]))).replace("{b}", tr("region." + str(GameState.ranch_linked_regions()[1]))))
		rendered_map = ""
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.ranch_attention"), func():
		debug_overlay.visible = false
		GameState.ranch["attention"] = minf(100.0, GameState.ranch_attention() + 20.0)
		_log(tr("debug.ranch.attention").replace("{n}", str(roundi(GameState.ranch_attention()))).replace("{act}", str(snappedf(GameState.ranch_activity(), 0.01))))
		_refresh()
	)
	for hk in ["patrol", "warning", "hunt"]:
		var k: String = hk
		_debug_button(event_row2, tr("debug.event.ranch_" + k), func():
			debug_overlay.visible = false
			GameState.debug_ranch_humans(k)
			_refresh()
			_process_events()
		)
	# 在放牧地吃一歲牛吃到一半，巡查的人過來（Phase 4a 第 7 步：事件結局矩陣走得到這條路）
	_debug_button(event_row2, tr("debug.event.ranch_eating"), func():
		debug_overlay.visible = false
		GameState.debug_ranch_eating()
		rendered_map = ""
		_refresh()
		_show_scavenger("ranch_patrol", false)
	)
	_debug_button(event_row2, tr("debug.event.lynx_kill"), func():
		debug_overlay.visible = false
		GameState.debug_lynx_kill()
		_show_discovery(GameState.current_discovery)
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.small_pounce"), func():
		debug_overlay.visible = false
		GameState.debug_small_pounce()
		_show_discovery(GameState.current_discovery)
		_refresh()
	)
	_debug_button(event_row2, tr("debug.event.pack_young"), func():
		debug_overlay.visible = false
		GameState.debug_pack_meet("young")
		_refresh()
	)
	var event_row3 := _debug_row()
	right.add_child(event_row3)
	_debug_button(event_row3, tr("debug.event.prey_nearby"), func():
		debug_overlay.visible = false
		GameState.debug_prey_nearby()
		_refresh()
	)
	_debug_button(event_row3, tr("debug.event.bear_passing"), func():
		debug_overlay.visible = false
		GameState.pending_events.append({"type": "bear_passing", "health": 0.0, "stamina": 0.0})
		_refresh()
	)
	# 成長（1.6 第 2 步）：模擬一段次成年期、強制轉變卡片、匯出試玩紀錄
	right.add_child(_debug_section_label("debug.section.growth"))
	var growth_row := _debug_row()
	right.add_child(growth_row)
	var profile_pick := OptionButton.new()
	for prof in DEBUG_GROWTH_PROFILES:
		profile_pick.add_item(tr("debug.profile." + str(prof[0])))
	growth_row.add_child(profile_pick)
	_debug_button(growth_row, tr("debug.jump_subadult_end"), func():
		var prof: Array = DEBUG_GROWTH_PROFILES[profile_pick.selected]
		_start_auto_to_adult(str(prof[1]), str(prof[2]))
	)
	var growth_row2 := _debug_row()
	right.add_child(growth_row2)
	_debug_button(growth_row2, tr("debug.force_adult"), func():
		debug_overlay.visible = false
		GameState.debug_force_transition("adult")
	)
	_debug_button(growth_row2, tr("debug.force_elder"), func():
		debug_overlay.visible = false
		GameState.debug_force_transition("elder")
	)
	_debug_button(growth_row2, tr("debug.export_log"), func():
		var path: String = GameState.debug_export_playtest_log()
		auto_status.text = tr("debug.exported").replace("{path}", path)
		_log(auto_status.text)
	)

	# 模擬到死亡（1.6 第 1 步，驗收 1.5 的「兩隻風格相反的狼」）
	right.add_child(_debug_section_label("debug.section.auto"))
	var auto_row := _debug_row()
	right.add_child(auto_row)
	var den_pick := OptionButton.new()
	for region_id in REGION_ORDER:
		if EncounterSystem.region_data(region_id).get("can_den", false):
			den_pick.add_item(tr("region." + region_id))
			den_pick.set_item_metadata(den_pick.item_count - 1, region_id)
	auto_row.add_child(den_pick)
	var prey_pick := OptionButton.new()
	for p in ["small_only", "deer_focus"]:
		prey_pick.add_item(tr("debug.auto.prey." + p))
		prey_pick.set_item_metadata(prey_pick.item_count - 1, p)
	auto_row.add_child(prey_pick)
	var style_pick := OptionButton.new()
	for st in ["cautious", "assault"]:
		style_pick.add_item(tr("debug.auto.style." + st))
		style_pick.set_item_metadata(style_pick.item_count - 1, st)
	auto_row.add_child(style_pick)
	_debug_button(auto_row, tr("debug.auto.start"), func():
		_start_auto_play(str(den_pick.get_item_metadata(den_pick.selected)),
			str(prey_pick.get_item_metadata(prey_pick.selected)), str(style_pick.get_item_metadata(style_pick.selected)))
	)
	auto_status = Label.new()
	auto_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	right.add_child(auto_status)
	# 戰鬥（1.6 第 3 步）
	var combat_row := _debug_row()
	right.add_child(combat_row)
	_debug_button(combat_row, tr("debug.event.fox_scavenge"), func():
		debug_overlay.visible = false
		GameState.start_feeding("white_tailed_deer", "adult", "stream")
		_show_scavenger("fox", false)
	)
	_debug_button(combat_row, tr("debug.event.mother_bear"), func():
		debug_overlay.visible = false
		GameState.identify("grizzly_bear")
		_on_encounter_triggered({"encountered": true, "animal_id": "grizzly_bear", "life_stage": "adult", "mother": true})
	)
	# 森林大火（1.6 第 5 步）：指定起火區域
	var fire_row := _debug_row()
	right.add_child(fire_row)
	var fire_pick := OptionButton.new()
	fire_pick.add_item(tr("debug.fire.random"))
	fire_pick.set_item_metadata(0, "")
	for region_id in REGION_ORDER:
		fire_pick.add_item(tr("region." + region_id))
		fire_pick.set_item_metadata(fire_pick.item_count - 1, region_id)
	fire_row.add_child(fire_pick)
	_debug_button(fire_row, tr("debug.fire.start"), func():
		debug_overlay.visible = false
		GameState.debug_start_fire(str(fire_pick.get_item_metadata(fire_pick.selected)))
		_refresh()
	)
	# 苔原的事件（1.6 第 6d 步）
	var tundra_row := _debug_row()
	right.add_child(tundra_row)
	_debug_button(tundra_row, tr("debug.tundra.blizzard"), func():
		debug_overlay.visible = false
		GameState.debug_start_blizzard()
		_refresh()
	)
	_debug_button(tundra_row, tr("debug.tundra.wolverine"), func():
		debug_overlay.visible = false
		GameState.debug_wolverine_feed()
		_show_scavenger("wolverine", false)
	)
	_debug_button(tundra_row, tr("debug.tundra.ravens"), func():
		debug_overlay.visible = false
		GameState.debug_ravens()
		_refresh()
	)
	_debug_button(tundra_row, tr("debug.tundra.whiteout"), func():
		debug_overlay.visible = false
		GameState.debug_whiteout()
		_refresh()
	)
	_debug_button(tundra_row, tr("debug.tundra.ice"), func():
		debug_overlay.visible = false
		GameState.debug_ice_break()
		_refresh()
	)
	# 苔原狼（1.6 第 6e 步）
	var tundra_wolf_row := _debug_row()
	right.add_child(tundra_wolf_row)
	_debug_button(tundra_wolf_row, tr("debug.tundra_wolf.meet"), func():
		debug_overlay.visible = false
		_show_tundra_meet(GameState.debug_tundra_meet())
	)
	_debug_button(tundra_wolf_row, tr("debug.tundra_wolf.mob"), func():
		debug_overlay.visible = false
		_show_tundra_mob(GameState.debug_tundra_mob())
	)
	_debug_button(tundra_wolf_row, tr("debug.tundra_wolf.howl"), func():
		debug_overlay.visible = false
		GameState.debug_tundra_howl()
		_refresh()
	)
	_debug_button(tundra_wolf_row, tr("debug.tundra_wolf.hunt"), func():
		debug_overlay.visible = false
		_show_tundra_hunt(GameState.debug_tundra_hunt())
	)
	_debug_button(tundra_wolf_row, tr("debug.tundra_wolf.follow"), func():
		debug_overlay.visible = false
		current_hunt = GameState.debug_tundra_follow()
		_enter_hunt()
	)
	_debug_button(tundra_wolf_row, tr("debug.tundra_wolf.carcass"), func():
		debug_overlay.visible = false
		GameState.debug_tundra_wolves_here()
		GameState.start_feeding("caribou", "adult", "open_tundra")
		_show_scavenger("tundra_wolves", false)
	)
	var stranger_row := _debug_row()
	right.add_child(stranger_row)
	_debug_button(stranger_row, tr("debug.event.stranger_meet"), func():
		debug_overlay.visible = false
		GameState.debug_unlock_stranger()
		_show_stranger_meet({"location": ""})
	)
	_debug_button(stranger_row, tr("debug.event.stranger_confront"), func():
		debug_overlay.visible = false
		GameState.debug_unlock_stranger()
		_show_stranger_confront()
	)
	npc_status = Label.new()
	npc_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	npc_status.theme_type_variation = &"SmallLabel"
	right.add_child(npc_status)
	_debug_button(combat_row, tr("debug.event.old_injury"), func():
		debug_overlay.visible = false
		GameState.debug_old_injury_flare()
	)
	_debug_button(right, tr("debug.playtest_stats"), func():
		debug_overlay.visible = false
		_show_playtest_stats()
	)
	_debug_button(event_row3, tr("debug.event.bear_scavenge"), func():
		debug_overlay.visible = false
		GameState.start_feeding("white_tailed_deer", "adult", "stream")
		_show_scavenger("bear", false)
	)

# 右欄的一列按鈕：放不下時自動換行，不會把右欄撐寬到視窗外。
func _debug_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 2)
	row.add_theme_constant_override("v_separation", 2)
	return row

func _debug_section_label(key: String) -> Label:
	var l := Label.new()
	l.text = tr(key)
	l.theme_type_variation = &"MutedLabel"
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
	# 陌生灰狼的狀態（試玩時判斷「現在挑戰還是等牠變老」用）
	var npc := GameState.stranger()
	if npc_status != null and npc != null:
		npc_status.text = tr("debug.npc_status").replace("{age}", "%.2f" % npc.age_years) \
			.replace("{stats}", "　".join(["speed", "strength", "skill", "perception"].map(func(k): return tr("stat." + k) + " %d" % int(npc.get(k)))) \
				+ "　" + tr("stat.health") + " %d／%d" % [int(npc.health), int(npc.health_max)]) \
			.replace("{state}", ("" if npc.alive else tr("debug.npc_dead") + " ") + tr("region." + npc.territory) + " " + str(npc.dominance))

func _on_debug_set(key: String, spin: SpinBox) -> void:
	GameState.debug_set_stat(key, spin.value)

func _toggle_debug() -> void:
	debug_overlay.visible = not debug_overlay.visible
	if debug_overlay.visible:
		_sync_debug_spins()

func _get_wolf_stat(key: String) -> float:
	var w: Wolf = GameState.wolf
	match key:
		"health": return _shown_health(w)
		"health_max": return round(w.health_max)
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
	if GameState.wolf == null or GameState.auto_playing:
		return
	var w: Wolf = GameState.wolf
	# 換季到期、還沒睡覺換季時顯示「冬末」，不顯示超過一季天數的日期（SPEC「季節轉換」）
	var season_text: String = tr("season." + GameTime.current_season())
	season_text = tr("ui.season_end").replace("{season}", season_text) if GameTime.season_due() else "%s D%d" % [season_text, GameTime.day]
	top_label.text = "%s  %s %s%s" % [
		tr("region." + GameState.current_region),
		season_text,
		tr("period." + GameTime.current_period()),
		_weather_text(),
	]
	top_label.tooltip_text = top_label.text
	stage_label.text = tr("stage." + _stage_key(w.life_stage()))
	# 目前的主要狩獵方式（按鈕，點了看說明）
	var tendency: Dictionary = GameState.current_tendency()
	tendency_button.visible = not tendency.is_empty()
	if not tendency.is_empty():
		tendency_button.text = tr("tendency." + str(tendency["type"]))
		tendency_button.tooltip_text = tendency_button.text
		tendency_button.icon = ArtLibrary.icon("tendency." + str(tendency["type"]))
	rain.emitting = GameState.weather == "storm" and not GameState.blizzard_here()
	snow.emitting = GameState.blizzard_here() or GameState.whiteout_here()
	snow.amount = 400 if GameState.blizzard_here() else 160
	# 燒完一片焦黑時換成燒毀的區域背景（art.json 的 region@burned）；正在燒時用原本的背景加火光，
	# 不然還在燒的區域看起來像已經燒完（試玩 BUG-07、08）
	var here_burn: String = GameState.burn_state(GameState.current_region)
	region_bg.texture = ArtLibrary.region_background(GameState.current_region, "burned" if here_burn == "ash" else GameTime.current_season())
	region_bg.modulate = ArtLibrary.period_tint(GameTime.current_period()) * (FIRE_TINT if here_burn == "burning" else Color.WHITE)
	_process_events.call_deferred()
	# 血量顯示「血量 72／90」，條的上限是血量上限（SPEC 1.6「血量上限成為能力值」）
	stats_bars["health"].max_value = w.health_max
	stats_bars["health"].value = w.health
	stats_labels["health"].text = tr("ui.stat_with_max").replace("{name}", tr("stat.health")) \
		.replace("{value}", str(_shown_health(w))).replace("{max}", str(int(round(w.health_max))))
	stats_bars["stamina"].value = w.stamina
	stats_bars["hunger"].value = w.hunger
	stats_bars["health_value"].value = w.health_value
	stats_bars["speed"].value = w.speed
	stats_bars["strength"].value = w.strength
	stats_bars["skill"].value = w.skill
	stats_bars["perception"].value = w.perception

	# 成年、老年換外貌（data/art.json 的 wolf.stages）
	var stage_key: String = _wolf_stage_key()
	if stage_key != portrait_stage:
		portrait_stage = stage_key
		if not ArtLibrary.setup_wolf(wolf_portrait, "idle", 5.0, stage_key):
			wolf_portrait.show_static(PixelArt.make_animal_sprite("gray_wolf"))

	var burned: bool = w.injury != Wolf.Injury.NONE and w.injury_source == "fire"
	var frostbitten: bool = w.injury != Wolf.Injury.NONE and w.injury_source == "blizzard"
	status_icons["injury"].visible = w.injury != Wolf.Injury.NONE and not burned and not frostbitten
	# 滑鼠移到傷勢圖示上：影響哪項能力、還要幾天（血量睡覺會回來，傷勢要時間才會好）
	var injury_tip: String = _injury_effect_text(w) if w.injury != Wolf.Injury.NONE else ""
	for kind in ["injury", "burn", "frostbite"]:
		status_icons[kind].tooltip_text = injury_tip
	_check_new_injury(w)
	status_icons["burn"].visible = burned
	status_icons["frostbite"].visible = frostbitten
	status_icons["poison"].visible = w.poison_days_remaining > 0
	var hunger_threshold: float = float(GameData.balance.get("hunger_low_threshold", 20))
	status_icons["hunger"].visible = w.hunger <= hunger_threshold
	status_icons["cold"].visible = GameState.is_freezing()
	# 吃撐（Phase 2b 第 1 步）：滑鼠移上去寫效果
	status_icons["gorged"].visible = w.is_overfed()
	status_icons["gorged"].tooltip_text = tr("status.gorged.tip")
	var snow_state: String = GameState.snow_state()
	var snow_tex: Texture2D = ArtLibrary.icon("snow." + snow_state) if snow_state != "none" else null
	snow_icon.visible = snow_tex != null
	if snow_tex != null:
		snow_icon.texture = snow_tex
		snow_icon.tooltip_text = tr("snow." + snow_state) + "\n" + tr("snow.tip." + snow_state)
	var low_stamina: bool = w.stamina <= float(GameData.balance.get("stamina_low_threshold", 10))
	stamina_warning.visible = low_stamina
	pack_btn.visible = not GameState.pack_members().is_empty()
	pack_label.visible = GameState.mate_follows_here()
	if stamina_icon != null:
		stamina_icon.visible = low_stamina

	var season: String = GameTime.current_season()
	var map_id: String = GameState.current_map()
	if season != last_rendered_season or map_id != rendered_map:
		last_rendered_season = season
		rendered_map = map_id
		map_title.text = tr(str(GameData.maps().get(map_id, {}).get("name_key", "ui.region_map")))
		region_buttons = {}
		var layout: Array = GameData.map_regions(map_id)
		for i in map_slots.size():
			var btn: Button = map_slots[i]
			btn.visible = i < layout.size()
			if i < layout.size():
				region_buttons[str(layout[i])] = btn
				btn.icon = _region_tile(str(layout[i]), season)
	_clear_children(cross_map_box)
	for link in GameData.links_from(GameState.current_region):
		var target: String = str(link["to"])
		var go := Button.new()
		go.text = tr("ui.go_map").replace("{map}", tr(str(GameData.maps().get(GameData.map_of(target), {}).get("name_key", "")))) \
			.replace("{n}", str(int(link["turns"])))
		go.pressed.connect(_on_region_button.bind(target))
		cross_map_box.add_child(go)
	# 冬春的冰面捷徑：走過那種冰之後才直接顯示冰厚、冰薄；之前要先踩上去試，由玩家判斷
	for ice in GameState.ice_shortcuts():
		var ice_target: String = str(ice["to"])
		var ice_btn := Button.new()
		var known: bool = GameState.ice_known(bool(ice["thin"]))
		ice_btn.text = tr("ui.ice_path" + (".known" if known else "")).replace("{region}", tr("region." + ice_target)) \
			.replace("{n}", str(int(ice["turns"]))).replace("{state}", tr("ice.state." + ("thin" if ice["thin"] else "solid")))
		if known:
			ice_btn.pressed.connect(func(): _on_region_button(ice_target, true))
		else:
			ice_btn.pressed.connect(func(): _show_ice_feel(ice))
		cross_map_box.add_child(ice_btn)

	for region_id in region_buttons.keys():
		var btn: Button = region_buttons[region_id]
		var is_adjacent: bool = GameState.adjacent_regions().has(region_id)
		var is_current: bool = region_id == GameState.current_region
		btn.disabled = not is_adjacent or is_current
		var marker: String = " ★" if region_id == GameState.den_region else ""
		var unknown: String = "" if GameState.is_region_visited(region_id) else " " + tr("ui.unknown")
		var danger: String = " ⚠" if not GameState.known_dangers(region_id, GameTime.current_season()).is_empty() else ""
		var burn: String = GameState.burn_state(region_id)
		if burn == "regrowth" and GameState.regrowth_late(region_id):
			burn = "regrown"
		# 火況只用一個字標在名稱後（「新綠」兩個字會擠掉名稱），說明放在滑鼠提示；長滿嫩草後不再標示
		var fire_mark: String = tr("map." + burn) if burn in ["burning", "ash", "regrowth"] else ""
		# 藏了肉的區域（Phase 2e）：照你以為的（被挖走、燒掉的回到那裡才知道）
		var cache_tip: String = _cache_map_tip(region_id)
		var cache_mark: String = tr("map.cache") if cache_tip != "" else ""
		btn.text = tr("region." + region_id) + marker + unknown + danger + fire_mark + cache_mark
		var tips: Array[String] = []
		if cache_tip != "":
			tips.append(cache_tip)
		if is_current:
			tips.append(tr("ui.here"))
		if burn != "":
			tips.append(tr("map.tip." + burn))
		btn.tooltip_text = "\n".join(tips)
		# 目前位置用亮框與亮字標出，不再在名稱後面加「[目前位置]」（按鈕寬度放不下，會被截掉）
		btn.theme_type_variation = &"CurrentRegionButton" if is_current else &""

	var available: Array[String] = GameState.available_actions()
	for action_id in action_buttons.keys():
		var btn: Button = action_buttons[action_id]
		btn.visible = available.has(action_id)
	# 「確定」的獵物出沒知識：寫明這次探索發現最可能的獵物的機率（按鈕上只寫名稱和百分比時，容易誤會成「去找這種獵物」）
	explore_hint_label.text = _explore_hint()
	explore_hint_label.visible = available.has("explore") and explore_hint_label.text != ""
	# 睡覺按鈕標出現在的睡處等級
	action_buttons["sleep"].text = tr("action.sleep") + "（" + tr("sleep_spot." + GameState.sleep_quality()) + "）"
	action_buttons["sleep"].tooltip_text = action_buttons["sleep"].text
	# 吃藏起來的肉（Phase 2e）：寫出幾段；滑鼠提示寫下一段新不新鮮
	var pieces: Array = GameState.cache_pieces()
	if not pieces.is_empty():
		action_buttons["eat_cache"].text = tr("action.eat_cache.n").replace("{n}", str(pieces.size()))
		var nxt: Dictionary = GameState.next_cache_piece()
		action_buttons["eat_cache"].tooltip_text = action_buttons["eat_cache"].text + "\n" + tr("action.eat_cache.tip." + ("stale" if not nxt.is_empty() and GameState.piece_state(nxt) == "stale" else "fresh"))
	# 回到殘骸：寫出剩幾段（Phase 2b 第 1 步）；滑鼠移上去寫不在時一天大約少多少
	var carcass: Dictionary = GameState.carcass_here()
	if not carcass.is_empty():
		action_buttons["return_to_carcass"].text = tr("action.return_to_carcass.n").replace("{n}", str(int(carcass["segments_left"])))
		action_buttons["return_to_carcass"].tooltip_text = action_buttons["return_to_carcass"].text + "\n" + tr("carcass.loss_tip").replace("{n}", "%.1f" % GameState.carcass_loss_per_day_absent(carcass))

# 地圖上藏肉的提示：「藏了 2 段：1 段新鮮（還能放約 6 天）、1 段快壞了」。照你以為的（被挖走、燒掉的回到那裡才知道）
func _cache_map_tip(region_id: String) -> String:
	var c: Dictionary = GameState.cache_here(region_id)
	var pieces: Array = c.get("pieces", [])
	if pieces.is_empty():
		return ""
	var parts: Array[String] = []
	for pc in pieces:
		var st: String = GameState.piece_state(pc, region_id)
		parts.append(tr("map.tip.cache." + st).replace("{d}", str(GameState.piece_days_left(pc, region_id))))
	return tr("map.tip.cache").replace("{n}", str(pieces.size())).replace("{detail}", "、".join(parts))

# 顯示用的血量：無條件進位（還活著就不會顯示 0），但不超過顯示的上限
# （血量 107.3／107.3 不會顯示成 108／107）。除錯選單也用這個值。
func _shown_health(w: Wolf) -> int:
	return mini(int(ceil(w.health)), int(round(w.health_max)))

# 外貌用的生命階段：""（次成年）、"adult"、"elder"。
func _wolf_stage_key() -> String:
	if GameState.wolf == null:
		return ""
	match GameState.wolf.life_stage():
		Wolf.LifeStage.ADULT: return "adult"
		Wolf.LifeStage.ELDER: return "elder"
	return ""

func _stage_key(stage: int) -> String:
	match stage:
		Wolf.LifeStage.SUBADULT: return "subadult"
		Wolf.LifeStage.ADULT: return "adult"
		_: return "elder"

func _log(text: String) -> void:
	# 照常過日子、自動遊玩時紀錄不顯示，但一樣檢查有沒有原始翻譯鍵
	_report_text_issues(text_watch.check(text, "log"))
	if text == "" or GameState.auto_playing:
		return
	if session_active:
		if session_entries.is_empty():
			session_entries.append({"label": "", "num": 0, "lines": []})
		session_entries.back()["lines"].append(text)
		_render_strips()
	else:
		_main_append(text)

func _flush_knowledge() -> void:
	var lines := _knowledge_buffer.duplicate()
	_knowledge_buffer.clear()
	for line in lines:
		_log_result(line)

# 要留在主畫面總結裡的句子（狩獵與戰鬥的結果、學到的知識）。
func _log_result(text: String) -> void:
	_log(text)
	if session_active and text != "" and not GameState.auto_playing:
		session_results.append(text)

# --- 主畫面的紀錄：一次行動一段 ---

# 玩家在主畫面按下行動時開新的一段；之後的訊息（含遭遇的總結、行動後的事件）都接在這一段。
func _new_main_entry() -> void:
	main_entry_open = false

func _main_append(text: String) -> void:
	if not main_entry_open or main_entries.is_empty():
		if main_entries.is_empty() or not main_entries.back()["lines"].is_empty():
			main_entries.append({"time": "", "lines": []})
		main_entries.back()["time"] = _time_label()
		main_entry_open = true
		if main_entries.size() > MAIN_LOG_KEEP:
			main_entries = main_entries.slice(main_entries.size() - MAIN_LOG_KEEP)
	main_entries.back()["lines"].append(text)
	_render_main_log()
	_store_recent_messages()

# 主畫面最後約 40 段訊息存進 life_log（跟著存檔），死亡時隨試玩紀錄匯出，用來查文案與經過。
const RECENT_MESSAGES_KEEP := 40

func _store_recent_messages() -> void:
	if GameState.auto_playing:
		return
	var list: Array = restored_messages.duplicate()
	for i in range(max(0, main_entries.size() - RECENT_MESSAGES_KEEP), main_entries.size()):
		var e: Dictionary = main_entries[i]
		if not e["lines"].is_empty():
			list.append(str(e["time"]) + "　" + _join_sentences(e["lines"]))
	GameState.life_log["recent_messages"] = list.slice(max(0, list.size() - RECENT_MESSAGES_KEEP))

func _render_main_log() -> void:
	var parts: Array[String] = []
	var start: int = max(0, main_entries.size() - MAIN_LOG_SHOWN)
	for i in range(start, main_entries.size()):
		var color: String = LOG_COLOR_NEW if i == main_entries.size() - 1 else LOG_COLOR_OLD
		parts.append("[color=%s]%s[/color]" % [color, _bb(_join_sentences(main_entries[i]["lines"]))])
	log_box.text = "\n".join(parts)
	log_box.scroll_to_line.call_deferred(max(0, log_box.get_line_count() - 1))

func _time_label() -> String:
	return "%s D%d %s" % [tr("season." + GameTime.current_season()), GameTime.day, tr("period." + GameTime.current_period())]

# 把幾行訊息接成一段：沒有句末標點的補上「。」。
func _join_sentences(lines: Array) -> String:
	var out: String = ""
	for line in lines:
		var t: String = str(line).strip_edges()
		if t == "":
			continue
		if not t[t.length() - 1] in ["。", "！", "？", "…", "」"]:
			t += "。"
		out += t
	return out

func _bb(text: String) -> String:
	return text.replace("[", "[lb]")

func _show_log_history() -> void:
	var lines: Array[String] = [tr("ui.log_history.title")]
	for entry in main_entries:
		if entry["lines"].is_empty():
			continue
		lines.append("[color=%s]%s[/color]　%s" % [LOG_COLOR_OLD, entry["time"], _bb(_join_sentences(entry["lines"]))])
	if lines.size() == 1:
		lines.append(tr("ui.log_history.empty"))
	region_info_text.bbcode_enabled = true
	region_info_text.text = "\n".join(lines)
	region_info_text.scroll_to_line.call_deferred(max(0, region_info_text.get_line_count() - 1))
	region_info_overlay.visible = true

# --- 這場遭遇的紀錄（遭遇、狩獵、戰鬥畫面下方） ---

func _make_session_strip() -> RichTextLabel:
	var strip := RichTextLabel.new()
	strip.bbcode_enabled = true
	strip.scroll_following = true
	strip.visible = false
	strip.theme_type_variation = &"SessionStrip"
	strip.custom_minimum_size = Vector2(0, _strip_height(strip, STRIP_LINES))
	return strip

func _strip_height(strip: RichTextLabel, lines: int) -> float:
	var line_h: float = strip.get_theme_font("normal_font").get_height(12) + strip.get_theme_constant("line_separation")
	return line_h * lines + 6

# 狩獵、戰鬥畫面要放進 640×360：先用一般大小，畫好後量內容高度，超過畫面才依序縮小
# （紀錄 3 → 2 行、角色圖 40 → 32、紀錄 → 1 行、角色圖 → 24、狩獵時拿掉角色圖）。2026-10-13 xvfb 量到選項 6 個時底部紀錄被擠出畫面。
# 選項很多時（試探＋四種追法＋放棄），最後一步把下方紀錄收起來（2026-10-19 ui_check：紀錄被擠出畫面）；
# 紀錄內容不會丟，遭遇結束後照常寫進主畫面。
var hunt_strip_hidden: bool = false

func _fit_hunt_layout(_option_count: int) -> void:
	hunt_strip_hidden = false
	hunt_strip.custom_minimum_size.y = _strip_height(hunt_strip, STRIP_LINES)
	_set_hunt_sprite_height(40.0)
	hunt_wolf_sprite.get_parent().get_parent().visible = true
	_shrink_hunt_layout.call_deferred()
	_shrink_hunt_layout_later()

# 文字換行要排過一次才知道多高：下一個畫格再檢查一次（ui_check 的 OFFSCREEN：戰鬥紀錄、選項超出畫面底部）
func _shrink_hunt_layout_later() -> void:
	await get_tree().process_frame
	if hunt_overlay.visible:
		_shrink_hunt_layout()

func _set_hunt_sprite_height(h: float) -> void:
	hunt_unit_h = h
	var z: float = h / 32.0
	hunt_wolf_sprite.zoom = z
	hunt_wolf_sprite.custom_minimum_size = Vector2(h * 1.8, h)
	# 對手的框照牠的體型放大（最多 2.4 倍高），兩隻底部對齊
	var oz: float = z * hunt_opp_scale
	if hunt_opp_frame.y * oz > h * 2.4:
		oz = h * 2.4 / hunt_opp_frame.y
	hunt_sprite.zoom = oz
	hunt_sprite.custom_minimum_size = Vector2(max(h * 1.8, hunt_opp_frame.x * oz), max(h, hunt_opp_frame.y * oz))

# 換對手時記下牠的顯示倍率與格子大小，照目前的大小重新排
func _set_hunt_opponent(animal_id: String, life_stage: String) -> void:
	hunt_opp_scale = ArtLibrary.display_scale(animal_id, life_stage)
	hunt_opp_frame = ArtLibrary.idle_frame_size(animal_id, life_stage)
	_set_hunt_sprite_height(hunt_unit_h)

func _shrink_hunt_layout() -> void:
	var box: Control = hunt_message.get_parent()
	var limit: float = get_viewport_rect().size.y - 6.0
	var tiers: Array[Callable] = [
		func(): hunt_strip.custom_minimum_size.y = _strip_height(hunt_strip, 2),
		func(): _set_hunt_sprite_height(32.0),
		func(): hunt_strip.custom_minimum_size.y = _strip_height(hunt_strip, 1),
		func(): _set_hunt_sprite_height(24.0),
		# 最後：狩獵（不是戰鬥，沒有動畫）時拿掉角色圖
		func(): hunt_wolf_sprite.get_parent().get_parent().visible = current_combat != null,
		func():
			hunt_strip_hidden = true
			hunt_strip.visible = false,
		# 還放不下（戰鬥選項多、每個選項兩行說明）：戰鬥也拿掉角色圖（動畫照樣跑，只是看不到）
		func(): hunt_wolf_sprite.get_parent().get_parent().visible = false,
	]
	for tier in tiers:
		if box.get_combined_minimum_size().y <= limit:
			return
		tier.call()

# 遭遇畫面上的選擇按鈕都經過這裡：按下時開新的一段紀錄，處理完再檢查遭遇是否結束。
func _session_choice(label: String, callback: Callable) -> Callable:
	return func():
		_begin_session_entry(label)
		callback.call()
		if not session_check_pending:
			session_check_pending = true
			_check_session_end.call_deferred()

func _begin_session_entry(label: String) -> void:
	if not session_active:
		session_active = true
		session_entries = []
		session_results = []
	# 戰鬥與多回合追擊（含狩獵的搏鬥）才編號
	var numbered: bool = current_combat != null or (current_hunt != null and current_hunt.stage in [HuntSystem.Stage.CHASE, HuntSystem.Stage.FIGHT])
	var num: int = 0
	if numbered:
		num = 1
		for e in session_entries:
			if int(e["num"]) > 0:
				num += 1
	session_entries.append({"label": choice_label_regex.sub(label, "", true).strip_edges(), "num": num, "lines": []})

# 選擇處理完後：遭遇畫面都關了就是這場遭遇結束。最後一個選擇有結果時先交代結果、按「繼續」才回到主畫面。
func _check_session_end() -> void:
	session_check_pending = false
	if not session_active or session_result_mode:
		return
	if encounter_overlay.visible or hunt_overlay.visible or current_hunt != null or current_combat != null:
		_render_strips()
		return
	if GameState.wolf == null or not GameState.wolf.alive or session_entries.is_empty() or session_entries.back()["lines"].is_empty():
		_end_session()
		return
	session_result_mode = true
	encounter_message.text = _join_sentences(session_entries.back()["lines"])
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "idle")
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	var btn := Button.new()
	btn.text = tr("ui.continue")
	btn.pressed.connect(_end_session)
	encounter_buttons_box.add_child(btn)
	encounter_overlay.visible = true
	_render_strips()

# 遭遇結束：主畫面的紀錄只留總結（標記的結果＋最後一句），再處理排隊的事件。
func _end_session() -> void:
	if session_result_mode:
		encounter_overlay.visible = false
	session_result_mode = false
	var all_lines: Array = []
	for e in session_entries:
		all_lines.append_array(e["lines"])
	var summary: Array[String] = session_results.duplicate()
	if not all_lines.is_empty() and not summary.has(all_lines.back()):
		summary.append(all_lines.back())
	session_active = false
	session_entries = []
	session_results = []
	encounter_strip.visible = false
	hunt_strip.visible = false
	for s in summary:
		_main_append(s)
	_refresh()

func _render_strips() -> void:
	var shown: Array = []
	for e in session_entries:
		if not e["lines"].is_empty():
			shown.append(e)
	# 結果畫面：最後一段已經寫在上面的描述，紀錄只列之前的
	if session_result_mode and not shown.is_empty():
		shown.pop_back()
	# 狩獵畫面上方列著觀察到的狀態：最後一段的那一句不再寫在下方紀錄
	if hunt_overlay.visible and hunt_notes_log != "" and not shown.is_empty() and shown.back()["lines"].has(hunt_notes_log):
		var last: Dictionary = shown.back().duplicate(true)
		last["lines"].erase(hunt_notes_log)
		shown[shown.size() - 1] = last
		if last["lines"].is_empty():
			shown.pop_back()
	var parts: Array[String] = []
	for i in shown.size():
		var e: Dictionary = shown[i]
		var color: String = LOG_COLOR_NEW if i == shown.size() - 1 and not session_result_mode else LOG_COLOR_OLD
		var prefix: String = (_circled(int(e["num"])) + " ") if int(e["num"]) > 0 else ""
		var label: String = ("[color=%s]%s：[/color]" % [LOG_COLOR_LABEL, _bb(str(e["label"]))]) if str(e["label"]) != "" else ""
		parts.append("[color=%s]%s[/color]%s[color=%s]%s[/color]" % [color, prefix, label, color, _bb(_join_sentences(e["lines"]))])
	var text: String = "\n".join(parts)
	for strip in [encounter_strip, hunt_strip]:
		strip.text = text
		strip.visible = session_active and not parts.is_empty() and not (strip == hunt_strip and hunt_strip_hidden)
		strip.scroll_to_line.call_deferred(max(0, strip.get_line_count() - 1))
	# 紀錄第一次出現（原本隱藏）時，狩獵、戰鬥畫面要重新量一次放不放得下（ui_check：紀錄跑到畫面底部外面）
	if hunt_overlay != null and hunt_overlay.visible:
		_shrink_hunt_layout_later()

func _circled(n: int) -> String:
	const CIRCLED := "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
	return CIRCLED[n - 1] if n >= 1 and n <= CIRCLED.length() else "(%d)" % n

# 先隱藏再刪除：queue_free 到這一格結束才真的刪掉，期間仍算進容器的大小；
# 隱藏的元件不算，避免狩獵畫面量高度時把舊按鈕算進去、誤拿掉角色圖（試玩回報 2）
func _clear_children(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			child.visible = false
		child.queue_free()

# --- Region movement ---

func _on_map_slot(i: int) -> void:
	var layout: Array = GameData.map_regions(rendered_map)
	if i < layout.size():
		_on_region_button(str(layout[i]))

# 地圖按鈕上的區域小圖：有美術就用（art.json 的 region_tile.<id>），沒有就用程式生成的小圖。
func _region_tile(region_id: String, season: String) -> Texture2D:
	var tex: Texture2D = ArtLibrary.icon("region_tile." + region_id)
	return tex if tex != null else PixelArt.make_region_tile(region_id, season, Vector2i(18, 18))

# 所有地圖的區域（區域資訊、知識清單用）。
func _all_regions() -> Array:
	var list: Array = []
	for map_id in GameData.maps().keys():
		list.append_array(GameData.map_regions(map_id))
	return list

func _on_region_button(region_id: String, via_ice: bool = false, river_confirmed: bool = false) -> void:
	if region_id == GameState.current_region:
		return
	# 進出河谷要過河（QA-64）：春季河冰變薄，先跳字卡讓玩家決定；其他季節只寫一行怎麼過河。
	var crossing: String = "" if via_ice else GameState.river_crossing(region_id)
	if crossing == "thaw" and not river_confirmed:
		_show_river_prompt(region_id)
		return
	if crossing == "flood" and not river_confirmed:
		_show_flood_prompt(region_id)
		return
	_new_main_entry()
	for entry in GameState.known_dangers(region_id, GameTime.current_season()):
		_log(tr("log.danger_warning") + _knowledge_text(entry))
	if via_ice:
		_log(tr("log.ice_shortcut"))
	elif crossing != "":
		_log(tr("river.cross." + crossing))
	GameState.action_move(region_id, via_ice)

# 春季進出河谷：河冰正在融化，過河時可能裂開。和森林、苔原之間的冰面捷徑不同，這是必經的路。
func _show_river_prompt(region_id: String) -> void:
	var river: String = str(GameState._ice_cfg().get("region", ""))
	var text: String = tr("river.thaw." + ("leave" if GameState.current_region == river else "enter"))
	encounter_message.text = text
	encounter_detail.text = tr("river.thaw.detail")
	_set_wolf_pose(encounter_sprite, "idle")
	encounter_bg.texture = ArtLibrary.terrain_background("ice", GameTime.current_season()) # 春季是冰薄版
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("river.thaw.go").replace("{region}", tr("region." + region_id)), func():
		encounter_overlay.visible = false
		_on_region_button(region_id, false, true)
	)
	_add_encounter_button(tr("river.thaw.back"), func():
		encounter_overlay.visible = false
	)
	encounter_overlay.visible = true

# 春季進出草原的大河：融雪水急，可能被沖走一段（Phase 2 第 4 步）。
func _show_flood_prompt(region_id: String) -> void:
	encounter_message.text = tr("river.flood.prompt")
	encounter_detail.text = tr("river.flood.detail")
	_set_wolf_pose(encounter_sprite, "idle")
	encounter_bg.texture = ArtLibrary.terrain_background("river", GameTime.current_season())
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("river.thaw.go").replace("{region}", tr("region." + region_id)), func():
		encounter_overlay.visible = false
		_on_region_button(region_id, false, true)
	)
	_add_encounter_button(tr("river.thaw.back"), func():
		encounter_overlay.visible = false
	)
	encounter_overlay.visible = true

# --- Actions ---

func _on_action_button(action_id: String) -> void:
	_new_main_entry()
	match action_id:
		"explore":
			_show_discovery(GameState.action_explore())
		"explore_modes":
			_show_explore_modes()
		"routine":
			_show_routine_menu()
		"gather":
			var result := GameState.action_gather()
			if result.get("found", false):
				_log(tr("log.gather.success").replace("{item}", tr("item." + str(result["item_id"]))))
			else:
				_log(tr("log.gather.fail"))
		"find_sleep_spot":
			var spot := GameState.action_find_sleep_spot()
			_log(tr("log.sleep_spot.fail") if spot == "" else tr("log.sleep_spot." + spot))
		"short_rest":
			GameState.action_short_rest()
			_log(tr("log.short_rest"))
		"rest_until":
			_show_rest_overlay()
		"make_den":
			GameState.action_make_den()
		"lie_down":
			_show_lie_down()
		"mark":
			var r: String = GameState.action_mark()
			_log(tr("log.mark." + r).replace("{region}", tr("region." + GameState.current_region)))
		"regurgitate":
			var got: float = GameState.regurgitate()
			_log(tr("den.regurgitated").replace("{days}", str(snapped(GameState.den_food_days(), 0.5))) if got > 0.0 else tr("den.cannot_regurgitate"))
		"howl":
			var hr: Dictionary = GameState.action_howl()
			_log(tr("log.howl"))
			if hr.get("came", false):
				_show_discovery(GameState.current_discovery)
		"return_to_carcass":
			var res := GameState.action_return_to_carcass()
			if res.get("gone", false) or res.is_empty():
				_log(tr("log.carcass_gone"))
			elif res.get("event", "") != "" and not res.get("own", true):
				_show_found_scavenger(str(res["event"]))
			elif res.get("event", "") != "":
				_show_scavenger(res["event"], true)
			else:
				_show_feeding()
		"eat_cache":
			GameState.action_eat_cache()
		"sleep":
			sleeping_now = true
			woken_encounter = {}
			var res := GameState.action_sleep()
			sleeping_now = false
			if not res.is_empty():
				if res.get("interrupted", false):
					_log(tr("log.slept_woken." + str(res["quality"])))
					_log(tr("log.sleep_interrupted"))
				else:
					_log(tr("log.slept." + str(res["quality"])))
				if not woken_encounter.is_empty():
					_on_encounter_triggered(woken_encounter)
					woken_encounter = {}
				# 換季的那一覺不另外顯示睡覺結算，併入換季字卡（SPEC「睡覺結算」）
				# 排進事件佇列，接在換日摘要之後，用按鍵關閉的卡片顯示（QA-47）
				# 插在換日摘要之後、睡覺期間排進的其他事件（渡鴉等）之前（QA-60）
				if not res.get("season_changed", false):
					var at: int = 0
					for i in GameState.pending_events.size():
						if GameState.pending_events[i].get("type", "") in ["day_summary", "season_card"]:
							at = i + 1
					# 一般的成長用淡出提示（sleep_growth），挨餓長不起來的第一晚才出卡片（GameState.sleep_summary 決定）
					var summary: Dictionary = res.get("summary", {})
					GameState.pending_events.insert(at, {"type": "sleep_summary" if summary.get("card", false) else "sleep_growth", "summary": summary})

# 依接下來的時段順序列出選項（不含目前時段）。
func _show_rest_overlay() -> void:
	_clear_children(rest_buttons_box)
	# 依目的列出（Phase 2b 第 2 步）：暴風雪結束、消化完、黃昏、清晨；選項由 GameState.rest_options() 決定
	for opt in GameState.rest_options():
		var btn := Button.new()
		match str(opt["id"]):
			"blizzard":
				btn.text = tr("ui.rest_until.blizzard")
				btn.pressed.connect(_on_rest_out_blizzard)
			"digest":
				btn.text = tr("ui.rest_until.digest")
				btn.tooltip_text = tr("ui.rest_until.digest.tip")
				btn.pressed.connect(_on_rest_digest)
			_:
				var period: String = str(opt["period"])
				btn.text = tr("ui.rest_until.option").replace("{period}", tr("period." + period))
				btn.tooltip_text = tr("ui.rest_until.tip." + period)
				btn.pressed.connect(_on_rest_until.bind(period))
		rest_buttons_box.add_child(btn)
	rest_overlay.visible = true

func _on_rest_digest() -> void:
	_new_main_entry()
	rest_overlay.visible = false
	var res := GameState.action_rest_digest()
	if not res.get("alive", false):
		return
	if str(res.get("interrupted", "")) != "":
		_log(tr("log.rest_interrupted"))
	elif GameState.wolf.is_overfed():
		_log(tr("log.rest_digest.long"))
	else:
		_log(tr("log.rest_digest"))

func _on_rest_until(period: String) -> void:
	_new_main_entry()
	rest_overlay.visible = false
	var res := GameState.action_rest_until(period)
	if not res.get("alive", false):
		return
	if str(res.get("interrupted", "")) != "":
		_log(tr("log.rest_interrupted"))
	else:
		_log(tr("log.rest_until").replace("{period}", tr("period." + period)))

func _on_rest_out_blizzard() -> void:
	_new_main_entry()
	rest_overlay.visible = false
	var res := GameState.action_rest_out_blizzard()
	if not res.get("alive", false):
		return
	match str(res.get("interrupted", "")):
		"":
			_log(tr("log.rest_blizzard.done"))
		"hungry":
			_log(tr("log.rest_blizzard.hungry"))
		_:
			_log(tr("log.rest_interrupted"))

func _animal_scale(life_stage: String) -> float:
	return 0.7 if life_stage == "juvenile" else 1.0

# --- 探索 ---

const CLUE_ICON_FOR := {"scent": "scent", "track": "track", "sound": "sound", "sign": "track", "sight": "sight"}

func _show_discovery(d: Dictionary) -> void:
	if d.is_empty() or GameState.wolf == null or not GameState.wolf.alive:
		return
	if d.get("kind", "") == "she_wolf":
		_show_she_wolf(d)
		return
	if d.get("kind", "") == "pack_sign":
		# 鄰群的徵兆（Phase 3 第 4 步）
		var ps_text: String = tr("pack_sign." + str(d.get("sign", "core"))).replace("{region}", tr("region." + str(d.get("home", ""))))
		GameState.clear_discovery()
		_show_event_message(ps_text, "stranger_wolf")
		_set_terrain_bg(encounter_bg, str(d.get("location", "")))
		return
	if d.get("kind", "") == "tundra_wolves":
		_show_tundra_meet(d)
		return
	if d.get("kind", "") == "tundra_mob":
		_show_tundra_mob(d)
		return
	if d.get("kind", "") == "tundra_hunt":
		_show_tundra_hunt(d)
		return
	if d.get("kind", "") in ["tundra_den", "tundra_den_bear"]:
		_show_tundra_den(d)
		return
	if d.get("kind", "") == "overmarked":
		_show_overmarked(d)
		return
	if d.get("kind", "") == "challenger":
		_show_challenger(d, false)
		return
	if d.get("kind", "") in ["cougar_ambush", "cougar_cache"]:
		_show_cougar(d)
		return
	if d.get("kind", "") == "lynx":
		_show_lynx(d)
		return
	if d.get("kind", "") == "small_pounce":
		_show_small_pounce(d)
		return
	if d.get("kind", "") == "salmon":
		_show_salmon(d)
		return
	if d.get("kind", "") == "migration":
		_show_migration(d)
		return
	if d.get("kind", "") == "pack_remains":
		_show_pack_remains(d, true)
		return
	var text := _discovery_text(d)
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_show_discovery_sprite(d)
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	if d.get("kind", "") == "carcass":
		_add_encounter_button(tr("ui.eat_carcass"), func():
			GameState.clear_discovery()
			encounter_overlay.visible = false
			_on_action_button("return_to_carcass")
		)
	if d.get("kind", "") == "remains":
		_add_encounter_button(tr("ui.eat_remains"), func():
			var tier: String = str(d.get("tier", "some"))
			var res: Dictionary = GameState.eat_remains()
			_log(tr("log.eat_remains." + tier).replace("{n}", str(int(res["gain"]))))
			encounter_overlay.visible = false
			_refresh()
			if not (res["encounter"] as Dictionary).is_empty():
				_log(tr("remains.bear_returns"))
				_on_encounter_triggered(res["encounter"])
		)
	if d.get("kind", "") == "clue" and d.get("source_kind", "") == "threat":
		_add_threat_options(d)
	elif d.get("kind", "") == "clue":
		if d.get("source_kind", "") == "gather":
			_add_encounter_button(tr("ui.gather_here"), func():
				var item: String = GameState.action_gather_discovered()
				encounter_overlay.visible = false
				if item != "":
					_log(tr("log.gather.success").replace("{item}", tr("item." + item)))
			)
		elif d.get("clue", "") == "sight":
			_add_hunt_button(tr("ui.hunt"), func():
				encounter_overlay.visible = false
				current_hunt = GameState.action_hunt_sighted()
				_enter_hunt()
			)
		elif ExploreSystem.can_track(d):
			var info := GameState.track_chance()
			_add_hunt_button(tr("ui.track") + "　" + tr("chance_label.success") + " " + _chance_text(float(info["chance"]), str(d.get("source", ""))), _on_track)
			encounter_detail.text = _format_factors(info["factors"])
	if d.get("kind", "") == "clue" and (d.get("source_kind", "") == "threat" or (d.get("source_kind", "") == "prey" and d.get("fresh_known", true) and not d.get("fresh", false))):
		# 按鈕寫出記下的效果：不花時間，累積知識（QA-53）
		_add_encounter_button(tr("ui.note") + "　" + tr("ui.note_hint." + ("threat" if d.get("source_kind", "") == "threat" else "prey")), func():
			GameState.note_discovery()
			encounter_overlay.visible = false
		)
	_add_encounter_button(tr("ui.keep_exploring"), func(): _show_discovery(GameState.action_explore()))
	_add_encounter_button(tr("ui.leave"), func():
		GameState.clear_discovery()
		encounter_overlay.visible = false
	)
	encounter_overlay.visible = true

# 灰熊、陌生灰狼的線索：目擊時可觀察（辨識前）或避開；足跡等線索可追蹤（新鮮時）、避開（灰熊）或記下。
func _add_threat_options(d: Dictionary) -> void:
	var source: String = str(d["source"])
	if d.get("clue", "") == "sight":
		if source == "stranger_wolf" and GameState.stranger_can_interact():
			_add_encounter_button(tr("stranger.approach"), func():
				var e := GameState.prepare_threat_sighting(source, str(d.get("location", "")))
				GameState.clear_discovery()
				_show_stranger_meet(e)
			)
			return
		if source == "grizzly_bear" and GameState.is_identified(source):
			_add_encounter_button(tr("ui.avoid"), _on_avoid)
		else:
			_add_encounter_button(tr("encounter.observe"), func():
				var e := GameState.prepare_threat_sighting(source, str(d.get("location", "")))
				GameState.clear_discovery()
				GameState.action_observe_distant(e)
				_log(_observed_text(source))
				encounter_overlay.visible = false
				_refresh()
			)
		return
	if ExploreSystem.can_track(d):
		var info := GameState.track_chance()
		_add_encounter_button(tr("ui.track") + "　" + tr("chance_label.success") + " " + _chance_text(float(info["chance"]), str(d.get("source", ""))), _on_track)
		encounter_detail.text = tr("explore.threat_track_warning")
	if source == "grizzly_bear":
		_add_encounter_button(tr("ui.avoid"), _on_avoid)

func _on_avoid() -> void:
	GameState.action_avoid()
	_log(tr("log.avoided"))
	encounter_overlay.visible = false

func _on_track() -> void:
	var animal_name: String = tr("animal." + str(GameState.current_discovery.get("source", "")))
	var result := GameState.action_track()
	encounter_overlay.visible = false
	if result.get("success", false) and result.has("encounter"):
		_on_encounter_triggered(result["encounter"])
	elif result.get("success", false):
		_log(tr("log.track.success").replace("{animal}", animal_name))
		current_hunt = result["hunt"]
		_enter_hunt()
	else:
		_log(tr("log.track.fail"))
		var reason: String = result.get("reason_key", "")
		if _has_text(reason):
			_log(tr(reason).replace("{animal}", animal_name))
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)

# 會開始狩獵的按鈕：太累時灰掉並寫「太累了，追不動」（1.7 QA-55）。
func _add_hunt_button(label: String, callback: Callable) -> void:
	if not GameState.too_tired_to_hunt():
		_add_encounter_button(label, callback)
		return
	var btn := Button.new()
	btn.text = label + "　" + tr("ui.too_tired_to_hunt")
	btn.disabled = true
	encounter_buttons_box.add_child(btn)

func _add_encounter_button(label: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(_session_choice(label, callback))
	encounter_buttons_box.add_child(btn)

# 痕跡：先找「動物.生命階段」（例如小駝鹿不會磨角），再找動物（discovery.json 的 signs）。
func _sign_of(animal_id: String, life_stage: String) -> String:
	var signs: Dictionary = GameData.discovery.get("signs", {})
	return str(signs.get(animal_id + "." + life_stage, signs.get(animal_id, "browse")))

# 照常過日子（Phase 1.7b，提案之十 E）：選天數與方式，代為行動，有事就停下、交還給你。
func _show_routine_menu() -> void:
	encounter_message.text = tr("routine.title")
	encounter_detail.text = tr("routine.hint")
	_set_wolf_pose(encounter_sprite, "walk")
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	for style in ["small", "big", "heal"]:
		for days in [1, 3]:
			var s: String = style
			var n: int = days
			_add_encounter_button(tr("routine.option." + style).replace("{n}", str(days)), func():
				encounter_overlay.visible = false
				_run_routine(n, s)
			)
	_add_encounter_button(tr("ui.leave"), func(): encounter_overlay.visible = false)
	encounter_overlay.visible = true

func _run_routine(days: int, style: String) -> void:
	var res := GameState.run_routine(days, style)
	var parts: Array[String] = []
	for k in res.get("prey", {}).keys():
		parts.append("%s %d" % [tr("animal." + str(k)), int(res["prey"][k])])
	var prey_text: String = tr("routine.prey").replace("{list}", "、".join(parts)) if not parts.is_empty() else tr("routine.no_prey")
	# 還不到一天就停下時不寫「過了 0 天」（試玩 BUG-11）
	# 換季那一晚不會算進天數（換季把日期歸 1），所以和睡了幾晚取大的
	var days_passed: int = max(int(res.get("days", 0)), int(res.get("den_nights", 0)) + int(res.get("wild_nights", 0)))
	var summary_key: String = "routine.summary" if days_passed > 0 else "routine.summary.short"
	var body: String = tr(summary_key).replace("{days}", str(days_passed)).replace("{prey}", prey_text) \
		.replace("{den}", str(int(res.get("den_nights", 0)))).replace("{wild}", str(int(res.get("wild_nights", 0))))
	if str(res.get("moved_to", "")) != "":
		body += tr("routine.moved").replace("{region}", tr("region." + str(res["moved_to"])))
	# 成長：卡片用圖示與顏色，紀錄欄用純文字
	var log_body: String = body
	var growth: Dictionary = res.get("growth", {})
	if not growth.is_empty():
		var gparts: Array[String] = []
		var plain: Array[String] = []
		for stat in GameState.SLEEP_SUMMARY_STATS:
			if growth.has(stat):
				gparts.append(_icon_bb("stat." + stat) + tr("stat." + stat) + " [color=%s]▲%.1f[/color]" % [UiTheme.html("stat_gain"), float(growth[stat])])
				plain.append(tr("stat." + stat) + " ▲%.1f" % float(growth[stat]))
		body += "\n" + tr("routine.growth") + "　".join(gparts)
		log_body += tr("routine.growth") + "　".join(plain) + "。"
	var stop_text: String = tr("routine.stop." + str(res.get("reason", "done")))
	body += "\n\n" + stop_text
	_log(log_body + stop_text)
	if not res.get("alive", true):
		_on_wolf_died(GameState.wolf.death_cause)
		return
	_show_card(tr("routine.card_title"), body)
	if not (res.get("encounter", {}) as Dictionary).is_empty():
		_on_encounter_triggered(res["encounter"])
	elif str(res.get("scavenger", "")) != "" and GameState.is_feeding():
		_show_scavenger(str(res["scavenger"]), false)
	elif not GameState.current_discovery.is_empty():
		_show_discovery(GameState.current_discovery)
	_process_events()

# 換個方式探索（Phase 1.7b 探索改版）：獸徑、登高嗅風、守在水邊、巡邊界，以及「探索到有值得注意的發現為止」。
func _show_explore_modes() -> void:
	encounter_message.text = tr("explore.modes.title")
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "walk")
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	var known: Array = GameState.known_features(GameState.current_region)
	for mode in ["trail", "ridge", "water", "border"]:
		if not ExploreSystem.mode_available(mode, GameState.current_region, known):
			continue
		var spot: String = str(ExploreSystem.mode_cfg(mode).get("spot", ""))
		var label: String = tr("explore.mode." + mode + (".spot" if spot != "" and known.has(spot) else ""))
		var m: String = mode
		_add_encounter_button(label, func():
			encounter_overlay.visible = false
			_show_discovery(GameState.action_explore(m))
		)
		# 探索方式的小圖示（2026-10-13）
		var last: Node = encounter_buttons_box.get_child(encounter_buttons_box.get_child_count() - 1)
		if last is Button and ArtLibrary.icon("explore." + mode) != null:
			(last as Button).icon = ArtLibrary.icon("explore." + mode)
			(last as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
	# 牧場邊緣：望向柵欄裡，看人在做什麼（Phase 4a 第 2 步）
	if GameState.can_watch_ranch():
		_add_encounter_button(tr("explore.mode.watch_ranch"), func():
			encounter_overlay.visible = false
			_show_discovery(GameState.action_watch_ranch())
		)
	_add_encounter_button(tr("explore.mode.until"), func():
		encounter_overlay.visible = false
		var res := GameState.action_explore_until()
		var skipped: Array = res.get("skipped", [])
		if not skipped.is_empty():
			_log(tr("explore.until.skipped").replace("{n}", str(skipped.size())))
		var d: Dictionary = res.get("discovery", {})
		if not d.is_empty() and GameState.is_notable_discovery(d):
			_show_discovery(d)
		elif not d.is_empty():
			_log(_discovery_text(d))
			GameState.clear_discovery()
			_log(tr("explore.until.none"))
			_refresh()
		else:
			_refresh()
		_process_events()
	)
	_add_encounter_button(tr("ui.leave"), func(): encounter_overlay.visible = false)
	encounter_overlay.visible = true

# 牧場的人類遭遇（Phase 4a 第 4 步）：開頭一段、這一回合發生的事、選項（成功率用百分比）；結束時寫結果，按「繼續」
func _show_ranch_encounter(enc: RanchEncounter, last_events: Array = []) -> void:
	var lines: Array[String] = []
	if last_events.is_empty() and enc.rounds == 0:
		lines.append(tr("ranch.enc.%s.intro" % enc.kind).replace("{n}", str(enc.dogs)))
	for e in last_events:
		lines.append(tr("ranch.enc." + str(e["key"])).replace("{n}", str(int(e.get("n", 0)))))
	if not enc.done and enc.stage == "dogs":
		lines.append(tr("ranch.enc.hunt.dogs_left").replace("{n}", str(enc.dogs)))
	var text: String = "".join(lines)
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	encounter_sprite.show_static(ArtLibrary.ranch_image("encounters", "dogs" if enc.stage == "dogs" else enc.kind))
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	if enc.done:
		_add_encounter_button(tr("ui.continue"), func():
			encounter_overlay.visible = false
			_refresh()
			if GameState.wolf != null and not GameState.wolf.alive:
				_on_wolf_died(GameState.wolf.death_cause)
			elif GameState.is_feeding():
				_show_feeding()
			else:
				_process_events()
		)
	else:
		for o in enc.options():
			var id: String = str(o["id"])
			var label: String = tr("ranch.enc.opt." + id)
			if not id in ["grab", "drop"]:
				label += "　%s %d%%" % [tr("chance_label.success"), roundi(float(o["chance"]) * 100.0)]
			_add_encounter_button(label, func():
				GameState.ranch_encounter_choose(id)
				_show_ranch_encounter(enc, enc.events.duplicate())
			)
	encounter_overlay.visible = true

func _discovery_text(d: Dictionary) -> String:
	var location: String = tr("explore.location." + str(d.get("location", "")))
	match d.get("kind", ""):
		"nothing" when d.get("blizzard", false):
			return tr("explore.blizzard")
		"carcass":
			return tr("explore.carcass" + (".frozen" if d.get("frozen", false) else "")).replace("{location}", location) \
				.replace("{animal}", tr("animal." + str(d["animal_id"])))
		"nothing" when d.get("wind_bad", false):
			return tr("explore.ridge.wind_bad")
		"small_pounce":
			return _small_pounce_text("see", d)
		"salmon":
			return tr("salmon.clue.%s.%s" % [str(d.get("stage", "peak")), str(d.get("clue", "shadows"))]).replace("{location}", tr("explore.location." + str(d.get("location", ""))))
		"nothing" when d.has("ranch_sign"):
			return tr("ranch.sign." + str(d["ranch_sign"])).replace("{location}", location)
		"nothing" when d.has("ranch_watch"):
			return tr("ranch.watch." + str(d["ranch_watch"]))
		"nothing" when d.has("ranch_guarded"):
			return tr("ranch.guarded." + str(d["ranch_guarded"])).replace("{location}", location)
		"nothing" when d.has("ranch_empty"):
			return tr("ranch.empty." + str(d["ranch_empty"])).replace("{location}", location)
		"nothing" when d.has("ranch_clue"):
			return tr("ranch.clue." + str(d["ranch_clue"])).replace("{location}", location)
		"nothing" when d.has("hibernating"):
			return tr("explore.hibernating." + str(d["hibernating"])).replace("{location}", location)
		"nothing" when str(d.get("mode", "")) == "water":
			return tr("explore.water.nothing").replace("{location}", location)
		"nothing" when d.get("day_bedded", false):
			return tr("explore.nothing.day").replace("{location}", location)
		"nothing" when str(d.get("absent_source", "")) == "":
			# 這一區、這一季沒有任何獵物（冬季的屋舍與畜欄，羊關在棚裡；2026-10-29 QA：原本顯示原始的翻譯鍵）
			return tr("explore.nothing.empty").replace("{location}", location)
		"nothing":
			return tr("explore.nothing").replace("{location}", location) \
				.replace("{animal}", tr("animal." + str(d.get("absent_source", ""))))
		"remains":
			return tr("explore.remains." + str(d.get("tier", "some"))).replace("{location}", location).replace("{animal}", tr("animal." + str(d["animal_id"])))
		"mark":
			var who_key: String = "explore.mark." + str(d.get("who", ""))
			var mark_text: String = tr(who_key + (".here" if str(d.get("region", "")) == GameState.current_region else ".near")) \
				.replace("{location}", location).replace("{region}", tr("region." + str(d.get("region", ""))))
			if str(d.get("who", "")) == "stranger_wolf" and GameState.pack_sign_key("mark") != "":
				mark_text += tr(GameState.pack_sign_key("mark"))
			return mark_text
		"feature":
			return tr("explore.feature").replace("{location}", location) \
				.replace("{feature}", tr("feature." + str(d["feature_id"])))
	if d.get("source_kind", "") == "threat":
		var source: String = str(d["source"])
		var state: String = "known" if GameState.is_identified(source) else "unknown"
		var clue_text: String = tr("clue.%s.%s.%s" % [source, d.get("clue", "sight"), state])
		if source == "stranger_wolf" and GameState.pack_sign_key(str(d.get("clue", "sight"))) != "":
			clue_text += tr(GameState.pack_sign_key(str(d.get("clue", "sight"))))
		var fresh_text: String = ""
		if d.get("clue", "") != "sight":
			fresh_text = tr("explore.threat_fresh") if d.get("fresh", false) else tr("explore.threat_stale")
		return tr("explore.threat").replace("{location}", location).replace("{clue}", clue_text) + fresh_text
	if d.get("source_kind", "") == "gather":
		return tr("explore.gather").replace("{location}", location).replace("{item}", tr("item." + str(d["source"])))
	var animal: String = _prey_name(str(d["source"]), d.get("life_stage", "adult"))
	if d.get("injured", false):
		# 會延續的個體：寫出牠的特徵（跛腳、年老），再遇到時「又是那頭…」（提案之十 D）
		animal = tr("explore.trait." + str(d.get("trait", "injured"))) + animal
		if d.get("again", false):
			return tr("explore.again").replace("{location}", location).replace("{animal}", animal)
	# 已經「確定」的事件壓縮成一行，不重新演出完整文字。
	if (d.get("fresh", false) or d.get("clue", "") == "sight") and GameState.is_confirmed({"type": "prey", "animal": d["source"],
			"region": GameState.current_region, "period": GameTime.current_period()}):
		return tr("explore.known").replace("{period}", tr("period." + GameTime.current_period())) \
			.replace("{location}", tr("explore.location." + str(d.get("location", "")))).replace("{animal}", tr("animal." + str(d["source"])))
	var fresh: String = ""
	if d.get("fresh_known", true):
		fresh = tr("explore.fresh") if d.get("fresh", false) else tr("explore.stale")
	if d.get("fled", false):
		return tr("explore.fled").replace("{animal}", _prey_name(d["source"], d.get("life_stage", "adult"))).replace("{location}", location)
	var clue: String = str(d.get("clue", "track"))
	if d.get("bugle", false):
		return tr("explore.clue.bugle").replace("{location}", location)
	# 有寫新不新鮮時，氣味用「陳舊的野兔氣味」，避免「陳舊的野兔的氣味」
	var clue_key: String = "explore.clue." + clue + ("_fresh" if clue == "scent" and fresh != "" else "")
	# 成群：看到的是一小群（發現時決定，狩獵沿用，試玩回報 4）
	if clue == "sight" and bool(d.get("herd", false)):
		clue_key = "explore.clue.sight_herd"
	var text: String = tr(clue_key).replace("{location}", location).replace("{animal}", animal) \
		.replace("{fresh}", fresh).replace("{sign}", tr("explore.sign." + _sign_of(str(d["source"]), str(d.get("life_stage", "adult")))))
	if not d.get("fresh_known", true):
		text += tr("explore.fresh_unknown").replace("{wind}", tr("factor.wind." + str(d.get("wind", "crosswind"))))
	if d.get("hidden", false):
		text += tr("explore.hidden_young")
	if d.has("ambush"):
		text += tr("explore.water.ambush")
	return text

# 發現畫面的圖：目擊到的動物用動物圖，採集物用物品圖示，其他用線索圖示。
func _show_discovery_sprite(d: Dictionary) -> void:
	# 牧場的線索、痕跡、觀察（Phase 4a 第 6 步）
	for rk in [["ranch_clue", "clues"], ["ranch_sign", "signs"], ["ranch_watch", "watch"]]:
		if d.has(rk[0]):
			var rtex: Texture2D = ArtLibrary.ranch_image(rk[1], str(d[rk[0]]).trim_suffix(".night"))
			if rtex != null:
				encounter_sprite.show_static(rtex)
				return
	var kind: String = d.get("kind", "")
	var source_kind: String = d.get("source_kind", "")
	if kind == "clue" and d.get("clue", "") == "sight" and source_kind == "prey":
		_set_creature(encounter_sprite, d["source"], d.get("life_stage", "adult"), "walk")
		return
	if kind == "clue" and source_kind == "gather":
		var item_tex: Texture2D = ArtLibrary.icon("item." + str(d["source"]))
		if item_tex != null:
			encounter_sprite.show_static(item_tex)
			return
	var icon_key: String = "sight"
	if kind == "carcass":
		var carcass_tex: Texture2D = ArtLibrary.carcass(str(d["animal_id"]))
		if carcass_tex != null:
			encounter_sprite.show_static(carcass_tex)
			return
	if kind == "nothing":
		icon_key = "unknown"
	elif kind == "clue":
		var clue: String = str(d.get("clue", "track"))
		if source_kind == "threat":
			icon_key = "claw" if clue == "claw" else ("scent" if clue.ends_with("scent") else ("sight" if clue == "sight" else "track"))
		else:
			icon_key = CLUE_ICON_FOR.get(clue, "track")
			icon_key = str(GameData.discovery.get("clue_icon_overrides", {}).get(str(d["source"]) + "." + clue, icon_key))
	encounter_sprite.show_static(ArtLibrary.texture(str(GameData.discovery.get("clue_icon_path", "")).replace("{type}", icon_key)))

# --- 分段進食與搶食 ---

func _feeding_prey_name() -> String:
	return _prey_name(str(GameState.current_feeding.get("animal_id", "")), str(GameState.current_feeding.get("life_stage", "adult")))

# intro：接在進食畫面最上面的前情（例如搶食的對手被趕走），讓畫面不會直接跳到剩下幾段肉。
func _show_feeding(intro: String = "") -> void:
	var f: Dictionary = GameState.current_feeding
	if f.is_empty():
		encounter_overlay.visible = false
		return
	var value: int = int(round(float(f["segment_value"])))
	encounter_message.text = (intro + "\n" if intro != "" else "") + tr("feeding.status").replace("{animal}", _feeding_prey_name()) \
		.replace("{n}", str(f["segments_left"])).replace("{v}", str(value))
	var chances := GameState.scavenge_chances()
	encounter_detail.text = tr("feeding.risk").replace("{bear}", str(int(round(float(chances["bear"]) * 100.0)))) \
		.replace("{fox}", str(int(round(float(chances["fox"]) * 100.0))))
	# 離開的話：不在時一天大約少幾段（Phase 2b 第 1 步）
	if int(f["segments_left"]) > 0:
		encounter_detail.text += "\n" + tr("feeding.leave_loss").replace("{n}", "%.1f" % GameState.carcass_loss_per_day_absent({"region_id": GameState.current_region, "segments_left": f["segments_left"], "segment_value": f.get("segment_value", 25.0)}))
	if float(chances.get("wolverine", 0.0)) > 0.0 and GameState.is_identified("wolverine"):
		encounter_detail.text += tr("feeding.risk.wolverine").replace("{n}", str(int(round(float(chances["wolverine"]) * 100.0))))
	elif float(chances.get("wolverine", 0.0)) > 0.0:
		encounter_detail.text += tr("feeding.risk.ravens")
	_set_wolf_pose(encounter_sprite, "eat")
	_set_terrain_bg(encounter_bg, str(f.get("terrain", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("feeding.eat").replace("{v}", str(value)), _on_feed)
	# 叼一段去藏（Phase 2e）：滿了而且都新鮮時灰掉；有過了新鮮期的寫「換掉放太久的那段」
	var cache_status: String = GameState.cache_status()
	if cache_status != "no":
		_add_encounter_button(tr("feeding.cache.replace" if cache_status == "replace" else "feeding.cache"), func():
			GameState.action_cache_segment()
			if GameState.wolf != null and not GameState.wolf.alive:
				_on_wolf_died(GameState.wolf.death_cause)
				return
			_show_feeding()
			_refresh()
		)
		var cache_btn: Button = encounter_buttons_box.get_child(encounter_buttons_box.get_child_count() - 1)
		cache_btn.disabled = cache_status == "full"
		cache_btn.tooltip_text = tr("feeding.cache.full").replace("{n}", str(int(GameData.balance.get("cache", {}).get("max_segments", 2)))) if cache_status == "full" else tr("feeding.cache.tip")
	# 叼一段回巢穴（Phase 3 第 5 步）：幼狼要靠你餵的季節
	if GameState.can_carry_to_den():
		_add_encounter_button(tr("feeding.carry_den"), func():
			GameState.carry_to_den()
			_log(tr("den.carrying").replace("{region}", tr("region." + GameState.pup_spot())))
			_show_feeding()
			_refresh()
		)
		var carry_btn: Button = encounter_buttons_box.get_child(encounter_buttons_box.get_child_count() - 1)
		carry_btn.tooltip_text = tr("feeding.carry_den.tip").replace("{days}", str(snapped(GameState.den_food_days(), 0.5)))
	_add_encounter_button(tr("feeding.leave"), func():
		GameState.leave_feeding()
		_log(tr("log.feeding_left"))
		encounter_overlay.visible = false
	)
	encounter_overlay.visible = true

func _on_feed() -> void:
	var res := GameState.feed_once()
	if res.is_empty():
		encounter_overlay.visible = false
		if GameState.wolf != null and not GameState.wolf.alive:
			_on_wolf_died(GameState.wolf.death_cause)
		return
	_log(tr("log.feeding_ate").replace("{v}", str(int(round(float(res["gain"]))))))
	if res.get("event", "") != "":
		_show_scavenger(res["event"], false)
	elif GameState.is_feeding():
		_show_feeding()
	else:
		_log(tr("log.feeding_done"))
		encounter_overlay.visible = false

# 灰熊或狐狸來搶食。returning：回到殘骸時撞見。
# 發現的殘骸（渡鴉、凍死的動物）旁已經有別的動物：先交代發現的經過，按「繼續」才進入對峙（QA-43）。
func _show_found_scavenger(event: String) -> void:
	var text: String = tr("scavenger.found." + _scavenger_text_key(event))
	_log(text)
	# 跟著渡鴉找到的：字卡上先寫發現殘骸的那一句
	encounter_message.text = (_found_intro + "\n" + text) if _found_intro != "" else text
	_found_intro = ""
	encounter_detail.text = ""
	var sprite: Dictionary = {"bear": ["grizzly_bear", "adult" if GameState.is_identified("grizzly_bear") else "distant"],
		"fox": ["red_fox", "adult"], "wolverine": ["wolverine", "adult"], "tundra_wolves": ["tundra_wolf", "adult"]}
	var sp: Array = sprite.get(event, ["red_fox", "adult"])
	_set_creature(encounter_sprite, str(sp[0]), str(sp[1]), "move")
	_set_terrain_bg(encounter_bg, str(GameState.current_feeding.get("terrain", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("ui.continue"), func(): _show_scavenger(event, true, true))
	encounter_overlay.visible = true

# 搶食者的文案鍵尾：苔原狼依剩幾隻、認不認得；狼獾與灰熊依認不認得。
func _scavenger_text_key(event: String) -> String:
	match event:
		"tundra_wolves":
			return "tundra_wolves" + ("" if GameState.tundra_pair().size() > 1 else ".single") + ("" if GameState.is_identified("tundra_wolf") else ".first")
		"wolverine":
			return "wolverine" + ("" if GameState.is_identified("wolverine") else ".first")
		"bear":
			return "bear" if GameState.is_identified("grizzly_bear") else "bear_unknown"
	return event

# intro_logged：發現殘骸的經過已經交代過（_show_found_scavenger），這裡不再寫「你回來時」。
func _show_scavenger(event: String, returning: bool, intro_logged: bool = false) -> void:
	if event == "challenger":
		_show_challenger({"first": int(GameState.life_log.get("challenger_visits", 0)) == 0}, true)
		return
	# 美洲獅回來找牠的獵物、黑熊被氣味引來（Phase 2 第 3 步）
	if event == "ranch_patrol":
		_show_ranch_encounter(GameState.start_ranch_encounter("eating", str(GameState.current_feeding.get("terrain", ""))))
		return
	if event in ["cougar", "black_bear", "coyote"]:
		var known: bool = GameState.is_identified(event)
		if not intro_logged:
			_log(tr("scavenger.%s.%s%s" % [event, "returning" if returning else "arrive", "" if known else ".first"]))
		_begin_combat(GameState.start_combat(event, "adult", "carcass"), "move")
		return
	if event == "she_wait":
		var st: String = tr("scavenger.she_wait")
		_log(st)
		encounter_message.text = st
		encounter_detail.text = ""
		_set_creature(encounter_sprite, "tundra_wolf", "adult", "idle")
		_clear_children(encounter_buttons_box)
		_add_encounter_button(tr("she_wolf.wait.share"), func():
			GameState.she_wait_choice(true)
			_log(tr("she_wolf.wait.shared"))
			_show_feeding()
		)
		_add_encounter_button(tr("she_wolf.wait.keep"), func():
			GameState.she_wait_choice(false)
			_show_feeding()
		)
		encounter_overlay.visible = true
		return
	if event == "tundra_wait":
		var text: String = _tt("scavenger.tundra_wait")
		_log(text)
		encounter_message.text = text
		encounter_detail.text = ""
		_set_creature(encounter_sprite, "tundra_wolf", "adult", "idle")
		_clear_children(encounter_buttons_box)
		_add_encounter_button(_tt("tundra.wait.share"), func():
			GameState.tundra_wait_choice(true)
			_log(_tt("tundra.wait.shared"))
			_show_feeding()
		)
		_add_encounter_button(tr("tundra.wait.keep"), func():
			GameState.tundra_wait_choice(false)
			_show_feeding()
		)
		encounter_overlay.visible = true
		return
	if event == "tundra_wolves":
		# 認得之前寫「毛色偏淺的狼」；只剩一隻時用單數（start_tundra_combat 才記辨識，所以這裡要先判斷）
		var suffix: String = ("" if GameState.tundra_pair().size() > 1 else ".single") + ("" if GameState.is_identified("tundra_wolf") else ".first")
		if not intro_logged:
			_log(tr("scavenger.tundra_wolves." + ("returning" if returning else "arrive") + suffix))
		_begin_combat(GameState.start_tundra_combat("carcass"), "move")
		return
	if event == "wolverine":
		var first: bool = not GameState.is_identified("wolverine")
		if not intro_logged:
			_log(tr("scavenger.wolverine.%s%s" % ["returning" if returning else "arrive", ".first" if first else ""]))
		_begin_combat(GameState.start_wolverine_combat(not returning), "move")
		return
	var bear_known: bool = event != "bear" or GameState.is_identified("grizzly_bear")
	var key: String = "scavenger.%s.%s" % [event, "returning" if returning else "arrive"]
	if not bear_known:
		key = "scavenger.bear_unknown"
	if intro_logged:
		key = "scavenger.found." + _scavenger_text_key(event)
	else:
		_log(tr(key))
	# 認得的灰熊：先選怎麼從牠口中搶肉，或對峙、放棄（1.8 第 7 步）
	if event == "bear" and bear_known:
		_show_bear_steal(tr(key))
		return
	# 狐狸：進入戰鬥模式（守住、叼走一塊、放棄、不理都在對峙畫面選）
	if bear_known:
		_begin_combat(GameState.start_combat("grizzly_bear" if event == "bear" else "red_fox", "adult", "carcass"), "move")
		return
	encounter_message.text = tr(key)
	encounter_detail.text = ""
	if event == "bear":
		_set_creature(encounter_sprite, "grizzly_bear", "adult" if bear_known else "distant", "move")
	else:
		_set_creature(encounter_sprite, "red_fox", "adult", "move")
	_clear_children(encounter_buttons_box)
	# 辨識前不能守住（第一次遇到灰熊不該就被打死）
	_add_encounter_button(tr("scavenger.grab"), _on_scavenger_choice.bind("bear", "grab"))
	_add_encounter_button(tr("scavenger.abandon"), _on_scavenger_choice.bind("bear", "abandon"))
	encounter_overlay.visible = true

# 灰熊佔住殘骸（1.8 第 7 步，提案之九）：咬一塊就跑、整個叼走（或撕一條後腿）、對峙、放棄。
func _show_bear_steal(text: String) -> void:
	encounter_message.text = text
	encounter_detail.text = tr("bear_steal.hint")
	_set_creature(encounter_sprite, "grizzly_bear", "adult", "idle")
	_set_terrain_bg(encounter_bg, str(GameState.current_feeding.get("terrain", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("bear_steal.bite") + "　" + _chance_text(GameState.bear_steal_chance("bite"), "grizzly_bear"),
		_on_bear_steal.bind("bite"))
	var carry_key: String = "bear_steal.carry_whole" if GameState.bear_carry_is_whole() else "bear_steal.carry_leg"
	_add_encounter_button(tr(carry_key) + "　" + _chance_text(GameState.bear_steal_chance("carry"), "grizzly_bear") + "　" + tr("bear_steal.danger"),
		_on_bear_steal.bind("carry"))
	_add_encounter_button(tr("bear_steal.confront"), func():
		_begin_combat(GameState.start_combat("grizzly_bear", "adult", "carcass"), "move"))
	_add_encounter_button(tr("scavenger.abandon"), _on_scavenger_choice.bind("bear", "abandon"))
	encounter_overlay.visible = true

func _on_bear_steal(kind: String) -> void:
	var res := GameState.resolve_bear_steal(kind)
	_log(tr("bear_steal.result." + str(res["outcome"])).replace("{n}", str(int(res.get("damage", 0)))))
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		encounter_overlay.visible = false
		_on_wolf_died(GameState.wolf.death_cause)
		return
	if GameState.is_feeding():
		_show_bear_steal(tr("bear_steal.still"))
	else:
		encounter_overlay.visible = false

func _on_scavenger_choice(event: String, choice: String) -> void:
	var res := GameState.resolve_scavenger(event, choice)
	_log(tr("scavenger.result." + str(res.get("outcome", choice))).replace("{n}", str(int(res.get("damage", 0)))))
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		encounter_overlay.visible = false
		_on_wolf_died(GameState.wolf.death_cause)
		return
	if GameState.is_feeding():
		_show_feeding()
	else:
		encounter_overlay.visible = false

# --- 主動事件 ---

# 暴雨用粒子效果（CLAUDE.md：暴雨不需要另外的圖）。
func _build_rain() -> void:
	rain = CPUParticles2D.new()
	rain.emitting = false
	rain.amount = 220
	rain.lifetime = 1.2
	rain.position = Vector2(340, -10)
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(380, 1)
	rain.direction = Vector2(-0.2, 1)
	rain.spread = 2.0
	rain.gravity = Vector2.ZERO
	rain.initial_velocity_min = 300.0
	rain.initial_velocity_max = 380.0
	rain.scale_amount_min = 1.0
	rain.scale_amount_max = 2.0
	rain.color = Color(0.7, 0.8, 1.0, 0.55)
	# 細長的雨絲，沿落下方向對齊
	var streak := Image.create(1, 6, false, Image.FORMAT_RGBA8)
	streak.fill(Color(1, 1, 1, 1))
	rain.texture = ImageTexture.create_from_image(streak)
	rain.particle_flag_align_y = true
	rain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(rain)

func _overlay_busy() -> bool:
	return session_active or current_hunt != null or current_combat != null or encounter_overlay.visible or hunt_overlay.visible or rest_overlay.visible \
		or debug_overlay.visible or region_info_overlay.visible or card_overlay.visible

# 目前的行動結束、沒有其他畫面開著時，依序處理世界主動找上門的事件。
func _process_events() -> void:
	if GameState.wolf == null or not GameState.wolf.alive or _overlay_busy():
		return
	var event := GameState.pop_event()
	if event.is_empty():
		return
	match event.get("type", ""):
		"storm":
			_log(tr("event.storm"))
		"rain_stopped":
			_log(tr("event.rain_stopped"))
		"howl":
			var entry := {"type": "territory", "animal": "stranger_wolf", "region": event["region"]}
			var howl_text: String = tr("event.howl.%d" % max(1, GameState.knowledge_level(entry))).replace("{region}", tr("region." + str(event["region"])))
			# 黑狼成家後：兩個聲音、好幾個聲音，夏季有幼狼的尖嚎（Phase 3a 第 2 步）
			if str(event.get("pack", "solo")) in ["pair", "pack"]:
				howl_text += tr("pack.sign.howl." + str(event["pack"]))
				if event.get("pups", false):
					howl_text += tr("pack.sign.howl.pups")
			_log(howl_text)
		"driven_off":
			var to: String = GameState.apply_drive_off()
			# 還沒到可以和牠對上的時機（這一局要等成年）：說一句，讓玩家知道要等
			var young: String = "" if GameState.stranger_can_interact() else tr("event.driven_off.too_young")
			_show_event_message(tr("event.driven_off").replace("{region}", tr("region." + to)) + young, "stranger_wolf")
		"stranger_confront":
			_show_stranger_confront()
			return
		"pack_meet":
			_show_pack_meet(event)
			return
		"fire_warning":
			var warn_key: String = "far" if event.get("far", false) else ("late" if event.get("late", false) else "early")
			_show_event_message(tr("fire.warning." + warn_key) \
				.replace("{origin}", tr("region." + str(event.get("origin", "")))), "white_tailed_deer", "fire_sign")
			return
		"fire_here":
			_show_fire_escape(event)
			return
		"fire_over":
			_show_fire_over(event)
			return
		"blizzard_warning":
			_show_event_message(tr("blizzard.warning." + ("late" if event.get("late", false) else "early")), "caribou", "blizzard_sign")
			return
		"blizzard_far":
			_log(tr("blizzard.far"))
		"blizzard_here":
			_show_blizzard(event)
			return
		"blizzard_over":
			_show_blizzard_over(event)
			return
		"whiteout":
			_log(tr("event.whiteout"))
		"ice_break":
			_show_ice_break(event)
			return
		"ravens":
			_show_ravens(event)
			return
		"tundra_howl":
			_show_tundra_howl(event)
			return
		"tundra_come":
			_show_tundra_meet({"charge": event.get("charge", false), "location": "", "came": true})
			return
		"prey_nearby":
			_show_prey_nearby(event)
			return
		"bear_passing":
			_show_bear_passing(event)
			return
		"season_card":
			_show_season_card(event)
			return
		"ranch_warning":
			_show_event_message(tr("ranch.warning"), "", "ranch_hunt")
			return
		"ranch_humans":
			_show_ranch_encounter(GameState.start_ranch_encounter(str(event.get("kind", "patrol"))))
			return
		"ranch_news":
			_show_event_message(tr("ranch.news").replace("{region}", tr("region." + str(event.get("region", "")))), "")
			encounter_sprite.show_static(ArtLibrary.icon("clue.fence"))
			return
		"sleep_summary":
			_show_sleep_summary(event.get("summary", {}))
			return
		"sleep_growth":
			_show_sleep_growth(event.get("summary", {}))
		"day_summary":
			_show_day_summary(event)
			return
		"stranger_killed":
			# 咬死黑狼的專屬卡片，接牠的傳說作結尾（SPEC「陌生灰狼」勝負的結果）
			var region: String = tr("region." + str(event.get("region", "")))
			var killed_body: String = tr("stranger.killed_card").replace("{region}", region)
			# 第一次打贏就咬死牠：成長接在這張卡片裡
			if event.has("first_win"):
				killed_body += _first_win_growth_text(event["first_win"])
			_show_card(tr("stranger.killed_card.title"), killed_body,
				ArtLibrary.region_background(str(event.get("region", GameState.current_region)), GameTime.current_season()))
			return
		"first_win":
			_show_first_win(event)
			return
		"injury_notice":
			_show_injury_notice(event)
			if int(event.get("severity", 0)) == Wolf.Injury.HEAVY:
				return
		"tendency_changed":
			_show_tendency_changed(event)
			return
		"year_review":
			_show_year_review(event.get("summary", {}))
			return
		"she_wolf_sign":
			var sign_text: String = tr("she_wolf.sign." + str(event.get("how", "scent")))
			var sr: String = str(event.get("region", ""))
			sign_text += tr("she_wolf.sign.here") if sr == GameState.current_region else tr("she_wolf.sign.near").replace("{region}", tr("region." + sr))
			_show_event_message(sign_text, "tundra_wolf")
			return
		"neighbor_howl":
			_show_event_message(tr("pack_sign.howl" + (".many" if event.get("many", false) else "")).replace("{region}", tr("region." + str(event.get("region", "")))), "stranger_wolf")
			return
		"territory_lost", "territory_won":
			_show_card(tr("territory_card.title." + str(event["type"]).trim_prefix("territory_")), tr("territory_card." + str(event["type"]).trim_prefix("territory_")).replace("{region}", tr("region." + str(event.get("region", "")))))
			_set_card_wolf("")
			return
		"pups_expected", "pups_born", "pups_weaned", "pups_follow":
			var pk: String = str(event["type"]).trim_prefix("pups_")
			_show_card(tr("pups.title." + pk), tr("pups." + pk + (".nomate" if pk == "weaned" and not event.get("mate", true) else "")).replace("{n}", str(int(event.get("n", 0)))).replace("{region}", tr("region." + str(event.get("region", "")))))
			_set_card_wolf("")
			return
		"pups_hungry":
			_show_event_message(tr("pups.hungry").replace("{region}", tr("region." + GameState.pup_spot())), "")
			return
		"pup_died":
			_show_event_message(tr("pups.died." + ("hunger" if str(event.get("cause", "")) == "hunger" else ("weak" if str(event.get("cause", "")) == "weak" else "predator"))) + (tr("pups.left").replace("{n}", str(int(event.get("left", 0)))) if int(event.get("left", 0)) > 0 else tr("pups.none_left")), "")
			return
		"den_threat":
			_show_den_threat(str(event.get("animal", "coyote")))
			return
		"she_wolf_mate":
			_show_card(tr("she_wolf.mate.title"), tr("she_wolf.mate." + str(event.get("how", "courted"))))
			_set_card_wolf("")
			return
		"yearling":
			_show_card(tr("yearling.title"), tr("yearling.body"))
			_set_card_wolf("")
			return
		"first_big_kill":
			_show_card(tr("first_big_kill.title"), tr("first_big_kill.body").replace("{animal}", TextFormat.prey_name(str(event.get("animal", "")), str(event.get("stage", "adult")))))
			return
		"adult_transition":
			_show_adult_transition()
			return
		"elder_transition":
			_show_elder_transition()
			return
	_refresh()

# 年度回顧卡（1.8 第 11 步）：一句總結與這一年的數字
func _show_year_review(s: Dictionary) -> void:
	var lines: Array[String] = [tr("year.headline." + str(s.get("headline", "quiet")))]
	lines.append(tr("year.kills").replace("{n}", str(int(s.get("kills", 0)))))
	if str(s.get("biggest", "")) != "":
		lines.append(tr("year.biggest").replace("{animal}", TextFormat.prey_name(str(s["biggest"]), str(s.get("biggest_stage", "adult")))))
	if int(s.get("heavy", 0)) > 0:
		lines.append(tr("year.heavy").replace("{n}", str(int(s["heavy"]))))
	var parts: Array[String] = []
	var changes: Dictionary = s.get("changes", {})
	for stat in changes.keys():
		var d: int = int(round(float(changes[stat])))
		if d != 0:
			parts.append("%s %s%d" % [tr("stat." + str(stat)), "+" if d > 0 else "", d])
	if not parts.is_empty():
		lines.append(tr("year.changes").replace("{list}", "　".join(parts)))
	_show_card(tr("year.title").replace("{n}", str(int(s.get("n", 1)))), "\n".join(lines))
	_set_card_wolf("")

# image_key：art.json 的 events（例如暴風雪徵兆），有圖就用圖，沒有才用動物。
func _show_event_message(text: String, sprite_id: String, image_key: String = "") -> void:
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	var event_tex: Texture2D = ArtLibrary.event_image(image_key) if image_key != "" else null
	if event_tex != null:
		encounter_sprite.show_static(event_tex)
	else:
		_set_creature(encounter_sprite, sprite_id, "adult")
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("ui.continue"), func():
		encounter_overlay.visible = false
		_refresh()
		if GameState.wolf != null and not GameState.wolf.alive:
			_on_wolf_died(GameState.wolf.death_cause)
	)
	encounter_overlay.visible = true

func _show_prey_nearby(event: Dictionary) -> void:
	var name: String = _prey_name(str(event["animal_id"]), str(event["life_stage"]))
	var text: String = tr("event.prey_nearby").replace("{animal}", name)
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, str(event["animal_id"]), str(event["life_stage"]), "move")
	_set_terrain_bg(encounter_bg, str(event.get("terrain", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("hunt.option.pounce"), func():
		encounter_overlay.visible = false
		current_hunt = GameState.hunt_nearby_prey(event)
		_enter_hunt()
	)
	_add_encounter_button(tr("ui.ignore"), func():
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

func _show_bear_passing(event: Dictionary) -> void:
	# 辨識前看到的灰熊一律是遠距目擊
	if not GameState.is_identified("grizzly_bear"):
		_show_distant({"encountered": true, "animal_id": "grizzly_bear", "life_stage": "adult", "distant": true})
		return
	var text: String = tr("event.bear_passing")
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, "grizzly_bear", "adult", "move")
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("event.bear_passing.hide").replace("{n}", str(int(round(GameState.bear_hide_chance() * 100.0)))), func():
		var res := GameState.resolve_bear_passing(event, "hide")
		encounter_overlay.visible = false
		if res["outcome"] == "hidden":
			_log(tr("event.bear_passing.hidden"))
			_refresh()
		else:
			_log(tr("event.bear_passing.spotted"))
			_on_encounter_triggered(res["encounter"])
	)
	_add_encounter_button(tr("event.bear_passing.leave"), func():
		GameState.resolve_bear_passing(event, "leave")
		_log(tr("event.bear_passing.left"))
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# --- 試玩紀錄（SPEC「遊戲內自動紀錄」）---

# 文字檢查（文案一致性 A）：畫面或紀錄出現原始翻譯鍵、沒替換的 {佔位} 時，記進試玩紀錄；
# 在編輯器裡遊玩時另外淡出提示一次，方便當下截圖。
const TEXT_WATCH_INTERVAL := 0.5
var text_watch := TextWatch.new()
var text_watch_timer: float = 0.0

func _report_text_issues(found: Array) -> void:
	if found.is_empty() or not OS.has_feature("editor"):
		return
	for item in found:
		_show_toast(tr("debug.text_issue").replace("{token}", str(item[1])), 3.0)

func _show_playtest_stats() -> void:
	var stats: Dictionary = GameState.life_log.get("stats", {})
	var counts: Dictionary = stats.get("option_counts", {})
	var counters: Dictionary = stats.get("counters", {})
	var lines: Array[String] = [tr("stats.title")]
	var ms := GameState.metrics_summary()
	lines.append(tr("stats.metrics").replace("{minutes}", str(ms["play_minutes"])).replace("{decisions}", str(ms["decisions_per_day"])) \
		.replace("{events}", str(ms["events_per_day"])).replace("{quiet}", str(ms["longest_quiet_days"])) \
		.replace("{best}", str(int(round(float(ms["best_choice_ratio"]) * 100.0)))).replace("{quick}", str(int(round(float(ms["quick_card_ratio"]) * 100.0)))))
	for issue in ms.get("text_issues", []):
		lines.append(tr("stats.text_issue").replace("{issue}", str(issue)))
	# 每個階段內各選項的選擇率；超過 80% 代表可能是最佳解
	var by_stage: Dictionary = {}
	for key in counts.keys():
		var stage: String = str(key).split(".")[0]
		by_stage[stage] = int(by_stage.get(stage, 0)) + int(counts[key])
	var keys: Array = counts.keys()
	keys.sort()
	for key in keys:
		var stage: String = str(key).split(".")[0]
		var rate: float = float(counts[key]) / max(1, int(by_stage[stage]))
		var flag: String = "　" + tr("stats.dominant") if rate > 0.8 and int(by_stage[stage]) >= 5 else ""
		lines.append("%s：%d（%d%%）%s" % [key, int(counts[key]), int(round(rate * 100.0)), flag])
	var observe_chances: int = int(counters.get("observe_opportunities", 0))
	lines.append(tr("stats.observe").replace("{n}", str(int(counts.get("observe.observe", 0)))).replace("{total}", str(observe_chances)))
	lines.append(tr("stats.give_ups").replace("{n}", str(int(GameState.life_log.get("chase_give_ups", 0)))))
	lines.append(tr("stats.nights").replace("{den}", str(int(stats.get("nights", {}).get("den", 0)))).replace("{wild}", str(int(GameState.life_log.get("wild_nights", 0)))))
	lines.append(tr("stats.wind_failures").replace("{n}", str(int(counters.get("wind_failures", 0)))))
	var after: Array = stats.get("after_deer", [])
	if not after.is_empty():
		var total_days: int = 0
		for entry in after:
			total_days += int(entry["days"])
		lines.append(tr("stats.after_deer_avg").replace("{n}", str(after.size())).replace("{avg}", "%.1f" % (float(total_days) / after.size())))
	for entry in after.slice(max(0, after.size() - 3)):
		var acts: Array[String] = []
		for a in entry["actions"].keys():
			acts.append("%s %d" % [tr("action." + str(a)), int(entry["actions"][a])])
		lines.append(tr("stats.after_deer").replace("{days}", str(int(entry["days"]))).replace("{actions}", "、".join(acts)))
	region_info_text.text = "\n".join(lines)
	region_info_overlay.visible = true

# --- 區域資訊 ---

func _build_region_info_overlay() -> void:
	region_info_overlay = Panel.new()
	region_info_overlay.visible = false
	region_info_overlay.anchor_right = 1.0
	region_info_overlay.anchor_bottom = 1.0
	region_info_overlay.theme_type_variation = &"OverlayPanel"
	add_child(region_info_overlay)
	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 12
	root.offset_top = 8
	root.offset_right = -12
	root.offset_bottom = -8
	region_info_overlay.add_child(root)
	region_info_text = RichTextLabel.new()
	region_info_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(region_info_text)
	var close_btn := Button.new()
	close_btn.text = tr("debug.close")
	close_btn.pressed.connect(func(): region_info_overlay.visible = false)
	root.add_child(close_btn)

# 已知的特徵顯示名稱，未知的以「？」表示；沒去過的區域連主要地形都是「？」。
# --- 知識 ---

func _source_name(source: String) -> String:
	return TextFormat.source_name(source)

func _knowledge_text(entry: Dictionary) -> String:
	return TextFormat.knowledge_text(entry)

func _explore_hint() -> String:
	var ctx := {"region_id": GameState.current_region, "season": GameTime.current_season(), "period": GameTime.current_period(),
		"depletion": GameState.region_depletion.get(GameState.current_region, {}),
		"known_features": GameState.known_features(GameState.current_region),
		"prey_knowledge": GameState.prey_knowledge_mults(GameState.current_region, GameTime.current_period())}
	var best: String = ""
	var best_chance: float = 0.0
	for animal_id in ctx["prey_knowledge"].keys():
		var c := ExploreSystem.estimate_prey_chance(ctx, animal_id)
		if c > best_chance:
			best = animal_id
			best_chance = c
	if best == "":
		return ""
	return tr("ui.explore_hint").replace("{n}", str(int(round(best_chance * 100.0)))).replace("{animal}", tr("animal." + best))

func _show_knowledge() -> void:
	region_info_text.bbcode_enabled = false
	var lines: Array[String] = [tr("ui.knowledge.title")]
	var order := ["prey", "danger", "opponent", "weakness", "overhunt"]
	var entries: Array = GameState.knowledge.values()
	entries.sort_custom(func(a, b):
		if a["type"] != b["type"]:
			return order.find(a["type"]) < order.find(b["type"])
		return int(a["count"]) > int(b["count"]))
	for entry in entries:
		lines.append(_knowledge_text(entry))
	for region_id in _all_regions():
		for f in GameState.known_features(region_id):
			lines.append(tr("knowledge.feature").replace("{region}", tr("region." + region_id)).replace("{feature}", tr("feature." + str(f))))
	if lines.size() == 1:
		lines.append(tr("ui.knowledge.empty"))
	region_info_text.text = "\n".join(lines)
	region_info_overlay.visible = true

func _show_region_info() -> void:
	region_info_text.bbcode_enabled = false
	var unknown: String = tr("ui.unknown")
	var lines: Array[String] = [tr("ui.region_info")]
	for region_id in _all_regions():
		if GameData.map_of(region_id) != GameData.map_of(GameState.den_region) and not GameState.is_region_visited(region_id):
			continue
		var data: Dictionary = EncounterSystem.region_data(region_id)
		var visited: bool = GameState.is_region_visited(region_id)
		var main: String = tr("region_main." + str(data.get("main_feature", ""))) if visited else unknown
		var known: Array = GameState.known_features(region_id)
		var parts: Array[String] = []
		for f in data.get("secondary_features", []):
			parts.append(tr("feature." + str(f)) if known.has(f) else unknown)
		lines.append("")
		lines.append(tr("region." + region_id) + "：" + main)
		lines.append("　" + tr("ui.region_info.features") + "：" + "、".join(parts))
		if visited and data.has("den_bonus"):
			lines.append("　" + tr("ui.region_info.den_bonus." + region_id))
		if GameState.is_own_territory(region_id):
			lines.append("　" + tr("ui.region_info.territory").replace("{n}", str(GameState.mark_days_left(region_id))))
	region_info_text.text = "\n".join(lines)
	region_info_overlay.visible = true

func _show_find_result(result: Dictionary) -> void:
	var animal_id: String = result["animal_id"]
	var life_stage: String = result["life_stage"]
	var prey_dir: int = int(result.get("prey_dir", -1))
	var wind_text: String = tr("factor.wind." + str(result.get("wind", "crosswind")))
	_log(tr("log.find_tracks.success") + "：" + tr("animal." + animal_id) + "（" + wind_text + "）")
	encounter_message.text = tr("log.find_tracks.success") + "\n" + tr("animal." + animal_id) + "　" + wind_text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, animal_id, life_stage)
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	_add_hunt_button(tr("ui.hunt"), func():
		encounter_overlay.visible = false
		_begin_hunt(animal_id, life_stage, prey_dir)
	)
	_add_encounter_button(tr("ui.ignore"), func(): encounter_overlay.visible = false)
	encounter_overlay.visible = true

# --- Hunting ---

func _begin_hunt(animal_id: String, life_stage: String, prey_dir: int = -1) -> void:
	current_hunt = GameState.start_hunt(animal_id, life_stage, prey_dir)
	_enter_hunt()

# 開始狩獵畫面：白尾鹿、馬鹿、騾鹿、馴鹿走戰術地圖，其他走選單。看到獵物、追蹤到獵物、發現足跡都經過這裡
# （2026-10-20 試玩：看到一群白尾鹿選「狩獵」沒有進戰術地圖——目擊、追蹤原本直接走選單）。
# 獵物靠近（短版開場）、和苔原狼一起狩獵、受傷的個體、躲在草裡的幼鹿、牧場的家畜也走戰術地圖（Phase 2i）：
# 所有獵物都在 game.animals 裡，選單式的畫面不會再出現（程式留著，模擬對照用；田鼠、地松鼠的小撲另外處理）。
func _enter_hunt() -> void:
	if GameState.tactical_eligible(current_hunt):
		_open_tactical()
		return
	_render_hunt_stage()

# 戰術狩獵（Phase 2c 第 2 步）：白尾鹿改在戰術地圖上狩獵，結束後照一般的狩獵結算
const TACTICAL_SCENE := "res://prototypes/tactical_hunt/TacticalHunt.tscn"
var tactical_view: Control = null

func _open_tactical() -> void:
	var view: Control = load(TACTICAL_SCENE).instantiate()
	add_child(view)
	tactical_view = view
	view.start_from_game(GameState.start_tactical(current_hunt), func(th):
		tactical_view = null
		var ok: bool = th.result == "caught"
		if th.result == "gave_up":
			current_hunt.condition_known = current_hunt.condition_known or th.condition_known
			current_hunt.condition = th.condition if current_hunt.condition == "" else current_hunt.condition
			_log(tr(current_hunt.give_up_text_key()).replace("{animal}", _hunt_prey_name()))
		GameState.finish_tactical_hunt(current_hunt, th)
		_after_hunt(ok)
		# 從遭遇畫面按「狩獵」進來的：這一段遭遇在這裡結束（交代結果、按「繼續」回主畫面）
		if session_active and not session_check_pending:
			session_check_pending = true
			_check_session_end.call_deferred())

# 依 HuntSystem.options() 畫出目前階段的選項；階段說明下方是觀察到的獵物狀態與搏鬥進度。
var hunt_notes: Array[String] = []
var hunt_notes_log: String = "" # 觀察結果寫進紀錄的那一句；狩獵畫面上方已經列出，下方紀錄不再重複

# 把幾段短句排成幾行：一段不拆開，放不下才換行（試玩回報：觀察到的狀態接成一長串時，句子在中間被折斷）
func _pack_phrases(parts: Array[String], label: Label) -> String:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var max_w: float = label.size.x if label.size.x > 0.0 else 600.0
	var lines: Array[String] = []
	for part in parts:
		if not lines.is_empty() and font.get_string_size(lines.back() + "　" + part, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			lines[lines.size() - 1] += "　" + part
		else:
			lines.append(part)
	return "\n".join(lines)

func _render_hunt_stage() -> void:
	if current_hunt == null:
		hunt_overlay.visible = false
		return
	hunt_overlay.visible = true
	combat_anim_btn.visible = false
	_clear_children(hunt_buttons_box)
	var animal_name: String = _hunt_prey_name()
	# 追擊時獵物在跑；狼的姿勢依階段：觀察、潛近伏低，追擊奔跑，撲抓、搏鬥撲擊
	var prey_action: String = "move" if current_hunt.stage == HuntSystem.Stage.CHASE else "idle"
	# 成群的獵物（馴鹿、馬鹿、成群的白尾鹿）在觀察階段顯示整群
	var herd: bool = current_hunt.in_herd and current_hunt.life_stage != "juvenile"
	if herd and current_hunt.stage == HuntSystem.Stage.OBSERVE:
		prey_action = "herd"
	# 搏鬥時獵物擺出反擊的姿勢（有圖的才會換，例如駝鹿的踢擊）
	if current_hunt.stage == HuntSystem.Stage.FIGHT:
		prey_action = "attack"
	# 搏鬥時獵物轉過來面向你（素材都面向右），其他階段照原方向（往右逃）
	hunt_sprite.flip_h = current_hunt.stage == HuntSystem.Stage.FIGHT
	_set_hunt_opponent(current_hunt.animal_id, current_hunt.life_stage)
	_set_creature(hunt_sprite, current_hunt.animal_id, current_hunt.life_stage, prey_action)
	var pose: String = "stalk"
	match current_hunt.stage:
		HuntSystem.Stage.CHASE: pose = "walk"
		HuntSystem.Stage.FIGHT, HuntSystem.Stage.POUNCE: pose = "pounce"
	_set_wolf_pose(hunt_wolf_sprite, pose)
	_set_terrain_bg(hunt_bg, current_hunt.terrain)
	var stage_key: String = "hunt.stage." + current_hunt.stage_name()
	if herd and current_hunt.stage == HuntSystem.Stage.OBSERVE:
		stage_key = "hunt.stage.observe_herd"
	var header: String = tr(stage_key).replace("{animal}", animal_name)
	var context: Array[String] = [tr("factor.wind." + current_hunt.wind_state())]
	if current_hunt.terrain != "":
		context.append(tr("explore.location." + current_hunt.terrain))
	header += "　" + "・".join(context)
	if current_hunt.stage == HuntSystem.Stage.CHASE:
		# 每回合顯示雙方體力的描述，讓玩家判斷要不要繼續追。
		var lines: Array[String] = []
		if current_hunt.chase_round > 0:
			lines.append(tr("hunt.chase.round").replace("{n}", str(current_hunt.chase_round + 1)))
		lines.append(tr(current_hunt.wolf_stamina_key()))
		var prey_text: String = tr(current_hunt.prey_stamina_key())
		var precise: int = current_hunt.prey_stamina_precise()
		if precise >= 0:
			prey_text += "（%d%%）" % precise
		lines.append(prey_text)
		if current_hunt.reaction == "stand":
			lines.append(tr("prey_reaction.stand"))
		header += "\n" + "　".join(lines)
	# 苔原狼一起狩獵：牠們幫的是改變條件、不直接加成功率，所以要寫出來（2026-10-15 試玩回報 20）
	if current_hunt.tundra_help > 0:
		var help: String = "other"
		if current_hunt.in_herd:
			help = "herd"
		elif HuntSystem.size_of(current_hunt.animal_id) == "large":
			help = "large"
		header += "\n" + _tt("hunt.tundra_help." + help)
	if current_hunt.stage == HuntSystem.Stage.POUNCE and current_hunt.hiding:
		header += "\n" + tr("hunt.hide.start").replace("{animal}", animal_name)
	if current_hunt.stage == HuntSystem.Stage.FIGHT:
		var wounds: int = int(current_hunt.fight_state.get("wounds", 0))
		if wounds > 0:
			header += "\n" + tr("hunt.fight.wounds").replace("{n}", str(wounds))
		if FightRules.in_danger(GameState.wolf):
			header += "\n" + tr("combat.danger")
	if not hunt_notes.is_empty():
		header += "\n" + _pack_phrases(hunt_notes, hunt_message)
	if GameState.wolf.in_burst:
		header += "\n" + tr("hunt.breath").replace("{n}", str(int(round(GameState.wolf.breath)))).replace("{max}", str(int(round(GameState.wolf.breath_max))))
	hunt_message.text = header
	for opt in current_hunt.options():
		var id: String = opt["id"]
		_add_hunt_choice(tr(opt["label_key"]), opt, func():
			_metric_choice(opt, current_hunt.options())
			if current_hunt.stage == HuntSystem.Stage.FIGHT:
				Audio.play_bite()
			_resolve_stage(current_hunt.choose(id))
		)
	_add_hunt_choice(tr("ui.give_up"), {}, func():
		_log(tr(current_hunt.give_up_text_key()).replace("{animal}", _hunt_prey_name()))
		current_hunt.give_up()
		_finish_hunt()
	)
	_fit_hunt_layout(hunt_buttons_box.get_children().filter(func(n): return not n.is_queued_for_deletion()).size())

# 失敗原因的鍵由因素組出來（reason.<因素>），沒寫原因文字的因素就不顯示，避免畫面出現原始的鍵名（2026-10-13）。
func _has_text(key: String) -> bool:
	return key != "" and tr(key) != key

func _hunt_prey_name() -> String:
	var name: String = _prey_name(current_hunt.animal_id, current_hunt.life_stage)
	return (tr("explore.injured") + name) if current_hunt.injured else name

func _prey_name(animal_id: String, life_stage: String) -> String:
	return TextFormat.prey_name(animal_id, life_stage)

# info 是 HuntSystem.options() 的一項：左邊是按鈕（名稱與成功率），右邊兩行是代價列與關鍵因素。
# 成功率的顯示：次成年期還沒經驗時只寫模糊說法（Phase 1.7b），否則寫百分比。
func _chance_text(chance: float, animal_id: String = "") -> String:
	var kind: String = "fight" if current_combat != null else "hunt"
	var id: String = animal_id
	if id == "":
		if current_combat != null:
			id = current_combat.animal_id
		elif current_hunt != null:
			id = current_hunt.animal_id
	if not GameState.chance_is_precise(kind, id):
		return tr(GameState.fuzzy_chance_key(chance))
	return "%d%%" % int(round(chance * 100.0))

func _add_hunt_choice(label: String, info: Dictionary, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	hunt_buttons_box.add_child(row)
	var btn := Button.new()
	btn.text = label
	if info.has("chance"):
		# 標出成功指的是什麼（狩獵：命中／成功；戰鬥：嚇退／命中／閃開／脫身）
		var prefix: String = tr(str(info["chance_key"])) + " " if info.has("chance_key") else ""
		btn.text += "　" + prefix + _chance_text(float(info["chance"]))
	btn.custom_minimum_size = Vector2(215, 0)
	btn.pressed.connect(_session_choice(label, callback))
	row.add_child(btn)
	var cost: String = _format_cost(info)
	if cost == "" and not info.has("factors"):
		return
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.alignment = BoxContainer.ALIGNMENT_CENTER
	detail.add_theme_constant_override("separation", 0)
	row.add_child(detail)
	if cost != "":
		var cost_label := _make_small_rich_label()
		cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cost_label.text = cost
		detail.add_child(cost_label)
	if info.has("factors"):
		# 因素只占一行（戰鬥選項多，換行會超出畫面高度）；放不下時以「…」截斷，完整內容在滑鼠提示
		var factor_label := Label.new()
		factor_label.text = _format_factors(info["factors"])
		factor_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		factor_label.clip_text = true
		factor_label.tooltip_text = factor_label.text
		factor_label.mouse_filter = Control.MOUSE_FILTER_PASS
		factor_label.theme_type_variation = &"DetailLabel"
		detail.add_child(factor_label)

func _make_small_rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.theme_type_variation = &"SmallRichLabel"
	label.modulate = UiTheme.color("hint")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# [img] 小圖示；找不到圖時不顯示。
func _icon_bb(key: String, size: int = 12) -> String:
	var path: String = ArtLibrary.icon_path(key)
	return "[img=%dx%d]%s[/img]" % [size, size, path] if path != "" else ""

# 代價列（SPEC 1.6「選項的代價與收穫」）：體力、下一階段的加成、練到的能力、多花的回合、受傷風險。沒有的項目不顯示。
func _format_cost(info: Dictionary) -> String:
	var parts: Array[String] = []
	var stamina: int = int(round(float(info.get("stamina", 0.0))))
	if stamina > 0:
		# 狩獵、戰鬥中扣的是喘（1.8 第 1 步）
		parts.append(_icon_bb("stat.stamina") + tr("cost.breath" if GameState.wolf != null and GameState.wolf.in_burst else "cost.stamina").replace("{n}", str(stamina)))
	var next: Dictionary = info.get("next_bonus", {})
	if float(next.get("value", 0.0)) > 0.0:
		parts.append(tr("cost.next_bonus").replace("{stage}", tr("cost.stage." + str(next["stage"]))) \
			.replace("{n}", str(int(round(float(next["value"]) * 100.0)))))
	if float(info.get("prey_drain", 0.0)) > 0.0:
		parts.append(tr("cost.prey_drain").replace("{n}", str(int(info["prey_drain"]))))
	var trains: Array = info.get("trains", [])
	if not trains.is_empty():
		var names: Array[String] = []
		for stat in trains:
			names.append(_icon_bb("stat." + str(stat)) + tr("stat." + str(stat)))
		parts.append(tr("cost.trains").replace("{list}", "、".join(names)))
	var turns: int = int(info.get("turns", 0))
	if turns > 0:
		parts.append(_icon_bb("cost.turns") + tr("cost.turns").replace("{n}", str(turns)))
	var risk: int = int(round(float(info.get("injury_risk", 0.0)) * 100.0))
	if risk > 0:
		parts.append("[color=%s]" % UiTheme.html("cost_risk") + _icon_bb("cost.injury_risk") + tr("cost.injury_risk").replace("{n}", str(risk)) + "[/color]")
	return "　".join(parts)

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
	GameState.spend_hunt_turns(int(stage_result.get("turns", 0)), current_hunt)
	var animal_name: String = _hunt_prey_name()
	for note in stage_result.get("notes", []):
		_log(tr(note).replace("{animal}", animal_name))
	if stage_result.has("prey_state"):
		hunt_notes.clear()
		for key in stage_result["prey_state"]:
			hunt_notes.append(tr(key))
		hunt_notes_log = tr("hunt.observe.success") + "　".join(hunt_notes)
		_log(hunt_notes_log)
		stage_result["text_key"] = ""
	if float(stage_result.get("damage", 0.0)) > 0.0:
		_log(tr("log.counter_damage").replace("{n}", str(int(stage_result["damage"]))))
	if stage_result.get("wind_shifted", false):
		_log(tr("log.wind_shifted").replace("{wind}", tr("factor.wind." + current_hunt.wind_state())))
	var text_key: String = stage_result.get("text_key", "")
	if text_key != "":
		_log(tr(text_key).replace("{animal}", animal_name))
	var reason_key: String = stage_result.get("reason_key", "")
	if _has_text(reason_key):
		_log(tr(reason_key).replace("{animal}", animal_name))
	if GameState.wolf != null and not GameState.wolf.alive:
		_finish_hunt()
	elif current_hunt.stage == HuntSystem.Stage.DONE:
		_finish_hunt()
	else:
		_render_hunt_stage()

func _finish_hunt() -> void:
	var succeeded: bool = current_hunt.result == HuntSystem.Result.SUCCESS
	GameState.finish_hunt(current_hunt)
	_after_hunt(succeeded)

func _after_hunt(succeeded: bool) -> void:
	if succeeded:
		_log_result(tr("hunt.result.success").replace("{animal}", _hunt_prey_name()))
	else:
		_log_result(tr("hunt.result.fail"))
	hunt_overlay.visible = false
	current_hunt = null
	hunt_notes.clear()
	hunt_notes_log = ""
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)
		return
	if GameState.is_feeding():
		_show_feeding()
		return
	# 獵物逃走：留下可再追的足跡
	if GameState.current_discovery.get("fled", false):
		_show_discovery(GameState.current_discovery)

# --- Competitor encounters ---

# 灰熊遭遇。辨識前一律是遠距目擊（_show_distant）；之後可能是母熊帶幼熊，或直接衝過來攻擊。
# 戰鬥中對手的名稱：帶著幼熊的母熊寫「母灰熊」（QA-71）。
func _combat_name(c: Combat) -> String:
	if c.mother and c.animal_id == "grizzly_bear":
		return tr("animal.grizzly_bear.mother")
	return _prey_name(c.animal_id, c.life_stage)

func _on_encounter_triggered(encounter: Dictionary) -> void:
	if GameState.auto_playing:
		return
	# 睡覺中被驚醒：先寫完在哪裡睡下、被驚醒，再進入遭遇（QA-70）
	if sleeping_now:
		woken_encounter = encounter
		return
	if encounter.get("distant", false):
		_show_distant(encounter)
		return
	if encounter.get("stranger_meet", false):
		_show_stranger_meet(encounter)
		return
	var animal_id: String = encounter.get("animal_id", "")
	var life_stage: String = encounter.get("life_stage", "adult")
	var key: String = "encounter.competitor"
	if encounter.get("mother", false):
		key = "encounter.mother"
	if encounter.get("direct", false):
		key = "encounter.direct_mother" if encounter.get("mother", false) else "encounter.direct"
	if encounter.get("salmon_stand", false):
		key = "encounter.salmon_stand"
	if encounter.get("woken", false):
		key = "encounter.woken_mother" if encounter.get("mother", false) else "encounter.woken"
		# 被驚醒時牠已經衝過來：不能寫「正盯著你」（2026-10-15 試玩回報 14、15）
		if encounter.get("direct", false):
			key = "encounter.woken_direct_mother" if encounter.get("mother", false) else "encounter.woken_direct"
	var intro: Array[String] = [tr(key).replace("{animal}", _prey_name(animal_id, life_stage))]
	# 直接衝撞的傷害在進入戰鬥前就扣了，要寫出來（試玩回報 15）
	if encounter.get("direct", false) and float(encounter.get("damage", 0.0)) > 0.0:
		intro.append(tr("encounter.direct_hit").replace("{n}", str(int(round(float(encounter["damage"]))))))
	for line in intro:
		_log(line)
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)
		return
	# 戰鬥畫面的開頭也寫出怎麼打起來的（紀錄欄之外，試玩回報 14）
	combat_intro = "".join(intro)
	_begin_combat(GameState.start_combat(animal_id, life_stage, "encounter", encounter),
		"attack" if encounter.get("direct", false) else "idle")

# 遠距目擊：灰熊或陌生灰狼在遠處，沒有發現狼。可以觀察（建立辨識、累積知識）或離開。
func _show_distant(encounter: Dictionary) -> void:
	var animal_id: String = encounter.get("animal_id", "grizzly_bear")
	var location: String = str(encounter.get("location", ""))
	var where: String = tr("explore.location." + location) if location != "" else tr("encounter.far_away")
	var text: String = tr("encounter.distant." + animal_id).replace("{location}", where).replace("{animal}", _source_name(animal_id))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, animal_id, "distant", "walk")
	_set_terrain_bg(encounter_bg, location)
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("encounter.observe"), func():
		GameState.action_observe_distant(encounter)
		_log(_observed_text(animal_id))
		encounter_overlay.visible = false
		_refresh()
	)
	_add_encounter_button(tr("ui.leave"), func():
		GameState.leave_distant(encounter)
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# --- 森林大火（SPEC 1.6「森林大火」） ---

# 火燒到你所在的區域：逃往還沒燒到的區域、到溪邊避難、躲進巢穴，各自附平安率。
func _show_fire_escape(event: Dictionary) -> void:
	# 火已經被暴雨澆熄（或熄滅）就不再跳逃生畫面
	if GameState.fire.is_empty() or str(GameState.fire.get("phase", "")) != "burning":
		return
	var region: String = str(event.get("region", GameState.current_region))
	var text: String = tr("fire.here" + (".entered" if event.get("entered", false) else "")).replace("{region}", tr("region." + region))
	if event.get("smoke", false):
		text = tr("fire.smoke")
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "walk")
	encounter_bg.texture = ArtLibrary.region_background(region, GameTime.current_season())
	encounter_bg.modulate = Color(1.0, 0.55, 0.35)
	_clear_children(encounter_buttons_box)
	for opt in GameState.fire_escape_options():
		var key: String = "fire.option." + str(opt["kind"])
		if opt["kind"] == "flee" and not GameState.is_region_visited(str(opt["region"])):
			key = "fire.option.flee_unknown"
		var label: String = tr(key).replace("{region}", tr("region." + str(opt["region"]))) \
			.replace("{n}", str(int(round(float(opt["safe"]) * 100.0))))
		var id: String = opt["id"]
		_add_encounter_button(label, func(): _on_fire_escape(id))
	encounter_overlay.visible = true

func _on_fire_escape(id: String) -> void:
	var res := GameState.fire_escape(id)
	encounter_bg.modulate = Color(1, 1, 1)
	encounter_overlay.visible = false
	if res.is_empty():
		return
	var result: String = str(res["result"])
	if result == "smoke":
		# 巢穴裡濃煙竄了進來：第二次逃生選擇（提案之十一）
		_show_fire_escape({"region": GameState.current_region, "smoke": true})
		return
	if result == "safe":
		_log(tr("fire.result.safe." + str(res["kind"])).replace("{region}", tr("region." + str(res["region"]))))
	elif result != "death":
		_log(tr("fire.result." + result))
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)

func _show_fire_over(event: Dictionary) -> void:
	var names: Array[String] = []
	for r in event.get("burned", []):
		names.append(tr("region." + str(r)))
	var body: String = tr("fire.over").replace("{list}", "、".join(names))
	if event.get("den_burned", false):
		body += "\n\n" + tr("fire.over.den").replace("{region}", tr("region." + GameState.den_region))
	_log(tr("fire.over").replace("{list}", "、".join(names)))
	var burned: Array = event.get("burned", [])
	_show_card(tr("fire.over.title"), body, ArtLibrary.region_background(str(burned[0]) if not burned.is_empty() else GameState.current_region, "burned"))

# --- 苔原的事件（1.6 第 6d 步） ---

func _weather_text() -> String:
	if GameState.blizzard_here():
		return "　" + tr("weather.blizzard")
	if GameState.whiteout_here():
		return "　" + tr("weather.whiteout")
	# 雪況寫在天氣後面（1.8 第 2 步）
	var snow_text: String = "" if GameState.snow_state() == "none" else "　" + tr("snow." + GameState.snow_state())
	return ("" if GameState.weather == "clear" else "　" + tr("weather." + GameState.weather)) + snow_text

# 暴風雪用粒子效果（同暴雨，不需要另外的圖）：斜吹的雪片。
func _build_snow() -> void:
	snow = CPUParticles2D.new()
	snow.emitting = false
	snow.amount = 400
	snow.lifetime = 2.0
	snow.position = Vector2(700, -10)
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(700, 1)
	snow.direction = Vector2(-1, 0.6)
	snow.spread = 12.0
	snow.gravity = Vector2.ZERO
	snow.initial_velocity_min = 220.0
	snow.initial_velocity_max = 320.0
	snow.scale_amount_min = 1.0
	snow.scale_amount_max = 2.5
	snow.color = Color(0.95, 0.97, 1.0, 0.7)
	var flake := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	flake.fill(Color(1, 1, 1, 1))
	snow.texture = ImageTexture.create_from_image(flake)
	snow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(snow)

func _show_blizzard(event: Dictionary) -> void:
	var region: String = str(event.get("region", GameState.current_region))
	var text: String = tr("blizzard.here").replace("{region}", tr("region." + region))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = tr("blizzard.detail")
	_set_wolf_pose(encounter_sprite, "walk")
	encounter_bg.texture = ArtLibrary.region_background(region, "winter")
	encounter_bg.modulate = Color(0.8, 0.85, 0.95)
	_clear_children(encounter_buttons_box)
	for opt in GameState.blizzard_options():
		var label: String = tr("blizzard.option." + str(opt["kind"])).replace("{region}", tr("region." + str(opt["region"]))) \
			.replace("{n}", str(int(round(float(opt["safe"]) * 100.0))))
		var id: String = opt["id"]
		_add_encounter_button(label, func(): _on_blizzard_choice(id))
	encounter_overlay.visible = true

func _on_blizzard_choice(id: String) -> void:
	var res := GameState.blizzard_choose(id)
	encounter_bg.modulate = Color(1, 1, 1)
	encounter_overlay.visible = false
	if res.is_empty():
		return
	if res.get("lost", false):
		_log(tr("blizzard.result.lost").replace("{region}", tr("region." + str(res["region"]))))
	elif str(res["kind"]) == "retreat":
		_log(tr("blizzard.result.retreat").replace("{region}", tr("region." + str(res["region"]))))
	else:
		_log(tr("blizzard.result." + str(res["kind"])))
	if str(res["result"]) != "safe":
		_log(tr("blizzard.frostbite." + str(res["result"])))
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)

func _show_blizzard_over(event: Dictionary) -> void:
	var body: String = tr("blizzard.over.later" if event.get("later", false) else "blizzard.over")
	if int(event.get("kills", 0)) > 0:
		body += "\n\n" + tr("blizzard.over.kills")
	_log(tr("blizzard.over.later" if event.get("later", false) else "blizzard.over"))
	_show_card(tr("blizzard.over.title"), body, ArtLibrary.region_background(GameState.current_region, "winter"))

# 第一次走這種冰：先踩上去試，只描述腳下的感覺，由玩家決定要不要走。
func _show_ice_feel(ice: Dictionary) -> void:
	_new_main_entry()
	var text: String = tr("ice.feel." + ("thin" if ice["thin"] else "solid"))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "walk")
	encounter_bg.texture = ArtLibrary.terrain_background("ice", GameTime.current_season()) # 結冰的河面（春季是冰薄版）
	_clear_children(encounter_buttons_box)
	var target: String = str(ice["to"])
	_add_encounter_button(tr("ice.prompt.go").replace("{region}", tr("region." + target)).replace("{n}", str(int(ice["turns"]))), func():
		encounter_overlay.visible = false
		_on_region_button(target, true)
	)
	_add_encounter_button(tr("ice.prompt.back"), func():
		encounter_overlay.visible = false
	)
	encounter_overlay.visible = true

func _show_ice_break(event: Dictionary = {}) -> void:
	var text: String = tr("ice.here.shortcut" if event.get("shortcut", false) else "ice.here")
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "walk")
	encounter_bg.texture = ArtLibrary.terrain_background("ice", GameTime.current_season()) # 結冰的河面（春季是冰薄版）
	_clear_children(encounter_buttons_box)
	for opt in GameState.ice_break_options():
		var id: String = opt["id"]
		_add_encounter_button(tr("ice.option." + id).replace("{n}", str(int(round(float(opt["chance"]) * 100.0)))), func():
			var res := GameState.ice_break_choose(id)
			encounter_overlay.visible = false
			_log(tr("ice.result." + ("success" if res.get("success", false) else "fail")))
			_refresh()
			if GameState.wolf != null and not GameState.wolf.alive:
				_on_wolf_died(GameState.wolf.death_cause)
		)
	encounter_overlay.visible = true

func _show_ravens(event: Dictionary) -> void:
	var region: String = str(event.get("region", GameState.current_region))
	var text: String = tr("ravens.here" if region == GameState.current_region else "ravens.far").replace("{region}", tr("region." + region))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, "raven", "adult", "circling")
	encounter_bg.texture = ArtLibrary.region_background(GameState.current_region, GameTime.current_season())
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("ravens.follow"), func():
		encounter_overlay.visible = false
		var region_before: String = GameState.current_region
		var res := GameState.ravens_follow(event)
		if GameState.wolf == null or not GameState.wolf.alive:
			_refresh()
			if GameState.wolf != null:
				_on_wolf_died(GameState.wolf.death_cause)
			return
		if res.get("found", false):
			var moved: bool = str(event.get("region", "")) != region_before
			_found_intro = tr("ravens.found" + (".moved" if moved else "")).replace("{animal}", tr("animal." + str(res["animal_id"]))) \
				.replace("{region}", tr("region." + GameState.current_region))
			_log(_found_intro)
			_on_action_button("return_to_carcass")
			_found_intro = "" # 殘骸旁沒有搶食者時用不到
		else:
			_log(tr("ravens.nothing"))
		_refresh()
	)
	_add_encounter_button(tr("ravens.ignore"), func():
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# --- 苔原狼（1.6 第 6e 步） ---

func _pair_key() -> String:
	return "pair" if GameState.tundra_pair().size() > 1 else "single"

# 苔原狼的文案：只剩一隻時優先用「.single」的單數版本（1.7-3）。
func _tt(key: String) -> String:
	if GameState.tundra_pair().size() <= 1 and tr(key + ".single") != key + ".single":
		return tr(key + ".single")
	return tr(key)

# 遇上苔原狼：避開、跟隨、威嚇、挑戰。牠們對你的態度依關係值。
func _show_tundra_meet(d: Dictionary, extra: String = "") -> void:
	var leader := GameState.tundra_leader()
	if leader == null:
		GameState.clear_discovery()
		return
	# 敵視：牠們一看到你就撲上來
	if d.get("charge", false):
		_log(tr("tundra.charge." + _pair_key()))
		GameState.note_tundra_seen()
		_begin_combat(GameState.start_tundra_combat("meet", true), "attack")
		return
	var lines: Array[String] = []
	if d.get("came", false): # 回應嚎叫後牠們循聲找來：開頭就是「找來了」，不再接「又出現在你面前」
		lines.append(_tt("tundra.come"))
		GameState.note_tundra_seen()
	else:
		lines.append(tr(GameState.tundra_meet_key(d.get("first", false))))
	# 體型和你現在相比（1.8 第 8 步）
	lines.append(_tt("tundra.size." + GameState.tundra_size_key()))
	# 牠們的孩子（1.8 第 10 步）：秋冬幼狼跟著行動，年輕的成狼一直都在
	var extra_n: int = GameState.tundra_pack_size() - GameState.tundra_pair().size()
	if extra_n > 0:
		lines.append(_tt("tundra.pack.extra").replace("{n}", str(extra_n)))
	lines.append(_tt("tundra.attitude." + GameState.tundra_relation_key()))
	if extra != "":
		lines.append(extra)
	var remember: String = _remember_line("tundra_wolf", "adult")
	if remember != "":
		lines.append(remember)
	if extra == "": # 跟隨後重畫時，開頭句已經寫過（QA-61）
		_log(lines[0])
	encounter_message.text = "\n".join(lines)
	encounter_detail.text = ""
	_set_creature(encounter_sprite, "tundra_wolf", "adult", "pair" if GameState.tundra_pair().size() > 1 else "idle")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("stranger.avoid"), func():
		GameState.tundra_avoid()
		_log(_tt("tundra.avoided"))
		encounter_overlay.visible = false
		_refresh()
	)
	if GameState.tundra_relation_key() == "friendly" and extra == "":
		_add_encounter_button(_tt("tundra.approach"), func():
			var res := GameState.tundra_approach()
			encounter_overlay.visible = false
			if res.get("lead", false):
				_log(_tt("tundra.lead"))
				_show_discovery(GameState.current_discovery)
			else:
				_log(_tt("tundra.approached"))
			_refresh()
		)
	if extra == "":
		_add_encounter_button(tr("tundra.follow").replace("{n}", str(int(round(GameState.tundra_follow_chance() * 100.0)))), func():
			var res := GameState.tundra_follow()
			if res.get("success", false):
				var text: String = _tt("tundra.follow.success").replace("{text}", _tundra_compare_text(str(res["assessment"]["compare"])))
				_log(text)
				_show_tundra_meet(d, text)
			else:
				_log(_tt("tundra.follow.fail"))
				_begin_combat(GameState.start_tundra_combat("meet"))
		)
	_add_encounter_button(tr("combat.option.threaten"), func():
		_begin_combat(GameState.start_tundra_combat("meet"))
		_on_combat_choice("threaten")
	)
	_add_encounter_button(tr("stranger.challenge"), func():
		_begin_combat(GameState.start_tundra_combat("meet"))
	)
	encounter_overlay.visible = true

# 離群的母狼（Phase 3 第 2 步）：避開、走近、跟著；牠在吃東西時多「一起吃」「搶過來」。
func _show_she_wolf(d: Dictionary, extra: String = "") -> void:
	if GameState.she_wolf() == null:
		GameState.clear_discovery()
		return
	var lines: Array[String] = []
	if d.get("came", false):
		lines.append(tr("she_wolf.came"))
	else:
		lines.append(tr("she_wolf.meet.first" if d.get("first", false) else "she_wolf.meet"))
	var eating: bool = bool(d.get("eating", false))
	if eating:
		lines.append(tr("she_wolf.meet.eating"))
	lines.append(tr("she_wolf.attitude." + GameState.she_relation_key()))
	if extra != "":
		lines.append(extra)
	else:
		_log(lines[0])
	encounter_message.text = "\n".join(lines)
	encounter_detail.text = ""
	_set_creature(encounter_sprite, "tundra_wolf", "adult", "idle")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("stranger.avoid"), func():
		GameState.she_avoid()
		_log(tr("she_wolf.avoided"))
		encounter_overlay.visible = false
		_refresh()
	)
	if eating:
		_add_encounter_button(tr("she_wolf.eat_together"), func():
			var res := GameState.she_eat_together()
			_log(tr("she_wolf.eat." + ("allowed" if res.get("allowed", false) else "refused")))
			encounter_overlay.visible = false
			_refresh()
		)
		_add_encounter_button(tr("she_wolf.steal"), func():
			var res := GameState.she_steal()
			_log(tr("she_wolf.stole" + (".left" if res.get("left", false) else "")))
			encounter_overlay.visible = false
			_refresh()
		)
	_add_encounter_button(tr("she_wolf.approach"), func():
		var ok := GameState.she_approach()
		_log(tr("she_wolf.approached" if ok else "she_wolf.approach.refused"))
		encounter_overlay.visible = false
		_refresh()
	)
	if extra == "":
		_add_encounter_button(tr("she_wolf.follow").replace("{n}", str(int(round(GameState.she_follow_chance() * 100.0)))), func():
			var res := GameState.she_follow()
			if res.get("success", false) and res.has("assessment"):
				var text: String = tr("she_wolf.follow.success").replace("{text}", tr("stranger.compare." + str(res["assessment"]["compare"])))
				_log(text)
				_show_she_wolf(d, text)
			else:
				_log(tr("she_wolf.follow.fail"))
				encounter_overlay.visible = false
				_refresh()
		)
	encounter_overlay.visible = true

# 狼群面板（Phase 3 第 3 步，SPEC「同行與指派」）：每個成員的狀態、指派（一直有效直到你改）、群獵的角色。目前只有伴侶。
func _show_pack_panel() -> void:
	var members: Array = GameState.pack_members()
	if members.is_empty():
		return
	var n: NpcWolf = GameState.she_wolf() if GameState.has_mate() else null
	if n == null:
		# 伴侶不在了、只剩幼狼（第 6 步再做逐隻的面板）
		encounter_message.text = _pups_line()
		encounter_detail.text = ""
		_clear_children(encounter_buttons_box)
		_add_encounter_button(tr("ui.close"), func():
			encounter_overlay.visible = false
		)
		encounter_overlay.visible = true
		return
	var lines: Array[String] = []
	lines.append(tr("ui.pack.mate").replace("{age}", str(snapped(n.age_years, 0.5))))
	lines.append(tr("stranger.compare." + GameState.power_compare(n.power())))
	lines.append(tr("ui.pack.health").replace("{hp}", str(int(n.health))).replace("{max}", str(int(n.health_max))))
	if n.task == "follow" and not GameState.followers().has(n):
		lines.append(tr("ui.pack.too_hurt"))
	if not GameState.pups().is_empty():
		lines.append(_pups_line())
	var role_now: String = GameState.hunt_role_of(n)
	lines.append(tr("ui.pack.now").replace("{task}", tr("ui.pack.task." + n.task)).replace("{role}", tr("ui.pack.role." + n.hunt_role) + ("" if n.hunt_role != "auto" else tr("ui.pack.role.auto_is").replace("{role}", tr("ui.pack.role." + role_now)))))
	encounter_message.text = "\n".join(lines)
	encounter_detail.text = tr("ui.pack.detail")
	_set_creature(encounter_sprite, "tundra_wolf", "adult", "idle")
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	for task in GameState.PACK_TASKS:
		var label: String = tr("ui.pack.task." + task) + ("　✓" if n.task == task else "")
		_add_encounter_button(label, func():
			GameState.set_task(n.id, task)
			_show_pack_panel()
			_refresh()
		)
	for role in GameState.HUNT_ROLES:
		var rl: String = tr("ui.pack.role_button").replace("{role}", tr("ui.pack.role." + role)) + ("　✓" if n.hunt_role == role else "")
		_add_encounter_button(rl, func():
			GameState.set_hunt_role(n.id, role)
			_show_pack_panel()
		)
	_add_encounter_button(tr("ui.close"), func():
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# 幼狼的狀況（Phase 3 第 5 步）：幾隻、在哪、存糧還夠幾天
func _pups_line() -> String:
	var n: int = GameState.pups().size()
	if not GameState.pups_need_food():
		return tr("ui.pack.pups.follow").replace("{n}", str(n))
	return tr("ui.pack.pups").replace("{n}", str(n)).replace("{region}", tr("region." + GameState.pup_spot())).replace("{days}", str(snapped(GameState.den_food_days(), 0.5)))

# 巢穴（集合點）有東西靠近、你在那裡（Phase 3 第 5 步）：趕走或護住幼狼
func _show_den_threat(animal: String) -> void:
	var known: bool = GameState.is_identified(animal)
	var text: String = tr("den.threat." + animal + ("" if known else ".unknown"))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, animal, "adult", "idle")
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("den.threat.drive").replace("{p}", str(roundi(GameState.den_threat_drive_chance(animal) * 100.0))), func():
		var r: Dictionary = GameState.den_threat_choice(animal, true)
		_log(tr("den.threat.drive." + ("ok" if r["ok"] else "fail")) + (tr("den.threat.lost") if int(r["lost"]) > 0 else ""))
		encounter_overlay.visible = false
		if GameState.wolf != null and not GameState.wolf.alive:
			_on_wolf_died(GameState.wolf.death_cause)
			return
		_refresh()
	)
	_add_encounter_button(tr("den.threat.shelter"), func():
		var r: Dictionary = GameState.den_threat_choice(animal, false)
		_log(tr("den.threat.sheltered") + (tr("den.threat.lost") if int(r["lost"]) > 0 else ""))
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# 兩隻苔原狼圍攻狼獾：幫苔原狼、在旁邊看、離開。
func _show_tundra_mob(d: Dictionary) -> void:
	# 文案依這一次之前認不認得苔原狼、狼獾（兩者都認得 known、都不認得 unknown）
	var wolves_known: bool = d.get("tundra_known", false)
	var wolverine_known: bool = d.get("wolverine_known", false)
	var mob_key: String = "known" if wolves_known and wolverine_known else ("wolves_known" if wolves_known else ("wolverine_known" if wolverine_known else "unknown"))
	var text: String = tr("tundra.mob." + mob_key)
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	var mob_tex: Texture2D = ArtLibrary.event_image("wolverine_mobbed")
	if mob_tex != null:
		encounter_sprite.show_static(mob_tex)
	else:
		_set_creature(encounter_sprite, "wolverine", "adult", "attack")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("tundra.mob.help"), func():
		_begin_combat(GameState.start_mob_combat(), "attack")
	)
	_add_encounter_button(tr("tundra.mob.side_wolverine"), func():
		var res := GameState.mob_side_wolverine()
		encounter_overlay.visible = false
		_log(_tt("tundra.mob.side." + str(res["result"])).replace("{n}", str(int(res["damage"]))))
		_after_mob_choice()
	)
	_add_encounter_button(tr("tundra.mob.grab"), func():
		var res := GameState.mob_grab()
		encounter_overlay.visible = false
		var line: String = _tt("tundra.mob.grab." + str(res["result"]))
		if res["turned"]:
			line += _tt("tundra.mob.grab.turned").replace("{n}", str(int(res["damage"])))
		_log(line)
		_after_mob_choice()
	)
	_add_encounter_button(tr("tundra.mob.watch"), func():
		var res := GameState.watch_tundra_mob()
		encounter_overlay.visible = false
		_log(tr("tundra.mob.watch." + str(res["result"])))
		_refresh()
	)
	_add_encounter_button(tr("ui.leave"), func():
		GameState.leave_tundra_mob()
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# 撞見苔原狼在追馴鹿或駝鹿（1.8 第 9 步）：加入、觀望、離開。
func _show_tundra_hunt(d: Dictionary) -> void:
	var text: String = _tt("tundra.hunt.seen").replace("{animal}", tr("animal." + str(d["animal_id"])))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = _tt("tundra.hunt.hint")
	var tex: Texture2D = ArtLibrary.event_image("tundra_joint_hunt")
	if tex != null:
		encounter_sprite.show_static(tex)
	else:
		_set_creature(encounter_sprite, "tundra_wolf", "adult", "move")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_hunt_button(tr("tundra.hunt.join"), func():
		encounter_overlay.visible = false
		current_hunt = GameState.join_tundra_hunt()
		_enter_hunt()
	)
	_add_encounter_button(tr("tundra.hunt.watch"), func():
		var res := GameState.watch_tundra_hunt()
		encounter_overlay.visible = false
		_log(_tt("tundra.hunt.watch." + str(res["result"])) + (_tt("tundra.hunt.leftover") if res["leftover"] else ""))
		_after_mob_choice()
	)
	_add_encounter_button(tr("ui.leave"), func():
		GameState.clear_discovery()
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# 苔原狼的巢穴（1.8 第 10 步）：巢穴的線索（靠近或離開）、灰熊朝巢穴走去（一起威嚇、旁觀、離開）。
func _show_tundra_den(d: Dictionary) -> void:
	var bear: bool = d.get("kind", "") == "tundra_den_bear"
	var text: String = tr("tundra.den.bear" + (".mother" if d.get("mother", false) else "")) if bear else _tt("tundra.den.clue")
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	if bear:
		_set_creature(encounter_sprite, "grizzly_bear", "adult", "move")
		if GameState.tundra_relation_key() in ["familiar", "friendly"]:
			_add_encounter_button(tr("tundra.den.threaten") + "　" + _chance_text(GameState.tundra_den_threaten_chance(bool(d.get("mother", false))), "grizzly_bear"), func():
				var res := GameState.den_bear_threaten()
				if res["result"] == "drove_off":
					encounter_overlay.visible = false
					_log(_tt("tundra.den.result.drove_off"))
					_refresh()
				else:
					_log(tr("tundra.den.result.fight"))
					_begin_combat(GameState.start_den_combat(), "attack")
			)
		_add_encounter_button(tr("tundra.den.watch"), func():
			var res := GameState.den_bear_watch()
			encounter_overlay.visible = false
			_log(_tt("tundra.den.watch." + str(res["result"])))
			_refresh()
		)
	else:
		_set_creature(encounter_sprite, "tundra_wolf", "adult", "idle")
		_add_encounter_button(tr("tundra.den.approach"), func():
			var res := GameState.approach_tundra_den()
			_log(_tt("tundra.den.approach." + str(res["result"])))
			if res["result"] == "charge":
				_begin_combat(GameState.start_tundra_combat("meet", true), "attack")
				return
			encounter_overlay.visible = false
			_refresh()
		)
	_add_encounter_button(tr("ui.leave"), func():
		GameState.clear_discovery()
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# 美洲獅（Phase 2 第 3 步）：伏擊（先挨一下，接著戰鬥或撤退）、發現牠藏起來的獵物（偷吃或離開）。
func _show_cougar(d: Dictionary) -> void:
	var known: String = "known" if d.get("known", false) else "unknown"
	var ambush: bool = d.get("kind", "") == "cougar_ambush"
	var text: String = tr("cougar.%s.%s" % ["ambush" if ambush else "cache", known]).replace("{animal}", _prey_name(str(d.get("animal_id", "mule_deer")), "adult")) \
		.replace("{n}", str(int(d.get("damage", 0))))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)
		return
	if ambush:
		_set_creature(encounter_sprite, "cougar", "adult", "attack")
		_add_encounter_button(tr("ui.continue"), func():
			_begin_combat(GameState.start_cougar_ambush_combat(), "attack"))
	else:
		var carcass_tex: Texture2D = ArtLibrary.carcass(str(d.get("animal_id", "mule_deer")))
		if carcass_tex != null:
			encounter_sprite.show_static(carcass_tex)
		_add_encounter_button(tr("cougar.cache.eat"), func():
			GameState.eat_cougar_cache()
			_show_feeding())
		_add_encounter_button(tr("ui.leave"), func():
			GameState.clear_discovery()
			encounter_overlay.visible = false
			_refresh())
	encounter_overlay.visible = true

# 猞猁（Phase 2 第 6 步）：看到牠；牠剛抓到雪兔時可以趕走牠搶下來，或悄悄靠近叼走（Phase 2g 第 3 步）。
func _show_lynx(d: Dictionary) -> void:
	var text: String = tr("lynx.%s.%s" % ["kill" if d.get("has_kill", false) else "seen", "known" if d.get("known", false) else "unknown"])
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, "lynx", "adult", "idle")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	if d.get("has_kill", false):
		# 悄悄叼走（Phase 2g 第 3 步）：不打架，失敗了牠帶著雪兔離開
		_add_encounter_button(tr("lynx.sneak") + "　" + tr("chance_label.success") + " " + _chance_text(GameState.lynx_sneak_chance(), "lynx"), func():
			var res: Dictionary = GameState.lynx_sneak()
			var out: String = tr("lynx.sneak.got").replace("{n}", str(int(res["gain"]))) if res["success"] else tr("lynx.sneak.fail." + str(res["escape"]))
			if int(res["damage"]) > 0:
				out += tr("lynx.sneak.swipe").replace("{n}", str(int(res["damage"])))
			_log(out)
			encounter_message.text = out
			_clear_children(encounter_buttons_box)
			_add_encounter_button(tr("ui.continue"), func():
				encounter_overlay.visible = false
				_refresh())
			_refresh())
		_add_encounter_button(tr("lynx.drive_off"), func():
			_begin_combat(GameState.start_lynx_combat(), "move"))
	_add_encounter_button(tr("ui.leave"), func():
		GameState.leave_lynx()
		encounter_overlay.visible = false
		_refresh())
	encounter_overlay.visible = true

# 鮭魚洄流的線索（Phase 2h 第 1 步）：河岸的捕魚做好前（第 2 步）只有「離開」
func _show_salmon(d: Dictionary) -> void:
	var text := _discovery_text(d)
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	# 看到熊的線索畫熊；其他畫鮭魚（高峰期在跳，其他在水裡擺尾）
	if str(d.get("clue", "")) in ["bear", "bears"]:
		_set_creature(encounter_sprite, "grizzly_bear", "adult", "idle")
	else:
		_set_creature(encounter_sprite, "salmon", "adult", "move" if str(d.get("stage", "")) == "peak" else "idle")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	if GameState.salmon_fishing_enabled():
		_add_encounter_button(tr("salmon.go_fish"), func():
			encounter_overlay.visible = false
			_open_river())
	_add_encounter_button(tr("ui.leave"), func():
		GameState.clear_discovery()
		encounter_overlay.visible = false
		_refresh())
	encounter_overlay.visible = true

# 河岸模式（Phase 2h 第 2 步）：結束時結算時間、體力、吃下的魚
const RIVER_SCENE := "res://scenes/RiverFishing.tscn"

func _open_river() -> void:
	var view: Control = load(RIVER_SCENE).instantiate()
	add_child(view)
	view.start(GameState.start_salmon_fishing(), func(rf):
		var res: Dictionary = GameState.finish_salmon_fishing(rf)
		_log(tr("river.ui.result").replace("{turns}", load("res://scripts/ui/RiverView.gd").periods_text(int(res["turns"]))).replace("{n}", str(int(res["caught"]))).replace("{h}", str(roundi(float(res["eaten"])))))
		_refresh()
		# 硬撐不走：那頭熊衝過來（灰熊遭遇）
		if str(res["result"]) == "stand":
			_on_encounter_triggered(GameState.salmon_stand_encounter()))

# 田鼠與地松鼠的小撲（Phase 2g 第 2 步）：撲過去或不理牠；結果寫明只是一小口。
func _small_pounce_text(kind: String, d: Dictionary) -> String:
	var key: String = "small_pounce.%s.%s" % [kind, str(d.get("animal", "vole"))]
	if bool(d.get("snow", false)) and TranslationServer.translate(key + ".snow") != key + ".snow":
		key += ".snow"
	return tr(key).replace("{location}", tr("explore.location." + str(d.get("location", ""))))

func _show_small_pounce(d: Dictionary) -> void:
	var text := _small_pounce_text("see", d)
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "idle")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("small_pounce.go") + "　" + tr("chance_label.success") + " " + _chance_text(GameState.small_pounce_chance(d), str(d.get("animal", ""))), func():
		var res: Dictionary = GameState.resolve_small_pounce(true)
		var out: String = _small_pounce_text("got" if res["caught"] else "miss", d).replace("{n}", str(int(res["gain"])))
		_log(out)
		encounter_message.text = out
		_clear_children(encounter_buttons_box)
		_add_encounter_button(tr("ui.continue"), func():
			encounter_overlay.visible = false
			_refresh())
		_refresh())
	_add_encounter_button(tr("small_pounce.ignore"), func():
		GameState.resolve_small_pounce(false)
		encounter_overlay.visible = false
		_refresh())
	encounter_overlay.visible = true

# 遷徙的足跡（Phase 2 第 6 步）：可以跟著走到牠們要去的區域。
func _show_migration(d: Dictionary) -> void:
	var to: String = str(d.get("to", ""))
	var text: String = tr("migration.tracks." + str(d.get("season", "autumn"))).replace("{region}", tr("region." + to))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "walk")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("migration.follow").replace("{region}", tr("region." + to)), func():
		var target: String = GameState.follow_migration()
		encounter_overlay.visible = false
		_on_region_button(target))
	_add_encounter_button(tr("ui.leave"), func():
		GameState.clear_discovery()
		encounter_overlay.visible = false
		_refresh())
	encounter_overlay.visible = true

# 最後一章（1.9b 第 2 步）：讓玩家選擇結束的方式
func _show_lie_down() -> void:
	encounter_message.text = tr("lie_down.prompt")
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "sleep")
	_set_terrain_bg(encounter_bg, "")
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("lie_down.confirm"), func():
		encounter_overlay.visible = false
		_log(tr("lie_down.text"))
		GameState.action_lie_down()
		_on_wolf_died(GameState.wolf.death_cause)
	)
	_add_encounter_button(tr("lie_down.cancel"), func(): encounter_overlay.visible = false)
	encounter_overlay.visible = true

# 年輕的挑戰者（1.9b 第 2 步）：讓牠、或對峙。carcass：牠來搶殘骸。
func _show_challenger(d: Dictionary, carcass: bool) -> void:
	var key: String = "challenger." + ("first" if d.get("first", false) else "again") + ("." + ("carcass" if carcass else ("territory" if d.get("territory", false) else "meet")))
	# 黑狼的兒子（Phase 3a 第 5 步）：第一次見面寫出牠是誰（毛色偏黑，取代原本的偏紅）
	if d.get("first", false) and GameState.challenger_is_son():
		key += ".son"
	var text: String = tr(key)
	# 「牠比上次更壯」只在牠真的變強時才說（只有你上次打贏時，文案稽核 2026-10-16）
	if not d.get("first", false) and GameState.challenger_grew():
		text += tr("challenger.again.grew")
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, "challenger", "adult", "idle")
	GameState.identify("challenger", false) # 親眼看到了（試玩 BUG-02、03：受傷來源與知識原本寫成未知的名字）
	_set_terrain_bg(encounter_bg, str(d.get("location", GameState.current_feeding.get("terrain", ""))))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("challenger.confront"), func():
		_begin_combat(GameState.start_challenger_combat("carcass" if carcass else ("territory" if d.get("territory", false) else "meet")), "move")
	)
	_add_encounter_button(tr("challenger.yield." + ("carcass" if carcass else "meet")), func():
		GameState.challenger_yield()
		encounter_overlay.visible = false
		_log(tr("challenger.yielded"))
		_refresh()
	)
	encounter_overlay.visible = true

# 黑狼的標記蓋在你的地盤上（1.9b 第 1 步）：重新標記、去找牠、讓出。
func _show_overmarked(d: Dictionary) -> void:
	var text: String = tr("territory.overmarked." + ("known" if GameState.is_identified("stranger_wolf") else "unknown"))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "idle")
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("territory.remark"), func():
		GameState.clear_discovery()
		encounter_overlay.visible = false
		var r: String = GameState.action_mark()
		_log(tr("log.mark." + r).replace("{region}", tr("region." + GameState.current_region)))
		_refresh()
	)
	_add_encounter_button(tr("territory.seek"), func():
		var res := GameState.seek_stranger_from_mark()
		if res.has("combat"):
			_begin_combat(res["combat"], "move")
		else:
			_show_discovery(res["discovery"])
	)
	_add_encounter_button(tr("territory.yield"), func():
		GameState.yield_territory()
		encounter_overlay.visible = false
		_log(tr("territory.yielded"))
		_refresh()
	)
	encounter_overlay.visible = true

# 幫狼獾、自己搶之後：分到肉就接著吃，死了就結束
func _after_mob_choice() -> void:
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)
		return
	if GameState.is_feeding():
		_show_feeding()

func _show_tundra_howl(event: Dictionary) -> void:
	var text: String = _tt("tundra.howl." + GameState.tundra_relation_key()).replace("{region}", tr("region." + str(event.get("region", ""))))
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_wolf_pose(encounter_sprite, "howl")
	encounter_bg.texture = ArtLibrary.region_background(GameState.current_region, GameTime.current_season())
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("tundra.howl.reply"), func():
		GameState.tundra_howl_reply(true)
		_log(tr("tundra.howl.replied"))
		encounter_overlay.visible = false
		_refresh()
	)
	_add_encounter_button(tr("tundra.howl.silent"), func():
		GameState.tundra_howl_reply(false)
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# --- 陌生灰狼（SPEC 1.6「陌生灰狼」） ---

# 直接遇上牠：避開、跟蹤、威嚇、挑戰。第一次相遇時說出這一帶關於牠的傳說。
func _show_stranger_meet(e: Dictionary, extra: String = "") -> void:
	var npc := GameState.stranger()
	var meetings: Array = GameState.life_log.get("stranger_meetings", [])
	var lines: Array[String] = []
	if meetings.is_empty() and extra == "":
		lines.append(tr("stranger.legend").replace("{region}", tr("region." + npc.territory)))
	else:
		lines.append(tr("stranger.meet_again"))
	lines.append(tr("stranger.age." + npc.life_stage_key()))
	var a: Dictionary = GameState.life_log.get("stranger_assessment", {})
	if extra != "":
		lines.append(extra)
	elif not a.is_empty():
		lines.append(tr("stranger.last_assessment").replace("{age}", "%.1f" % float(a.get("wolf_age", 0.0))) \
			.replace("{text}", tr("stranger.compare." + str(a["compare"]))))
	var remember: String = _remember_line("stranger_wolf", "adult")
	if remember != "":
		lines.append(remember)
	_log(lines[0])
	encounter_message.text = "\n".join(lines)
	encounter_detail.text = ""
	_set_creature(encounter_sprite, "stranger_wolf", "adult", "idle")
	_set_terrain_bg(encounter_bg, str(e.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("stranger.avoid"), func():
		GameState.stranger_avoid()
		_log(tr("stranger.avoided"))
		encounter_overlay.visible = false
		_refresh()
	)
	if extra == "":
		_add_encounter_button(tr("stranger.follow").replace("{n}", str(int(round(GameState.stranger_follow_chance() * 100.0)))), func():
			var res := GameState.stranger_follow()
			if res.get("success", false):
				var text: String = tr("stranger.follow.success").replace("{text}", tr("stranger.compare." + str(res["assessment"]["compare"])))
				_log(text)
				_show_stranger_meet(e, text)
			else:
				_log(tr("stranger.follow.fail"))
				_begin_combat(GameState.start_stranger_combat("meet"))
		)
	_add_encounter_button(tr("combat.option.threaten"), func():
		_begin_combat(GameState.start_stranger_combat("meet"))
		_on_combat_choice("threaten")
	)
	_add_encounter_button(tr("stranger.challenge"), func():
		_begin_combat(GameState.start_stranger_combat("meet"))
	)
	encounter_overlay.visible = true

# 在牠的範圍待太久：牠現身，退讓（離開這一帶，不受傷）或對峙（進入戰鬥，牠護地盤更拚）。
func _show_stranger_confront() -> void:
	var text: String = tr("stranger.confront")
	_log(text)
	encounter_message.text = text
	encounter_detail.text = ""
	_set_creature(encounter_sprite, "stranger_wolf", "adult", "threaten")
	_set_terrain_bg(encounter_bg, GameState._random_terrain(GameState.current_region))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("combat.option.yield"), func():
		var to: String = GameState.stranger_yield_territory()
		_log(tr("stranger.yielded").replace("{region}", tr("region." + to)))
		encounter_overlay.visible = false
		_refresh()
	)
	_add_encounter_button(tr("stranger.stand"), func():
		_begin_combat(GameState.start_stranger_combat("territory"))
	)
	encounter_overlay.visible = true

# 黑狼一家吃剩的殘骸（Phase 3a 第 4 步）：一段一段吃，每吃一段都可能被牠們發現；也可以離開。
func _show_pack_remains(d: Dictionary, first: bool) -> void:
	var location: String = tr("explore.location." + str(d.get("location", "")))
	var text: String = tr("pack.remains." + ("found" if first else "left")).replace("{location}", location).replace("{n}", str(int(d.get("segments", 1))))
	if first:
		_log(text)
	encounter_message.text = text
	encounter_detail.text = tr("pack.remains.risk." + str(d.get("zone", "core")))
	var remains_tex: Texture2D = ArtLibrary.carcass("white_tailed_deer")
	if remains_tex != null:
		encounter_sprite.show_static(remains_tex)
	_set_terrain_bg(encounter_bg, str(d.get("location", "")))
	_clear_children(encounter_buttons_box)
	_add_encounter_button(tr("pack.remains.eat").replace("{p}", str(roundi(GameState.pack_remains_risk() * 100.0))), func():
		var res: Dictionary = GameState.eat_pack_remains()
		_log(tr("log.pack_remains.ate").replace("{n}", str(int(res["gain"]))))
		if res["caught"]:
			_log(tr("pack.remains.caught"))
			encounter_overlay.visible = false
			_refresh()
			return
		if int(res["left"]) <= 0:
			_log(tr("pack.remains.done"))
			encounter_overlay.visible = false
			_refresh()
			return
		_refresh()
		_show_pack_remains(GameState.current_discovery, false)
	)
	_add_encounter_button(tr("ui.leave"), func():
		GameState.clear_discovery()
		encounter_overlay.visible = false
		_refresh()
	)
	encounter_overlay.visible = true

# 撞上黑狼一家（Phase 3a 第 3 步）：退開、對峙、逃；落單的年輕狼可以打或避開。
func _show_pack_meet(event: Dictionary) -> void:
	GameState.meet_pack_id = str(event.get("pack", "black"))
	var neighbor: bool = GameState.meet_pack_id != "black"
	var location: String = tr("explore.location." + str(event.get("location", "")))
	_clear_children(encounter_buttons_box)
	_set_terrain_bg(encounter_bg, str(event.get("location", GameState._random_terrain(GameState.current_region))))
	encounter_detail.text = ""
	if str(event.get("lone", "")) == "young":
		var young_text: String = tr("pack.meet.young" + (".neighbor" if neighbor else "")).replace("{location}", location)
		_log(young_text)
		encounter_message.text = young_text
		_set_creature(encounter_sprite, "challenger", "adult", "idle")
		_add_encounter_button(tr("stranger.stand"), func():
			_begin_combat(GameState.start_pack_young_combat())
		)
		_add_encounter_button(tr("ui.leave"), func():
			GameState.pack_young_avoid()
			_log(tr("pack.young.avoided"))
			encounter_overlay.visible = false
			_refresh()
		)
		encounter_overlay.visible = true
		return
	var who: String = tr("pack.who." + ("neighbor" if neighbor else ("heir" if GameState.black_pack.generation > 1 else str(event.get("stage", "pack")))))
	# 換代後是新一代：不寫「那隻黑狼記得…」，態度另有一句（效果減半）；一般鄰群（Phase 3 第 4 步）有自己的寫法
	var att: String = str(event.get("attitude", "neutral"))
	var meet_key: String = "pack.meet." + att + (".neighbor" if neighbor and att != "neutral" else (".heir" if GameState.black_pack.generation > 1 and att != "neutral" else ""))
	var text: String = tr(meet_key).replace("{who}", who).replace("{location}", location)
	_log(text)
	encounter_message.text = text
	var team: int = GameState.team_size()
	encounter_detail.text = (tr("pack.meet.count") if team <= 1 else tr("pack.meet.count.team").replace("{m}", str(team))).replace("{n}", str(int(event.get("size", 2))))
	_set_creature(encounter_sprite, "stranger_wolf", "adult", "threaten")
	var after := func(msg: String) -> void:
		_log(msg)
		encounter_overlay.visible = false
		_refresh()
	if not bool(event.get("charge", false)):
		_add_encounter_button(tr("pack.option.retreat"), func():
			var to: String = GameState.pack_retreat()
			after.call(tr("pack.retreat").replace("{region}", tr("region." + to)))
		)
	_add_encounter_button(tr("pack.option.standoff").replace("{p}", str(roundi(GameState.pack_standoff_chance() * 100.0))), func():
		var r: Dictionary = GameState.pack_standoff()
		after.call(tr("pack.standoff." + ("won" if r["won"] else "lost") + (".neighbor" if neighbor and r["won"] else "")).replace("{who}", who).replace("{region}", tr("region." + str(r["region"]))))
	)
	_add_encounter_button(tr("pack.option.flee").replace("{p}", str(roundi((1.0 - GameState.pack_flee_caught_chance()) * 100.0))), func():
		var r: Dictionary = GameState.pack_flee()
		after.call(tr("pack.flee." + ("caught" if r["caught"] else "safe")).replace("{region}", tr("region." + str(r["region"]))))
	)
	encounter_overlay.visible = true

# --- 戰鬥模式（SPEC 1.6「戰鬥模式」）：對峙 → 交鋒 → 結束 ---

func _begin_combat(c: Combat, opp_action: String = "idle") -> void:
	encounter_overlay.visible = false
	current_combat = c
	c.set_meta("tundra_relation_before", GameState.tundra_relation_key()) # 戰鬥後只有關係改變時才寫（1.7-3）
	combat_notes = []
	combat_wolf_pose = "hurt" if opp_action == "attack" else "threaten"
	combat_opp_action = opp_action
	_render_combat()

func _render_combat() -> void:
	var c := current_combat
	if c == null:
		hunt_overlay.visible = false
		return
	hunt_overlay.visible = true
	_clear_children(hunt_buttons_box)
	var name: String = _combat_name(c)
	hunt_sprite.flip_h = true # 戰鬥中對手面向你（素材都面向右）
	_set_hunt_opponent(c.animal_id, c.life_stage)
	_set_creature(hunt_sprite, c.animal_id, c.life_stage, combat_opp_action, false)
	_set_wolf_pose(hunt_wolf_sprite, combat_wolf_pose, false)
	_set_terrain_bg(hunt_bg, c.terrain)
	var lines: Array[String] = []
	if c.phase == Combat.Phase.STANDOFF:
		lines.append(tr("combat.standoff.title").replace("{animal}", name))
		var stake_key: String = "combat.stake." + ("mother" if c.mother else c.context + "." + c.animal_id)
		# 苔原狼只剩一隻時用單數的句子
		if c.animal_id == "tundra_wolf" and GameState.tundra_pair().size() < 2:
			stake_key += ".single"
		lines.append(tr(stake_key).replace("{animal}", name))
		var remember: String = _remember_line(c.animal_id, c.life_stage)
		if remember != "":
			lines.append(remember)
	else:
		lines.append(tr("combat.exchange.title").replace("{animal}", name) + "　" + tr(c.opp_condition_key()))
		if c.mother:
			lines.append(tr("combat.stake.mother"))
	# 每回合的結果寫在下方的遭遇紀錄（編號），描述只留雙方的狀態
	if FightRules.in_danger(GameState.wolf):
		lines.append(tr("combat.danger"))
	if GameState.wolf.in_burst:
		lines.append(tr("hunt.breath").replace("{n}", str(int(round(GameState.wolf.breath)))).replace("{max}", str(int(round(GameState.wolf.breath_max)))))
	if combat_intro != "":
		lines.insert(0, combat_intro)
	hunt_message.text = "\n".join(lines)
	for opt in c.options():
		var id: String = opt["id"]
		_add_hunt_choice(tr(opt["label_key"]), opt, func(): _on_combat_choice(id))
	combat_anim_btn.text = tr("combat.anim." + CombatAnimator.mode())
	combat_anim_btn.visible = true
	_fit_hunt_layout(hunt_buttons_box.get_children().filter(func(n): return not n.is_queued_for_deletion()).size())

# 試玩指標：有成功率的選擇裡，是不是選了最高的那個。
func _metric_choice(opt: Dictionary, all: Array) -> void:
	if not opt.has("chance"):
		return
	var best: float = 0.0
	for o in all:
		if o.has("chance"):
			best = max(best, float(o["chance"]))
	GameState.metric_choice(float(opt["chance"]), best)

func _on_combat_choice(id: String) -> void:
	var c := current_combat
	# 動畫播放中再按：略過剩下的演出
	if combat_anim.playing:
		combat_anim.skip()
		return
	combat_intro = ""
	for o in c.options():
		if str(o.get("id", "")) == id:
			_metric_choice(o, c.options())
	var res := c.choose(id)
	if id in ["bite", "lunge", "attack", "harass"]:
		Audio.play_bite()
	var name: String = _combat_name(c)
	combat_notes = []
	for n in res.get("notes", []):
		var text: String = tr(str(n)).replace("{animal}", name)
		combat_notes.append(text)
		_log(text)
	combat_wolf_pose = str(res.get("wolf_pose", "threaten"))
	combat_opp_action = str(res.get("opp_action", "idle"))
	# 照事件的順序播放這一回合（1.9 第 2 步）；播放中選項灰掉，按「動畫」那一行可略過
	for b in hunt_buttons_box.get_children():
		for n in ([b] + b.get_children()):
			if n is Button and not (n as Button).flat:
				(n as Button).disabled = true
	await combat_anim.play(res.get("events", []))
	_refresh()
	if c.phase == Combat.Phase.DONE:
		_finish_combat_ui()
	else:
		_render_combat()
	# 動畫播完才結算：_session_choice 在動畫開始時就檢查過遭遇結束，這裡要再檢查一次，
	# 不然戰鬥結束後沒有結果畫面、結果也不會寫回主畫面（試玩回報 10）
	if not session_check_pending:
		session_check_pending = true
		_check_session_end.call_deferred()

func _finish_combat_ui() -> void:
	var c := current_combat
	current_combat = null
	combat_intro = ""
	var r := GameState.finish_combat(c)
	hunt_overlay.visible = false
	var name: String = _combat_name(c)
	var result_text: String = ""
	if c.outcome != "died":
		# 依情境有專屬的結果文字（例如圍攻狼獾：combat.result.mob.drove_off）
		var result_key: String = "combat.result.%s.%s" % [c.context, c.outcome]
		if tr(result_key) == result_key:
			result_key = "combat.result." + c.outcome
		result_text = tr(result_key).replace("{animal}", name)
		_log_result(result_text)
		if str(r.get("grow", "")) != "":
			_log_result(tr("combat.grow." + str(r["grow"])))
		# 咬死時後面有「那隻黑狼」卡片，不另外寫地盤（QA-67）
		if c.npc != null and c.npc.id == "stranger_wolf" and c.outcome == "drove_off":
			_log_result(tr("stranger.won_territory").replace("{region}", tr("region." + str(GameState.life_log.get("own_territory", "")))))
		if c.npc != null and GameState.TUNDRA_WOLF_IDS.has(c.npc.id) and not GameState.tundra_pair().is_empty() \
				and GameState.tundra_relation_key() != str(c.get_meta("tundra_relation_before", GameState.tundra_relation_key())):
			_log(_tt("tundra.relation_change." + GameState.tundra_relation_key()))
		if c.context == "den" and bool(c.get_meta("pup_lost", false)):
			_log_result(tr("tundra.den.pup_lost"))
		if r.get("lynx_hare", false):
			_log_result(tr("lynx.got_hare"))
	_refresh()
	if GameState.wolf != null and not GameState.wolf.alive:
		_on_wolf_died(GameState.wolf.death_cause)
		return
	if c.context == "mob" and GameState.is_feeding():
		_log(tr("tundra.mob.share"))
		result_text += tr("tundra.mob.share")
	if c.context in ["carcass", "mob"] and GameState.is_feeding():
		_show_feeding(result_text)

# --- 轉變與回饋提示（SPEC 1.6「轉變與回饋提示」）---

func _build_card_overlay() -> void:
	card_overlay = Panel.new()
	card_overlay.visible = false
	card_overlay.theme_type_variation = &"OverlayPanel"
	card_overlay.anchor_right = 1.0
	card_overlay.anchor_bottom = 1.0
	add_child(card_overlay)
	card_bg = _make_background_rect(true)
	card_overlay.add_child(card_bg)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	card_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var card_sprite_center := CenterContainer.new()
	box.add_child(card_sprite_center)
	card_wolf = AnimatedIcon.new()
	card_wolf.custom_minimum_size = Vector2(96, 64)
	card_wolf.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	card_wolf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card_wolf.visible = false
	card_sprite_center.add_child(card_wolf)
	card_title = Label.new()
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_title.theme_type_variation = &"CardTitle"
	box.add_child(card_title)
	card_body = RichTextLabel.new()
	card_body.bbcode_enabled = true
	card_body.fit_content = true
	card_body.scroll_active = false
	card_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(card_body)
	card_buttons_box = HBoxContainer.new()
	card_buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(card_buttons_box)

# bg 為 null 時沿用目前區域的背景。關閉後繼續處理佇列裡的下一個事件。
func _show_card(title: String, body: String, bg: Texture2D = null) -> void:
	card_wolf.visible = false
	card_title.text = title
	card_body.fit_content = true
	card_body.scroll_active = false
	card_body.custom_minimum_size.y = 0
	card_body.text = body
	_fit_card.call_deferred()
	card_bg.texture = bg if bg != null else ArtLibrary.region_background(GameState.current_region, GameTime.current_season())
	card_bg.modulate = Color(1, 1, 1) if bg != null else ArtLibrary.period_tint(GameTime.current_period())
	_clear_children(card_buttons_box)
	var btn := Button.new()
	btn.text = tr("ui.continue")
	var shown_ms: int = Time.get_ticks_msec()
	btn.pressed.connect(func():
		GameState.metric_card((Time.get_ticks_msec() - shown_ms) / 1000.0) # 試玩指標：1 秒內就按「繼續」＝沒在讀
		card_overlay.visible = false
		_refresh()
	)
	card_buttons_box.add_child(btn)
	card_overlay.visible = true
	btn.grab_focus.call_deferred()

# 卡片內容太長（例如成年卡）時，內文改成可捲動，「繼續」留在畫面內（2026-10-13 xvfb 量到按鈕被擠出畫面）。
func _fit_card() -> void:
	var panel: Control = card_body.get_parent().get_parent()
	var limit: float = get_viewport_rect().size.y - 8.0
	var over: float = panel.get_combined_minimum_size().y - limit
	if over <= 0.0:
		return
	var h: float = card_body.get_content_height() - over
	card_body.fit_content = false
	card_body.scroll_active = true
	card_body.custom_minimum_size.y = max(60.0, h)

# 卡片上方放狼的外貌（成年、老年轉變用）。
func _set_card_wolf(stage: String) -> void:
	card_wolf.visible = ArtLibrary.setup_wolf(card_wolf, "idle", 5.0, stage)

func _notice_lines(lines: Array) -> String:
	var texts: Array[String] = []
	for line in lines:
		var text: String = tr(str(line.get("key", "")))
		var region: String = str(line.get("region", ""))
		if region != "":
			text = text.replace("{region}", tr("region." + region))
		texts.append(text)
	return "".join(texts)

func _show_season_card(event: Dictionary) -> void:
	var season: String = str(event.get("season", GameTime.current_season()))
	var body: String = _notice_lines(event.get("lines", []))
	var review: String = _season_review_text(event.get("review", {}))
	if review != "":
		body += "

" + review
	# 苔原的卡片用那一區的季節背景（森林用季節背景）
	var bg: Texture2D = ArtLibrary.season_background(season)
	if str(event.get("map", "forest")) != "forest":
		bg = ArtLibrary.region_background(str(event.get("region", GameState.current_region)), season)
	_show_card(tr("season_card.title").replace("{season}", tr("season." + season)), body, bg)
	_play_pending_level_up() # 換季的那一覺沒有睡醒卡片，成長併在換季卡片

# 第一次獨自擊退成年灰熊的卡片：當下的成長與提高的上限（SPEC「灰熊：血量與耐力」）。
# 第一次打贏危險的對手（灰熊、美洲獅、黑熊、黑狼）：乾淨的勝利寫學到什麼，受重傷才打贏寫代價（2026-10-15 試玩回報 13）。
func _show_first_win(event: Dictionary) -> void:
	var animal: String = str(event.get("animal", ""))
	var clean: bool = bool(event.get("clean", true))
	var body: String = tr("first_win.%s.body%s" % [animal, "" if clean else ".heavy"])
	_log(body)
	_show_card(tr("first_win.%s.title" % animal), body + _first_win_growth_text(event))

func _first_win_growth_text(event: Dictionary) -> String:
	var text: String = ""
	var clean: bool = bool(event.get("clean", true))
	for pair in [["gains", "first_win.gains" + ("" if clean else ".heavy")], ["caps", "first_win.caps"]]:
		var parts: Array[String] = []
		for stat in Growth.ALL_STATS:
			if event.get(pair[0], {}).has(stat):
				parts.append(_icon_bb("stat." + stat) + tr("stat." + stat) + " ▲" + str(maxi(1, int(round(float(event[pair[0]][stat]))))))
		if not parts.is_empty():
			text += "\n\n" + tr(pair[1]) + "\n" + "　".join(parts)
	return text

# 換季字卡的成長回顧：這一季各能力的變化（含換季成長），挨餓的一季另外說明；老年有衰退時一起列出。
func _season_review_text(review: Dictionary) -> String:
	if review.is_empty():
		return ""
	var g: Dictionary = GameData.balance.get("growth", {})
	var min_change: float = float(g.get("season_review_min", 0.5))
	var starved: bool = float(review.get("fed_ratio", 1.0)) < float(g.get("season_starved_ratio", 0.3))
	var parts: Array[String] = []
	var declined: bool = false
	for stat in GameState.SLEEP_SUMMARY_STATS:
		var d: float = float(review.get("changes", {}).get(stat, 0.0))
		if absf(d) < min_change:
			continue
		declined = declined or d < 0.0
		parts.append(_icon_bb("stat." + stat) + tr("stat." + stat) + (" ▲" if d > 0.0 else " ▼") + str(maxi(1, int(round(absf(d))))))
	if parts.is_empty():
		return tr("season_card.review.starved") if starved else ""
	var key: String = "declined" if declined else ("starved_some" if starved else "grew")
	return tr("season_card.review." + key) + "
" + "　".join(parts)

# 受傷提示（QA-06）：受傷的當下只有戰鬥裡的一句，看不出傷在哪、影響什麼、要多久才好。
# _refresh 發現傷勢變重時排入 injury_notice，等遭遇結束後才顯示：重傷用卡片，輕傷用淡入提示。
func _check_new_injury(w: Wolf) -> void:
	var sig: String = "%d|%s" % [w.injury, w.injury_stat]
	if last_injury_sig == "":
		last_injury_sig = sig # 剛載入遊戲時不提示
		return
	if sig == last_injury_sig:
		return
	var old_severity: int = int(last_injury_sig.split("|")[0])
	last_injury_sig = sig
	if w.injury > old_severity or (w.injury == Wolf.Injury.HEAVY and w.injury_stat != ""):
		GameState.pending_events.append({"type": "injury_notice", "severity": w.injury})

func _show_injury_notice(event: Dictionary) -> void:
	var w: Wolf = GameState.wolf
	if w == null or w.injury == Wolf.Injury.NONE:
		return
	if int(event.get("severity", 0)) == Wolf.Injury.HEAVY and w.injury == Wolf.Injury.HEAVY:
		var stat: String = w.injury_stat
		var body: String = tr("injury.card.heavy" + ("." + stat if stat != "" else ""))
		body += "\n\n[color=%s]%s[/color]" % [LOG_COLOR_LABEL, _injury_effect_text(w)]
		body += "\n" + tr("injury.card.hp_note")
		_show_card(tr("injury.card.heavy.title"), body)
	else:
		# 輕傷也寫出從哪裡來，並留在紀錄裡（QA-51）
		var text: String = tr("injury.toast.light").replace("{days}", str(w.injury_days_remaining))
		if w.last_injury_source != "":
			text = tr("injury.toast.light_source").replace("{source}", TextFormat.injury_source(w.last_injury_source)) \
				.replace("{days}", str(w.injury_days_remaining))
		_log(text)
		_show_toast(text, 2.4)

# 「速度 −20%，約 4 天痊癒」；輕傷沒有能力影響。
# 傷勢資訊（QA-44，Phase 2 第 7 步）：部位、程度、影響、恢復方式、大約天數、舊傷。
func _show_injury_info() -> void:
	var w: Wolf = GameState.wolf
	if w == null:
		return
	region_info_text.bbcode_enabled = false
	var lines: Array[String] = [tr("injury.info.title"), ""]
	if w.injury == Wolf.Injury.NONE:
		lines.append(tr("injury.info.none"))
	else:
		var heavy: bool = w.injury == Wolf.Injury.HEAVY
		lines.append(tr("injury.info.severity." + ("heavy" if heavy else "light")))
		if w.injury_part != "":
			lines.append(tr("injury.info.part").replace("{part}", tr("injury.info.part_name." + w.injury_part.split(".")[0])))
		if w.injury_source != "":
			lines.append(tr("injury.info.source").replace("{source}", TextFormat.injury_source(w.injury_source)))
		lines.append(tr("injury.info.effect").replace("{text}", _injury_effect_text(w)))
		lines.append(tr("injury.info.days").replace("{days}", str(w.injury_days_remaining)))
		lines.append("")
		lines.append(tr("injury.info.recovery." + ("heavy" if heavy else "light")))
	if not w.old_injuries.is_empty():
		lines.append("")
		lines.append(tr("injury.info.old_title"))
		for record in w.old_injuries:
			lines.append("　" + tr(str(record.get("part_key", ""))) + "（" + TextFormat.injury_source(str(record.get("source", ""))) + "）")
	region_info_text.text = "\n".join(lines)
	region_info_overlay.visible = true

func _injury_effect_text(w: Wolf) -> String:
	if w.injury == Wolf.Injury.HEAVY and w.injury_stat != "":
		var pct: int = int(round((1.0 - float(GameData.balance.get("heavy_injury_stat_mult", 0.8))) * 100.0))
		return tr("injury.effect.heavy").replace("{stat}", tr("stat." + w.injury_stat)).replace("{n}", str(pct)) \
			.replace("{days}", str(w.injury_days_remaining))
	return tr("injury.effect.light").replace("{days}", str(w.injury_days_remaining))

func _show_day_summary(event: Dictionary) -> void:
	var texts: Array[String] = []
	for line in event.get("lines", []):
		var text: String = tr(str(line.get("key", ""))).replace("{part}", tr(str(line.get("part", ""))))
		texts.append(text)
		_log(text)
	_show_card(tr("ui.day_summary.title").replace("{n}", str(int(event.get("day", GameState.life_log.get("days_lived", 1))))), "\n".join(texts))

func _tendency_effect_text(type: String, effect: float) -> String:
	return tr("tendency_effect." + type).replace("{n}", str(int(round(effect * 100.0))))

func _show_tendency_changed(event: Dictionary) -> void:
	var type: String = str(event.get("tendency", ""))
	var text: String = tr("tendency_change." + type)
	_log(text)
	var body: String = text + "\n\n" + _icon_bb("tendency." + type, 16) + " " + tr("tendency." + type) \
		+ "　" + _tendency_effect_text(type, GameState.tendency_effect(type))
	_show_card(tr("tendency_change.title"), body)

# 成年卡片：成年外貌、身體描述、各項能力的巔峰上限（SPEC 1.6「成年轉變」）。
func _show_adult_transition() -> void:
	var w: Wolf = GameState.wolf
	var cfg: Dictionary = GameData.notices.get("adult_transition", {})
	var key: String = str(GameState.life_log.get("adult_body", ""))
	if key == "":
		key = GameState.adult_body_key()
	var body: String = tr(str(cfg.get("intro", ""))) + tr(key)
	_log(tr(str(cfg.get("intro", ""))))
	var caps: Array[String] = []
	for stat in Growth.ALL_STATS:
		caps.append(_icon_bb("stat." + stat) + tr("stat." + stat) + " " + str(int(round(float(w.potential.get(stat, Growth.get_stat(w, stat)))))))
	# 成年的那一刻身體長了一次（GameState._settle_adulthood 的 adult_bonus）
	var bonus: Dictionary = GameState.life_log.get("adult_bonus", {})
	if not bonus.is_empty():
		var gains: Array[String] = []
		for stat in Growth.ALL_STATS:
			if bonus.has(stat):
				gains.append(_icon_bb("stat." + stat) + tr("stat." + stat) + " ▲" + str(int(round(float(bonus[stat])))))
		body += "\n\n" + tr("adult_transition.bonus") + "\n" + "　".join(gains)
	body += "\n\n" + tr("adult_transition.caps") + "\n" + "　".join(caps)
	_show_card(tr("adult_transition.title"), body)
	_set_card_wolf("adult")

# 遠遠觀察的描述：黑狼依家族的階段換句子（Phase 3a 第 2 步），其他動物照舊。
func _observed_text(animal_id: String) -> String:
	if animal_id != "stranger_wolf":
		return tr("encounter.observed." + animal_id)
	return "".join(GameState.pack_observed_text_keys().map(func(k): return tr(k)))

# 老年卡片：老年外貌、身體描述、之後每季會衰退的能力，以及仍會微幅成長的技巧。
func _show_elder_transition() -> void:
	var cfg: Dictionary = GameData.notices.get("elder_transition", {})
	var text: String = tr(str(cfg.get("body", "")))
	_log(text)
	var decline: Array[String] = []
	var decay: Dictionary = Growth.age_decay(GameState.wolf.age_years)
	for stat in decay.keys():
		if float(decay[stat]) > 0.0:
			decline.append(_icon_bb("stat." + str(stat)) + tr("stat." + str(stat)))
	var growing: Array[String] = []
	for stat in cfg.get("growing", []):
		growing.append(_icon_bb("stat." + str(stat)) + tr("stat." + str(stat)))
	var body: String = text + "\n\n" + tr("elder_transition.decline").replace("{list}", "、".join(decline))
	if not growing.is_empty():
		body += "\n" + tr("elder_transition.growing").replace("{list}", "、".join(growing))
	_show_card(tr("elder_transition.title"), body)
	_set_card_wolf("elder")

func _show_tendency_panel() -> void:
	if _overlay_busy():
		return
	var cfg: Dictionary = GameData.tendency
	var decisions: Array = GameState.life_log.get("decisions", [])
	var shares: Dictionary = GameState.tendency_shares()
	var current: Dictionary = GameState.current_tendency()
	var lines: Array[String] = []
	if current.is_empty():
		lines.append(tr("ui.tendency.none").replace("{n}", str(max(0, int(cfg.get("min_decisions", 10)) - decisions.size()))))
	else:
		var type: String = str(current["type"])
		lines.append(_icon_bb("tendency." + type, 16) + " " + tr("ui.tendency.main").replace("{name}", tr("tendency." + type)) \
			+ "　" + _tendency_effect_text(type, float(current["effect"])))
		lines.append(tr("tendency_desc." + type))
	lines.append("")
	lines.append(tr("ui.tendency.recent").replace("{n}", str(decisions.size())))
	for t in cfg.get("types", []):
		var pct: int = int(round(float(shares.get(t, 0.0)) * 100.0))
		lines.append("%s %s　%d%%　%s" % [_icon_bb("tendency." + str(t)), tr("tendency." + str(t)), pct, "▮".repeat(int(round(pct / 5.0)))])
	lines.append("")
	lines.append(tr("ui.tendency.switch_hint").replace("{n}", str(int(round(float(cfg.get("switch_margin", 0.1)) * 100.0)))))
	_show_card(tr("ui.tendency.title"), "\n".join(lines))

func _build_toast() -> void:
	toast = RichTextLabel.new()
	toast.bbcode_enabled = true
	toast.fit_content = true
	toast.scroll_active = false
	toast.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	# 放在能力條下方，避免蓋住畫面中央的卡片
	toast.anchor_top = 0.21
	toast.offset_left = -200
	toast.offset_right = 200
	toast.modulate = Color(1, 1, 1, 0)
	toast.theme_type_variation = &"Toast"
	add_child(toast)

# 不擋操作的短暫提示：淡入、停留、淡出。正在顯示時新的提示排在後面，不互相蓋掉（最多留 TOAST_QUEUE_MAX 條）。
const TOAST_QUEUE_MAX := 3
var toast_queue: Array = []

func _show_toast(text: String, hold: float = 1.6) -> void:
	if toast_tween != null and toast_tween.is_running():
		toast_queue.append([text, hold])
		while toast_queue.size() > TOAST_QUEUE_MAX:
			toast_queue.pop_front()
		return
	_play_toast(text, hold)

func _next_toast() -> void:
	if not toast_queue.is_empty():
		var next: Array = toast_queue.pop_front()
		_play_toast(str(next[0]), float(next[1]))

func _play_toast(text: String, hold: float) -> void:
	toast.text = "[center]" + text + "[/center]"
	move_child(toast, get_child_count() - 1)
	if toast_tween != null:
		toast_tween.kill()
	toast_tween = create_tween()
	toast.modulate = Color(1, 1, 1, 0)
	toast_tween.tween_property(toast, "modulate:a", 1.0, 0.4)
	toast_tween.tween_interval(hold)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.6)
	toast_tween.finished.connect(_next_toast)

func _show_day_toast() -> void:
	if GameState.wolf == null or not GameState.wolf.alive or GameState.auto_playing:
		return
	# 有季節卡片或換日摘要要顯示時，卡片本身就交代了換日
	if card_overlay.visible:
		return
	for event in GameState.pending_events:
		if event.get("type", "") in ["season_card", "day_summary"]:
			return
	# 和頂部一致：這一季的第幾天；到期後顯示季末（QA-56）
	var season_text: String = tr("season." + GameTime.current_season())
	_show_toast(tr("ui.season_end").replace("{season}", season_text) if GameTime.season_due() \
		else tr("ui.day_toast").replace("{n}", str(GameTime.day)).replace("{season}", season_text))

# 睡覺結算：上次睡覺到這次提升的能力；速度或力量提升時附一句原因（也寫進行動紀錄）。
# 睡覺結算卡片：這一晚長了哪些能力（附數字），沒有成長時寫原因（QA-47）。
func _show_sleep_summary(summary: Dictionary) -> void:
	var gains: Array = summary.get("gains", [])
	var amounts: Dictionary = summary.get("amounts", {})
	var lines: Array[String] = []
	if not gains.is_empty():
		var parts: Array[String] = []
		for stat in gains:
			parts.append(_icon_bb("stat." + str(stat)) + tr("stat." + str(stat)) + " [color=%s]▲%.1f[/color]" % [UiTheme.html("stat_gain"), float(amounts.get(stat, 0.0))])
		lines.append(tr("sleep_summary.today") + "　".join(parts))
	var reason: String = str(summary.get("reason", ""))
	if reason != "":
		lines.append(tr(reason))
		_log(tr(reason))
	if lines.is_empty():
		return
	_show_card(tr("sleep_summary.title"), "\n".join(lines))
	_play_pending_level_up()

# 一般的睡醒成長（字卡分級 2026-10-16）：不出卡片，寫進紀錄，有能力提升時淡出提示一次（同一晚合併成一條）。
func _show_sleep_growth(summary: Dictionary) -> void:
	var gains: Array = summary.get("gains", [])
	var amounts: Dictionary = summary.get("amounts", {})
	var reason: String = tr(str(summary.get("reason", ""))) if str(summary.get("reason", "")) != "" else ""
	if not gains.is_empty():
		var plain: Array[String] = []
		var rich: Array[String] = []
		for stat in gains:
			var amount: String = "▲%.1f" % float(amounts.get(stat, 0.0))
			plain.append(tr("stat." + str(stat)) + " " + amount)
			rich.append(_icon_bb("stat." + str(stat)) + tr("stat." + str(stat)) + " [color=%s]%s[/color]" % [UiTheme.html("stat_gain"), amount])
		_log(tr("sleep_summary.log").replace("{list}", "　".join(plain)))
		_show_toast(tr("sleep_summary.toast").replace("{list}", "　".join(rich)) + ("\n" + reason if reason != "" else ""), 2.6)
	_log(reason)
	_play_pending_level_up()

# 能力提升的音效跟著卡片出現（被驚醒時卡片排在遭遇之後，音效不先播，試玩回報 14）
func _play_pending_level_up() -> void:
	if level_up_pending:
		level_up_pending = false
		Audio.play_level_up()

# --- 除錯：模擬到死亡 ---

func _start_auto_play(den: String, prey: String, style: String) -> void:
	if auto_player != null:
		return
	current_hunt = null
	for overlay in [encounter_overlay, hunt_overlay, rest_overlay, region_info_overlay, card_overlay]:
		overlay.visible = false
	auto_player = AutoPlayer.new(prey, style)
	auto_player.start(den)

# 從目前這隻狼開始自動玩到次成年期最後一天（之後交還給玩家）。
func _start_auto_to_adult(prey: String, style: String) -> void:
	if auto_player != null:
		return
	if GameState.wolf == null or GameState.wolf.life_stage() != Wolf.LifeStage.SUBADULT:
		auto_status.text = tr("debug.already_adult")
		return
	current_hunt = null
	for overlay in [encounter_overlay, hunt_overlay, rest_overlay, region_info_overlay, card_overlay]:
		overlay.visible = false
	auto_player = AutoPlayer.new(prey, style)
	auto_player.stop_before_adult = true
	auto_player.start_from_current()

func _process(delta: float) -> void:
	if auto_player == null:
		GameState.metric_play_time(delta)
		text_watch_timer -= delta
		if text_watch_timer <= 0.0 and not GameState.auto_playing:
			text_watch_timer = TEXT_WATCH_INTERVAL
			_report_text_issues(text_watch.scan(self, debug_overlay))
		return
	auto_player.step(AUTO_DAYS_PER_FRAME)
	if GameState.wolf != null:
		auto_status.text = tr("debug.auto.running").replace("{age}", "%.1f" % GameState.wolf.age_years) \
			.replace("{n}", str(int(GameState.life_log.get("days_lived", 1))))
	if auto_player.done():
		# 死亡時 GameState 已發出 wolf_died，畫面會切到一生回顧；活著（跳到次成年期最後一天）就交還給玩家。
		auto_player.finish()
		auto_player = null
		if GameState.wolf != null and GameState.wolf.alive:
			GameState.pending_events.clear()
			GameState.clear_discovery()
			auto_status.text = tr("debug.auto.done")
			_sync_debug_spins()
			_refresh()

# --- Lifecycle ---

var death_card_shown: bool = false

# 死去時先用一張字卡交代這一生怎麼結束（2026-10-15 試玩：原本直接跳到一生回顧），按「繼續」才到一生回顧。
# wolf_died 訊號和各處主動呼叫都會進來，只顯示一次；延到這一格最後，讓正在進行的畫面先處理完。
func _on_wolf_died(cause: String) -> void:
	if not is_inside_tree() or death_card_shown:
		return
	death_card_shown = true
	_show_death_card.call_deferred(cause)

func _show_death_card(cause: String) -> void:
	for o in [encounter_overlay, hunt_overlay, rest_overlay, region_info_overlay, debug_overlay]:
		o.visible = false
	current_hunt = null
	current_combat = null
	var bg: Texture2D = ArtLibrary.region_background(GameState.current_region, "burned") if cause == "fire" else null
	_show_card(tr("death.card.title"), _death_text(cause), bg)
	_clear_children(card_buttons_box)
	var btn := Button.new()
	btn.text = tr("ui.continue")
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/LifeSummary.tscn"))
	card_buttons_box.add_child(btn)
	card_overlay.move_to_front()
	btn.grab_focus.call_deferred()

# 死因的字卡：老死依所在的地圖寫景；戰死寫出對手（認得才寫名字）。
func _death_text(cause: String) -> String:
	match cause:
		"old_age":
			var key: String = "death.card.old_age." + GameState.current_map()
			return tr(key) if tr(key) != key else tr("death.card.old_age.forest")
		"combat", "bear":
			var d: Dictionary = GameState.life_log.get("death_detail", {})
			var animal: String = str(d.get("animal", "grizzly_bear" if cause == "bear" else ""))
			if animal != "":
				return tr("death.card.combat").replace("{animal}", TextFormat.source_name(animal))
			return tr("death.card.combat.generic")
	var k: String = "death.card." + cause
	return tr(k) if tr(k) != k else tr("death.card.unknown")

func _on_save_and_exit() -> void:
	SaveSystem.save_game()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# 遭遇時想起上一次交手的結果。黑狼、苔原狼是具名的對手：記得「上次你還不是牠（們）的對手」；
# 灰熊等一般動物依現在的實力差距判斷（QA-41），苔原狼兩隻都在時用「牠們」（QA-42）。
func _remember_line(animal_id: String, life_stage: String) -> String:
	var plural: bool = animal_id == "tundra_wolf" and GameState.tundra_pair().size() > 1
	var history: String = GameState.opponent_history(animal_id, life_stage)
	if history == "":
		return ""
	var named: bool = animal_id in ["stranger_wolf", "tundra_wolf", "challenger"]
	# 年輕的挑戰者每次來都更壯：用牠現在的實際能力比（試玩 BUG-04，原本用資料表的固定力量）
	if history == "lost" and animal_id == "challenger" and GameState.challenger() != null:
		return tr("combat.remember") + tr("stranger.compare." + str(GameState.npc_assessment(GameState.challenger())["compare"]))
	if history == "lost" and not named:
		var opp_power: float = float(FightRules.opponent_profile(animal_id, life_stage).get("power", 100))
		return tr("combat.remember.generic." + GameState.power_compare(opp_power)).replace("{animal}", _prey_name(animal_id, life_stage))
	var key: String = "combat.remember" if history == "lost" else "combat.remember_won"
	return tr(key + (".plural" if plural else ""))

# 和苔原狼比較強弱的句子：兩隻都在時用「牠們」（QA-42）。
func _tundra_compare_text(compare: String) -> String:
	return tr(("tundra.compare." if GameState.tundra_pair().size() > 1 else "stranger.compare.") + compare)
