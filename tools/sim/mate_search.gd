extends SceneTree
# Phase 3 第 2 步「離群母狼與配對」的一生模擬（SPEC Phase 3「離群母狼與配對」、待確認「遇到離群母狼的機率、關係升降的量」）。
# 自動玩家住在巢穴附近（四張地圖輪流），玩到 UNTIL 歲或死亡，統計：
#   1. 第一次遇到母狼（徵兆）、成為伴侶的年齡；成年後一年內、兩年內配對的比例（目標：秋冬認真找，1～2 年內配對）
#   2. 從第一次的徵兆到成為伴侶花了幾天；母狼離開的次數
# 用法：bash tools/run_sim.sh mate_search 0 30；MATE=never|sometimes|always 找伴侶的認真程度（預設 sometimes）；UNTIL=5 玩到幾歲
const DENS := ["forest_east", "tundra_south", "mountain_canyon", "grassland_riverwoods"]

func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs := int(_env("RUNS", "20"))
	var policy := _env("MATE", "sometimes")
	var until := float(_env("UNTIL", "5"))
	var adult_ages: Array = []
	var mate_after_adult: Array = [] # 成年後幾年配對（沒配對的不放）
	var sign_to_mate: Array = [] # 第一次徵兆到配對的天數
	var lefts := 0
	var signs := 0
	var reached_adult := 0
	var died_before := 0
	for r in runs:
		var ap = AP.new("all", "average")
		ap.mate_search = policy
		ap.start(DENS[r % DENS.size()])
		var guard := 0
		while not ap.done() and guard < 3000 and GS.wolf.alive and GS.wolf.age_years < until:
			guard += 1
			ap.step(1)
		ap.finish()
		var adult := -1.0
		var mated := -1.0
		var first_sign := -1
		var mate_day := -1
		for e in GS.life_events():
			var t: String = str(e.get("type", ""))
			if t == "adult" and adult < 0.0:
				adult = float(e["age"])
			elif t == "she_wolf.sign":
				signs += 1
				if first_sign < 0:
					first_sign = int(e["day"])
			elif t == "she_wolf.left":
				lefts += 1
			elif t == "mate" and mated < 0.0:
				mated = float(e["age"])
				mate_day = int(e["day"])
		if adult < 0.0:
			died_before += 1
			continue
		reached_adult += 1
		adult_ages.append(adult)
		if mated >= 0.0:
			mate_after_adult.append(mated - adult)
			if first_sign >= 0:
				sign_to_mate.append(mate_day - first_sign)
	var within1 := mate_after_adult.filter(func(y): return y <= 1.0).size()
	var within2 := mate_after_adult.filter(func(y): return y <= 2.0).size()
	mate_after_adult.sort()
	sign_to_mate.sort()
	print("== mate_search：%d 隻（%s，住在巢穴附近，玩到 %.1f 歲）" % [runs, policy, until])
	print("  成年的 %d 隻（成年前死亡 %d）" % [reached_adult, died_before])
	print("  成年後 1 年內配對 %d%%、2 年內 %d%%、玩到結束 %d%%" % [roundi(100.0 * within1 / max(1, reached_adult)), roundi(100.0 * within2 / max(1, reached_adult)), roundi(100.0 * mate_after_adult.size() / max(1, reached_adult))])
	if not mate_after_adult.is_empty():
		print("  成年後幾年配對：中位數 %.2f（%s）" % [mate_after_adult[mate_after_adult.size() / 2], str(mate_after_adult)])
	if not sign_to_mate.is_empty():
		print("  第一次徵兆到配對：中位數 %d 天（%s）" % [sign_to_mate[sign_to_mate.size() / 2], str(sign_to_mate)])
	print("  母狼出現 %d 次、離開 %d 次" % [signs, lefts])
	quit()
	return true
