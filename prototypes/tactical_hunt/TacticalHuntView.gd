extends Control

# 戰術狩獵原型的畫面（docs/proposals/tactical-hunt-prototype.md 第九節，畫面甲：整張地圖）。
# 邏輯全在 TacticalHunt.gd；這裡只畫格子、處理點選、顯示資訊。主遊戲看得到的文字用翻譯鍵（tactical.*，Phase 2c 第 4 步）；
# 只有原型的設定列（情境、狼、體力、招式、新局、重來、返回）與給開發看的數字直接寫中文。
#
# 操作：點綠／黃／橘的格子移動（潛行／小跑／衝刺），點紅框的格子撲上去咬；咬住之後用下方的按鈕。
# 鹿群版（E～H，docs/proposals/tactical-hunt-herd.md）：點一隻鹿設為目標（黃框）；幼鹿是有白點的小鹿，細線連到生母。
# 動物與地塊用 data/art.json 的 tactical（Phase 2c，程式畫的佔位圖，tools/make_tactical_art.py）；沒有圖時退回色塊。
# 苔原狼同伴（群體狩獵實驗，docs/proposals/tundra-joint-tactical.md）：設定列選同伴；K～N 是用主遊戲地圖的群體狩獵情境。
# 同伴畫成偏淡的狼，角落的點是角色（藍：驅趕、橘：追擊），虛線指向牠要去的地方；滑鼠停在同伴上看牠在做什麼。

const TH := preload("res://scripts/core/TacticalHunt.gd")
const CELL := 14
const MAP_ORIGIN := Vector2(4, 4)
const COLORS := {
	".": Color("#5f7a3a"), "f": Color("#2d4a2a"), "l": Color("#6b4f33"), "r": Color("#8a877e"), "w": Color("#3f6478"), "s": Color("#5f8f8a"), "d": Color("#1f3f5c"), "c": Color("#55524c"), "b": Color("#1a140e"),
	"creep": Color(0.45, 0.9, 0.45, 0.35), "trot": Color(0.95, 0.85, 0.3, 0.35), "sprint": Color(1.0, 0.55, 0.2, 0.35),
	"wolf": Color("#c9c9c9"), "deer": Color("#b07a44"), "deer_held": Color("#d04a3a"), "intent": Color(1, 1, 1, 0.75),
	"target": Color("#ff4040"), "goal": Color(0.7, 0.9, 1.0, 0.5),
	"fawn": Color("#d9a76a"), "picked": Color("#ffe060"), "bond": Color(1, 1, 1, 0.35),
}
const SCENARIOS := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]
const WOLVES := {"slow": "慢（速度 40）", "normal": "普通（60）", "fast": "快（85）"}
# 群體狩獵實驗的情境：主遊戲的地圖（每局隨機），秋季
const EXTRA := [
	{"name": "K 馴鹿群、苔原", "family": "tundra", "species": "caribou", "herd": 6, "condition": "average"},
	{"name": "L 白尾鹿群、空地", "family": "open", "species": "deer", "herd": 4, "condition": "average"},
	{"name": "M 健康駝鹿、密林", "family": "dense", "species": "moose", "herd": 1, "condition": "healthy"},
	{"name": "N 虛弱駝鹿、密林", "family": "dense", "species": "moose", "herd": 1, "condition": "weak"},
]
const ALLIES := [[], ["drive", "chase"], ["drive"], ["chase"]]
const ALLY_COLORS := {"drive": Color("#7fc8ff"), "chase": Color("#ffb060")}

var h = TH.new()
var map: Control
var info: RichTextLabel
var hover_box: RichTextLabel
# 撲咬的機率與所有因素（2026-10-22 試玩回報：右下角的小框放不下，因素被截掉）：滑鼠停在可以撲的格子時，蓋在下方紀錄上
var detail_panel: PanelContainer
var detail_box: RichTextLabel
var log_box: RichTextLabel
var buttons: HFlowContainer
var scenario_pick: OptionButton
var wolf_pick: OptionButton
var stamina_pick: OptionButton
var special_pick: OptionButton # 會不會前截鎖喉（特殊招式，2026-10-16）
var ally_pick: OptionButton # 苔原狼同伴（群體狩獵實驗）
var ally_last := {} # 同伴的編號 -> [上一個位置, 面向]
var lock_armed: bool = false # 按了「前截鎖喉」，下一次點紫框就出手
var hover := Vector2i(-1, -1)
var game_seed: int = 0
var lines: Array[String] = []
# 動物與地塊的圖（Phase 2c，data/art.json 的 tactical；程式畫的佔位圖）
var art_sprites := {}
var art_tiles := {}
var wolf_facing := Vector2i(1, 0)
# 從主遊戲開的戰術狩獵（Phase 2c 第 2 步）：沒有設定列，結束時按「繼續」交回主遊戲
var game_mode: bool = false
var on_done: Callable
var setup_row: HBoxContainer
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
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.theme_type_variation = &"SmallRichLabel"
	add_child(info)
	# 下方：設定列、紀錄、按鈕
	setup_row = HBoxContainer.new()
	setup_row.position = Vector2(4, 232)
	setup_row.add_theme_constant_override("separation", 4)
	add_child(setup_row)
	scenario_pick = _option(setup_row, SCENARIOS.map(func(s): return s + " " + str(h.t["scenarios"][s]["name"])) + EXTRA.map(func(e): return e["name"]), 104)
	wolf_pick = _option(setup_row, WOLVES.values(), 76)
	wolf_pick.selected = 1
	stamina_pick = _option(setup_row, ["體力滿", "體力一半"], 62)
	special_pick = _option(setup_row, ["無招式", "鎖喉"], 58)
	ally_pick = _option(setup_row, ["無同伴", "苔原狼 2", "驅趕 1", "追擊 1"], 66)
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
	# 只是顯示用：不攔滑鼠（2026-10-24 試玩回報：咬住時招式灰掉、按鈕擠成三排，最下面的「鬆口」「交給本能」被它蓋住，按了沒反應）
	hover_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_box.theme_type_variation = &"SmallRichLabel"
	add_child(hover_box)
	detail_panel = PanelContainer.new()
	detail_panel.position = Vector2(4, 262)
	detail_panel.size = Vector2(400, 94)
	detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dbg := StyleBoxFlat.new()
	dbg.bg_color = Color(0.1, 0.1, 0.09, 1.0)
	dbg.border_color = Color("#ff8080")
	dbg.set_border_width_all(1)
	dbg.set_content_margin_all(4)
	detail_panel.add_theme_stylebox_override("panel", dbg)
	detail_panel.visible = false
	add_child(detail_panel)
	detail_box = RichTextLabel.new()
	detail_box.bbcode_enabled = true
	detail_box.scroll_active = false
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_box.theme_type_variation = &"SmallRichLabel"
	detail_panel.add_child(detail_box)
	_new_hunt(true)

# 主遊戲用：換成主遊戲開好的這一場（GameState.start_tactical），結束時呼叫 done_cb(th)
func start_from_game(th, done_cb: Callable) -> void:
	game_mode = true
	on_done = done_cb
	setup_row.visible = false
	h = th
	last_wolf_pos = Vector2i(-99, -99)
	lock_armed = false
	lines = [tr("tactical.ui.intro")]
	if bool(h.game_mods.get("youth_hint", false)):
		lines.append("[color=#e0c070]%s[/color]" % tr("tactical.ui.youth_hint"))
	# 苔原狼一起狩獵（Phase 2i）：一行說明牠們會做什麼（跟上來的也先說）
	if h.wolves.size() > 1 or not h.pending_allies.is_empty():
		lines.append("[color=#a0c8e8]%s[/color]" % tr("tactical.ui.ally_intro"))
	_after_action()

# width：選單的寬度（設定列放不下時文字截斷，展開的清單照舊完整；群體狩獵實驗多一個選單後，2026-10-22）
func _option(parent: Node, items: Array, width: float = 0.0) -> OptionButton:
	var o := OptionButton.new()
	o.theme_type_variation = &"SmallButton"
	if width > 0.0:
		o.fit_to_longest_item = false
		o.clip_text = true
		o.custom_minimum_size.x = width
	for it in items:
		o.add_item(str(it))
	parent.add_child(o)
	return o

func _new_hunt(new_seed: bool) -> void:
	if new_seed or game_seed == 0:
		game_seed = randi() % 100000 + 1
	var stamina_mult: float = 1.0 if stamina_pick.selected == 0 else 0.5
	var sc_name: String
	if scenario_pick.selected < SCENARIOS.size():
		h.setup(SCENARIOS[scenario_pick.selected], WOLVES.keys()[wolf_pick.selected], game_seed, stamina_mult)
		sc_name = str(h.t["scenarios"][h.scenario_id]["name"])
	else:
		var e: Dictionary = EXTRA[scenario_pick.selected - SCENARIOS.size()]
		var w: Dictionary = (h.t["wolves"][WOLVES.keys()[wolf_pick.selected]] as Dictionary).duplicate()
		w["stamina"] = float(w["stamina"]) * stamina_mult
		w["health"] = 100.0
		w["health_max"] = 100.0
		var ctx := {"family": e["family"], "seed": game_seed, "condition": e["condition"], "wolf": w, "species": e["species"], "season": "autumn",
			"wind_relation": ["headwind", "crosswind", "tailwind"][game_seed % 3]}
		if int(e["herd"]) > 1:
			var conds: Array = []
			for i in int(e["herd"]):
				conds.append(e["condition"])
			ctx["herd"] = {"conditions": conds, "calves": 0}
		h.setup_from_game(ctx)
		sc_name = str(e["name"]).substr(2)
	for role in ALLIES[ally_pick.selected]:
		h.add_ally(role, h.wolf_pos)
	ally_last = {}
	last_wolf_pos = Vector2i(-99, -99)
	h.knows_front_lock = special_pick.selected == 1
	lock_armed = false
	lines = ["情境 %s，種子 %d。點綠／黃／橘色的格子移動（潛行／小跑／衝刺），點紅框撲上去咬。" % [sc_name, game_seed]]
	if h.wolves.size() > 1:
		lines.append("苔原狼同伴：藍點的驅趕會繞到獵物另一側，你離獵物 7 格內就衝過去把牠往你這邊趕（你藏著不動或潛行時撲有埋伏加成）；橘點的追擊跟在你後面，獵物跑了就追。牠們咬住獵物時你撲上去更容易；你咬住時牠們會圍過來。")
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
		var what: String = tr("tactical.ui.result." + h.result)
		if game_mode:
			# 主遊戲：時間、體力、殘骸由主遊戲結算，這裡只交代結果
			lines.append("[color=%s]%s[/color]" % [color, tr("tactical.ui.result_line").replace("{result}", what).replace("{n}", str(h.rounds))])
		else:
			# 原型：多列給開發看的數字
			if h.result == "caught" and (h.herd.size() > 1 or not h.sp(h.target).is_empty()):
				what += "%s（%d 段肉）" % [h.label(h.target), h.meat]
			lines.append("[color=%s]結果：%s（%d 回合，用掉的喘 %d、受傷 %d；換算遊戲時間 %d 回合、體力 −%d）[/color]" % [color, what,
				h.rounds, roundi(h.breath_used), roundi(h.damage_taken), h.game_turns(), roundi(h.stamina_cost())])
	log_box.text = "\n".join(lines.slice(maxi(0, lines.size() - 30)))
	_build_buttons()
	_refresh()

func _build_buttons() -> void:
	for c in buttons.get_children():
		c.queue_free()
	if h.done:
		if game_mode:
			var cont := Button.new()
			cont.theme_type_variation = &"SmallButton"
			cont.text = tr("ui.continue")
			cont.pressed.connect(func():
				var cb := on_done
				queue_free()
				cb.call(h))
			buttons.add_child(cont)
		return
	if h.held:
		var names := {"takedown": tr("tactical.ui.takedown"), "throat": tr("tactical.ui.throat"), "hang": tr("tactical.ui.hang"), "hamstring": tr("tactical.ui.hamstring"), "release": tr("tactical.ui.release")}
		var opts: Dictionary = h.hold_options()
		for id in ["takedown", "throat", "hamstring", "hang", "release"]:
			# 喘不夠的招式照樣列出、灰掉，寫出要多少喘
			if h.hold_short.has(id):
				var sb := Button.new()
				sb.theme_type_variation = &"SmallButton"
				sb.text = names[id] + tr("tactical.ui.no_breath")
				sb.disabled = true
				sb.tooltip_text = tr("tactical.ui.no_breath_tip").replace("{n}", str(roundi(float(h.hold_short[id]["breath"])))).replace("{have}", str(floori(h.breath)))
				buttons.add_child(sb)
			elif opts.has(id):
				var b := Button.new()
				b.theme_type_variation = &"SmallButton"
				b.text = names[id] + ("" if id in ["release", "hang"] else " %d%%" % roundi(float(opts[id]["chance"]) * 100.0))
				var cost: String = tr("tactical.ui.breath_cost").replace("{n}", str(snappedf(float(opts[id]["breath"]), 0.1)))
				var allies_help: bool = id == "hang" and opts[id].has("ally_takedown_any")
				# 死咬拖住寫喘；旁邊有苔原狼時改寫牠們拖倒的機率（按鈕放不下兩個，喘寫在滑鼠提示）
				if id == "hang" and not allies_help:
					b.text += cost
				b.tooltip_text = "、".join((opts[id]["factors"] as Array).map(func(f): return "%s %+d%%" % [f[0], roundi(float(f[1]) * 100.0)]))
				# 有苔原狼同伴時滑鼠提示寫喘（一起咬著時省喘）
				if h.wolves.size() > 1 and id != "release":
					b.tooltip_text = cost + " " + b.tooltip_text
				if allies_help:
					var pa: String = str(roundi(float(opts[id]["ally_takedown_any"]) * 100.0))
					b.text += tr("tactical.ui.ally_takedown").replace("{p}", pa)
					b.tooltip_text = tr("tactical.ui.ally_takedown_tip").replace("{n}", str((opts[id]["ally_takedown"] as Array).size())).replace("{p}", pa) + "\n" + b.tooltip_text
				var a: String = id
				b.pressed.connect(func(): h.hold_action(a); _after_action())
				buttons.add_child(b)
		var auto_h := Button.new()
		auto_h.theme_type_variation = &"SmallButton"
		auto_h.text = tr("tactical.ui.instinct")
		auto_h.pressed.connect(func(): TacticalInstinct.play(h); _after_action())
		buttons.add_child(auto_h)
		return
	if h.knows_front_lock:
		var fl := Button.new()
		fl.theme_type_variation = &"SmallButton"
		fl.toggle_mode = true
		fl.button_pressed = lock_armed
		var ready: bool = not h.front_lock_targets().is_empty()
		fl.disabled = not ready
		fl.text = tr("tactical.ui.front_lock") if h.front_lock_ready() else tr("tactical.ui.front_lock_weak")
		fl.tooltip_text = tr("tactical.ui.front_lock_tip")
		fl.toggled.connect(func(on): lock_armed = on; _refresh())
		buttons.add_child(fl)
	# 苔原狼咬住、你還沒咬住（群體狩獵實驗）：壓倒、咬喉要你先撲上去咬住才有（2026-10-22 試玩回報：看起來像咬住了，招式卻不見）
	# 喘不夠連撲都撲不了：同樣寫出來（不然紅框直接不見）
	var short_pounce: bool = h.breath < -float(h.t["move"]["breath_pounce"]) and h._cheb(h.wolf_pos, h.deer_pos) <= 2
	if h._ally_holding() > 0 or short_pounce:
		var hint := Button.new()
		hint.theme_type_variation = &"SmallButton"
		hint.text = tr("tactical.ui.no_breath_pounce") if short_pounce else tr("tactical.ui.ally_held_hint")
		hint.disabled = true
		hint.tooltip_text = tr("tactical.ui.no_breath_pounce_tip").replace("{n}", str(roundi(-float(h.t["move"]["breath_pounce"])))).replace("{have}", str(floori(h.breath))) \
			if short_pounce else tr("tactical.ui.ally_held_tip")
		buttons.add_child(hint)
	var obs := Button.new()
	obs.theme_type_variation = &"SmallButton"
	obs.text = tr("tactical.ui.observe")
	obs.pressed.connect(func(): h.observe(); _after_action())
	buttons.add_child(obs)
	# 交給本能（Phase 2c 第 3 步）：照同一套規則，依局面挑一種打法打完這一場
	var auto := Button.new()
	auto.theme_type_variation = &"SmallButton"
	auto.text = tr("tactical.ui.instinct")
	auto.tooltip_text = tr("tactical.ui.instinct_tip")
	auto.pressed.connect(func(): TacticalInstinct.play(h); _after_action())
	buttons.add_child(auto)
	var quit := Button.new()
	quit.theme_type_variation = &"SmallButton"
	quit.text = tr("tactical.ui.give_up")
	quit.pressed.connect(func(): h.give_up(); _after_action())
	buttons.add_child(quit)

func _refresh() -> void:
	map.queue_redraw()
	info.text = _info_text()
	# 撲咬、前截鎖喉的機率有一長串因素：放在下方的大框；移動方式之類的短句照舊放右下角
	var ht: String = _hover_text()
	var long: bool = ht.contains("\n")
	detail_panel.visible = long
	log_box.visible = not long
	detail_box.text = ht if long else ""
	hover_box.text = "" if long else (ht if ht != "" else _ally_text())

# --- 右側資訊 ---

func _bar(v: float, mx: float, color: String) -> String:
	var n: int = clampi(roundi(v / max(1.0, mx) * 6.0), 0, 6)
	return "[color=%s]%s[/color][color=#444]%s[/color]" % [color, "█".repeat(n), "█".repeat(6 - n)]

func _info_text() -> String:
	var t: Array[String] = []
	t.append(tr("tactical.ui.round").replace("{n}", str(h.rounds)))
	t.append(tr("tactical.ui.wind").replace("{dir}", {Vector2i(1, 0): "→", Vector2i(-1, 0): "←", Vector2i(0, 1): "↓", Vector2i(0, -1): "↑"}.get(h.wind, "?")))
	t.append({"upwind": "[color=#e08a8a]%s[/color]", "downwind": "[color=#9fe08a]%s[/color]", "crosswind": "%s"}[h.wind_side()] % tr("tactical.ui.wind_side." + h.wind_side()))
	t.append("")
	t.append(tr("tactical.ui.breath").replace("{n}", str(roundi(h.breath))).replace("{max}", str(roundi(h.breath_max))))
	t.append(_bar(h.breath, h.breath_max, "#7fb3e0"))
	t.append(tr("tactical.ui.health").replace("{n}", str(roundi(float(h.wolf["health"])))))
	t.append("")
	if h.herd.size() > 1:
		t.append(tr("tactical.ui.target").replace("{animal}", h.label()))
		t.append(tr("tactical.ui.herd_count").replace("{n}", str(h.active_deer().size())))
	# 單隻時前面寫是什麼動物（原本一律寫「鹿：」，河狸、駝鹿也是，2026-10-22）
	var prefix: String = ""
	if h.herd.size() <= 1:
		var nk: String = str(h.sp().get("name_key", ""))
		prefix = tr("tactical.ui.animal_prefix").replace("{animal}", tr(nk)) if nk != "" else tr("tactical.ui.deer_prefix")
	t.append(prefix + tr("tactical.ui.state." + h.deer_state) + (tr("tactical.ui.held") if h.held else (tr("tactical.ui.ally_held") if h._ally_holding() > 0 else "")))
	if h.held:
		t.append(tr("tactical.ui.hold_at." + h.hold_side))
	if int(h.herd[h.target].get("hamstrung", 0)) > 0:
		t.append("[color=#e08a8a]%s[/color]" % tr("tactical.factor.hamstrung"))
	if h.hidden_unfound():
		t.append("[color=#e0c070]%s[/color]" % tr("tactical.ui.hidden"))
	if h.deer_state in ["unaware", "suspicious"]:
		t.append(tr("tactical.ui.alert").replace("{n}", str(roundi(h.alert))))
		t.append(_bar(h.alert, 100.0, "#e0c070"))
	else:
		t.append(tr("tactical.ui.fatigue").replace("{n}", str(roundi(h.deer_fatigue_any() * 100.0))))
	if h.wounds > 0:
		t.append("[color=#e08a8a]%s[/color]" % tr("tactical.ui.wounds").replace("{n}", str(h.wounds)))
	if h.condition_known:
		t.append(tr("tactical.ui.condition").replace("{condition}", tr("tactical.condition." + h.condition)))
	return "\n".join(t)

# 苔原狼同伴（群體狩獵實驗）：角色與現在在做什麼，一行；被趕過來時第二行提示。右側資訊欄放不下，滑鼠沒停在格子上時寫在右下角
func _ally_text() -> String:
	if h.wolves.size() <= 1 or h.done or h.held: # 咬住時按鈕排三行，放不下（苔原狼拖倒的機率寫在死咬拖住上）
		return ""
	var parts: Array[String] = []
	for k in range(1, h.wolves.size()):
		var role: String = str(h.wolves[k]["role"])
		parts.append("[color=#%s]%s[/color]%s" % [ALLY_COLORS[role].to_html(false), tr("tactical.ally.role." + role), tr("tactical.ally.intent." + str(h.wolves[k].get("intent", "following")))])
	var out: String = "　".join(parts)
	if h._driven() and h.deer_state == "flee":
		out += "\n[color=#9fe08a]%s[/color]" % tr("tactical.factor.ambush")
	return out

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
			return "[color=#c080ff]%s[/color]\n" % tr("tactical.ui.front_lock_hover").replace("{p}", str(roundi(float(fp["chance"]) * 100.0))) + "、".join(parts0)
		return tr("tactical.ui.front_lock_pick")
	var targets: Dictionary = h.pounce_targets()
	if targets.has(hover):
		var p: Dictionary = targets[hover]
		var s := ("%s　" % h.label() if h.herd.size() > 1 else "") + "[color=#ff8080]%s[/color]" % tr("tactical.ui.pounce").replace("{p}", str(roundi(float(p["chance"]) * 100.0)))
		var parts: Array[String] = []
		for f in p["factors"]:
			if absf(float(f[1])) >= 0.005:
				parts.append("%s %+d" % [f[0], roundi(float(f[1]) * 100.0)])
		s += tr("tactical.ui.kick_risk").replace("{p}", str(roundi(float(p["kick"]) * 100.0))) if float(p["kick"]) > 0.0 else ""
		s += "\n" + "、".join(parts)
		return s
	# 滑鼠停在苔原狼同伴上：牠在做什麼（群體狩獵實驗）
	for k in range(1, h.wolves.size()):
		if Vector2i(h.wolves[k]["pos"]) == hover:
			return tr("tactical.ally.tip").replace("{role}", tr("tactical.ally.name." + str(h.wolves[k]["role"]))) \
				.replace("{what}", tr("tactical.ally.intent_tip." + str(h.wolves[k].get("intent", "following"))))
	# 滑鼠停在一隻鹿上：寫出牠是誰（母鹿、幼鹿分得出來，2026-10-22 試玩回報）
	for i in h.active_deer():
		if Vector2i(h.herd[i]["pos"]) == hover and h.herd.size() > 1:
			return h.label(i) + ("（" + tr("tactical.ui.target_mark") + "）" if i == h.target else "")
	var r: Dictionary = h.reachable()
	if r.has(hover):
		if r[hover] == "trot" and h.tired():
			return tr("tactical.ui.move.tired_trot")
		return tr("tactical.ui.move." + str(r[hover]))
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
# small：幼獸畫小一號（格子的 0.8，置中），和母親一眼分得出來（2026-10-22 試玩回報）
func _draw_animal(kind: String, c: Vector2i, facing: Vector2i, tint: Color = Color.WHITE, small: bool = false) -> bool:
	var tex: Texture2D = art_sprites.get(kind, null)
	if tex == null:
		return false
	var d := Vector2i(signi(facing.x), signi(facing.y))
	var idx: int = maxi(0, TH.DIRS.find(d))
	var r := _cell_rect(c)
	if small:
		r = r.grow(-CELL * 0.1)
	map.draw_texture_rect_region(tex, r, Rect2(idx * CELL, 0, CELL, CELL), tint)
	return true

func _deer_kind(i: int) -> String:
	# 幼鹿有自己的圖就用（小駝鹿，Phase 2f 第 2 步），沒有就用共用的小鹿圖
	var sp: String = str(h.herd[i].get("species", "deer"))
	if h.is_fawn(i):
		return sp if art_sprites.has(sp) else "fawn"
	# 冬季換毛的動物有冬季的圖（雪兔變白，2026-10-22）
	if str(h.game_mods.get("season", "")) == "winter" and art_sprites.has(sp + "_winter"):
		return sp + "_winter"
	return sp if art_sprites.has(sp) else "deer"

func _draw_map() -> void:
	for y in h.height:
		for x in h.width:
			_draw_tile(Vector2i(x, y))
	# 鹿的目的地（沒察覺時）
	var hid: bool = h.hidden_unfound()
	if h.deer_state == "unaware" and not hid:
		map.draw_rect(_cell_rect(h.deer_goal()).grow(-3), COLORS["goal"], false, 1.0)
	# 躲在草裡、還沒找到（Phase 2i 第 6 步）：只畫大概在哪的範圍
	if hid:
		map.draw_rect(Rect2(Vector2(h.hidden_area.position) * CELL, Vector2(h.hidden_area.size) * CELL).grow(-1), Color("#e0c070"), false, 1.5)
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
		if not _draw_animal(_deer_kind(i), h.herd[i]["pos"], h.herd[i]["facing"], Color.WHITE, h.is_fawn(i)):
			var r := _cell_rect(h.herd[i]["pos"]).grow(-3 if h.is_fawn(i) else -1)
			map.draw_rect(r, COLORS["fawn"] if h.is_fawn(i) else COLORS["deer"])
			var oc: Vector2 = Vector2(h.herd[i]["pos"]) * CELL + Vector2(CELL, CELL) * 0.5
			map.draw_line(oc, oc + Vector2(h.herd[i]["facing"]) * CELL * 0.5, Color(1, 1, 1, 0.7), 1.0)
	# 目標：方塊＋面向；逃跑時畫意圖的方向
	var dc: Vector2 = Vector2(h.deer_pos) * CELL + Vector2(CELL, CELL) * 0.5
	var fawn_t: bool = h.is_fawn(h.target)
	# 意圖線先畫，鹿畫在上面
	if not h.done and not h.held and not hid:
		for d in h.deer_intent():
			map.draw_line(dc, dc + Vector2(d).normalized() * CELL * h._flee_budget(), COLORS["intent"], 1.0)
	if hid:
		pass
	elif not _draw_animal(_deer_kind(h.target), h.deer_pos, h.deer_facing, Color(1.0, 0.55, 0.5) if h.held else Color.WHITE, fawn_t):
		map.draw_rect(_cell_rect(h.deer_pos).grow(-3 if fawn_t else -1), COLORS["deer_held"] if h.held else (COLORS["fawn"] if fawn_t else COLORS["deer"]))
		map.draw_line(dc, dc + Vector2(h.deer_facing) * CELL * 0.6, Color.WHITE, 2.0)
	if h.herd.size() > 1:
		map.draw_rect(_cell_rect(h.deer_pos), COLORS["picked"], false, 1.0)
	# 觀察後看出的最弱的那一隻（Phase 2d 第 2 步）：格子左上角的橘點
	for i in h.active_deer():
		if bool(h.herd[i].get("weakest", false)):
			map.draw_circle(Vector2(h.herd[i]["pos"]) * CELL + Vector2(3, 3), 2.5, Color("#ff8a3d"))
	# 狼
	# 狼的面向：上一步移動的方向；沒動過時朝向鹿
	if h.wolf_pos != last_wolf_pos:
		var mv: Vector2i = h.wolf_pos - last_wolf_pos
		wolf_facing = mv if last_wolf_pos.x > -99 and mv != Vector2i.ZERO else (h.hidden_area.get_center() if hid else h.deer_pos) - h.wolf_pos
		last_wolf_pos = h.wolf_pos
	if not _draw_animal("wolf", h.wolf_pos, wolf_facing):
		var wc: Vector2 = Vector2(h.wolf_pos) * CELL + Vector2(CELL, CELL) * 0.5
		map.draw_circle(wc, CELL * 0.42, COLORS["wolf"])
	_draw_allies()
	if hover.x >= 0:
		map.draw_rect(_cell_rect(hover), Color(1, 1, 1, 0.6), false, 1.0)

# 苔原狼同伴（群體狩獵實驗）：偏淡的狼、角落的角色點、指向要去的地方的虛線；咬住獵物時獵物外圈紅框
func _draw_allies() -> void:
	for k in range(1, h.wolves.size()):
		var w: Dictionary = h.wolves[k]
		var pos: Vector2i = w["pos"]
		var role: String = str(w["role"])
		var col: Color = ALLY_COLORS.get(role, Color.WHITE)
		var last: Array = ally_last.get(k, [Vector2i(-99, -99), h.deer_pos - pos])
		if pos != last[0]:
			last = [pos, (pos - Vector2i(last[0])) if Vector2i(last[0]).x > -99 else h.deer_pos - pos]
			ally_last[k] = last
		var center: Vector2 = Vector2(pos) * CELL + Vector2(CELL, CELL) * 0.5
		if not h.done:
			var aim0: Vector2i = w.get("aim", pos)
			var aim := Vector2i(clampi(aim0.x, 0, h.width - 1), clampi(aim0.y, 0, h.height - 1)) # 預測的位置可能在地圖外
			if aim != pos:
				map.draw_dashed_line(center, Vector2(aim) * CELL + Vector2(CELL, CELL) * 0.5, Color(col, 0.7), 1.0, 3.0)
		if not _draw_animal("wolf", pos, last[1], Color(0.85, 0.92, 1.0)):
			map.draw_circle(center, CELL * 0.38, Color("#e0e6ee"))
		map.draw_circle(Vector2(pos) * CELL + Vector2(CELL - 3, 3), 2.5, col)
		if str(w.get("intent", "")) == "holding":
			map.draw_rect(_cell_rect(h.deer_pos).grow(1), Color("#ff6050"), false, 1.5)
