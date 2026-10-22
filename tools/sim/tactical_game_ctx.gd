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
	_check(gs.tactical_context("dense_forest", "headwind", "weak")["family"] == "dense" and gs.tactical_context("stream", "headwind", "weak")["family"] == "stream" \
		and gs.tactical_context("prairie", "headwind", "weak")["family"] == "open", "地形 → 地圖族（第 4 步）")
	# 第 4 步：每種地圖族都開得起來、狼與鹿不在倒木上、鹿在開闊處、目的地在 5～9 格外
	for fam in ["open", "edge", "dense", "stream", "logs", "slope", "tundra", "river"]:
		for sd in 10:
			var fh = TH.new()
			fh.setup_from_game({"family": fam, "seed": sd * 31 + 7, "condition": "healthy", "fawn": sd % 3 == 0, "wolf": base["wolf"], "wind_relation": "headwind"})
			_check(fh.terrain(fh.deer_pos) == "." and fh.terrain(fh.wolf_pos) != "l", "%s：鹿在開闊處、狼不在倒木上" % fam)
			_check(fh.dist(fh.wolf_pos, fh.deer_pos) >= 6.0, "%s：狼離鹿夠遠（%.1f）" % [fam, fh.dist(fh.wolf_pos, fh.deer_pos)])
			_check(fh.wind_side() == "downwind", "%s：下風（%s）" % [fam, fh.wind_side()])
			if sd % 3 == 0:
				_check(fh.herd.size() == 2 and fh.is_fawn(1), "%s：幼鹿跟在母鹿旁邊" % fam)
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
	# 9. Phase 2d 第 2 步：馬鹿（母鹿、小鹿走戰術地圖，公鹿照舊走選單）、鹿群、觀察標出最弱的、獵到的是哪一隻
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	_check(gs.tactical_eligible(gs.start_hunt("elk", "adult")) and gs.tactical_eligible(gs.start_hunt("elk", "juvenile")), "馬鹿：母鹿、小鹿走戰術地圖")
	_check(gs.tactical_eligible(gs.start_hunt("elk", "buck")), "公馬鹿也走戰術地圖（Phase 2f）")
	var bh = gs.start_hunt("elk", "buck")
	bh.set_herd(true)
	var bth = gs.start_tactical(bh)
	_check(bth.herd.all(func(d): return str(d["species"]) == "elk_bull" and str(d["kind"]) == "adult") and bth.herd.size() >= 2 and bth.herd.size() <= 4, "公馬鹿的小群：2～4 隻、都是公鹿、沒有小鹿（%d）" % bth.herd.size())
	for i in 30:
		root.get_node("RNGService").set_seed(900 + i)
		var eh = gs.start_hunt("elk", "adult")
		eh.set_herd(true)
		var eth = gs.start_tactical(eh)
		var adults: int = eth.herd.filter(func(d): return str(d["kind"]) == "adult").size()
		_check(adults >= 4 and adults <= 7, "馬鹿鹿群：成鹿 4～7 隻（%d）" % adults)
		_check(eth.herd.all(func(d): return str(d["species"]) in ["elk", "elk_calf"]), "馬鹿鹿群：都是馬鹿")
		_check(eth.herd.all(func(d): return eth.terrain(d["pos"]) == "."), "馬鹿鹿群：都在開闊處")
		eth.observe()
		var worst := "healthy"
		for d in eth.herd:
			if str(d["kind"]) == "adult" and str(d["condition"]) != "healthy" and (worst == "healthy" or str(d["condition"]) == "weak"):
				worst = str(d["condition"])
		var marked: Array = eth.herd.filter(func(d): return bool(d.get("weakest", false)))
		_check((worst == "healthy" and marked.is_empty()) or (marked.size() == 1 and str(marked[0]["condition"]) == worst), "觀察鹿群：標出最弱的那一隻（%s）" % worst)
	# 獵到小馬鹿 → 記成小鹿
	var ch = gs.start_hunt("elk", "juvenile")
	var cth = gs.start_tactical(ch)
	_check(cth.is_fawn(cth.target) and cth.label(cth.target) == "小馬鹿", "馬鹿小鹿：目標是小馬鹿（%s）" % cth.label(cth.target))
	cth._finish("caught", "test")
	gs.finish_tactical_hunt(ch, cth)
	_check(ch.life_stage == "juvenile" and gs.is_feeding(), "獵到小馬鹿：記成小鹿、進入進食")
	if gs.is_feeding():
		gs.leave_feeding()
	# 幼鹿那一場換目標獵到母鹿 → 記成成鹿
	var mh = gs.start_hunt("white_tailed_deer", "juvenile")
	var mth = gs.start_tactical(mh)
	for k in mth.herd.size():
		if not mth.is_fawn(k):
			mth.set_target(k)
	mth._finish("caught", "test")
	gs.finish_tactical_hunt(mh, mth)
	_check(mh.life_stage == "adult", "幼鹿那一場換目標獵到母鹿：記成成鹿（%s）" % mh.life_stage)
	# 10. Phase 2d 第 3 步：騾鹿（岩坡地圖、物種的地形代價）
	_check(gs.tactical_eligible(gs.start_hunt("mule_deer", "adult")) and gs.tactical_eligible(gs.start_hunt("mule_deer", "buck")), "騾鹿：成鹿、公鹿走戰術地圖")
	_check(gs.tactical_context("scree", "headwind", "weak")["family"] == "slope" and gs.tactical_context("cliff", "headwind", "weak")["family"] == "slope", "碎石坡、崖邊 → 岩坡地圖")
	var mu = gs.start_hunt("mule_deer", "adult")
	mu.terrain = "scree"
	var muth = gs.start_tactical(mu)
	_check(str(muth.herd[muth.target]["species"]) == "mule_deer" and muth.label(muth.target) in ["騾鹿", "牠"], "騾鹿：物種與稱呼（%s）" % muth.label(muth.target))
	var rock := Vector2i(-1, -1)
	for ry in muth.height:
		for rx in range(1, muth.width):
			if muth.terrain(Vector2i(rx, ry)) == "r" and muth.terrain(Vector2i(rx - 1, ry)) == ".":
				rock = Vector2i(rx, ry)
	_check(rock.x >= 0, "岩坡地圖上有岩坡")
	if rock.x >= 0:
		_check(muth.deer_extra(rock) == 0.0 and muth.step_cost(rock - Vector2i(1, 0), rock) >= 3.0, "岩坡：騾鹿不減速、狼 +2（狼 %.1f）" % muth.step_cost(rock - Vector2i(1, 0), rock))
	var mfh = gs.start_hunt("mule_deer", "juvenile")
	mfh.hiding = false
	var mfth = gs.start_tactical(mfh)
	_check(mfth.label(mfth.target) == "騾鹿幼鹿", "騾鹿幼鹿：稱呼（%s）" % mfth.label(mfth.target))
	# 11. Phase 2d 第 4 步：馴鹿（苔原、河谷、水格；一律成群；母鹿不護幼）
	_check(gs.tactical_context("open_tundra", "headwind", "weak")["family"] == "tundra" and gs.tactical_context("river_willow", "headwind", "weak")["family"] == "river", "苔原 → 苔原地圖、柳叢河谷 → 河谷地圖")
	_check(gs.tactical_context("river", "headwind", "weak")["family"] == "stream", "森林的河照舊是溪邊地圖")
	var cb = gs.start_hunt("caribou", "adult")
	cb.terrain = "river_willow"
	var cbth = gs.start_tactical(cb)
	var cb_adults: int = cbth.herd.filter(func(d): return str(d["kind"]) == "adult").size()
	_check(cb.in_herd and cb_adults >= 5 and cb_adults <= 8, "馴鹿：一律成群、5～8 隻（%d）" % cb_adults)
	var water := Vector2i(-1, -1)
	var bank := Vector2i(-1, -1)
	for wy in range(1, cbth.height):
		for wx in cbth.width:
			if cbth.terrain(Vector2i(wx, wy)) == "w" and cbth.terrain(Vector2i(wx, wy - 1)) == ".":
				water = Vector2i(wx, wy)
				bank = Vector2i(wx, wy - 1)
	_check(water.x >= 0, "河谷地圖上有河")
	if water.x >= 0:
		cbth.di = cbth.target
		_check(cbth.deer_extra(water) == 0.0 and cbth.step_cost(bank, water) >= 3.0, "河：馴鹿涉水不減速、狼 +2")
	_check(cbth.wolf_pos != Vector2i(-1, -1) and cbth.terrain(cbth.wolf_pos) != "w", "狼不會開局在水裡")
	var cc = gs.start_hunt("caribou", "juvenile")
	var ccth = gs.start_tactical(cc)
	_check(ccth.label(ccth.target) == "小馴鹿", "小馴鹿：稱呼（%s）" % ccth.label(ccth.target))
	# 母鹿不護幼：狼咬住小馴鹿時，母鹿照常逃、不回頭
	var mo: int = int(ccth.herd[ccth.target]["mother"])
	ccth.herd[ccth.target]["held"] = true
	ccth.herd[ccth.target]["state"] = "flee"
	ccth.di = mo
	_check(not ccth._mother_defend(), "馴鹿母鹿不護幼")
	# 12. Phase 2f 第 2 步：駝鹿（成獸單隻、小駝鹿跟著母鹿、密林倒木不減速、母駝鹿護幼更兇）
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	_check(gs.tactical_eligible(gs.start_hunt("moose", "adult")) and gs.tactical_eligible(gs.start_hunt("moose", "juvenile")), "駝鹿：成獸、小駝鹿走戰術地圖")
	var moth = gs.start_tactical(gs.start_hunt("moose", "adult"))
	_check(moth.herd.size() == 1 and str(moth.herd[0]["species"]) == "moose" and moth.label(moth.target) == "牠", "駝鹿單隻、稱呼「牠」（%s）" % moth.label(moth.target))
	var mforest := Vector2i(-1, -1)
	for my in moth.height:
		for mx in moth.width:
			if moth.terrain(Vector2i(mx, my)) == "f":
				mforest = Vector2i(mx, my)
	_check(mforest.x < 0 or moth.deer_extra(mforest) == 0.0, "駝鹿在密林裡不減速")
	var mch = gs.start_tactical(gs.start_hunt("moose", "juvenile"))
	_check(mch.label(mch.target) == "小駝鹿" and str(mch.herd[int(mch.herd[mch.target]["mother"])]["species"]) == "moose", "小駝鹿：稱呼、母親是駝鹿（%s）" % mch.label(mch.target))
	# 母駝鹿護幼：踢中的傷害上限比共用的（14）高
	var mtop := 0
	for i in 200:
		var mmh = gs.start_tactical(gs.start_hunt("moose", "juvenile"))
		var mi_: int = int(mmh.herd[mmh.target]["mother"])
		mmh.herd[mmh.target]["held"] = true
		mmh.herd[mmh.target]["state"] = "flee"
		mmh.wolf_pos = Vector2i(mmh.herd[mmh.target]["pos"])
		mmh.di = mi_
		mmh.deer_pos = Vector2i(mmh.herd[mi_]["pos"])
		mmh._mother_defend()
		for d in mmh.hits_taken:
			mtop = maxi(mtop, int(d))
	_check(mtop > 14, "母駝鹿踢得比母白尾鹿重（最大 %d）" % mtop)
	# 13. Phase 2f 第 3 步：野牛（一律成群 6～10 隻、獵小牛也是整群、成牛擋小牛、小牛在水裡不減速、深雪更慢）
	gs.new_game("grassland_plains")
	gs.debug_force_transition("adult")
	_check(gs.tactical_eligible(gs.start_hunt("bison", "adult")) and gs.tactical_eligible(gs.start_hunt("bison", "juvenile")), "野牛：成牛、小牛走戰術地圖")
	var bah = gs.start_hunt("bison", "adult")
	bah.set_herd(true)
	var bath = gs.start_tactical(bah)
	var badults: int = bath.herd.filter(func(d): return str(d["kind"]) == "adult").size()
	_check(badults >= 6 and badults <= 10 and str(bath.herd[bath.target]["species"]) == "bison", "野牛群 6～10 隻成牛（%d）" % badults)
	var bjh = gs.start_hunt("bison", "juvenile")
	bjh.set_herd(true)
	var bjth = gs.start_tactical(bjh)
	var bjadults: int = bjth.herd.filter(func(d): return str(d["kind"]) == "adult").size()
	_check(bjth.is_fawn(bjth.target) and bjadults >= 6 and bjth.label(bjth.target) == "小野牛", "獵小牛也是整群、目標是小野牛（成牛 %d、%s）" % [bjadults, bjth.label(bjth.target)])
	# 不是牠媽媽的成牛也會擋：把狼放到小牛旁邊、咬住小牛，找一隻不是生母的成牛試
	var guard_ok := false
	for i in 50:
		var gh = gs.start_hunt("bison", "juvenile")
		gh.set_herd(true)
		var gth = gs.start_tactical(gh)
		var calf: int = gth.target
		var mom: int = int(gth.herd[calf]["mother"])
		gth.herd[calf]["held"] = true
		gth.herd[calf]["state"] = "flee"
		gth.wolf_pos = Vector2i(gth.herd[calf]["pos"])
		for j in gth.herd.size():
			if j != mom and not gth.is_fawn(j) and gth.dist(gth.herd[j]["pos"], gth.wolf_pos) <= 3.0:
				gth.di = j
				if gth._mother_defend():
					guard_ok = true
				break
		if guard_ok:
			break
	_check(guard_ok, "不是生母的成牛也會擋小牛")
	# 小牛旁邊有成牛：撲咬有「大野牛擋在牠旁邊」
	bjth.di = bjth.target
	var gfac := false
	for fct in bjth.pounce_chance("still")["factors"]:
		if str(fct[0]) == "大野牛擋在牠旁邊":
			gfac = true
	var near_adult := false
	for j in bjth.herd.size():
		if not bjth.is_fawn(j) and bjth.dist(bjth.herd[j]["pos"], bjth.herd[bjth.target]["pos"]) <= 2.5:
			near_adult = true
	_check(gfac == near_adult, "小牛旁邊有成牛時撲咬減（%s／%s）" % [gfac, near_adult])
	bjth.game_mods["snow_slow"] = 1.0
	# 河邊的牛群也放得下小牛：獵小牛時目標一定是小牛（2026-10-21 截圖發現河邊的野牛群沒有小牛、目標變成成牛）
	var no_calf := 0
	for i in 100:
		for sp_ter in [["bison", "river_willow"], ["bison", ""], ["caribou", "river_willow"], ["elk", ""]]:
			var jh = gs.start_hunt(sp_ter[0], "juvenile", -1, false, sp_ter[1])
			jh.set_herd(true)
			var jth = gs.start_tactical(jh)
			if not jth.is_fawn(jth.target):
				no_calf += 1
	_check(no_calf == 0, "獵小牛、小鹿時目標一定是幼獸（河邊也是；%d 場不是）" % no_calf)
	# 2026-10-22 使用者：落單的野牛（15%）、落單的小牛（一對母子或旁邊沒有成獸）、受傷的野牛帶著傷走戰術地圖、小牛躲到站定的母牛身後
	var lone := 0
	for i in 600:
		if not gs.start_hunt("bison", "adult").in_herd:
			lone += 1
	_check(lone >= 45 and lone <= 100, "野牛約 12%% 落單（%d／600）" % lone)
	var single_n := 0
	var alone_n := 0
	for i in 200:
		var lj = gs.start_hunt("bison", "juvenile", -1, false, "", false, false, 0)
		var ljth = gs.start_tactical(lj)
		if not ljth.is_fawn(ljth.target):
			single_n += 1000
		elif ljth.herd.size() == 1:
			alone_n += 1
		elif ljth.herd.size() == 2:
			single_n += 1
	_check(single_n + alone_n == 200 and alone_n >= 40 and alone_n <= 80, "落單的小牛：約三成旁邊沒有成獸、其餘是一對母子（只有小牛 %d、母子 %d）" % [alone_n, single_n])
	var ih = gs.start_hunt("bison", "adult", -1, false, "", true)
	_check(gs.tactical_eligible(ih), "受傷的野牛走戰術地圖")
	var ith = gs.start_tactical(ih)
	_check(int(ith.herd[ith.target]["wounds"]) == 1 and ith.herd.size() == 1, "受傷的野牛帶著 1 道傷、單獨一頭")
	_check(not gs.tactical_eligible(gs.start_hunt("white_tailed_deer", "adult", -1, false, "", true)), "受傷的白尾鹿照舊走選單")
	# 小牛躲到站定的母牛身後：母牛站定、小牛在逃，下一步小牛到母牛旁邊、離狼比母牛遠
	var hid_ok := false
	for i in 30:
		var ph = gs.start_hunt("bison", "juvenile", -1, false, "", false, false, 0)
		var pth = gs.start_tactical(ph)
		if pth.herd.size() != 2:
			continue
		var calf: int = pth.target
		var mom: int = 1 - calf
		pth.herd[mom]["state"] = "stand"
		pth.herd[calf]["state"] = "flee"
		pth.wolf_pos = Vector2i(pth.herd[mom]["pos"]) + Vector2i(0, 3) if pth.in_bounds(Vector2i(pth.herd[mom]["pos"]) + Vector2i(0, 3)) else Vector2i(pth.herd[mom]["pos"]) + Vector2i(0, -3)
		pth.di = calf
		if pth._huddle_behind_standing():
			hid_ok = pth._cheb(pth.herd[calf]["pos"], pth.herd[mom]["pos"]) <= 1 and pth.dist(pth.herd[calf]["pos"], pth.wolf_pos) >= pth.dist(pth.herd[mom]["pos"], pth.wolf_pos)
			break
	_check(hid_ok, "小野牛躲到站定的母牛身後")
	# 未滿 1 歲（2026-10-22 使用者選 A 加提示）：小獵物、殘骸的倍率；盯上成年的大、中型獵物時有提示，幼鹿、成年狼沒有
	gs.new_game("forest_east")
	_check(not gs.youth_food_mults().is_empty(), "未滿 1 歲有小獵物、殘骸的倍率")
	_check(bool(gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult")).game_mods.get("youth_hint", false)), "小狼盯上成年白尾鹿：有提示")
	_check(not bool(gs.start_tactical(gs.start_hunt("white_tailed_deer", "juvenile")).game_mods.get("youth_hint", false)), "小狼盯上幼鹿：沒有提示")
	gs.wolf.age_years = 2.5
	_check(gs.youth_food_mults().is_empty() and not bool(gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult")).game_mods.get("youth_hint", false)), "成年後沒有倍率、沒有提示")
	# 河狸（2026-10-22）：走戰術地圖、一律水塘地圖、離深水近（1～3 格）或遠（5～8 格）、小河狸單獨出場、進深水就潛走、淺水比陸上快
	gs.new_game("forest_east")
	gs.wolf.age_years = 2.5
	_check(gs.tactical_eligible(gs.start_hunt("beaver", "adult")) and gs.tactical_eligible(gs.start_hunt("beaver", "juvenile")), "河狸、小河狸走戰術地圖")
	var near_ok := 0
	var far_ok := 0
	for i in 40:
		var bh2 = gs.start_hunt("beaver", "adult", -1, false, "stream")
		var bth2 = gs.start_tactical(bh2)
		var dd := 99
		for by in bth2.height:
			for bx in bth2.width:
				if bth2.terrain(Vector2i(bx, by)) == "d":
					dd = mini(dd, bth2._cheb(Vector2i(bx, by), bth2.deer_pos))
		_check(bth2.herd.size() == 1 and str(bth2.herd[0]["species"]) == "beaver" and dd < 99, "河狸單獨一隻、地圖上有深水（水塘）")
		if bh2.refuge_near and dd >= 1 and dd <= 3:
			near_ok += 1
		elif not bh2.refuge_near and dd >= 5 and dd <= 8:
			far_ok += 1
	_check(near_ok + far_ok >= 36, "河狸離深水的距離照近／遠（近 %d、遠 %d／40）" % [near_ok, far_ok])
	var kth = gs.start_tactical(gs.start_hunt("beaver", "juvenile"))
	_check(kth.herd.size() == 1 and kth.label(kth.target) == "牠" and str(kth.herd[0]["species"]) == "beaver_kit", "小河狸單獨出場（沒有母親）")
	var bvh = gs.start_tactical(gs.start_hunt("beaver", "adult"))
	var shallow := Vector2i(-1, -1)
	var deep := Vector2i(-1, -1)
	for by in bvh.height:
		for bx in bvh.width:
			var tt: String = bvh.terrain(Vector2i(bx, by))
			if tt == "s" and shallow.x < 0:
				shallow = Vector2i(bx, by)
			if tt == "d" and deep.x < 0:
				deep = Vector2i(bx, by)
	_check(shallow.x >= 0 and deep.x >= 0 and bvh.deer_extra(deep) < bvh.deer_extra(shallow) and bvh.deer_extra(shallow) < 0.0, "河狸：深水比淺水快、淺水比陸上快")
	_check(bvh.step_cost(deep + Vector2i(0, 0), deep) >= 0.0 and float(bvh.t["move"]["terrain_extra"]["d"]) > float(bvh.t["move"]["terrain_extra"]["s"]), "狼：深水比淺水慢")
	var dove := false
	for i in 10:
		var dvh = gs.start_tactical(gs.start_hunt("beaver", "adult"))
		dvh.deer_state = "flee"
		for by in dvh.height:
			for bx in dvh.width:
				if dvh.terrain(Vector2i(bx, by)) == "d" and not dove:
					dvh.herd[0]["pos"] = Vector2i(bx, by)
		dvh.wolf_pos = Vector2i(0, 0)
		dvh._deer_flee()
		if dvh.done and dvh.result == "escaped" and str(dvh.reason).contains("深水"):
			dove = true
			break
	_check(dove, "河狸進了深水就潛走")
	# 叉角羚（2026-10-22）：成羚成群 4～8 隻、小羚單獨出場、躲在草裡的小羚照舊走選單、深雪時跑不動
	gs.new_game("grassland_plains")
	gs.wolf.age_years = 2.5
	var pha = gs.start_hunt("pronghorn", "adult")
	pha.set_herd(true)
	var phth = gs.start_tactical(pha)
	_check(gs.tactical_eligible(pha) and phth.herd.size() >= 4 and phth.herd.size() <= 8 and str(phth.herd[0]["species"]) == "pronghorn", "叉角羚：成群 4～8 隻（%d）" % phth.herd.size())
	var pkth = gs.start_tactical(gs.start_hunt("pronghorn", "juvenile"))
	_check(pkth.herd.size() == 1 and str(pkth.herd[0]["species"]) == "pronghorn_kid", "小叉角羚單獨出場")
	_check(not gs.tactical_eligible(gs.start_hunt("pronghorn", "juvenile", -1, false, "", false, true)), "躲在草裡的小羚照舊走選單")
	phth.game_mods["snow_slow"] = 1.0
	_check(phth._snow_slow(phth.target) == 3.0, "深雪：叉角羚每回合少跑 3 格")
	# 大角羊（2026-10-22）：峽谷地圖、離峭壁近或遠、母羊成群、公羊小群、小羊跟著母羊、上了峭壁就逃掉、狼在峭壁上幾乎走不動
	gs.new_game("mountain_canyon")
	gs.wolf.age_years = 2.5
	var bha = gs.start_hunt("bighorn_sheep", "adult")
	bha.set_herd(true)
	var bhth = gs.start_tactical(bha)
	var has_cliff := false
	for cy in bhth.height:
		for cx in bhth.width:
			if bhth.terrain(Vector2i(cx, cy)) == "c":
				has_cliff = true
	_check(gs.tactical_eligible(bha) and has_cliff and bhth.herd.size() >= 3 and bhth.herd.size() <= 6, "母大角羊：峽谷地圖、成群 3～6 隻（%d）" % bhth.herd.size())
	var bhr = gs.start_hunt("bighorn_sheep", "buck")
	bhr.set_herd(true)
	var bhrth = gs.start_tactical(bhr)
	_check(bhrth.herd.all(func(d): return str(d["species"]) == "bighorn_ram") and bhrth.herd.size() >= 2 and bhrth.herd.size() <= 4, "公大角羊小群 2～4 隻")
	var bhl = gs.start_tactical(gs.start_hunt("bighorn_sheep", "juvenile"))
	_check(bhl.is_fawn(bhl.target) and bhl.label(bhl.target) == "小羊" and bhl.herd.size() == 2, "小羊跟著母羊（%s）" % bhl.label(bhl.target))
	var climbed := false
	for i in 10:
		var chh = gs.start_tactical(gs.start_hunt("bighorn_sheep", "adult"))
		chh.deer_state = "flee"
		for cy in chh.height:
			for cx in chh.width:
				if cy + 1 < chh.height and chh.terrain(Vector2i(cx, cy)) == "c" and chh.terrain(Vector2i(cx, cy + 1)) != "c" and not climbed:
					chh.herd[chh.target]["pos"] = Vector2i(cx, cy + 1)
		chh.wolf_pos = Vector2i(chh.width / 2, chh.height - 1)
		chh.di = chh.target
		chh._deer_flee()
		if (chh.done or bool(chh.herd[chh.target]["gone"])) and str(chh.events).contains("峭壁"):
			climbed = true
			break
	_check(climbed, "大角羊上了峭壁就逃掉")
	_check(float(bhth.t["move"]["terrain_extra"]["c"]) >= 6.0, "狼在峭壁上幾乎走不動")
	# 兔子（2026-10-22，小獵物的短版）：走戰術地圖、單隻、開局 3～5 格、沒察覺時趴著不動、幼兔單獨、雪兔冬季換白毛的圖
	gs.new_game("forest_east")
	gs.wolf.age_years = 2.5
	for hsp in ["hare", "snowshoe_hare"]:
		_check(gs.tactical_eligible(gs.start_hunt(hsp, "adult")) and gs.tactical_eligible(gs.start_hunt(hsp, "juvenile")), "%s：成兔、幼兔走戰術地圖" % hsp)
	var hok := 0
	for i in 30:
		var hth = gs.start_tactical(gs.start_hunt("snowshoe_hare", "adult"))
		var d0: float = hth.dist(hth.wolf_pos, hth.deer_pos)
		if hth.herd.size() == 1 and d0 >= 2.5 and d0 <= 6.0:
			hok += 1
	_check(hok >= 27, "雪兔單隻、開局 3～5 格（%d／30）" % hok)
	var fz = gs.start_tactical(gs.start_hunt("snowshoe_hare", "adult"))
	var p0: Vector2i = fz.deer_pos
	fz.di = fz.target
	for i in 5:
		fz._deer_wander()
	_check(fz.deer_pos == p0, "沒察覺的雪兔趴著不動")
	var hy = gs.start_tactical(gs.start_hunt("snowshoe_hare", "juvenile"))
	_check(hy.herd.size() == 1 and str(hy.herd[0]["species"]) == "snowshoe_hare_young", "小雪兔單獨出場")
	_check(bjth._snow_slow(bjth.target) == 2.0 and bjth._snow_slow(0 if bjth.target != 0 else 1) == 2.0, "深雪：野牛、小牛每回合少跑 2 格（白尾鹿 1 格）")
	pol.free()
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
