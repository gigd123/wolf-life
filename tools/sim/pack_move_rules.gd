extends SceneTree
# Phase 3d 第 2 步：核心區連贏 2 次就搬到別張地圖。
#   1. 同一天贏兩次只算一次；不同天贏兩次 → 搬家（換地圖、核心在那張地圖、帶頭的範圍跟著、原本的核心不再是牠們的）
#   2. 邊界區贏不算；換季重新算
#   3. 搬家的消息記著原本的地圖，回到那張地圖的季節卡片才寫；黑狼一家換季的消息照牠住的地圖
#   4. 鄰群（山地）也一樣會搬
#   5. 第 3 步：同一張地圖兩群 → 換季衝突，輸的搬走、贏的損失比輸的少、消息記在那張地圖；一次最多一場；開局沒有衝突
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
	# 第 3 步：狼群之間的衝突
	gs.new_game("forest_east")
	gs.wolf.age_years = 4.0
	bp = gs.black_pack
	bp.stage = "pack"
	bp.mate_age = 4.0
	bp.young = [1.5, 2.0, 2.5]
	var mtn = gs.pack_by_id("mountain")
	mtn.young = [1.5]
	bp.map_id = "mountain"
	var mcore: String = str(mtn.regions[0])
	var other: Array = root.get_node("GameData").map_regions("mountain").filter(func(r): return str(r) != mcore)
	bp.regions = [str(other[0])]
	gs.stranger_territory = str(other[0])
	var gl = gs.pack_by_id("grassland")
	var before_sizes := {"black": bp.young.size(), "mountain": mtn.young.size()}
	var cr: Dictionary = gs._pack_conflicts()
	_ok(not cr.is_empty() and str(cr["map"]) == "mountain", "同一張地圖兩群：換季時起衝突（%s）" % str(cr))
	var loser = gs.pack_by_id(str(cr.get("loser", "")))
	var winner = gs.pack_by_id(str(cr.get("winner", "")))
	_ok(loser != null and loser.map_id != "mountain" and winner.map_id == "mountain", "輸的搬走（到 %s）、贏的留下" % (loser.map_id if loser != null else "?"))
	_ok(int(cr.get("winner_loss", 0)) < int(cr.get("loser_loss", 0)), "贏的損失比輸的少（贏 %d、輸 %d）" % [int(cr.get("winner_loss", 0)), int(cr.get("loser_loss", 0))])
	var nw: Array = gs.life_log.get("pack_news", [])
	_ok(not nw.is_empty() and str(nw.back().get("event", "")) == "conflict" and str(nw.back().get("map", "")) == "mountain", "消息記在衝突的那張地圖（山地）")
	_ok(gs.life_events("pack.conflict").size() == 1, "寫進生命事件")
	# 每季最多一場：兩張地圖都有兩群時，一次只處理一張
	gs.new_game("forest_east")
	bp = gs.black_pack
	bp.stage = "pack"
	bp.mate_age = 4.0
	bp.young = [1.5]
	mtn = gs.pack_by_id("mountain")
	gl = gs.pack_by_id("grassland")
	bp.map_id = "mountain"
	bp.regions = [str(root.get_node("GameData").map_regions("mountain").filter(func(r): return str(r) != str(mtn.regions[0]))[0])]
	var fo = gs.pack_by_id("forest_outer")
	var n_conf := 0
	gs._pack_conflicts()
	for e in gs.life_events("pack.conflict"):
		n_conf += 1
	_ok(n_conf == 1, "一次換季最多一場衝突（%d）" % n_conf)
	# 沒有共住的地圖：沒有衝突
	gs.new_game("forest_east")
	_ok(gs._pack_conflicts().is_empty(), "開局的配置（每張地圖一群）：沒有衝突")
	print("全部通過" if fails == 0 else "有失敗 %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
