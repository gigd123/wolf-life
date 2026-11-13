extends Control
# 森林大火逃生地圖的原型畫面（Phase 2n 第 1 步，2026-11-13）：2D 佔位圖，主選單「大火逃生（原型）」進來，和遊戲進度無關。
# 點格子移動（框起來的是走得到的格子）、站在地圖邊上可以往那一邊離開、「等」原地回喘、「交給本能」走一步。
# 看不到的地方是黑的；看過但被煙遮住的地方照樣畫地形（暗一點），火與煙只畫看得到的範圍（燃燒的火光在兩倍視線內也看得到）。
# 第 5 步換成 HD-2D。

const CELL := 8
const MAP_ORIGIN := Vector2(4, 4)
const MAPS := ["edge_1", "edge_2", "dense_1", "dense_2", "logs_1", "river_1", "pond_1", "stream_1"]
const WARN := ["early", "normal", "late"]
const COLORS := {
	".": Color("#7a9a4a"), "f": Color("#2f5a32"), "a": Color("#8aa83a"), "h": Color("#5f7a3a"), "l": Color("#6a5236"),
	"w": Color("#4f86b0"), "d": Color("#2d5a8a"), "r": Color("#8a8580"), "g": Color("#a09a90"), "x": Color("#3a3634"), "n": Color("#3a2a20"),
	"burning": Color("#ff6a1a"), "hot": Color("#8a2f14"), "ash": Color("#3f3a38"), "ember": Color("#ffd23a"),
}

var fe := FireEscape.new()
var map: Control
var info: RichTextLabel
var log_box: RichTextLabel
var buttons: HFlowContainer
var setup_row: HBoxContainer
var map_pick: OptionButton
var wind_pick: OptionButton
var warn_pick: OptionButton
var den_check: CheckBox
var seed := 1
var row2: HBoxContainer
var game_mode := false # 主遊戲裡（Phase 2n 第 4 步）：沒有原型的選項，四個邊寫出連到的區域，結束時按「繼續」回主遊戲
var on_done: Callable

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#141614")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	map = Control.new()
	map.position = MAP_ORIGIN
	map.size = Vector2(40 * CELL, 32 * CELL)
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.draw.connect(_draw_map)
	map.gui_input.connect(_map_input)
	add_child(map)
	info = RichTextLabel.new()
	info.position = Vector2(332, 4)
	info.size = Vector2(304, 130)
	info.bbcode_enabled = true
	info.scroll_active = false
	info.theme_type_variation = &"SmallRichLabel"
	add_child(info)
	log_box = RichTextLabel.new()
	log_box.position = Vector2(332, 136)
	log_box.size = Vector2(304, 120)
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.theme_type_variation = &"SmallRichLabel"
	add_child(log_box)
	buttons = HFlowContainer.new()
	buttons.position = Vector2(332, 260)
	buttons.size = Vector2(304, 60)
	buttons.add_theme_constant_override("h_separation", 3)
	buttons.add_theme_constant_override("v_separation", 3)
	add_child(buttons)
	setup_row = HBoxContainer.new()
	setup_row.position = Vector2(4, 268)
	setup_row.add_theme_constant_override("separation", 3)
	add_child(setup_row)
	map_pick = _option(MAPS.map(func(m): return m), 74)
	wind_pick = _option([tr("fire.wind.0"), tr("fire.wind.1"), tr("fire.wind.2")], 56)
	wind_pick.selected = 1
	warn_pick = _option(WARN.map(func(w): return tr("fire.ui.warn." + w)), 70)
	warn_pick.selected = 1
	den_check = CheckBox.new()
	den_check.text = tr("fire.ui.has_den")
	den_check.theme_type_variation = &"SmallButton"
	setup_row.add_child(den_check)
	row2 = HBoxContainer.new()
	row2.position = Vector2(4, 300)
	row2.add_theme_constant_override("separation", 3)
	add_child(row2)
	for pair in [["fire.ui.new", func(): seed += 1; _new()], ["fire.ui.replay", _new], ["fire.ui.back", func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")]]:
		var b := Button.new()
		b.text = tr(pair[0])
		b.theme_type_variation = &"SmallButton"
		b.pressed.connect(pair[1])
		row2.add_child(b)
	_new()

# 主遊戲用：照世界的狀態產生好的火場；sides = {邊: {region, kind}}，done_cb 在按「繼續」時呼叫
func start_from_game(p_fe: FireEscape, intro: String, done_cb: Callable) -> void:
	game_mode = true
	on_done = done_cb
	setup_row.visible = false
	row2.visible = false
	fe = p_fe
	log_box.clear()
	if intro != "":
		_log(intro)
	if bool(fe.get_meta("memory", false)):
		_log("[color=#e0c070]" + tr("fire.memory") + "[/color]")
	_log(tr("fire.ui.start").format({"wind": _wind_text()}))
	_refresh()

# 某一邊連到哪裡（主遊戲）：區域名，在燒的寫出來；沒有連到的是「這一區的邊緣」
func _side_label(s: String) -> String:
	var base: String = tr("fire.side." + s)
	if not game_mode:
		return base
	var d: Dictionary = (fe.get_meta("sides", {}) as Dictionary).get(s, {})
	var r: String = str(d.get("region", ""))
	if r == "":
		return base + tr("fire.ui.side_edge")
	return base + "（" + tr("region." + r) + ("・" + tr("fire.ui.burning") if fe.edges_burning.has(s) else "") + "）"

func _option(items: Array, w: float) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.custom_minimum_size = Vector2(w, 0)
	o.theme_type_variation = &"SmallButton"
	setup_row.add_child(o)
	return o

func _new() -> void:
	var winds := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
	fe = FireEscape.new()
	fe.setup({"hunt_map": MAPS[map_pick.selected], "seed": seed, "wind": winds[seed % 4], "strength": wind_pick.selected,
		"warning": WARN[warn_pick.selected], "den": den_check.button_pressed, "wolf": {"perception": 55, "health": 100, "health_max": 100}})
	log_box.clear()
	_log(tr("fire.ui.start").format({"wind": _wind_text()}))
	_refresh()

func _wind_text() -> String:
	var dirs := {Vector2i(1, 0): "fire.dir.e", Vector2i(-1, 0): "fire.dir.w", Vector2i(0, 1): "fire.dir.s", Vector2i(0, -1): "fire.dir.n"}
	var v := Vector2i(roundi(fe.wind.x), roundi(fe.wind.y))
	var d: String = tr(dirs.get(v, "fire.dir.diag"))
	return tr("fire.ui.wind").format({"dir": d, "strength": tr("fire.wind.%d" % fe.strength)})

func _log(t: String) -> void:
	log_box.append_text(t + "\n")

func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2i(int(ev.position.x / CELL), int(ev.position.y / CELL))
		if fe.done:
			return
		if fe.reachable().has(c):
			fe.move_to(c)
			_after()

func _after() -> void:
	for e in fe.events:
		match str(e.get("kind", "")):
			"ember":
				if fe.visible(e["cell"]):
					_log(tr("fire.ui.ember"))
			"choke":
				_log(tr("fire.ui.choke"))
			"burned":
				_log(tr("fire.ui.burned"))
			"den_in":
				_log(tr("fire.ui.den_in"))
			"den_out":
				_log(tr("fire.ui.den_out"))
			"den_smoke":
				_log("[color=#ff9a6a]" + tr("fire.ui.den_smoke") + "[/color]")
	fe.events = []
	for w in fe.wind_events:
		_log(tr("fire.ui.wind_change") + _wind_text())
	fe.wind_events = []
	if fe.done:
		_log("[b]" + tr("fire.result." + fe.result).format({"side": tr("fire.side." + fe.exit_side) if fe.exit_side != "" else ""}) + "[/b]")
		if fe.outcome() != "death":
			_log(tr("fire.ui.damage").format({"n": roundi(fe.total_damage())}) + "　" + tr("fire.outcome." + fe.outcome() + ("" if fe.outcome() in ["safe", "death"] or str(fe.summary()["cause"]) == "fire" else ".smoke")))
	_refresh()

func _refresh() -> void:
	map.queue_redraw()
	var t: Array[String] = []
	t.append(tr("fire.ui.round").format({"n": fe.rounds}) + "　" + _wind_text())
	t.append(tr("fire.ui.breath").format({"n": roundi(fe.breath), "max": roundi(fe.breath_max)}) + "　" + tr("fire.ui.health").format({"n": roundi(float(fe.wolf["health"]))}))
	if fe.in_den:
		t.append(tr("fire.ui.in_den") + ("　" + tr("fire.ui.den_smoky") if fe.den_smoke else ""))
	t.append(tr("fire.ui.smoke").format({"s": tr("fire.smoke.%d" % fe.smoke_at(fe.wolf_pos))}) + "　" + tr("fire.ui.sight").format({"n": fe.sight_radius()}))
	if game_mode:
		t.append(tr("fire.ui.sides").format({"list": "　".join(["n", "e", "s", "w"].map(func(s): return _side_label(s)))}))
	elif not fe.edges_burning.is_empty():
		t.append(tr("fire.ui.edges_burning").format({"list": "、".join(fe.edges_burning.map(func(s): return tr("fire.side." + s)))}))
	t.append("[color=#999999]" + tr("fire.ui.hint") + "[/color]")
	info.text = "\n".join(t)
	for b in buttons.get_children():
		b.queue_free()
	if fe.done:
		if game_mode:
			_btn(tr("ui.continue"), func():
				var cb := on_done
				cb.call(fe))
		return
	if fe.in_den:
		_btn(tr("fire.ui.den_stay"), func(): fe.wait(); _after())
		_btn(tr("fire.ui.den_leave"), func(): fe.leave_den(); _after())
		return
	if fe.can_enter_den():
		_btn(tr("fire.ui.den_enter"), func(): fe.enter_den(); _after())
	for s in fe.can_exit():
		_btn(tr("fire.ui.exit").format({"side": _side_label(s)}), func(): fe.exit_to(s); _after())
	_btn(tr("fire.ui.wait"), func(): fe.wait(); _after())
	_btn(tr("fire.ui.instinct"), func(): FireInstinct.step(fe, "smart"); _after())

func _btn(label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.theme_type_variation = &"SmallButton"
	b.pressed.connect(cb)
	buttons.add_child(b)

func _draw_map() -> void:
	var r: int = fe.sight_radius()
	for y in fe.height:
		for x in fe.width:
			var p := Vector2i(x, y)
			var rect := Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL))
			if not fe.known.has(p):
				# 看不到的地方：燃燒的火光在兩倍視線內也看得到
				var glow: bool = fe.burning(p) and fe._cheb(p, fe.wolf_pos) <= r * 2
				map.draw_rect(rect, Color("#5a2a10") if glow else Color("#0a0a0a"))
				continue
			var vis: bool = fe.visible(p)
			var col: Color = COLORS.get(fe.terrain(p), Color.MAGENTA)
			if vis and fe.fire.has(p):
				col = COLORS[fe.state(p)]
			if not vis:
				col = col.darkened(0.55)
			map.draw_rect(rect, col)
			if vis:
				var sm: int = fe.smoke_at(p)
				if sm > 0:
					map.draw_rect(rect, Color(0.75, 0.75, 0.72, 0.18 * sm))
				if fe.embers.has(p):
					map.draw_circle(rect.get_center(), 1.6, COLORS["ember"])
			elif fe.burning(p) and fe._cheb(p, fe.wolf_pos) <= r * 2:
				map.draw_rect(rect, Color(1.0, 0.4, 0.1, 0.5))
	if not fe.done:
		for p in fe.reachable():
			map.draw_rect(Rect2(Vector2(p) * CELL, Vector2(CELL, CELL)).grow(-1), Color(1, 1, 1, 0.25), false, 1.0)
	if fe.den_cell.x >= 0 and fe.known.has(fe.den_cell):
		map.draw_rect(Rect2(Vector2(fe.den_cell) * CELL, Vector2(CELL, CELL)).grow(-1), Color("#e0c070"), false, 1.5)
	map.draw_circle((Vector2(fe.wolf_pos) + Vector2(0.5, 0.5)) * CELL, CELL * (0.25 if fe.in_den else 0.45), Color.WHITE)
	# 地圖四邊：相鄰區在燒的那一邊畫紅線
	for s in fe.edges_burning:
		var a := Vector2.ZERO
		var b := Vector2.ZERO
		match s:
			"w": b = Vector2(0, fe.height * CELL)
			"e":
				a = Vector2(fe.width * CELL, 0)
				b = Vector2(fe.width * CELL, fe.height * CELL)
			"n": b = Vector2(fe.width * CELL, 0)
			_:
				a = Vector2(0, fe.height * CELL)
				b = Vector2(fe.width * CELL, fe.height * CELL)
		map.draw_line(a, b, Color("#ff4020"), 2.0)
