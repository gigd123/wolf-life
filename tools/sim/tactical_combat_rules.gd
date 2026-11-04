extends SceneTree
# 戰術戰鬥原型（docs/proposals/tactical-combat-prototype.md）的規則測試。每一步做完在這裡加檢查。
# 第 1 步：情境載入、單位、殘骸、移動範圍（喘、叼肉依大小變慢、大塊不能衝刺）、地形擋路、叼肉與放下、撤出地圖。
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
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
