extends SceneTree
# UI 檢查（2026-10-13）：xvfb 下實際開遊戲，主選單、開局四張地圖，再從六個巢穴各隨機點按鈕玩一段
# （中途跳到成年、老年，每 15 步強制一次遭遇）。每一步掃描畫面上的文字與訊息：
#   RAWKEY 原始翻譯鍵、PLACEHOLDER 沒替換的 {佔位}、OFFSCREEN 超出 640×360 的文字元件、LABEL_SPILL 不換行的 Label 字超出框。
# 截圖存到 UI_CHECK_OUT（預設 /tmp/ui_check/）。用法見 tools/ui_check.sh。
var OUT: String = OS.get_environment("UI_CHECK_OUT") if OS.get_environment("UI_CHECK_OUT") != "" else "/tmp/ui_check/"
var STEPS: int = int(OS.get_environment("UI_CHECK_STEPS")) if OS.get_environment("UI_CHECK_STEPS") != "" else 400
var prefixes := {}
var key_re := RegEx.new()
var ph_re := RegEx.new()
var issues := {} # issue text -> first context
var shots := 0
var rng := RandomNumberGenerator.new()
var frame := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var f := FileAccess.open("res://localization/strings_zh_TW.csv", FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() > 0 and line[0].contains("."):
			prefixes[line[0].split(".")[0]] = true
	key_re.compile("(?<![\\w/:])([a-z][a-z0-9_]*)(\\.[a-z0-9_]+)+")
	ph_re.compile("\\{[a-z_]+\\}")
	rng.seed = int(OS.get_environment("UI_CHECK_SEED")) if OS.get_environment("UI_CHECK_SEED") != "" else 7
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var gs = root.get_node("GameState")
	var anim_mode: String = CombatAnimator.mode()
	gs.log_message.connect(func(m): _check_text(str(m), "log"))
	change_scene_to_file("res://scenes/MainMenu.tscn")
	await _wait(5)
	_scan(current_scene, "main_menu")
	_shot("main_menu")
	# 1. 開局畫面：每張地圖
	change_scene_to_file("res://scenes/DenSelect.tscn")
	await _wait(5)
	for map_id in ["forest", "tundra", "mountain", "grassland"]:
		var ds = current_scene
		ds._show_map(map_id)
		await _wait(4)
		_scan(current_scene, "den_select." + map_id)
		_shot("den_" + map_id)
	# 2. 各地圖玩一段
	for den in ["forest_east", "tundra_south", "mountain_canyon", "grassland_riverwoods", "mountain_foothills", "grassland_hills"]:
		gs.new_game(den)
		change_scene_to_file("res://scenes/Game.tscn")
		await _wait(6)
		_shot(den + "_start")
		await _play(den)
	CombatAnimator.set_mode(anim_mode)
	print("UI 檢查：問題 ", issues.size(), " 個，截圖 ", shots, " 張（", OUT, "）")
	for k in issues.keys():
		print("ISSUE ", k, "   @ ", issues[k])
	quit()

func _play(den: String) -> void:
	var gs = root.get_node("GameState")
	var animals: Array = gs.debug_animal_ids()
	var last_sig := ""
	for step in STEPS:
		if not (current_scene and current_scene.name == "Game"):
			await _wait(4)
			_scan(current_scene, den + ".end")
			_shot(den + "_end")
			return
		var game = current_scene
		if step == 90:
			gs.debug_force_transition("adult")
		if step == 180:
			gs.debug_add_age(5.0)
			gs.debug_force_transition("elder")
		# 每 15 步強制一次遭遇（所有獵物輪流）
		if step % 15 == 7 and _top_buttons(game).size() > 0 and _overlay_kind(game) == "main":
			var a: String = animals[(step / 15) % animals.size()]
			game._on_debug_force_encounter(a, "juvenile" if step % 30 == 7 else "adult")
			await _wait(3)
		var ctx := "%s step %d %s" % [den, step, _overlay_kind(game)]
		var found := _scan(game, ctx)
		var sig := _overlay_kind(game)
		if found or (sig != last_sig and shots < 400 and rng.randf() < 0.35) or step % 40 == 0:
			_shot("%s_%03d_%s" % [den, step, sig])
		last_sig = sig
		var btns := _top_buttons(game)
		if btns.is_empty():
			await _wait(10)
			continue
		var b: Button = btns[rng.randi_range(0, btns.size() - 1)]
		b.pressed.emit()
		await _wait(4)
		if gs.wolf != null and not gs.wolf.alive:
			await _wait(30)
	if current_scene and current_scene.name == "Game":
		_scan(current_scene, den + ".last")

func _overlay_kind(game) -> String:
	for k in ["card_overlay", "hunt_overlay", "encounter_overlay", "rest_overlay", "region_info_overlay"]:
		var o = game.get(k)
		if o != null and o.visible:
			return k.replace("_overlay", "")
	return "main"

func _skip_button(b: Button, game) -> bool:
	var t := b.text
	if t == TranslationServer.translate("ui.debug") or t == TranslationServer.translate("ui.save_and_exit"):
		return true
	if game.get("debug_overlay") != null and game.debug_overlay.is_ancestor_of(b):
		return true
	if t.begins_with(TranslationServer.translate("action.lie_down")):
		return true
	# 動畫切換會改到 user:// 的設定，不點
	if b == game.get("combat_anim_btn"):
		return true
	return false

func _top_buttons(game) -> Array:
	var kind := _overlay_kind(game)
	var scope: Node = game if kind == "main" else game.get(kind + "_overlay")
	var out: Array = []
	for n in scope.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and not b.disabled and not _skip_button(b, game):
			if kind == "main":
				var covered := false
				for k in ["card_overlay", "hunt_overlay", "encounter_overlay", "rest_overlay", "region_info_overlay"]:
					var o = game.get(k)
					if o != null and o.is_ancestor_of(b):
						covered = true
				if covered:
					continue
			out.append(b)
	return out

func _texts_of(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(n.text)
	elif n is RichTextLabel:
		out.append(n.get_parsed_text())
	elif n is Button:
		out.append(n.text)
	elif n is OptionButton:
		out.append(n.text)
	if n is Control and n.tooltip_text != "":
		out.append(n.tooltip_text)
	return out

func _check_text(t: String, ctx: String) -> bool:
	var hit := false
	for m in key_re.search_all(t):
		var s := m.get_string()
		if prefixes.has(m.get_string(1)) and not s.ends_with(".png") and not s.ends_with(".json"):
			_issue("RAWKEY " + s + "  in「" + t.substr(0, 80).replace("\n", " ") + "」", ctx)
			hit = true
	for m in ph_re.search_all(t):
		_issue("PLACEHOLDER " + m.get_string() + "  in「" + t.substr(0, 80).replace("\n", " ") + "」", ctx)
		hit = true
	return hit

func _scan(scene: Node, ctx: String) -> bool:
	var hit := false
	var vr: Rect2 = scene.get_viewport().get_visible_rect()
	for n in scene.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		if scene.get("debug_overlay") != null and scene.debug_overlay.is_ancestor_of(c):
			continue
		for t in _texts_of(c):
			if _check_text(str(t), ctx + " " + str(c.get_path()).get_file()):
				hit = true
		if _in_scroll(c, scene):
			continue
		var r := c.get_global_rect()
		if r.size.x > 0 and r.size.y > 0 and not vr.grow(1.0).encloses(r) and (c is Label or c is Button or c is RichTextLabel):
			_issue("OFFSCREEN %s %s rect=%s text=「%s」" % [c.get_class(), str(c.get_path()).get_file(), str(r), _first_text(c)], ctx)
			hit = true
		if c is Label and c.autowrap_mode == TextServer.AUTOWRAP_OFF and not c.clip_text and c.text != "":
			var need := c.get_theme_font("font").get_multiline_string_size(c.text, c.horizontal_alignment, -1, c.get_theme_font_size("font_size")).x
			if need > c.size.x + 2:
				_issue("LABEL_SPILL %s need=%d have=%d text=「%s」" % [str(c.get_path()).get_file(), need, c.size.x, _first_text(c)], ctx)
				hit = true
	return hit

func _first_text(c: Control) -> String:
	var t: Array = _texts_of(c)
	return (str(t[0]) if not t.is_empty() else "").substr(0, 40).replace("\n", " ")

func _in_scroll(c: Node, scene: Node) -> bool:
	var p := c.get_parent()
	while p != null and p != scene:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

func _issue(k: String, ctx: String) -> void:
	# 同一個問題只記第一次出現的地方
	var norm := k
	if not issues.has(norm):
		issues[norm] = ctx
		print("NEW ", norm, "   @ ", ctx)

func _shot(name: String) -> void:
	if shots >= 400:
		return
	shots += 1
	var img := root.get_texture().get_image()
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	img.save_png(OUT + name + ".png")
