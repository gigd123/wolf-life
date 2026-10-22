extends SceneTree
# 鮭魚洄流季（Phase 2h）的回歸測試。第 1 步：
#   1. 強度照季節與天數（夏季 6～10 初期、秋季 1～4 高峰、5～8 衰退、其他沒有），只在森林北部、森林東部、山地源頭
#   2. 探索時的線索：只在有洄流的區域與日子；守在水邊比一般探索常見；高峰期比初期常見；地點是水邊；是值得停下的發現
#   3. 線索的種類照強度；文字都有翻譯、衰退期的「已經稀了」只在衰退期
#   4. 鮭魚溪地圖族 3 張，每張都有好、普通、差的淺灘，fish 層只在淺灘上
# 第 2 步（河岸模式）：
#   5. 開場在岸邊；只有站在有魚的淺灘上才能撲；成功率照魚量與強度；撲到就吃（+5）、吃撐時走得比較近、吃到上限就不能撲
#   6. 離開、待太久；8 個戰術回合＝1 個遊戲回合；結算加上時間、體力、飽食度與紀錄
# 第 3 步（灰熊）：
#   7. 開場的頭數照強度與線索；大熊佔魚最多的淺灘、彼此 2 格以上；小熊離大熊 3 格以上；狼開場不在威嚇範圍內；熊佔的格子走不過去
#   8. 太靠近：先威嚇（不能撲魚、可以硬撐），下一回合還在就被趕到範圍外；硬撐 → 灰熊遭遇（先被撞）
#   9. 熊吃剩的魚：丟在旁邊的岸上，走上去就吃（+8）；熊會後到、會離開
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
	# 5. 河岸模式
	_at("autumn", 2)
	gs.current_region = "forest_east"
	gs.wolf.hunger = 60.0
	gs.debug_salmon()
	var rf = gs.start_salmon_fishing()
	_check(gs.current_discovery.is_empty() and rf.terrain(rf.wolf_pos) == "." and not rf.can_fish() and rf.stage == "peak", "開場在岸邊、不能撲、強度是高峰")
	# 第 2 步的檢查不要熊（熊在第 7～9 項另外測）
	rf.bears = []
	rf.cfg["bears"]["arrive"] = {"early": 0.0, "peak": 0.0, "decline": 0.0}
	var spots := {}
	for y in rf.height:
		for x in rf.width:
			var q: int = rf.fish_at(Vector2i(x, y))
			if q > 0 and not spots.has(q):
				spots[q] = Vector2i(x, y)
	var cfg: Dictionary = root.get_node("GameData").balance["salmon"]["river"]
	for q in [1, 2, 3]:
		rf.wolf_pos = spots[q]
		_check(absf(rf.fish_chance() - float(cfg["catch"][str(q)])) < 0.001, "高峰期魚量 %d 的成功率 %.2f" % [q, rf.fish_chance()])
	rf.stage = "early"
	_check(absf(rf.fish_chance() - float(cfg["catch"]["3"]) * 0.5) < 0.001, "初期的成功率減半")
	rf.stage = "peak"
	var deep := Vector2i(-1, -1)
	for y in rf.height:
		for x in rf.width:
			if rf.terrain(Vector2i(x, y)) == "d" and deep.x < 0:
				deep = Vector2i(x, y)
	rf.wolf_pos = deep
	_check(not rf.can_fish(), "深潭撲不到魚")
	rf.wolf_pos = spots[3]
	var h0: float = rf.hunger
	var tries := 0
	while rf.caught == 0 and tries < 100:
		tries += 1
		rf.fish_once()
	_check(rf.caught == 1 and absf(rf.hunger - h0 - 5.0) < 0.01 and absf(rf.eaten - 5.0) < 0.01 and absf(rf.stamina_spent - tries) < 0.01, "撲到就吃 +5、每撲一次體力 −1（撲了 %d 次）" % tries)
	var r0: float = rf.move_range()
	rf.hunger = 125.0
	_check(rf.move_range() < r0, "吃撐了走得比較近")
	rf.hunger = rf.hunger_max
	_check(not rf.can_fish(), "吃到上限就不能撲")
	rf.hunger = 100.0
	# 6. 離開與結算
	rf.rounds = 17
	_check(rf.game_turns() == 3, "17 個戰術回合＝3 個遊戲回合（%d）" % rf.game_turns())
	rf.leave()
	_check(rf.done and rf.result == "left", "離開")
	var t0: int = gt.day * 100 + gt.period_index * 10 + gt.turn_in_period
	gs.wolf.hunger = 60.0
	gs.wolf.stamina = 80.0
	var res: Dictionary = gs.finish_salmon_fishing(rf)
	var t1: int = gt.day * 100 + gt.period_index * 10 + gt.turn_in_period
	_check(int(res["turns"]) == 3 and t1 != t0 and gs.wolf.hunger > 60.0 and gs.wolf.stamina < 80.0, "結算：時間、飽食度、體力（%s）" % res)
	_check(int(gs.life_log.get("salmon", {}).get("trips", 0)) == 1 and float(gs.life_log.get("food_by", {}).get("salmon", 0.0)) > 0.0, "紀錄：去了幾次、食物來源")
	var rf2 = RF_new()
	rf2.setup({"stage": "peak", "seed": 3, "hunger": 60.0, "cfg": cfg})
	for i in int(cfg["max_rounds"]):
		rf2.move_to(rf2.wolf_pos + Vector2i(1, 0) if rf2.in_bounds(rf2.wolf_pos + Vector2i(1, 0)) else rf2.wolf_pos + Vector2i(-1, 0))
	_check(rf2.done and rf2.result == "timeout", "待太久就離開")
	# 7. 開場的灰熊
	var counts_b := {"early": [], "peak": [], "bears": [], "bear": []}
	var bad_place := 0
	for i in 80:
		for k in ["early", "peak", "bears", "bear"]:
			var r = RF_new()
			r.setup({"stage": "peak" if k in ["bears", "bear"] else k, "clue": k if k in ["bears", "bear"] else "", "seed": i * 31 + k.length(), "hunger": 60.0, "cfg": cfg})
			counts_b[k].append(r.bears.size())
			for a1 in r.bears.size():
				var b1: Dictionary = r.bears[a1]
				if r.fish_at(b1["pos"]) <= 0:
					bad_place += 1
				for a2 in r.bears.size():
					if a2 != a1 and bool(r.bears[a2]["big"]):
						var dd: int = r._cheb(b1["pos"], r.bears[a2]["pos"])
						if dd < (2 if bool(b1["big"]) else 3):
							bad_place += 1
			if r._bear_threat_dist(r.wolf_pos) <= 0:
				bad_place += 1
	_check(counts_b["early"].max() <= 1 and counts_b["peak"].min() >= 1 and counts_b["peak"].max() <= 2 and counts_b["bears"].min() >= 2 and counts_b["bear"].min() >= 1,
		"開場的頭數：初期 0～1、高峰 1～2、「好幾頭灰熊」2～3、「灰熊在捕魚」至少 1")
	_check(bad_place == 0, "熊都站在有魚的淺灘、大熊彼此 2 格以上、小熊離大熊 3 格以上、狼開場不在威嚇範圍內（不對的 %d）" % bad_place)
	var rb = RF_new()
	rb.setup({"stage": "peak", "clue": "bears", "seed": 77, "hunger": 60.0, "cfg": cfg})
	var big_i := -1
	for i in rb.bears.size():
		if bool(rb.bears[i]["big"]):
			big_i = i
	var bq := 0
	for y in rb.height:
		for x in rb.width:
			bq = maxi(bq, rb.fish_at(Vector2i(x, y)))
	_check(big_i >= 0 and rb.fish_at(rb.bears[big_i]["pos"]) == bq, "大熊佔魚最多的淺灘")
	var bpos: Vector2i = rb.bears[big_i]["pos"]
	rb.wolf_pos = bpos + Vector2i(2, 0) if rb.in_bounds(bpos + Vector2i(2, 0)) else bpos - Vector2i(2, 0)
	rb.wolf_pos = bpos + Vector2i(1, 0) if rb.in_bounds(bpos + Vector2i(1, 0)) else bpos - Vector2i(1, 0)
	_check(not rb.reachable().has(bpos), "熊佔的格子走不過去")
	# 8. 威嚇、趕開、硬撐
	rb.cfg["bears"]["arrive"] = {"early": 0.0, "peak": 0.0, "decline": 0.0}
	rb.cfg["bears"]["leave"] = 0.0
	rb._bears_turn()
	_check(rb.threatened() and rb.warns >= 1 and not rb.can_fish(), "太靠近：被威嚇、不能撲魚")
	rb._bears_turn()
	_check(not rb.threatened() and rb.pushes == 1 and rb._bear_threat_dist(rb.wolf_pos) > 0, "還在範圍內：被趕到所有熊的範圍外")
	rb.wolf_pos = bpos + Vector2i(1, 0) if rb.in_bounds(bpos + Vector2i(1, 0)) and rb.bear_at(bpos + Vector2i(1, 0)) < 0 else bpos - Vector2i(1, 0)
	rb._bears_turn()
	rb.stand_ground()
	_check(rb.done and rb.result == "stand", "被威嚇時可以硬撐不走")
	gs.wolf.health = gs.wolf.health_max
	var res2: Dictionary = gs.finish_salmon_fishing(rb)
	var enc: Dictionary = gs.salmon_stand_encounter()
	_check(str(res2["result"]) == "stand" and bool(enc.get("salmon_stand", false)) and bool(enc.get("direct", false)) and gs.wolf.health < gs.wolf.health_max,
		"硬撐 → 灰熊衝過來（先被撞）、接成灰熊遭遇")
	# 9. 吃剩的魚、後到與離開
	var rl = RF_new()
	rl.setup({"stage": "peak", "clue": "bear", "seed": 5, "hunger": 60.0, "cfg": cfg})
	rl._drop_leftover(rl.bears[0]["pos"])
	_check(rl.leftovers.size() == 1 and rl.terrain(rl.leftovers[0]) == ".", "吃剩的魚丟在旁邊的岸上")
	var lo: Vector2i = rl.leftovers[0]
	rl.wolf_pos = lo
	var e0: float = rl.eaten
	rl._eat_leftover()
	_check(rl.leftovers.is_empty() and absf(rl.eaten - e0 - 8.0) < 0.01 and rl.scraps == 1, "走上去就吃 +8")
	var arrived := 0
	var left := 0
	for i in 40:
		var ra = RF_new()
		ra.setup({"stage": "peak", "seed": 900 + i, "hunger": 60.0, "cfg": cfg})
		var n0: int = ra.bears.size()
		for k in 64:
			if ra.done:
				break
			var before: int = ra.bears.size()
			ra._end_round()
			if ra.bears.size() > before:
				arrived += 1
			elif ra.bears.size() < before:
				left += 1
	_check(arrived > 10 and left > 5, "熊會後到（%d 次）、會離開（%d 次）" % [arrived, left])
	for k in ["river.ui.intro", "river.ui.fish", "river.ui.leave", "river.catch", "river.miss", "river.full", "river.ui.result", "salmon.clue.peak.bears"]:
		_check(TranslationServer.translate(k) != k, "有翻譯：" + k)
	print("線索次數（300 次探索）：%s" % counts)
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

func RF_new():
	return load("res://scripts/core/RiverFishing.gd").new()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
