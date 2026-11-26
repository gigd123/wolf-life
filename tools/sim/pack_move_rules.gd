extends SceneTree
# Phase 3d 第 2 步：核心區連贏 2 次就搬到別張地圖。
#   1. 同一天贏兩次只算一次；不同天贏兩次 → 搬家（換地圖、核心在那張地圖、帶頭的範圍跟著、原本的核心不再是牠們的）
#   2. 邊界區贏不算；換季重新算
#   3. 搬家的消息記著原本的地圖，回到那張地圖的季節卡片才寫；黑狼一家換季的消息照牠住的地圖
#   4. 鄰群（山地）也一樣會搬
# 用法：bash tools/run_sim.sh pack_move_rules
var f := 0
var fails := 0

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
	print(("  ✓ " if c else "  ✗ ") + msg)

func _setup(gs):
	gs.new_game("forest_east")
	gs.wolf.age_years = 4.0
	var bp = gs.black_pack
	bp.stage = "pack"
	bp.mate_age = 4.0
	bp.young = [1.5]
	bp.map_id = "forest"
	bp.regions = ["forest_south"]
	gs.stranger_territory = "forest_south"
	gs.current_region = "forest_south"
	return bp

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 8
	var gs = root.get_node("GameState")
	var bp = _setup(gs)
	gs._standoff_won_here(bp)
	gs._standoff_won_here(bp)
	_ok(bp.map_id == "forest" and bp.regions == ["forest_south"], "同一天贏兩次只算一次：還在森林南部")
	gs.life_log["days_lived"] = int(gs.life_log.get("days_lived", 1)) + 1
	gs._standoff_won_here(bp)
	_ok(bp.map_id != "forest" and not bp.regions.is_empty() and root.get_node("GameData").map_of(str(bp.regions[0])) == bp.map_id, "不同天第二次：搬到別張地圖（%s %s）" % [bp.map_id, str(bp.regions)])
	_ok(gs.last_relocation == bp.map_id, "這次的勝利寫明搬去哪（%s）" % gs.last_relocation)
	_ok(gs.stranger_territory == str(bp.regions[0]), "帶頭的黑狼的範圍跟著搬")
	_ok(gs.pack_zone("forest_south") == "", "原本的核心不再是牠們的")
	var news: Array = gs.life_log.get("pack_news", [])
	_ok(not news.is_empty() and str(news.back().get("event", "")) == "moved" and str(news.back().get("map", "")) == "forest", "搬家的消息記在原本的地圖（森林）")
	_ok(gs.life_events("pack.moved").size() == 1, "寫進生命事件")
	# 邊界區不算、換季重算
	bp = _setup(gs)
	gs.current_region = "forest_east" if gs.pack_zone_of(bp, "forest_east") == "border" else "forest_north"
	for k in 3:
		gs.life_log["days_lived"] = int(gs.life_log.get("days_lived", 1)) + 1
		gs._standoff_won_here(bp)
	_ok(bp.map_id == "forest", "邊界區贏不算（%s）" % gs.current_region)
	gs.current_region = "forest_south"
	gs._standoff_won_here(bp)
	root.get_node("GameTime").season_index = (root.get_node("GameTime").season_index + 1) % 4
	gs.life_log["days_lived"] = int(gs.life_log.get("days_lived", 1)) + 1
	gs._standoff_won_here(bp)
	_ok(bp.map_id == "forest", "換季重新算：上一季贏的一次不算")
	# 鄰群也會搬
	gs.new_game("mountain_foothills")
	gs.wolf.age_years = 4.0
	var mp = gs.pack_by_id("mountain")
	var core: String = str(mp.regions[0])
	gs.current_region = core
	gs._standoff_won_here(mp)
	gs.life_log["days_lived"] = int(gs.life_log.get("days_lived", 1)) + 1
	gs._standoff_won_here(mp)
	_ok(mp.map_id != "mountain" and root.get_node("GameData").map_of(str(mp.regions[0])) == mp.map_id, "山地的鄰群也會搬（%s %s）" % [mp.map_id, str(mp.regions)])
	print("全部通過" if fails == 0 else "有失敗 %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
