extends SceneTree
# Phase 2j（一天的節奏：晨昏出獵、白天休息）的回歸測試：
#   1. 白天探索、移動的體力 × daytime.stamina_mult（夏天 × summer_stamina_mult）；清晨不變
#   2. 白天休息的體力回復 × hunt.period.rest_stamina_mult.day
#   3. 白天探索空手、這一帶有晨昏活動的鹿：結果帶 day_bedded，畫面寫「白天牠們多半臥在隱蔽處」；清晨空手不寫
#   4. 自動玩家不餓、體力不滿時白天休息到黃昏；餓了照樣活動
# 用法：bash tools/run_sim.sh daytime_rules
var f := 0
var gs
var gt
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _cost(per: String, season: String, action: String) -> float:
	gt.season_index = gt.SEASONS.find(season)
	gt.period_index = gt.PERIODS.find(per)
	gt.turn_in_period = 0
	gs.wolf.stamina = 80.0
	gs.wolf.hunger = 80.0
	gs._spend_action_stamina(action)
	return 80.0 - gs.wolf.stamina

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	var gd = root.get_node("GameData")
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.pending_events.clear()
	gs.wolf.clear_injury()
	var dc: Dictionary = gd.balance["daytime"]
	# 1
	var base: float = _cost("dawn", "autumn", "explore")
	var day: float = _cost("day", "autumn", "explore")
	var summer: float = _cost("day", "summer", "explore")
	var move_d: float = _cost("day", "autumn", "move_region")
	var move_n: float = _cost("dusk", "autumn", "move_region")
	_check(absf(day - base * float(dc["stamina_mult"])) < 0.01 and absf(summer - base * float(dc["summer_stamina_mult"])) < 0.01 and absf(move_d - move_n * float(dc["stamina_mult"])) < 0.01,
		"白天探索、移動比較累：探索 清晨 %.1f、白天 %.1f、夏天白天 %.1f；移動 黃昏 %.1f、白天 %.1f" % [base, day, summer, move_n, move_d])
	# 2
	var rm: float = float(gd.balance["hunt"]["period"]["rest_stamina_mult"]["day"])
	gt.period_index = gt.PERIODS.find("day")
	gs.wolf.stamina = 20.0
	gs._rest_stamina(10.0)
	var got_day: float = gs.wolf.stamina - 20.0
	gt.period_index = gt.PERIODS.find("night")
	gs.wolf.stamina = 20.0
	gs._rest_stamina(10.0)
	var got_night: float = gs.wolf.stamina - 20.0
	_check(absf(got_day - 10.0 * rm) < 0.01 and absf(got_night - 10.0) < 0.01, "白天休息回復 × %s（白天 +%.1f、夜裡 +%.1f）" % [rm, got_day, got_night])
	# 3
	var Exp = load("res://scripts/core/ExploreSystem.gd")
	var hit_day := 0
	var nothing_day := 0
	var hit_dawn := 0
	gt.season_index = gt.SEASONS.find("summer")
	for per in ["day", "dawn"]:
		gt.period_index = gt.PERIODS.find(per)
		gt.turn_in_period = 0
		for i in 400:
			gs.wolf.stamina = 90.0
			gs.wolf.hunger = 90.0
			var r: Dictionary = gs.action_explore()
			var d: Dictionary = r.get("discovery", gs.current_discovery) if r.has("discovery") else gs.current_discovery
			if str(d.get("kind", "")) == "nothing":
				if per == "day":
					nothing_day += 1
					if bool(d.get("day_bedded", false)):
						hit_day += 1
				elif bool(d.get("day_bedded", false)):
					hit_dawn += 1
			gs.clear_discovery()
			gs.pending_events.clear()
			gt.period_index = gt.PERIODS.find(per)
			gt.turn_in_period = 0
	var text: String = TranslationServer.translate("explore.nothing.day")
	_check(nothing_day > 0 and hit_day == nothing_day and hit_dawn == 0 and text.contains("白天"), "白天空手寫出原因（白天空手 %d 次都有、清晨 %d 次）" % [nothing_day, hit_dawn])
	# 4
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var ap = AP.new("all", "average")
	gt.season_index = gt.SEASONS.find("autumn")
	gt.period_index = gt.PERIODS.find("day")
	gt.turn_in_period = 0
	gs.wolf.hunger = 100.0
	gs.wolf.stamina = 70.0
	gs.current_feeding = {}
	var d0: int = gt.day
	ap._play_day()
	var rested := false
	for k in gs.life_log.get("stats", {}).get("time", {}).keys():
		if str(k).ends_with(".rest_until"):
			rested = true
	_check(rested, "自動玩家不餓、體力不滿時白天休息到黃昏")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
