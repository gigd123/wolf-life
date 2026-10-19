extends SceneTree
# Phase 3a 第 1 步「黑狼家族的狀態與換季更新」的回歸測試（WolfPack.gd）：
#   1. 你還不到 2.5 歲、也沒打贏過牠：不會成家；打贏過牠就可以
#   2. 牠老了不會成家
#   3. 有伴侶才在春季生幼狼；生了就是狼群
#   4. 帶頭的死了：有伴侶和夠大的子女就換代（最年長的接手），否則解散
#   5. 擴張不會到你的巢穴，優先你的標記淡掉的區域
#   6. 存檔 → 讀檔一樣；GameState 換季時會更新、換代時建立新的帶頭的
# 用法：bash tools/run_sim.sh black_pack_rules
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var WP = load("res://scripts/core/WolfPack.gd")
	var NPC = load("res://scripts/core/NpcWolf.gd")
	var rng = root.get_node("RNGService")
	var data = root.get_node("GameData")
	var cfg: Dictionary = data.balance["black_pack"]
	cfg["pair_chance"] = 1.0 # 測規則，不測機率
	var adjacent := {}
	for r in data.map_regions("forest"):
		adjacent[r] = data.regions()[r].get("adjacent", [])
	var leader = NPC.create("stranger_wolf", "forest_north")
	leader.age_years = 4.0
	# 1. 年齡與打贏
	rng.set_seed(1)
	var p = WP.new()
	p.regions = ["forest_north"]
	p.on_season_passed({"season": "autumn", "leader": leader, "player_age": 2.0, "beaten": false, "adjacent": adjacent})
	_check(p.stage == "solo", "2 歲、沒打贏過：不成家（%s）" % p.stage)
	p.on_season_passed({"season": "autumn", "leader": leader, "player_age": 2.0, "beaten": true, "adjacent": adjacent})
	_check(p.stage == "pair" and p.has_mate(), "打贏過牠：可以成家（%s）" % p.stage)
	var p2 = WP.new()
	p2.on_season_passed({"season": "autumn", "leader": leader, "player_age": 2.5, "beaten": false, "adjacent": adjacent})
	_check(p2.stage == "pair", "滿 2.5 歲：可以成家（%s）" % p2.stage)
	# 2. 老了不成家
	var old = NPC.create("stranger_wolf", "forest_north")
	old.age_years = 7.0
	var p3 = WP.new()
	p3.on_season_passed({"season": "winter", "leader": old, "player_age": 4.0, "beaten": true, "adjacent": adjacent})
	_check(p3.stage == "solo", "牠老了不成家（%s）" % p3.stage)
	# 3. 春季生幼狼
	cfg["pup_chance"] = 1.0
	var p4 = WP.new()
	p4.regions = ["forest_north"]
	p4.on_season_passed({"season": "spring", "leader": leader, "player_age": 1.0, "beaten": false, "adjacent": adjacent})
	_check(p4.pups() == 0, "沒有伴侶不生幼狼")
	p4.mate_age = 3.0
	p4.stage = "pair"
	p4.on_season_passed({"season": "spring", "leader": leader, "player_age": 3.0, "beaten": false, "adjacent": adjacent})
	_check(p4.stage == "pack" and p4.pups() >= 3, "有伴侶、春季：生幼狼成為狼群（%s，%d 隻）" % [p4.stage, p4.pups()])
	# 4. 換代與解散
	var dead = NPC.create("stranger_wolf", "forest_north")
	dead.alive = false
	var p5 = WP.new()
	p5.regions = ["forest_north"]
	p5.stage = "pack"
	p5.mate_age = 4.0
	p5.young = [1.75, 3.0, 0.5]
	cfg["mate_death_per_season"] = 0.0
	cfg["disperse_per_season"] = {}
	var ev: Array = p5.on_season_passed({"season": "summer", "leader": dead, "player_age": 5.0, "beaten": false, "adjacent": adjacent})
	_check(ev.has("succession") and p5.generation == 2 and absf(p5.heir_age - 3.25) < 0.01, "有伴侶與夠大的子女：最年長的接手（%s，第 %d 代，%.2f 歲）" % [ev, p5.generation, p5.heir_age])
	_check(p5.regions == ["forest_north"], "換代後領域不變")
	var p6 = WP.new()
	p6.regions = ["forest_north"]
	p6.stage = "pack"
	p6.young = [0.5, 0.75]
	ev = p6.on_season_passed({"season": "summer", "leader": dead, "player_age": 5.0, "beaten": false, "adjacent": adjacent})
	_check(p6.stage == "gone" and p6.regions.is_empty(), "沒有伴侶、子女太小：解散（%s）" % p6.stage)
	# 5. 擴張
	cfg["expand_chance"] = 1.0
	for i in 20:
		rng.set_seed(i)
		var p7 = WP.new()
		p7.regions = ["forest_north"]
		p7.stage = "pack"
		p7.mate_age = 4.0
		p7.young = [1.25, 1.25, 1.5, 2.25]
		p7.on_season_passed({"season": "autumn", "leader": leader, "player_age": 4.0, "beaten": false,
			"den": "forest_east", "own": ["forest_west"], "adjacent": adjacent})
		_check(p7.regions.size() == 2 and not p7.regions.has("forest_east"), "擴張不到你的巢穴（%s）" % [p7.regions])
	# forest_south 相鄰 east、west；east 有你的標記 → 擴張到 west
	var p8 = WP.new()
	p8.regions = ["forest_south"]
	p8.stage = "pack"
	p8.mate_age = 4.0
	p8.young = [1.25, 1.25, 1.5, 2.25]
	p8.on_season_passed({"season": "autumn", "leader": leader, "player_age": 4.0, "beaten": false,
		"den": "forest_north", "own": ["forest_east"], "adjacent": adjacent})
	_check(p8.regions.size() == 2 and p8.regions[1] == "forest_west", "優先沒有你標記的區域（%s）" % [p8.regions])
	# 6. 存檔、GameState
	var back = WP.from_dict(JSON.parse_string(JSON.stringify(p5.to_dict())))
	_check(JSON.stringify(JSON.parse_string(JSON.stringify(back.to_dict()))) == JSON.stringify(JSON.parse_string(JSON.stringify(p5.to_dict()))), "WolfPack 存檔 → 讀檔一樣")
	var gs = root.get_node("GameState")
	gs.new_game("forest_east")
	_check(gs.black_pack.stage == "solo" and gs.black_pack.regions == [gs.stranger_territory], "開局：黑狼獨居、領域是牠的範圍")
	gs.black_pack.stage = "pack"
	gs.black_pack.mate_age = 4.0
	gs.black_pack.young = [2.5]
	gs.stranger().die("old_age")
	gs._update_black_pack()
	_check(gs.black_pack.generation == 2 and gs.pack_leader() != null and gs.pack_leader().id == "black_heir" and gs.pack_leader().alive,
		"GameState 換代：建立新的帶頭的（%s）" % [gs.pack_leader().id if gs.pack_leader() != null else "null"])
	var saved = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_from_dict(saved)
	_check(gs.black_pack.generation == 2 and gs.pack_leader() != null and gs.pack_leader().id == "black_heir", "讀檔後換代還在")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
