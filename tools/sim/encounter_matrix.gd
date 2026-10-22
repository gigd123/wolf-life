extends SceneTree
# 事件結局矩陣（文案一致性 B，2026-10-16）：每種遭遇／事件 × 第一步的每個選項 × 幾種後續打法，實際按畫面上的按鈕玩到底，檢查：
#   NO_RESULT   有戰鬥，結束時沒有結果畫面（試玩 BUG-05）
#   NO_HUNT_RESULT 狩獵結束後，下一個畫面沒有交代結果（結果畫面、或寫著結果的遭遇畫面、或卡片）
#   STUCK       畫面上沒有能按的按鈕、又沒回到主畫面（卡住）
#   TOO_LONG    按了 MAX_STEPS 次還沒結束
#   QUEUE       回到主畫面後事件佇列還有東西卻沒有顯示
#   NO_ROUTINE  回到主畫面後「照常過日子」按鈕不見
#   NO_DEATH_CARD  死了卻沒有「最後」字卡
#   TEXT        原始翻譯鍵、沒替換的 {佔位}（TextWatch）
#   NOT_TRIGGERED  除錯觸發後什麼都沒發生（只列出，不算失敗）
# 用法：bash tools/run_sim.sh encounter_matrix（headless，約 6 分鐘）；環境變數 ONLY=名稱片段（只跑符合的情境）、POLICIES=first,last,r1,r2、
#   TRACE=1（印出每一步）。有戰鬥動畫的版本：ANIM=fast xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/sim/encounter_matrix.gd
const MAX_STEPS := 140
var issues := {} # 問題 -> 第一次的情境
var stats := {"runs": 0, "combat": 0, "died": 0, "not_triggered": []}
var rng := RandomNumberGenerator.new()
var gs
var frame := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

# 情境：名稱、巢穴、生命階段、觸發方式（"enc:動物:階段" 強制遭遇；"btn:翻譯鍵" 按除錯選單的按鈕）
func _scenarios() -> Array:
	var out: Array = []
	for a in gs.debug_animal_ids():
		for st in ["adult", "juvenile"]:
			out.append({"name": "%s.%s" % [a, st], "den": "forest_east", "stage": "adult", "trigger": "enc:%s:%s" % [a, st]})
	for k in ["debug.event.bear_distant", "debug.event.stranger_distant", "debug.event.howl", "debug.event.driven_off",
			"debug.event.prey_nearby", "debug.event.bear_passing", "debug.event.fox_scavenge", "debug.event.mother_bear",
			"debug.event.stranger_meet", "debug.event.stranger_confront", "debug.event.bear_scavenge", "debug.event.old_injury",
			"debug.event.pack_meet", "debug.event.pack_young", "debug.event.pack_remains", "debug.event.small_pounce", "debug.event.lynx_kill", "debug.event.salmon"]:
		out.append({"name": k, "den": "forest_east", "stage": "adult", "trigger": "btn:" + k})
	out.append({"name": "debug.challenger", "den": "forest_east", "stage": "elder", "trigger": "btn:debug.challenger"})
	for k in ["debug.tundra.wolverine", "debug.tundra.ravens", "debug.tundra.ice", "debug.tundra_wolf.meet", "debug.tundra_wolf.mob",
			"debug.tundra_wolf.howl", "debug.tundra_wolf.carcass", "debug.tundra.blizzard"]:
		out.append({"name": k, "den": "tundra_south", "stage": "adult", "trigger": "btn:" + k})
	# 次成年的狼也跑幾種危險的
	for a in ["grizzly_bear", "stranger_wolf", "cougar", "moose"]:
		out.append({"name": "subadult.%s" % a, "den": "forest_east", "stage": "subadult", "trigger": "enc:%s:adult" % a})
	return out

func _run() -> void:
	var anim_mode: String = CombatAnimator.mode()
	# 有視窗（xvfb）時可以開戰鬥動畫，測「動畫還沒播完就結束」這類先後問題（試玩 BUG-05）；headless 一律略過動畫
	if OS.get_environment("ANIM") != "":
		CombatAnimator.set_mode(OS.get_environment("ANIM"))
	var only: String = OS.get_environment("ONLY")
	var policies: Array = (OS.get_environment("POLICIES") if OS.get_environment("POLICIES") != "" else "first,last,r1,r2").split(",")
	var before_logs: Array = Array(DirAccess.get_files_at("res://playtest_logs")) if DirAccess.dir_exists_absolute("res://playtest_logs") else []
	for scn in _scenarios():
		if only != "" and not Array(only.split(",")).any(func(o): return str(scn["name"]).contains(o)):
			continue
		# 第一步有幾個選項：先觸發一次看看
		var n_first: int = await _probe(scn)
		if n_first < 0:
			stats["not_triggered"].append(scn["name"])
			continue
		for choice in range(max(1, n_first)):
			for pol in policies:
				await _play(scn, choice, pol)
	CombatAnimator.set_mode(anim_mode)
	# 狼死亡時遊戲會存試玩紀錄；測試產生的不留
	if DirAccess.dir_exists_absolute("res://playtest_logs"):
		for fn in DirAccess.get_files_at("res://playtest_logs"):
			if not before_logs.has(fn):
				DirAccess.remove_absolute("res://playtest_logs/" + fn)
	print("== 事件結局矩陣：%d 場（有戰鬥 %d、死亡 %d）" % [stats["runs"], stats["combat"], stats["died"]])
	if not stats["not_triggered"].is_empty():
		print("NOT_TRIGGERED ", stats["not_triggered"])
	for k in issues.keys():
		print("ISSUE ", k, "   @ ", issues[k])
	print("問題 %d 個" % issues.size() if not issues.is_empty() else "全部通過")
	quit(1 if not issues.is_empty() else 0)

func _setup(scn: Dictionary) -> Node:
	gs.new_game(str(scn["den"]))
	match str(scn["stage"]):
		"adult":
			gs.debug_force_transition("adult")
		"elder":
			gs.debug_add_age(6.0)
			gs.debug_force_transition("elder")
	gs.pending_events.clear()
	change_scene_to_file("res://scenes/Game.tscn")
	await _wait(6)
	var game = current_scene
	game.text_watch_timer = 0.0
	return game

func _trigger(game, scn: Dictionary) -> void:
	var t: String = str(scn["trigger"])
	if t.begins_with("enc:"):
		var p: PackedStringArray = t.split(":")
		game._on_debug_force_encounter(p[1], p[2])
	else:
		var label: String = TranslationServer.translate(t.substr(4))
		for n in game.debug_overlay.find_children("*", "Button", true, false):
			if (n as Button).text == label:
				(n as Button).pressed.emit()
				break
		game.debug_overlay.visible = false
	await _wait(4)

func _probe(scn: Dictionary) -> int:
	var game = await _setup(scn)
	root.get_node("RNGService").set_seed(hash(str(scn["name"]) + "probe"))
	await _trigger(game, scn)
	if _at_rest(game):
		return -1
	return _top_buttons(game).size()

func _at_rest(game) -> bool:
	return _overlay_kind(game) == "main" and not game.session_active and game.current_combat == null and game.current_hunt == null \
		and gs.pending_events.is_empty()

func _play(scn: Dictionary, choice: int, pol: String) -> void:
	rng.seed = hash(str(scn["name"]) + pol + str(choice))
	var game = await _setup(scn)
	root.get_node("RNGService").set_seed(hash(str(scn["name"]) + pol + str(choice))) # 同一場可以重現（TRACE）
	await _trigger(game, scn)
	stats["runs"] += 1
	var ctx := "%s 選項%d %s" % [scn["name"], choice, pol]
	var saw_session := false
	var saw_result := false
	var saw_combat := false
	var in_hunt := false
	var hunt_just_ended := false
	var idle := 0
	var steps := 0
	var path: Array = []
	while true:
		if not (current_scene and current_scene.name == "Game"):
			break # 死後到了一生回顧
		game = current_scene
		if gs.wolf != null and not gs.wolf.alive:
			stats["died"] += 1
			await _wait(8)
			if current_scene and current_scene.name == "Game" and not (game.death_card_shown and game.card_overlay.visible):
				_issue("NO_DEATH_CARD", ctx)
			break
		saw_session = saw_session or game.session_active
		saw_result = saw_result or game.session_result_mode
		saw_combat = saw_combat or game.current_combat != null
		if in_hunt and game.current_hunt == null and game.current_combat == null:
			hunt_just_ended = true
		in_hunt = game.current_hunt != null
		if hunt_just_ended and not in_hunt:
			var told: bool = game.session_result_mode or game.card_overlay.visible \
				or (game.encounter_overlay.visible and game.encounter_message.text.strip_edges() != "")
			if not told and _overlay_kind(game) != "main":
				_issue("NO_HUNT_RESULT " + "／".join(path.slice(-3)), ctx)
			if told or _overlay_kind(game) == "main":
				hunt_just_ended = false
		if _at_rest(game):
			break
		# 主畫面但還沒結束（事件佇列有東西、遭遇還沒收尾）：等它自己顯示，不去按主畫面的行動
		var btns: Array = [] if _overlay_kind(game) == "main" else _top_buttons(game)
		if btns.is_empty():
			idle += 1
			if idle > 40:
				_issue("STUCK %s %s" % [_overlay_kind(game), "／".join(path.slice(-4))], ctx)
				break
			await _wait(2)
			continue
		idle = 0
		steps += 1
		if steps > MAX_STEPS:
			_issue("TOO_LONG " + "／".join(path.slice(-4)), ctx)
			break
		var i: int = 0
		if steps == 1:
			i = min(choice, btns.size() - 1)
		else:
			match pol:
				"first": i = 0
				"last": i = btns.size() - 1
				_: i = rng.randi_range(0, btns.size() - 1)
		var b: Button = btns[i]
		if OS.get_environment("TRACE") != "":
			print("  [%s] %s session=%s result=%s combat=%s msg=「%s」 按：%s／%s" % [ctx, _overlay_kind(game), game.session_active, game.session_result_mode,
				game.current_combat != null, game.encounter_message.text.substr(0, 40).replace("\n", " "), b.text.substr(0, 16), btns.map(func(x): return x.text.substr(0, 8))])
		path.append(b.text.substr(0, 12))
		b.pressed.emit()
		await _wait(3)
	if saw_combat:
		stats["combat"] += 1
	var alive: bool = gs.wolf != null and gs.wolf.alive and current_scene and current_scene.name == "Game"
	if alive:
		game = current_scene
		await _wait(6)
		if hunt_just_ended and not saw_result:
			_issue("NO_HUNT_RESULT（直接回到主畫面） " + "／".join(path.slice(-3)), ctx)
		if saw_combat and not saw_result:
			_issue("NO_RESULT " + "／".join(path.slice(-3)), ctx)
		if not gs.pending_events.is_empty() and _overlay_kind(game) == "main":
			_issue("QUEUE " + str(gs.pending_events.map(func(e): return e.get("type", ""))), ctx)
		# 進食中、還有發現、次成年等不能照常過日子的狀態不算（GameState.can_routine）
		if _overlay_kind(game) == "main" and gs.can_routine() and not _routine_visible(game):
			_issue("NO_ROUTINE", ctx)
		game.text_watch.scan(game, game.debug_overlay)
	for k in gs.metrics().get("text_issues", {}).keys():
		_issue("TEXT %s「%s」" % [k, gs.metrics()["text_issues"][k]["text"]], ctx)
	gs.metrics()["text_issues"] = {}

func _routine_visible(game) -> bool:
	var label: String = TranslationServer.translate("action.routine")
	for n in game.find_children("*", "Button", true, false):
		var b := n as Button
		if b.text == label and b.is_visible_in_tree():
			return true
	return false

# --- 和 tools/ui_check.gd 相同的按鈕選取 ---

func _overlay_kind(game) -> String:
	# 戰術狩獵（Phase 2c）：蓋在整個畫面上，按它自己的按鈕（觀察、放棄、繼續）
	var tv = game.get("tactical_view")
	if tv != null and is_instance_valid(tv) and tv.is_inside_tree():
		return "tactical"
	for k in ["card_overlay", "hunt_overlay", "encounter_overlay", "rest_overlay", "region_info_overlay"]:
		var o = game.get(k)
		if o != null and o.visible:
			return k.replace("_overlay", "")
	return "main"

func _skip_button(b: Button, game) -> bool:
	var t := b.text
	if t == TranslationServer.translate("ui.debug") or t == TranslationServer.translate("ui.save_and_exit"):
		return true
	if game.debug_overlay.is_ancestor_of(b):
		return true
	if t.begins_with(TranslationServer.translate("action.lie_down")):
		return true
	if b == game.get("combat_anim_btn"):
		return true
	return false

func _top_buttons(game) -> Array:
	var kind := _overlay_kind(game)
	var scope: Node = game if kind == "main" else (game.tactical_view.buttons if kind == "tactical" else game.get(kind + "_overlay"))
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

func _issue(k: String, ctx: String) -> void:
	if not issues.has(k):
		issues[k] = ctx
		print("NEW ", k, "   @ ", ctx)
