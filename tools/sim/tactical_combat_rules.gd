extends SceneTree
# 戰術戰鬥原型（docs/proposals/tactical-combat-prototype.md）的規則測試。每一步做完在這裡加檢查。
# 第 1 步：情境載入、單位、殘骸、移動範圍（喘、叼肉依大小變慢、大塊不能衝刺）、地形擋路、叼肉與放下、撤出地圖。
# 第 2 步：表態與範圍、同步結算（閃出範圍就打不到、目標走掉就撲空、衝撞停在第一個撞到的、假衝不傷人、閃避、變卦、先後與打斷）、
#   預告後輪流（對手出手前最多轉 45°）、叼肉的機率、結束（對手走了、撤出、被打倒、時間到）、兩種模式隨機打完不出錯。
# 用法：bash tools/run_sim.sh tactical_combat_rules
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _run() -> void:
	var tc := TacticalCombat.new()
	# 情境
	for sc in ["grizzly_arrives", "grizzly_on_carcass", "grizzly_open", "cougar_cache", "cougar_ambush", "grizzly_arrives_mate", "grizzly_on_carcass_mate"]:
		tc.setup(sc, {"seed": 3})
		var w: int = String(tc.map.grid[0]).length()
		var same := true
		for row in tc.map.grid:
			same = same and String(row).length() == w
		_check(same and tc.enemy_index() >= 0 and tc.active(0), "情境 %s 載入（%d×%d、%d 隻）" % [sc, tc.map.width, tc.map.height, tc.units.size()])
	tc.setup("grizzly_arrives_mate", {})
	_check(tc.index_of("mate") == 1 and str(tc.units[1]["side"]) == "ally", "加伴侶的情境有伴侶")
	tc.setup("grizzly_arrives", {})
	_check(tc.index_of("mate") == -1, "沒加伴侶的情境沒有伴侶")
	# 移動
	var free_move: float = tc.max_move(0)
	var r: Dictionary = tc.reachable(0)
	_check(not r.has(tc.carcass["pos"]) and not r.has(tc.units[tc.enemy_index()]["pos"]), "殘骸、對手那一格不能走進去")
	var tree := Vector2i(11, 4)
	tc.units[0]["pos"] = Vector2i(10, 4)
	_check(tc.map.terrain(tree) == "T" and not tc.reachable(0).has(tree), "大樹走不進去")
	var rock := Vector2i(6, 3)
	tc.units[0]["pos"] = Vector2i(5, 3)
	_check(tc.map.terrain(rock) == "B" and tc.reachable(0).has(rock), "大石頭狼跳得上去")
	var ei: int = tc.enemy_index()
	var bear_cost: float = float(tc.map.costs_from(Vector2i(5, 3), 9.0, {}, tc.terrain_cost(ei), tc._impassable(ei)).get(rock, 99.0))
	var wolf_cost: float = float(tc.map.costs_from(Vector2i(5, 3), 9.0, {}, tc.terrain_cost(0), tc._impassable(0)).get(rock, 99.0))
	_check(bear_cost > wolf_cost and bear_cost < 9.0, "灰熊上得了大石頭，但比較慢（%.0f 對狼的 %.0f）" % [bear_cost, wolf_cost])
	# 叼肉依大小變慢
	tc.setup("grizzly_arrives", {})
	_check(tc.at_carcass(0) and tc.take_kinds(0) == ["piece", "leg"], "大殘骸旁可以叼一塊或撕一條腿")
	var seg0: int = int(tc.carcass["segments"])
	_check(tc.take_from_carcass(0, "piece") == 1 and str(tc.units[0]["carrying"]) == "medium" and int(tc.carcass["segments"]) == seg0 - 1, "叼一塊：1 段、中")
	_check(is_equal_approx(tc.max_move(0), free_move - 1.0), "叼著一段：少 1 格（%.0f → %.0f）" % [free_move, tc.max_move(0)])
	_check(tc.take_kinds(0).is_empty(), "叼著時不能再拿")
	tc.drop_carried(0)
	_check(str(tc.units[0]["carrying"]) == "" and tc.drops.size() == 1 and tc.pick_up(0) and tc.drops.is_empty(), "放下、撿起")
	tc.drop_carried(0)
	tc.drops.clear()
	var n: int = tc.take_from_carcass(0, "leg")
	_check(n >= 2 and n <= 3 and str(tc.units[0]["carrying"]) == "large" and not tc.can_sprint(0), "撕一條腿：2～3 段、大、不能衝刺")
	_check(tc.max_move(0) <= tc.trot_range(0) - 2.0 + 0.001, "叼著大塊：少 2 格")
	tc.units[0]["carcass_test"] = true
	tc.carcass = {"pos": Vector2i(8, 8), "animal": "hare", "segments": 1, "size": "small", "small_whole": true, "whole_size": "small", "leg": [2, 3]}
	tc.units[0]["carrying"] = ""
	tc.units[0]["pos"] = Vector2i(7, 8)
	_check(tc.take_kinds(0) == ["whole"] and tc.take_from_carcass(0, "whole") == 1 and is_equal_approx(tc.max_move(0), free_move), "野兔整隻叼走：小，移動不變")
	# 撤出
	tc.units[0]["pos"] = Vector2i(5, 5)
	_check(not tc.can_exit(0), "不在邊緣不能撤出")
	tc.units[0]["pos"] = Vector2i(0, 5)
	tc.exit_unit(0)
	_check(bool(tc.units[0]["out"]) and tc.meat_taken() == 1, "在邊緣撤出、帶走的肉算你的")
	# 轉身與角度（共用工具）
	_check(TacticalGrid.turn_toward(Vector2i(1, 0), Vector2i(-1, 0), 1) in [Vector2i(1, 1), Vector2i(1, -1)], "灰熊每回合只轉 45°")
	_check(TacticalGrid.turn_toward(Vector2i(1, 0), Vector2i(-1, 0), -1) == Vector2i(-1, 0), "美洲獅可以直接轉過來")
	_check(TacticalGrid.side_of(Vector2i(5, 5), Vector2i(1, 0), Vector2i(3, 5)) == "rear" and TacticalGrid.side_of(Vector2i(5, 5), Vector2i(1, 0), Vector2i(6, 5)) == "front" \
		and TacticalGrid.side_of(Vector2i(5, 5), Vector2i(1, 0), Vector2i(5, 6)) == "side", "前、側、後")
	_step2()
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

# 開場：開闊地、狼在 wp、灰熊在 bp 面向 bf；回傳 TacticalCombat
func _arena(wp: Vector2i, bp: Vector2i, bf: Vector2i, m := "sync", seed := 1, sc := "grizzly_open") -> TacticalCombat:
	var tc := TacticalCombat.new()
	tc.setup(sc, {"seed": seed, "mode": m})
	var e: int = tc.enemy_index()
	tc.units[0]["pos"] = wp
	tc.units[e]["pos"] = bp
	tc.units[e]["facing"] = bf
	tc.units[e]["eating"] = false
	return tc

func _force(tc: TacticalCombat, action: String, target := Vector2i(-1, -1)) -> void:
	tc.rounds += 1
	tc.intents.clear()
	tc.plans.clear()
	tc.events.clear()
	var e: int = tc.enemy_index()
	var u: Dictionary = tc.units[e]
	tc.intents[e] = {"action": action, "looks": action, "move": u["pos"], "facing": u["facing"], "target": target,
		"zone": tc.zone_cells(e, action, u["pos"], u["facing"], target)}

func _count(tc: TacticalCombat, kind: String) -> int:
	return tc.events.filter(func(ev): return str(ev["kind"]) == kind).size()

func _step2() -> void:
	print("第 2 步")
	var tc := _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0))
	var it: Dictionary = tc.begin_round()[tc.enemy_index()]
	_check(str(it["action"]) in ["swipe", "bite"] and (it["zone"] as Array).has(Vector2i(5, 5)), "灰熊在旁邊：表態揮掌或咬，範圍包含你（%s）" % it["action"])
	# 留在範圍裡約 85% 被打中；閃到牠側後方就打不到
	var stay := 0
	var away := 0
	for s in 300:
		tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0), "sync", s)
		tc.cfg["change_chance"] = {}
		_force(tc, "swipe")
		tc.plan(0, {"action": "wait"})
		tc.resolve()
		if _count(tc, "hit") > 0: stay += 1
		tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0), "sync", s)
		tc.cfg["change_chance"] = {}
		_force(tc, "swipe")
		tc.plan(0, {"move": Vector2i(7, 6), "action": "wait"})
		tc.resolve()
		if _count(tc, "hit") > 0: away += 1
	_check(abs(stay / 300.0 - 0.85) < 0.07 and away == 0, "揮掌：留在範圍 %d／300 被打中，繞到牠後面 0 次（%d）" % [stay, away])
	# 閃避
	var dodged := 0
	for s in 300:
		tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0), "sync", s)
		tc.cfg["change_chance"] = {}
		_force(tc, "swipe")
		tc.plan(0, {"action": "dodge"})
		tc.resolve()
		if _count(tc, "hit") > 0: dodged += 1
	_check(dodged < stay * 0.55, "閃避：被打中 %d／300（留著不動 %d）" % [dodged, stay])
	# 目標走掉就撲空（同步）
	var whiff := 0
	for s in 50:
		tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(1, 0), "sync", s)
		_force(tc, "move")
		tc.intents[tc.enemy_index()]["move"] = Vector2i(9, 5)
		tc.plan(0, {"action": "bite", "target": tc.enemy_index()})
		tc.resolve()
		whiff += _count(tc, "whiff")
	_check(whiff == 50, "同步：咬的時候灰熊走開了，一定撲空")
	# 衝撞停在第一個撞到的單位前；假衝不傷人
	tc = _arena(Vector2i(4, 5), Vector2i(8, 5), Vector2i(-1, 0), "sync", 7)
	tc.cfg["change_chance"] = {}
	tc.cfg["actions"]["charge"]["hit"] = 1.0
	_force(tc, "charge")
	tc.plan(0, {"action": "wait"})
	tc.resolve()
	_check(tc.units[tc.enemy_index()]["pos"] == Vector2i(5, 5) and _count(tc, "hit") == 1, "衝撞：衝到你前面一格、撞到你")
	tc = _arena(Vector2i(4, 5), Vector2i(8, 5), Vector2i(-1, 0), "sync", 7)
	tc.cfg["change_chance"] = {}
	_force(tc, "bluff_charge")
	tc.plan(0, {"action": "wait"})
	var hp0: float = tc.units[0]["hp"]
	tc.resolve()
	_check(tc.units[tc.enemy_index()]["pos"] == Vector2i(6, 5) and tc.units[0]["hp"] == hp0, "假衝：衝兩格就停，沒有傷人")
	# 變卦
	tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0), "sync", 3)
	tc.cfg["change_chance"] = {"grizzly_bear": 1.0}
	_force(tc, "swipe")
	tc.plan(0, {"action": "wait"})
	tc.resolve()
	_check(_count(tc, "changed") == 1 and _count(tc, "hit") == 0, "變卦：表態揮掌、結算時改成後退")
	# 先後與打斷：灰熊先打中你，有機會打斷你的咬
	var inter := 0
	for s in 300:
		tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0), "sync", s)
		tc.cfg["change_chance"] = {}
		_force(tc, "bite")
		tc.plan(0, {"action": "bite", "target": tc.enemy_index()})
		tc.resolve()
		inter += _count(tc, "interrupted")
	_check(inter > 10 and inter < 150, "先後：灰熊先咬到時，有時打斷你的咬（%d／300）" % inter)
	# 預告後輪流：對手出手前最多轉 45°
	tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0), "alternate", 4)
	tc.cfg["change_chance"] = {}
	_force(tc, "swipe")
	tc.plan(0, {"move": Vector2i(7, 5), "action": "wait"})
	tc.resolve()
	var f: Vector2i = tc.units[tc.enemy_index()]["facing"]
	_check(f in [Vector2i(-1, 1), Vector2i(-1, -1)] and _count(tc, "hit") == 0, "輪流：你繞到背後，灰熊只轉 45°，打不到你")
	tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0), "alternate", 4, "cougar_ambush")
	tc.cfg["change_chance"] = {}
	_force(tc, "swipe")
	tc.plan(0, {"move": Vector2i(7, 6), "action": "wait"})
	tc.resolve()
	_check(true, "輪流（美洲獅）結算不出錯")
	# 叼肉：灰熊在吃、你在牠背後 → 機率高；牠面對你 → 低
	tc = TacticalCombat.new()
	tc.setup("grizzly_on_carcass", {"seed": 2})
	var e: int = tc.enemy_index()
	var behind: float = tc.wolf_chance(0, "take", -1, Vector2i(9, 4))["chance"]
	tc.units[e]["eating"] = false
	tc.units[e]["facing"] = Vector2i(-1, 0)
	tc.units[e]["pos"] = Vector2i(10, 5)
	var facing: float = tc.wolf_chance(0, "take", -1, Vector2i(9, 4))["chance"]
	_check(behind > facing + 0.3, "叼肉：灰熊在吃 %.0f%%、面對你 %.0f%%" % [behind * 100.0, facing * 100.0])
	var got := 0
	for s in 100:
		tc = TacticalCombat.new()
		tc.setup("grizzly_on_carcass", {"seed": s})
		tc.units[0]["pos"] = Vector2i(9, 4)
		_force(tc, "eat")
		tc.plan(0, {"action": "take", "kind": "piece"})
		tc.resolve()
		if str(tc.units[0]["carrying"]) == "medium": got += 1
	_check(got > 60, "灰熊在吃時，從旁邊叼一塊 %d／100 成功" % got)
	# 結束
	tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0))
	tc.units[tc.enemy_index()]["hp"] = 10.0
	tc.begin_round()
	tc.plan(0, {"action": "wait"})
	tc.resolve()
	_check(tc.done and tc.outcome == "enemy_left", "灰熊血量很低就走了：對手走了")
	tc = _arena(Vector2i(0, 5), Vector2i(8, 5), Vector2i(-1, 0))
	tc.units[0]["carrying"] = "medium"
	tc.units[0]["carry_segments"] = 1
	tc.begin_round()
	tc.plan(0, {"action": "retreat"})
	tc.resolve()
	_check(tc.done and tc.outcome == "retreated" and tc.meat_taken() == 1, "在邊緣撤出：帶走 1 段")
	tc = _arena(Vector2i(5, 5), Vector2i(6, 5), Vector2i(-1, 0))
	tc.cfg["change_chance"] = {}
	tc.cfg["actions"]["swipe"]["hit"] = 1.0
	tc.units[0]["hp"] = 1.0
	_force(tc, "swipe")
	tc.plan(0, {"action": "wait"})
	tc.resolve()
	_check(tc.done and tc.outcome == "knocked", "血量打光：被打倒（原型不會死）")
	tc = _arena(Vector2i(2, 2), Vector2i(13, 8), Vector2i(-1, 0))
	tc.rounds = int(tc.cfg["max_rounds"]) - 1
	tc.begin_round()
	tc.plan(0, {"action": "wait"})
	tc.resolve()
	_check(tc.done and tc.outcome in ["timeout", "enemy_left"], "回合用完就結束（%s）" % tc.outcome)
	# 兩種模式、每個情境，隨機打到結束不出錯
	var ok := true
	var outs := {}
	for m in ["sync", "alternate"]:
		for sc in ["grizzly_arrives", "grizzly_on_carcass", "grizzly_open", "cougar_cache", "cougar_ambush", "grizzly_arrives_mate", "grizzly_on_carcass_mate"]:
			for s in 20:
				tc = TacticalCombat.new()
				tc.setup(sc, {"seed": s, "mode": m})
				var guard := 0
				while not tc.done and guard < 40:
					guard += 1
					tc.begin_round()
					for i in tc.units.size():
						if tc.active(i) and tc.player_side(i):
							tc.plan(i, _random_plan(tc, i))
					tc.resolve()
				ok = ok and tc.done
				outs[tc.outcome] = int(outs.get(tc.outcome, 0)) + 1
	_check(ok, "兩種模式、七個情境各 20 場隨機打法都會結束：%s" % JSON.stringify(outs))

func _random_plan(tc: TacticalCombat, i: int) -> Dictionary:
	var p := {}
	var r: Dictionary = tc.reachable(i)
	if not r.is_empty() and tc.rng.randf() < 0.6:
		var cells: Array = r.keys()
		p["move"] = cells[tc.rng.randi_range(0, cells.size() - 1)]
	var acts := ["bite", "pounce", "harass", "take", "dodge", "wait", "retreat", "guard", "observe"]
	p["action"] = acts[tc.rng.randi_range(0, acts.size() - 1)]
	p["target"] = tc.enemy_index()
	p["kind"] = "piece"
	return p
