class_name RiverFishing
extends RefCounted

# 鮭魚洄流的河岸模式（Phase 2h 第 2 步，SPEC「Phase 2h」）：鮭魚溪的戰術地圖上，狼移動、站上淺灘撲魚、邊捕邊吃、隨時離開。
# 只管這一場的局面；時間、體力、飽食度由 GameState.finish_salmon_fishing 結算（同戰術狩獵）。
# 地圖、地形的移動代價沿用戰術狩獵（data/tactical_hunt.json 的 maps（family salmon）與 move.terrain_extra）；數值在 balance.salmon.river。
# 灰熊（第 3 步，balance.salmon.river.bears）：大熊佔魚最多的淺灘、小熊挑離大熊遠的空位；你太靠近就威嚇，下一回合還在就把你趕開；
# 可以硬撐不走（結束這一場，GameState 接成灰熊遭遇）；熊會後到、會離開，偶爾在岸邊丟下吃剩的魚。

const TUNING_PATH := "res://data/tactical_hunt.json"
const DIRS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

var t: Dictionary = {}
var cfg: Dictionary = {}
var rng := RandomNumberGenerator.new()
var map_id: String = ""
var grid: Array = []
var fish: Array = []
var width: int = 0
var height: int = 0
var stage: String = "peak"
var clue: String = "" # 這一次看到的線索（灰熊多不多，第 3 步）
var wolf_pos := Vector2i.ZERO
var hunger: float = 0.0 # 現在的飽食度（開場帶進來，邊捕邊吃）
var hunger_max: float = 150.0
var overfed_at: float = 120.0
var rounds: int = 0
var caught: int = 0
var attempts: int = 0
var eaten: float = 0.0
var stamina_spent: float = 0.0
var done: bool = false
var result: String = "" # "left" 自己離開、"full" 吃不下了也算離開、"timeout" 待太久、"stand" 硬撐不走（變成灰熊遭遇）
var bears: Array = [] # [{pos, big, target, fishing, warned}]
var leftovers: Array = [] # 熊吃剩的魚所在的格子
var warns: int = 0 # 被威嚇幾次
var pushes: int = 0 # 被趕開幾次
var scraps: int = 0 # 撿到幾條熊吃剩的魚
var events: Array = []

func _init() -> void:
	t = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))

# ctx：{stage, seed, hunger, hunger_max, overfed_at, cfg（balance.salmon.river）, map（可省略：地圖 id）}
func setup(ctx: Dictionary) -> void:
	cfg = (ctx.get("cfg", {}) as Dictionary).duplicate(true) # 複製：這一場的調整不影響共用的資料
	rng.seed = int(ctx.get("seed", 1))
	stage = str(ctx.get("stage", "peak"))
	clue = str(ctx.get("clue", ""))
	hunger = float(ctx.get("hunger", 60.0))
	hunger_max = float(ctx.get("hunger_max", 150.0))
	overfed_at = float(ctx.get("overfed_at", 120.0))
	var ids: Array = (t.get("maps", {}) as Dictionary).keys().filter(func(k): return str(t["maps"][k].get("family", "")) == "salmon")
	ids.sort()
	map_id = str(ctx.get("map", ids[rng.randi_range(0, ids.size() - 1)]))
	grid = (t["maps"][map_id]["map"] as Array).duplicate()
	fish = (t["maps"][map_id]["fish"] as Array).duplicate()
	height = grid.size()
	width = String(grid[0]).length()
	rounds = 0
	caught = 0
	attempts = 0
	eaten = 0.0
	stamina_spent = 0.0
	done = false
	result = ""
	events = []
	bears = []
	leftovers = []
	warns = 0
	pushes = 0
	scraps = 0
	_spawn_start_bears()
	wolf_pos = _start_cell()

# 開場的位置：離水 1～2 格的岸邊（不在淺灘上）
func _start_cell() -> Vector2i:
	var cands: Array = []
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if terrain(c) != "." or _bear_threat_dist(c) <= 1:
				continue
			for d in DIRS:
				var n: Vector2i = c + d
				if in_bounds(n) and terrain(n) in ["s", "d"]:
					cands.append(c)
					break
	if cands.is_empty():
		return Vector2i(width / 2, 2)
	return cands[rng.randi_range(0, cands.size() - 1)]

# --- 地形 ---

func terrain(c: Vector2i) -> String:
	return String(grid[c.y])[c.x]

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

# 這一格的魚量：0 沒有、1 差、2 普通、3 好（只在淺灘上）
func fish_at(c: Vector2i) -> int:
	if not in_bounds(c):
		return 0
	var f: String = String(fish[c.y])[c.x]
	return int(f) if f.is_valid_int() else 0

func step_cost(from: Vector2i, to: Vector2i) -> float:
	var d := to - from
	var base: float = float(t["move"]["diag_cost"]) if d.x != 0 and d.y != 0 else 1.0
	return base + float(t["move"]["terrain_extra"].get(terrain(to), 0.0))

func overfed() -> bool:
	return hunger >= overfed_at

func move_range() -> float:
	return float(cfg.get("move_range", 4.0)) - (float(cfg.get("gorged_move_less", 1.0)) if overfed() else 0.0)

# 這一回合走得到的格子：{cell: 花費}；相鄰的一格一定走得到
func reachable() -> Dictionary:
	var out := {}
	if done:
		return out
	var best := {wolf_pos: 0.0}
	var frontier: Array = [wolf_pos]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		for d in DIRS:
			var n: Vector2i = c + d
			if not in_bounds(n) or bear_at(n) >= 0:
				continue
			var cost: float = float(best[c]) + step_cost(c, n)
			if cost <= move_range() + 0.001 and cost < float(best.get(n, INF)):
				best[n] = cost
				frontier.append(n)
	for c in best.keys():
		if c != wolf_pos:
			out[c] = best[c]
	for d in DIRS:
		var n: Vector2i = wolf_pos + d
		if in_bounds(n) and not out.has(n) and bear_at(n) < 0:
			out[n] = step_cost(wolf_pos, n)
	return out

# --- 行動 ---

func move_to(c: Vector2i) -> void:
	if done or not reachable().has(c):
		return
	wolf_pos = c
	_eat_leftover()
	_end_round()

# 撲魚的成功率（站的這一格）；不在淺灘或吃不下時是 0
func fish_chance() -> float:
	var q := fish_at(wolf_pos)
	if q <= 0 or terrain(wolf_pos) != "s" or hunger >= hunger_max or threatened():
		return 0.0
	return float(cfg.get("catch", {}).get(str(q), 0.0)) * float(cfg.get("stage_mult", {}).get(stage, 1.0))

func can_fish() -> bool:
	return not done and fish_chance() > 0.0

func fish_once() -> void:
	if not can_fish():
		return
	attempts += 1
	stamina_spent += float(cfg.get("fish_stamina", 1.0))
	if rng.randf() < fish_chance():
		caught += 1
		var gain: float = minf(float(cfg.get("fish_value", 5)), hunger_max - hunger)
		var was_overfed := overfed()
		hunger += gain
		eaten += gain
		events.append(_tx("river.catch").replace("{n}", str(roundi(gain))))
		if hunger >= hunger_max:
			events.append(_tx("river.full"))
		elif overfed() and not was_overfed:
			events.append(_tx("river.gorged"))
	else:
		events.append(_tx("river.miss"))
	_end_round()

# 原地待一回合（不撲魚）
func wait() -> void:
	if not done:
		_end_round()

func leave() -> void:
	if done:
		return
	done = true
	result = "full" if hunger >= hunger_max else "left"

# 硬撐不走：被威嚇時才能選；這一場結束，GameState 接成灰熊遭遇
func stand_ground() -> void:
	if done or not threatened():
		return
	done = true
	result = "stand"
	events.append(_tx("river.bear.stand"))

func _end_round() -> void:
	_bears_turn()
	rounds += 1
	if rounds >= int(cfg.get("max_rounds", 160)):
		events.append(_tx("river.timeout"))
		done = true
		result = "timeout"

# --- 灰熊 ---

func _bc() -> Dictionary:
	return cfg.get("bears", {})

func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func bear_at(c: Vector2i) -> int:
	for i in bears.size():
		if bears[i]["pos"] == c:
			return i
	return -1

func radius(i: int) -> int:
	return int(_bc().get("radius", {}).get("big" if bool(bears[i]["big"]) else "small", 1))

# 某一格離最近的熊的「威嚇範圍外幾格」：≤ 0 表示在某頭熊的威嚇範圍內
func _bear_threat_dist(c: Vector2i) -> int:
	var best := 99
	for i in bears.size():
		best = mini(best, _cheb(c, bears[i]["pos"]) - radius(i))
	return best

# 有熊在威嚇你（你在牠範圍內、牠已經警告過）：這時不能撲魚，可以硬撐
func threatened() -> bool:
	for i in bears.size():
		if bool(bears[i]["warned"]) and _cheb(wolf_pos, bears[i]["pos"]) <= radius(i):
			return true
	return false

func _spawn_start_bears() -> void:
	var rr: Array = _bc().get("start", {}).get(stage, [0, 0])
	if clue == "bears":
		rr = _bc().get("start_clue_bears", rr)
	var n: int = rng.randi_range(int(rr[0]), int(rr[1]))
	if clue == "bear":
		n = maxi(n, 1)
	for k in n:
		var big: bool = k == 0 or rng.randf() < float(_bc().get("big_share", 0.5))
		var b := {"pos": Vector2i.ZERO, "big": big, "target": Vector2i(-1, -1), "fishing": true, "warned": false}
		bears.append(b)
		var tg := _pick_target(bears.size() - 1)
		if tg.x < 0:
			bears.pop_back()
			continue
		b["pos"] = tg
		b["target"] = tg
	# 後放的大熊可能落在先放的小熊旁邊：小熊照規則讓開（開場就排好，不用等第一回合）
	for i in bears.size():
		if bool(bears[i]["big"]):
			continue
		for j in bears.size():
			if bool(bears[j]["big"]) and _cheb(bears[i]["pos"], bears[j]["pos"]) < 3:
				var tg2 := _pick_target(i)
				if tg2.x >= 0:
					bears[i]["pos"] = tg2
					bears[i]["target"] = tg2
				break

# 熊要去的淺灘：大熊挑魚最多、離其他大熊 2 格以上；小熊挑離大熊 3 格以上；都要沒有熊佔著。同魚量挑近的
func _pick_target(i: int) -> Vector2i:
	var me: Dictionary = bears[i]
	var best := Vector2i(-1, -1)
	var best_score := -INF
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			var q := fish_at(c)
			if q <= 0:
				continue
			var ok := true
			for j in bears.size():
				if j == i:
					continue
				var other: Vector2i = bears[j]["target"] if Vector2i(bears[j]["target"]).x >= 0 else bears[j]["pos"]
				if other == c or bears[j]["pos"] == c:
					ok = false
				elif bool(bears[j]["big"]) and _cheb(other, c) < (2 if bool(me["big"]) else 3):
					ok = false
			if not ok:
				continue
			var score: float = q * 10.0 - (Vector2(c - Vector2i(me["pos"])).length() * 0.1 if Vector2i(me["pos"]) != Vector2i.ZERO else rng.randf())
			if score > best_score:
				best_score = score
				best = c
	return best

func _bears_turn() -> void:
	var bc := _bc()
	# 後到的熊：從地圖左右兩端的岸邊走進來
	if bears.size() < int(bc.get("max", 4)) and rng.randf() < float(bc.get("arrive", {}).get(stage, 0.0)):
		var big: bool = rng.randf() < float(bc.get("big_share", 0.5))
		var edge_x: int = 0 if rng.randf() < 0.5 else width - 1
		var entry := Vector2i(edge_x, height / 2)
		for y in height:
			var c := Vector2i(edge_x, y)
			if terrain(c) == "." and bear_at(c) < 0 and c != wolf_pos and absi(y - height / 2) < absi(entry.y - height / 2) + (0 if terrain(entry) == "." else 99):
				entry = c
		bears.append({"pos": entry, "big": big, "target": Vector2i(-1, -1), "fishing": false, "warned": false})
		bears[-1]["target"] = _pick_target(bears.size() - 1)
		if Vector2i(bears[-1]["target"]).x < 0:
			bears.pop_back()
		else:
			events.append(_tx("river.bear.arrive." + ("big" if big else "small")))
	var i := 0
	while i < bears.size():
		var b: Dictionary = bears[i]
		# 離開：捕魚的熊吃夠了，叼著魚走進樹林（有時把吃剩的丟在岸邊）
		if bool(b["fishing"]) and rng.randf() < float(bc.get("leave", 0.0)):
			if rng.randf() < float(bc.get("leave_discard", 0.0)):
				_drop_leftover(b["pos"])
			events.append(_tx("river.bear.leave"))
			bears.remove_at(i)
			continue
		# 小熊：大熊佔到附近就讓開
		if not bool(b["big"]):
			for j in bears.size():
				if j != i and bool(bears[j]["big"]) and _cheb(bears[j]["target"] if Vector2i(bears[j]["target"]).x >= 0 else bears[j]["pos"], b["target"]) < 3:
					var tg := _pick_target(i)
					if tg.x >= 0:
						b["target"] = tg
						b["fishing"] = false
					break
		if Vector2i(b["target"]).x < 0 or not bool(b["fishing"]):
			_bear_walk(i)
		elif rng.randf() < float(bc.get("discard", {}).get(stage, 0.0)):
			_drop_leftover(b["pos"])
		i += 1
	# 威嚇與趕開
	for k in bears.size():
		var b: Dictionary = bears[k]
		if _cheb(wolf_pos, b["pos"]) <= radius(k):
			if bool(b["warned"]):
				_push_wolf(k)
				b["warned"] = false
			else:
				b["warned"] = true
				warns += 1
				events.append(_tx("river.bear.warn." + ("big" if bool(b["big"]) else "small")))
		else:
			b["warned"] = false

func _bear_walk(i: int) -> void:
	var b: Dictionary = bears[i]
	if Vector2i(b["target"]).x < 0:
		b["target"] = _pick_target(i)
		if Vector2i(b["target"]).x < 0:
			return
	for step in int(_bc().get("speed", 3)):
		var pos: Vector2i = b["pos"]
		var goal: Vector2i = b["target"]
		if pos == goal:
			b["fishing"] = true
			return
		var best := pos
		for d in DIRS:
			var n: Vector2i = pos + d
			if in_bounds(n) and bear_at(n) < 0 and n != wolf_pos and _cheb(n, goal) < _cheb(best, goal):
				best = n
		if best == pos:
			return
		b["pos"] = best
	if b["pos"] == b["target"]:
		b["fishing"] = true

# 把你趕到所有熊的威嚇範圍外最近的格子（不跳過深潭以外的限制：只要走得到的地形）
func _push_wolf(k: int) -> void:
	var best := wolf_pos
	var bd := INF
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if bear_at(c) >= 0 or terrain(c) == "d" or _bear_threat_dist(c) <= 0:
				continue
			var d: float = Vector2(c - wolf_pos).length()
			if d < bd:
				bd = d
				best = c
	wolf_pos = best
	pushes += 1
	events.append(_tx("river.bear.charge." + ("big" if bool(bears[k]["big"]) else "small")))
	_eat_leftover()

func _drop_leftover(at: Vector2i) -> void:
	if leftovers.size() >= int(_bc().get("max_leftovers", 4)):
		return
	for d in DIRS:
		var c: Vector2i = at + d
		if in_bounds(c) and terrain(c) == "." and not leftovers.has(c) and bear_at(c) < 0:
			leftovers.append(c)
			events.append(_tx("river.bear.discard"))
			return

func _eat_leftover() -> void:
	var k := leftovers.find(wolf_pos)
	if k < 0 or hunger >= hunger_max:
		return
	leftovers.remove_at(k)
	var gain: float = minf(float(_bc().get("leftover_value", 8)), hunger_max - hunger)
	hunger += gain
	eaten += gain
	scraps += 1
	events.append(_tx("river.leftover").replace("{n}", str(roundi(gain))))

# 換算成遊戲時間：rounds_per_turn 個戰術回合 = 1 個遊戲回合（至少 1）
func game_turns() -> int:
	return maxi(1, int(ceil(float(rounds) / float(cfg.get("rounds_per_turn", 8)))))

func _tx(key: String) -> String:
	return TranslationServer.translate(key)
