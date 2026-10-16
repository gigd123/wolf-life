extends SceneTree
# 文案斷言稽核（文案一致性 C，2026-10-16，對照表 docs/text-conditions.md）的回歸測試：
# 雪兔週期十年的春天卡片、年輕的狼「比上次更壯」、只探索時的睡醒原因、苔原狼「這次只有牠一隻」。
# 用法：bash tools/run_sim.sh text_claims
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	# 1. 雪兔：每年春天的卡片和去年比一致
	gs.new_game("forest_east")
	var table: Array = load("res://data/balance.json").data["hare_cycle"]["mult"]
	for y in table.size():
		gs.life_log["hare_year"] = y
		gs.pending_events.clear()
		gt.season_index = 0
		gs._queue_season_card({})
		var keys: Array = []
		for e in gs.pending_events:
			if e.get("type", "") == "season_card":
				for line in e.get("lines", []):
					if str(line.get("key", "")).begins_with("year.hint.spring"):
						keys.append(str(line["key"]))
		var now: float = float(table[y]); var last: float = float(table[posmod(y - 1, table.size())])
		var key: String = keys[0] if not keys.is_empty() else "（無）"
		print("雪兔第 %d 年 %.2f（去年 %.2f）：%s" % [y, now, last, key])
		if key.ends_with("hare_low"):
			_check(now < last, "第 %d 年說「少了很多」時要比去年少" % y)
		if key.ends_with("hare_low_rising"):
			_check(now > last, "第 %d 年說「比去年多」時要比去年多" % y)
	# 2. 年輕的狼：只有上次被你打贏後才變強
	gs.new_game("forest_east")
	_check(not gs.challenger_grew(), "沒見過時不算變強")
	var npc = gs._ensure_challenger()
	var s0: float = npc.strength
	gs._after_challenger(false)
	_check(not gs.challenger_grew() and npc.strength == s0, "你讓了或輸了：牠沒變強，也不說更壯")
	gs._after_challenger(true)
	_check(gs.challenger_grew() and npc.strength > s0, "你打贏了：牠變強，說更壯")
	# 3. 睡醒原因：沒追獵也沒打鬥時不說追逐
	gs.new_game("forest_east")
	var snap: Dictionary = {"speed": gs.wolf.speed - 1.0, "strength": gs.wolf.strength, "health_max": gs.wolf.health_max, "skill": gs.wolf.skill, "perception": gs.wolf.perception}
	gs.life_log["sleep_snapshot"] = snap
	gs.life_log["since_sleep"] = {}
	var r1: String = str(gs.sleep_summary({"points": 6.0, "hunger_mult": 1.0})["reason"])
	gs.life_log["since_sleep"] = {"chase": 2}
	var r2: String = str(gs.sleep_summary({"points": 6.0, "hunger_mult": 1.0})["reason"])
	print("睡醒原因：只探索 %s、有追獵 %s" % [r1, r2])
	_check(r1 == "sleep_reason.roam", "只探索時寫四處走動")
	_check(r2.ends_with("_chase"), "有追獵時寫追逐")
	# 4. 苔原狼：上次也只有一隻時，不說「這次只有牠一隻」
	gs.new_game("tundra_south")
	var pair: Array = gs.tundra_pair()
	if pair.size() < 2:
		print("（苔原狼不到兩隻，略過）")
	else:
		var k1: String = gs.tundra_meet_key(true)
		pair[1].alive = false
		var k2: String = gs.tundra_meet_key(false)
		var k3: String = gs.tundra_meet_key(false)
		print("苔原狼：", k1, " → ", k2, " → ", k3)
		_check(k1 == "tundra.meet.first.pair" and k2 == "tundra.meet.again.single" and k3 == "tundra.meet.again.single_same", "一對 → 剩一隻（這次只有牠）→ 還是一隻")
		gs.new_game("tundra_south")
		gs.tundra_pair()[1].alive = false
		var k4: String = gs.tundra_meet_key(true)
		var k5: String = gs.tundra_meet_key(false)
		_check(k4 == "tundra.meet.first.single" and k5 == "tundra.meet.again.single_same", "從頭到尾只見過一隻：不說「這次只有牠一隻」（%s、%s）" % [k4, k5])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
