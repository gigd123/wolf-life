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
#   9. 注意：事件 × 屋舍 × 白天 × 間隔太短；每天消退（約 14 天減半）；上限 100
#  10. 人類的痕跡：照活動度出現；種類照注意的層級（低注意沒有獵犬、槍聲）
#  11. 在牧場邊緣觀察：看得出警戒的層級，夜裡有夜裡的寫法；別的地方不能觀察
# 第 3 步：
#  12. 家畜：放牧地探索看到牛（牛犢只在春夏）、屋舍與畜欄看到羊（冬天沒有）、邊緣偶爾走散的牛；牧場外沒有家畜
#  13. 獵到家畜加那一種的注意；出手沒獵到算被看到（+3）；沒開放時不加
# 第 4 步：
#  14. 巡查不會死；一槍夠重是重傷；躲的成功率看遮蔽與感知、跑看速度；往開闊地跑一定被看到（+3）
#  15. 只在牧場一帶、注意 40 以上才有巡查；70 以上先預警才追獵；追獵後換地圖就甩掉，注意不變
#  16. 追獵可能被打死（死因 human）；能咬退狗、掙脫；狗咬、騎馬的人趕到開槍
#  17. 在牧場吃到一半被打斷：叼一段跑（多吃一段、殘骸沒了）、丟下、趴著躲（成功就繼續吃）
# 第 5 步（自動玩家，AutoPlayer）：
#  18. 策略照打法（謹慎 never、平均 sometimes、強攻 often；照常過日子 never）；沒開放時不動
#  19. sometimes 餓了、注意低才往放牧地走；不餓或注意 40 以上不去；在放牧地留下來找家畜；never 在牧場裡就離開
#  20. 注意到 leave_at 離開牧場一帶（sometimes 40、often 70）；巢穴在那一帶時先待在同地圖的另一區；70 以上巢穴在那一帶就搬走
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
	_step3()
	_step4()
	_step5()
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
	_check(absf(v1 - 6.0) < 0.01, "夜裡在放牧地獵到牛犢 +6（%.1f）" % v1)
	gs.life_log["days_lived"] = 110
	gt.period_index = 1 # 白天
	var v2: float = gs.ranch_add_attention("sheep", "ranch_yard")
	_check(absf(v2 - 12.0 * 1.5 * 1.3) < 0.01, "白天在屋舍獵羊 12 × 1.5 × 1.3（%.1f）" % v2)
	var v3: float = gs.ranch_add_attention("calf", "ranch_pasture")
	_check(absf(v3 - 6.0 * 1.3 * 1.5) < 0.01, "同一天再一次 × 1.5（%.1f）" % v3)
	gs.life_log["days_lived"] = 112
	var v4: float = gs.ranch_add_attention("calf", "ranch_pasture")
	gs.life_log["days_lived"] = 116
	var v5: float = gs.ranch_add_attention("calf", "ranch_pasture")
	_check(absf(v4 - 6.0 * 1.3 * 1.3) < 0.01 and absf(v5 - 6.0 * 1.3 * 1.1) < 0.01, "隔 2 天 × 1.3、隔 4 天 × 1.1")
	for i in 10:
		gs.ranch_add_attention("sheep", "ranch_yard")
	_check(gs.ranch_attention() <= 100.0, "上限 100")
	gs.ranch["attention"] = 60.0
	for i in 14:
		gs._decay_ranch_attention()
	var after20: float = gs.ranch_attention()
	for i in 8:
		gs._decay_ranch_attention()
	_check(after20 > 27.0 and after20 < 33.0 and gs.ranch_attention() < 21.0, "每天消退：60 → 14 天約 30、22 天約 20（%.1f、%.1f）" % [after20, gs.ranch_attention()])
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

func _explore_sources(region: String, season_idx: int, n: int) -> Dictionary:
	var gt = root.get_node("GameTime")
	gt.season_index = season_idx
	var out := {}
	for i in n:
		gs.current_region = region
		gs.wolf.stamina = 100.0
		gs.wolf.hunger = 100.0
		gs.ranch["attention"] = 0.0
		var d: Dictionary = gs.action_explore()
		if str(d.get("source_kind", "")) == "prey":
			var k: String = str(d["source"]) + "." + str(d.get("life_stage", "adult"))
			out[k] = int(out.get(k, 0)) + 1
		gs.clear_discovery()
	return out

func _step3() -> void:
	gs.new_game("forest_east")
	gs.pending_events.clear()
	gs.ranch = {"state": "open", "candidate": "A"}
	gd.set_ranch("A")
	# 12. 家畜在哪裡、哪一季
	var summer_p: Dictionary = _explore_sources("ranch_pasture", 1, 150)
	var winter_p: Dictionary = _explore_sources("ranch_pasture", 3, 150)
	_check(int(summer_p.get("cattle.juvenile", 0)) > 0 and int(summer_p.get("cattle.adult", 0)) > 0 and int(summer_p.get("cattle.buck", 0)) > 0, "夏季的放牧地：牛犢、一歲牛、成牛（%s）" % str(summer_p))
	_check(int(winter_p.get("cattle.juvenile", 0)) == 0 and int(winter_p.get("cattle.adult", 0)) > 0, "冬季沒有牛犢（%s）" % str(winter_p))
	var summer_y: Dictionary = _explore_sources("ranch_yard", 1, 150)
	var winter_y: Dictionary = _explore_sources("ranch_yard", 3, 100)
	_check(int(summer_y.get("sheep.adult", 0)) > 0 and int(winter_y.get("sheep.adult", 0)) == 0 and not summer_y.has("sheep.juvenile"), "屋舍與畜欄：夏季有羊、冬季沒有（%s／%s）" % [str(summer_y), str(winter_y)])
	var edge: Dictionary = _explore_sources("ranch_edge", 1, 200)
	var edge_cattle: int = 0
	for k in edge.keys():
		if k.begins_with("cattle"):
			edge_cattle += int(edge[k])
	_check(edge_cattle > 0 and edge_cattle < int(summer_p.get("cattle.adult", 0)) + int(summer_p.get("cattle.juvenile", 0)) + int(summer_p.get("cattle.buck", 0)), "牧場邊緣偶爾有走散的牛（%d）" % edge_cattle)
	var outside: Dictionary = _explore_sources("forest_south", 1, 200)
	_check(not outside.keys().any(func(k): return k.begins_with("cattle") or k.begins_with("sheep")), "牧場外沒有家畜")
	# 13. 注意
	var gt = root.get_node("GameTime")
	gt.period_index = 3
	gs.current_region = "ranch_pasture"
	var cases := [["cattle", "juvenile", 6.0], ["cattle", "adult", 8.0], ["cattle", "buck", 10.0]]
	var ok := true
	for c in cases:
		gs.ranch = {"state": "open", "candidate": "A"}
		var h = gs.start_hunt(c[0], c[1], -1, false, "prairie")
		h.result = 1 # SUCCESS
		gs._ranch_hunt_attention(h)
		if absf(gs.ranch_attention() - float(c[2])) > 0.01:
			ok = false
		gs.clear_discovery()
	gs.current_region = "ranch_yard"
	gs.ranch = {"state": "open", "candidate": "A"}
	var hs = gs.start_hunt("sheep", "adult", -1, false, "clearing")
	hs.result = 1
	gs._ranch_hunt_attention(hs)
	_check(ok and absf(gs.ranch_attention() - 18.0) < 0.01, "夜裡獵到：牛犢 +6、一歲牛 +8、成牛 +10；屋舍的羊 12 × 1.5（%.1f）" % gs.ranch_attention())
	gs.clear_discovery()
	gs.current_region = "ranch_pasture"
	gs.ranch = {"state": "open", "candidate": "A"}
	var hf = gs.start_hunt("cattle", "adult", -1, false, "prairie")
	hf.result = 2
	hf.decisions.append("stalk.creep")
	gs._ranch_hunt_attention(hf)
	var seen_v: float = gs.ranch_attention()
	gs.clear_discovery()
	gs.ranch = {"state": "open", "candidate": "A"}
	var h0 = gs.start_hunt("cattle", "adult", -1, false, "prairie")
	h0.result = 2
	gs._ranch_hunt_attention(h0)
	_check(absf(seen_v - 3.0) < 0.01 and gs.ranch_attention() == 0.0, "出手沒獵到 +3（%.1f）；還沒出手就走不算" % seen_v)
	gs.clear_discovery()
	gs.ranch = {"state": "clues", "candidate": "A"}
	var hc = gs.start_hunt("cattle", "adult", -1, false, "prairie")
	hc.result = 1
	gs._ranch_hunt_attention(hc)
	_check(gs.ranch_attention() == 0.0, "沒開放時不加")
	gs.clear_discovery()

func _step4() -> void:
	var gt = root.get_node("GameTime")
	gs.new_game("forest_east")
	gs.pending_events.clear()
	gs.debug_force_transition("adult")
	gs.ranch = {"state": "open", "candidate": "A"}
	gd.set_ranch("A")
	gs.current_region = "ranch_pasture"
	# 14. 巡查
	var never_dead := true
	var heavy := 0
	var shot := 0
	for i in 600:
		gs.wolf.health = 6.0
		gs.wolf.hunger = 100.0 # 跑很多次、時間會過：不讓牠餓死
		gs.wolf.clear_injury()
		gs.ranch["attention"] = 45.0
		gs.start_ranch_encounter("patrol")
		gs.ranch_encounter_choose(["hide", "retreat", "run"][i % 3])
		if not gs.wolf.alive or gs.wolf.health < 1.0:
			never_dead = false
			break
	_check(never_dead, "巡查不會死（血量 6 的狼 600 次）")
	gs.wolf.health = gs.wolf.health_max
	for i in 600:
		gs.wolf.health = gs.wolf.health_max
		gs.wolf.clear_injury()
		gs.wolf.hunger = 100.0
		gs.start_ranch_encounter("patrol")
		var enc = gs.ranch_enc
		gs.ranch_encounter_choose("hide")
		if enc.shots.size() > 0:
			shot += 1
			if float(enc.shots[0]) >= 20.0:
				_check(gs.wolf.injury == 2, "一槍 %d 是重傷" % int(enc.shots[0])) if heavy == 0 else null
				heavy += 1
	_check(shot > 100 and heavy > 0, "在放牧地趴下躲常被打中（%d／600，其中重傷 %d）" % [shot, heavy])
	var e1 := RanchEncounter.new()
	e1.setup("patrol", gs._ranch_enc_cfg(), {"speed": 60, "perception": 60}, gs.ranch_cover("prairie"), 1)
	var e2 := RanchEncounter.new()
	e2.setup("patrol", gs._ranch_enc_cfg(), {"speed": 60, "perception": 60}, gs.ranch_cover("forest_edge"), 1)
	var e3 := RanchEncounter.new()
	e3.setup("patrol", gs._ranch_enc_cfg(), {"speed": 85, "perception": 60}, gs.ranch_cover("prairie"), 1)
	_check(e2.escape_chance("hide") > e1.escape_chance("hide") + 0.2 and e3.escape_chance("run") > e1.escape_chance("run") + 0.15,
		"躲：林緣 %.0f%% 比草原 %.0f%% 好；跑：速度 85 %.0f%% 比 60 %.0f%% 好" % [e2.escape_chance("hide") * 100, e1.escape_chance("hide") * 100, e3.escape_chance("run") * 100, e1.escape_chance("run") * 100])
	gs.ranch["attention"] = 30.0
	gs.start_ranch_encounter("patrol")
	gs.ranch_enc.rng.seed = 7
	var e_run = gs.ranch_enc
	e_run.cover = 0.0
	gs.ranch_encounter_choose("run")
	_check(e_run.seen and gs.ranch_attention() > 30.0, "往開闊地跑一定被看到（注意 30 → %.1f）" % gs.ranch_attention())
	# 15. 觸發
	gs.pending_events.clear()
	gs.ranch["attention"] = 30.0
	var any_low := false
	for i in 300:
		gs._maybe_ranch_humans()
		if not gs.pending_events.is_empty():
			any_low = true
			gs.pending_events.clear()
	gs.ranch["attention"] = 50.0
	gs.current_region = "forest_north"
	var any_far := false
	for i in 300:
		gs._maybe_ranch_humans()
		if not gs.pending_events.is_empty():
			any_far = true
			gs.pending_events.clear()
	gs.current_region = "ranch_pasture"
	var patrols := 0
	for i in 300:
		gs._maybe_ranch_humans()
		if not gs.pending_events.is_empty():
			patrols += 1
			gs.pending_events.clear()
	_check(not any_low and not any_far and patrols > 10, "巡查只在注意 40 以上、牧場一帶（%d／300 個時段）" % patrols)
	gs.ranch["attention"] = 80.0
	gs.ranch["warned"] = false
	gs._maybe_ranch_humans()
	var first: String = str(gs.pending_events[0]["type"]) if not gs.pending_events.is_empty() else ""
	gs.pending_events.clear()
	var hunts := 0
	for i in 200:
		gs._maybe_ranch_humans()
		if gs.pending_events.any(func(e): return str(e.get("kind", "")) == "hunt"):
			hunts += 1
		gs.pending_events.clear()
	_check(first == "ranch_warning" and hunts > 10, "注意 70 以上：先預警，之後才追獵（%s，%d／200）" % [first, hunts])
	gs.start_ranch_encounter("hunt")
	gs.ranch_enc = null
	var tracked: bool = gs.ranch_tracking()
	gs.current_region = "ranch_edge"
	gs.wolf.stamina = 100.0
	gs.action_move("forest_south")
	_check(tracked and not gs.ranch_tracking() and gs.ranch_attention() > 70.0, "追獵後換地圖就甩掉，注意不變（%.0f）" % gs.ranch_attention())
	# 16. 追獵
	gs.current_region = "ranch_pasture"
	var dead := 0
	var repelled := 0
	var broke := 0
	var caught := 0
	var n := 400
	for i in n:
		gs.wolf.alive = true
		gs.wolf.health = gs.wolf.health_max
		gs.wolf.stamina = 80.0
		gs.wolf.clear_injury()
		gs.wolf.hunger = 100.0
		gs.start_ranch_encounter("hunt")
		var enc = gs.ranch_enc
		gs.ranch_auto_play()
		if enc.result == "killed":
			dead += 1
		if enc.result == "repelled":
			repelled += 1
		if enc.rounds > 1:
			caught += 1
		if enc.events.any(func(e): return str(e["key"]) == "hunt.dog.broke_free"):
			broke += 1
	_check(dead > 0 and dead < n * 0.2 and repelled + broke > 0, "追獵（放牧地、健康的成年狼、照本能）：被狗追上 %d、咬退狗 %d、掙脫 %d、被打死 %d／%d" % [caught, repelled, broke, dead, n])
	var rep2 := 0
	for i in 200:
		gs.wolf.alive = true
		gs.wolf.health = gs.wolf.health_max
		gs.wolf.hunger = 100.0
		gs.start_ranch_encounter("hunt")
		var enc2 = gs.ranch_enc
		var g := 0
		while not enc2.done and g < 30:
			g += 1
			gs.ranch_encounter_choose("run" if enc2.stage == "escape" else "fight_dog")
		if enc2.result == "repelled":
			rep2 += 1
	_check(rep2 > 0, "一直咬退狗也走得通（%d／200 把狗全咬退）" % rep2)
	gs.wolf.alive = true
	gs.wolf.health = 20.0
	var killed := false
	for i in 200:
		gs.wolf.alive = true
		gs.wolf.health = 20.0
		gs.start_ranch_encounter("hunt")
		gs.ranch_auto_play()
		if not gs.wolf.alive:
			killed = gs.wolf.death_cause == "human"
			break
	_check(killed, "受傷的狼被追獵可能被打死（死因 human）")
	# 17. 吃到一半
	gs.wolf.alive = true
	gs.wolf.health = gs.wolf.health_max
	gs.current_region = "ranch_pasture"
	gs.ranch["attention"] = 50.0
	var interrupts := 0
	for i in 200:
		gs.start_feeding("cattle", "adult", "prairie")
		gs.wolf.hunger = 20.0
		var r: Dictionary = gs.feed_once()
		if str(r.get("event", "")) == "ranch_patrol":
			interrupts += 1
		gs.current_feeding = {}
	gs.start_feeding("cattle", "adult", "prairie")
	gs.wolf.hunger = 20.0
	var seg: float = float(gs.current_feeding["segment_value"])
	gs.start_ranch_encounter("eating", "prairie")
	gs.ranch_encounter_choose("grab")
	var grabbed_ok: bool = not gs.is_feeding() and absf(gs.wolf.hunger - 20.0 - seg) < 0.1
	gs.start_feeding("cattle", "adult", "prairie")
	gs.start_ranch_encounter("eating", "prairie")
	gs.ranch_encounter_choose("drop")
	var dropped_ok: bool = not gs.is_feeding()
	_check(interrupts > 10 and grabbed_ok and dropped_ok, "牧場吃到一半被打斷（%d／200 段）；叼一段跑多吃一段、殘骸沒了；丟下就沒了" % interrupts)
	gs.current_region = "forest_south"
	gs.start_feeding("white_tailed_deer", "adult", "forest_edge")
	var outside := 0
	for i in 100:
		var r2: Dictionary = gs.feed_once()
		if str(r2.get("event", "")) == "ranch_patrol":
			outside += 1
		if not gs.is_feeding():
			gs.start_feeding("white_tailed_deer", "adult", "forest_edge")
	gs.current_feeding = {}
	_check(outside == 0, "牧場外吃東西不會被巡查打斷")

func _ap_ready(ap, region: String, hunger: float, att: float) -> void:
	gs.current_region = region
	gs.wolf.hunger = hunger
	gs.wolf.stamina = 100.0
	gs.wolf.health = gs.wolf.health_max
	gs.wolf.clear_injury()
	gs.ranch["attention"] = att
	ap._relocate_to = ""

func _step5() -> void:
	var AP = load("res://scripts/core/AutoPlayer.gd")
	gs.new_game("forest_east")
	gs.pending_events.clear()
	gs.debug_force_transition("adult")
	# 18. 策略
	var ok_pol: bool = AP.new("all", "cautious").ranch_policy == "never" and AP.new("all", "average").ranch_policy == "sometimes" \
		and AP.new("all", "assault").ranch_policy == "often"
	var rt = AP.new("all", "average")
	rt.start_routine(3, "big")
	rt.finish()
	gs.auto_playing = false
	_check(ok_pol and rt.ranch_policy == "never", "牧場策略照打法：謹慎 never、平均 sometimes、強攻 often；照常過日子 never")
	var ap = AP.new("all", "average")
	gs.ranch = {}
	gd.set_ranch("")
	_ap_ready(ap, "forest_east", 40.0, 0.0)
	_check(not ap._ranch_step() and gs.current_region == "forest_east", "牧場沒開放時不動")
	gs.ranch = {"state": "open", "candidate": "A"}
	gd.set_ranch("A")
	# 19. 去不去
	_ap_ready(ap, "forest_east", 50.0, 0.0)
	var d0: int = ap._ranch_dist("forest_east")
	var went: bool = ap._ranch_step() and ap._ranch_dist(gs.current_region) < d0
	_ap_ready(ap, "forest_east", 80.0, 0.0)
	var full_stay: bool = not ap._ranch_step() and gs.current_region == "forest_east"
	_ap_ready(ap, "forest_east", 50.0, 45.0)
	var att_stay: bool = not ap._ranch_step() and gs.current_region == "forest_east"
	_ap_ready(ap, "ranch_pasture", 50.0, 0.0)
	var hunt_here: bool = not ap._ranch_step() and ap._ranch_hunting and gs.current_region == "ranch_pasture"
	_check(went and full_stay and att_stay and hunt_here, "sometimes：餓了、注意低才往牧場走（離牧場 %d 步）；不餓、注意 45 不去；在放牧地留下來找家畜" % d0)
	var nv = AP.new("all", "cautious")
	_ap_ready(nv, "ranch_pasture", 50.0, 0.0)
	_check(nv._ranch_step() and gs.current_region != "ranch_pasture", "never：在牧場裡就離開")
	# 20. 離開、搬巢穴
	_ap_ready(ap, "forest_south", 80.0, 45.0)
	var left: bool = ap._ranch_step() and not ap._in_ranch_area(gs.current_region)
	var oft = AP.new("all", "assault")
	_ap_ready(oft, "forest_south", 80.0, 45.0)
	oft._ranch_step() # often 注意 45 還會去（往放牧地走），不會離開牧場一帶
	var often_stays: bool = oft._in_ranch_area(gs.current_region)
	_ap_ready(oft, "forest_south", 80.0, 72.0)
	var often_left: bool = oft._ranch_step() and not oft._in_ranch_area(gs.current_region)
	_check(left and often_stays and often_left, "注意到了就離開牧場一帶：sometimes 45 離開、often 45 不走、often 72 離開")
	gs.den_region = "forest_south"
	_ap_ready(ap, "forest_east", 80.0, 45.0)
	var home: String = ap._home_region()
	var temp_home: bool = home != "forest_south" and not ap._in_ranch_area(home) and gd.map_of(home) == "forest"
	_ap_ready(oft, "forest_south", 80.0, 75.0)
	for i in 12:
		if gs.den_region != "forest_south":
			break
		gs.ranch["attention"] = 75.0
		oft._ranch_step()
	var moved: bool = gs.den_region != "forest_south" and not oft._in_ranch_area(gs.den_region) and oft.ranch_moves == 1
	_ap_ready(ap, "forest_east", 80.0, 75.0)
	gs.den_region = "forest_east"
	ap._ranch_step()
	_check(temp_home and moved and ap._relocate_to == "", "巢穴在牧場一帶：注意 45 先待在 %s；75 搬到 %s；巢穴不在那一帶不搬" % [home, gs.den_region])
