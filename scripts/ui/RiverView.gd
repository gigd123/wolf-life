extends Control

# 鮭魚洄流的河岸畫面（Phase 2h 第 2 步）：版面同戰術狩獵（scripts/core/RiverFishing.gd 管規則）。
# 點亮起的格子移動；站上淺灘按「撲魚」；隨時「離開河邊」。淺灘上的點是魚量（3 點最多）。
# 主遊戲用 start(rf, done_cb)：結束時按「繼續」呼叫 done_cb(rf)，時間、體力、飽食度由 GameState.finish_salmon_fishing 結算。

const RF := preload("res://scripts/core/RiverFishing.gd")
const CELL := 14
const MAP_ORIGIN := Vector2(4, 4)
const COLORS := {
	".": Color("#5f7a3a"), "f": Color("#2d4a2a"), "l": Color("#6b4f33"), "r": Color("#8a877e"), "w": Color("#3f6478"), "s": Color("#5f8f8a"), "d": Color("#1f3f5c"),
	"move": Color(0.95, 0.85, 0.3, 0.3), "fish": Color("#f08a70"), "wolf": Color("#c9c9c9"),
}

var rf = null
var on_done: Callable
var map: Control
var info: RichTextLabel
var log_box: RichTextLabel
var buttons: HFlowContainer
var hover_box: RichTextLabel
var hover := Vector2i(-1, -1)
var lines: Array[String] = []
var art_sprites := {}
var art_tiles := {}
var wolf_facing := Vector2i(1, 0)
var last_wolf_pos := Vector2i(-99, -99)

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1b1e1a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	map = Control.new()
	map.position = MAP_ORIGIN
	map.size = Vector2(40 * CELL, 16 * CELL)
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var ta: Dictionary = GameData.art.get("tactical", {})
	for k in ta.get("sprites", {}).keys():
		art_sprites[k] = ArtLibrary.texture(str(ta["sprites"][k]))
	for k in ta.get("tiles", {}).keys():
		art_tiles[k] = (ta["tiles"][k] as Array).map(func(path): return ArtLibrary.texture(str(path)))
	map.draw.connect(_draw_map)
	map.gui_input.connect(_map_input)
	map.mouse_exited.connect(func(): hover = Vector2i(-1, -1); _refresh())
	add_child(map)
	info = RichTextLabel.new()
	info.position = Vector2(568, 2)
	info.size = Vector2(70, 230)
	info.bbcode_enabled = true
	info.scroll_active = false
	info.theme_type_variation = &"SmallRichLabel"
	add_child(info)
	log_box = RichTextLabel.new()
	log_box.position = Vector2(4, 262)
	log_box.size = Vector2(400, 94)
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.theme_type_variation = &"SmallRichLabel"
	add_child(log_box)
	buttons = HFlowContainer.new()
	buttons.position = Vector2(410, 262)
	buttons.size = Vector2(226, 30)
	buttons.add_theme_constant_override("separation", 4)
	add_child(buttons)
	hover_box = RichTextLabel.new()
	hover_box.position = Vector2(410, 318)
	hover_box.size = Vector2(226, 40)
	hover_box.bbcode_enabled = true
	hover_box.scroll_active = false
	hover_box.theme_type_variation = &"SmallRichLabel"
	add_child(hover_box)

func start(p_rf, done_cb: Callable) -> void:
	rf = p_rf
	on_done = done_cb
	lines = [tr("river.ui.intro")]
	_after_action()

# --- 輸入 ---

func _cell_at(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / CELL), int(p.y / CELL))

func _map_input(ev: InputEvent) -> void:
	if rf == null:
		return
	if ev is InputEventMouseMotion:
		var c := _cell_at(ev.position)
		if c != hover:
			hover = c
			_refresh()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if rf.done:
			return
		var c := _cell_at(ev.position)
		if rf.reachable().has(c):
			rf.move_to(c)
			_after_action()

func _after_action() -> void:
	for e in rf.events:
		lines.append(str(e))
	rf.events = []
	if rf.done:
		lines.append("[color=#9fe08a]%s[/color]" % tr("river.ui.result").replace("{turns}", _periods(rf.game_turns())).replace("{n}", str(rf.caught)).replace("{h}", str(roundi(rf.eaten))))
	log_box.text = "\n".join(lines.slice(maxi(0, lines.size() - 30)))
	_build_buttons()
	_refresh()

func _build_buttons() -> void:
	for c in buttons.get_children():
		c.queue_free()
	if rf.done:
		var cont := Button.new()
		cont.theme_type_variation = &"SmallButton"
		cont.text = tr("ui.continue")
		cont.pressed.connect(func():
			var cb := on_done
			queue_free()
			cb.call(rf))
		buttons.add_child(cont)
		return
	var fb := Button.new()
	fb.theme_type_variation = &"SmallButton"
	if rf.can_fish():
		fb.text = tr("river.ui.fish").replace("{p}", str(roundi(rf.fish_chance() * 100.0)))
	else:
		fb.text = tr("river.ui.full") if rf.hunger >= rf.hunger_max else tr("river.ui.fish_here")
		fb.disabled = true
	fb.pressed.connect(func(): rf.fish_once(); _after_action())
	buttons.add_child(fb)
	var lv := Button.new()
	lv.theme_type_variation = &"SmallButton"
	lv.text = tr("river.ui.leave")
	lv.pressed.connect(func(): rf.leave(); _after_action())
	buttons.add_child(lv)

func _refresh() -> void:
	map.queue_redraw()
	info.text = _info_text()
	hover_box.text = _hover_text()

# --- 右側資訊 ---

# 遊戲回合換成時段（4 回合一個時段），寫成「¼」「½」「1」「1¾」
static func periods_text(turns: int) -> String:
	var whole: int = turns / GameTime.TURNS_PER_PERIOD
	var frac: String = ["", "¼", "½", "¾"][turns % GameTime.TURNS_PER_PERIOD]
	return (str(whole) if whole > 0 or frac == "" else "") + frac

func _periods(turns: int) -> String:
	return periods_text(turns)

func _bar(v: float, mx: float, color: String) -> String:
	var n: int = clampi(roundi(v / max(1.0, mx) * 6.0), 0, 6)
	return "[color=%s]%s[/color][color=#444]%s[/color]" % [color, "█".repeat(n), "█".repeat(6 - n)]

func _info_text() -> String:
	var t: Array[String] = []
	t.append(tr("river.ui.stage." + rf.stage))
	t.append(tr("tactical.ui.round").replace("{n}", str(rf.rounds)))
	t.append(tr("river.ui.time").replace("{n}", _periods(rf.game_turns())))
	t.append("")
	t.append(tr("river.ui.hunger").replace("{n}", str(roundi(rf.hunger))).replace("{max}", str(roundi(rf.hunger_max))))
	t.append(_bar(rf.hunger, rf.hunger_max, "#e0a070"))
	if rf.overfed():
		t.append("[color=#e0c070]%s[/color]" % tr("river.ui.overfed"))
	t.append(tr("river.ui.caught").replace("{n}", str(rf.caught)))
	return "\n".join(t)

func _hover_text() -> String:
	if rf.done or hover.x < 0 or not rf.in_bounds(hover):
		return ""
	var parts: Array[String] = []
	var q: int = rf.fish_at(hover)
	if q > 0:
		parts.append(tr("river.ui.spot.%d" % q))
	elif rf.terrain(hover) == "d":
		parts.append(tr("river.ui.deep"))
	if rf.reachable().has(hover):
		parts.append(tr("river.ui.move"))
	return "　".join(parts)

# --- 地圖 ---

func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * CELL, Vector2(CELL, CELL))

func _draw_tile(c: Vector2i) -> void:
	var kind: String = rf.terrain(c)
	var list: Array = art_tiles.get(kind, [])
	var tex: Texture2D = list[(c.x * 7 + c.y * 13) % list.size()] if not list.is_empty() else null
	if tex != null:
		map.draw_texture_rect(tex, _cell_rect(c), false)
	else:
		map.draw_rect(_cell_rect(c), COLORS.get(kind, COLORS["."]))

func _draw_animal(kind: String, c: Vector2i, facing: Vector2i) -> bool:
	var tex: Texture2D = art_sprites.get(kind, null)
	if tex == null:
		return false
	var d := Vector2i(signi(facing.x), signi(facing.y))
	var idx: int = maxi(0, RF.DIRS.find(d))
	map.draw_texture_rect_region(tex, _cell_rect(c), Rect2(idx * CELL, 0, CELL, CELL))
	return true

func _draw_map() -> void:
	if rf == null:
		return
	for y in rf.height:
		for x in rf.width:
			var c := Vector2i(x, y)
			_draw_tile(c)
			# 魚量：淺灘左下角的小點，3 點最多
			var q: int = rf.fish_at(c)
			for i in q:
				map.draw_circle(Vector2(c) * CELL + Vector2(3 + i * 4, CELL - 3), 1.5, COLORS["fish"])
	if not rf.done:
		for c in rf.reachable().keys():
			map.draw_rect(_cell_rect(c), COLORS["move"])
	if rf.wolf_pos != last_wolf_pos:
		var mv: Vector2i = rf.wolf_pos - last_wolf_pos
		if last_wolf_pos.x > -99 and mv != Vector2i.ZERO:
			wolf_facing = mv
		last_wolf_pos = rf.wolf_pos
	if not _draw_animal("wolf", rf.wolf_pos, wolf_facing):
		map.draw_circle(Vector2(rf.wolf_pos) * CELL + Vector2(CELL, CELL) * 0.5, CELL * 0.42, COLORS["wolf"])
	if hover.x >= 0:
		map.draw_rect(_cell_rect(hover), Color(1, 1, 1, 0.6), false, 1.0)
