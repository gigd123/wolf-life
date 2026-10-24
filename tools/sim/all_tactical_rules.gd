extends SceneTree
# Phase 2i 第 5～7 步（所有狩獵改成戰術場景）的回歸測試：
# 第 5 步：
#   1. 受傷的個體走戰術地圖（所有物種）；目標帶 injured，傷數照 injured_wounds_by（馴鹿 0、其他 1）
#   2. 受傷的獵物逃得比較慢：每回合的逃跑格數 × injured_speed_mult（叉角羚 0.75）
#   3. 受傷的旱獺、大角羊離避難處遠（injured_refuge_far）
#   4. 獵物靠近：走戰術地圖；你在目標 3～4 格、牠還沒察覺；幼鹿單獨
# 第 6 步（躲在草裡的幼鹿）：
#   5. 走戰術地圖；幼鹿單獨、躲著、沒察覺；大概在哪的範圍 3×3 包含牠；還沒找到不能撲
#   6. 觀察看出來的機會隨感知變大；同一片草再看，機會變小
#   7. 走到牠旁邊（還沒看出）：竄出來逃，前 bolt_rounds 回合多跑 bolt_bonus 格
#   8. 感知高的狼走近就看見（不驚動牠）
#   9. 畫面：還沒找到時資訊欄寫「躲在草裡」
# 用法：bash tools/run_sim.sh all_tactical_rules
var f := 0
var gs
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _hidden(a: String, perc: float):
	gs.debug_set_stat("perception", perc)
	var h = gs.start_hunt(a, "juvenile", -1, false, "", false, true)
	return gs.start_tactical(h)

func _free_next_to(th, p: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
		var c: Vector2i = p + d
		if c.x >= 0 and c.y >= 0 and c.x < th.width and c.y < th.height:
			return c
	return p + Vector2i(1, 0)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.pending_events.clear()
	# 1. 受傷的個體
	var all_ok := true
	var wounds_ok := true
	for a in ["white_tailed_deer", "elk", "mule_deer", "caribou", "moose", "bison", "pronghorn", "bighorn_sheep", "beaver", "hare", "snowshoe_hare", "marmot"]:
		var h = gs.start_hunt(a, "adult", -1, false, "", true)
		if not gs.tactical_eligible(h):
			all_ok = false
			print("    不走戰術地圖：", a)
			continue
		var th = gs.start_tactical(h)
		if not bool(th.herd[th.target].get("injured", false)) or th.herd.size() != 1:
			all_ok = false
		var want: int = 0 if a == "caribou" else 1
		if int(th.herd[th.target]["wounds"]) != want:
			wounds_ok = false
			print("    傷數不對：%s %d" % [a, int(th.herd[th.target]["wounds"])])
	_check(all_ok, "受傷的個體：所有物種走戰術地圖、單隻、帶 injured")
	_check(wounds_ok, "受傷的個體：傷數照 injured_wounds_by（馴鹿 0、其他 1）")
	# 2. 逃得比較慢
	var hs = gs.start_hunt("pronghorn", "adult", -1, false, "prairie", false)
	var ths = gs.start_tactical(hs)
	var hi = gs.start_hunt("pronghorn", "adult", -1, false, "prairie", true)
	var thi = gs.start_tactical(hi)
	thi.herd[thi.target]["condition"] = ths.herd[ths.target]["condition"]
	thi.herd[thi.target]["wounds"] = 0
	var b0: float = ths._flee_budget(ths.target)
	var b1: float = thi._flee_budget(thi.target)
	_check(absf(b1 - maxf(1.0, b0 * 0.75)) < 0.01, "受傷的叉角羚每回合逃跑格數 × 0.75（%.2f → %.2f）" % [b0, b1])
	# 3. 離避難處遠
	var far_ok := true
	for i in 30:
		var hm = gs.start_hunt("marmot", "adult", -1, false, "scree", true)
		hm.refuge_near = true
		var thm = gs.start_tactical(hm)
		if thm.dist(thm.deer_pos, thm._open_hole(thm.deer_pos)) < 3.5:
			far_ok = false
	_check(far_ok, "受傷的旱獺離洞口遠（擲到近也一樣）")
	# 4. 獵物靠近
	var near_ok := true
	var dists: Array = []
	for ev in [{"animal_id": "snowshoe_hare", "life_stage": "adult"}, {"animal_id": "white_tailed_deer", "life_stage": "juvenile"}, {"animal_id": "caribou", "life_stage": "juvenile"}]:
		for i in 10:
			var hn = gs.hunt_nearby_prey({"animal_id": ev["animal_id"], "life_stage": ev["life_stage"], "terrain": ""})
			if not gs.tactical_eligible(hn):
				near_ok = false
				continue
			var thn = gs.start_tactical(hn)
			var d: float = thn.dist(thn.wolf_pos, thn.herd[thn.target]["pos"])
			dists.append(snappedf(d, 0.1))
			if d < 2.9 or d > 4.6 or str(thn.herd[thn.target]["state"]) != "unaware" or thn.herd.size() != 1:
				near_ok = false
	_check(near_ok, "獵物靠近：走戰術地圖、你在 3～4 格、牠還沒察覺、幼鹿單獨（距離 %s～%s）" % [dists.min(), dists.max()])
	# 5. 躲在草裡的幼鹿
	root.get_node("GameTime").season_index = root.get_node("GameTime").SEASONS.find("summer")
	var hid_ok := true
	for a in ["white_tailed_deer", "elk", "mule_deer", "pronghorn"]:
		for i in 5:
			var hh = gs.start_hunt(a, "juvenile", -1, false, "", false, true)
			if not hh.hiding or not gs.tactical_eligible(hh):
				hid_ok = false
				print("    不走戰術地圖：", a)
				continue
			var th = gs.start_tactical(hh)
			var tg: Dictionary = th.herd[th.target]
			if th.herd.size() != 1 or not bool(tg.get("hiding", false)) or str(tg["state"]) != "unaware" or not th.hidden_unfound() \
					or th.hidden_area.size != Vector2i(3, 3) or not th.hidden_area.has_point(tg["pos"]) or not th.pounce_targets().is_empty():
				hid_ok = false
	_check(hid_ok, "躲在草裡的幼鹿：走戰術地圖、單獨躲著沒察覺、範圍 3×3 包含牠、還沒找到不能撲")
	# 6. 觀察的機會
	var tl = _hidden("white_tailed_deer", 45.0)
	var th_hi = _hidden("white_tailed_deer", 90.0)
	var c_lo: float = tl.hidden_observe_chance()
	var c_hi: float = th_hi.hidden_observe_chance()
	th_hi.stats["hidden_observes"] = 1
	var c_again: float = th_hi.hidden_observe_chance()
	_check(c_hi > c_lo + 0.2 and c_again < c_hi * 0.5, "觀察看出來的機會：感知 45 → %.2f、90 → %.2f；再看一次 %.2f" % [c_lo, c_hi, c_again])
	# 7. 走到旁邊：竄出來
	var tb = _hidden("white_tailed_deer", 30.0)
	var fp: Vector2i = tb.herd[tb.target]["pos"]
	tb.wolf_pos = _free_next_to(tb, fp)
	tb._check_hidden()
	var bolt_ok: bool = tb.deer_state == "flee" and bool(tb.herd[tb.target].get("bolted", false)) and not tb.hidden_unfound()
	var hc: Dictionary = tb.t["game"]["hidden"]
	tb.di = tb.target
	var fl: Array = tb.t["herd"]["fawn_flee"]
	var bb: float = tb._flee_budget()
	_check(bolt_ok and absf(bb - (float(fl[0]) + float(hc["bolt_bonus"]))) < 0.01,
		"走到旁邊還沒看出：竄出來逃、第一回合 %.1f 格（幼鹿 %s ＋ %s）" % [bb, fl[0], hc["bolt_bonus"]])
	# 8. 感知高的狼走近就看見
	var tw = _hidden("white_tailed_deer", 95.0)
	var fp2: Vector2i = tw.herd[tw.target]["pos"]
	var rd: float = tw.hidden_reveal_dist()
	var spot := Vector2i(-1, -1)
	for y in tw.height:
		for x in tw.width:
			var c := Vector2i(x, y)
			if tw._cheb(c, fp2) >= 2 and tw.dist(c, fp2) <= rd:
				spot = c
	tw.wolf_pos = spot
	tw._check_hidden()
	_check(spot.x >= 0 and not tw.hidden_unfound() and tw.deer_state == "unaware",
		"感知 95 走到 %.1f 格內就看見（沒驚動牠）" % rd)
	# 9. 畫面
	var view = load("res://prototypes/tactical_hunt/TacticalHunt.tscn").instantiate()
	root.add_child(view)
	view.start_from_game(_hidden("white_tailed_deer", 50.0), func(_t): pass)
	_check(view._info_text().contains("躲在草裡"), "畫面：還沒找到時資訊欄寫「躲在草裡」")
	view.queue_free()
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
