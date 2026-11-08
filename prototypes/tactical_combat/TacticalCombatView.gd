extends Control

# 戰術戰鬥原型的畫面（docs/proposals/tactical-combat-prototype.md 第十節，2026-11-04）。邏輯全在 TacticalCombat.gd。
# 操作：點綠／黃／橘的格子選這回合要走到哪（再點自己取消），再按一個動作按鈕（按下去才結算）；伴侶用右邊的指令按鈕。
# 對手：箭頭是面向；粉紅的格子是看得到的預告範圍（實色＝明確，淡色＝部分，模糊時不畫）；虛線是牠盯著誰；右欄寫預告。
# 上一回合被打中的格子畫 ×；殘骸是褐色方塊、數字是剩幾段；叼著肉的狼有橘點。

const CELL := 24
const MAP_ORIGIN := Vector2(4, 4)
const COLORS := {
	".": Color("#5f7a3a"), "f": Color("#2d4a2a"), "l": Color("#6b4f33"), "r": Color("#8a877e"), "s": Color("#5f8f8a"),
	"c": Color("#45423d"), "T": Color("#1f3a22"), "t": Color("#2f5a33"), "B": Color("#9a958a"),
	"creep": Color(0.45, 0.9, 0.45, 0.35), "trot": Color(0.95, 0.85, 0.3, 0.35), "sprint": Color(1.0, 0.55, 0.2, 0.35),
	"zone_clear": Color(1.0, 0.1, 0.45, 0.45), "zone_partial": Color(1.0, 0.2, 0.55, 0.18),
	"wolf": Color("#d6d6d6"), "mate": Color("#a8b8c8"), "grizzly_bear": Color("#7a5232"), "black_bear": Color("#2a2420"), "stranger_wolf": Color("#3a3838"), "challenger": Color("#c8b490"), "tundra_wolf": Color("#e8e4dc"), "pack_wolf": Color("#5a524a"), "member_1": Color("#b8a898"), "cougar": Color("#c8a06a"),
	"carcass": Color("#6e2f22"), "planned": Color("#ffffff"), "hit": Color("#ff3030"),
}
const SCENARIOS := ["grizzly_arrives", "grizzly_on_carcass", "grizzly_open", "cougar_cache", "cougar_ambush", "grizzly_arrives_mate", "grizzly_on_carcass_mate", "black_bear_arrives", "black_bear_on_carcass", "wolf_duel", "tundra_pair", "pack_clash", "coyote_pair", "wolverine_carcass", "lynx_hare"]
const WOLVES := ["novice", "average", "veteran"]
const KNOW := ["novice", "experienced", "veteran"]
const MODES := ["sync", "alternate"]

var tc := TacticalCombat.new()
var map: Control
var info: RichTextLabel
var log_box: RichTextLabel
var actions_box: HFlowContainer
var cmd_box: HBoxContainer
var scenario_pick: OptionButton
var wolf_pick: OptionButton
var know_pick: OptionButton
var mode_pick: OptionButton
var planned := Vector2i(-1, -1)
var range_shown := false # 點了自己的狼：顯示能走的格子（2026-11-08）
var hover := Vector2i(-1, -1)
var hit_cells: Array = []
var seed := 1
var hd: CombatHD2D # HD-2D 畫面（2026-11-05）；hd_on 時取代 2D 地圖
var hd_on := true
var hd_btn: Button
# 主遊戲（Phase 2k）：start_from_game 帶入主遊戲開好的這一場；打完按「繼續」呼叫 on_done
var game_mode := false
var on_done: Callable
var setup_row: HBoxContainer
var proto_buttons: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1b1e1a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	map = Control.new()
	map.position = MAP_ORIGIN
	map.size = Vector2(16 * CELL, 10 * CELL)
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.draw.connect(_draw_map)
	map.gui_input.connect(_map_input)
	map.mouse_exited.connect(func(): hover = Vector2i(-1, -1); map.queue_redraw())
	add_child(map)
	hd = CombatHD2D.new()
	hd.view = self
	hd.position = MAP_ORIGIN
	hd.size = map.size
	hd.cell_hovered.connect(_on_hover)
	hd.cell_clicked.connect(_on_click)
	add_child(hd)
	info = RichTextLabel.new()
	info.position = Vector2(394, 28)
	info.size = Vector2(242, 170)
	info.bbcode_enabled = true
	info.scroll_active = false
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.theme_type_variation = &"SmallRichLabel"
	add_child(info)
	cmd_box = HBoxContainer.new()
	cmd_box.position = Vector2(394, 200)
	cmd_box.add_theme_constant_override("separation", 2)
	add_child(cmd_box)
	var setup := HBoxContainer.new()
	setup.position = Vector2(4, 248)
	setup.add_theme_constant_override("separation", 3)
	add_child(setup)
	setup_row = setup
	scenario_pick = _option(setup, SCENARIOS.map(func(s): return tr("tcombat.sc." + s)), 120)
	wolf_pick = _option(setup, WOLVES.map(func(s): return tr("tcombat.wolf." + s)), 54)
	wolf_pick.selected = 1
	know_pick = _option(setup, KNOW.map(func(s): return tr("tcombat.know." + s)), 64)
	mode_pick = _option(setup, MODES.map(func(s): return tr("tcombat.mode." + s)), 76)
	hd_btn = Button.new()
	hd_btn.theme_type_variation = &"SmallButton"
	hd_btn.pressed.connect(func(): hd_on = not hd_on; _apply_hd(); _refresh())
	# 畫面切換、新局、重來、返回放在右欄最上面（原本和選項同一列，太長會蓋到右下的動作按鈕，點不到，2026-11-05）
	var top_row := HBoxContainer.new()
	top_row.position = Vector2(394, 2)
	top_row.add_theme_constant_override("separation", 3)
	add_child(top_row)
	top_row.add_child(hd_btn)
	for pair in [["tcombat.new", func(): _new_game(true)], ["tcombat.replay", func(): _new_game(false)],
			["tcombat.back", func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")]]:
		var b := Button.new()
		b.text = tr(pair[0])
		b.theme_type_variation = &"SmallButton"
		b.custom_minimum_size = Vector2(36, 24)
		b.pressed.connect(pair[1])
		top_row.add_child(b)
		proto_buttons.append(b)
	log_box = RichTextLabel.new()
	log_box.position = Vector2(4, 274)
	log_box.size = Vector2(384, 82)
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.theme_type_variation = &"SmallRichLabel"
	add_child(log_box)
	actions_box = HFlowContainer.new()
	actions_box.position = Vector2(394, 222)
	actions_box.size = Vector2(242, 134)
	actions_box.add_theme_constant_override("h_separation", 3)
	actions_box.add_theme_constant_override("v_separation", 3)
	add_child(actions_box)
	_new_game(true)

func _option(parent: Node, items: Array, width: float) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.custom_minimum_size = Vector2(width, 0)
	o.theme_type_variation = &"SmallButton"
	o.fit_to_longest_item = false
	parent.add_child(o)
	return o

func _new_game(new_seed: bool) -> void:
	if new_seed:
		seed = randi() % 100000 + 1
	tc = TacticalCombat.new()
	tc.setup(SCENARIOS[scenario_pick.selected], {"seed": seed, "wolf_profile": WOLVES[wolf_pick.selected],
		"knowledge": KNOW[know_pick.selected], "mode": MODES[mode_pick.selected]})
	log_box.clear()
	hit_cells.clear()
	planned = Vector2i(-1, -1)
	_log("[color=#aaaaaa]%s[/color]" % tr("tcombat.hint"))
	tc.begin_round()
	_log_tell()
	hd.setup(tc)
	_apply_hd()
	_refresh()

# 主遊戲用：換成主遊戲開好的這一場（GameState.start_tactical_combat），打完按「繼續」呼叫 done_cb
func start_from_game(combat: TacticalCombat, done_cb: Callable, intro: String = "") -> void:
	game_mode = true
	on_done = done_cb
	setup_row.visible = false
	for b in proto_buttons:
		(b as Button).visible = false
	tc = combat
	log_box.clear()
	hit_cells.clear()
	planned = Vector2i(-1, -1)
	if intro != "":
		_log(intro)
	_log("[color=#aaaaaa]%s[/color]" % tr("tcombat.hint"))
	tc.begin_round()
	_log_tell()
	hd.setup(tc)
	_apply_hd()
	_refresh()

func _apply_hd() -> void:
	hd.visible = hd_on
	map.visible = not hd_on
	hd_btn.text = tr("tcombat.view.hd" if hd_on else "tcombat.view.2d")

func _log(t: String) -> void:
	log_box.append_text(t + "\n")

func _name(i: int) -> String:
	if i < 0 or i >= tc.units.size():
		return ""
	var u: Dictionary = tc.units[i]
	if u.has("name"):
		return str(u["name"]) # 主遊戲帶進來的名字（成員、同一種的第二隻……）
	var base: String = tr("tcombat.name." + (str(u["id"]) if str(u["species"]) == "wolf" else str(u["species"])))
	if str(u["species"]) == "wolf" and base.begins_with("tcombat.name."):
		return tr("tcombat.name.member") + str(u["id"]).trim_prefix("member_") # 同伴1、同伴2
	# 同一種有好幾隻：加編號
	var same: Array = tc.enemies().filter(func(k): return str(tc.units[k]["species"]) == str(u["species"]))
	if str(u["side"]) == "enemy" and same.size() > 1:
		return base + str(same.find(i) + 1)
	return base

# --- 地圖 ---

func _cell_at(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / CELL), int(p.y / CELL))

func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * CELL, Vector2(CELL, CELL))

func _center(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL + Vector2(CELL, CELL) * 0.5

func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_on_hover(_cell_at(ev.position))
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_on_click(_cell_at(ev.position))

# 2D 地圖與 HD-2D 畫面共用
func _on_hover(c: Vector2i) -> void:
	if c != hover:
		hover = c
		map.queue_redraw()
		if hd_on:
			hd.refresh()
		_refresh_info()

func _on_click(c: Vector2i) -> void:
	if tc.done:
		return
	# 點自己的狼：顯示／收起能走的格子（已經選了要走到哪時，取消那一格）；顯示時點格子＝選這回合要走到哪
	if c == tc.units[0]["pos"]:
		if planned.x >= 0:
			planned = Vector2i(-1, -1)
		range_shown = not range_shown
	elif c == planned:
		planned = Vector2i(-1, -1)
		range_shown = true
	elif range_shown and tc.reachable(0).has(c):
		planned = c
		range_shown = false
	_refresh()

func _draw_map() -> void:
	for y in tc.map.height:
		for x in tc.map.width:
			var c := Vector2i(x, y)
			var k: String = tc.map.terrain(c)
			map.draw_rect(_cell_rect(c), COLORS.get(k, COLORS["."]))
			if k == "T" or k == "t":
				map.draw_circle(_center(c), CELL * (0.45 if k == "T" else 0.3), Color("#14301a"))
			elif k == "B":
				map.draw_rect(_cell_rect(c).grow(-4), Color("#b8b2a4"))
			elif k == "c":
				map.draw_line(Vector2(c) * CELL, Vector2(c) * CELL + Vector2(CELL, CELL), Color("#2e2c28"), 2.0)
	for y in tc.map.height + 1:
		map.draw_line(Vector2(0, y * CELL), Vector2(tc.map.width * CELL, y * CELL), Color(0, 0, 0, 0.18))
	for x in tc.map.width + 1:
		map.draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, tc.map.height * CELL), Color(0, 0, 0, 0.18))
	# 能走的格子（點自己的狼才顯示）
	if not tc.done and range_shown:
		var reach: Dictionary = tc.reachable(0)
		for c in reach.keys():
			map.draw_rect(_cell_rect(c).grow(-1), COLORS[reach[c]])
	# 預告範圍
	for e in tc.intents.keys():
		var seen: Dictionary = tc.intents[e].get("seen", {})
		var col: Color = COLORS["zone_clear"] if int(seen.get("level", 0)) >= 2 else COLORS["zone_partial"]
		for c in seen.get("zone", []):
			map.draw_rect(_cell_rect(c), col)
			# 明確：實線外框；部分：細的虛框
			map.draw_rect(_cell_rect(c).grow(-1), Color(1.0, 0.15, 0.5, 0.9 if int(seen.get("level", 0)) >= 2 else 0.5), false, 2.0 if int(seen.get("level", 0)) >= 2 else 1.0)
	# 殘骸、放下的肉
	if not tc.carcass.is_empty() and int(tc.carcass["segments"]) > 0:
		var r := _cell_rect(tc.carcass["pos"]).grow(-3)
		map.draw_rect(r, COLORS["carcass"])
		map.draw_string(get_theme_default_font(), r.position + Vector2(4, r.size.y - 4), str(tc.carcass["segments"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	for d in tc.drops:
		map.draw_rect(_cell_rect(d["pos"]).grow(-8), COLORS["carcass"])
	# 單位
	for i in tc.units.size():
		if not tc.active(i):
			continue
		var u: Dictionary = tc.units[i]
		var key: String = str(u["id"]) if str(u["species"]) == "wolf" else str(u["species"])
		var c: Vector2i = u["pos"]
		var big: bool = str(u["species"]) in ["grizzly_bear", "black_bear"]
		map.draw_circle(_center(c), CELL * (0.46 if big else 0.36), Color(0, 0, 0, 0.6))
		map.draw_circle(_center(c), CELL * (0.42 if big else 0.32), COLORS.get(key, Color.WHITE))
		var f := Vector2(u["facing"]).normalized()
		map.draw_line(_center(c), _center(c) + f * CELL * 0.5, Color.BLACK, 2.0)
		if str(u["carrying"]) != "":
			map.draw_circle(_center(c) + Vector2(CELL * 0.25, -CELL * 0.25), 3.0, Color("#ff9a40"))
		if bool(u.get("eating", false)):
			map.draw_string(get_theme_default_font(), Vector2(c) * CELL + Vector2(1, 9), "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
		# 注意力：對手盯著誰（細線）
		if not tc.player_side(i):
			var a: int = int(u.get("attention", -1))
			if a >= 0 and tc.active(a):
				map.draw_dashed_line(_center(c), _center(tc.units[a]["pos"]), Color(1, 0.9, 0.4, 0.5), 1.0, 3.0)
	# 計畫要走的格子
	if planned.x >= 0:
		map.draw_rect(_cell_rect(planned).grow(-1), COLORS["planned"], false, 2.0)
		map.draw_line(_center(tc.units[0]["pos"]), _center(planned), Color(1, 1, 1, 0.6), 1.0)
	# 上一回合被打中的
	for c in hit_cells:
		var r2 := _cell_rect(c).grow(-5)
		map.draw_line(r2.position, r2.end, COLORS["hit"], 2.0)
		map.draw_line(Vector2(r2.position.x, r2.end.y), Vector2(r2.end.x, r2.position.y), COLORS["hit"], 2.0)
	if hover.x >= 0 and tc.map.in_bounds(hover):
		map.draw_rect(_cell_rect(hover), Color(1, 1, 1, 0.5), false, 1.0)

# --- 右欄與按鈕 ---

func _refresh() -> void:
	map.queue_redraw()
	if hd_on:
		hd.refresh()
	_refresh_info()
	_build_actions()
	_build_commands()

func _pct(v: float) -> int:
	return int(round(v * 100.0))

func _show_text(show: Dictionary) -> String:
	match int(show["tier"]):
		0: return tr("tcombat.show.0").format({"risk": tr("tcombat.risk." + str(show["risk"])), "lo": _pct(show["lo"]), "hi": _pct(show["hi"])})
		1: return tr("tcombat.show.1").format({"lo": _pct(show["lo"]), "hi": _pct(show["hi"])})
		2: return tr("tcombat.show.2").format({"v": _pct(show["lo"])})
	return tr("tcombat.show.3").format({"v": _pct(show["lo"])})

func _refresh_info() -> void:
	var lines: Array[String] = []
	var e := tc.enemy_index()
	if tc.done:
		var ek: String = "tcombat.end." + tc.outcome + (".game" if game_mode and tr("tcombat.end." + tc.outcome + ".game") != "tcombat.end." + tc.outcome + ".game" else "")
		lines.append("[b]%s[/b]" % tr(ek).format({"n": tc.meat_taken()}))
	for e2 in tc.enemies():
		e = e2
		var u: Dictionary = tc.units[e]
		var eline: String = tr("tcombat.info.enemy").format({"name": _name(e), "hp": _pct(float(u["hp"]) / float(u["hp_max"])), "pat": _pct(float(u["stamina"]) / max(1.0, float(u["stamina_max"])))})
		if bool(u["out"]):
			eline += tr("tcombat.info.enemy_out." + str(u["out_reason"])) if tr("tcombat.info.enemy_out." + str(u["out_reason"])) != "tcombat.info.enemy_out." + str(u["out_reason"]) else tr("tcombat.info.enemy_out.left")
		lines.append(eline)
		if tc.intents.has(e) and tc.active(e):
			var seen: Dictionary = tc.intents[e].get("seen", {})
			var t: String = tr("tcombat.tell." + str(seen.get("text", "vague")))
			if bool(seen.get("feint_hint", false)):
				t += tr("tcombat.tell.feint")
			lines.append("[color=#ffb0a0]%s[/color]　[color=#999999]%s[/color]" % [t, tr("tcombat.level." + str(seen.get("level", 0)))])
	for i in tc.units.size():
		if not tc.player_side(i):
			continue
		var w: Dictionary = tc.units[i]
		var line: String = tr("tcombat.info.wolf").format({"name": _name(i), "hp": int(w["hp"]), "max": int(w["hp_max"]), "b": int(w["breath"])})
		if str(w["carrying"]) != "":
			line += tr("tcombat.info.carrying").format({"n": int(w["carry_segments"])})
		# 主遊戲：過了重傷線（再被打到 0 會死）
		if game_mode and not bool(w["out"]) and float(w["hp"]) <= float(w["hp_max"]) * float(FightRules.combat_cfg().get("danger_ratio", 0.25)):
			line += "[color=#ff5050]%s[/color]" % tr("tcombat.info.heavy")
		if bool(w["out"]):
			line += tr("tcombat.info.out." + str(w["out_reason"]))
		elif str(w["side"]) == "ally":
			line += "　" + tr("tcombat.info.mode." + tc.ally_mode(i))
		lines.append(line)
	if not tc.carcass.is_empty():
		lines.append(tr("tcombat.info.carcass").format({"n": int(tc.carcass["segments"])}))
	var from: Vector2i = planned if planned.x >= 0 else tc.units[0]["pos"]
	if tc.in_shown_zone(from) and not tc.done:
		lines.append("[color=#ff7060]%s[/color]" % tr("tcombat.in_zone"))
	lines.append("[color=#888888]%s[/color]" % tr("tcombat.round").format({"n": tc.rounds, "mode": tr("tcombat.mode." + tc.mode)}))
	info.text = "\n".join(lines)

func _build_actions() -> void:
	for c in actions_box.get_children():
		c.queue_free()
	if game_mode and tc.done:
		var cont := Button.new()
		cont.text = tr("ui.continue")
		cont.theme_type_variation = &"SmallButton"
		cont.custom_minimum_size = Vector2(60, 24)
		cont.focus_mode = Control.FOCUS_NONE
		cont.pressed.connect(func(): if on_done.is_valid(): on_done.call())
		actions_box.add_child(cont)
		return
	if tc.done or not tc.active(0):
		return
	var from: Vector2i = planned if planned.x >= 0 else tc.units[0]["pos"]
	var sprinted: bool = planned.x >= 0 and str(tc.reachable(0).get(planned, "")) == "sprint"
	var e := tc.enemy_index()
	for o in tc.action_options(0, from, sprinted):
		var id: String = str(o["id"])
		var label: String = tr("tcombat.act." + id + ("." + str(o["kind"]) if o.has("kind") else ""))
		if o.has("show"):
			label += "\n" + _show_text(o["show"])
		var b := Button.new()
		b.text = label
		b.theme_type_variation = &"SmallButton"
		b.focus_mode = Control.FOCUS_NONE
		var p := {"action": id, "target": int(o.get("target", e))}
		if o.has("kind"):
			p["kind"] = o["kind"]
		if o.has("factors") and int(o["show"]["tier"]) >= 2:
			b.tooltip_text = "\n".join((o["factors"] as Array).map(func(f): return tr("tcombat.factor." + str(f[0])) + ("" if is_zero_approx(float(f[1])) else " %+d%%" % _pct(float(f[1])))))
		b.custom_minimum_size = Vector2(36, 24) # 「等」這種一個字的按鈕太小、不好點
		b.pressed.connect(func(): _commit(p))
		actions_box.add_child(b)
	var auto := Button.new()
	auto.text = tr("tcombat.auto")
	auto.theme_type_variation = &"SmallButton"
	auto.focus_mode = Control.FOCUS_NONE
	auto.pressed.connect(_auto_play)
	actions_box.add_child(auto)

func _build_commands() -> void:
	for c in cmd_box.get_children():
		c.queue_free()
	var m := tc.index_of("mate")
	if m < 0 or not tc.active(m):
		return
	var l := Label.new()
	l.text = tr("tcombat.cmd.title")
	l.add_theme_font_size_override("font_size", 11)
	cmd_box.add_child(l)
	for cmd in TacticalCombat.COMMANDS:
		var b := Button.new()
		b.text = tr("tcombat.cmd." + cmd)
		b.theme_type_variation = &"SmallButton"
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = str(tc.units[m]["command"]) == cmd
		b.pressed.connect(func(): tc.set_command(m, cmd); _refresh())
		cmd_box.add_child(b)

# --- 結算 ---

func _commit(p: Dictionary) -> void:
	if planned.x >= 0:
		p["move"] = planned
	tc.plan(0, p)
	_resolve_and_next()

func _resolve_and_next() -> void:
	var hp_before := {}
	for i in tc.units.size():
		hp_before[i] = tc.units[i]["hp"]
	var evs: Array = tc.resolve()
	hit_cells.clear()
	_log("[color=#777777]— %s —[/color]" % tr("tcombat.round").format({"n": tc.rounds, "mode": tr("tcombat.mode." + tc.mode)}))
	for ev in evs:
		var t := _event_text(ev)
		if t != "":
			_log(t)
		if str(ev["kind"]) == "hit":
			hit_cells.append(tc.units[int(ev["target"])]["pos"])
	planned = Vector2i(-1, -1)
	if not tc.done:
		tc.begin_round()
		_log_tell()
	_refresh()

func _log_tell() -> void:
	for e in tc.intents.keys():
		var seen: Dictionary = tc.intents[e].get("seen", {})
		var t: String = tr("tcombat.tell." + str(seen.get("text", "vague")))
		if bool(seen.get("feint_hint", false)):
			t += tr("tcombat.tell.feint")
		_log("[color=#ffb0a0]%s：%s[/color]" % [_name(e), t])

func _auto_play() -> void:
	var guard := 0
	while not tc.done and guard < 60:
		guard += 1
		tc.plan(0, tc.auto_plan(0))
		_resolve_and_next()

func _event_text(ev: Dictionary) -> String:
	var k: String = str(ev["kind"])
	var who: int = int(ev.get("who", -1))
	var fmt := {"who": _name(who), "target": _name(int(ev.get("target", -1)))}
	match k:
		"move", "wait", "dodge", "guard", "turn":
			return ""
		"hit":
			fmt["dmg"] = int(round(float(ev["dmg"])))
			return "[color=#ff8070]%s[/color]" % tr("tcombat.ev.hit").format(fmt)
		"bite":
			if who >= 0 and tc.player_side(who):
				fmt["dmg"] = int(round(float(ev["dmg"])))
				return tr("tcombat.ev.wolf." + str(ev.get("how", "bite"))).format(fmt)
			return tr("tcombat.ev.enemy.bite").format(fmt)
		"swipe", "charge", "bluff_charge", "pounce":
			return tr("tcombat.ev.enemy." + k).format(fmt)
		"fled":
			return tr("tcombat.ev.fled." + str(ev.get("why", "hurt"))).format(fmt)
		"eat", "steal":
			fmt["left"] = int(ev["left"])
			return tr("tcombat.ev." + k).format(fmt)
		"take":
			fmt["n"] = int(ev["segments"])
			return tr("tcombat.ev.take." + str(ev.get("how", "piece"))).format(fmt)
		"retreat":
			fmt["n"] = int(ev.get("meat", 0))
			return tr("tcombat.ev.retreat" + ("" if int(ev.get("meat", 0)) > 0 else ".empty")).format(fmt)
		"learned":
			var parts: PackedStringArray = str(ev["key"]).split("|")
			return "[color=#a0d0ff]%s[/color]" % tr("tcombat.ev.learned").format({"animal": tr("tcombat.name." + parts[0]), "act": tr("tcombat.enemy_act." + parts[1]), "n": int(ev["count"])})
		"end":
			var ek2: String = "tcombat.end." + str(ev["outcome"])
			if game_mode and tr(ek2 + ".game") != ek2 + ".game":
				ek2 += ".game"
			return "[b]%s[/b]" % tr(ek2).format({"n": int(ev["meat"])})
	var key := "tcombat.ev." + k
	return tr(key).format(fmt) if tr(key) != key else ""
