extends SceneTree
# Phase 2o 第 3 步：地形與逃跑路線的規則。
# 開闊的平地、狼在 open_bonus_min_dist 格以外：逃跑多 open_bonus 格；狼貼在後面時不算；
# 難走的地形照 rough_mult 算（物種的 terrain_cost 照舊覆寫：騾鹿在岩坡不減速）；
# 逃跑方向偏好開闊、好跑的地方；牠在開闊地拉開距離時判定追不上，本能放棄（不白白耗喘）。
# 用法：bash tools/run_sim.sh hunt_flee_terrain_rules
var f := 0
var fails := 0
const WOLF := {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _set_ter(h, c: Vector2i, ch: String) -> void:
	if not h.in_bounds(c):
		return
	var row: String = h.grid[c.y]
	h.grid[c.y] = row.substr(0, c.x) + ch + row.substr(c.x + 1)

func _clear(h, center: Vector2i, r: int) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			_set_ter(h, center + Vector2i(dx, dy), ".")

func _fleeing(TH, species: String = "deer"):
	var h = TH.new()
	var ctx := {"family": "open", "seed": 5, "condition": "average", "wolf": WOLF, "wind_relation": "crosswind"}
	if species != "deer":
		ctx["species"] = species
	h.setup_from_game(ctx)
	h.deer_state = "flee"
	h.herd[h.di]["state"] = "flee"
	h.flee_round = 2
	h.herd[h.di]["flee_round"] = 2
	var dp := Vector2i(h.width / 2, h.height / 2)
	h.deer_pos = dp
	h.herd[h.di]["pos"] = dp
	_clear(h, dp, 3)
	return h

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var ft: Dictionary = TH.new().t["deer"].get("flee_terrain", {})
	_ok(not ft.is_empty(), "tactical_hunt.json 的 deer 有 flee_terrain 設定")
	var md: float = float(ft.get("open_bonus_min_dist", 0.0))
	# 開闊地多跑
	var h = _fleeing(TH)
	h.wolf_pos = h.deer_pos + Vector2i(-int(md) - 2, 0)
	_ok(h.open_ground(h.deer_pos), "四周都是平地：開闊")
	var far_open: float = h._flee_budget()
	h.wolf_pos = h.deer_pos + Vector2i(-2, 0)
	var near_open: float = h._flee_budget()
	_ok(far_open >= near_open + float(ft.get("open_bonus", 0.0)) - 0.01, "狼在 %.0f 格外才多跑（遠 %.1f、貼著 %.1f）" % [md, far_open, near_open])
	h.wolf_pos = h.deer_pos + Vector2i(-int(md) - 2, 0)
	_set_ter(h, h.deer_pos + Vector2i(1, 1), "l")
	_ok(not h.open_ground(h.deer_pos), "旁邊一格有倒木：不算開闊")
	_ok(h._flee_budget() <= far_open - float(ft.get("open_bonus", 0.0)) + 0.01, "不開闊時沒有加成（%.1f）" % h._flee_budget())
	# 難走的地形
	var h2 = _fleeing(TH)
	var c: Vector2i = h2.deer_pos + Vector2i(1, 0)
	_set_ter(h2, c, "l")
	var wolf_l: float = float(h2.t["move"]["terrain_extra"]["l"])
	_ok(absf(h2.deer_extra(c) - wolf_l * float(ft.get("rough_mult", 1.0))) < 0.01, "倒木：獵物多花狼的 %.1f 倍（%.1f）" % [float(ft.get("rough_mult", 1.0)), h2.deer_extra(c)])
	_set_ter(h2, c, "c")
	_ok(absf(h2.deer_extra(c) - float(h2.t["move"]["terrain_extra"]["c"])) < 0.01, "峭壁不打折")
	var hm = _fleeing(TH, "mule_deer")
	_set_ter(hm, hm.deer_pos + Vector2i(1, 0), "r")
	_ok(hm.deer_extra(hm.deer_pos + Vector2i(1, 0)) == 0.0, "成年騾鹿在岩坡不減速（物種覆寫）")
	# 逃跑方向偏好開闊：東邊一大片倒木、西邊開闊，狼在北邊，牠往西多
	var west := 0
	var east := 0
	for i in 60:
		var h3 = _fleeing(TH)
		h3.rng.seed = 1000 + i
		var dp: Vector2i = h3.deer_pos
		for dy in range(-3, 4):
			for dx in range(2, 6):
				_set_ter(h3, dp + Vector2i(dx, dy), "f")
		_clear(h3, dp + Vector2i(-4, 0), 2)
		h3.wolf_pos = dp + Vector2i(0, -3)
		h3.deer_facing = Vector2i(0, 1)
		var p0: Vector2i = h3.deer_pos
		h3._deer_flee()
		if h3.deer_pos.x < p0.x:
			west += 1
		elif h3.deer_pos.x > p0.x:
			east += 1
	_ok(west > east, "逃跑往開闊那一側多（西 %d、東 %d）" % [west, east])
	# 追不上：開闊地、拉開距離
	var h4 = _fleeing(TH)
	h4.target = h4.di
	_clear(h4, h4.deer_pos, 2)
	var gap: float = float(ft.get("give_up", {}).get("gap", 3.0))
	h4.wolf_pos = h4.deer_pos + Vector2i(-int(h4.sprint_range() + gap) - 1, 0)
	if not h4.in_bounds(h4.wolf_pos):
		h4.wolf_pos = h4.deer_pos + Vector2i(int(h4.sprint_range() + gap) + 1, 0)
	_ok(h4.open_chase_hopeless(), "開闊地、離你 %.0f 格：追不上" % h4.dist(h4.wolf_pos, h4.deer_pos))
	var b0: float = h4.breath
	TacticalInstinct.step(h4, "stalk")
	_ok(h4.done and h4.result == "gave_up", "本能放棄（%s）" % h4.result)
	_ok(h4.breath >= b0 - 0.01, "放棄那一下沒耗喘")
	var h5 = _fleeing(TH)
	h5.target = h5.di
	h5.wolf_pos = h5.deer_pos + Vector2i(-3, 0)
	_ok(not h5.open_chase_hopeless(), "離你 3 格：還追得上")
	print("地形與逃跑路線的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
