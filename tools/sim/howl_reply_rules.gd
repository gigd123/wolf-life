extends SceneTree
# Phase 3c 第 2 步：嚎叫的回應。
# 不花回合、體力；同一個時段同一區回應固定（再嚎不重新判定、不重複累加注意）；換時段或移動後重新判定；
# 回應者：還沒成為伴侶的離群母狼、鄰群、黑狼一家；最多 3 個、越近越先；文字不寫身分；時段倍率；
# 聽得到的範圍（同一張地圖；別張地圖只有直接相連的區域聽得到、算遠處）；狼群注意你（核心 × 3、邊界 × 2、不疊加）。
# 用法：bash tools/run_sim.sh howl_reply_rules
var f := 0
var fails := 0
var gs
var gt

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _fresh(region: String) -> void:
	gs.life_log.erase("howl_cache")
	gs.life_log.erase("pack_alert")
	gs.current_region = region

func _black_pack(region: String) -> void:
	gs.black_pack.stage = "pack"
	gs.black_pack.regions = [region]
	gs.black_pack.young = [1.5, 1.5, 0.5]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	var cfg: Dictionary = root.get_node("GameData").balance["mate"]
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.wolf.age_years = 3.0
	gs.events_today = 0
	gt.season_index = 2
	gt.period_index = gt.PERIODS.find("night")
	# 不花回合、體力
	var turn0: int = gs._abs_turn()
	var st0: float = gs.wolf.stamina
	gs.action_howl()
	_ok(gs._abs_turn() == turn0 and is_equal_approx(gs.wolf.stamina, st0), "嚎叫不花回合、不花體力")
	# 母狼在兩區外：回應寫「較遠」
	cfg["enter_chance"] = {"spring": 1.0, "summer": 1.0, "autumn": 1.0, "winter": 1.0}
	gs._update_she_wolf()
	var n = gs.she_wolf()
	_ok(n != null, "有一隻離群母狼")
	var hr: Dictionary = {}
	var she_far := 0
	for i in 200:
		_fresh("forest_east")
		n.territory = "forest_west"
		hr = gs.action_howl()
		for r in hr["replies"]:
			if str(r["who"]) == "she":
				she_far += 1
				_ok(str(r["dist"]) == "far" and str(r["region"]) == "forest_west", "母狼在兩區外：較遠、那一帶是牠在的區域（%s）" % str(r))
	_ok(she_far > 40 and she_far < 160, "兩區外的母狼有時回應（200 次 %d）" % she_far)
	# 同一個時段同一區：回應固定、不重新判定
	_fresh("forest_east")
	var a: Dictionary = gs.action_howl()
	var same := true
	for i in 10:
		var b: Dictionary = gs.action_howl()
		if not b["repeat"] or str(b["replies"]) != str(a["replies"]):
			same = false
	_ok(same, "同一個時段同一區：再嚎是同一個回應")
	gs.current_region = "forest_north"
	_ok(not gs.action_howl()["repeat"], "移動後重新判定")
	gt.period_index = gt.PERIODS.find("dawn")
	_ok(not gs.action_howl()["repeat"], "換時段後重新判定")
	# 時段倍率
	var day := 0
	var night := 0
	for i in 1000:
		_fresh("forest_east")
		n.territory = "forest_west"
		gt.period_index = gt.PERIODS.find("day")
		day += gs.action_howl()["replies"].filter(func(r): return str(r["who"]) == "she").size()
		_fresh("forest_east")
		gt.period_index = gt.PERIODS.find("night")
		night += gs.action_howl()["replies"].filter(func(r): return str(r["who"]) == "she").size()
	_ok(day < night * 0.5, "白天的回應比夜裡少很多（白天 %d、夜裡 %d）" % [day, night])
	# 文字不寫身分
	var bad := false
	for kind in ["one", "few", "many"]:
		for dist in ["near", "far", "remote"]:
			var t: String = TranslationServer.translate("howl.reply.%s.%s" % [kind, dist])
			for w in ["母狼", "離群", "黑狼", "伴侶", "狼群"]:
				if t.find(w) >= 0:
					bad = true
					print("  身分字眼：", kind, ".", dist, " ", w)
	_ok(not bad, "回應的文字不寫身分")
	# 黑狼一家：在牠們的領域嚎叫 → 注意 × 3；邊界 × 2；兩區外沒有；不疊加
	_black_pack("forest_west")
	n.territory = "forest_north"
	gt.period_index = gt.PERIODS.find("night")
	var come_cfg: float = float(cfg["howl_reply"]["alert"]["core"]["come"])
	cfg["howl_reply"]["alert"]["core"]["come"] = 0.0
	_fresh("forest_west")
	gs.action_howl()
	_ok(is_equal_approx(gs.pack_alert_mult("black"), 3.0), "在黑狼一家的領域嚎叫：注意 × 3（%.1f）" % gs.pack_alert_mult("black"))
	var until0: int = int(gs.life_log["pack_alert"]["black"]["until"])
	gs.action_howl()
	gs.action_howl()
	_ok(int(gs.life_log["pack_alert"]["black"]["until"]) == until0 and is_equal_approx(gs.pack_alert_mult("black"), 3.0), "同一個時段再嚎：注意不重複累加")
	_fresh("forest_south")
	gs.action_howl()
	_ok(is_equal_approx(gs.pack_alert_mult("black"), 2.0), "在邊界嚎叫：注意 × 2（%.1f）" % gs.pack_alert_mult("black"))
	_fresh("forest_east")
	_ok(gs._map_steps("forest_east", "forest_west") >= 2, "森林東部離森林西部兩步以上")
	gs.action_howl()
	_ok(is_equal_approx(gs.pack_alert_mult("black"), 1.0), "離兩區以上嚎叫：沒有影響")
	# 核心連嚎兩個時段：倍率還是 × 3（只延長）
	_fresh("forest_west")
	gs.action_howl()
	gt.period_index = gt.PERIODS.find("predawn")
	gs.action_howl()
	_ok(is_equal_approx(gs.pack_alert_mult("black"), 3.0), "連嚎兩個時段：倍率不疊加（%.1f）" % gs.pack_alert_mult("black"))
	# 核心：牠們可能直接循聲過來
	cfg["howl_reply"]["alert"]["core"]["come"] = 1.0
	gs.life_log.erase("quiet_until")
	_fresh("forest_west")
	gs.pending_events.clear()
	var hc: Dictionary = gs.action_howl()
	_ok(not hc["pack_event"].is_empty() and gs.pending_events.size() > 0, "在核心嚎叫：牠們循聲過來（%s）" % str(hc["pack_event"].get("type", "")))
	cfg["howl_reply"]["alert"]["core"]["come"] = come_cfg
	# 最多 3 個、越近越先
	cfg["howl_reply"]["pack"] = {"near": 1.0, "far": 1.0, "remote": 1.0}
	cfg["howl_reply"]["she"] = {"near": 1.0, "far": 1.0}
	_fresh("forest_east")
	gs.pending_events.clear()
	var many: Array = gs.action_howl()["replies"]
	_ok(many.size() <= 3, "最多 3 個回應（%d）" % many.size())
	var ranks := {"near": 0, "far": 1, "remote": 2}
	var sorted := true
	for i in range(1, many.size()):
		if int(ranks[str(many[i]["dist"])]) < int(ranks[str(many[i - 1]["dist"])]):
			sorted = false
	_ok(sorted, "越近越先（%s）" % str(many.map(func(r): return r["dist"])))
	# 聽得到的範圍：在沒有緊貼森林的苔原區域聽不到黑狼一家；在緊貼森林的那一區聽得到（遠處）
	n.territory = "forest_east"
	_fresh("tundra_north")
	var heard_far: bool = gs.action_howl()["replies"].any(func(r): return str(r["who"]) == "black")
	_ok(not heard_far, "苔原北部（不緊貼森林）聽不到黑狼一家")
	_fresh("tundra_south")
	var rs: Array = gs.action_howl()["replies"].filter(func(r): return str(r["who"]) == "black")
	_ok(rs.size() == 1 and str(rs[0]["dist"]) == "remote" and str(rs[0]["region"]) == "forest_north", "苔原南部（和森林北部相連）：黑狼一家是遠處、從森林北部那一帶（%s）" % str(rs))
	cfg["howl_reply"]["pack"] = {"near": 0.55, "far": 0.3, "remote": 0.25}
	cfg["howl_reply"]["she"] = {"near": 0.6, "far": 0.3}
	# 母狼就在這一區：照原本的循聲走過來
	gs.current_region = "forest_east"
	n.territory = "forest_east"
	cfg["howl"]["come_chance"] = 1.0
	_fresh("forest_east")
	var hs: Dictionary = gs.action_howl()
	_ok(hs["came"] and str(gs.current_discovery.get("kind", "")) == "she_wolf", "母狼就在這一區：循聲走過來")
	cfg["howl"]["come_chance"] = 0.5
	print("嚎叫回應的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
