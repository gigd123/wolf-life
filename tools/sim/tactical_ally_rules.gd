extends SceneTree
# 苔原狼一起狩獵實驗（docs/proposals/tundra-joint-tactical.md，使用者選方案 A ＋ 互相圍攻）的回歸測試：
#   1. 只有你一隻狼時，新的規則都不作用（逃跑方向、距離、埋伏、同伴咬住）
#   2. 驅趕：你和驅趕的同伴隔著獵物相對（空地）時，牠往你這邊逃，你藏著時撲有埋伏加成
#   3. 同伴咬住：獵物不動（除非掙脫）；你撲牠有「苔原狼拖住了牠」加成、被踢的機率減半；撲中就換你咬住
#   4. 你咬住時：遠處的同伴衝刺過來；旁邊有同伴時牠比較難掙脫；旁邊 1／2 隻同伴時招式的喘 × 0.5／0.3，成功率不變
#   5. 同伴停著時回喘；你撲空的回合同伴也動
# 用法：bash tools/run_sim.sh tactical_ally_rules
var f := 0
var fails := 0
const TH := preload("res://scripts/core/TacticalHunt.gd")
const WOLF := {"speed": 60, "skill": 55, "strength": 55, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	# 1. 單狼
	var h = _new(1)
	h.deer_state = "flee"
	_check(h._away_dir().is_equal_approx(Vector2(h.deer_pos - h.wolf_pos).normalized()), "單狼：逃離你的方向不變")
	_check(is_equal_approx(h._threat_dist(h.deer_pos), h.dist(h.deer_pos, h.wolf_pos)), "單狼：離狼的距離就是離你")
	_check(h._ambush_bonus("still") == 0.0 and h._ally_holding() == 0 and not h._driven(), "單狼：沒有埋伏、沒有同伴咬住")
	# 2. 驅趕與埋伏
	var toward := 0
	var amb := 0
	var caught := 0
	for i in 30:
		h = _open_field(i)
		h.add_ally("drive", Vector2i(h.width / 2, h.height / 2) + Vector2i(3, 0))
		var me: Vector2i = h.wolf_pos
		var first_flee := Vector2i(-1, -1)
		var guard := 0
		while not h.done and guard < 30:
			guard += 1
			TacticalInstinct.step(h, "hold")
			if first_flee.x < 0 and h.deer_state == "flee":
				first_flee = h.deer_pos
		if first_flee.x >= 0 and h.dist(first_flee, me) < 5.0:
			toward += 1
		amb += int(h.stats.get("p_ambush", 0))
		if h.result == "caught":
			caught += 1
	_check(toward >= 20, "驅趕：獵物往你這邊逃（%d／30 場逃到離你 5 格內）" % toward)
	_check(amb >= 10, "驅趕：你藏著時撲有埋伏加成（%d 次）" % amb)
	_check(caught >= 18, "驅趕到你面前，大多獵得到（%d／30）" % caught)
	# 3. 同伴咬住
	var stayed := 0
	var broke := 0
	for i in 200:
		h = _new(i)
		h.add_ally("chase", h.deer_pos + Vector2i(1, 0))
		h.deer_state = "flee"
		h.herd[h.di]["ally_held"] = 1
		var p0: Vector2i = h.deer_pos
		h.rounds += 1
		h._deer_turn()
		if h.done:
			continue
		if h._ally_holding() == 1:
			if h.deer_pos == p0:
				stayed += 1
		else:
			broke += 1
	_check(stayed > 80 and broke > 30 and stayed + broke >= 190, "同伴咬住：大多拖得住、有時掙脫（拖住 %d、掙脫 %d／200）" % [stayed, broke])
	h = _new(3)
	h.add_ally("chase", h.deer_pos + Vector2i(1, 0))
	h.deer_state = "flee"
	h.flee_round = 3
	var k0: float = h.kick_chance()
	var c0: float = h.pounce_chance("still")["chance"]
	h.herd[h.di]["ally_held"] = 1
	var info: Dictionary = h.pounce_chance("still")
	var has_f := false
	for fa in info["factors"]:
		if fa[0] == h._tx("tactical.factor.ally_holding"):
			has_f = true
	_check(has_f and info["chance"] > c0 + 0.2, "撲被拖住的獵物有加成（%.2f → %.2f）" % [c0, info["chance"]])
	_check(is_equal_approx(h.kick_chance(), k0 * 0.5), "被拖住時踢中的機率減半")
	var transferred := false
	for i in 40:
		h = _new(i)
		h.add_ally("chase", h.deer_pos + Vector2i(1, 0))
		h.deer_state = "flee"
		h.herd[h.di]["ally_held"] = 1
		h.wolves[0]["pos"] = h.deer_pos + Vector2i(-1, 0)
		h.pounce()
		if h.held:
			transferred = h._ally_holding() == 0
			break
	_check(transferred, "撲中被拖住的獵物：換你咬住")
	# 4. 你咬住時同伴衝過來、比較難掙脫
	h = _new(5)
	h.add_ally("chase", h.deer_pos + Vector2i(-9, 0))
	h.held = true
	h.hold_side = "rear"
	var d0: float = h.dist(h.wolves[1]["pos"], h.deer_pos)
	h._allies_turn()
	_check(h.dist(h.wolves[1]["pos"], h.deer_pos) <= d0 - 4.0 and str(h.wolves[1]["mode"]) == "sprint", "你咬住時同伴衝刺過來（%.1f → %.1f，%s）" % [d0, h.dist(h.wolves[1]["pos"], h.deer_pos), h.wolves[1]["mode"]])
	var b_far: float = h.break_chance()
	h.wolves[1]["pos"] = h.deer_pos + Vector2i(1, 1)
	_check(h.break_chance() < b_far - 0.05, "旁邊有同伴時比較難掙脫（%.2f → %.2f）" % [b_far, h.break_chance()])
	# 一起咬住省喘、成功率不變
	h = _new(6)
	h.held = true
	h.hold_side = "rear"
	h.wolves[0]["breath"] = 50.0
	var solo: Dictionary = h.hold_options()
	h.add_ally("chase", h.deer_pos + Vector2i(1, 1))
	var one: Dictionary = h.hold_options()
	h.add_ally("drive", h.deer_pos + Vector2i(1, -1))
	h.wolves[2]["pos"] = h.deer_pos + Vector2i(1, -1)
	var two: Dictionary = h.hold_options()
	_check(is_equal_approx(float(one["takedown"]["breath"]), float(solo["takedown"]["breath"]) * 0.5) and is_equal_approx(float(two["takedown"]["breath"]), float(solo["takedown"]["breath"]) * 0.3),
		"旁邊 1／2 隻同伴：壓倒的喘 %.1f → %.1f → %.1f" % [solo["takedown"]["breath"], one["takedown"]["breath"], two["takedown"]["breath"]])
	_check(is_equal_approx(float(two["takedown"]["chance"]), float(solo["takedown"]["chance"])) and is_equal_approx(float(two["throat"]["chance"]), float(solo["throat"]["chance"])), "一起咬著時壓倒、咬喉的成功率和單狼一樣")
	# 同伴停著回喘
	h = _new(7)
	h.add_ally("chase", h.wolf_pos)
	h.wolves[1]["breath"] = 10.0
	h.wolves[1]["pos"] = h.deer_pos + Vector2i(1, 0)
	h.deer_state = "suspicious"
	h.held = true
	h.herd[h.di]["ally_held"] = 1
	h.held = false
	h._allies_turn()
	_check(float(h.wolves[1]["breath"]) > 10.0, "同伴停著（咬著）時回喘（10 → %.0f）" % h.wolves[1]["breath"])
	# 撲空的回合同伴也動
	var moved := false
	for i in 40:
		h = _new(i)
		h.add_ally("chase", h.deer_pos + Vector2i(-8, 0))
		h.deer_state = "flee"
		h.flee_round = 1
		h.wolves[0]["pos"] = h.deer_pos + Vector2i(-1, 0)
		var a0: Vector2i = h.wolves[1]["pos"]
		h.pounce()
		if not h.held and not h.done:
			moved = h.wolves[1]["pos"] != a0
			break
	_check(moved, "你撲空的回合同伴也會動")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _new(seed: int):
	var h = TH.new()
	h.setup_from_game({"family": "open", "seed": seed * 31 + 5, "condition": "average", "wolf": WOLF, "wind_relation": "crosswind", "species": "deer", "season": "autumn"})
	h.t = h.t.duplicate(true)
	return h

# 全空地：你在獵物西邊 5 格，獵物沒察覺
func _open_field(seed: int):
	var h = _new(seed)
	for y in h.height:
		for x in h.width:
			h.grid[y][x] = "."
	var mid := Vector2i(h.width / 2, h.height / 2)
	h.wolves[0]["pos"] = mid + Vector2i(-5, 0)
	h.deer_pos = mid
	h.alert = 0.0
	h.deer_state = "unaware"
	return h

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
	else:
		print("  ✓ " + what)
