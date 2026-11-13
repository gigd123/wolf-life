class_name FireInstinct
extends RefCounted
# 森林大火逃生地圖的「交給本能」與模擬用的打法（Phase 2n 第 1 步，2026-11-13；第 3 步再改進）。
# smart：照危險（煙、靠近火、下風處會被火追上的格子）找代價最小的路，目標是不是上風邊、沒有在燒的出口，或深水、冷卻的焦土、岩坡；
#        靠近火或在濃煙裡才衝刺，其他時候小跑；到了出口就離開，到了避難處就等。
# 爛打法（模擬對照）：downwind 往下風邊跑、nearest 往最近的邊跑、stay 原地不動、water 跑到最近的水就等（有深水就去深水）。
# den（第 2 步）：跑到巢穴洞口鑽進去，濃煙灌進來就衝出來改用 smart；沒有巢穴時同 smart。
# goal:<n/e/s/w/water> 只走某一個目標（檢查一張地圖有幾條走得通的路）。

const POLICIES := ["smart", "downwind", "nearest", "stay", "water", "den"]

# 一格的危險（加在走過去的代價上）：整張圖一次算好
#   離燃燒的格子近（多源 BFS 的距離）、在火的下風處（從每個燃燒的格子往下風走幾格）、煙、剛燒過、火星
static func danger_map(fe) -> Dictionary:
	# 同一回合、同一個位置算過就用算好的
	var key: String = "%d|%s|%d" % [fe.rounds, str(fe.wolf_pos), fe.fire.size()]
	if fe.has_meta("dmap_key") and str(fe.get_meta("dmap_key")) == key:
		return fe.get_meta("dmap")
	var res: Dictionary = _danger_map(fe)
	fe.set_meta("dmap_key", key)
	fe.set_meta("dmap", res)
	return res

static func _danger_map(fe) -> Dictionary:
	var eta_map: Dictionary = fire_eta(fe)
	var burn: Array = fe.burning_cells()
	var near := {}
	var q: Array = []
	for b in burn:
		near[b] = 0
		q.append(b)
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		var nd: int = int(near[cur]) + 1
		if nd > 3:
			continue
		for d in fe.DIRS8:
			var n: Vector2i = cur + d
			if fe.in_bounds(n) and not near.has(n):
				near[n] = nd
				q.append(n)
	var down := {}
	var L: int = 4 + fe.strength * 3
	var perp := Vector2(-fe.wind.y, fe.wind.x)
	for b in burn:
		for k in range(1, L + 1):
			for lat in [-1, 0, 1]:
				var p: Vector2i = b + Vector2i(roundi(fe.wind.x * k + perp.x * lat), roundi(fe.wind.y * k + perp.y * lat))
				down[p] = true
	var out := {}
	for y in fe.height:
		for x in fe.width:
			var p := Vector2i(x, y)
			if fe.burning(p):
				out[p] = 999.0
				continue
			var v: float = fe.smoke_at(p) * 1.5
			if fe.state(p) == "hot":
				v += 3.0
			var nr: int = int(near.get(p, 99))
			if nr <= 1:
				v += 6.0
			elif nr <= 3:
				v += 2.5
			if down.has(p):
				v += 1.0 + fe.strength
			if fe.embers.has(p):
				v += 4.0
			# 火比你先到（第 3 步）：估計火幾回合後燒到這一格，比你走到這裡快就很危險
			var arrive: float = float(fe._cheb(fe.wolf_pos, p)) / float(fe.move_budget("trot"))
			var eta: float = float(eta_map.get(p, 999.0))
			if eta < arrive + 1.0:
				v += 8.0
			elif eta < arrive + 3.0:
				v += 2.5
			out[p] = v
	return out

# 火大約幾回合後燒到每一格（第 3 步）：從燃燒中的格子出發，每走一格的時間 = 1 ÷（燃料 × 方向的倍率 × 一回合延燒幾次），不會燒的格子到不了
static func fire_eta(fe) -> Dictionary:
	var w: Dictionary = fe.wcfg()
	var sp: Array = w["spread"]
	var subs: int = int(w.get("substeps", 1))
	var eta := {}
	var open: Array = []
	for b in fe.burning_cells():
		eta[b] = 0.0
		open.append(b)
	for e in fe.embers:
		eta[e] = maxf(0.0, float(fe.embers[e]) - fe.rounds)
		open.append(e)
	# 簡單的 Dijkstra（格子數不多，桶子以 0.25 回合為單位）
	var buckets := {}
	for p in open:
		var k: int = roundi(float(eta[p]) * 4.0)
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(p)
	var keys: Array = buckets.keys()
	keys.sort()
	var ki := 0
	var maxk := 240
	var k2 := 0
	while k2 <= maxk:
		if buckets.has(k2):
			for cur in buckets[k2]:
				if roundi(float(eta[cur]) * 4.0) != k2:
					continue
				for d in fe.DIRS8:
					var n: Vector2i = cur + d
					if not fe.in_bounds(n) or fe.fuel(n) <= 0.0 or (fe.fire.has(n) and str(fe.fire[n]["s"]) != "burning"):
						continue
					var a: float = Vector2(d).normalized().dot(fe.wind)
					var fdir: float = float(sp[0]) if a > 0.5 else (float(sp[2]) / subs if a < -0.5 else float(sp[1]) / subs)
					var rate: float = fe.fuel(n) * fdir * subs * (0.7 if d.x != 0 and d.y != 0 else 1.0)
					var t: float = float(eta[cur]) + 1.0 / maxf(0.03, rate)
					if t < float(eta.get(n, 999.0)):
						eta[n] = t
						var nk: int = roundi(t * 4.0)
						if nk <= maxk:
							if not buckets.has(nk):
								buckets[nk] = []
							buckets[nk].append(n)
		k2 += 1
	return eta

static func danger(fe, p: Vector2i) -> float:
	return float(danger_map(fe).get(p, 0.0))

# 目標格子
static func goals(fe, policy: String) -> Dictionary:
	var out := {}
	var up: String = fe.upwind_side()
	var want: Array = []
	match policy:
		"smart":
			want = ["n", "e", "s", "w", "refuge"]
			want.erase(up)
		"downwind":
			want = [fe.downwind_side()]
		"water":
			want = ["water"]
		"den":
			if fe.den_cell.x >= 0:
				out[fe.den_cell] = "den"
				return out
			want = ["n", "e", "s", "w", "refuge"]
			want.erase(up)
		_:
			if policy.begins_with("goal:"):
				want = [policy.substr(5)]
	var has_deep := false
	for y in fe.height:
		for x in fe.width:
			if fe.terrain(Vector2i(x, y)) == "d":
				has_deep = true
	for s in want:
		if s in ["refuge", "water"]:
			for y in fe.height:
				for x in fe.width:
					var p := Vector2i(x, y)
					var t: String = fe.terrain(p)
					if t == "d" or (s == "water" and t == "w" and not has_deep) or (s == "refuge" and (t in ["r", "g", "x"] or fe.state(p) == "ash")):
						out[p] = s
		elif s in fe.SIDES:
			if fe.edges_burning.has(s):
				continue
			for i in (fe.height if s in ["w", "e"] else fe.width):
				var p: Vector2i
				match s:
					"w": p = Vector2i(0, i)
					"e": p = Vector2i(fe.width - 1, i)
					"n": p = Vector2i(i, 0)
					_: p = Vector2i(i, fe.height - 1)
				out[p] = s
	return out

# 從狼的位置到每一格的代價（移動 + 危險），回傳 {dist, prev}。代價以 0.5 為單位放進桶子（Dial 演算法），比每次找最小的快
static func dijkstra(fe) -> Dictionary:
	var dmap: Dictionary = danger_map(fe)
	var dist := {fe.wolf_pos: 0}
	var prev := {}
	var buckets: Array = [[fe.wolf_pos]]
	var bi := 0
	while bi < buckets.size():
		var bucket: Array = buckets[bi]
		var k := 0
		while k < bucket.size():
			var cur: Vector2i = bucket[k]
			k += 1
			if int(dist[cur]) != bi:
				continue
			for d in fe.DIRS8:
				var n: Vector2i = cur + d
				if not fe.in_bounds(n) or fe.burning(n):
					continue
				var w: int = roundi((fe.step_cost(n) * (1.4 if d.x != 0 and d.y != 0 else 1.0) + float(dmap[n])) * 2.0)
				var nd: int = bi + maxi(1, w)
				if not dist.has(n) or nd < int(dist[n]):
					dist[n] = nd
					prev[n] = cur
					while buckets.size() <= nd:
						buckets.append([])
					(buckets[nd] as Array).append(n)
		bi += 1
	return {"dist": dist, "prev": prev}

static func step(fe, policy: String) -> void:
	if fe.done:
		return
	# 在巢穴裡：躲到濃煙灌進來才衝出去（之後照 smart 逃）；其他打法一進來就出去
	if fe.in_den:
		if policy == "den" and not fe.den_smoke:
			fe.wait()
		else:
			fe.leave_den()
		return
	if policy == "den" and fe.den_smoke:
		policy = "smart"
	if policy == "stay":
		fe.wait()
		return
	if policy == "nearest":
		var best := ""
		var bd := 999
		for s in fe.SIDES:
			var d: int = {"w": fe.wolf_pos.x, "e": fe.width - 1 - fe.wolf_pos.x, "n": fe.wolf_pos.y, "s": fe.height - 1 - fe.wolf_pos.y}[s]
			if d < bd:
				bd = d
				best = s
		policy = "goal:" + best
	var g: Dictionary = goals(fe, policy)
	# 已經在目標上：出口就離開，避難處就等
	if g.has(fe.wolf_pos):
		var kind: String = str(g[fe.wolf_pos])
		if kind == "den":
			fe.enter_den()
			return
		if kind in fe.SIDES:
			fe.exit_to(kind)
		else:
			fe.wait()
		return
	var dj: Dictionary = dijkstra(fe)
	var dist: Dictionary = dj["dist"]
	var target := Vector2i(-1, -1)
	var bt := 1e9
	for p in g:
		if dist.has(p) and float(dist[p]) < bt:
			bt = float(dist[p])
			target = p
	if target.x < 0:
		fe.wait()
		return
	# 沿著路走，走到這一回合走得到的最遠一格
	var path: Array = []
	var cur: Vector2i = target
	while cur != fe.wolf_pos:
		path.push_front(cur)
		cur = dj["prev"][cur]
	var reach: Dictionary = fe.reachable()
	var urgent: bool = float(danger_map(fe).get(fe.wolf_pos, 0.0)) >= 4.0 or fe.smoke_at(fe.wolf_pos) >= 2
	var pick := Vector2i(-1, -1)
	for p in path:
		if not reach.has(p):
			break
		if str(reach[p]) == "sprint" and not urgent:
			break
		pick = p
	if pick.x < 0:
		fe.wait()
		return
	fe.move_to(pick)

static func play(fe, policy: String = "smart") -> void:
	var guard := 0
	while not fe.done and guard < 200:
		guard += 1
		step(fe, policy)
