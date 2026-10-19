extends SceneTree
# Phase 2b 第 4 步「活動時段」的回歸測試：清晨、黃昏潛近 +5%（其他時段不加）；夏季白天狩獵結束多扣體力 ×1.3；白天休息回的體力 ×1.2。
# 用法：bash tools/run_sim.sh period_effects
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var HS = load("res://scripts/core/HuntSystem.gd")
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	var w = gs.wolf
	# 1. 潛近
	var by := {}
	for p in gt.PERIODS:
		gt.period_index = gt.PERIODS.find(p)
		w.in_burst = false
		root.get_node("RNGService").set_seed(7)
		var h = HS.new(w, "white_tailed_deer", "adult", 0.0, 0, 0, "forest_edge")
		h.stage = HS.Stage.STALK
		var opts: Array = h.options()
		by[p] = float(opts[0]["chance"]) if not opts.is_empty() else -1.0
		var has_factor: bool = opts[0]["factors"].any(func(x): return str(x["key"]).begins_with("factor.period.")) if not opts.is_empty() else false
		_check(has_factor == (p in ["dawn", "dusk"]), "%s：晨昏才有時段的因素" % p)
		w.in_burst = false
	print("潛近第一個選項的成功率：", by)
	_check(absf(by["dawn"] - by["day"] - 0.05) < 0.011 or by["dawn"] >= 0.95, "清晨比白天 +5%%（%.2f → %.2f）" % [by["day"], by["dawn"]])
	# 2. 夏季白天狩獵結束
	gt.season_index = gt.SEASONS.find("summer")
	for p in ["day", "dusk"]:
		gt.period_index = gt.PERIODS.find(p)
		w.stamina = 80.0
		w.in_burst = false
		var h2 = HS.new(w, "white_tailed_deer", "adult", 0.0, 0, 0, "forest_edge")
		w.spend_breath(40.0)
		h2.pending_turns = 0
		gs.finish_hunt(h2)
		print("夏季 %s 狩獵結束扣體力 %.2f（記錄 %.2f）" % [p, 80.0 - w.stamina, h2.end_stamina])
		by["end_" + p] = 80.0 - w.stamina
	_check(absf(by["end_day"] / max(0.01, by["end_dusk"]) - 1.3) < 0.02, "夏季白天 ×1.3")
	# 3. 白天休息
	for p in ["day", "night"]:
		gt.period_index = gt.PERIODS.find(p)
		w.stamina = 20.0
		gs._rest_stamina(10.0)
		by["rest_" + p] = w.stamina - 20.0
	_check(absf(by["rest_day"] - 12.0) < 0.01 and absf(by["rest_night"] - 10.0) < 0.01, "白天休息 ×1.2（白天 %.1f、夜間 %.1f）" % [by["rest_day"], by["rest_night"]])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
