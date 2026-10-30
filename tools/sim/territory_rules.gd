extends SceneTree
# Phase 3 第 4 步「領域與鄰群」的回歸測試（SPEC Phase 3「領域與鄰群」）：
#   1. 每一區屬於誰：地圖上的鄰群有領域（core）與相鄰（border）；住在地圖外的只有邊界那一區
#   2. 撞上鄰群：每個時段擲；之後這一群冷卻；事件帶著是哪一群
#   3. 對峙的勝算主要看數量：伴侶跟著時比較高
#   4. 嚎叫的那天：一個人嚎叫 × 1.5（引來），和伴侶一起嚎叫 × 0.6（宣示領域）
#   5. 試探：你的標記淡掉、和牠們相鄰 → 被試探；換季時沒補就變成牠們的（地圖外的只清掉你的標記）
#   6. 在牠們領域的邊緣對峙贏了、你也標記了：換季時變成你的（牠們留下核心）
#   7. 有伴侶後地盤最多 3 區
#   8. 解散的鄰群：幾季後有新的一對搬進來
#   9. 鄰群的領域裡大、中型獵物少一點
# 用法：bash tools/run_sim.sh territory_rules
var gs
var gt
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _mate() -> void:
	gs._spawn_she_wolf()
	var n = gs.she_wolf()
	n.territory = gs.current_region
	n.relation = 8
	gs.she_approach()
	gs.pending_events.clear()

func _run() -> void:
	var data = root.get_node("GameData")
	var meet: Dictionary = data.balance["black_pack"]["meet"]
	# 1
	gs.new_game("mountain_foothills")
	gs.wolf.age_years = 3.0
	var mp = gs.pack_by_id("mountain")
	_check(gs.pack_zone_of(mp, "mountain_canyon") == "core" and gs.pack_zone_of(mp, "mountain_meadow") == "border" and gs.pack_zone_of(mp, "mountain_foothills") == "", "山地的鄰群：峽谷是領域、高山草甸相鄰、山腳（你的巢穴）不是")
	var fo = gs.pack_by_id("forest_outer")
	_check(gs.pack_zone_of(fo, "forest_west") == "border" and gs.pack_zone_of(fo, "forest_east") == "", "森林地圖外的一群：只在森林西部")
	# 2
	meet["core_chance"] = 1.0
	gs.current_region = "mountain_canyon"
	gs.events_today = 0
	gs.pending_events.clear()
	gs._maybe_neighbor_meet()
	var ev: Dictionary = gs.pending_events[0] if not gs.pending_events.is_empty() else {}
	_check(str(ev.get("type", "")) == "pack_meet" and str(ev.get("pack", "")) == "mountain", "撞上山地的鄰群（事件帶著是哪一群）")
	gs.pending_events.clear()
	gs.events_today = 0
	gs._maybe_neighbor_meet()
	_check(gs.pending_events.is_empty() and gs.is_quiet("mountain"), "之後這一群冷卻")
	meet["core_chance"] = 0.04
	# 3（成年狼常見的能力值；new_game 的能力還是小狼的，兩邊都會卡在最低勝算）
	for st in [["speed", 66.0], ["skill", 62.0], ["strength", 70.0], ["perception", 70.0]]:
		gs.debug_set_stat(st[0], st[1])
	gs.meet_pack_id = "mountain"
	var solo: float = gs.pack_standoff_chance()
	gs.current_region = "mountain_foothills"
	_mate()
	var team: float = gs.pack_standoff_chance()
	_check(team > solo, "對峙的勝算看數量：一隻 %.0f%% → 和伴侶 %.0f%%" % [solo * 100.0, team * 100.0])
	# 4
	gs.life_log["howled_day"] = gs._today()
	var together: float = gs._howl_meet_mult()
	gs.she_wolf().task = "den"
	var alone: float = gs._howl_meet_mult()
	gs.she_wolf().task = "follow"
	_check(is_equal_approx(alone, 1.5) and is_equal_approx(together, 0.6), "嚎叫的那天：一個人 ×%.1f、和伴侶一起 ×%.1f" % [alone, together])
	gs.life_log["howled_day"] = -1
	# 7
	_check(gs.territory_max() == 3, "有伴侶後地盤最多 3 區")
	# 5
	gs.new_game("mountain_foothills")
	gs.wolf.age_years = 3.0
	mp = gs.pack_by_id("mountain")
	mp.regions = ["mountain_canyon"]
	gs.life_log["marks"] = {"mountain_meadow": gs._today() - 10}
	data.balance["black_pack"]["probe"]["faded_chance"] = 1.0
	gs._probe_by(mp)
	_check((gs.life_log.get("pack_probe.mountain", {}) as Dictionary).has("mountain_meadow"), "標記淡掉、和牠們相鄰：被試探")
	var taken: Array = gs._take_probed_by(mp)
	_check(taken == ["mountain_meadow"] and mp.regions.has("mountain_meadow") and not gs.life_log["marks"].has("mountain_meadow"), "換季時沒補：變成牠們的")
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	fo = gs.pack_by_id("forest_outer")
	gs.life_log["marks"] = {"forest_west": gs._today() - 10}
	gs._probe_by(fo)
	var t2: Array = gs._take_probed_by(fo)
	_check(t2.is_empty() and not gs.life_log["marks"].has("forest_west") and fo.regions.is_empty(), "地圖外的一群：只清掉你的標記，不佔")
	data.balance["black_pack"]["probe"]["faded_chance"] = 0.3
	# 6
	gs.new_game("mountain_foothills")
	gs.wolf.age_years = 3.0
	mp = gs.pack_by_id("mountain")
	mp.regions = ["mountain_canyon", "mountain_meadow"]
	gs.current_region = "mountain_meadow"
	gs.meet_pack_id = "mountain"
	var so: Dictionary = data.balance["black_pack"]["meet"]["standoff"]
	so["min"] = 1.0
	so["max"] = 1.0
	var r: Dictionary = gs.pack_standoff()
	so["min"] = 0.03
	so["max"] = 0.6
	gs.action_mark()
	gs._settle_pack_claims()
	_check(r["won"] and not mp.regions.has("mountain_meadow") and mp.regions.has("mountain_canyon"), "在牠們領域的邊緣對峙贏了、你也標記了：換季時變成你的（%s）" % str(mp.regions))
	_check(gs.life_events("territory.won").size() == 1 and gs.pack_attitude_of(mp) == "wary", "寫進生命事件；牠們之後戒備你")
	# 8
	mp.stage = "gone"
	mp.regions = []
	gs.life_log["pack_gone_mountain"] = 0
	var seasons := 0
	while mp.stage == "gone" and seasons < 10:
		gs._update_neighbor_packs()
		seasons += 1
	_check(mp.stage == "pair" and mp.regions.size() == 1 and gs.npcs.has(mp.leader_id), "解散的鄰群：%d 季後有新的一對搬進來" % seasons)
	# 9
	var pm: Dictionary = gs.prey_mults(str(mp.regions[0]))
	_check(float(pm.get("mule_deer", 1.0)) < 1.0, "鄰群的領域裡騾鹿少一點（× %.2f）" % float(pm.get("mule_deer", 1.0)))
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
