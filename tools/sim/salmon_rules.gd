extends SceneTree
# 鮭魚洄流季（Phase 2h）的回歸測試。第 1 步：
#   1. 強度照季節與天數（夏季 6～10 初期、秋季 1～4 高峰、5～8 衰退、其他沒有），只在森林北部、森林東部、山地源頭
#   2. 探索時的線索：只在有洄流的區域與日子；守在水邊比一般探索常見；高峰期比初期常見；地點是水邊；是值得停下的發現
#   3. 線索的種類照強度；文字都有翻譯、衰退期的「已經稀了」只在衰退期
#   4. 鮭魚溪地圖族 3 張，每張都有好、普通、差的淺灘，fish 層只在淺灘上
# 用法：bash tools/run_sim.sh salmon_rules
var gs
var gt
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _at(season: String, day: int) -> void:
	gt.season_index = gt.SEASONS.find(season)
	gt.day = day

func _run() -> void:
	gs.new_game("forest_east")
	gs.pending_events.clear()
	# 1. 強度
	var cases := [["spring", 5, ""], ["summer", 5, ""], ["summer", 6, "early"], ["summer", 10, "early"], ["autumn", 1, "peak"], ["autumn", 4, "peak"],
		["autumn", 5, "decline"], ["autumn", 8, "decline"], ["autumn", 9, ""], ["winter", 2, ""]]
	for c in cases:
		_at(c[0], c[1])
		_check(gs.salmon_stage("forest_east") == c[2], "%s 第 %d 天：%s（%s）" % [c[0], c[1], c[2], gs.salmon_stage("forest_east")])
	_at("autumn", 2)
	for r in ["forest_north", "forest_east", "mountain_headwaters"]:
		_check(gs.salmon_stage(r) == "peak", r + " 有洄流")
	for r in ["forest_west", "grassland_river", "tundra_east", "mountain_foothills"]:
		_check(gs.salmon_stage(r) == "", r + " 沒有洄流")
	# 2. 線索的頻率
	var counts := {}
	for k in [["peak", "trail"], ["peak", "water"], ["early", "trail"], ["none", "water"]]:
		var n := 0
		var bad := 0
		for i in 300:
			gs.wolf.stamina = 100.0; gs.wolf.hunger = 100.0; gs.wolf.health = gs.wolf.health_max
			gs.current_region = "forest_east" if k[0] != "none" else "forest_west"
			if k[0] == "early":
				_at("summer", 7)
			else:
				_at("autumn", 2)
			gs.clear_discovery(); gs.pending_events.clear()
			var d: Dictionary = gs.action_explore(k[1])
			if str(d.get("kind", "")) == "salmon":
				n += 1
				if not ["stream", "river_willow", "river"].has(str(d["location"])) or str(d["stage"]) != (k[0] if k[0] != "none" else "") or not gs.is_notable_discovery(d):
					bad += 1
		counts[k[0] + "." + k[1]] = n
		_check(bad == 0, "線索的地點是水邊、強度對、值得停下（%s：不對的 %d 次）" % [k, bad])
	_check(int(counts["peak.water"]) > int(counts["peak.trail"]) and int(counts["peak.trail"]) > int(counts["early.trail"]) and int(counts["none.water"]) == 0,
		"守在水邊比較常見、高峰比初期常見、沒有洄流的區域沒有（%s）" % counts)
	# 3. 線索的種類與文字
	var cl: Dictionary = root.get_node("GameData").balance["salmon"]["clues"]
	for st in cl.keys():
		for c in cl[st].keys():
			var key: String = "salmon.clue.%s.%s" % [st, c]
			_check(TranslationServer.translate(key) != key, "有翻譯：" + key)
	_check(not (cl["early"] as Dictionary).has("spawned") and not (cl["peak"] as Dictionary).has("spawned"), "產完卵的魚只在衰退期")
	# 4. 地圖
	var maps: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical_hunt.json"))["maps"]
	var fam := 0
	for id in maps.keys():
		var m: Dictionary = maps[id]
		if str(m.get("family", "")) != "salmon":
			continue
		fam += 1
		var q := {}
		var off := 0
		for y in (m["map"] as Array).size():
			for x in String(m["map"][y]).length():
				var f: String = String(m["fish"][y])[x]
				if f != ".":
					q[f] = true
					if String(m["map"][y])[x] != "s":
						off += 1
		_check(q.has("1") and q.has("2") and q.has("3") and off == 0, "%s：好、普通、差的淺灘都有，魚只在淺灘上（%s，不在淺灘 %d 格）" % [id, q.keys(), off])
	_check(fam == 3, "鮭魚溪 3 張（%d）" % fam)
	print("線索次數（300 次探索）：%s" % counts)
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
