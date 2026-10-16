extends SceneTree
# 存檔一致性（文案一致性 D，2026-10-16）：玩一段之後 存檔 → 讀檔 → 再存檔，兩次存檔的內容要一樣（沒有讀不回來的狀態）；
# 還沒顯示的字卡、今天睡過的傷勢好轉讀檔後還在。
# 用法：bash tools/run_sim.sh save_roundtrip
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	for den in ["forest_east", "tundra_south", "mountain_canyon", "grassland_riverwoods"]:
		gs.new_game(den)
		gs.debug_force_transition("adult")
		gs.run_routine(3, "small")
		gs.debug_start_fire("")
		for i in 6:
			gs.debug_skip_day()
		gs.wolf.apply_injury(1, 3, "", "", "test")
		gs._sleep_heal = 1
		gs._queue_notice({"type": "season_card", "season": "spring", "first": false, "lines": [], "map": "forest", "region": den, "review": {}})
		var n_pending: int = gs.pending_events.size()
		var d1 = JSON.parse_string(JSON.stringify(gs.to_dict()))
		gs.load_from_dict(d1)
		var d2 = JSON.parse_string(JSON.stringify(gs.to_dict()))
		var diff: Array = _diff(d1, d2, "")
		_check(diff.is_empty(), "%s：讀檔後再存不一樣：%s" % [den, diff.slice(0, 8)])
		_check(gs.pending_events.size() == n_pending and n_pending > 0, "%s：還沒顯示的事件 %d → %d" % [den, n_pending, gs.pending_events.size()])
		_check(gs._sleep_heal == 1, "%s：今天睡過的傷勢好轉讀檔後不見" % den)
		print("%s：存檔 %d 個欄位、待顯示事件 %d、差異 %d" % [den, (d1 as Dictionary).size(), gs.pending_events.size(), diff.size()])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _diff(a, b, path: String) -> Array:
	var out: Array = []
	if typeof(a) != typeof(b):
		return [path]
	if a is Dictionary:
		for k in a.keys():
			if not b.has(k):
				out.append(path + "/" + str(k) + "（少了）")
			else:
				out.append_array(_diff(a[k], b[k], path + "/" + str(k)))
		for k in b.keys():
			if not a.has(k):
				out.append(path + "/" + str(k) + "（多了）")
	elif a is Array:
		if a.size() != b.size():
			return [path + "（長度 %d → %d）" % [a.size(), b.size()]]
		for i in a.size():
			out.append_array(_diff(a[i], b[i], path + "[%d]" % i))
	elif a != b:
		out.append("%s（%s → %s）" % [path, str(a).substr(0, 30), str(b).substr(0, 30)])
	return out

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
