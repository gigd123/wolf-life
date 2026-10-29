extends SceneTree
# 聽到與貼身必察覺（2026-10-29 QA：小跑貼近鹿群卻沒逃；使用者選 A 加 B）：
#   1. 小跑結束在牠身邊 1 格內：一定察覺（逃，會站定的照站定）
#   2. 隔著密林（沒有視線）小跑到 2 格：聽到的警覺照算（不被密林打折）
#   3. 潛行貼到旁邊：沒有聲音、不強制察覺（潛行還是有用）
#   4. 躲在草裡的幼鹿不受影響（靠不動來躲）
# 用法：bash tools/run_sim.sh alert_hearing
var f := 0
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _fresh(gs):
	var h = gs.start_hunt("white_tailed_deer", "adult", -1, false, "dense_forest")
	h.set_herd(false)
	var th = gs.start_tactical(h)
	th.di = th.target
	return th

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	gs.new_game("forest_east")
	gs.wolf.age_years = 4.0
	gs.debug_set_stat("skill", 90.0)
	# 1
	var ok1 := true
	for i in 20:
		var th = _fresh(gs)
		th.wolf_pos = th.deer_pos + Vector2i(1, 0)
		th.alert = 0.0
		th._raise_alert("trot")
		if not str(th.deer_state) in ["flee", "stand"]:
			ok1 = false
	_check(ok1, "小跑結束在 1 格內：一定察覺（技巧 90 也一樣）")
	# 2
	var th2 = _fresh(gs)
	th2.wolf_pos = th2.deer_pos + Vector2i(2, 0)
	var g: Dictionary = th2.alert_gain("trot")
	var hear: float = float(th2.t["alert"]["hearing"]["trot"][0][1])
	_check(float(g["gain"]) >= hear, "2 格內小跑：聽到至少 +%d（這次 +%.0f，不管有沒有視線）" % [roundi(hear), float(g["gain"])])
	# 3
	var ok3 := true
	for i in 20:
		var th = _fresh(gs)
		th.wolf_pos = th.deer_pos + Vector2i(1, 0)
		th.alert = 0.0
		var gc: Dictionary = th.alert_gain("creep")
		th._raise_alert("creep")
		# 上風被聞到本來就會逃；只看聲音＋看見的部分，而且沒被聞到時不強制察覺
		if float(gc["noise"]) >= 100.0 or (float(gc["scent"]) < 1.0 and str(th.deer_state) == "flee"):
			ok3 = false
	_check(ok3, "潛行貼到旁邊：沒有聲音、不強制察覺（上風被聞到另計）")
	# 4
	gs.debug_set_stat("perception", 30.0)
	var hh = gs.start_hunt("white_tailed_deer", "juvenile", -1, false, "forest_edge", false, true)
	var thh = gs.start_tactical(hh)
	thh.di = thh.target
	thh.wolf_pos = thh.deer_pos + Vector2i(3, 0)
	thh._raise_alert("trot")
	_check(thh.hidden_unfound() and str(thh.deer_state) == "unaware", "躲在草裡的幼鹿：小跑經過也不會被聽到驚起")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
