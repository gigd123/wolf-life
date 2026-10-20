extends Control

# 戰術狩獵原型的畫面（docs/proposals/tactical-hunt-prototype.md 第九節，畫面甲：整張地圖）。
# 邏輯全在 TacticalHunt.gd；這裡只畫格子、處理點選、顯示資訊。原型的文字直接寫中文（和美術測試一樣，不進翻譯檔）。
#
# 操作：點綠／黃／橘的格子移動（潛行／小跑／衝刺），點紅框的格子撲上去咬；咬住之後用下方的按鈕。
# 鹿群版（E～H，docs/proposals/tactical-hunt-herd.md）：點一隻鹿設為目標（黃框）；幼鹿是有白點的小鹿，細線連到生母。
# 動物與地塊用 data/art.json 的 tactical（Phase 2c，程式畫的佔位圖，tools/make_tactical_art.py）；沒有圖時退回色塊。

const TH := preload("res://scripts/core/TacticalHunt.gd")
const CELL := 14
const MAP_ORIGIN := Vector2(4, 4)
const COLORS := {
	".": Color("#5f7a3a"), "f": Color("#2d4a2a"), "l": Color("#6b4f33"),
	"creep": Color(0.45, 0.9, 0.45, 0.35), "trot": Color(0.95, 0.85, 0.3, 0.35), "sprint": Color(1.0, 0.55, 0.2, 0.35),
	"wolf": Color("#c9c9c9"), "deer": Color("#b07a44"), "deer_held": Color("#d04a3a"), "intent": Color(1, 1, 1, 0.75),
	"target": Color("#ff4040"), "goal": Color(0.7, 0.9, 1.0, 0.5),
	"fawn": Color("#d9a76a"), "picked": Color("#ffe060"), "bond": Color(1, 1, 1, 0.35),
}
const SCENARIOS := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]
const WOLVES := {"slow": "慢（速度 40）", "normal": "普通（60）", "fast": "快（85）"}

var h = TH.new()
var map: Control
var info: RichTextLabel
var hover_box: RichTextLabel
var log_box: RichTextLabel
var buttons: HFlowContainer
var scenario_pick: OptionButton
var wolf_pick: OptionButton
var stamina_pick: OptionButton
var special_pick: OptionButton # 會不會前截鎖喉（特殊招式，2026-10-16）
var lock_armed: bool = false # 按了「前截鎖喉」，下一次點紫框就出手
var hover := Vector2i(-1, -1)
var game_seed: int = 0
var lines: Array[String] = []
# 動物與地塊的圖（Phase 2c，data/art.json 的 tactical；程式畫的佔位圖）
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
	# 下方：設定列、紀錄、按鈕
	var setup_row := HBoxContainer.new()
	setup_row.position = Vector2(4, 232)
	setup_row.add_theme_constant_override("separation", 4)
	add_child(setup_row)
	scenario_pick = _option(setup_row, SCENARIOS.map(func(s): return s + " " + str(h.t["scenarios"][s]["name"])))
	wolf_pick = _option(setup_row, WOLVES.values())
	wolf_pick.selected = 1
	stamina_pick = _option(setup_row, ["體力滿", "體力一半"])
	special_pick = _option(setup_row, ["無招式", "鎖喉"])
	var restart := Button.new()
	restart.text = "新局"
	restart.theme_type_variation = &"SmallButton"
	restart.pressed.connect(func(): _new_hunt(true))
	setup_row.add_child(restart)
	var replay := Button.new()
	replay.text = "重來"
	replay.theme_type_variation = &"SmallButton"
	replay.pressed.connect(func(): _new_hunt(false))
	setup_row.add_child(replay)
	var back := Button.new()
	back.text = "返回"
	back.theme_type_variation = &"SmallButton"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	setup_row.add_child(back)
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
	_new_hunt(true)

func _option(parent: Node, items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.theme_type_variation = &"SmallButton"
	for it in items:
		o.add_item(str(it))
	parent.add_child(o)
	return o

func _new_hunt(new_seed: bool) -> void:
	if new_seed or game_seed == 0:
		game_seed = randi() % 100000 + 1
	h.setup(SCENARIOS[scenario_pick.selected], WOLVES.keys()[wolf_pick.selected], game_seed, 1.0 if stamina_pick.selected == 0 else 0.5)
	last_wolf_pos = Vector2i(-99, -99)
	h.knows_front_lock = special_pick.selected == 1
	lock_armed = false
	lines = ["情境 %s，種子 %d。點綠／黃／橘色的格子移動（潛行／小跑／衝刺），點紅框撲上去咬。" % [h.t["scenarios"][h.scenario_id]["name"], game_seed]]
	if h.herd.size() > 1:
		lines.append("鹿群：點一隻鹿設為目標（黃框）。身上有白點的小鹿是幼鹿，細線連到牠的生母；衝進鹿群 2 格內會讓牠們散開。")
	_after_action()

# --- 輸入 ---

func _cell_at(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / CELL), int(p.y / CELL))

func _map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := _cell_at(ev.position)
		if c != hover:
			hover = c
			_refresh()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if h.done:
			return
		var c := _cell_at(ev.position)
		if lock_armed:
			lock_armed = false
			if h.front_lock_targets().has(c):
				h.front_lock_at(c)
				_after_action()
			else:
				_build_buttons()
				_refresh()
			return
		var targets: Dictionary = h.pounce_targets()
		if targets.has(c):
			h.pounce_at(c)
		elif h.reachable().has(c):
			h.move_to(c)
		else:
			# 點到鹿：換目標（不算一回合）
			for i in h.active_deer():
				if h.herd[i]["pos"] == c and i != h.target:
					h.set_target(i)
					_build_buttons()
					_refresh()
			return
		_after_action()

func _after_action() -> void:
	for e in h.events:
		lines.append(str(e))
	h.events = []
	if h.done:
		var color := "#9fe08a" if h.result == "caught" else "#e0a08a"
		var what: String = {"caught": "獵到", "escaped": "逃脫，留下一條新鮮足跡", "lost": "跟丟，留下一條新鮮足跡", "gave_up": "放棄", "timeout": "拖太久"}.get(h.result, h.result)
		if h.result == "caught" and (h.herd.size() > 1 or not h.sp(h.target).is_empty()):
			what += "%s（%d 段肉）" % ["幼鹿" if h.caught_kind == "fawn" else str(h.sp(h.target).get("name", "成鹿")), h.meat]
		lines.append("[color=%s]結果：%s（%d 回合，用掉的喘 %d、受傷 %d；換算遊戲時間 %d 回合、體力 −%d）[/color]" % [color, what,
			h.rounds, roundi(h.breath_used), roundi(h.damage_taken), h.game_turns(), roundi(h.stamina_cost())])
	log_box.text = "\n".join(lines.slice(maxi(0, lines.size() - 30)))
	_build_buttons()
	_refresh()

func _build_buttons() -> void:
	for c in buttons.get_children():
		c.queue_free()
	if h.done:
		return
	if h.held:
		var names := {"takedown": "壓倒", "throat": "咬喉", "hang": "死咬拖住", "hamstring": "咬後腿", "release": "鬆口"}
		var opts: Dictionary = h.hold_options()
		for id in ["takedown", "throat", "hamstring", "hang", "release"]:
			if opts.has(id):
				var b := Button.new()
				b.theme_type_variation = &"SmallButton"
				b.text = names[id] + ("" if id in ["release", "hang"] else " %d%%" % roundi(float(opts[id]["chance"]) * 100.0))
				if id == "hang":
					b.text += "（%d 喘）" % roundi(float(opts[id]["breath"]))
				b.tooltip_text = "、".join((opts[id]["factors"] as Array).map(func(f): return "%s %+d%%" % [f[0], roundi(float(f[1]) * 100.0)]))
				var a: String = id
				b.pressed.connect(func(): h.hold_action(a); _after_action())
				buttons.add_child(b)
		return
	if h.knows_front_lock:
		var fl := Button.new()
		fl.theme_type_variation = &"SmallButton"
		fl.toggle_mode = true
		fl.button_pressed = lock_armed
		var ready: bool = not h.front_lock_targets().is_empty()
		fl.disabled = not ready
		fl.text = "前截鎖喉" if h.front_lock_ready() else "前截鎖喉（能力不足）"
		fl.tooltip_text = "衝到逃跑的成鹿正前方、回身鎖喉：成功直接咬死，失敗容易被正面撞開（用掉 30 喘）。按下後點紫框。需要速度 70、技巧 60。"
		fl.toggled.connect(func(on): lock_armed = on; _refresh())
		buttons.add_child(fl)
	var obs := Button.new()
	obs.theme_type_variation = &"SmallButton"
	obs.text = "觀察（原地，回喘）"
	obs.pressed.connect(func(): h.observe(); _after_action())
	buttons.add_child(obs)
	var quit := Button.new()
	quit.theme_type_variation = &"SmallButton"
	quit.text = "放棄"
	quit.pressed.connect(func(): h.give_up(); _after_action())
	buttons.add_child(quit)

func _refresh() -> void:
	map.queue_redraw()
	info.text = _info_text()
	hover_box.text = _hover_text()

# --- 右側資訊 ---

func _bar(v: float, mx: float, color: String) -> String:
	var n: int = clampi(roundi(v / max(1.0, mx) * 6.0), 0, 6)
	return "[color=%s]%s[/color][color=#444]%s[/color]" % [color, "█".repeat(n), "█".repeat(6 - n)]

func _info_text() -> String:
	var t: Array[String] = []
	t.append("回合 %d" % h.rounds)
	t.append("風 %s" % {Vector2i(1, 0): "→", Vector2i(-1, 0): "←", Vector2i(0, 1): "↓", Vector2i(0, -1): "↑"}.get(h.wind, "?"))
	t.append({"upwind": "[color=#e08a8a]你在上風[/color]", "downwind": "[color=#9fe08a]你在下風[/color]", "crosswind": "側風"}[h.wind_side()])
	t.append("")
	t.append("喘 %d/%d" % [roundi(h.breath), roundi(h.breath_max)])
	t.append(_bar(h.breath, h.breath_max, "#7fb3e0"))
	t.append("血 %d" % roundi(float(h.wolf["health"])))
	t.append("")
	if h.herd.size() > 1:
		t.append("目標 " + h.label())
		t.append("場上 %d 隻" % h.active_deer().size())
	t.append(("" if h.herd.size() > 1 else "鹿：") + {"unaware": "沒察覺", "suspicious": "起疑", "flee": "逃跑", "stand": "站定"}.get(h.deer_state, h.deer_state) + ("（咬住）" if h.held else ""))
	if h.held:
		t.append("咬在" + {"rear": "後腿", "side": "側腹", "front": "頸部"}.get(h.hold_side, "?"))
	if int(h.herd[h.target].get("hamstrung", 0)) > 0:
		t.append("[color=#e08a8a]後腿受傷[/color]")
	if h.deer_state in ["unaware", "suspicious"]:
		t.append("警覺 %d" % roundi(h.alert))
		t.append(_bar(h.alert, 100.0, "#e0c070"))
	else:
		t.append("累 %d%%" % roundi(h.deer_fatigue_any() * 100.0))
	if h.wounds > 0:
		t.append("[color=#e08a8a]帶傷 %d[/color]" % h.wounds)
	if h.condition_known:
		t.append("體況：" + {"healthy": "健康", "average": "普通", "weak": "虛弱"}[h.condition])
	return "\n".join(t)

# 滑鼠所在的格子：移動方式，或撲咬的命中率與因素
func _hover_text() -> String:
	if h.done or hover.x < 0:
		return ""
	if lock_armed:
		var ft: Dictionary = h.front_lock_targets()
		if ft.has(hover):
			var fp: Dictionary = ft[hover]
			var parts0: Array[String] = []
			for f in fp["factors"]:
				if absf(float(f[1])) >= 0.005:
					parts0.append("%s %+d" % [f[0], roundi(float(f[1]) * 100.0)])
			return "[color=#c080ff]前截鎖喉 %d%%[/color]（失敗 35%% 被撞）\n" % roundi(float(fp["chance"]) * 100.0) + "、".join(parts0)
		return "點紫框出手；點別的地方取消"
	var targets: Dictionary = h.pounce_targets()
	if targets.has(hover):
		var p: Dictionary = targets[hover]
		var s := "[color=#ff8080]撲咬 %d%%[/color]" % roundi(float(p["chance"]) * 100.0)
		var parts: Array[String] = []
		for f in p["factors"]:
			if absf(float(f[1])) >= 0.005:
				parts.append("%s %+d" % [f[0], roundi(float(f[1]) * 100.0)])
		s += "　被踢 %d%%" % roundi(float(p["kick"]) * 100.0) if float(p["kick"]) > 0.0 else ""
		s += "\n" + "、".join(parts)
		return s
	var r: Dictionary = h.reachable()
	if r.has(hover):
		if r[hover] == "trot" and h.tired():
			return "小跑（喘不夠：少一格，不扣喘也不回喘）"
		return {"creep": "潛行（回喘）", "trot": "小跑（−4 喘）", "sprint": "衝刺（−22 喘）"}[r[hover]]
	return ""

# --- 地圖 ---

func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * CELL, Vector2(CELL, CELL))

# 地塊：同一種地形有多張時依座標輪替（固定，不會每次重畫都變）；沒有圖就畫色塊
func _draw_tile(c: Vector2i) -> void:
	var kind: String = h.terrain(c)
	var list: Array = art_tiles.get(kind, [])
	var tex: Texture2D = list[(c.x * 7 + c.y * 13) % list.size()] if not list.is_empty() else null
	if tex != null:
		map.draw_texture_rect(tex, _cell_rect(c), false)
	else:
		map.draw_rect(_cell_rect(c), COLORS[kind])

# 動物：8 個方向的橫條挑一格；held 時偏紅
func _draw_animal(kind: String, c: Vector2i, facing: Vector2i, tint: Color = Color.WHITE) -> bool:
	var tex: Texture2D = art_sprites.get(kind, null)
	if tex == null:
		return false
	var d := Vector2i(signi(facing.x), signi(facing.y))
	var idx: int = maxi(0, TH.DIRS.find(d))
	map.draw_texture_rect_region(tex, _cell_rect(c), Rect2(idx * CELL, 0, CELL, CELL), tint)
	return true

func _deer_kind(i: int) -> String:
	if h.is_fawn(i):
		return "fawn"
	return "elk" if str(h.herd[i].get("species", "deer")) == "elk" else "deer"

func _draw_map() -> void:
	for y in h.height:
		for x in h.width:
			_draw_tile(Vector2i(x, y))
	# 鹿的目的地（沒察覺時）
	if h.deer_state == "unaware":
		map.draw_rect(_cell_rect(h.deer_goal()).grow(-3), COLORS["goal"], false, 1.0)
	if not h.done:
		var reach: Dictionary = h.reachable()
		for c in reach.keys():
			map.draw_rect(_cell_rect(c), COLORS[reach[c]])
		for c in h.pounce_targets().keys():
			map.draw_rect(_cell_rect(c).grow(-1), COLORS["target"], false, 2.0)
		if lock_armed:
			for c in h.front_lock_targets().keys():
				map.draw_rect(_cell_rect(c).grow(-2), Color("#c080ff"), false, 2.0)
	# 鹿群：母子之間的細線（跑散了就不畫）、其他的鹿（幼鹿小一號）
	for i in h.active_deer():
		var m: int = int(h.herd[i]["mother"])
		if m >= 0 and not bool(h.herd[m]["gone"]) and not bool(h.herd[i]["separated"]):
			map.draw_line(Vector2(h.herd[i]["pos"]) * CELL + Vector2(CELL, CELL) * 0.5, Vector2(h.herd[m]["pos"]) * CELL + Vector2(CELL, CELL) * 0.5, COLORS["bond"], 1.0)
	for i in h.active_deer():
		if i == h.target:
			continue
		if not _draw_animal(_deer_kind(i), h.herd[i]["pos"], h.herd[i]["facing"]):
			var r := _cell_rect(h.herd[i]["pos"]).grow(-3 if h.is_fawn(i) else -1)
			map.draw_rect(r, COLORS["fawn"] if h.is_fawn(i) else COLORS["deer"])
			var oc: Vector2 = Vector2(h.herd[i]["pos"]) * CELL + Vector2(CELL, CELL) * 0.5
			map.draw_line(oc, oc + Vector2(h.herd[i]["facing"]) * CELL * 0.5, Color(1, 1, 1, 0.7), 1.0)
	# 目標：方塊＋面向；逃跑時畫意圖的方向
	var dc: Vector2 = Vector2(h.deer_pos) * CELL + Vector2(CELL, CELL) * 0.5
	var fawn_t: bool = h.is_fawn(h.target)
	# 意圖線先畫，鹿畫在上面
	if not h.done and not h.held:
		for d in h.deer_intent():
			map.draw_line(dc, dc + Vector2(d).normalized() * CELL * h._flee_budget(), COLORS["intent"], 1.0)
	if not _draw_animal(_deer_kind(h.target), h.deer_pos, h.deer_facing, Color(1.0, 0.55, 0.5) if h.held else Color.WHITE):
		map.draw_rect(_cell_rect(h.deer_pos).grow(-3 if fawn_t else -1), COLORS["deer_held"] if h.held else (COLORS["fawn"] if fawn_t else COLORS["deer"]))
		map.draw_line(dc, dc + Vector2(h.deer_facing) * CELL * 0.6, Color.WHITE, 2.0)
	if h.herd.size() > 1:
		map.draw_rect(_cell_rect(h.deer_pos), COLORS["picked"], false, 1.0)
	# 狼
	# 狼的面向：上一步移動的方向；沒動過時朝向鹿
	if h.wolf_pos != last_wolf_pos:
		var mv: Vector2i = h.wolf_pos - last_wolf_pos
		wolf_facing = mv if last_wolf_pos.x > -99 and mv != Vector2i.ZERO else h.deer_pos - h.wolf_pos
		last_wolf_pos = h.wolf_pos
	if not _draw_animal("wolf", h.wolf_pos, wolf_facing):
		var wc: Vector2 = Vector2(h.wolf_pos) * CELL + Vector2(CELL, CELL) * 0.5
		map.draw_circle(wc, CELL * 0.42, COLORS["wolf"])
	if hover.x >= 0:
		map.draw_rect(_cell_rect(hover), Color(1, 1, 1, 0.6), false, 1.0)
