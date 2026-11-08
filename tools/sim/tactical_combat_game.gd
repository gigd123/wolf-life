extends SceneTree
# Phase 2k 戰術戰鬥接進主遊戲（SPEC「戰術戰鬥接進主遊戲」）的回歸測試（R-125）：
#   1. 灰熊、美洲獅的戰鬥走戰術戰鬥；狐狸、狼獾還是選單式；關掉時（tactical_combat_off）一律選單式
#   2. 被打倒與死亡：還沒重傷被打到 0 → 停在 1、被打倒、不死；已經重傷再被打到 0 → 死亡
#   3. 灰熊來搶你的殘骸：交給本能打完，結果寫回（撤出帶肉 → 吃下去、殘骸沒了；對手走了 → 殘骸留下）
#   4. 從熊口搶（on_carcass）、遭遇（encounter）、伏擊（ambush）、美洲獅都打得完，時間有前進
#   5. 跟著你的伴侶一起進場，受的傷記在牠身上
#   6. 戰鬥裡學到的（見過幾次）存進主遊戲的知識 combat_move（第 2 步）：帶進下一場、學到時跳通知、照常過日子最多到「通常」
#   7. 自動玩家 play_combat 走戰術戰鬥、不會卡住
# 用法：bash tools/run_sim.sh tactical_combat_game
var gs
var gt
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _fresh() -> void:
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	gs.wolf.health_max = 110.0
	gs.wolf.health = 110.0
	gs.wolf.speed = 62.0
	gs.wolf.strength = 70.0
	gs.wolf.skill = 60.0
	gs.wolf.perception = 60.0
	gs.wolf.hunger = 50.0

# 有伴侶與 n_young 隻滿 2 歲、跟著你的子女（照 pack_hunt_rules 的 _pack）
func _with_pack(n_young: int):
	_fresh()
	gs.wolf.age_years = 4.0
	gs.pending_events.clear()
	gs._spawn_she_wolf()
	var m = gs.she_wolf()
	m.territory = gs.current_region
	m.relation = 8
	gs.she_approach()
	gs.pending_events.clear()
	gt.season_index = 0
	gs.breeding()["pregnant"] = true
	gs.breeding()["winter_fed"] = 1.0
	gs._give_birth()
	gs.pending_events.clear()
	var ps: Array = gs.pups()
	for i in ps.size():
		if i < n_young:
			ps[i].age_years = 2.0
			gs._grow_young()
			ps[i].task = "follow"
		else:
			ps[i].die("test")
	m.task = "follow"
	gs.breeding().erase("prev_task")
	gt.season_index = 2
	return m

# 單位不重疊、都站在走得過去的格子
func _no_overlap(tc) -> bool:
	var seen := {}
	for u in tc.units:
		if seen.has(u["pos"]) or "cTt".contains(tc.map.terrain(u["pos"])):
			return false
		seen[u["pos"]] = true
	return true

func _run() -> void:
	print("== 1. 哪些走戰術戰鬥")
	_fresh()
	_check(gs.uses_tactical_combat(gs.start_combat("grizzly_bear", "adult", "encounter")), "灰熊走戰術戰鬥")
	_check(gs.uses_tactical_combat(gs.start_combat("cougar", "adult", "encounter")), "美洲獅走戰術戰鬥")
	_check(gs.uses_tactical_combat(gs.start_combat("black_bear", "adult", "carcass")), "黑熊走戰術戰鬥（第 3 步）")
	_check(not gs.uses_tactical_combat(gs.start_combat("red_fox", "adult", "carcass")), "狐狸還是選單式")
	gs.tactical_combat_off = true
	_check(not gs.uses_tactical_combat(gs.start_combat("grizzly_bear", "adult", "encounter")), "關掉時灰熊也是選單式")
	gs.tactical_combat_off = false

	print("== 2. 被打倒與死亡")
	_fresh()
	var c = gs.start_combat("grizzly_bear", "adult", "encounter")
	var tc: TacticalCombat = gs.start_tactical_combat(c)
	var r: Dictionary = tc.hurt_hook.call(0, 999.0, tc.enemy_index())
	_check(not r["died"] and r["knocked"] and gs.wolf.health >= 1.0 and gs.wolf.alive, "健康時被打很重：停在 %.0f、被打倒、沒死" % gs.wolf.health)
	var r2: Dictionary = tc.hurt_hook.call(0, 999.0, tc.enemy_index())
	_check(r2["died"], "已經重傷再被打到 0：死亡")
	_fresh()
	gs.wolf.health = 20.0 # 開打時就在重傷線以下
	c = gs.start_combat("grizzly_bear", "adult", "encounter")
	tc = gs.start_tactical_combat(c)
	r = tc.hurt_hook.call(0, 50.0, tc.enemy_index())
	_check(r["died"], "開打時已經重傷，被打到 0：死亡")
	# 戰鬥裡的單位：死了算 died 結束
	_fresh()
	c = gs.start_combat("grizzly_bear", "adult", "encounter")
	tc = gs.start_tactical_combat(c)
	gs.wolf.health = 10.0
	tc.units[0]["hp"] = 10.0
	tc._hurt(0, 50.0, tc.enemy_index())
	tc._check_end()
	_check(tc.done and tc.outcome == "died", "戰鬥裡重傷後被打倒 → 結束、died（%s）" % tc.outcome)
	gs.apply_tactical_combat(c, tc)
	gs.finish_combat(c)
	_check(not gs.wolf.alive, "寫回主遊戲：狼死了（死因 %s）" % gs.wolf.death_cause)

	print("== 3. 灰熊來搶你的殘骸（各 40 場）")
	var outs := {}
	var fed_ok := 0
	var fed_n := 0
	var kept_ok := 0
	var kept_n := 0
	var turns_moved := 0
	for i in 40:
		_fresh()
		gs.start_feeding("elk", "adult", "forest_edge")
		var seg0: int = int(gs.current_feeding.get("segments_left", 0))
		var h0: float = gs.wolf.hunger
		var t0: int = gt.day * 1000 + gt.period_index * 100 + gt.turn_in_period + gt.season_index * 100000
		c = gs.start_combat("grizzly_bear", "adult", "carcass")
		tc = gs.auto_tactical_combat(c)
		var oc: String = c.outcome
		gs.finish_combat(c)
		outs[oc] = int(outs.get(oc, 0)) + 1
		var t1: int = gt.day * 1000 + gt.period_index * 100 + gt.turn_in_period + gt.season_index * 100000
		if t1 > t0:
			turns_moved += 1
		if oc == "grab":
			fed_n += 1
			if gs.wolf.hunger > h0 and gs.current_feeding.is_empty():
				fed_ok += 1
		elif oc in ["drove_off", "parted"]:
			kept_n += 1
			if not gs.current_feeding.is_empty() and int(gs.current_feeding["segments_left"]) <= seg0:
				kept_ok += 1
	print("    結果：", outs)
	_check(fed_ok == fed_n, "撤出帶肉：吃下去、殘骸沒了（%d／%d）" % [fed_ok, fed_n])
	_check(kept_ok == kept_n, "對手走了：殘骸還在、段數沒變多（%d／%d）" % [kept_ok, kept_n])
	_check(turns_moved == 40, "每場時間都有前進（%d／40）" % turns_moved)

	print("== 4. 其他情境打得完")
	for case in [["grizzly_bear", "carcass", "on_carcass"], ["grizzly_bear", "encounter", ""], ["cougar", "encounter", "ambush"], ["cougar", "carcass", ""], ["black_bear", "carcass", ""], ["black_bear", "encounter", ""]]:
		var done_n := 0
		var rounds := 0
		for i in 15:
			_fresh()
			if str(case[1]) == "carcass":
				gs.start_feeding("mule_deer", "adult", "dense_forest")
			c = gs.start_combat(str(case[0]), "adult", str(case[1]))
			if str(case[2]) != "":
				c.set_meta("tc_layout", str(case[2]))
			tc = gs.auto_tactical_combat(c)
			gs.finish_combat(c)
			if tc.done:
				done_n += 1
			rounds += tc.rounds
		_check(done_n == 15, "%s／%s／%s：15 場都打完（平均 %.1f 回合）" % [case[0], case[1], case[2] if case[2] != "" else "預設", float(rounds) / 15.0])

	print("== 5. 伴侶一起進場")
	_fresh()
	var mate = load("res://scripts/core/NpcWolf.gd").new()
	mate.id = "test_mate"
	mate.health = 100.0
	mate.health_max = 100.0
	gs.npcs[mate.id] = mate
	c = gs.start_combat("grizzly_bear", "adult", "encounter")
	c.set_meta("follower", mate.id)
	tc = gs.start_tactical_combat(c)
	var mi: int = tc.index_of("mate")
	_check(mi >= 0, "伴侶在場上")
	if mi >= 0:
		tc._hurt(mi, 30.0, tc.enemy_index())
		gs.apply_tactical_combat(c, tc)
		_check(absf(mate.health - 70.0) < 0.6, "伴侶被打 30：血量記在牠身上（%.0f）" % mate.health)

	print("== 6. 學到的存起來")
	_fresh()
	# 單場可能一開打就結束、沒看到招式：最多打 5 場
	var any := 0
	for t in 5:
		c = gs.start_combat("grizzly_bear", "adult", "encounter")
		tc = gs.auto_tactical_combat(c)
		for k in gs.knowledge.keys():
			if str(k).begins_with("combat_move|grizzly_bear|"):
				any += int(gs.knowledge[k]["count"])
		if any > 0:
			break
		gs.wolf.health = gs.wolf.health_max
	_check(any > 0, "主遊戲的知識有 combat_move（合計 %d）" % any)
	# 第 2 步：主遊戲的知識帶進下一場（見過幾次 → 預告看得比較清楚）
	gs.knowledge[gs.knowledge_key({"type": "combat_move", "animal": "grizzly_bear", "move": "swipe"})] = {"type": "combat_move", "animal": "grizzly_bear", "move": "swipe", "count": 3}
	c = gs.start_combat("grizzly_bear", "adult", "encounter")
	tc = gs.start_tactical_combat(c)
	_check(tc.know_count("grizzly_bear", "swipe") == 3, "確定的知識帶進戰鬥：揮掌見過 3 次（%d）" % tc.know_count("grizzly_bear", "swipe"))
	# 戰鬥裡多看到一次 → 學到（跳「你學到」）
	_fresh()
	var learned := []
	var cb := func(e): if str(e.get("type", "")) == "combat_move": learned.append(e)
	gs.knowledge_learned.connect(cb)
	c = gs.start_combat("grizzly_bear", "adult", "encounter")
	tc = gs.start_tactical_combat(c)
	tc.learn("grizzly_bear", "charge")
	tc.learn("grizzly_bear", "charge")
	gs.apply_tactical_combat(c, tc)
	gs.knowledge_learned.disconnect(cb)
	var lv: int = gs.knowledge_level({"type": "combat_move", "animal": "grizzly_bear", "move": "charge"})
	_check(lv == 2 and learned.size() == 2, "戰鬥裡看到衝撞 2 次 → 知識【通常】、跳 2 次學到（%d、%d）" % [lv, learned.size()])
	# 照常過日子：最多到「通常」
	_fresh()
	gs.routine_running = true
	c = gs.start_combat("grizzly_bear", "adult", "encounter")
	tc = gs.start_tactical_combat(c)
	for k in 3:
		tc.learn("grizzly_bear", "swipe")
	gs.apply_tactical_combat(c, tc)
	gs.routine_running = false
	lv = gs.knowledge_level({"type": "combat_move", "animal": "grizzly_bear", "move": "swipe"})
	_check(lv == 2, "照常過日子時最多到【通常】（%d）" % lv)

	print("== 8. 狼對狼（第 4 步）")
	_fresh()
	gs.wolf.strength = 90.0
	var sw = gs.stranger()
	_check(sw != null, "有黑狼")
	if sw != null:
		c = gs.start_stranger_combat("meet")
		_check(gs.uses_tactical_combat(c), "黑狼走戰術戰鬥")
		tc = gs.start_tactical_combat(c)
		var ei: int = tc.enemy_index()
		_check(absf(float(tc.units[ei]["stats"]["strength"]) - sw.strength) < 0.01 and absf(float(tc.units[ei]["hp_max"]) - sw.health_max) < 0.01, "黑狼的能力、血量照牠自己的")
		# 牠示弱 → 接著選放牠走／追擊
		tc.units[ei]["out"] = true
		tc.units[ei]["out_reason"] = "submit"
		tc._check_end()
		gs.apply_tactical_combat(c, tc)
		var ids: Array = c.options().map(func(o): return str(o["id"]))
		_check(c.opp_submitted and c.phase != _phase_done() and ids.has("let_go") and ids.has("pursue"), "牠示弱：接著可以放牠走或追擊（%s）" % str(ids))
		c.choose("let_go")
		gs.finish_combat(c)
		_check(c.outcome == "drove_off", "放牠走＝打贏（%s）" % c.outcome)
		# 你示弱
		_fresh()
		c = gs.start_stranger_combat("meet")
		tc = gs.start_tactical_combat(c)
		tc.plan(0, {"action": "submit"})
		tc.begin_round()
		tc.plan(0, {"action": "submit"})
		tc.resolve()
		gs.apply_tactical_combat(c, tc)
		_check(c.outcome == "submit", "你示弱：outcome submit（%s）" % c.outcome)
		gs.finish_combat(c)
		# 自動玩家打完
		_fresh()
		var ap2 = load("res://scripts/core/AutoPlayer.gd").new("all", "assault")
		var c2 = gs.start_stranger_combat("territory")
		ap2.play_combat(c2)
		_check(c2.phase == _phase_done() and c2.outcome != "", "自動玩家對黑狼打完（%s）" % c2.outcome)
		_fresh()
		var c3 = gs.start_challenger_combat("meet")
		_check(gs.uses_tactical_combat(c3), "年輕挑戰者走戰術戰鬥")
		ap2.play_combat(c3)
		_check(c3.phase == _phase_done(), "自動玩家對挑戰者打完（%s）" % c3.outcome)

	print("== 9. 多隻（第 5 步）")
	var mate9 = _with_pack(3)
	var fol: Array = gs.followers()
	_check(fol.size() == 4, "伴侶＋3 隻子女跟著你（%d）" % fol.size())
	c = gs.start_combat("grizzly_bear", "adult", "encounter")
	tc = gs.start_tactical_combat(c)
	var allies9: Array = range(tc.units.size()).filter(func(k): return str(tc.units[k]["side"]) == "ally")
	_check(allies9.size() == 3 and tc.index_of("mate") >= 0 and tc.index_of("member_1") >= 0 and tc.index_of("member_2") >= 0, "你這邊最多 4 隻：伴侶＋2 隻成員（%d）" % allies9.size())
	_check(_no_overlap(tc), "進場的位置不重疊、走得過去")
	# 每種起始位置 × 20 張地圖（含殘骸）都不重疊
	var bad := []
	for lay in ["arrives", "on_carcass", "encounter", "ambush"]:
		for t9 in 20:
			gs.current_feeding = {"animal_id": "elk", "segments_left": 6, "terrain": "forest_edge"}
			var cc9 = gs.start_combat("grizzly_bear", "adult", "carcass" if lay in ["arrives", "on_carcass"] else "encounter")
			cc9.set_meta("tc_layout", lay)
			var tt = gs.start_tactical_combat(cc9)
			var ok9: bool = _no_overlap(tt) and (tt.carcass.is_empty() or not tt.units.any(func(u): return u["pos"] == tt.carcass["pos"]))
			if not ok9:
				bad.append(lay)
	gs.current_feeding = {}
	_check(bad.is_empty(), "四種起始位置各 20 張地圖都不重疊（%s）" % str(bad))
	var mem: Dictionary = c.get_meta("tc_members", {})
	_check(str(mem.get("mate", "")) == mate9.id, "可以下指令的是伴侶")
	# 成員的傷寫回：被打 20、另一隻倒下
	var m1: int = tc.index_of("member_1")
	var n1 = gs.npcs[str(mem["member_1"])]
	var hp_before: float = n1.health
	tc._hurt(m1, 20.0, tc.enemy_index())
	var m2: int = tc.index_of("member_2")
	var n2 = gs.npcs[str(mem["member_2"])]
	tc.units[m2]["hp"] = 5.0
	tc._hurt(m2, 30.0, tc.enemy_index())
	gs.apply_tactical_combat(c, tc)
	_check(absf(n1.health - (hp_before - 20.0)) < 0.6, "成員被打 20：記在牠身上（%.0f → %.0f）" % [hp_before, n1.health])
	_check(not n2.alive, "重傷的成員還留在場上被打到 0：死亡")
	# 苔原狼一對：兩隻都進場、能力照各自的
	_fresh()
	var pair: Array = gs.tundra_pair()
	_check(pair.size() == 2, "苔原狼有一對")
	if pair.size() == 2:
		c = gs.start_tundra_combat("meet")
		_check(gs.uses_tactical_combat(c), "苔原狼走戰術戰鬥")
		tc = gs.start_tactical_combat(c)
		var foes9: Array = tc.enemies()
		_check(foes9.size() == 2 and absf(float(tc.units[foes9[1]]["hp_max"]) - pair[1].health_max) < 0.01, "兩隻苔原狼都進場、第二隻照牠自己的血量")
		_check(_no_overlap(tc), "苔原狼的位置不重疊")
		for k in foes9:
			tc.units[k]["out"] = true
			tc.units[k]["out_reason"] = "fled"
		tc.units[foes9[1]]["hp"] = 40.0
		tc._check_end()
		_check(tc.outcome == "routed", "兩隻都走了：routed（%s）" % tc.outcome)
		gs.apply_tactical_combat(c, tc)
		_check(c.outcome == "drove_off" and absf(pair[1].health - 40.0) < 0.6, "＝打贏、第二隻的傷寫回（%s、%.0f）" % [c.outcome, pair[1].health])
		gs.finish_combat(c)
		_fresh()
		var ap9 = load("res://scripts/core/AutoPlayer.gd").new("all", "assault")
		var c9 = gs.start_tundra_combat("carcass")
		ap9.play_combat(c9)
		_check(c9.phase == _phase_done(), "自動玩家對一對苔原狼打完（%s）" % c9.outcome)
	# 鄰群：撲上去打改成戰術戰鬥
	_with_pack(1)
	gs.current_region = "mountain_canyon"
	gs.meet_pack_id = "mountain"
	var mp = gs.pack_by_id("mountain")
	mp.young = [1.5, 2.0, 0.5]
	_check(gs.uses_tactical_pack_fight(), "鄰群的衝突走戰術戰鬥")
	tc = gs.start_pack_tactical()
	_check(tc.enemies().size() == 3 and str(tc.units[tc.enemy_index()]["species"]) == "pack_wolf", "牠們帶頭的＋2 隻進場（%d）" % tc.enemies().size())
	_check(_no_overlap(tc), "鄰群的位置不重疊")
	for k in tc.enemies():
		tc.units[k]["out"] = true
		tc.units[k]["out_reason"] = "submit"
	tc._check_end()
	var r9: Dictionary = gs.finish_pack_tactical(tc)
	_check(r9["won"] and mp.young.size() == 2 and gs.pack_attitude_of(mp) == "wary", "牠們都退走＝打贏：少一隻年輕的、之後戒備你")
	gs.current_region = "mountain_canyon"
	tc = gs.start_pack_tactical()
	tc.plan(0, {"action": "submit"})
	tc.begin_round()
	tc.plan(0, {"action": "submit"})
	tc.resolve()
	r9 = gs.finish_pack_tactical(tc)
	_check(not r9["won"] and gs.current_region != "mountain_canyon", "你示弱＝輸：被趕走（%s）" % gs.current_region)
	gs.current_region = "mountain_canyon"
	r9 = gs.auto_pack_tactical()
	_check(r9.has("won"), "交給本能打得完（%s）" % ("贏" if r9["won"] else ("各自退開" if r9.get("parted", false) else "輸")))
	gs.tactical_combat_off = true
	_check(not gs.uses_tactical_pack_fight(), "對照組：選單式")
	gs.tactical_combat_off = false

	print("== 10. 郊狼一對來偷殘骸（Phase 2l 第 1 步，40 場）")
	_fresh()
	gs.start_feeding("elk", "adult", "open")
	var cc10 = gs.start_combat("coyote", "adult", "carcass")
	_check(gs.uses_tactical_combat(cc10), "郊狼走戰術戰鬥")
	var tt10 = gs.start_tactical_combat(cc10)
	_check(tt10.enemies().size() == 2, "郊狼一對進場（%d 隻）" % tt10.enemies().size())
	var roles10: Array = tt10.enemies().map(func(k): return str(tt10.units[k].get("role", "")))
	_check(roles10.has("decoy") and roles10.has("thief"), "一隻引開、一隻去偷（%s）" % str(roles10))
	_check(_no_overlap(tt10), "起始位置不重疊")
	gs.current_feeding = {}
	var ok10 := 0
	var sum_ok := 0
	var stole10 := 0
	for t10 in 40:
		_fresh()
		gs.start_feeding("elk", "adult", "open")
		var seg10: int = int(gs.current_feeding["segments_left"])
		var c10 = gs.start_combat("coyote", "adult", "carcass")
		var tc10 = gs.auto_tactical_combat(c10)
		if tc10.done:
			ok10 += 1
		stole10 += tc10.meat_stolen()
		var left10: int = int(c10.get_meta("tc_left", 0))
		var kept10: int = int(gs.current_feeding.get("segments_left", 0)) if not gs.current_feeding.is_empty() else 0
		# 開場的段數 = 被偷走 + 留下（殘骸＋地上）+ 你帶走；牠們都走了時留下的寫回主遊戲
		if seg10 == tc10.meat_stolen() + left10 + tc10.meat_taken() and (c10.outcome != "drove_off" or kept10 == left10):
			sum_ok += 1
		gs.finish_combat(c10)
	_check(ok10 == 40, "40 場都打得完（%d）" % ok10)
	_check(sum_ok == 40, "肉的段數對得上、留下的寫回主遊戲（%d／40）" % sum_ok)
	_check(stole10 > 0 and stole10 < 40 * 3, "有時會被偷走（40 場共 %d 段）" % stole10)

	print("== 7. 自動玩家")
	_fresh()
	var ap = load("res://scripts/core/AutoPlayer.gd").new("all", "average")
	gs.start_feeding("elk", "adult", "forest_edge")
	ap.play_combat(gs.start_combat("grizzly_bear", "adult", "carcass"))
	_check(gs.life_log.get("stats", {}).get("combat", {}).keys().any(func(k): return str(k).contains(".tactical.")), "play_combat 走戰術戰鬥")

	print("全部通過" if fails == 0 else "失敗 %d 項" % fails)
	quit(1 if fails > 0 else 0)

# Combat.gd 用到自動載入的 GameData，-s 腳本不能在編譯時直接引用 Combat，改成執行時載入
func _phase_done() -> int:
	return int(load("res://scripts/core/Combat.gd").Phase.DONE)
