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
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
