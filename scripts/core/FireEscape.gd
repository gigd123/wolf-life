class_name FireEscape
extends RefCounted
# 森林大火的逃生地圖（Phase 2n，SPEC「森林大火的逃生地圖」）：邏輯，不含畫面。
# 第 1 步（2026-11-13）：燃料、風向與風力、夜裡、乾濕；火的狀態（燃燒 → 剛燒過 → 冷卻的焦土）、飛火（先落火星、之後才燒）；
# 煙（照風飄、微風時在水邊低處積聚）與視線；狼的移動與喘；每回合的燒、熱、煙的傷。
# 一回合約 10 秒、一格約 5 公尺；數值在 data/fire_escape.json，都是待驗證的假設。

const CFG_PATH := "res://data/fire_escape.json"
const DIRS8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const SIDES := {"w": Vector2i(-1, 0), "e": Vector2i(1, 0), "n": Vector2i(0, -1), "s": Vector2i(0, 1)}

var c: Dictionary = {}
var rng := RandomNumberGenerator.new() # 火（延燒、飛火、風的變化）
var rng_d := RandomNumberGenerator.new() # 狼受的傷（嗆傷）：和火分開，換打法時火的變化一樣
var width := 0
var height := 0
var grid: Array = [] # grid[y][x] = 地形字元
var fire: Dictionary = {} # 格子 → {"s": burning/hot/ash, "t": 剩幾回合, "small": 這一回合剛點燃（還不延燒）}
var embers: Dictionary = {} # 落下火星的格子 → 第幾回合燒起來
var smoke: Dictionary = {} # 格子 → 0～3
var known: Dictionary = {} # 看過的格子（被煙遮住時照樣標出地形）
var wind := Vector2(1, 0) # 風往哪個方向吹（下風）
var strength := 1 # 0 微風、1 中風、2 強風
var night := false
var dry := false
var edges_burning: Array = [] # 這幾邊連到的區域正在燒（"n"/"e"/"s"/"w"）
var warning := "normal" # 多早察覺：early／normal／late（決定狼離火多遠）
var den_cell := Vector2i(-1, -1) # 巢穴洞口（第 2 步；巢穴所在的區域才有）
var in_den := false # 鑽在巢穴裡
var den_smoke := false # 濃煙灌進了巢穴
var den_rounds := 0 # 在巢穴裡躲了幾回合
var start_down := "" # 開場時的下風邊（逃到下風的區域，火之後還會追過去：第 4 步用）
var start_up := ""

var wolf_pos := Vector2i.ZERO
var wolf: Dictionary = {}
var breath := 100.0
var breath_max := 100.0
var rounds := 0
var done := false
var result := "" # escaped／into_fire／survived／dead／timeout
var exit_side := ""
var dmg := {"burn": 0.0, "heat": 0.0, "hot": 0.0, "smoke": 0.0, "choke": 0.0}
var events: Array = []
var wind_events: Array = [] # 風的變化（畫面寫一句）

func _init() -> void:
	c = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))

# ctx：{map（地圖的列）或 hunt_map（戰術狩獵的地圖 id）, seed, wind（Vector2）, strength（0～2）, night, dry, edges_burning,
#       wolf：{perception, health, health_max}, breath_max}
func setup(ctx: Dictionary) -> void:
	var seed: int = int(ctx.get("seed", 1))
	rng.seed = seed
	rng_d.seed = seed * 7 + 3
	var rows: Array = ctx.get("map", [])
	if rows.is_empty():
		# 戰術狩獵的地圖只有 16 列：兩張疊起來（第二張上下翻）成 40×32，風從哪個方向來都有足夠的距離
		rows = _rows_from_hunt_map(str(ctx.get("hunt_map", "edge_1")), seed)
		var second: Array = _rows_from_hunt_map(str(ctx.get("hunt_map2", ctx.get("hunt_map", "edge_1"))), seed + 1)
		second.reverse()
		rows = rows + second
	grid = []
	for r in rows:
		var line: Array = []
		for ch in String(r):
			line.append(ch)
		grid.append(line)
	height = grid.size()
	width = (grid[0] as Array).size()
	wind = (ctx.get("wind", Vector2(1, 0)) as Vector2).normalized()
	strength = clampi(int(ctx.get("strength", 1)), 0, 2)
	night = bool(ctx.get("night", false))
	dry = bool(ctx.get("dry", false))
	edges_burning = ctx.get("edges_burning", [])
	wolf = (ctx.get("wolf", {"perception": 50, "health": 100, "health_max": 100}) as Dictionary).duplicate()
	breath_max = float(ctx.get("breath_max", 100.0))
	breath = breath_max
	fire = {}
	embers = {}
	known = {}
	rounds = 0
	_burn_cache_round = -1
	done = false
	result = ""
	exit_side = ""
	events = []
	wind_events = []
	for k in dmg:
		dmg[k] = 0.0
	in_den = false
	den_smoke = false
	den_rounds = 0
	den_cell = Vector2i(-1, -1)
	# 早先燒過的一塊地（真實的大火燒出來的是燒過、半燒、沒燒的鑲嵌地景）：冷卻的焦土
	if bool(ctx.get("ash_patch", rng.randf() < float(c.get("ash_patch_chance", 0.0)))):
		_carve_ash_patch()
	# 巢穴所在的區域：地圖上有洞口
	if bool(ctx.get("den", false)):
		_place_den()
	_ignite_upwind_edge()
	# 相鄰區在燒的那幾邊，火也從那裡進來；有時火已經從兩側包過來
	for s in edges_burning:
		if s != upwind_side():
			_ignite_edge(s, 1.0, 1.0)
	if bool(ctx.get("flank", rng.randf() < float(c.get("flank_chance", 0.0)))):
		for s in SIDES:
			if Vector2(SIDES[s]).dot(wind) == 0.0:
				_ignite_edge(s, 0.5, 0.8)
	warning = str(ctx.get("warning", "normal"))
	start_down = downwind_side()
	start_up = upwind_side()
	wolf_pos = ctx.get("wolf_pos", _start_cell())
	_update_smoke()
	_see()

# 早先燒過的一塊地：地圖下風的一半裡挑一點，半徑 ash_patch_radius 內的燃料格變成焦土（x）
func _carve_ash_patch() -> void:
	var rr: Array = c.get("ash_patch_radius", [2, 4])
	var rad: int = rng.randi_range(int(rr[0]), int(rr[1]))
	var center := Vector2i(rng.randi_range(4, width - 5), rng.randi_range(4, height - 5))
	for y in range(center.y - rad, center.y + rad + 1):
		for x in range(center.x - rad, center.x + rad + 1):
			var p := Vector2i(x, y)
			if in_bounds(p) and Vector2(p - center).length() <= rad + 0.3 and fuel(p) > 0.0:
				grid[y][x] = "x"

# 巢穴洞口：地圖中間一帶、離上風邊有距離的陸地（不是水），變成 n
func _place_den() -> void:
	var cands: Array = []
	var up: String = upwind_side()
	for y in range(3, height - 3):
		for x in range(3, width - 3):
			var p := Vector2i(x, y)
			var d: int = {"w": x, "e": width - 1 - x, "n": y, "s": height - 1 - y}[up]
			if d >= 8 and not terrain(p) in ["w", "d"]:
				cands.append(p)
	if cands.is_empty():
		return
	den_cell = cands[rng.randi_range(0, cands.size() - 1)]
	grid[den_cell.y][den_cell.x] = "n"

# 戰術狩獵的地圖轉成火場（字元對應；空地有一點機率是闊葉林、灌木，讓燃料有變化）
func _rows_from_hunt_map(id: String, seed: int) -> Array:
	var t: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical_hunt.json"))
	var m: Dictionary = t.get("maps", {}).get(id, t["maps"].values()[0])
	var conv: Dictionary = c.get("from_hunt_map", {})
	var pick := RandomNumberGenerator.new()
	pick.seed = seed + 4242
	var out: Array = []
	for r in m["map"]:
		var line := ""
		for ch in String(r):
			var t2: String = str(conv.get(ch, "."))
			if t2 == ".":
				var roll: float = pick.randf()
				if roll < float(c.get("forest_aspen", 0.0)):
					t2 = "a"
				elif roll < float(c.get("forest_aspen", 0.0)) + float(c.get("forest_shrub", 0.0)):
					t2 = "h"
			line += t2
		out.append(line)
	return out

# --- 地形 ---

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func terrain(p: Vector2i) -> String:
	return str(grid[p.y][p.x]) if in_bounds(p) else ""

func tcfg(p: Vector2i) -> Dictionary:
	return c["terrain"].get(terrain(p), c["terrain"]["."])

func fuel(p: Vector2i) -> float:
	return float(tcfg(p).get("fuel", 0.0))

func state(p: Vector2i) -> String:
	return str(fire[p]["s"]) if fire.has(p) else ""

func burning(p: Vector2i) -> bool:
	return state(p) == "burning"

# 燃燒中的格子（每回合快取，本能算危險時用）
var _burn_cache: Array = []
var _burn_cache_round := -1
func burning_cells() -> Array:
	if _burn_cache_round != rounds:
		_burn_cache = fire.keys().filter(func(p): return str(fire[p]["s"]) == "burning")
		_burn_cache_round = rounds
	return _burn_cache

func can_burn(p: Vector2i) -> bool:
	return in_bounds(p) and fuel(p) > 0.0 and not fire.has(p)

func wcfg() -> Dictionary:
	return c["wind"][strength]

func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

# 風從哪一邊來（上風邊）
func upwind_side() -> String:
	var best := ""
	var bd := 9.0
	for s in SIDES:
		var d: float = Vector2(SIDES[s]).dot(wind)
		if d < bd:
			bd = d
			best = s
	return best

func downwind_side() -> String:
	var best := ""
	var bd := -9.0
	for s in SIDES:
		var d: float = Vector2(SIDES[s]).dot(wind)
		if d > bd:
			bd = d
			best = s
	return best

# 在地圖的哪幾邊上（角落兩邊）
func sides_of(p: Vector2i) -> Array:
	var out: Array = []
	if p.x == 0:
		out.append("w")
	if p.x == width - 1:
		out.append("e")
	if p.y == 0:
		out.append("n")
	if p.y == height - 1:
		out.append("s")
	return out

# --- 開場 ---

# 火從上風那一邊進來：那一邊的前兩排有燃料的格子點燃（第一排全部、第二排一半）
func _ignite_upwind_edge() -> void:
	_ignite_edge(upwind_side(), 1.0, 0.5)

# 某一邊燒起來：frac 從靠上風的那一頭算起燒多長、second 第二排點燃的機率
func _ignite_edge(s: String, frac: float, second: float) -> void:
	var n: int = height if s in ["w", "e"] else width
	var along := Vector2(0, 1) if s in ["w", "e"] else Vector2(1, 0)
	var from_start: bool = along.dot(wind) >= 0.0 # 靠上風的那一頭是索引小的一端
	for k in n:
		if float(k) >= frac * n:
			break
		var i: int = k if from_start else n - 1 - k
		for depth in 2:
			var p: Vector2i
			match s:
				"w": p = Vector2i(depth, i)
				"e": p = Vector2i(width - 1 - depth, i)
				"n": p = Vector2i(i, depth)
				_: p = Vector2i(i, height - 1 - depth)
			if can_burn(p) and (depth == 0 or rng.randf() < second):
				_ignite(p, false)

# 狼的起點：離上風邊 start_fire_dist 格、走得動的格子、靠近中間
func _start_cell() -> Vector2i:
	var dd: Array = c.get("start_fire_dist", {}).get(warning, [11, 15])
	var s: String = upwind_side()
	var cands: Array = []
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var p := Vector2i(x, y)
			if terrain(p) in ["d", "w", "r", "g", "l"] or fire.has(p):
				continue
			var d: int = {"w": x, "e": width - 1 - x, "n": y, "s": height - 1 - y}[s]
			if d >= int(dd[0]) and d <= int(dd[1]):
				cands.append(p)
	if cands.is_empty():
		return Vector2i(width / 2, height / 2)
	return cands[rng.randi_range(0, cands.size() - 1)]

func _ignite(p: Vector2i, small: bool) -> void:
	fire[p] = {"s": "burning", "t": int(tcfg(p).get("burn", 1)), "small": small, "born": rounds}
	embers.erase(p)

# --- 狼的行動 ---

func move_budget(mode: String) -> int:
	return int(c["move"][mode])

func can_mode(mode: String) -> bool:
	match mode:
		"sprint":
			return breath >= -float(c["move"]["breath_sprint"])
		"trot":
			return breath >= -float(c["move"]["breath_trot"])
	return true

func step_cost(p: Vector2i) -> int:
	return 1 + int(tcfg(p).get("move", 0))

# 走得到的格子：{格子: 方式}（燃燒中的格子過不去）
func reachable() -> Dictionary:
	var maxb: int = move_budget("sprint") if can_mode("sprint") else (move_budget("trot") if can_mode("trot") else move_budget("walk"))
	var dist := {wolf_pos: 0}
	var frontier: Array = [wolf_pos]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for d in DIRS8:
			var n: Vector2i = cur + d
			if not in_bounds(n) or burning(n):
				continue
			var nd: int = int(dist[cur]) + step_cost(n)
			if nd <= maxb and (not dist.has(n) or nd < int(dist[n])):
				dist[n] = nd
				frontier.append(n)
	var out := {}
	for p in dist:
		if p == wolf_pos:
			continue
		var cost: int = int(dist[p])
		out[p] = "walk" if cost <= move_budget("walk") else ("trot" if cost <= move_budget("trot") else "sprint")
	return out

func move_to(p: Vector2i) -> void:
	if done or in_den:
		return
	var r := reachable()
	if not r.has(p):
		return
	wolf_pos = p
	_spend(str(r[p]))
	_end_round()

# 原地不動（回喘）
func wait() -> void:
	if done:
		return
	breath = minf(breath_max, breath + float(c["move"]["breath_regen"]))
	_end_round()

# 巢穴：站在洞口時鑽進去（擋得住火、擋不住煙）；在裡面時衝出來（回到洞口那一格，外面的火可能已經不一樣了）
func can_enter_den() -> bool:
	return not done and not in_den and wolf_pos == den_cell

func enter_den() -> void:
	if not can_enter_den():
		return
	in_den = true
	den_rounds = 0
	events.append({"kind": "den_in"})
	_end_round()

func leave_den() -> void:
	if done or not in_den:
		return
	in_den = false
	events.append({"kind": "den_out"})
	_end_round()

# 站在地圖邊上：往那一邊離開（逃到那一邊連到的區域）
func can_exit() -> Array:
	return sides_of(wolf_pos)

func exit_to(side: String) -> void:
	if done or in_den or not can_exit().has(side):
		return
	done = true
	exit_side = side
	result = "into_fire" if edges_burning.has(side) else "escaped"
	events.append({"kind": "exit", "side": side})

func _spend(mode: String) -> void:
	breath = clampf(breath + float(c["move"]["breath_" + mode]), 0.0, breath_max)

# --- 回合結束：火、煙、傷 ---

func _end_round() -> void:
	rounds += 1
	_maybe_wind_change()
	_spread()
	_update_smoke()
	_hurt_wolf()
	_see()
	if done:
		return
	if float(wolf["health"]) <= 0.0:
		done = true
		result = "dead"
		return
	if not fire.values().any(func(f): return str(f["s"]) == "burning") and embers.is_empty():
		done = true
		result = "survived"
		return
	if rounds >= int(c.get("max_rounds", 45)):
		done = true
		result = "timeout"

func _maybe_wind_change() -> void:
	if rng.randf() >= float(c.get("wind_change_chance", 0.0)):
		return
	if rng.randf() < 0.5:
		var ns: int = clampi(strength + (1 if rng.randf() < 0.5 else -1), 0, 2)
		if ns != strength:
			strength = ns
			wind_events.append({"kind": "strength", "strength": strength, "round": rounds})
	else:
		wind = wind.rotated(PI / 4.0 * (1.0 if rng.randf() < 0.5 else -1.0)).normalized()
		wind_events.append({"kind": "dir", "round": rounds})

# 延燒：每個燃燒中的格子照燃料 × 方向（下風、側面、上風）× 夜裡、乾濕點燃旁邊的格子；強風往下風隔一格直接點燃；飛火先落火星
func _spread() -> void:
	var w: Dictionary = wcfg()
	var sp: Array = w["spread"]
	var mult: float = (float(c.get("night_mult", 1.0)) if night else 1.0) * (float(c.get("dry_mult", 1.0)) if dry else 1.0)
	var subs: int = int(w.get("substeps", 1))
	for sub in subs:
		_spread_once(w, sp, mult, subs, sub == 0)
	_age_fire()

func _spread_once(w: Dictionary, sp: Array, mult: float, subs: int, first: bool) -> void:
	var src: Array = fire.keys().filter(func(p): return str(fire[p]["s"]) == "burning" and not bool(fire[p]["small"]))
	var lit: Array = []
	for b in src:
		for d in DIRS8:
			var n: Vector2i = b + d
			if not can_burn(n) or lit.has(n):
				continue
			var a: float = Vector2(d).normalized().dot(wind)
			var f: float = float(sp[0]) if a > 0.5 else (float(sp[2]) / subs if a < -0.5 else float(sp[1]) / subs)
			if d.x != 0 and d.y != 0:
				f *= 0.7
			if rng.randf() < fuel(n) * f * mult:
				lit.append(n)
		# 強風：往下風隔一格（中間不是水）
		if float(w["jump"]) > 0.0:
			var j: Vector2i = b + Vector2i(roundi(wind.x * 2.0), roundi(wind.y * 2.0))
			var mid: Vector2i = b + Vector2i(roundi(wind.x), roundi(wind.y))
			if can_burn(j) and not terrain(mid) in ["w", "d"] and not lit.has(j) and rng.randf() < float(w["jump"]) * fuel(j) / 0.35 * mult:
				lit.append(j)
		# 飛火：針葉林、倒木燒起來時，火星落到下風幾格外（不會落在狼身上；先標出來，之後才燒）
		if first and terrain(b) in ["f", "l"] and rng.randf() < float(w["spot"]) * mult:
			var dd: Array = w["spot_dist"]
			var dist: int = rng.randi_range(int(dd[0]), int(dd[1]))
			var perp := Vector2(-wind.y, wind.x)
			var t: Vector2i = b + Vector2i(roundi(wind.x * dist + perp.x * rng.randi_range(-1, 1)), roundi(wind.y * dist + perp.y * rng.randi_range(-1, 1)))
			if can_burn(t) and t != wolf_pos and not embers.has(t):
				var ed: Array = c.get("ember_delay", [1, 2])
				embers[t] = rounds + rng.randi_range(int(ed[0]), int(ed[1]))
				events.append({"kind": "ember", "cell": t})
	for n in lit:
		_ignite(n, false)

# 燃燒 → 剛燒過 → 冷卻；火星到時間燒起來
func _age_fire() -> void:
	for p in fire.keys():
		var f2: Dictionary = fire[p]
		# 這一回合才燒起來的不算（不然只燒 1 回合的草地一點著就熄，延燒不出去）
		if int(f2.get("born", -1)) == rounds and str(f2["s"]) == "burning":
			continue
		f2["small"] = false
		f2["t"] = int(f2["t"]) - 1
		if int(f2["t"]) <= 0:
			if str(f2["s"]) == "burning":
				f2["s"] = "hot"
				f2["t"] = int(c.get("hot_rounds", 2))
			elif str(f2["s"]) == "hot":
				f2["s"] = "ash"
				f2["t"] = 9999
	# 火星到時間：燒起來（頭一回合火小，不延燒）
	for e in embers.keys():
		if int(embers[e]) <= rounds:
			if can_burn(e) and e != wolf_pos:
				_ignite(e, true)
			embers.erase(e)

# 煙：每個燃燒中的格子往外放煙（中風、強風往下風拉長；微風往四周、在水邊低處積聚），疊加後夾在 0～3
func _update_smoke() -> void:
	var w: Dictionary = wcfg()
	var acc := {}
	var L: int = int(w["smoke_len"])
	var W: int = int(w["smoke_width"])
	var perp := Vector2(-wind.y, wind.x)
	for b in fire.keys():
		if str(fire[b]["s"]) == "hot":
			_add_smoke(acc, b, 0.6)
			continue
		if str(fire[b]["s"]) != "burning":
			continue
		if strength == 0:
			for y in range(-L, L + 1):
				for x in range(-L, L + 1):
					var dd: int = maxi(absi(x), absi(y))
					_add_smoke(acc, b + Vector2i(x, y), 1.6 * (1.0 - float(dd) / float(L + 1)))
		else:
			for k in L + 1:
				for lat in range(-W, W + 1):
					var p: Vector2i = b + Vector2i(roundi(wind.x * k + perp.x * lat), roundi(wind.y * k + perp.y * lat))
					_add_smoke(acc, p, 2.0 * (1.0 - float(k) / float(L + 1)) * (1.0 - float(absi(lat)) / float(W + 1)))
	smoke = {}
	var pool: int = int(w.get("smoke_pool", 0))
	for p in acc:
		var v: float = float(acc[p])
		if pool > 0 and terrain(p) in ["w", "d"] and v > 0.3:
			v += float(pool)
		var lv: int = clampi(int(floor(v * 0.8 + 0.2)), 0, int(c.get("smoke_max", 3)))
		if lv > 0:
			smoke[p] = lv

func _add_smoke(acc: Dictionary, p: Vector2i, v: float) -> void:
	if v <= 0.0 or not in_bounds(p):
		return
	acc[p] = float(acc.get(p, 0.0)) + v

func smoke_at(p: Vector2i) -> int:
	return int(smoke.get(p, 0))

func _shelter(p: Vector2i, key: String) -> float:
	return float(c.get("shelter", {}).get(terrain(p), {}).get(key, 1.0))

# 每回合的傷：站在燃燒的格子、旁邊燃燒的熱、剛燒過的地、煙（扣喘、扣血、嗆傷）
func _hurt_wolf() -> void:
	var p := wolf_pos
	var h := 0.0
	# 在巢穴裡：火和熱進不來；火靠近或洞口有濃煙時，每回合有機率濃煙灌進來，之後每回合都像站在極濃的煙裡
	if in_den:
		den_rounds += 1
		var dc: Dictionary = c.get("den", {})
		var near_fire := false
		for b in burning_cells():
			if _cheb(b, p) <= int(dc.get("near", 4)):
				near_fire = true
				break
		if not den_smoke and (near_fire or smoke_at(p) >= 2) and rng_d.randf() < float(dc.get("smoke_chance", 0.15)):
			den_smoke = true
			events.append({"kind": "den_smoke"})
		if den_smoke:
			var lv: int = int(dc.get("smoke_level", 3))
			breath = maxf(0.0, breath - float(c["smoke_breath"][lv]))
			var sh: float = float(c["smoke_health"][lv]) * float(dc.get("smoke_mult", 1.5))
			dmg["smoke"] += sh
			h += sh
			if rng_d.randf() < float(c["choke_chance"][lv]):
				var cd: Array = c.get("choke_damage", [4, 8])
				var v0: float = float(rng_d.randi_range(int(cd[0]), int(cd[1])))
				dmg["choke"] += v0
				h += v0
				events.append({"kind": "choke"})
		else:
			breath = minf(breath_max, breath + float(c["move"]["breath_regen"]) * 0.5)
		wolf["health"] = float(wolf["health"]) - h
		return
	if burning(p):
		var v: float = float(c.get("burn_on", 30))
		dmg["burn"] += v
		h += v
		events.append({"kind": "burned"})
	var adj := 0
	for d in DIRS8:
		if burning(p + d):
			adj += 1
	if adj > 0:
		var v2: float = minf(adj * float(c.get("heat_adjacent", 3)), float(c.get("heat_max", 12))) * _shelter(p, "heat")
		dmg["heat"] += v2
		h += v2
	if state(p) == "hot":
		var v3: float = float(c.get("hot_on", 6))
		dmg["hot"] += v3
		h += v3
	var lv: int = clampi(int(floor(smoke_at(p) * _shelter(p, "smoke") + 0.01)), 0, 3)
	if lv > 0:
		breath = maxf(0.0, breath - float(c["smoke_breath"][lv]))
		var sh: float = float(c["smoke_health"][lv])
		dmg["smoke"] += sh
		h += sh
		if rng_d.randf() < float(c["choke_chance"][lv]):
			var cd: Array = c.get("choke_damage", [4, 8])
			var v4: float = float(rng_d.randi_range(int(cd[0]), int(cd[1])))
			dmg["choke"] += v4
			h += v4
			events.append({"kind": "choke"})
	elif adj == 0:
		breath = minf(breath_max, breath + float(c["move"]["breath_regen"]) * 0.5)
	wolf["health"] = float(wolf["health"]) - h

# --- 結果（第 3 步）---

# 平安／輕度燒傷／重度燒傷／死亡：照這一場累積的傷（outcome.light、outcome.heavy）
func outcome() -> String:
	if result == "dead" or float(wolf["health"]) <= 0.0:
		return "death"
	var o: Dictionary = c.get("outcome", {})
	var td: float = total_damage()
	if td >= float(o.get("heavy", 25.0)):
		return "heavy"
	if td >= float(o.get("light", 8.0)):
		return "light"
	return "safe"

# 怎麼逃的（一生回顧、試玩紀錄、第 4 步接世界用）
func summary() -> Dictionary:
	var how := "open"
	if result in ["escaped", "into_fire"]:
		how = "exit"
	elif in_den or wolf_pos == den_cell:
		how = "den"
	else:
		match terrain(wolf_pos):
			"d", "w":
				how = "water"
			"x":
				how = "ash"
			"r", "g":
				how = "rock"
		if how == "open" and state(wolf_pos) == "ash":
			how = "ash"
	var td: float = total_damage()
	var smoke_part: float = float(dmg["smoke"]) + float(dmg["choke"])
	return {"result": result, "outcome": outcome(), "how": how, "side": exit_side, "downwind": exit_side != "" and exit_side == start_down,
		"upwind": exit_side != "" and exit_side == start_up, "damage": td, "cause": "smoke" if smoke_part >= td * 0.5 and td > 0.0 else "fire",
		"den_smoke": den_smoke, "rounds": rounds, "strength": strength}

func total_damage() -> float:
	var t := 0.0
	for k in dmg:
		t += float(dmg[k])
	return t

# --- 視線 ---

func sight_radius() -> int:
	if in_den:
		return 0
	var lv: int = smoke_at(wolf_pos)
	var base: int = int(c["sight"][lv])
	return base + maxi(0, roundi((float(wolf.get("perception", 50)) - 50.0) * float(c.get("sight_per_perception", 0.1)) / 1.0))

func visible(p: Vector2i) -> bool:
	return _cheb(p, wolf_pos) <= sight_radius()

func _see() -> void:
	var r: int = sight_radius()
	for y in range(maxi(0, wolf_pos.y - r), mini(height, wolf_pos.y + r + 1)):
		for x in range(maxi(0, wolf_pos.x - r), mini(width, wolf_pos.x + r + 1)):
			known[Vector2i(x, y)] = true
