extends SceneTree
# 錄遊玩影片（2026-11-11，給其他 AI 或人看遊戲用）：開主遊戲，照 MODE 自動玩，配合 Godot 的 --write-movie 錄下來。
#   MODE=hunt   主遊戲的戰術狩獵（馬鹿群）：交給本能一步一步走，每一步前先點狼顯示能走的格子
#   MODE=combat 主遊戲的戰術戰鬥（在殘骸旁被灰熊搶）：交給本能一回合一回合打
#   MODE=life   主畫面一路探索：遇到狩獵、戰鬥照上面的方式打，其他事件挑一個選項，卡片按繼續
# STEP 每幾格做一個動作（預設 40，30 fps 約 1.3 秒），FRAMES 錄幾格後結束（預設 900）。
# 用法：MODE=hunt xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
#   --resolution 1920x1080 --fixed-fps 30 --write-movie out.avi -s tools/record_play.gd
var f := 0
var game
var mode := "life"
var step_every := 40
var max_frames := 900
var next_at := 30
var pol := ""
var shown := false

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

func _process(_d) -> bool:
	f += 1
	var gs = root.get_node("GameState")
	if f == 2:
		mode = _env("MODE", "life")
		step_every = int(_env("STEP", "40"))
		max_frames = int(_env("FRAMES", "900"))
		var den := "forest_west" if mode == "hunt" else ("forest_east" if mode == "combat" else _env("DEN", "forest_east"))
		gs.new_game(den)
		gs.debug_force_transition("adult")
		gs.wolf.perception = maxf(gs.wolf.perception, 80.0)
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 20:
		if mode == "hunt":
			game._begin_hunt("elk", "adult")
		elif mode == "combat":
			gs.start_feeding("elk", "adult", "forest_edge")
			game._begin_combat(gs.start_combat("grizzly_bear", "adult", "carcass"), "move")
	if f >= next_at and f > 25:
		next_at = f + step_every
		_act()
	return f >= max_frames

func _act() -> void:
	var hv = game.tactical_view
	if hv != null and is_instance_valid(hv) and hv.h != null:
		if hv.h.done:
			_press_continue(hv)
			return
		if pol == "":
			TacticalInstinct.pick_target(hv.h)
			pol = TacticalInstinct.pick_policy(hv.h)
		# 先點狼顯示能走的格子，下一個動作再走
		if not shown and not hv.h.held:
			hv.range_shown = true
			hv._refresh()
			shown = true
			next_at = f + step_every / 2
			return
		shown = false
		hv.range_shown = false
		TacticalInstinct.step(hv.h, pol)
		hv._after_action()
		return
	pol = ""
	var cv = game.tactical_combat_view
	if cv != null and is_instance_valid(cv) and cv.tc != null:
		if cv.tc.done:
			_press_continue(cv)
			return
		if not shown:
			cv.range_shown = true
			cv._refresh()
			shown = true
			next_at = f + step_every / 2
			return
		shown = false
		cv.range_shown = false
		cv.tc.plan(0, cv.tc.auto_plan(0))
		cv._resolve_and_next()
		return
	if _press_continue(game):
		return
	if game.encounter_overlay.visible:
		var btns: Array = game.encounter_buttons_box.get_children().filter(func(b): return b is Button and b.visible and not b.disabled)
		if btns.is_empty():
			return
		var pick: Button = btns[0]
		for b in btns:
			var t: String = b.text
			if t.contains("狩") or t.contains("追") or t.contains("靠近") or t.contains("出手") or t.contains("吃"):
				pick = b
				break
		pick.pressed.emit()
		return
	if mode == "life":
		game._on_action_button("explore")

# 畫面上看得到的「繼續」之類的按鈕：按下去
func _press_continue(node: Node) -> bool:
	for b in node.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.disabled and str(b.text) in ["繼續", "好", "知道了", "確定"]:
			b.pressed.emit()
			return true
	return false
