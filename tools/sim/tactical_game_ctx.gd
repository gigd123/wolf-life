extends SceneTree
# Phase 2c 第 1 步「原型邏輯搬進主遊戲、讀主遊戲的狀態」的回歸測試（TacticalHunt.setup_from_game、GameState.tactical_context）：
#   1. 狼的能力值、體況照主遊戲
#   2. 吃撐：喘的上限 ×0.6、不能衝刺
#   3. 年齡：撲咬、壓倒、咬喉扣年齡減成
#   4. 晨昏：看見你的警覺漲得慢
#   5. 深雪：鹿每回合少跑一格
#   6. 相對風向：下風時風從鹿吹向你、上風相反
#   7. 地形 → 地圖（密林、林緣 → C；倒木、岩石 → D；其他 → A）
# 用法：bash tools/run_sim.sh tactical_game_ctx
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var base := {"map": "A", "seed": 5, "condition": "healthy",
		"wolf": {"speed": 70.0, "skill": 65.0, "strength": 75.0, "perception": 60.0, "stamina": 80.0, "health": 100.0, "health_max": 110.0}}
	var h = TH.new()
	h.setup_from_game(base)
	_check(float(h.wolf["speed"]) == 70.0 and float(h.wolf["strength"]) == 75.0 and h.condition == "healthy", "能力值、體況照主遊戲")
	var bmax: float = h.breath_max
	var sprint: float = h.max_move()
	# 2. 吃撐
	var g = TH.new()
	var gctx := base.duplicate(true)
	gctx["gorged"] = true
	g.setup_from_game(gctx)
	_check(absf(g.breath_max - bmax * 0.6) < 0.01 and g.max_move() < sprint, "吃撐：喘 ×0.6（%.1f → %.1f）、不能衝刺（%.1f → %.1f）" % [bmax, g.breath_max, sprint, g.max_move()])
	# 3. 年齡：把狼放到鹿旁邊比撲咬機率
	var y = TH.new()
	y.setup_from_game(base)
	var o = TH.new()
	var octx := base.duplicate(true)
	octx["age_penalty"] = 0.12
	o.setup_from_game(octx)
	for x in [y, o]:
		x.wolf_pos = x.deer_pos - Vector2i(1, 0)
	var py: float = float(y.pounce_chance()["chance"])
	var po: float = float(o.pounce_chance()["chance"])
	_check(absf(py - po - 0.12) < 0.001, "年齡：撲咬 −0.12（%.2f → %.2f）" % [py, po])
	_check(o.pounce_chance()["factors"].any(func(fa): return str(fa[0]) == "你老了"), "年齡：因素寫「你老了」")
	# 4. 晨昏
	var tw = TH.new()
	var tctx := base.duplicate(true)
	tctx["twilight"] = true
	tw.setup_from_game(tctx)
	for x in [y, tw]:
		x.wolf_pos = x.deer_pos - Vector2i(6, 0)
	_check(float(tw.alert_gain("creep")["noise"]) < float(y.alert_gain("creep")["noise"]), "晨昏：看見你的警覺漲得慢")
	# 5. 深雪
	var sn = TH.new()
	var sctx := base.duplicate(true)
	sctx["deep_snow"] = true
	sn.setup_from_game(sctx)
	sn.flee_round = 1
	y.flee_round = 1
	_check(absf(y._flee_budget() - sn._flee_budget() - 1.0) < 0.001, "深雪：鹿少跑一格（%.0f → %.0f）" % [y._flee_budget(), sn._flee_budget()])
	# 6. 相對風向
	var w1 = TH.new()
	var wctx := base.duplicate(true)
	wctx["wind_relation"] = "headwind"
	w1.setup_from_game(wctx)
	_check(w1.wind_side() == "downwind", "下風：%s" % w1.wind_side())
	wctx["wind_relation"] = "tailwind"
	w1.setup_from_game(wctx)
	_check(w1.wind_side() == "upwind", "上風：%s" % w1.wind_side())
	# 7. 地形 → 地圖
	var gs = root.get_node("GameState")
	gs.new_game("forest_east")
	_check(gs.tactical_context("dense_forest", "headwind", "weak")["map"] == "C" and gs.tactical_context("fallen_logs", "headwind", "weak")["map"] == "D" \
		and gs.tactical_context("clearing", "headwind", "weak")["map"] == "A", "地形 → 地圖")
	var ctx: Dictionary = gs.tactical_context("clearing", "headwind", "weak")
	var m = TH.new()
	m.setup_from_game(ctx)
	_check(absf(float(m.wolf["speed"]) - gs.wolf.effective_speed()) < 0.001 and m.condition == "weak", "GameState 的狼帶進戰術地圖")
	# 8. 第 2 步：主遊戲開一場、打完、結果接回（獵到 → 進食；放棄 → 紀錄；時間、體力、受傷）
	var AP = load("res://tools/sim/tactical_hunt_sim.gd")
	var pol = AP.new()
	var outcomes := {}
	for i in 40:
		root.get_node("RNGService").set_seed(300 + i)
		gs.new_game("forest_east")
		gs.debug_force_transition("adult")
		gs.wolf.stamina = 80.0
		var hunt = gs.start_hunt("white_tailed_deer", "juvenile" if i % 5 == 0 else "adult")
		if not gs.tactical_eligible(hunt):
			_check(false, "白尾鹿應該用戰術地圖")
			break
		var th = gs.start_tactical(hunt)
		if hunt.life_stage == "juvenile":
			_check(th.is_fawn(th.target), "幼鹿：目標是幼鹿")
		var t0: int = root.get_node("GameTime").day * 100 + root.get_node("GameTime").period_index * 10 + root.get_node("GameTime").turn_in_period
		var st0: float = gs.wolf.stamina
		var hp0: float = gs.wolf.health
		var tries0: int = int(gs.life_log.get("hunt_attempts", 0))
		if i % 7 == 3:
			th.give_up()
		else:
			pol._play(th, "stalk")
		var dmg: float = th.damage_taken
		gs.finish_tactical_hunt(hunt, th)
		outcomes[th.result] = int(outcomes.get(th.result, 0)) + 1
		var t1: int = root.get_node("GameTime").day * 100 + root.get_node("GameTime").period_index * 10 + root.get_node("GameTime").turn_in_period
		_check(t1 > t0, "時間有前進（%s）" % th.result)
		_check(gs.wolf.stamina < st0, "體力有扣（%.1f → %.1f）" % [st0, gs.wolf.stamina])
		_check(dmg <= 0.0 or gs.wolf.health < hp0, "被踢：血量有扣")
		_check(int(gs.life_log.get("hunt_attempts", 0)) == tries0 + 1, "狩獵紀錄 +1")
		match th.result:
			"caught":
				_check(gs.is_feeding() and hunt.result == 1, "獵到：進入進食")
			"gave_up":
				_check(hunt.result == 3, "放棄：記為放棄")
			_:
				_check(hunt.result == 2 and gs.current_discovery.get("fled", false), "逃走：留下足跡（%s）" % th.result)
	print("結果：", outcomes)
	pol.free()
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
