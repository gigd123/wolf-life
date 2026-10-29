extends SceneTree
# Phase 2i 第 5～7 步（所有狩獵改成戰術場景）的回歸測試：
# 第 5 步：
#   1. 受傷的個體走戰術地圖（所有物種）；目標帶 injured，傷數照 injured_wounds_by（馴鹿 0、其他 1）
#   2. 受傷的獵物逃得比較慢：每回合的逃跑格數 × injured_speed_mult（叉角羚照 injured_speed_by）
#   3. 受傷的旱獺、大角羊離避難處遠（injured_refuge_far）
#   4. 獵物靠近：走戰術地圖；你在目標 3～4 格、牠還沒察覺；幼鹿單獨
# 第 6 步（躲在草裡的幼鹿）：
#   5. 走戰術地圖；幼鹿單獨、躲著、沒察覺；大概在哪的範圍 3×3 包含牠；還沒找到不能撲
#   6. 觀察看出來的機會隨感知變大；同一片草再看，機會變小
#   7. 走到牠旁邊（還沒看出）：竄出來逃，前 bolt_rounds 回合多跑 bolt_bonus 格
#   8. 感知高的狼走近就看見（不驚動牠）
#   9. 畫面：還沒找到時資訊欄寫「躲在草裡」
# 第 7 步（牧場的家畜）：
#  10. 牛犢、一歲牛、成牛、羊都走戰術地圖：物種對、牛犢與一歲牛單獨、成牛會站定（stand）、羊一群 5～9 隻
#  11. 戰術地圖有家畜的小圖
#  12. 牧場的注意：獵到加那一種的注意；牠察覺你、沒獵到算被看到；沒察覺就放棄不加
#  13. 所有會被獵的動物都走戰術地圖（除了小撲）
#  14. 單獨出場的幼體（牛犢、小河狸、小叉角羚）獵到後還是幼體（2026-10-25 修正：原本被改成成體）；鹿群裡改追成鹿的照舊改成成體
#  15. 一次吃完的獵物（兔子、河狸、旱獺、小叉角羚）獵到後飽食度加 hunger_value（2026-10-25 試玩回報：獵到河狸飽食度沒增加）
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
	var pm: float = float(thi.t["game"]["injured_speed_by"]["pronghorn"])
	_check(absf(b1 - maxf(1.0, b0 * pm)) < 0.01, "受傷的叉角羚每回合逃跑格數 × %s（%.2f → %.2f）" % [pm, b0, b1])
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
	_check(c_hi > c_lo + 0.2 and absf(c_again - c_hi * float(th_hi.t["game"]["hidden"]["observe_repeat_mult"])) < 0.01, "觀察看出來的機會：感知 45 → %.2f、90 → %.2f；再看一次 %.2f" % [c_lo, c_hi, c_again])
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
	# 10. 牧場的家畜
	gs.new_game("grassland_plains")
	gs.debug_force_transition("adult")
	var ls_ok := true
	var sheep_sizes: Array = []
	for p in [["cattle", "juvenile", "cattle_calf"], ["cattle", "adult", "cattle"], ["cattle", "buck", "cattle_cow"], ["sheep", "adult", "sheep"]]:
		for i in 5:
			var hl = gs.start_hunt(p[0], p[1], -1, false, "prairie")
			if not gs.tactical_eligible(hl):
				ls_ok = false
				continue
			var tl2 = gs.start_tactical(hl)
			var spc: String = str(tl2.herd[tl2.target]["species"])
			if spc != p[2]:
				ls_ok = false
				print("    物種不對：", p, " → ", spc)
			if p[0] == "cattle" and tl2.herd.size() != 1:
				ls_ok = false
			if p[2] == "cattle_cow" and not tl2.sp(tl2.target).has("stand"):
				ls_ok = false
			if p[0] == "sheep":
				sheep_sizes.append(tl2.herd.size())
	_check(ls_ok and sheep_sizes.min() >= 5 and sheep_sizes.max() <= 9, "家畜走戰術地圖：物種對、牛單獨、成牛會站定、羊一群 %s～%s 隻" % [sheep_sizes.min(), sheep_sizes.max()])
	# 11. 小圖
	var art_ok := true
	for k in ["cattle_calf", "cattle", "cattle_cow", "sheep"]:
		if not ResourceLoader.exists("res://assets/art/tactical/%s.png" % k):
			art_ok = false
	_check(art_ok, "戰術地圖有牛犢、一歲牛、成牛、羊的小圖")
	# 12. 牧場的注意
	gs.debug_ranch("open")
	gs.ranch["attention"] = 0.0
	var hk = gs.start_hunt("cattle", "juvenile", -1, false, "prairie")
	var tk = gs.start_tactical(hk)
	tk._finish("caught", "test")
	gs.wolf.hunger = 30.0
	gs.finish_tactical_hunt(hk, tk)
	var a_kill: float = gs.ranch_attention()
	gs.current_feeding = {}
	gs.ranch["attention"] = 0.0
	var hn2 = gs.start_hunt("cattle", "adult", -1, false, "prairie")
	var tn = gs.start_tactical(hn2)
	tn.deer_state = "flee"
	tn.detect_cause = "close"
	tn._finish("escaped", "test")
	gs.finish_tactical_hunt(hn2, tn)
	var a_seen: float = gs.ranch_attention()
	gs.ranch["attention"] = 0.0
	var hq = gs.start_hunt("cattle", "adult", -1, false, "prairie")
	var tq = gs.start_tactical(hq)
	tq._finish("gave_up", "test")
	gs.finish_tactical_hunt(hq, tq)
	var a_quiet: float = gs.ranch_attention()
	_check(a_kill > 0.0 and a_seen > 0.0 and a_seen < a_kill and a_quiet == 0.0, "牧場的注意：獵到牛犢 +%.1f、被察覺沒獵到 +%.1f、沒察覺就放棄 +%.1f" % [a_kill, a_seen, a_quiet])
	# 13. 所有獵物
	var tun: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical_hunt.json"))
	var missing: Array = []
	var gd = root.get_node("GameData")
	for a in gd.animals.keys():
		var ad = gd.animals[a]
		if ad is Dictionary and str(ad.get("type", "")) == "prey" and a != "red_fox" and not (tun["game"]["animals"] as Array).has(a):
			missing.append(a)
	_check(missing.is_empty(), "所有會被獵的動物都走戰術地圖（紅狐只搶食；沒有的：%s）" % [missing])
	# 14. 單獨出場的幼體獵到後還是幼體
	var young_ok := true
	for a in [["cattle", "prairie"], ["beaver", "stream"], ["pronghorn", "prairie"]]:
		var hy = gs.start_hunt(a[0], "juvenile", -1, false, a[1])
		var ty = gs.start_tactical(hy)
		ty._finish("caught", "test")
		gs.wolf.hunger = 30.0
		gs.finish_tactical_hunt(hy, ty)
		gs.current_feeding = {}
		if hy.life_stage != "juvenile":
			young_ok = false
			print("    獵到後變成 ", hy.life_stage, "：", a[0])
	_check(young_ok, "單獨出場的幼體（牛犢、小河狸、小叉角羚）獵到後還是幼體")
	# 15. 一次吃完的獵物加飽食度
	var gd2 = root.get_node("GameData")
	var eat_ok := true
	var eat_log: Array = []
	for a in [["snowshoe_hare", "adult", "dense_forest"], ["hare", "adult", "prairie"], ["beaver", "adult", "stream"], ["beaver", "juvenile", "stream"], ["marmot", "adult", "scree"], ["pronghorn", "juvenile", "prairie"]]:
		gs.wolf.hunger = 30.0
		var he = gs.start_hunt(a[0], a[1], -1, false, a[2])
		var te = gs.start_tactical(he)
		te._finish("caught", "test")
		gs.finish_tactical_hunt(he, te)
		var want: float = float(gd2.animals[a[0]][a[1]]["hunger_value"])
		eat_log.append("%s %s +%d" % [a[0], a[1], roundi(gs.wolf.hunger - 30.0)])
		if gs.wolf.hunger - 30.0 < want - 10.0 or gs.wolf.hunger - 30.0 > want or not gs.current_feeding.is_empty():
			eat_ok = false
		gs.current_feeding = {}
	_check(eat_ok, "一次吃完的獵物獵到後加飽食度（%s；時間的消耗另計）" % "、".join(eat_log))
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
