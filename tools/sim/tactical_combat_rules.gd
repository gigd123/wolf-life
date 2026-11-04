extends SceneTree
# 戰術戰鬥原型（docs/proposals/tactical-combat-prototype.md）的規則測試。每一步做完在這裡加檢查。
# 第 1 步：情境載入、單位、殘骸、移動範圍（喘、叼肉依大小變慢、大塊不能衝刺）、地形擋路、叼肉與放下、撤出地圖。
# 第 2 步：表態與範圍、同步結算（閃出範圍就打不到、目標走掉就撲空、衝撞停在第一個撞到的、假衝不傷人、閃避、變卦、先後與打斷）、
#   預告後輪流（對手出手前最多轉 45°）、叼肉的機率、結束（對手走了、撤出、被打倒、時間到）、兩種模式隨機打完不出錯。
# 第 3 步：物種只用自己能用的動作；注意力（被咬就看咬牠的）；威脅遠時吃、近時守或打；守食物時假衝比遭遇時多；
#   被圍背靠岩壁；美洲獅受傷上樹（殘骸留下）；放棄（血量、耐心、殘骸吃光）；個性不同。
# 第 4 步：資訊等級（知識、感知、距離、視線、觀察）、模糊不顯示範圍、部分顯示聯集、明確顯示這個動作；假動作的提示老練的比較常看出來；
#   機率顯示四種（風險＋寬範圍、範圍、約略、精確），範圍一定包含實際值、實際機率不變；看到出手就記一次、最多 3、有預留欄位。
# 第 5 步：伴侶的指令（預設自動）；牽制時站到和你不同的一側、不站正面、會騷擾，注意力被引過去；叼肉時灰熊在吃會叼到並撤出；
#   退開時保持距離；血量低自己撤；你牽制＋伴侶叼肉比你一隻拿到更多肉。
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
	_step3()
	_step4()
	_step5()
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

func _step3() -> void:
	print("第 3 步")
	# 物種只用自己能用的動作
	var used := {"grizzly_bear": {}, "cougar": {}}
	for sc in ["grizzly_arrives", "grizzly_on_carcass", "grizzly_open", "cougar_cache", "cougar_ambush", "grizzly_arrives_mate"]:
		for s in 30:
			var tc := TacticalCombat.new()
			tc.setup(sc, {"seed": s})
			var guard := 0
			while not tc.done and guard < 30:
				guard += 1
				var its: Dictionary = tc.begin_round()
				for k in its.keys():
					used[str(tc.units[k]["species"])][str(its[k]["action"])] = true
				for i in tc.units.size():
					if tc.active(i) and tc.player_side(i):
						tc.plan(i, _random_plan(tc, i))
				tc.resolve()
	var ok := true
	for sp in used.keys():
		var allowed: Array = TacticalCombat.new().cfg["opponents"][sp]["actions"]
		for a in used[sp].keys():
			if not allowed.has(a) and a != "flee":
				ok = false
				print("    %s 用了 %s" % [sp, a])
	_check(ok and not used["grizzly_bear"].has("climb") and not used["grizzly_bear"].has("pounce") and not used["cougar"].has("charge"),
		"只用自己能用的動作（灰熊 %s；美洲獅 %s）" % [", ".join(used["grizzly_bear"].keys()), ", ".join(used["cougar"].keys())])
	# 注意力：被咬就看咬牠的
	var tc := TacticalCombat.new()
	tc.setup("grizzly_arrives_mate", {"seed": 5})
	var e: int = tc.enemy_index()
	tc.units[e]["pos"] = Vector2i(9, 5)
	tc.units[0]["pos"] = Vector2i(8, 5)
	tc.units[1]["pos"] = Vector2i(10, 6)
	tc.units[e]["bitten_by"] = 1
	var it: Dictionary = tc.begin_round()[e]
	_check(int(tc.units[e]["attention"]) == 1 and TacticalGrid.side_of(Vector2i(9, 5), it["facing"], Vector2i(10, 6)) != "rear", "被伴侶咬了：注意力轉到伴侶、轉身面向牠")
	# 威脅遠時吃
	var eat := 0
	var near_eat := 0
	for s in 100:
		tc = TacticalCombat.new()
		tc.setup("grizzly_on_carcass", {"seed": s})
		e = tc.enemy_index()
		if str(tc.begin_round()[e]["action"]) == "eat": eat += 1
		tc = TacticalCombat.new()
		tc.setup("grizzly_on_carcass", {"seed": s})
		tc.units[0]["pos"] = Vector2i(9, 4)
		if str(tc.begin_round()[tc.enemy_index()]["action"]) == "eat": near_eat += 1
	_check(eat > 80 and near_eat < 25, "你在遠處時灰熊多半在吃（%d／100），你到殘骸旁就不太吃了（%d／100）" % [eat, near_eat])
	# 守食物時假衝比遭遇時多
	var bluff_food := 0
	var bluff_open := 0
	var charges_food := 0
	var charges_open := 0
	for s in 400:
		tc = TacticalCombat.new()
		tc.setup("grizzly_arrives", {"seed": s})
		e = tc.enemy_index()
		tc.units[e]["pos"] = Vector2i(8, 5)
		tc.units[e]["facing"] = Vector2i(-1, 0)
		tc.units[0]["pos"] = Vector2i(5, 5)
		var a1: String = str(tc.begin_round()[e]["action"])
		if a1 == "bluff_charge": bluff_food += 1
		if a1 in ["bluff_charge", "charge"]: charges_food += 1
		tc = TacticalCombat.new()
		tc.setup("grizzly_open", {"seed": s})
		e = tc.enemy_index()
		tc.units[e]["pos"] = Vector2i(8, 5)
		tc.units[0]["pos"] = Vector2i(5, 5)
		var a2: String = str(tc.begin_round()[e]["action"])
		if a2 == "bluff_charge": bluff_open += 1
		if a2 in ["bluff_charge", "charge"]: charges_open += 1
	_check(float(bluff_food) / max(1, charges_food) > float(bluff_open) / max(1, charges_open), "守食物時的衝撞多半是假衝（%d／%d），遭遇時比較少（%d／%d）" % [bluff_food, charges_food, bluff_open, charges_open])
	# 被圍：背靠岩壁
	var wall := 0
	for s in 100:
		tc = TacticalCombat.new()
		tc.setup("cougar_cache", {"seed": s})
		e = tc.enemy_index()
		tc.carcass = {}
		tc.units[e]["pos"] = Vector2i(3, 5)
		tc.units[e]["facing"] = Vector2i(1, 0)
		tc.units[e]["bold"] = 0.0
		tc.cfg["opponents"]["cougar"]["actions"].erase("climb")
		tc.units[0]["pos"] = Vector2i(4, 5)
		tc.units.append(tc._make_wolf("mate", "ally", Vector2i(3, 6), tc.units[0]["stats"].duplicate()))
		if str(tc.begin_round()[e]["action"]) == "back_to_wall": wall += 1
	_check(wall > 20, "美洲獅被兩隻圍住、旁邊有峭壁：常背靠岩壁（%d／100）" % wall)
	# 美洲獅受傷上樹，殘骸留下
	var climbed := 0
	for s in 50:
		tc = TacticalCombat.new()
		tc.setup("cougar_cache", {"seed": s})
		e = tc.enemy_index()
		tc.units[e]["pos"] = Vector2i(5, 3)
		tc.units[e]["hp"] = float(tc.units[e]["hp_max"]) * 0.5
		tc.units[0]["pos"] = Vector2i(6, 4)
		var guard2 := 0
		while not tc.done and guard2 < 6:
			guard2 += 1
			tc.begin_round()
			tc.plan(0, {"action": "wait"})
			tc.resolve()
		if str(tc.units[e]["out_reason"]) == "climbed":
			climbed += 1
			ok = int(tc.carcass["segments"]) > 0
	_check(climbed > 15, "美洲獅受傷、樹在旁邊：常上樹（%d／50），殘骸留下" % climbed)
	# 放棄：耐心用完（遭遇戰你一直保持距離）
	var left := 0
	for s in 30:
		tc = TacticalCombat.new()
		tc.setup("grizzly_open", {"seed": s})
		e = tc.enemy_index()
		tc.units[0]["pos"] = Vector2i(0, 0)
		tc.units[e]["pos"] = Vector2i(15, 9)
		tc.cfg["ai"]["scores"]["approach_threat"] = -10.0
		var g := 0
		while not tc.done and g < 30:
			g += 1
			tc.begin_round()
			tc.plan(0, {"action": "wait"})
			tc.resolve()
		if tc.outcome == "enemy_left" and str(tc.units[e]["out_reason"]) == "patience": left += 1
	_check(left > 20, "遭遇戰你一直保持距離：灰熊失去興趣走了（%d／30）" % left)
	# 殘骸吃光就走
	tc = TacticalCombat.new()
	tc.setup("grizzly_on_carcass", {"seed": 1})
	tc.carcass["segments"] = 0
	_check(str(tc.begin_round()[tc.enemy_index()]["action"]) == "flee", "殘骸吃光了，灰熊就走")
	# 個性
	var bolds := {}
	for s in 20:
		tc = TacticalCombat.new()
		tc.setup("grizzly_open", {"seed": s})
		bolds[snappedf(float(tc.units[tc.enemy_index()]["bold"]), 0.1)] = true
	_check(bolds.size() >= 6, "每隻灰熊的個性不同（%d 種）" % bolds.size())

func _setup_k(know: String, prof := "average", sc := "grizzly_open", seed := 1) -> TacticalCombat:
	var tc := TacticalCombat.new()
	tc.setup(sc, {"seed": seed, "knowledge": know, "wolf_profile": prof})
	return tc

func _step4() -> void:
	print("第 4 步")
	# 資訊等級
	var tc := _setup_k("novice")
	var e: int = tc.enemy_index()
	tc.units[0]["pos"] = Vector2i(7, 5)
	var nov: int = tc.info_level(0, e, "swipe")
	tc = _setup_k("veteran")
	tc.units[0]["pos"] = Vector2i(7, 5)
	var vet: int = tc.info_level(0, e, "swipe")
	_check(vet > nov, "老練的看得比新手清楚（%d → %d）" % [nov, vet])
	tc = _setup_k("experienced")
	tc.units[0]["pos"] = Vector2i(7, 5)
	var near: int = tc.info_level(0, e, "swipe")
	tc.units[0]["pos"] = Vector2i(1, 5)
	var far: int = tc.info_level(0, e, "swipe")
	tc.units[0]["pos"] = Vector2i(3, 2)
	tc.units[e]["pos"] = Vector2i(5, 2)
	var through_forest: bool = tc.line_of_sight(Vector2i(3, 2), Vector2i(5, 2))
	var blocked: int = tc.info_level(0, e, "swipe")
	_check(far < near and not through_forest and blocked < near, "遠（%d）、視線被密林擋住（%d）都比近（%d）看不清楚" % [far, blocked, near])
	tc = _setup_k("experienced")
	tc.units[0]["pos"] = Vector2i(7, 5)
	tc.begin_round()
	tc.plan(0, {"action": "observe"})
	tc.resolve()
	var before: int = tc.info_level(0, e, "swipe")
	tc.begin_round()
	_check(tc.info_level(0, e, "swipe") == mini(3, before + 1), "觀察後下一回合高一級")
	# 模糊、部分、明確的範圍
	var ok_zone := true
	for know in ["novice", "experienced", "veteran"]:
		for prof in ["novice", "average", "veteran"]:
			for s in 20:
				tc = _setup_k(know, prof, "grizzly_open", s)
				e = tc.enemy_index()
				tc.units[0]["pos"] = Vector2i(8, 5)
				var its: Dictionary = tc.begin_round()
				var it: Dictionary = its[e]
				var seen: Dictionary = it["seen"]
				var real: Array = tc.zone_cells(e, str(it["looks"]), it["move"], it["facing"], it["target"])
				match int(seen["level"]):
					0: ok_zone = ok_zone and (seen["zone"] as Array).is_empty()
					1:
						for c in real:
							ok_zone = ok_zone and (not seen["attack"] or (seen["zone"] as Array).has(c))
					_: ok_zone = ok_zone and (seen["zone"] as Array) == real
	_check(ok_zone, "模糊不顯示範圍、部分顯示可能範圍的聯集（包含實際的）、明確以上顯示這個動作的範圍")
	# 假動作的提示
	var hints := {}
	for know in ["novice", "experienced", "veteran"]:
		var h := 0
		var n := 0
		for s in 400:
			tc = _setup_k(know, "veteran", "grizzly_open", s)
			e = tc.enemy_index()
			tc.units[0]["pos"] = Vector2i(5, 5)
			tc.units[e]["pos"] = Vector2i(8, 5)
			tc.rounds = 1
			tc.intents = {e: tc._intent(e, "bluff_charge", Vector2i(8, 5), Vector2i(-1, 0), Vector2i(-1, -1), "bluff")}
			var seen2: Dictionary = tc.telegraph(0, e)
			n += 1
			if seen2["feint_hint"]: h += 1
		hints[know] = h
	_check(hints["novice"] == 0 and hints["veteran"] > hints["experienced"], "假衝的提示：新手 %d、有經驗 %d、老練 %d（／400）" % [hints["novice"], hints["experienced"], hints["veteran"]])
	# 機率顯示
	var ok_show := true
	var tiers := {}
	for know in ["novice", "experienced", "veteran"]:
		tc = _setup_k(know)
		e = tc.enemy_index()
		for ch in [0.12, 0.43, 0.77]:
			var d: Dictionary = tc.display_chance(0, ch, "grizzly_bear")
			tiers[know] = int(d["tier"])
			if int(d["tier"]) <= 1:
				ok_show = ok_show and float(d["lo"]) <= ch + 0.001 and float(d["hi"]) >= ch - 0.001
			match int(d["tier"]):
				0: ok_show = ok_show and float(d["hi"]) - float(d["lo"]) >= 0.2 and d["risk"] in ["high", "mid", "low"]
				2: ok_show = ok_show and is_equal_approx(float(d["lo"]), snappedf(ch, 0.05))
				3: ok_show = ok_show and is_equal_approx(float(d["lo"]), ch)
	_check(ok_show and tiers["novice"] == 0 and tiers["veteran"] == 3, "機率顯示：新手風險＋寬範圍（包含實際值）、有經驗約略（以 5%% 為單位）、老練精確（%s）" % JSON.stringify(tiers))
	tc = _setup_k("novice")
	tc.units[0]["pos"] = Vector2i(8, 5)
	var opts: Array = tc.action_options(0)
	var bite: Dictionary = opts.filter(func(o): return o["id"] == "bite")[0]
	var tc2 := _setup_k("veteran")
	tc2.units[0]["pos"] = Vector2i(8, 5)
	var bite2: Dictionary = tc2.action_options(0).filter(func(o): return o["id"] == "bite")[0]
	_check(is_equal_approx(float(bite["chance"]), float(bite2["chance"])), "知識只改變顯示，實際機率一樣（%.0f%%）" % (float(bite["chance"]) * 100.0))
	# 學習
	tc = _setup_k("novice")
	e = tc.enemy_index()
	tc.units[0]["pos"] = Vector2i(5, 5)
	tc.units[e]["pos"] = Vector2i(6, 5)
	tc.units[e]["facing"] = Vector2i(-1, 0)
	tc.units[0]["hp"] = 9999.0
	for r in 5:
		_force(tc, "swipe")
		tc.plan(0, {"action": "wait"})
		tc.resolve()
	var entry: Dictionary = tc.knowledge["grizzly_bear|swipe"]
	_check(int(entry["count"]) == 3 and entry.has("category") and entry.has("source"), "看到揮掌就記一次、最多 3（預留 category、source）")

# 跑一場：你照 you_plan（Callable(tc) -> plan）做，伴侶照指令；回傳 tc
func _play(sc: String, seed: int, you_plan: Callable, cmd := "auto", rounds := 30) -> TacticalCombat:
	var tc := TacticalCombat.new()
	tc.setup(sc, {"seed": seed, "knowledge": "experienced"})
	var m := tc.index_of("mate")
	if m >= 0:
		tc.set_command(m, cmd)
	var g := 0
	while not tc.done and g < rounds:
		g += 1
		tc.begin_round()
		tc.plan(0, you_plan.call(tc))
		tc.resolve()
	return tc

# 你：先在殘骸附近牽制（站在灰熊正面外、騷擾），伴侶去叼；你自己有機會也叼，叼到就撤
func _you_harass(tc: TacticalCombat) -> Dictionary:
	var e: int = tc.enemy_index()
	var u: Dictionary = tc.units[0]
	if str(u["carrying"]) != "":
		if tc.map.on_edge(u["pos"]):
			return {"action": "retreat"}
		var edge: Vector2i = tc._nearest_edge_away(0)
		return {"move": tc._ally_move(0, edge, tc._shown_zone_for(0)), "action": "wait"}
	if not tc.active(e):
		return {"action": "wait"}
	if tc.take_kinds(0).has("piece") and (bool(tc.units[e]["eating"]) or int(tc.units[e].get("attention", -1)) != 0):
		return {"action": "take", "kind": "piece"}
	var ep: Vector2i = tc.units[e]["pos"]
	var zone: Dictionary = tc._shown_zone_for(0)
	var goal: Vector2i = ep + Vector2i(-1, 0)
	var mv: Vector2i = tc._ally_move(0, goal, zone, false, Vector2i(0, 0))
	var p := {"action": "harass", "target": e}
	if mv != u["pos"]:
		p["move"] = mv
	if not tc.map.adjacent(mv, ep):
		p["action"] = "wait"
	return p

# 你一隻：繞到殘骸背面，牠吃的時候叼一塊就撤
func _you_solo(tc: TacticalCombat) -> Dictionary:
	var e: int = tc.enemy_index()
	var u: Dictionary = tc.units[0]
	if str(u["carrying"]) != "":
		if tc.map.on_edge(u["pos"]):
			return {"action": "retreat"}
		return {"move": tc._ally_move(0, tc._nearest_edge_away(0), tc._shown_zone_for(0)), "action": "wait"}
	if tc.take_kinds(0).has("piece") and tc.active(e) and (bool(tc.units[e]["eating"]) or TacticalGrid.side_of(tc.units[e]["pos"], tc.units[e]["facing"], u["pos"]) != "front"):
		return {"action": "take", "kind": "piece"}
	if tc.carcass.is_empty() or int(tc.carcass["segments"]) <= 0:
		return {"action": "wait"}
	var p := {"action": "wait"}
	var mv: Vector2i = tc._ally_move(0, tc.carcass["pos"] + Vector2i(0, -1), tc._shown_zone_for(0), false, Vector2i(0, 0))
	if mv != u["pos"]:
		p["move"] = mv
	return p

func _step5() -> void:
	print("第 5 步")
	var tc := TacticalCombat.new()
	tc.setup("grizzly_arrives_mate", {"seed": 1})
	var m: int = tc.index_of("mate")
	_check(str(tc.units[m]["command"]) == "auto", "伴侶的指令預設是自動")
	# 牽制：站到不同的一側、不站正面、會騷擾
	var sides_ok := 0
	var harassed := 0
	var drew := 0
	for s in 40:
		tc = TacticalCombat.new()
		tc.setup("grizzly_arrives_mate", {"seed": s, "knowledge": "experienced"})
		m = tc.index_of("mate")
		var e: int = tc.enemy_index()
		tc.set_command(m, "harass")
		tc.units[e]["pos"] = Vector2i(9, 5)
		tc.units[e]["facing"] = Vector2i(-1, 0)
		tc.units[0]["pos"] = Vector2i(8, 5)
		tc.units[0]["hp"] = 9999.0
		tc.units[m]["hp"] = 9999.0
		for r in 4:
			tc.begin_round()
			tc.plan(0, {"action": "dodge"})
			tc.resolve()
			if tc.done: break
		if tc.active(e) and TacticalGrid.side_of(tc.units[e]["pos"], tc.units[e]["facing"], tc.units[m]["pos"]) != "front" or int(tc.units[e].get("attention", -1)) == m:
			sides_ok += 1
		for ev in tc.events:
			pass
		if int(tc.units[e].get("attention", -1)) == m: drew += 1
	for s in 40:
		tc = TacticalCombat.new()
		tc.setup("grizzly_arrives_mate", {"seed": s, "knowledge": "experienced"})
		m = tc.index_of("mate")
		tc.set_command(m, "harass")
		var e2: int = tc.enemy_index()
		tc.units[e2]["pos"] = Vector2i(9, 5)
		tc.units[e2]["facing"] = Vector2i(-1, 0)
		tc.units[0]["pos"] = Vector2i(8, 5)
		var any := false
		for r in 4:
			tc.begin_round()
			tc.plan(0, {"action": "dodge"})
			tc.resolve()
			for ev in tc.events:
				if str(ev["kind"]) == "bite" and int(ev["who"]) == m:
					any = true
			if tc.done: break
		if any: harassed += 1
	_check(sides_ok > 25 and harassed > 15 and drew > 8, "牽制：伴侶站到牠側後方（%d／40）、會騷擾（%d／40）、把注意力引過去（%d／40）" % [sides_ok, harassed, drew])
	# 叼肉：灰熊在吃、伴侶叼到並撤出
	var got := 0
	for s in 40:
		tc = _play("grizzly_on_carcass_mate", s, func(t): return {"action": "wait"}, "take", 20)
		for u in tc.units:
			if str(u["id"]) == "mate" and bool(u["out"]) and str(u["out_reason"]) == "retreated" and int(u["carry_segments"]) > 0:
				got += 1
	_check(got > 15, "叼肉：灰熊在吃時，伴侶叼到一塊並撤出地圖（%d／40）" % got)
	# 退開：保持距離
	var kept := 0
	for s in 30:
		tc = TacticalCombat.new()
		tc.setup("grizzly_open", {"seed": s, "with_mate": true})
		m = tc.index_of("mate")
		if m < 0:
			tc.units.insert(1, tc._make_wolf("mate", "ally", Vector2i(5, 6), tc.units[0]["stats"].duplicate()))
			m = 1
		tc.set_command(m, "back")
		for r in 3:
			tc.begin_round()
			tc.plan(0, {"action": "wait"})
			tc.resolve()
			if tc.done: break
		var e3: int = tc.enemy_index()
		if not tc.active(e3) or not tc.active(m) or tc.map.dist(tc.units[m]["pos"], tc.units[e3]["pos"]) >= 2.5:
			kept += 1
	_check(kept > 22, "退開：伴侶和灰熊保持距離（%d／30）" % kept)
	# 血量低自己撤
	tc = TacticalCombat.new()
	tc.setup("grizzly_arrives_mate", {"seed": 2})
	m = tc.index_of("mate")
	tc.set_command(m, "harass")
	tc.units[m]["hp"] = float(tc.units[m]["hp_max"]) * 0.3
	_check(tc.ally_mode(m) == "escape", "伴侶血量低於四成：不管指令，自己撤")
	# 你牽制＋伴侶叼肉，比你一隻拿到更多肉
	var duo := 0
	var solo := 0
	var mate_hurt := 0
	for s in 60:
		tc = _play("grizzly_on_carcass_mate", s, _you_harass, "take")
		duo += tc.meat_taken()
		var mm: int = tc.index_of("mate")
		if float(tc.units[mm]["hp"]) < float(tc.units[mm]["hp_max"]): mate_hurt += 1
		tc = _play("grizzly_on_carcass", s, _you_solo)
		solo += tc.meat_taken()
	_check(duo > solo, "你牽制＋伴侶叼肉：60 場共 %d 段；你一隻 %d 段（伴侶受傷 %d 場）" % [duo, solo, mate_hurt])
