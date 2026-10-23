extends SceneTree
# Phase 4a 第 1 步（牧場地圖、候選位置、出現的時機、動態的連接、存檔、線索與卡片）的回歸測試：
#   1. 新局沒有牧場：地圖、區域、連接都沒有
#   2. 2～3 歲每季擲一次 25%：約 68% 的局出現；一生最多擲 4 次；同一季重複呼叫不重擲；3 歲還沒出現 → never
#   3. 出現的那一季只有線索，下一季才開放；開放後牧場邊緣連到候選的兩個區域、雙向
#   4. 候選位置：每個至少 10%；連到巢穴區的候選比較少
#   5. 線索只在出現的那一季、連到牧場的區域（約 25%）
#   6. 存讀檔：開放的牧場、擲過的季都還在；沒有牧場的存檔讀回來也沒有
#   7. 開放後第一次走到連到牧場的區域跳一張卡片（只跳一次）；走得進牧場、走得回來
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
	gd.set_ranch("")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
	else:
		print("  ✓ " + what)
