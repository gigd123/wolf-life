extends SceneTree
# Phase 2m 第 2 步的規則檢查：你盯上的那一隻逃掉 → 這一區記一頭會延續的個體（傷、疲勞、時段、成群）；
# 逃掉後的足跡連到牠、追蹤的因素（同一天、雪地、血跡、過了幾天）；傷每 2 天好一處、疲勞 2 個時段後恢復；
# 再遇到時戰術地圖帶著牠的傷、還累著時從上次的逃跑回合開始、觀察時認得出牠；獵到就移除、又逃了換掉舊的；
# 沒察覺你的不記；選單式照舊只記咬傷的大型成獸。
# 用法：bash tools/run_sim.sh fled_notable_rules
var f := 0
var fails := 0
var gs
var gt

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _fled_hunt(animal: String, wounds: int, tired: int, noticed: bool = true, herd: bool = false):
	var h = gs.start_hunt(animal, "adult", 1, false, "forest_edge", false, false, 1 if herd else 0)
	h.set_meta("fled_individual", {"wounds": wounds, "tired": tired, "noticed": noticed})
	h.result = h.Result.PREY_FLED if noticed else h.Result.PLAYER_GAVE_UP
	h.fled = noticed
	h.stage = h.Stage.DONE
	gs.finish_hunt(h)
	return h

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.notables = []
	# 1. 逃掉 → 記下、足跡連到牠
	_fled_hunt("white_tailed_deer", 2, 6)
	_ok(gs.notables.size() == 1, "記一頭")
	var n: Dictionary = gs.notables[0] if not gs.notables.is_empty() else {}
	_ok(int(n.get("wounds", -1)) == 2 and int(n.get("tired", -1)) == 6 and str(n.get("trait", "")) == "wounded", "傷、疲勞、wounded（%s）" % str(n))
	_ok(int(gs.current_discovery.get("notable_id", 0)) == int(n.get("id", -1)) and bool(gs.current_discovery.get("fled", false)), "足跡連到牠")
	_ok(bool(gs.current_discovery.get("injured", false)), "帶傷的足跡")
	var keys: Array = (gs.track_chance()["factors"] as Array).map(func(x): return str(x["key"]))
	_ok(keys.has("factor.track_same_day") and keys.has("factor.track_blood"), "追蹤的因素：同一天、血跡（%s）" % str(keys))
	var id: int = int(n.get("id", 0))
	var st: Dictionary = gs.notable_state(id)
	_ok(int(st["wounds"]) == 2 and int(st["tired"]) == 6, "剛逃掉：傷 2、還累著")
	# 2. 過了 2 個時段：不累了；過 2 天：好一處；4 天後忘了
	gt.advance_turns(4 * 2)
	_ok(int(gs.notable_state(id)["tired"]) == 0, "2 個時段後不累")
	gs.life_log["days_lived"] = int(gs.life_log["days_lived"]) + 2
	_ok(int(gs.notable_state(id)["wounds"]) == 1, "2 天後好一處（%d）" % int(gs.notable_state(id)["wounds"]))
	gs.current_discovery = {"kind": "clue", "source_kind": "prey", "source": "white_tailed_deer", "clue": "track", "fresh": true, "fresh_known": true, "wind": "crosswind", "life_stage": "adult", "notable_id": id}
	keys = (gs.track_chance()["factors"] as Array).map(func(x): return str(x["key"]))
	_ok(keys.has("factor.track_old") and not keys.has("factor.track_same_day"), "過了幾天：足跡舊了（%s）" % str(keys))
	gs.current_discovery = {}
	# 3. 再遇到：戰術地圖帶著牠的傷、認得出牠
	gs.hunting_notable = id
	var h2 = gs.start_hunt("white_tailed_deer", "adult", 1, false, "forest_edge", true, false, 0)
	var th = gs.start_tactical(h2)
	_ok(int(th.herd[0]["wounds"]) == 1 and bool(th.herd[0].get("known", false)) and not bool(th.herd[0].get("injured", false)), "戰術地圖：傷 1、認得出、不套跛腳")
	th.events = []
	th.observe()
	_ok(th.events.any(func(e): return str(e).contains("認出牠")), "觀察時認得出（%s）" % str(th.events))
	# 4. 又逃了：換掉舊的
	gs.hunting_notable = id
	_fled_hunt("white_tailed_deer", 1, 3)
	_ok(gs.notables.size() == 1 and int(gs.notables[0]["id"]) != id, "又逃了換掉舊的")
	# 5. 還累著時開始逃：接著上次的回合數
	var id2: int = int(gs.notables[0]["id"])
	gs.hunting_notable = id2
	var h3 = gs.start_hunt("white_tailed_deer", "adult", 1, false, "forest_edge", true, false, 0)
	var th3 = gs.start_tactical(h3)
	th3.di = 0
	th3._start_flee("close")
	_ok(int(th3.flee_round) == 3, "還累著：逃跑從第 3 回合開始（%d）" % int(th3.flee_round))
	gs.hunting_notable = 0
	# 6. 沒察覺你的不記
	gs.notables = []
	_fled_hunt("white_tailed_deer", 0, 0, false)
	_ok(gs.notables.is_empty(), "沒察覺你的不記")
	# 7. 成群的：再遇到時照樣在群裡
	gs.notables = []
	_fled_hunt("white_tailed_deer", 0, 4, true, true)
	_ok(bool(gs.notables[0].get("herd", false)) and str(gs.notables[0]["trait"]) == "fled", "成群、沒受傷 → fled")
	var here: Array = gs._notables_here()
	var hits := 0
	var herd_ok := true
	for i in 200:
		var r: Dictionary = load("res://scripts/core/ExploreSystem.gd").generate({"region_id": gs.current_region, "season": gt.current_season(), "period": gt.current_period(),
			"depletion": {}, "burn": "", "wind_dir": 0, "known_features": [], "prey_knowledge": {}, "weather": "clear", "stranger_territory": "?",
			"mode": "trail", "berries_mult": 1.0, "lean_nothing": 1.0, "marks": [], "notables": here, "youth": {}})
		if int(r.get("notable_id", 0)) != 0:
			hits += 1
			herd_ok = herd_ok and bool(r.get("herd", false)) and not bool(r.get("injured", true))
	_ok(hits > 0, "200 次探索裡有再遇到")
	_ok(herd_ok, "再遇到：在群裡、傷好了不算受傷（遇到 %d 次）" % hits)
	print("同一隻獵物的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
