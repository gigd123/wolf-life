extends SceneTree
# 田鼠與地松鼠的小撲（Phase 2g 第 2 步）的回歸測試：
#   1. 哪一季、哪種地形有哪種（田鼠全年；地松鼠、金背地松鼠春季與夏季前半）
#   2. 只取代平淡的探索結果（什麼都沒發現、採集物、陳舊的線索），不蓋掉獵物、殘骸、冬眠的洞口；整體約 10%（草原丘陵春季約 7～8%）；守在水邊不會
#   3. 成功率：田鼠 50%（冬季雪下 40%）、感知高的加成；地松鼠 40%，看技巧與速度
#   4. 撲過去：體力 −2、不花時段、成功飽食度 +1／+2、技巧成長約狩獵撲中的六分之一、同一天第二次起遞減
#   5. 自動玩家（照常過日子）：未滿 2 歲撲、成年後不理
# 用法：bash tools/run_sim.sh small_pounce_rules
var gs
var gt
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _ids(region: String) -> Array:
	var out: Array = []
	for c in gs.small_pounce_candidates(region):
		if not out.has(c[0]):
			out.append(c[0])
	out.sort()
	return out

func _run() -> void:
	gs.new_game("grassland_hills")
	gs.pending_events.clear()
	# 1. 季節與地形
	gt.season_index = gt.SEASONS.find("spring"); gt.day = 2
	_check(_ids("grassland_hills") == ["ground_squirrel", "vole"], "草原丘陵 春季：田鼠、地松鼠（%s）" % [_ids("grassland_hills")])
	gt.season_index = gt.SEASONS.find("summer"); gt.day = 7
	_check(_ids("grassland_hills") == ["vole"], "夏季後半只剩田鼠（%s）" % [_ids("grassland_hills")])
	gt.season_index = gt.SEASONS.find("winter"); gt.day = 3
	_check(_ids("grassland_hills") == ["vole"], "冬季只有田鼠（%s）" % [_ids("grassland_hills")])
	gt.season_index = gt.SEASONS.find("spring"); gt.day = 2
	_check(_ids("mountain_canyon") == ["golden_mantled"], "岩壁峽谷（碎石坡）春季：金背地松鼠（%s）" % [_ids("mountain_canyon")])
	# 2. 頻率
	var n := 0
	var sp := 0
	var water_sp := 0
	var kinds := {} # 偏低時印出探索結果與天氣的分布（2026-10-23：偶爾只有 25／600）
	for i in 600:
		gs.wolf.stamina = 100.0
		gs.wolf.hunger = 100.0
		gs.current_region = "grassland_hills"
		gt.season_index = gt.SEASONS.find("spring"); gt.day = 2
		gs.clear_discovery()
		gs.pending_events.clear()
		var d: Dictionary = gs.action_explore("trail")
		n += 1
		var dk: String = str(d.get("kind", "")) + ("" if not d.has("source") else ":" + str(d["source"]))
		kinds[dk] = int(kinds.get(dk, 0)) + 1
		kinds["weather:" + str(gs.weather)] = int(kinds.get("weather:" + str(gs.weather), 0)) + 1
		kinds["period:" + str(gt.current_period())] = int(kinds.get("period:" + str(gt.current_period()), 0)) + 1
		if str(d.get("kind", "")) == "small_pounce":
			sp += 1
			_check(["vole", "ground_squirrel"].has(str(d["animal"])) and ["rolling_hills", "prairie"].has(str(d["location"])), "地點與動物一致（%s）" % d)
		gs.clear_discovery()
		if not gs.wolf.alive:
			break
	# 下限 30 → 20（2026-10-23）：小撲只取代平淡的結果，草原丘陵春季平淡的結果每次只有 20～30 個，45 次裡有一次 25（平均約 50）
	_check(sp >= 20 and sp <= 90, "整體約 10%%（%d／%d）" % [sp, n])
	if sp < 40:
		print("  （偏低）探索結果與天氣：", kinds)
	_check(gs._small_pounce_replaceable({"kind": "nothing"}) and gs._small_pounce_replaceable({"kind": "clue", "source_kind": "gather"})
		and gs._small_pounce_replaceable({"kind": "clue", "source_kind": "prey", "fresh": false, "clue": "track"}), "平淡的結果可以換成小撲")
	_check(not gs._small_pounce_replaceable({"kind": "clue", "source_kind": "prey", "fresh": true, "clue": "track"})
		and not gs._small_pounce_replaceable({"kind": "clue", "source_kind": "prey", "clue": "sight"})
		and not gs._small_pounce_replaceable({"kind": "remains"}) and not gs._small_pounce_replaceable({"kind": "nothing", "hibernating": "marmot"})
		and not gs._small_pounce_replaceable({"kind": "clue", "source_kind": "threat"}) and not gs._small_pounce_replaceable({"kind": "feature"}),
		"新鮮的線索、看到的獵物、殘骸、冬眠的洞口、危險、地點不會被換掉")
	# 3. 成功率
	gs.wolf.perception = 50.0; gs.wolf.skill = 50.0; gs.wolf.speed = 50.0
	var base_vole: float = gs.small_pounce_chance({"animal": "vole", "snow": false})
	var snow_vole: float = gs.small_pounce_chance({"animal": "vole", "snow": true})
	_check(absf(base_vole - (0.5 + (gs.wolf.effective_perception() - 50.0) / 200.0)) < 0.001, "田鼠：50%% ＋ 感知（%.2f）" % base_vole)
	_check(absf((base_vole - snow_vole) - 0.1) < 0.001, "冬季雪下的田鼠少 10%%（%.2f）" % snow_vole)
	gs.wolf.perception = 90.0
	_check(gs.small_pounce_chance({"animal": "vole", "snow": false}) > base_vole, "感知高的比較容易撲到田鼠")
	var gsq: float = gs.small_pounce_chance({"animal": "ground_squirrel"})
	gs.wolf.skill = 90.0
	_check(gs.small_pounce_chance({"animal": "ground_squirrel"}) > gsq, "技巧高的比較容易撲到地松鼠")
	# 4. 撲過去
	var got := 0
	var growth_first := 0.0
	var growth_second := 0.0
	for i in 40:
		gs.wolf.stamina = 80.0
		gs.wolf.hunger = 50.0
		gs.wolf.skill = 50.0
		gs.life_log.erase("small_pounce")
		gs.current_discovery = {"kind": "small_pounce", "animal": "ground_squirrel", "location": "prairie", "snow": false}
		var t0: int = gt.day * 100 + gt.period_index * 10 + gt.turn_in_period
		var r1: Dictionary = gs.resolve_small_pounce(true)
		var t1: int = gt.day * 100 + gt.period_index * 10 + gt.turn_in_period
		_check(t0 == t1 and absf(gs.wolf.stamina - 78.0) < 0.01 and gs.current_discovery.is_empty(), "撲過去：體力 −2、不花時段、發現清掉")
		_check(absf(gs.wolf.hunger - (52.0 if r1["caught"] else 50.0)) < 0.01, "成功飽食度 +2、失敗 0")
		if r1["caught"]:
			got += 1
			growth_first = gs.wolf.skill - 50.0
			# 同一天第二次：成長遞減
			gs.wolf.skill = 50.0
			gs.current_discovery = {"kind": "small_pounce", "animal": "ground_squirrel", "location": "prairie", "snow": false}
			var r2: Dictionary = gs.resolve_small_pounce(true)
			if r2["caught"]:
				growth_second = gs.wolf.skill - 50.0
	_check(got >= 8 and got <= 30, "地松鼠 40～60%% 撲到（%d／40）" % got)
	_check(growth_first > 0.0 and growth_first < 0.1, "撲到一次的技巧成長很小（%.3f）" % growth_first)
	_check(growth_second > 0.0 and growth_second < growth_first, "同一天第二次撲到的成長遞減（%.3f → %.3f）" % [growth_first, growth_second])
	gs.current_discovery = {"kind": "small_pounce", "animal": "vole", "location": "prairie", "snow": false}
	var h0: float = gs.wolf.hunger
	var s0: float = gs.wolf.stamina
	_check(gs.resolve_small_pounce(false).is_empty() and gs.wolf.hunger == h0 and gs.wolf.stamina == s0 and gs.current_discovery.is_empty(), "不理牠：什麼都不變")
	_check(gs.is_notable_discovery({"kind": "small_pounce"}), "未滿 2 歲：小撲會停下「探索到有發現為止」")
	gs.wolf.age_years = 3.0
	_check(not gs.is_notable_discovery({"kind": "small_pounce"}), "成年：小撲不打斷「探索到有發現為止」")
	# 5. 自動玩家
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var tries := {}
	for adult in [false, true]:
		var total := 0
		for r in 4:
			var ap = AP.new("all", "balanced")
			ap.start("grassland_hills")
			if adult:
				gs.wolf.age_years = 3.0
			var guard := 0
			while not ap.done() and guard < 25:
				ap.step(1); guard += 1
			ap.finish()
			total += int(gs.life_log.get("small_pounce", {}).get("tries", 0))
		tries[adult] = total
	_check(int(tries[false]) > 0 and int(tries[true]) == 0, "自動玩家：小狼會撲、成年不理（%d／%d）" % [tries[false], tries[true]])
	print("小撲 %d／%d 次探索；地松鼠撲到 %d／40；技巧成長 第一次 %.3f、同一天第二次 %.3f；自動玩家 小狼 %d 次、成年 %d 次" % [sp, n, got, growth_first, growth_second, tries[false], tries[true]])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
