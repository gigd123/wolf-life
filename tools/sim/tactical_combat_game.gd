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

func _run() -> void:
	print("== 1. 哪些走戰術戰鬥")
	_fresh()
	_check(gs.uses_tactical_combat(gs.start_combat("grizzly_bear", "adult", "encounter")), "灰熊走戰術戰鬥")
	_check(gs.uses_tactical_combat(gs.start_combat("cougar", "adult", "encounter")), "美洲獅走戰術戰鬥")
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
	for case in [["grizzly_bear", "carcass", "on_carcass"], ["grizzly_bear", "encounter", ""], ["cougar", "encounter", "ambush"], ["cougar", "carcass", ""]]:
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
	c = gs.start_combat("grizzly_bear", "adult", "encounter")
	tc = gs.auto_tactical_combat(c)
	var any := 0
	for k in gs.knowledge.keys():
		if str(k).begins_with("combat_move|grizzly_bear|"):
			any += int(gs.knowledge[k]["count"])
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

	print("== 7. 自動玩家")
	_fresh()
	var ap = load("res://scripts/core/AutoPlayer.gd").new("all", "average")
	gs.start_feeding("elk", "adult", "forest_edge")
	ap.play_combat(gs.start_combat("grizzly_bear", "adult", "carcass"))
	_check(gs.life_log.get("stats", {}).get("combat", {}).keys().any(func(k): return str(k).contains(".tactical.")), "play_combat 走戰術戰鬥")

	print("全部通過" if fails == 0 else "失敗 %d 項" % fails)
	quit(1 if fails > 0 else 0)
