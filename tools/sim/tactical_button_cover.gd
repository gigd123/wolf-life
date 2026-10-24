extends SceneTree
# 戰術狩獵畫面的按鈕有沒有被別的元件蓋住（2026-10-24 試玩回報：咬住小駝鹿、喘 0 時四個招式灰掉、按鈕擠成三排，
# 最下面的「鬆口」「交給本能」被撲咬資訊的小框 hover_box 蓋住，按了沒反應）。
# 主遊戲開一場戰術狩獵，在幾種狀態（沒咬住、咬住、咬住且喘 0；有喘、沒喘）下，檢查每個看得到的按鈕中心點，
# 有沒有排在它後面（畫在上面、先收到滑鼠）、又會攔滑鼠的元件。
# 用法：bash tools/run_sim.sh tactical_button_cover
var f := 0
var game
var gs
var fails := 0

func _btns(n: Node, out: Array) -> void:
	if n is Button and n.is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_btns(c, out)

# 樹的前序走訪：排在後面的元件畫在上面、先收到滑鼠
func _order(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_order(c, out)

func _check_cover(view, state: String) -> void:
	var order: Array = []
	_order(game, order)
	var bs: Array = []
	_btns(view.buttons, bs)
	for b in bs:
		var pt: Vector2 = b.get_global_rect().get_center()
		var idx: int = order.find(b)
		for k in range(idx + 1, order.size()):
			var c = order[k]
			if not (c is Control) or not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				continue
			if b.is_ancestor_of(c):
				continue
			if c.get_global_rect().has_point(pt):
				fails += 1
				print("  ✗ %s：按鈕「%s」被 %s（%s）蓋住" % [state, b.text, c.name, c.get_class()])
				break

func _process(_d) -> bool:
	f += 1
	if f == 2:
		gs = root.get_node("GameState")
		gs.new_game("forest_east")
		gs.debug_force_transition("adult")
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 6:
		gs.pending_events.clear()
		game.encounter_overlay.visible = false
		game.card_overlay.visible = false
		game.current_hunt = gs.start_hunt("moose", "juvenile", -1, false, "forest_edge")
		game._open_tactical()
	if f >= 8 and f <= 13:
		var view = game.tactical_view
		var h = view.h
		var cases := [["沒咬住、有喘", false, 30.0], ["沒咬住、喘 0", false, 0.0], ["咬住、有喘", true, 30.0], ["咬住、喘 0", true, 0.0]]
		var ci: int = f - 8
		if ci < cases.size():
			for k in h.herd.size():
				if h.is_fawn(k):
					h.target = k
					h.di = k
			h.wolf_pos = h.herd[h.target]["pos"] + Vector2i(-1, 0)
			h.held = bool(cases[ci][1])
			h.hold_side = "rear"
			h.breath = float(cases[ci][2])
			view._after_action()
			_check_cover.call_deferred(view, str(cases[ci][0]))
	if f == 16:
		print("失敗 %d 項" % fails if fails > 0 else "全部通過")
		quit()
	return false
