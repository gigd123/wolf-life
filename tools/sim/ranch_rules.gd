extends SceneTree
# Phase 4a 第 1 步（牧場地圖、候選位置、出現的時機、動態的連接、存檔、線索與卡片）的回歸測試：
#   1. 新局沒有牧場：地圖、區域、連接都沒有
#   2. 2～3 歲每季擲一次 25%：約 68% 的局出現；一生最多擲 4 次；同一季重複呼叫不重擲；3 歲還沒出現 → never
#   3. 出現的那一季只有線索，下一季才開放；開放後牧場邊緣連到候選的兩個區域、雙向
#   4. 候選位置：每個至少 10%；連到巢穴區的候選比較少
#   5. 線索只在出現的那一季、連到牧場的區域（約 25%）
#   6. 存讀檔：開放的牧場、擲過的季都還在；沒有牧場的存檔讀回來也沒有
#   7. 開放後第一次走到連到牧場的區域跳一張卡片（只跳一次）；走得進牧場、走得回來
# 第 2 步：
#   8. 人類活動度：牧場的區域、連到牧場、再隔一個連接、乘地形與季節；苔原、山地、沒有牧場時 0；注意讓近的區域提高
#   9. 注意：事件 × 屋舍 × 白天 × 間隔太短；每天消退（約 20 天減半）；上限 100
#  10. 人類的痕跡：照活動度出現；種類照注意的層級（低注意沒有獵犬、槍聲）
#  11. 在牧場邊緣觀察：看得出警戒的層級，夜裡有夜裡的寫法；別的地方不能觀察
# 用法：bash tools/run_sim.sh ranch_rules
var gs
var gd
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gd = root.get_node("GameData")
	_run.call_deferred()

func _ranch_links(region: String) -> Array:
	return gd.links_from(region).filter(func(l): return str(l["to"]).begins_with("ranch_"))

func _run() -> void:
	gs.new_game("forest_south")
	gs.pending_events.clear()
	gd.ranch_def["enabled"] = true # 主遊戲先關著（家畜、人類做好前），測試打開
	# 1. 新局沒有牧場
	_check(not gd.maps().has("ranch") and not gd.regions().has("ranch_edge") and _ranch_links("forest_south").is_empty(), "新局沒有牧場的地圖、區域、連接")
	# 2. 出現的機率與擲骰
	var appeared := 0
	var max_rolls := 0
	var double_ok := true
	var never_ok := true
	var by_cand := {}
	var lives := 3000
	for i in lives:
		gs.ranch = {}
		gs.wolf.age_years = 0.67
		for s in 14:
			gs.wolf.age_years += 0.25
			gs._update_ranch()
			var r0: int = int(gs.ranch.get("rolls", 0))
			gs._update_ranch() # 同一季再呼叫一次（讀檔、季節初始化）：不能重擲
			if gs.ranch_state() == "" and int(gs.ranch.get("rolls", 0)) != r0:
				double_ok = false
		max_rolls = maxi(max_rolls, int(gs.ranch.get("rolls", 0)))
		if gs.ranch_state() == "open":
			appeared += 1
			var c: String = str(gs.ranch["candidate"])
			by_cand[c] = int(by_cand.get(c, 0)) + 1
			if float(gs.ranch["appear_age"]) < 2.0 or float(gs.ranch["appear_age"]) >= 3.0:
				never_ok = false
		elif gs.ranch_state() != "never":
			never_ok = false
	var rate: float = float(appeared) / lives
	_check(rate > 0.63 and rate < 0.74, "約 68%% 的局出現（%.1f%%）" % (rate * 100.0))
	_check(max_rolls == 4, "一生最多擲 4 次（%d）" % max_rolls)
	_check(double_ok, "同一季重複呼叫不重擲")
	_check(never_ok, "出現時在 2～3 歲；沒出現的是 never")
	# 4. 候選位置（巢穴在森林南部：A、C 連到巢穴，權重減半）
	var min_share := 1.0
	for c in ["A", "B", "C", "D"]:
		min_share = minf(min_share, float(by_cand.get(c, 0)) / maxf(1.0, appeared))
	_check(min_share >= 0.1, "每個候選至少 10%%（%s）" % str(by_cand))
	_check(int(by_cand.get("A", 0)) < int(by_cand.get("B", 0)) and int(by_cand.get("C", 0)) < int(by_cand.get("D", 0)), "連到巢穴區的候選（A、C）比較少")
	# 3. 線索的一季 → 開放
	gs.new_game("forest_south")
	gs.pending_events.clear()
	gs.ranch = {"state": "clues", "candidate": "A", "appear_age": 2.25, "last_roll": 9}
	gs.wolf.age_years = 2.5
	_check(not gd.maps().has("ranch") and _ranch_links("forest_south").is_empty(), "出現的那一季還進不去")
	gs._update_ranch()
	_check(gs.ranch_state() == "open" and gd.maps().has("ranch") and gd.regions().has("ranch_pasture"), "下一季開放：牧場的地圖與區域")
	var to_ranch: Array = _ranch_links("forest_south")
	var back: Array = gd.links_from("ranch_edge").map(func(l): return str(l["to"]))
	_check(to_ranch.size() == 1 and back.has("forest_south") and back.has("grassland_hills") and _ranch_links("grassland_hills").size() == 1, "牧場邊緣連到森林南部、丘陵草地（雙向）")
	_check(_ranch_links("tundra_south").is_empty() and _ranch_links("mountain_foothills").is_empty(), "苔原、山地不連到牧場")
	_check(not bool(gd.regions()["ranch_yard"].get("can_den", true)), "牧場不能築巢")
	# 6. 存讀檔
	var saved: Dictionary = gs.to_dict()
	gs.new_game("forest_south")
	_check(not gd.maps().has("ranch"), "新局把牧場清掉")
	gs.load_from_dict(saved)
	_check(gs.ranch_state() == "open" and gd.maps().has("ranch") and _ranch_links("forest_south").size() == 1, "讀檔後牧場還在、連接還在")
	gs.new_game("forest_south")
	var no_ranch: Dictionary = gs.to_dict()
	gs.ranch = {"state": "clues", "candidate": "B"}
	gs.load_from_dict(no_ranch)
	_check(gs.ranch_state() == "" and not gd.maps().has("ranch"), "沒有牧場的存檔讀回來也沒有")
	# 5. 線索
	gs.new_game("forest_south")
	gs.ranch = {"state": "clues", "candidate": "A"}
	var found := 0
	var kinds := {}
	for i in 1000:
		gs.current_discovery = {}
		if gs._maybe_ranch_clue():
			found += 1
			kinds[str(gs.current_discovery.get("ranch_clue", ""))] = true
	_check(found > 200 and found < 300, "出現的那一季，在連到牧場的區域約 25%% 找到線索（%d／1000）" % found)
	var kinds_ok: bool = kinds.size() == 4
	for k in kinds.keys():
		kinds_ok = kinds_ok and k in ["cattle_smell", "smoke", "axe", "fence_posts"]
	_check(kinds_ok, "線索的四種：牛的氣味、炊煙、斧頭聲、柵欄樁（%s）" % str(kinds.keys()))
	gs.current_region = "forest_north"
	var far := 0
	for i in 300:
		if gs._maybe_ranch_clue():
			far += 1
	gs.current_region = "forest_south"
	gs.ranch["state"] = "open"
	var after := 0
	for i in 300:
		if gs._maybe_ranch_clue():
			after += 1
	_check(far == 0 and after == 0, "別的區域、開放之後沒有這種線索")
	# 換季卡片：人在連到牧場的地圖才寫，寫那一頭的區域
	gs.new_game("forest_east")
	gs.pending_events.clear()
	gs.ranch = {"state": "clues", "candidate": "A", "card": "clues"}
	gs._queue_season_card()
	var card_lines: Array = []
	for e in gs.pending_events:
		if str(e.get("type", "")) == "season_card":
			card_lines = e["lines"]
	var has_line: bool = card_lines.any(func(l): return str(l["key"]) == "ranch.season.clues" and str(l.get("region", "")) == "forest_south")
	gs.pending_events.clear()
	gs.ranch = {"state": "open", "candidate": "A", "card": "open"}
	gs.current_region = "tundra_south"
	gs._queue_season_card()
	var tundra_lines: Array = []
	for e in gs.pending_events:
		if str(e.get("type", "")) == "season_card":
			tundra_lines = e["lines"]
	_check(has_line and not tundra_lines.any(func(l): return str(l["key"]).begins_with("ranch.")), "換季卡片：在森林寫「森林南部那一頭…」，在苔原不寫")
	# 7. 第一次走到附近的卡片、走進牧場
	gs.new_game("forest_east")
	gs.pending_events.clear()
	gs.ranch = {"state": "open", "candidate": "A"}
	gd.set_ranch("A")
	gs.wolf.stamina = 100.0
	gs.action_move("forest_south")
	var news: Array = gs.pending_events.filter(func(e): return str(e.get("type", "")) == "ranch_news")
	_check(news.size() == 1 and str(news[0]["region"]) == "forest_south", "第一次走到連到牧場的區域跳一張卡片")
	gs.pending_events.clear()
	gs.action_move("forest_east")
	gs.action_move("forest_south")
	_check(gs.pending_events.filter(func(e): return str(e.get("type", "")) == "ranch_news").is_empty(), "只跳一次")
	gs.wolf.stamina = 100.0
	gs.action_move("ranch_edge")
	_check(gs.current_region == "ranch_edge" and gs.current_map() == "ranch", "走得進牧場邊緣")
	gs.action_move("ranch_pasture")
	gs.action_move("ranch_edge")
	gs.action_move("grassland_hills")
	_check(gs.current_region == "grassland_hills", "從牧場走到丘陵草地")
	gs.current_region = "ranch_pasture"
	var ok := true
	for i in 30:
		var d: Dictionary = gs.action_explore()
		if not gs.wolf.alive:
			break
		if d.is_empty() and gs.wolf.alive:
			ok = false
		gs.clear_discovery()
		gs.wolf.stamina = 100.0
		gs.wolf.hunger = 100.0
	_check(ok, "在牧場探索不會出錯")
	_step2()
	gd.set_ranch("")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
	else:
		print("  ✓ " + what)

func _step2() -> void:
	var gt = root.get_node("GameTime")
	gs.new_game("forest_east")
	gs.pending_events.clear()
	gs.ranch = {"state": "open", "candidate": "A"}
	gd.set_ranch("A")
	# 8. 活動度（照季節的倍率換算回基礎值）
	var sm: float = float(gd.ranch_def["activity"]["season"][gt.current_season()])
	var yard: float = gs.ranch_activity("ranch_yard") / sm
	var linked: float = gs.ranch_activity("forest_south") / sm # 林緣 0.8
	var near: float = gs.ranch_activity("forest_east") / sm # 和森林南部相鄰；溪流 0.8
	_check(absf(yard - 0.9) < 0.01 and absf(linked - 0.24) < 0.01 and absf(near - 0.08) < 0.01, "活動度：屋舍 0.9、森林南部 0.3 × 林緣 0.8、森林東部 0.1 × 0.8（%.2f、%.2f、%.2f）" % [yard, linked, near])
	_check(gs.ranch_activity("forest_north") == 0.0 and gs.ranch_activity("tundra_south") == 0.0 and gs.ranch_activity("mountain_foothills") == 0.0, "遠的區域、苔原、山地是 0")
	gs.ranch["attention"] = 50.0
	var with_att: float = gs.ranch_activity("forest_south")
	_check(absf(with_att - (0.24 * sm + 0.2)) < 0.01 and gs.ranch_activity("forest_east") / sm - 0.08 < 0.01, "注意 50：牧場與連到牧場的區域 +0.2，再遠的不變（%.2f）" % with_att)
	gs.ranch["state"] = "clues"
	_check(gs.ranch_activity("ranch_yard") == 0.0, "還沒開放時沒有活動度")
	gs.ranch["state"] = "open"
	# 9. 注意
	gs.ranch = {"state": "open", "candidate": "A"}
	gs.life_log["days_lived"] = 100
	gt.period_index = 3 # 夜裡
	var v1: float = gs.ranch_add_attention("calf", "ranch_pasture")
	_check(absf(v1 - 12.0) < 0.01, "夜裡在放牧地獵到牛犢 +12（%.1f）" % v1)
	gs.life_log["days_lived"] = 110
	gt.period_index = 1 # 白天
	var v2: float = gs.ranch_add_attention("sheep", "ranch_yard")
	_check(absf(v2 - 25.0 * 1.5 * 1.3) < 0.01, "白天在屋舍獵羊 25 × 1.5 × 1.3（%.1f）" % v2)
	var v3: float = gs.ranch_add_attention("calf", "ranch_pasture")
	_check(absf(v3 - 12.0 * 1.3 * 2.0) < 0.01, "同一天再一次 × 2（%.1f）" % v3)
	gs.life_log["days_lived"] = 112
	var v4: float = gs.ranch_add_attention("calf", "ranch_pasture")
	gs.life_log["days_lived"] = 116
	var v5: float = gs.ranch_add_attention("calf", "ranch_pasture")
	_check(absf(v4 - 12.0 * 1.3 * 1.6) < 0.01 and absf(v5 - 12.0 * 1.3 * 1.3) < 0.01, "隔 2 天 × 1.6、隔 4 天 × 1.3")
	for i in 10:
		gs.ranch_add_attention("sheep", "ranch_yard")
	_check(gs.ranch_attention() <= 100.0, "上限 100")
	gs.ranch["attention"] = 60.0
	for i in 20:
		gs._decay_ranch_attention()
	var after20: float = gs.ranch_attention()
	for i in 12:
		gs._decay_ranch_attention()
	_check(after20 > 27.0 and after20 < 33.0 and gs.ranch_attention() < 21.0, "每天消退：60 → 20 天約 30、32 天約 20（%.1f、%.1f）" % [after20, gs.ranch_attention()])
	# 10. 痕跡
	gs.current_region = "ranch_pasture"
	var by_tier := {}
	for att in [0.0, 30.0, 80.0]:
		gs.ranch["attention"] = att
		var kinds := {}
		var n := 0
		for i in 2000:
			if gs._maybe_ranch_sign():
				n += 1
				kinds[str(gs.current_discovery["ranch_sign"])] = true
		by_tier[att] = [n, kinds.keys()]
	var calm_k: Array = by_tier[0.0][1]
	var hunt_k: Array = by_tier[80.0][1]
	_check(not calm_k.has("hound_tracks") and not calm_k.has("gunshot") and not calm_k.has("searching") and calm_k.has("fence"), "注意低：只有柵欄、牛、炊煙（%s）" % str(calm_k))
	_check((by_tier[30.0][1] as Array).has("barking") and not (by_tier[30.0][1] as Array).has("gunshot"), "注意 30：多了蹄印、狗叫，沒有槍聲")
	_check(hunt_k.has("searching") and hunt_k.has("gunshot"), "注意 80：「牠們在找你」、槍聲")
	_check(int(by_tier[80.0][0]) > int(by_tier[0.0][0]), "注意高時痕跡比較常見（%d → %d／2000）" % [by_tier[0.0][0], by_tier[80.0][0]])
	gs.current_region = "forest_north"
	var far := 0
	for i in 500:
		if gs._maybe_ranch_sign():
			far += 1
	_check(far == 0, "遠的區域沒有痕跡")
	# 11. 觀察
	gs.current_region = "ranch_pasture"
	_check(not gs.can_watch_ranch(), "放牧地不能「望向柵欄裡」")
	gs.current_region = "ranch_edge"
	var seen := {}
	for pair in [[5.0, 1], [5.0, 3], [30.0, 1], [50.0, 1], [80.0, 1]]:
		gs.ranch["attention"] = pair[0]
		gt.period_index = pair[1]
		var d: Dictionary = gs.action_watch_ranch()
		seen[str(d.get("ranch_watch", ""))] = true
		gs.clear_discovery()
		gs.wolf.stamina = 100.0
	_check(gs.can_watch_ranch() and seen.has("calm") and seen.has("calm.night") and seen.has("wary") and seen.has("patrol") and seen.has("hunt"), "牧場邊緣觀察：看得出四層，夜裡有夜裡的寫法（%s）" % str(seen.keys()))
