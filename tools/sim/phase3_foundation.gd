extends SceneTree
# Phase 3 第 1 步「基礎」的回歸測試（SPEC Phase 3「狼的資料結構」「鄰群的配置」「狼群成員」「衝突與戰鬥」）：
#   1. 開局照 packs.layout 建立鄰群：住在地圖上的核心在離巢穴最遠的區域，地圖外的只有邊界區；帶頭的是具名 NPC
#   2. 上限：未滿 1 歲的幼狼不算；超過時秋冬換季才離開（最年長的先走），生幼狼不受上限
#   3. 地圖外的狼群剩帶頭的一隻時，領域不會變成牠的範圍
#   4. 生命事件：成年、死亡寫進紀錄，可以依種類篩選
#   5. 各對手的冷卻：互不影響、時間到就解除
#   6. 事件上限的例外：cap_exempt 的種類不受每天的上限、也不佔名額
#   7. 存檔 → 讀檔：鄰群、NPC 的新欄位、玩家的性別都一樣
#   8. 鄰群跑 15 年的換季：不會壞、平均 4～8 隻、秋冬離群後九成在上限以內、換代時建立新的帶頭的
# 用法：bash tools/run_sim.sh phase3_foundation
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

func _run() -> void:
	var data = root.get_node("GameData")
	var WP = load("res://scripts/core/WolfPack.gd")
	var NPC = load("res://scripts/core/NpcWolf.gd")
	# 1. 開局
	gs.new_game("mountain_foothills")
	var layout: Array = data.balance["packs"]["layout"]
	_check(gs.neighbor_packs.size() == layout.size(), "鄰群數量照 layout（%d）" % gs.neighbor_packs.size())
	var mountain = gs.pack_by_id("mountain")
	_check(mountain != null and mountain.regions == ["mountain_canyon"], "巢穴在山腳：山地的鄰群核心在最遠的峽谷（%s）" % str(mountain.regions if mountain else []))
	var outer = gs.pack_by_id("forest_outer")
	_check(outer != null and outer.off_map and outer.regions.is_empty() and outer.border == "forest_west", "森林地圖外的一群：只有邊界區（森林西部）")
	var ok_leaders := true
	for p in gs.neighbor_packs:
		var l = gs.npcs.get(p.leader_id, null)
		if l == null or l.pack_id != p.id or l.config_key() != "pack_breeder" or p.stage not in ["pair", "pack"] or not p.has_mate():
			ok_leaders = false
	_check(ok_leaders, "每一群帶頭的是具名 NPC（所屬、設定正確），一開始是一對或狼群")
	var grass = gs.pack_by_id("grassland")
	_check(grass != null and data.map_regions("grassland").has(str(grass.regions[0])), "巢穴不在草原：草原的鄰群核心在草原的某一區（%s）" % str(grass.regions))
	# 2. 上限
	var cfg: Dictionary = data.balance["black_pack"]
	var keep_over = cfg["over_cap_disperse"]
	cfg["over_cap_disperse"] = 1.0
	var keep_disperse = cfg["disperse_per_season"]
	cfg["disperse_per_season"] = {"autumn": 0.0001, "winter": 0.0001}
	var leader = NPC.create("stranger_wolf", "forest_north")
	leader.age_years = 4.0
	var p = WP.new()
	p.regions = ["forest_north"]
	p.stage = "pack"
	p.mate_age = 4.0
	p.young = [0.0, 0.0, 0.0, 0.0, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 3.0]
	_check(p.counted_size(true) == 9 and p.size(true) == 13, "未滿 1 歲的不算進上限（算進 %d、全部 %d）" % [p.counted_size(true), p.size(true)])
	p.young = [1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.25]
	p.on_season_passed({"season": "summer", "leader": leader, "player_age": 3.0})
	_check(p.counted_size(true) == 12, "夏季超過上限不會立刻離開（%d）" % p.counted_size(true))
	p.on_season_passed({"season": "autumn", "leader": leader, "player_age": 3.0, "expand": false})
	_check(p.counted_size(true) == 10 and not p.young.has(3.75) and not p.young.has(3.5), "秋季超過的離開，最年長的先走（%d，%s）" % [p.counted_size(true), str(p.young)])
	cfg["pup_chance"] = 1.0
	var keep_survival = cfg["pup_survival_per_season"]
	cfg["pup_survival_per_season"] = 1.0
	p.on_season_passed({"season": "spring", "leader": leader, "player_age": 3.0})
	_check(p.pups() >= 3, "滿了也照樣生幼狼（%d 隻）" % p.pups())
	cfg["disperse_per_season"] = keep_disperse
	cfg["over_cap_disperse"] = keep_over
	cfg["pup_survival_per_season"] = keep_survival
	# 3. 地圖外剩一隻
	var o = WP.new()
	o.kind = "neighbor"
	o.off_map = true
	o.border = "forest_west"
	o.stage = "solo"
	var ol = NPC.create("pack_x", "forest_west", "pack_breeder")
	o.on_season_passed({"season": "summer", "leader": ol, "player_age": 3.0, "expand": false})
	_check(o.regions.is_empty(), "地圖外的狼群剩一隻：領域不會變成邊界區（%s）" % str(o.regions))
	# 4. 生命事件
	gs.new_game("forest_east")
	gs.wolf.age_years = 2.0
	gs._check_life_stage_transition(0)
	gs.add_life_event("test", {"who": "x"})
	_check(gs.life_events("adult").size() == 1 and gs.life_events().size() >= 2, "成年寫進生命事件，可以依種類篩選")
	_check(str(gs.life_events("test")[0].get("who", "")) == "x" and gs.life_events("test")[0].has("day"), "生命事件帶著日子與資料")
	# 5. 冷卻
	gs.set_quiet("black", 3)
	_check(gs.is_quiet("black") and not gs.is_quiet("pack_mountain"), "黑狼冷卻中，別的對手不受影響")
	gs.life_log["days_lived"] = int(gs.life_log["days_lived"]) + 1
	_check(not gs.is_quiet("black"), "過了 3 個時段以上，冷卻解除")
	# 6. 事件上限
	gs.events_today = 2
	gs.pending_events.clear()
	_check(not gs._can_trigger_event() and gs._can_trigger_event("den"), "上限到了：一般事件不行，巢穴的事件可以")
	gs._queue_event({"type": "test"}, "den")
	_check(gs.events_today == 2, "巢穴的事件不佔名額")
	gs.pending_events.clear()
	gs.events_today = 0
	# 7. 存檔
	gs.new_game("grassland_hills")
	var lid: String = gs.neighbor_packs[1].leader_id
	gs.npcs[lid].traits = ["bold"]
	var before: Array = JSON.parse_string(JSON.stringify(gs.neighbor_packs.map(func(x): return x.to_dict())))
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game("forest_east")
	gs.load_from_dict(d)
	var after: Array = JSON.parse_string(JSON.stringify(gs.neighbor_packs.map(func(x): return x.to_dict())))
	_check(JSON.stringify(before) == JSON.stringify(after), "存檔後鄰群一樣")
	_check(gs.npcs[lid].traits == ["bold"] and gs.npcs[lid].pack_id != "" and gs.wolf.sex == "male", "NPC 的新欄位、玩家的性別存得住")
	# 8. 15 年
	var counted: Array = []
	var winter: Array = []
	var successions := 0
	var crashed := false
	for run in 20:
		gs.new_game("forest_east")
		for s in 60:
			gs._age_npcs()
			gs._update_neighbor_packs()
			gt.season_index = (gt.season_index + 1) % 4
			for q in gs.neighbor_packs:
				var l = gs.npcs.get(q.leader_id, null)
				if q.stage != "gone" and l == null:
					crashed = true
				if q.stage != "gone" and s >= 8:
					counted.append(q.counted_size(l != null and l.alive))
					if gt.current_season() == "spring": # 剛過完冬季的換季（秋冬已經離群過）
						winter.append(q.counted_size(l != null and l.alive))
				if q.generation > 1 and s == 59:
					successions += 1
	_check(not crashed, "15 年的換季：每一群都找得到帶頭的")
	var mean: float = counted.reduce(func(a, b): return a + b, 0) / float(max(1, counted.size()))
	winter.sort()
	var p90: int = int(winter[int(winter.size() * 0.9)]) if not winter.is_empty() else 0
	_check(mean >= 4.0 and mean <= 8.0, "狼群平均 %.1f 隻（算進上限的，目標約 4～8）" % mean)
	_check(p90 <= int(data.balance["black_pack"]["max_size"]), "秋冬離群之後，九成的狼群在上限以內（第 90 百分位 %d）" % p90)
	_check(successions > 0, "有狼群換代過（20 局裡 %d 群）" % successions)
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
