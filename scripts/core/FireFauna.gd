class_name FireFauna
extends RefCounted
# 森林大火逃生地圖裡的其他動物（Phase 2n 第 6 步，2026-11-13；SPEC「其他動物（提示，不是導航）」）。
# 鹿群、雪兔、渡鴉、熊：察覺到火（離燃燒的格子 notice 格內、或身上有煙；渡鴉一開場就飛起來）之後往某一邊逃，
# 那一邊照「火最晚燒到」挑（safe_pick 的機率），其他時候慌了亂挑一邊（可能是錯的）——玩家從牠們的動向推測，不能當成箭頭。
# 動物不攻擊狼、不擋路、不影響火；用自己的亂數（rng_a），所以火的變化、狼受的傷和沒有動物時一樣（模擬基準不變）。
# 看到牠們開始逃（在視線內；渡鴉在兩倍視線內也看得到）時寫一句：哪種動物、幾隻、往哪一邊。
# 牠們走到地圖邊上就離開；被火燒到的格子就不見（不寫）。

var rng_a := RandomNumberGenerator.new()
var animals: Array = [] # {id, kind, group, pos, target, fleeing, gone, seen}
var _cfg: Dictionary = {}
var _next_id := 0

func setup(fe, seed: int) -> void:
	rng_a.seed = seed * 13 + 11
	animals = []
	_cfg = fe.c.get("animals", {})
	var kinds: Dictionary = _cfg.get("kinds", {})
	var gid := 0
	for k in kinds:
		var kc: Dictionary = kinds[k]
		if rng_a.randf() >= float(kc.get("chance", 1.0)):
			continue
		var groups: Array = kc.get("groups", [1, 1])
		for gi in rng_a.randi_range(int(groups[0]), int(groups[1])):
			var size: Array = kc.get("size", [1, 1])
			var n: int = rng_a.randi_range(int(size[0]), int(size[1]))
			var home: Vector2i = _spawn_cell(fe, kc)
			if home.x < 0:
				continue
			for i in n:
				var p: Vector2i = home if i == 0 else _near_free(fe, home, kc)
				animals.append({"id": _next_id, "kind": k, "group": gid, "pos": p, "target": "", "fleeing": false, "gone": false, "seen": false})
				_next_id += 1
			gid += 1

# 出現的地方：照這種動物喜歡的地形（on），離狼 min_wolf 格以上、還沒燒、不在邊上
func _spawn_cell(fe, kc: Dictionary) -> Vector2i:
	var on: Array = kc.get("on", [])
	var md: int = int(kc.get("min_wolf", 4))
	var cands: Array = []
	for y in range(2, fe.height - 2):
		for x in range(2, fe.width - 2):
			var p := Vector2i(x, y)
			if fe.fire.has(p) or fe._cheb(p, fe.wolf_pos) < md:
				continue
			if not on.is_empty() and not fe.terrain(p) in on:
				continue
			if fe.terrain(p) in ["d", "w"] and not bool(kc.get("fly", false)):
				continue
			cands.append(p)
	if cands.is_empty():
		return Vector2i(-1, -1)
	return cands[rng_a.randi_range(0, cands.size() - 1)]

func _near_free(fe, home: Vector2i, kc: Dictionary) -> Vector2i:
	for t in 12:
		var p := home + Vector2i(rng_a.randi_range(-2, 2), rng_a.randi_range(-2, 2))
		if fe.in_bounds(p) and not fe.fire.has(p) and (bool(kc.get("fly", false)) or not fe.terrain(p) in ["d"]):
			return p
	return home

func kcfg(k: String) -> Dictionary:
	return _cfg.get("kinds", {}).get(k, {})

# 每回合（FireEscape._end_round 火延燒、煙更新之後）
func step(fe) -> void:
	var picked := {} # 同一群挑同一邊
	var eta: Dictionary = {}
	for a in animals:
		if a["gone"]:
			continue
		var kc: Dictionary = kcfg(str(a["kind"]))
		var fly: bool = bool(kc.get("fly", false))
		# 被火燒到（飛的不會）：不見
		if not fly and fe.burning(a["pos"]):
			a["gone"] = true
			continue
		if not a["fleeing"]:
			if not _notices(fe, a, kc):
				continue
			a["fleeing"] = true
			var g: int = int(a["group"])
			if not picked.has(g):
				if eta.is_empty():
					eta = FireInstinct.fire_eta(fe)
				picked[g] = _pick_side(fe, kc, eta)
			a["target"] = picked[g]
		_move(fe, a, kc)
	_report(fe)

func _notices(fe, a: Dictionary, kc: Dictionary) -> bool:
	if fe.rounds >= int(kc.get("from_round", 0)) and bool(kc.get("fly", false)):
		return true
	var p: Vector2i = a["pos"]
	if fe.smoke_at(p) >= int(kc.get("notice_smoke", 1)):
		return true
	var r: int = int(kc.get("notice", 6))
	for y in range(p.y - r, p.y + r + 1):
		for x in range(p.x - r, p.x + r + 1):
			if fe.burning(Vector2i(x, y)):
				return true
	return false

# 往哪一邊逃：火最晚燒到的邊（沒有在燒、不是上風）照 safe_pick 的機率，其他時候隨便一邊（慌了）
func _pick_side(fe, kc: Dictionary, eta: Dictionary) -> String:
	var best := ""
	var bt := -1.0
	var sides: Array = []
	for s in fe.SIDES:
		if fe.edges_burning.has(s) or s == fe.upwind_side():
			continue
		sides.append(s)
		var tmin := 999.0
		for p in _edge_cells(fe, s):
			tmin = minf(tmin, float(eta.get(p, 999.0)))
		if tmin > bt:
			bt = tmin
			best = s
	if sides.is_empty():
		return fe.downwind_side()
	if rng_a.randf() < float(kc.get("safe_pick", 0.7)):
		return best
	return sides[rng_a.randi_range(0, sides.size() - 1)]

func _edge_cells(fe, s: String) -> Array:
	var out: Array = []
	var n: int = fe.height if s in ["w", "e"] else fe.width
	for i in range(0, n, 2):
		match s:
			"w": out.append(Vector2i(0, i))
			"e": out.append(Vector2i(fe.width - 1, i))
			"n": out.append(Vector2i(i, 0))
			_: out.append(Vector2i(i, fe.height - 1))
	return out

func _dist_to_side(fe, p: Vector2i, s: String) -> int:
	return {"w": p.x, "e": fe.width - 1 - p.x, "n": p.y, "s": fe.height - 1 - p.y}[s]

# 往目標那一邊走 move 格：每一步挑離那一邊最近、沒在燒的相鄰格（有一點亂，wander 的機率走斜的或側邊）；在邊上再走一步就離開
func _move(fe, a: Dictionary, kc: Dictionary) -> void:
	var fly: bool = bool(kc.get("fly", false))
	var s: String = str(a["target"])
	for k in int(kc.get("move", 3)):
		var p: Vector2i = a["pos"]
		if _dist_to_side(fe, p, s) == 0:
			a["gone"] = true
			return
		var best := p
		var bd := 1e9
		for d in fe.DIRS8:
			var n: Vector2i = p + d
			if not fe.in_bounds(n):
				continue
			if not fly and (fe.burning(n) or fe.terrain(n) == "d"):
				continue
			var v: float = float(_dist_to_side(fe, n, s)) + rng_a.randf() * float(kc.get("wander", 0.6))
			if not fly:
				v += float(fe.smoke_at(n)) * 0.3
			if v < bd:
				bd = v
				best = n
		if best == p:
			return
		a["pos"] = best

# 看到逃跑的動物：每一群寫一次（第一次看到時）
func _report(fe) -> void:
	var groups := {}
	for a in animals:
		if a["gone"] or not a["fleeing"] or a["seen"]:
			continue
		var kc: Dictionary = kcfg(str(a["kind"]))
		var r: int = fe.sight_radius() * (2 if bool(kc.get("fly", false)) else 1)
		if fe.in_den or fe._cheb(a["pos"], fe.wolf_pos) > r:
			continue
		var g: int = int(a["group"])
		if not groups.has(g):
			groups[g] = {"kind": a["kind"], "side": a["target"], "n": 0}
		groups[g]["n"] += 1
	for g in groups:
		var n := 0
		for a in animals:
			if int(a["group"]) == g and not a["gone"]:
				a["seen"] = true
				n += 1
		fe.events.append({"kind": "animal", "animal": groups[g]["kind"], "side": groups[g]["side"], "n": n})

func visible_animals(fe) -> Array:
	var out: Array = []
	for a in animals:
		if a["gone"]:
			continue
		var kc: Dictionary = kcfg(str(a["kind"]))
		var r: int = fe.sight_radius() * (2 if bool(kc.get("fly", false)) else 1)
		if not fe.in_den and fe._cheb(a["pos"], fe.wolf_pos) <= r:
			out.append(a)
	return out
