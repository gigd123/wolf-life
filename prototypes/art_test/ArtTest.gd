extends Control

# 美術測試場景（2026-10-13）：和遊戲程式、存檔無關，只用來比較兩種美術風格在遊戲畫面裡的樣子。
# 右上角可以即時切換「插畫／像素」與背景；下方是和遊戲一樣的文字與選項。
# 素材：assets/art/art_test/（arts/art_illustrated_test_2026-10-13/export_game.py 產生）。
# 像素版還沒有的動物用遊戲現有的像素圖頂替，畫面左上角會註明。
# 這是原型，文字直接寫在這裡，不走翻譯鍵（同 prototypes/visual_test）。

const ArtSprite := preload("res://prototypes/art_test/ArtSprite.gd")
const MANIFEST := "res://assets/art/art_test/manifest.json"
const GROUND_Y := 226.0
const WOLF_H := 64.0          # 灰狼在畫面上的高度（邏輯像素，640×360）；像素版的灰狼本體正好 64，整數倍率 1
const NAMES := {"hare": "雪兔", "elk_cow": "母馬鹿", "grizzly": "灰熊", "wolf_black": "黑狼", "wolf_gray": "灰狼"}
# 像素版沒有素材時，用遊戲裡的哪一隻頂替
const FALLBACK := {"wolf_gray": "", "wolf_black": "stranger_wolf", "grizzly": "grizzly_bear", "elk_cow": "elk", "hare": "snowshoe_hare"}
# shift：背景往上移多少（邏輯像素），讓圖裡的地面落在文字面板上方、動物腳下（下方面板蓋住的是圖的最底部）
const BACKGROUNDS := {
	"illus": {"meadow": {"path": "res://assets/art/art_test/illus/bg_meadow.jpg", "shift": 126},
		"forest": {"path": "res://assets/art/art_test/illus/bg_forest.jpg", "shift": 122}},
	"pixel": {"meadow": {"path": "res://assets/art/backgrounds/terrain/forest_edge.png", "shift": 72},
		"forest": {"path": "res://assets/art/backgrounds/terrain/dense_forest.png", "shift": 72}},
	# 主視覺（黃昏斜角像素場景，arts/art_scene_test_2026-10-13/）：目前只有林內一張，林緣草地先共用
	"scene": {"meadow": {"path": "res://assets/art/art_test/scene/bg_forest.png", "shift": 56},
		"forest": {"path": "res://assets/art/art_test/scene/bg_forest.png", "shift": 56}},
}
const STYLES := ["illus", "pixel", "scene"]
const STYLE_NAMES := {"illus": "插畫", "pixel": "像素", "scene": "場景"}

var manifest: Dictionary = {}
var style: String = "illus"
var bg_key: String = "meadow"
var scenario: String = ""
var rounds: int = 0
# 每開始一個情境（或切換風格重來）加一；等待結束後世代不同就不再繼續，避免舊的流程蓋掉新的
var gen: int = 0
var walk_tween: Tween

var bg: TextureRect
var world: Node2D
var wolf: Node2D
var other: Node2D
var other_id: String = ""
var message: Label
var buttons: HFlowContainer
var note: Label
var style_btn: Button
var bg_btn: Button


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f != null:
		manifest = JSON.parse_string(f.get_as_text())
	bg = TextureRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	world = Node2D.new()
	add_child(world)
	wolf = ArtSprite.new()
	world.add_child(wolf)
	other = ArtSprite.new()
	world.add_child(other)
	_build_ui()
	_apply_style()
	_menu()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.05, 0.06, 0.05, 0.84)
	style_box.content_margin_left = 10
	style_box.content_margin_right = 10
	style_box.content_margin_top = 6
	style_box.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style_box)
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -122
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(600, 40)
	box.add_child(message)
	buttons = HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 4)
	box.add_child(buttons)

	var top := HBoxContainer.new()
	top.anchor_left = 1.0
	top.anchor_right = 1.0
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.offset_right = -6
	top.offset_top = 4
	top.add_theme_constant_override("separation", 4)
	add_child(top)
	style_btn = _small_button("", _toggle_style)
	top.add_child(style_btn)
	bg_btn = _small_button("", _toggle_bg)
	top.add_child(bg_btn)
	top.add_child(_small_button("回開始畫面", func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))

	note = Label.new()
	note.position = Vector2(8, 6)
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	note.add_theme_constant_override("outline_size", 3)
	add_child(note)


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


# ---------------- 風格與背景 ----------------
func _entry(id: String) -> Dictionary:
	return manifest.get(style, {}).get(id, {})


func _setup_sprite(s: Node2D, id: String) -> void:
	var rel: float = float(manifest.get("illus", {}).get(id, {}).get("rel_height", 1.0))
	var e := _entry(id)
	s.fallback_base_zoom = maxf(1.0, round(WOLF_H / 30.0))
	s.setup(e, style != "illus", WOLF_H * rel, FALLBACK.get(id, ""), id == "wolf_gray")


func _apply_style() -> void:
	style_btn.text = "風格：" + STYLE_NAMES[style]
	bg_btn.text = "背景：" + ("林緣草地" if bg_key == "meadow" else "林內")
	var bg_info: Dictionary = BACKGROUNDS[style][bg_key]
	bg.texture = load(bg_info["path"])
	bg.offset_top = -float(bg_info["shift"])
	bg.offset_bottom = -float(bg_info["shift"])
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if style == "illus" else CanvasItem.TEXTURE_FILTER_NEAREST
	_setup_sprite(wolf, "wolf_gray")
	if other_id != "":
		_setup_sprite(other, other_id)
	var missing: Array = []
	for id in ["wolf_gray"] + ([other_id] if other_id != "" else []):
		if _entry(id).is_empty():
			missing.append(NAMES[id])
	var lines: Array = []
	if style == "pixel":
		lines.append("像素版：背景暫用遊戲現有的地形圖")
	elif style == "scene":
		lines.append("場景版（主視覺）：目前只有林內一張場景")
		if not missing.is_empty():
			lines.append("、".join(missing) + "還沒有新圖，暫用遊戲現有的像素圖")
	note.text = "\n".join(lines)


func _toggle_style() -> void:
	style = STYLES[(STYLES.find(style) + 1) % STYLES.size()]
	_apply_style()
	_restart()


func _toggle_bg() -> void:
	bg_key = "forest" if bg_key == "meadow" else "meadow"
	_apply_style()


func _restart() -> void:
	match scenario:
		"hunt":
			_hunt(other_id)
		"encounter":
			_encounter(other_id)
		"walk":
			_free_walk()
		_:
			_menu()


# ---------------- 小工具 ----------------
func _say(text: String, options: Array = []) -> void:
	message.text = text
	for c in buttons.get_children():
		c.queue_free()
	for o in options:
		var b := Button.new()
		b.text = o[0]
		b.pressed.connect(o[1])
		buttons.add_child(b)


func _place(s: Node2D, x: float, face_left: bool) -> void:
	s.position = Vector2(x, GROUND_Y)
	s.flip = face_left


func _move(s: Node2D, to_x: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(s, "position:x", to_x, dur)
	await tw.finished


func _new_gen() -> int:
	gen += 1
	if walk_tween != null:
		walk_tween.kill()
	return gen


func _play_once(s: Node2D, a: String) -> void:
	s.play(a)
	await s.finished


func _lunge(s: Node2D, dx: float, dur: float) -> void:
	var x0: float = s.position.x
	var tw := create_tween()
	tw.tween_property(s, "position:x", x0 + dx, dur * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur * 0.2)
	tw.tween_property(s, "position:x", x0, dur * 0.35)


func _show_other(id: String) -> void:
	other_id = id
	other.visible = id != ""
	if id != "":
		_setup_sprite(other, id)
	_apply_style()


# ---------------- 情境 ----------------
func _menu() -> void:
	_new_gen()
	scenario = ""
	_show_other("")
	_place(wolf, 300, false)
	wolf.play("idle")
	_say("美術測試：選一個情境。右上角可以切換風格與背景，切換後情境會重新開始。", [
		["狩獵雪兔", func(): _hunt("hare")],
		["狩獵母馬鹿", func(): _hunt("elk_cow")],
		["遇到灰熊", func(): _encounter("grizzly")],
		["遇到黑狼", func(): _encounter("wolf_black")],
		["自由走動", _free_walk],
	])


func _free_walk() -> void:
	var g := _new_gen()
	scenario = "walk"
	_show_other("")
	_place(wolf, 120, false)
	_say("灰狼在林間走動。", [["停下", _walk_stop], ["回選單", _menu]])
	while g == gen:
		for target in [520.0, 120.0]:
			wolf.flip = target < wolf.position.x
			wolf.play("walk")
			walk_tween = create_tween()
			walk_tween.tween_property(wolf, "position:x", target, 5.0)
			await walk_tween.finished
			if g != gen:
				return


func _walk_stop() -> void:
	_new_gen()
	scenario = "idle"
	wolf.play("idle")
	_say("灰狼停下來，站著觀察四周。", [["繼續走", _free_walk], ["回選單", _menu]])


func _hunt(prey: String) -> void:
	_new_gen()
	scenario = "hunt"
	_show_other(prey)
	_place(wolf, 120, false)
	_place(other, 430, false)
	wolf.play("idle")
	other.play("idle")
	var nm: String = NAMES[prey]
	_say("前方的草地上有一隻%s，正低頭吃東西，還沒發現你。" % nm, [["潛近", _hunt_stalk], ["回選單", _menu]])


func _hunt_stalk() -> void:
	var g := gen
	_say("你壓低身子，一步一步靠近……")
	wolf.play("walk", 0.55)
	await _move(wolf, 250, 2.4)
	if g != gen:
		return
	wolf.play("idle")
	_say("距離近了。牠的耳朵動了一下，抬起頭。", [["撲上去", _hunt_chase], ["伏低等一下", _hunt_wait], ["回選單", _menu]])


func _hunt_wait() -> void:
	_say("你伏在草裡一動也不動。牠又低下頭。", [["撲上去", _hunt_chase], ["回選單", _menu]])


func _hunt_chase() -> void:
	var g := gen
	_say("牠察覺了，拔腿就跑！你衝了出去。")
	var prey_run := "hop" if other.has_action("hop") else "walk"
	other.play(prey_run, 1.6)
	wolf.play("walk", 2.0)
	var prey_end := 560.0
	var gap: float = WOLF_H * 0.9 + other.target_h * 0.55
	_move(other, prey_end, 1.5)
	await _move(wolf, prey_end - gap, 1.5)
	if g != gen:
		return
	other.play("idle")
	_lunge(wolf, 18, wolf.duration("bite"))
	wolf.play("bite")
	await get_tree().create_timer(wolf.duration("bite") * 0.5).timeout
	if g != gen:
		return
	other.play("hurt")
	await wolf.finished
	if g != gen:
		return
	wolf.play("idle")
	_say("你追上去，一口咬住了牠。", [["再來一次", func(): _hunt(other_id)], ["回選單", _menu]])


func _encounter(id: String) -> void:
	var g := _new_gen()
	scenario = "encounter"
	rounds = 0
	_show_other(id)
	_place(wolf, 190, false)
	_place(other, 720, true)
	wolf.play("idle")
	other.play("walk")
	var text: String = "一頭灰熊從林子裡走出來" if id == "grizzly" else "一隻黑狼從林子裡走出來"
	_say(text + "……")
	await _move(other, 430, 2.6)
	if g != gen:
		return
	other.play("idle")
	_say(text + "，停下來盯著你。", _encounter_options())


func _encounter_options() -> Array:
	return [["撲咬", _encounter_bite], ["對峙", _encounter_stare], ["撤退", _encounter_retreat], ["回選單", _menu]]


func _encounter_bite() -> void:
	var g := gen
	rounds += 1
	_say("你撲了上去！")
	if not await _exchange(wolf, other, 34, g):
		return
	await get_tree().create_timer(0.25).timeout
	if g != gen or not await _exchange(other, wolf, -34, g):
		return
	var nm: String = NAMES[other_id]
	if rounds >= 2:
		_say("%s退開了，轉身走回林子裡。" % nm)
		other.flip = false
		other.play("walk")
		await _move(other, 720, 2.4)
		if g != gen:
			return
		_say("林子裡又安靜下來。", [["再來一次", func(): _encounter(other_id)], ["回選單", _menu]])
	else:
		_say("你咬中了牠，牠也回咬了你一口。", _encounter_options())


# 一次撲咬：attacker 往前撲、咬到一半 target 受傷；回傳 false 表示中途換了情境
func _exchange(attacker: Node2D, target: Node2D, dx: float, g: int) -> bool:
	_lunge(attacker, dx, attacker.duration("bite"))
	attacker.play("bite")
	await get_tree().create_timer(attacker.duration("bite") * 0.5).timeout
	if g != gen:
		return false
	target.play("hurt")
	await get_tree().create_timer(maxf(attacker.duration("bite") * 0.5, target.duration("hurt"))).timeout
	if g != gen:
		return false
	attacker.play("idle")
	target.play("idle")
	return true


func _encounter_stare() -> void:
	_say("你們對峙著，誰都沒有先動。", _encounter_options())


func _encounter_retreat() -> void:
	var g := gen
	_say("你轉身退開。")
	wolf.flip = true
	wolf.play("walk", 1.6)
	await _move(wolf, -60, 2.0)
	if g != gen:
		return
	_say("你離開了牠的視線。", [["再來一次", func(): _encounter(other_id)], ["回選單", _menu]])
