class_name TacticalHunt
extends RefCounted

# 戰術狩獵的邏輯（原型規格 docs/proposals/tactical-hunt-prototype.md、tactical-hunt-herd.md；
# Phase 2c 接進主遊戲，2026-10-20 從 prototypes/ 搬來）。純邏輯、不碰 GameState，可以 headless 測試；
# 畫面層與模擬都只呼叫這裡的公開函式。數值在 data/tactical_hunt.json。
# 主遊戲用 setup_from_game() 開局（狼的能力、喘、體況、吃撐、年齡、晨昏、雪況），原型畫面與模擬照舊用 setup()。
#
# 一回合：狼行動（移動／觀察／撲咬／放棄）→ 鹿行動 → 更新。座標是格子（Vector2i），x 往右、y 往下。
# 風向 wind 是風吹「往」的方向：狼在上風＝氣味從狼吹向鹿。

const TUNING_PATH := "res://data/tactical_hunt.json"
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

var t: Dictionary = {}
var rng := RandomNumberGenerator.new()
var width: int
var height: int
var grid: Array = [] # grid[y] 是一列字元：. 開闊、f 密林、l 倒木
var wind := Vector2i(-1, 0)
var scenario_id: String = ""

# 狼與鹿都是清單（之後的鹿群、狼群用；2026-10-15 使用者同意）。原型只有一隻狼、一隻鹿；
# 下面的屬性是「目前這隻」（wolves[wi]、herd[di]）的捷徑，邏輯照舊寫 wolf_pos、deer_state…
var wolves: Array = [] # {pos, stats{speed, strength, skill, perception, stamina, health, health_max}, breath, breath_max, breath_used}
var herd: Array = [] # {pos, facing, state(unaware/suspicious/flee/stand), alert, flee_round, condition, condition_known, held, wounds, lost_turns, goal_index, last_cells,
	# kind(adult/fawn), mother（幼鹿的生母索引，-1 沒有）, gone（逃掉了）, defend_rounds（生母連續護幼幾回合）, separated（幼鹿和生母跑散）}
var wi: int = 0
var di: int = 0 # 目前處理的那一隻（鹿的回合裡會輪流）；平常等於 target
var target: int = 0 # 狼選定的目標（鹿群版，docs/proposals/tactical-hunt-herd.md）
var observed: int = 0 # 觀察過幾次（意圖範圍縮小）
var hold_side: String = "" # 咬住的位置（rear / side / front）
var wolf_pos: Vector2i:
	get: return wolves[wi]["pos"]
	set(v): wolves[wi]["pos"] = v
var wolf: Dictionary:
	get: return wolves[wi]["stats"]
	set(v): wolves[wi]["stats"] = v
var breath: float:
	get: return wolves[wi]["breath"]
	set(v): wolves[wi]["breath"] = v
var breath_max: float:
	get: return wolves[wi]["breath_max"]
	set(v): wolves[wi]["breath_max"] = v
var breath_used: float:
	get: return wolves[wi]["breath_used"]
	set(v): wolves[wi]["breath_used"] = v
var deer_pos: Vector2i:
	get: return herd[di]["pos"]
	set(v): herd[di]["pos"] = v
var deer_facing: Vector2i:
	get: return herd[di]["facing"]
	set(v): herd[di]["facing"] = v
var deer_state: String:
	get: return herd[di]["state"]
	set(v): herd[di]["state"] = v
var alert: float:
	get: return herd[di]["alert"]
	set(v): herd[di]["alert"] = v
var flee_round: int:
	get: return herd[di]["flee_round"]
	set(v): herd[di]["flee_round"] = v
var condition: String:
	get: return herd[di]["condition"]
	set(v): herd[di]["condition"] = v
var condition_known: bool:
	get: return herd[di]["condition_known"]
	set(v): herd[di]["condition_known"] = v
var lost_turns: int:
	get: return herd[di]["lost_turns"]
	set(v): herd[di]["lost_turns"] = v
var deer_goal_index: int:
	get: return herd[di]["goal_index"]
	set(v): herd[di]["goal_index"] = v
var deer_last_cells: Array:
	get: return herd[di]["last_cells"]
	set(v): herd[di]["last_cells"] = v
var held: bool:
	get: return herd[di]["held"]
	set(v): herd[di]["held"] = v
var wounds: int:
	get: return herd[di]["wounds"]
	set(v): herd[di]["wounds"] = v

# 結果
var rounds: int = 0
var done: bool = false
var result: String = "" # caught / escaped / lost / gave_up / timeout
var reason: String = ""
var detect_cause: String = ""
var kicks: int = 0
var events: Array = [] # 發生的事（原型直接用中文）
# 鹿群版
var caught_kind: String = "" # 獵到的是 adult 還是 fawn
var meat: int = 0
var defends: int = 0 # 生母護幼的次數
var damage_taken: float = 0.0
var charged_round: int = -1 # 這一回合已經有站定的獵物衝撞過（一回合最多一次，Phase 2f 第 3 步：整群野牛站定時不會每隻都撞）
var damage_by: Dictionary = {} # 受傷來源：prey（獵物本身踢）、mother（生母護幼）
var scattered: bool = false # 這一回合狼衝進鹿群
# 鹿群一起逃（Phase 2d 第 1 步）：逃跑中的鹿依 herd[i].group 分成小群，每一小群每回合算一個方向，
# 每隻再沿這個方向、用自己的逃跑格數跑（虛弱的、幼鹿自然掉在後面）；狼衝進來時沿衝進來的線分成兩三群。
var group_dirs := {} # 小群 -> 這回合（上回合）的方向
var group_push := {} # 小群 -> {dir: Vector2, rounds}：剛分開時往兩側推開
var group_split_age := {} # 小群 -> 分開後過了幾回合（沒分開過的不在裡面）
var next_group: int = 1
var wolf_from := Vector2i.ZERO # 狼這一回合從哪裡出發（衝進鹿群的方向）
var last_mode: String = "still" # 狼這一回合怎麼動（生母踢中的機率看這個）
var mother_hit_fawn_held: bool = false # 這一回合生母踢中了咬著幼鹿的狼
# 特殊招式（2026-10-16）：會不會前截鎖喉（原型裡由畫面的開關決定）；用了幾次
var knows_front_lock: bool = false
var front_locks: int = 0
var stats := {"stuck": 0, "toward_wolf": 0}
# 主遊戲帶進來的狀態（Phase 2c 第 1 步，setup_from_game）：age_penalty（撲咬、壓倒、咬喉的年齡減成）、
# no_sprint（吃撐不能衝刺）、alert_mult（晨昏時鹿的警覺值漲得慢）、snow_slow（深雪時鹿每回合少跑幾格）
var game_mods := {}
# 接回主遊戲用（Phase 2c 第 2 步）：每一下受到的傷害、這一場的鍛鍊（同 HuntSystem.practice 的格式，Growth.apply_practice）
var hits_taken: Array = []
var practice: Array = []

func _init() -> void:
	t = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))

# --- 開局 ---

func setup(p_scenario: String, wolf_profile: String, seed: int, stamina_mult: float = 1.0) -> void:
	rng.seed = seed
	game_mods = {}
	hits_taken = []
	practice = []
	scenario_id = p_scenario
	var sc: Dictionary = t["scenarios"][p_scenario]
	var map_src: Dictionary = t["scenarios"][sc["map_from"]] if sc.has("map_from") else sc
	grid = map_src["map"].duplicate()
	height = grid.size()
	width = String(grid[0]).length()
	wind = Vector2i(int(sc["wind"][0]), int(sc["wind"][1]))
	var wstats: Dictionary = (t["wolves"][wolf_profile] as Dictionary).duplicate()
	wstats["stamina"] = float(wstats["stamina"]) * stamina_mult
	wstats["health_max"] = 100.0
	wstats["health"] = 100.0
	var b: Dictionary = t["breath"]
	var bmax: float = clamp(float(b["base"]) + float(wstats["stamina"]) * float(b["per_stamina"]) + (float(wstats["speed"]) - 50.0) * float(b["per_speed"]),
		float(b["min"]), float(b["max"]))
	wolves = [{"pos": Vector2i(int(sc["wolf"][0]), int(sc["wolf"][1])), "stats": wstats, "breath": bmax, "breath_max": bmax, "breath_used": 0.0}]
	var list: Array = sc.get("deer_list", [{"pos": sc.get("deer", [10, 8]), "kind": "adult"}])
	herd = []
	for d in list:
		herd.append({"pos": Vector2i(int(d["pos"][0]), int(d["pos"][1])), "facing": DIRS[rng.randi_range(0, 7)], "state": "unaware", "alert": 0.0,
			"flee_round": 0, "condition": str(_weighted(t["deer"]["condition_weights"])), "condition_known": false, "held": false, "wounds": 0,
			"lost_turns": 0, "goal_index": 0, "last_cells": [], "kind": str(d.get("kind", "adult")), "mother": int(d.get("mother", -1)),
			"gone": false, "defend_rounds": 0, "separated": false, "species": str(d.get("species", "deer")), "group": 0})
	wi = 0
	di = 0
	target = 0
	caught_kind = ""
	meat = 0
	defends = 0
	damage_taken = 0.0
	charged_round = -1
	damage_by = {}
	scattered = false
	group_dirs = {}
	group_push = {}
	group_split_age = {}
	next_group = 1
	wolf_from = wolves[0]["pos"]
	last_mode = "still"
	mother_hit_fawn_held = false
	front_locks = 0
	observed = 0
	rounds = 0
	done = false
	result = ""
	reason = ""
	detect_cause = ""
	kicks = 0
	events = []
	stats = {"stuck": 0, "toward_wolf": 0}

# 主遊戲開局（Phase 2c）：ctx = {map（情境或地圖 id）, seed, wolf（{speed, skill, strength, perception, stamina, health, health_max}）,
# condition（主遊戲擲出的體況）, gorged, age_penalty, twilight, deep_snow, wind（Vector2i，可省略）}
# Phase 2d 第 2 步：species（"deer" 白尾鹿、"elk" 馬鹿）；herd = {conditions: [每隻成鹿的體況，第一隻是主遊戲遇到的那一隻], calves: 幾隻小鹿}
func setup_from_game(ctx: Dictionary) -> void:
	var scenario: String = str(ctx.get("map", "A"))
	var herd_cfg: Dictionary = ctx.get("herd", {})
	if ctx.has("family"):
		scenario = _build_game_scenario(str(ctx["family"]), bool(ctx.get("fawn", false)), int(ctx.get("seed", 1)), str(ctx.get("species", "deer")), herd_cfg)
	setup(scenario, "normal", int(ctx.get("seed", 1)))
	var w: Dictionary = ctx.get("wolf", {})
	for k in ["speed", "skill", "strength", "perception", "health", "health_max"]:
		if w.has(k):
			wolves[0]["stats"][k] = float(w[k])
	var g: Dictionary = t.get("game", {})
	# 喘的上限：照原型的公式（體力的影響比主遊戲大，校準時用的就是這個），用主遊戲現在的體力與速度；血量低於一半 × low_health_mult
	var b: Dictionary = t["breath"]
	var ws: Dictionary = wolves[0]["stats"]
	var bmax: float = float(b["base"]) + float(w.get("stamina", 80.0)) * float(b["per_stamina"]) + (float(ws["speed"]) - 50.0) * float(b["per_speed"])
	if float(ws["health"]) < float(ws["health_max"]) * 0.5:
		bmax *= float(b.get("low_health_mult", 0.8))
	bmax = clamp(bmax, float(b["min"]), float(b["max"]))
	if bool(ctx.get("gorged", false)):
		bmax *= float(g.get("gorged_breath_mult", 0.6))
		game_mods["no_sprint"] = true
	wolves[0]["breath"] = bmax
	wolves[0]["breath_max"] = bmax
	var conds: Array = herd_cfg.get("conditions", [])
	if not conds.is_empty():
		var k := 0
		for d in herd:
			if str(d.get("kind", "adult")) != "fawn" and k < conds.size():
				if str(conds[k]) in ["healthy", "average", "weak"]:
					d["condition"] = str(conds[k])
				k += 1
	elif str(ctx.get("condition", "")) in ["healthy", "average", "weak"]:
		for d in herd:
			if str(d.get("kind", "adult")) != "fawn":
				d["condition"] = str(ctx["condition"])
	if float(ctx.get("age_penalty", 0.0)) > 0.0:
		game_mods["age_penalty"] = float(ctx["age_penalty"])
	if ctx.has("season"):
		game_mods["season"] = str(ctx["season"])
	if bool(ctx.get("twilight", false)):
		game_mods["alert_mult"] = float(g.get("twilight_alert_mult", 0.85))
	if bool(ctx.get("deep_snow", false)):
		game_mods["snow_slow"] = float(g.get("deep_snow_flee_less", 1.0))
	if ctx.has("wind"):
		wind = ctx["wind"]
	elif ctx.has("wind_relation"):
		wind = wind_for(str(ctx["wind_relation"]))

# 主遊戲的相對風向 → 地圖上的風：下風（headwind，風從鹿吹向你）、上風（tailwind）、側風（crosswind）
func wind_for(relation: String) -> Vector2i:
	var v := Vector2(deer_pos - wolf_pos)
	var d := Vector2i(int(sign(v.x)) if absf(v.x) >= absf(v.y) else 0, int(sign(v.y)) if absf(v.y) > absf(v.x) else 0)
	if d == Vector2i.ZERO:
		d = Vector2i(1, 0)
	match relation:
		"headwind":
			return -d
		"tailwind":
			return d
	return Vector2i(-d.y, d.x)

# 每種地形的地圖（Phase 2c 第 4 步，data/tactical_hunt.json 的 maps）：同一族挑一張，鹿在中間一帶的開闊處，
# 狼在 game.start_dist 格外（可以在林子裡），鹿的兩個目的地在 5～9 格外的開闊處；幼鹿跟在母鹿旁邊。結果存成臨時情境 "_game"。
func _build_game_scenario(family: String, fawn: bool, seed: int, species: String = "deer", herd_cfg: Dictionary = {}) -> String:
	var pick := RandomNumberGenerator.new()
	pick.seed = seed + 99991
	var ids: Array = (t.get("maps", {}) as Dictionary).keys().filter(func(k): return str(t["maps"][k].get("family", "")) == family)
	if ids.is_empty():
		ids = (t.get("maps", {}) as Dictionary).keys()
	if ids.is_empty():
		return "A"
	var m: Dictionary = t["maps"][ids[pick.randi_range(0, ids.size() - 1)]]
	var rows: Array = m["map"]
	var open_at := func(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.y < rows.size() and c.x < String(rows[0]).length() and String(rows[c.y])[c.x] == "."
	var w: int = String(rows[0]).length()
	var h: int = rows.size()
	var deer := Vector2i(w / 2, h / 2)
	for i in 200:
		var c := Vector2i(pick.randi_range(w * 3 / 10, w * 7 / 10), pick.randi_range(3, h - 4))
		if open_at.call(c):
			deer = c
			break
	var wolf := deer - Vector2i(9, 0)
	for i in 200:
		var ang: float = pick.randf() * TAU
		var r: float = pick.randf_range(float(t.get("game", {}).get("start_dist", [8.0, 11.0])[0]), float(t.get("game", {}).get("start_dist", [8.0, 11.0])[1]))
		var c := deer + Vector2i(roundi(cos(ang) * r), roundi(sin(ang) * r * 0.6))
		if c.x >= 1 and c.y >= 1 and c.x < w - 1 and c.y < h - 1 and not String(rows[c.y])[c.x] in ["l", "w"]:
			wolf = c
			break
	var goals: Array = []
	for i in 300:
		if goals.size() >= 2:
			break
		var c := Vector2i(pick.randi_range(1, w - 2), pick.randi_range(1, h - 2))
		var d: float = Vector2(c - deer).length()
		if open_at.call(c) and d >= 5.0 and d <= 9.0:
			goals.append([c.x, c.y])
	if goals.is_empty():
		goals = [[deer.x, deer.y]]
	var sc := {"name": str(m.get("name", "")), "wind": [-1, 0], "wolf": [wolf.x, wolf.y], "goals": goals, "map": rows}
	var calf_sp: String = species + "_calf" if t.get("species", {}).has(species + "_calf") else "deer"
	# 鹿群（Phase 2d 第 2 步）：成鹿圍在中間那一隻旁邊 3 格內的開闊處，前幾隻成鹿身邊各跟一隻小鹿
	var n_adults: int = (herd_cfg.get("conditions", []) as Array).size()
	if n_adults >= 2:
		var taken := {deer: true}
		var list: Array = [{"pos": [deer.x, deer.y], "kind": "adult", "species": species}]
		for r in [1, 2, 3]:
			for i in 40:
				if list.size() >= n_adults:
					break
				var c := deer + Vector2i(pick.randi_range(-r, r), pick.randi_range(-r, r))
				if open_at.call(c) and not taken.has(c) and c != wolf:
					taken[c] = true
					list.append({"pos": [c.x, c.y], "kind": "adult", "species": species})
		var adults: int = list.size()
		for k in mini(int(herd_cfg.get("calves", 0)), adults):
			var mp := Vector2i(int(list[k]["pos"][0]), int(list[k]["pos"][1]))
			# 先找母親旁邊一格；旁邊都被同伴或水佔住時往外找到 3 格（Phase 2f：河邊的野牛群曾經放不下小牛）
			var placed := false
			for r in [1, 2, 3]:
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if placed or maxi(absi(dx), absi(dy)) != r:
							continue
						var c: Vector2i = mp + Vector2i(dx, dy)
						if open_at.call(c) and not taken.has(c) and c != wolf:
							taken[c] = true
							list.append({"pos": [c.x, c.y], "kind": "fawn", "mother": k, "species": calf_sp})
							placed = true
				if placed:
					break
		sc["deer_list"] = list
	elif fawn:
		var f := deer + Vector2i(1, 1)
		for d in DIRS:
			if open_at.call(deer + d):
				f = deer + d
				break
		sc["deer_list"] = [{"pos": [deer.x, deer.y], "kind": "adult", "species": species}, {"pos": [f.x, f.y], "kind": "fawn", "mother": 0, "species": calf_sp}]
	else:
		sc["deer_list"] = [{"pos": [deer.x, deer.y], "kind": "adult", "species": species}]
	t["scenarios"]["_game"] = sc
	return "_game"

# 文字一律用翻譯鍵（Phase 2c 第 4 步）
static func _tx(key: String) -> String:
	return TranslationServer.translate(key)

func _age_factor(factors: Array, hold: bool = false) -> float:
	var a: float = float(game_mods.get("age_penalty", 0.0))
	# 年齡減成扣在哪裡：age_scope = "pounce" 時咬住後（壓倒、咬喉）不扣（力量、技巧本身已經隨年齡下降）
	if hold and str(game_mods.get("age_scope", t.get("game", {}).get("age_scope", "all"))) == "pounce":
		a = 0.0
	if a > 0.0:
		factors.append([_tx("tactical.factor.old_age"), -a])
	# 交給本能（Phase 2c 第 3 步）：出手比較莽撞
	var ip: float = float(game_mods.get("instinct_penalty", 0.0))
	if ip > 0.0:
		factors.append([_tx("tactical.factor.instinct"), -ip])
	return -a - ip

# --- 鹿群（鹿群版） ---

# 物種的設定（tuning.json species；沒寫的物種是白尾鹿，回傳空的）
func sp(i: int = -1) -> Dictionary:
	return t.get("species", {}).get(str(herd[di if i < 0 else i].get("species", "deer")), {})

func is_fawn(i: int = -1) -> bool:
	return str(herd[di if i < 0 else i].get("kind", "adult")) == "fawn"

# 還在場上的鹿（沒逃掉）
func active_deer() -> Array:
	var out: Array = []
	for i in herd.size():
		if not bool(herd[i].get("gone", false)):
			out.append(i)
	return out

# 鹿佔的格子（狼不能走進去）；except 那一隻不算
func deer_cells(except: int = -1) -> Dictionary:
	var out := {}
	for i in active_deer():
		if i != except:
			out[herd[i]["pos"]] = true
	return out

# 這隻母鹿的幼鹿（沒有就 -1）
# 小牛旁邊 d 格內有沒有還在場上的成牛
func _guarded(i: int, d: float) -> bool:
	for j in herd.size():
		if j != i and not is_fawn(j) and not bool(herd[j]["gone"]) and dist(herd[j]["pos"], herd[i]["pos"]) <= d:
			return true
	return false

func fawn_of(i: int) -> int:
	for j in herd.size():
		if int(herd[j].get("mother", -1)) == i and not bool(herd[j].get("gone", false)):
			return j
	return -1

# 紀錄裡怎麼稱呼這一隻：只有一隻鹿時「牠」，鹿群裡「母鹿」「幼鹿」
func label(i: int = -1) -> String:
	var k: int = di if i < 0 else i
	if herd.size() <= 1:
		return _tx("tactical.label.it")
	if is_fawn(k):
		return _tx(str(sp(k).get("name_key", "tactical.label.fawn")))
	return _tx(str(sp(k).get("name_key", "tactical.label.doe")))

func set_target(i: int) -> void:
	if i >= 0 and i < herd.size() and not bool(herd[i]["gone"]) and not held:
		target = i
		di = i

# 目標逃掉了：換成最近的、還在場上的那一隻
func _retarget() -> void:
	var best := -1
	var bd := INF
	for i in active_deer():
		var d: float = dist(herd[i]["pos"], wolf_pos)
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		target = best
	di = target

# --- 地形與距離 ---

func terrain(c: Vector2i) -> String:
	return String(grid[c.y])[c.x]

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func step_cost(from: Vector2i, to: Vector2i) -> float:
	var d := to - from
	var base: float = float(t["move"]["diag_cost"]) if d.x != 0 and d.y != 0 else 1.0
	return base + float(t["move"]["terrain_extra"].get(terrain(to), 0.0))

# 物種的地形代價（Phase 2d 第 3 步）：species.*.terrain_cost 覆寫 move.terrain_extra（騾鹿在岩坡 r 不減速）；di 那一隻
func deer_extra(c: Vector2i) -> float:
	var tc: Dictionary = sp().get("terrain_cost", {})
	var k := terrain(c)
	return float(tc[k]) if tc.has(k) else float(t["move"]["terrain_extra"].get(k, 0.0))

# 擋路的地形（倒木、岩坡、河）對這隻鹿是不是障礙：鹿閒晃時避開、逃跑時少走（密林只是慢一點，不算）
func deer_rough(c: Vector2i) -> bool:
	return terrain(c) in ["l", "r", "w"] and deer_extra(c) > 0.0

func deer_step_cost(from: Vector2i, to: Vector2i) -> float:
	var d := to - from
	return (float(t["move"]["diag_cost"]) if d.x != 0 and d.y != 0 else 1.0) + deer_extra(to)

func dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

# 從 start 出發、花費不超過 limit 能到的格子：{cell: cost}（不能走進鹿那一格）。
func costs_from(start: Vector2i, limit: float, blocks: Dictionary = {}) -> Dictionary:
	var best := {start: 0.0}
	var open: Array = [start]
	while not open.is_empty():
		var cur: Vector2i = open.pop_front()
		for d in DIRS:
			var n: Vector2i = cur + d
			if not in_bounds(n) or blocks.has(n):
				continue
			var c: float = float(best[cur]) + step_cost(cur, n)
			if c <= limit + 0.001 and (not best.has(n) or c < float(best[n])):
				best[n] = c
				open.append(n)
	return best

# --- 狼的行動 ---

func sprint_range() -> float:
	for pair in t["move"]["sprint_by_speed"]:
		if float(wolf["speed"]) < float(pair[0]):
			return float(pair[1])
	return 4.0

func trot_range() -> float:
	return float(t["move"]["trot_range_slow"]) if float(wolf["speed"]) < float(t["move"]["trot_slow_speed"]) else float(t["move"]["trot_range"])

func max_move() -> float:
	var m: Dictionary = t["move"]
	if breath >= -float(m["breath_sprint"]) and not bool(game_mods.get("no_sprint", false)):
		return sprint_range()
	if breath >= -float(m["breath_trot"]):
		return trot_range()
	# 喘不夠時還能小跑，但少一格、不扣喘也不回喘（小跑是狼的耐力步伐；2026-10-16 使用者選 A）
	return max(float(m["creep_range"]), trot_range() - float(m.get("tired_trot_less", 1.0)))

# 喘不夠小跑：這時的小跑不扣喘
func tired() -> bool:
	return breath < -float(t["move"]["breath_trot"])

# 依花費決定方式：潛行（≤1）、小跑、衝刺。
func mode_for_cost(cost: float) -> String:
	if cost <= float(t["move"]["creep_range"]) + 0.001:
		return "creep"
	if cost <= trot_range() + 0.001:
		return "trot"
	return "sprint"

# 畫面用：能到的格子與方式 {cell: "creep"|"trot"|"sprint"}
func reachable() -> Dictionary:
	var out := {}
	if held:
		return out
	var blocks := deer_cells()
	var costs := costs_from(wolf_pos, max_move(), blocks)
	for c in costs.keys():
		if c != wolf_pos:
			out[c] = mode_for_cost(float(costs[c]))
	# 潛行一定能走一格（密林、倒木裡也能慢慢潛行；原本密林一格花 2，潛行走不動）
	for d in DIRS:
		var n: Vector2i = wolf_pos + d
		if in_bounds(n) and not blocks.has(n):
			out[n] = "creep" # 相鄰的一格永遠算潛行
	return out

func move_to(cell: Vector2i) -> void:
	if done:
		return
	var r := reachable()
	if not r.has(cell):
		return
	var mode: String = r[cell]
	wolf_from = wolf_pos
	wolf_pos = cell
	_spend("breath_" + mode)
	if mode == "sprint":
		_practice("speed", true)
	_end_wolf_turn(mode)

# 鍛鍊：repeat = 這一場同一項能力練過幾次（Growth 的遞減）
func _practice(stat: String, success: bool, kind: String = "action") -> void:
	var n: int = practice.filter(func(p): return str(p["stat"]) == stat).size()
	practice.append({"stat": stat, "success": success, "repeat": n, "kind": kind})

func observe() -> void:
	if done:
		return
	_spend("breath_observe")
	condition_known = true
	observed += 1
	events.append(_tx("tactical.observe").replace("{condition}", _tx("tactical.condition." + condition)))
	_mark_weakest()
	_end_wolf_turn("still")

# 鹿群（成鹿 2 隻以上）：觀察時看出群裡最弱的那一隻（Phase 2d 第 2 步；同主遊戲「觀察鹿群，找出跑得慢的」）。
func _mark_weakest() -> void:
	var adults: Array = active_deer().filter(func(i): return not is_fawn(i))
	if adults.size() < 2:
		return
	# 一次只看得清楚幾隻（game.herd_observe_sample：目標＋其他隨機幾隻；0 = 整群都看得到）
	var sample: int = int(t.get("game", {}).get("herd_observe_sample", 0))
	if sample > 0 and adults.size() > sample:
		var others: Array = adults.filter(func(i): return i != target)
		var seen: Array = [target] if not is_fawn(target) else []
		while seen.size() < sample and not others.is_empty():
			seen.append(others.pop_at(rng.randi_range(0, others.size() - 1)))
		adults = seen
	var rank := {"weak": 0, "average": 1, "healthy": 2}
	var best := -1
	for i in adults:
		if best < 0 or int(rank.get(str(herd[i]["condition"]), 2)) < int(rank.get(str(herd[best]["condition"]), 2)):
			best = i
	for i in herd.size():
		herd[i]["weakest"] = false
	if str(herd[best]["condition"]) == "healthy":
		events.append(_tx("tactical.herd.all_healthy"))
		return
	herd[best]["weakest"] = true
	herd[best]["condition_known"] = true
	events.append(_tx("tactical.herd.weakest").replace("{animal}", label(best)))

func give_up() -> void:
	if done:
		return
	_finish("gave_up", _tx("tactical.gave_up"))

func _spend(key: String) -> void:
	if key == "breath_trot" and tired():
		return # 累了的小跑：不扣喘也不回喘
	var v: float = float(t["move"][key])
	if v < 0.0:
		breath_used += -v
	breath = clamp(breath + v, 0.0, breath_max)

# 撲咬：移動到鹿旁邊的一格、同一回合撲上去（追上就撲）。回傳 {格子: 撲咬資訊}；已經相鄰時原地撲（mode "still"）。
# 鹿還沒在逃時，用小跑或衝刺衝過去撲，牠會先驚覺（rush 扣命中）；潛行或原地撲沒有這個扣分。
func pounce_targets() -> Dictionary:
	var out := {}
	if done or held:
		return out
	var need: float = -float(t["move"]["breath_pounce"])
	var cells := {}
	if _cheb(wolf_pos, deer_pos) <= 1:
		cells[wolf_pos] = "still"
	var reach := reachable()
	for c in reach.keys():
		if _cheb(c, deer_pos) <= 1:
			var mode: String = reach[c]
			var cost: float = max(0.0, -float(t["move"]["breath_" + mode]))
			if breath >= cost + need:
				cells[c] = mode
	if breath < need:
		return out
	var keep := wolf_pos
	for c in cells.keys():
		wolf_pos = c
		var info := pounce_chance(str(cells[c]))
		info["mode"] = cells[c]
		out[c] = info
	wolf_pos = keep
	return out

func can_pounce() -> bool:
	return not pounce_targets().is_empty()

func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

# 狼在鹿的哪一側（依鹿面向的方向）：front / side / rear
func angle_side() -> String:
	var to_wolf := Vector2(wolf_pos - deer_pos).normalized()
	var face := Vector2(deer_facing).normalized()
	var c: float = to_wolf.dot(face)
	if c > 0.5:
		return "front"
	if c < -0.5:
		return "rear"
	return "side"

func deer_fatigue() -> float:
	if deer_state != "flee":
		return 0.0
	return clamp(float(flee_round - 2) / _fatigue_rounds(), 0.0, 1.0)

# 體況的加減（2026-10-20 對齊 Phase 2b：健康的成鹿更難撲中、壓倒、咬喉，更容易掙脫，也更晚累；虛弱的相反）。幼鹿不套用。
func cond_mod(key: String) -> float:
	if is_fawn():
		return 0.0
	return float(t["deer"].get("condition_mods", {}).get(condition, {}).get(key, 0.0))

func _fatigue_rounds() -> float:
	var r: float = float(t["deer"].get("condition_mods", {}).get(condition, {}).get("fatigue_rounds", 3.0)) if not is_fawn() else 3.0
	return max(1.0, r)

# --- 站定（Phase 2f，SPEC「Phase 2f：會站定的大型獵物」）---
# species.*.stand：{healthy/average/weak 站定機率, season_mult, break（每回合改成逃跑）, startle（突然逼近、退開時加）,
#   ignore_dist（退到這麼遠兩回合，牠不理你走開）, charge（正面 2 格內衝撞）, charge_damage, kick_mult}；
# species.*.stand_mods[體況]：站定（或站定時被咬住）時撲咬、壓倒、咬喉的加減（照生態，健康的幾乎打不下來）

func _stands() -> bool:
	return deer_state == "stand" and sp().has("stand")

func _roll_stand(cause: String) -> bool:
	var st: Dictionary = sp().get("stand", {})
	if st.is_empty() or is_fawn() or held or cause == "missed":
		return false
	var chance: float = float(st.get(condition, 0.0)) * float(st.get("season_mult", {}).get(str(game_mods.get("season", "")), 1.0))
	if rng.randf() >= chance:
		return false
	deer_state = "stand"
	herd[di]["stand_rounds"] = 0
	herd[di]["far_rounds"] = 0
	herd[di]["last_wolf_dist"] = dist(deer_pos, wolf_pos)
	if detect_cause == "":
		detect_cause = cause
	events.append(_tx("tactical.stand.start").replace("{animal}", label()))
	return true

# 站定的這一回合（di 那一隻）：狼退得夠遠就走開；可能改成逃跑；轉身面向你（最多 45°）；你在正面 2 格內可能衝撞
func _deer_stand() -> void:
	var st: Dictionary = sp().get("stand", {})
	var h: Dictionary = herd[di]
	h["stand_rounds"] = int(h.get("stand_rounds", 0)) + 1
	var d: float = dist(deer_pos, wolf_pos)
	if d >= float(st.get("ignore_dist", 8.0)):
		h["far_rounds"] = int(h.get("far_rounds", 0)) + 1
		if int(h["far_rounds"]) >= 2 and di == target:
			_finish("gave_up", _tx("tactical.stand.ignored").replace("{animal}", label()))
			return
	else:
		h["far_rounds"] = 0
	var p: float = float(st.get("break", {}).get(condition, 0.05))
	var prev: float = float(h.get("last_wolf_dist", d))
	if (last_mode in ["trot", "sprint"] and d <= 2.0) or d - prev >= 2.0:
		p += float(st.get("startle", 0.0))
	h["last_wolf_dist"] = d
	if rng.randf() < p:
		deer_state = "flee"
		flee_round = 0
		events.append(_tx("tactical.stand.bolt").replace("{animal}", label()))
		return
	_turn_toward_wolf()
	if charged_round != rounds and _cheb(deer_pos, wolf_pos) <= 2 and angle_side() == "front" and rng.randf() < float(st.get("charge", 0.0)):
		charged_round = rounds
		var cd: Array = st.get("charge_damage", [8, 16])
		var dmg: int = rng.randi_range(int(cd[0]), int(cd[1]))
		wolf["health"] = float(wolf["health"]) - dmg
		damage_taken += dmg
		hits_taken.append(dmg)
		damage_by["prey"] = float(damage_by.get("prey", 0.0)) + dmg
		kicks += 1
		events.append(_tx("tactical.stand.charge").replace("{animal}", label()).replace("{n}", str(dmg)))

# 轉身面向狼，每回合最多轉 45°（DIRS 相鄰的一格）
func _turn_toward_wolf() -> void:
	var want := _dir_toward(deer_pos, wolf_pos)
	var cur: int = DIRS.find(deer_facing)
	var goal: int = DIRS.find(want)
	if cur < 0 or goal < 0:
		deer_facing = want
		return
	var diff: int = posmod(goal - cur, 8)
	if diff == 0:
		return
	deer_facing = DIRS[posmod(cur + (1 if diff <= 4 else -1), 8)]

func _stand_factor(factors: Array, key: String) -> float:
	if not (_stands() or bool(herd[di].get("stood", false))):
		return 0.0
	var v: float = float(sp().get("stand_mods", {}).get(condition, {}).get(key, 0.0))
	if v != 0.0:
		factors.append([_tx("tactical.factor.standing"), v])
	return v

func _cond_factor(factors: Array, key: String) -> float:
	var v: float = cond_mod(key)
	if v != 0.0 and condition_known:
		factors.append([_tx("tactical.factor.cond." + condition), v])
	return v

# 撲咬命中率與因素（狼在 wolf_pos）：{"chance", "factors": [[文字, 加減]], "side", "kick"}
func pounce_chance(mode: String = "still") -> Dictionary:
	var p: Dictionary = t["pounce"]
	var side := angle_side()
	var factors: Array = []
	var v: float = float(p["base"])
	var a: float = float(p["angle"][side])
	v += a
	factors.append([_tx("tactical.factor.side." + side), a])
	var tired: float = deer_fatigue() * float(p["tired_max"])
	if tired > 0.0:
		v += tired
		factors.append([_tx("tactical.factor.tired"), tired])
	var ab: float = ((float(wolf["speed"]) + float(wolf["skill"])) * 0.5 - float(t["deer"]["speed"])) / float(p["ability_divisor"])
	v += ab
	factors.append([_tx("tactical.factor.ability"), ab])
	if terrain(deer_pos) == "l":
		v += float(p["in_logs"])
		factors.append([_tx("tactical.factor.in_logs"), float(p["in_logs"])])
	# 物種在某些地形上比較難撲（騾鹿在岩坡上，Phase 2d 第 3 步）
	var tp: float = float(sp().get("terrain_pounce", {}).get(terrain(deer_pos), 0.0))
	if tp != 0.0:
		v += tp
		factors.append([_tx("tactical.factor.terrain_" + terrain(deer_pos)), tp])
	if is_fawn():
		var fb: float = float(t["herd"]["fawn"]["pounce"])
		v += fb
		factors.append([_tx("tactical.factor.fawn"), fb])
		# 成牛擋在小牛旁邊（野牛，Phase 2f 第 3 步）：把小牛和牛群分開才好撲
		var gd: Dictionary = sp().get("guarded", {})
		if not gd.is_empty() and _guarded(di, float(gd.get("dist", 1.5))):
			v += float(gd["pounce"])
			factors.append([_tx("tactical.factor.guarded"), float(gd["pounce"])])
	if sp().has("pounce"):
		v += float(sp()["pounce"])
		factors.append([_tx(str(sp().get("name_key", ""))), float(sp()["pounce"])])
	v += _cond_factor(factors, "pounce")
	v += _stand_factor(factors, "pounce")
	v += _age_factor(factors)
	# 牠還沒發現你（沒察覺）就撲到：最好的機會
	if deer_state == "unaware" and not (mode in ["trot", "sprint"] and alert + float(alert_gain(mode)["gain"]) >= float(t["deer"]["flee_at"])):
		v += float(p["unaware"])
		factors.append([_tx("tactical.factor.unaware"), float(p["unaware"])])
	# 鹿還沒逃、你用小跑或衝刺衝過去：這一步的動靜會讓牠警覺；會讓牠跳開的話命中大降
	if deer_state != "flee" and mode in ["trot", "sprint"]:
		var bolt: bool = alert + float(alert_gain(mode)["gain"]) >= float(t["deer"]["flee_at"])
		var r: float = float(p["rush_bolt"]) if bolt else float(p["rush"])
		v -= r
		factors.append([_tx("tactical.factor.rush_bolt" if bolt else "tactical.factor.rush"), -r])
	return {"chance": clamp(v, 0.05, 0.95), "factors": factors, "side": side, "kick": kick_chance()}

func kick_chance() -> float:
	if is_fawn():
		return 0.0 # 幼鹿不會踢狼
	var side := angle_side()
	var k: Dictionary = t["pounce"]["kick"]
	var m: float = float(sp().get("kick_mult", 1.0))
	if deer_state == "stand":
		m *= float(sp().get("stand", {}).get("kick_mult", 1.0))
	if side == "rear":
		return float(k["rear"]) * m if deer_state == "flee" else 0.0
	if side == "front":
		return float(k["front"]) * m if deer_state != "flee" else 0.0
	return float(k["side"]) * m

func pounce() -> void:
	pounce_at(wolf_pos)

func pounce_at(cell: Vector2i) -> void:
	var targets := pounce_targets()
	if not targets.has(cell):
		return
	var info: Dictionary = targets[cell]
	wolf_from = wolf_pos
	if str(info["mode"]) != "still":
		wolf_pos = cell
		_spend("breath_" + str(info["mode"]))
	_spend("breath_pounce")
	last_mode = str(info["mode"])
	var side: String = info["side"]
	if rng.randf() < float(info["kick"]):
		var k: Array = sp().get("kick_damage", t["pounce"]["kick_damage"])
		var dmg: int = rng.randi_range(int(k[0]), int(k[1]))
		wolf["health"] = float(wolf["health"]) - dmg
		damage_taken += dmg
		hits_taken.append(dmg)
		damage_by["prey"] = float(damage_by.get("prey", 0.0)) + dmg
		kicks += 1
		events.append(_tx("tactical.kick.rear" if side == "rear" else "tactical.kick.hoof").replace("{n}", str(dmg)))
	var hit: bool = rng.randf() < float(info["chance"])
	_practice("skill", hit)
	if hit:
		# 咬住了：不是馬上獵到，接下來要壓倒或咬喉，牠會掙扎（2026-10-15 使用者同意的兩步）
		held = true
		hold_side = side
		if deer_state == "stand":
			herd[di]["stood"] = true # 站定時被咬住：咬住後的加減照站定（Phase 2f）
		events.append(_tx("tactical.bite." + side).replace("{animal}", label()))
		rounds += 1
		_deer_turn()
		return
	events.append(_tx("tactical.miss"))
	if deer_state != "flee" and not _stands():
		_start_flee("missed")
	if deer_state == "flee":
		flee_round = maxi(flee_round, 1) # 受驚：下一回合從衝刺開始
	rounds += 1
	_herd_alarm()
	_deer_turn()
	if not done and rounds >= int(t["max_rounds"]):
		_finish("timeout", _tx("tactical.timeout.far"))

# --- 特殊招式：前截鎖喉（2026-10-16 使用者同意先在原型試做；參考黃石的母狼 06）---
# 目標是逃跑中的成鹿，這一回合小跑或衝刺得到牠正前方相鄰的格子：衝到牠前面回身鎖喉。
# 成功直接咬死（不用壓倒、咬喉、被甩開）；失敗容易被正面撞踢，用掉很多喘，鹿繼續逃。

func front_lock_ready() -> bool:
	var fl: Dictionary = t["special"]["front_lock"]
	return knows_front_lock and float(wolf["speed"]) >= float(fl["min_speed"]) and float(wolf["skill"]) >= float(fl["min_skill"])

# {格子: {"chance", "factors", "mode"}}
func front_lock_targets() -> Dictionary:
	var out := {}
	if done or held or not front_lock_ready() or deer_state != "flee" or is_fawn():
		return out
	var fl: Dictionary = t["special"]["front_lock"]
	var reach := reachable()
	var keep := wolf_pos
	for c in reach.keys():
		var mode: String = reach[c]
		if not mode in ["trot", "sprint"] or _cheb(c, deer_pos) > 1:
			continue
		if breath < -float(t["move"]["breath_" + mode]) + float(fl["breath"]):
			continue
		wolf_pos = c
		if angle_side() == "front":
			var info := front_lock_chance()
			info["mode"] = mode
			out[c] = info
		wolf_pos = keep
	return out

func front_lock_chance() -> Dictionary:
	var fl: Dictionary = t["special"]["front_lock"]
	var factors: Array = []
	var v: float = float(fl["base"])
	var ab: float = ((float(wolf["speed"]) + float(wolf["skill"])) * 0.5 - 60.0) / float(fl["ability_divisor"])
	v += ab
	factors.append([_tx("tactical.factor.ability"), ab])
	var tired: float = deer_fatigue() * float(fl["tired"])
	if tired > 0.0:
		v += tired
		factors.append([_tx("tactical.factor.tired"), tired])
	var cb: float = float(fl["condition"].get(condition, 0.0))
	if cb != 0.0 and condition_known:
		factors.append([_tx("tactical.factor.cond." + condition), cb])
	v += cb
	return {"chance": clamp(v, 0.05, 0.9), "factors": factors}

func front_lock_at(cell: Vector2i) -> void:
	var targets := front_lock_targets()
	if not targets.has(cell):
		return
	var fl: Dictionary = t["special"]["front_lock"]
	var info: Dictionary = targets[cell]
	wolf_pos = cell
	_spend("breath_" + str(info["mode"]))
	breath = max(0.0, breath - float(fl["breath"]))
	breath_used += float(fl["breath"])
	last_mode = str(info["mode"])
	front_locks += 1
	rounds += 1
	if rng.randf() < float(info["chance"]):
		_finish("caught", _tx("tactical.lock.caught").replace("{animal}", label()))
		return
	if rng.randf() < float(fl["fail_hit"]):
		var k: Array = fl["fail_damage"]
		var dmg: int = rng.randi_range(int(k[0]), int(k[1]))
		wolf["health"] = float(wolf["health"]) - dmg
		damage_taken += dmg
		hits_taken.append(dmg)
		damage_by["prey"] = float(damage_by.get("prey", 0.0)) + dmg
		kicks += 1
		events.append(_tx("tactical.lock.hit").replace("{animal}", label()).replace("{n}", str(dmg)))
	else:
		events.append(_tx("tactical.lock.miss").replace("{animal}", label()))
	_deer_turn()
	if not done and rounds >= int(t["max_rounds"]):
		_finish("timeout", _tx("tactical.timeout.far"))

# --- 咬住之後：壓倒（力量）、咬喉（技巧，成功就咬死）、鬆口 ---

func hold_options() -> Dictionary:
	if not held or done:
		return {}
	var h: Dictionary = t["hold"]
	var fat: float = deer_fatigue_any()
	var out := {}
	var fb: Dictionary = t["herd"]["fawn"] if is_fawn() else sp().get("hold", {})
	var hams: int = int(herd[di].get("hamstrung", 0))
	var td: float = float(h["takedown_base"]) + (float(wolf["strength"]) - 50.0) / float(h["divisor"]) + fat * float(h["tired"]) \
		+ (float(h["rear"]) if hold_side == "rear" else 0.0) + wounds * float(h["per_wound"]) + float(fb.get("takedown", 0.0)) \
		+ hams * float(h["hamstring"]["takedown"])
	var tf: Array = [[_tx("tactical.factor.strength"), (float(wolf["strength"]) - 50.0) / float(h["divisor"])], [_tx("tactical.factor.tired"), fat * float(h["tired"])]]
	td += _cond_factor(tf, "takedown")
	td += _stand_factor(tf, "takedown")
	td += _age_factor(tf, true)
	if hams > 0:
		tf.append([_tx("tactical.factor.hamstrung"), hams * float(h["hamstring"]["takedown"])])
	out["takedown"] = {"chance": clamp(td, 0.05, 0.95), "breath": float(h["takedown_breath"]), "factors": tf}
	var front_b: float = float(h["front"]["throat"]) if hold_side == "front" else 0.0
	var th: float = float(h["throat_base"]) + (float(wolf["skill"]) - 50.0) / float(h["divisor"]) + fat * float(h["tired"]) + wounds * float(h["per_wound"]) \
		+ float(fb.get("throat", 0.0)) + front_b
	var thf: Array = [[_tx("tactical.factor.skill"), (float(wolf["skill"]) - 50.0) / float(h["divisor"])], [_tx("tactical.factor.tired"), fat * float(h["tired"])]]
	th += _cond_factor(thf, "throat")
	th += _stand_factor(thf, "throat")
	th += _age_factor(thf, true)
	if front_b > 0.0:
		thf.append([_tx("tactical.factor.neck"), front_b])
	out["throat"] = {"chance": clamp(th, 0.05, 0.95), "breath": float(h["throat_breath"]), "factors": thf}
	# 死咬拖住：用體重掛著不放（每個位置都能用，側面最有效）
	out["hang"] = {"chance": 1.0, "breath": float(h["hang"]["breath"]),
		"factors": [[_tx("tactical.factor.break"), float(h["hang"]["break"].get(hold_side, -0.08))]]}
	# 咬後腿：從後方咬住才有
	if hold_side == "rear" and hams < int(h["hamstring"]["max"]):
		var hm: Dictionary = h["hamstring"]
		var hc: float = float(hm["base"]) + (float(wolf["strength"]) - 50.0) / float(hm["divisor"]) + fat * float(hm["tired"]) + float(fb.get("hamstring", 0.0))
		out["hamstring"] = {"chance": clamp(hc, 0.05, 0.95), "breath": float(hm["breath"]),
			"factors": [[_tx("tactical.factor.strength"), (float(wolf["strength"]) - 50.0) / float(hm["divisor"])], [_tx("tactical.factor.tired"), fat * float(hm["tired"])]]}
	for k in out.keys():
		if breath < float(out[k]["breath"]):
			out.erase(k)
	out["release"] = {"chance": 1.0, "breath": 0.0, "factors": []}
	return out

# 牠掙脫的機率（每回合）：越累越低；咬喉失敗那一回合更容易掙脫
func break_chance(after_throat_miss: bool = false, hanging: bool = false) -> float:
	var h: Dictionary = t["hold"]
	var v: float = float(h["break_base"]) - deer_fatigue_any() * float(h["break_tired"]) + (float(h["throat_miss_break"]) if after_throat_miss else 0.0)
	if hanging:
		v += float(h["hang"]["break"].get(hold_side, -0.08)) # 死咬拖住：比較難甩開
	if is_fawn():
		v += float(t["herd"]["fawn"]["break"])
	v += float(sp().get("hold", {}).get("break", 0.0))
	v += cond_mod("break")
	if mother_hit_fawn_held:
		# 被母鹿踢得鬆口（母鹿的物種可以覆寫，駝鹿踢得更重）
		var m: int = int(herd[di].get("mother", -1))
		v += float((sp(m) if m >= 0 else {}).get("defend", {}).get("break_bonus", t["herd"]["defend"]["break_bonus"]))
	return clamp(v, 0.05, 0.95)

# 疲勞：逃跑的回合數，或咬住時掙扎的消耗（沒在逃也算）
func deer_fatigue_any() -> float:
	return clamp(float(flee_round - 2) / _fatigue_rounds() + float(herd[di].get("struggle", 0)) * 0.15, 0.0, 1.0)

func hold_action(id: String) -> void:
	var opts := hold_options()
	if not opts.has(id):
		return
	var o: Dictionary = opts[id]
	last_mode = "still"
	if id == "release":
		_let_go(_tx("tactical.release").replace("{animal}", label()))
		rounds += 1
		_deer_turn()
		return
	breath = max(0.0, breath - float(o["breath"]))
	breath_used += float(o["breath"])
	if id == "hang":
		# 死咬拖住：那一回合只花 hang 的喘（不再扣咬著的消耗），獵物掙扎得更累
		herd[di]["struggle"] = int(herd[di].get("struggle", 0)) + int(t["hold"]["hang"]["struggle"].get(hold_side, 1)) - 1
		events.append(_tx("tactical.hang").replace("{animal}", label()))
		rounds += 1
		_deer_turn(false, true)
		if not done and rounds >= int(t["max_rounds"]):
			_finish("timeout", _tx("tactical.timeout"))
		return
	if id == "hamstring":
		rounds += 1
		if rng.randf() < float(o["chance"]):
			herd[di]["hamstrung"] = int(herd[di].get("hamstrung", 0)) + 1
			wounds += int(t["hold"]["hamstring"]["slow"])
			events.append(_tx("tactical.hamstring.hit").replace("{animal}", label()))
		else:
			events.append(_tx("tactical.hamstring.miss"))
		_deer_turn()
		if not done and rounds >= int(t["max_rounds"]):
			_finish("timeout", _tx("tactical.timeout"))
		return
	var ok: bool = rng.randf() < float(o["chance"])
	_practice("strength" if id == "takedown" else "skill", ok)
	if ok:
		rounds += 1
		_practice("strength", true, "takedown")
		_finish("caught", _tx("tactical.caught." + id))
		return
	events.append(_tx("tactical.struggle." + id))
	rounds += 1
	_deer_turn(id == "throat")
	if not done and rounds >= int(t["max_rounds"]):
		_finish("timeout", _tx("tactical.timeout"))

func _let_go(text: String) -> void:
	held = false
	wounds += 1
	deer_state = "flee"
	flee_round = maxi(flee_round, 1)
	events.append(text)

# 咬住時鹿的回合：掙扎（可能踢中你），可能掙脫、帶傷逃跑
func _deer_struggle(after_throat_miss: bool, hanging: bool = false) -> void:
	herd[di]["struggle"] = int(herd[di].get("struggle", 0)) + 1
	var h: Dictionary = t["hold"]
	var kick_p: float = float(sp().get("hold", {}).get("kick", h["kick"])) * (float(h["front"]["kick_mult"]) if hold_side == "front" else 1.0)
	if not is_fawn() and rng.randf() < kick_p:
		var k: Array = sp().get("kick_damage", t["pounce"]["kick_damage"])
		var dmg: int = rng.randi_range(int(k[0]), int(k[1]))
		wolf["health"] = float(wolf["health"]) - dmg
		kicks += 1
		damage_taken += dmg
		hits_taken.append(dmg)
		damage_by["prey"] = float(damage_by.get("prey", 0.0)) + dmg
		events.append(_tx("tactical.struggle_kick").replace("{n}", str(dmg)))
	if rng.randf() < break_chance(after_throat_miss, hanging):
		_let_go(_tx("tactical.broke_free").replace("{animal}", label()))
		_deer_flee()

# --- 回合結束：警覺值、鹿行動 ---

func _end_wolf_turn(mode: String) -> void:
	rounds += 1
	last_mode = mode
	for i in active_deer():
		di = i
		if deer_state in ["unaware", "suspicious"]:
			_raise_alert(mode)
	di = target
	_herd_alarm()
	# 狼小跑或衝刺衝到鹿群旁邊：這一回合鹿群散開（幼鹿可能和生母跑散），整群沿狼衝進來的線分成兩三群
	scattered = false
	if herd.size() > 1 and mode in ["trot", "sprint"]:
		for i in active_deer():
			if _cheb(herd[i]["pos"], wolf_pos) <= int(t["herd"]["scatter_dist"]):
				scattered = true
				break
		if scattered and _split_groups():
			events.append(_tx("tactical.scatter"))
	if mode == "still":
		wolf_from = wolf_pos
	_deer_turn()
	if not done and rounds >= int(t["max_rounds"]):
		_finish("timeout", _tx("tactical.timeout.far"))

func wind_side() -> String:
	var v := Vector2(deer_pos - wolf_pos)
	if v.length() == 0.0:
		return "crosswind"
	var c: float = v.normalized().dot(Vector2(wind).normalized())
	if c > 0.5:
		return "upwind"
	if c < -0.5:
		return "downwind"
	return "crosswind"

func has_sight() -> bool:
	# 兩格之間有密林就擋住視線（端點不算）
	var a := Vector2(wolf_pos)
	var b := Vector2(deer_pos)
	var n: int = int(ceil(a.distance_to(b) * 2.0))
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		var c := Vector2i(roundi(p.x), roundi(p.y))
		if c != wolf_pos and c != deer_pos and terrain(c) == "f":
			return false
	return true

# 警覺值的增加 = 看見（距離 × 移動方式，密林擋住打折，技巧越高越不顯眼）＋ 聞到（只看風向與距離）。
func alert_gain(mode: String) -> Dictionary:
	var al: Dictionary = t["alert"]
	var d: float = dist(wolf_pos, deer_pos)
	var sight: float = _band(al["sight_by_distance"], d) * float(al["mode"][mode])
	if not has_sight():
		sight *= float(al["no_sight"])
	# 鹿群越大越警覺（鹿群版）
	if herd.size() > 1:
		var vg: Dictionary = t["herd"]["vigilance"]
		sight *= min(float(vg["max"]), 1.0 + float(vg["per_extra"]) * (active_deer().size() - 1))
	sight *= 1.0 - (float(wolf["skill"]) - 40.0) / float(al["skill_divisor"])
	var scent: float = _band(al["scent"].get(wind_side(), []), d)
	# 晨昏光線暗、鹿低頭吃草：看見你的警覺漲得慢（Phase 2c，對應 Phase 2b 的潛近 +5%）
	sight *= float(game_mods.get("alert_mult", 1.0))
	# 物種的警覺（馴鹿在開闊的苔原上看得遠，Phase 2d 第 4 步）
	sight *= float(sp().get("alert_mult", 1.0))
	return {"gain": sight + scent, "scent": scent, "noise": sight}

func _band(table: Array, d: float) -> float:
	for pair in table:
		if d <= float(pair[0]):
			return float(pair[1])
	return 0.0

func _raise_alert(mode: String) -> void:
	var a := alert_gain(mode)
	var gain: float = float(a["gain"])
	if gain <= 0.0 and deer_state == "unaware" and dist(wolf_pos, deer_pos) > float(t["alert"]["relax_beyond"]):
		alert = max(0.0, alert - float(t["alert"]["relax"]))
		return
	alert = min(100.0, alert + gain)
	if alert >= float(t["deer"]["flee_at"]):
		var cause: String = "scent" if float(a["scent"]) >= float(a["noise"]) else ("noise" if mode in ["trot", "sprint"] else "close")
		_start_flee(cause)
	elif alert >= float(t["deer"]["suspicious_at"]) and deer_state == "unaware":
		deer_state = "suspicious"
		events.append(_tx("tactical.look").replace("{animal}", label()))

func _start_flee(cause: String) -> void:
	# 會站定的大型獵物（Phase 2f）：察覺你時照體況的機率站定、不逃
	if _roll_stand(cause):
		return
	deer_state = "flee"
	flee_round = 0
	if detect_cause == "":
		detect_cause = cause
	if cause == "herd":
		return # 跟著同伴跑，紀錄寫在 _herd_alarm
	var text: String = _tx("tactical.flee." + (cause if cause in ["scent", "noise", "close", "missed"] else "other"))
	if herd.size() > 1:
		text = label() + text.substr(1) # 這幾句都以「牠」開頭
	events.append(text)

# 一隻驚逃，整群跟著驚：其他每隻 + contagion 警覺（鹿群版）
func _herd_alarm() -> void:
	if herd.size() <= 1:
		return
	var any_flee := false
	for i in active_deer():
		if str(herd[i]["state"]) in ["flee", "stand"]:
			any_flee = true
			break
	if not any_flee:
		return
	var joined := 0
	var keep := di
	for i in active_deer():
		di = i
		if deer_state in ["unaware", "suspicious"]:
			alert = min(100.0, alert + float(t["herd"]["contagion"]))
			if alert >= float(t["deer"]["flee_at"]):
				_start_flee("herd")
				joined += 1
			elif deer_state == "unaware":
				deer_state = "suspicious"
	di = keep
	if joined > 0:
		events.append(_tx("tactical.herd_runs"))

func _deer_turn(after_throat_miss: bool = false, hanging: bool = false) -> void:
	if done:
		return
	mother_hit_fawn_held = false
	_plan_groups()
	# 其他鹿先動（生母護幼要在咬住的幼鹿掙扎之前）；離狼遠的（跑在前面的）先動，後面的才不會被同伴擋住
	var order: Array = active_deer()
	order.sort_custom(func(a, b): return dist(herd[a]["pos"], wolf_pos) > dist(herd[b]["pos"], wolf_pos))
	for i in order:
		if i == target or done:
			continue
		di = i
		if not _mother_defend():
			_deer_act()
	di = target
	if done:
		return
	if bool(herd[target]["gone"]):
		_retarget()
		return
	if held:
		if not hanging:
			breath = max(0.0, breath - float(t["hold"]["hold_breath"])) # 咬著不放也很累（死咬拖住那一回合只花招式本身的喘）
		_deer_struggle(after_throat_miss, hanging)
		if not bool(herd[target]["gone"]):
			di = target
		return
	if not _mother_defend():
		_deer_act()
	if not done and bool(herd[target]["gone"]):
		_retarget()
	di = target

# 一隻鹿依狀態行動（di 那一隻）
func _deer_act() -> void:
	match deer_state:
		"unaware":
			_deer_wander()
		"stand":
			if sp().has("stand"):
				_deer_stand()
			else:
				deer_facing = _dir_toward(deer_pos, wolf_pos)
		"suspicious":
			deer_facing = _dir_toward(deer_pos, wolf_pos)
		"flee":
			_deer_flee()
	_check_lost()

# 生母護幼（鹿群版）：狼在自己的幼鹿 trigger 格內、或咬住了幼鹿，而且自己在 reach 格內，就轉身衝向狼、用前蹄踢。
# 只有生母會這樣做；最多連續 max_rounds 回合，之後放棄逃開。回傳這一回合有沒有護幼。
func _mother_defend() -> bool:
	if is_fawn() or bool(herd[di]["gone"]):
		return false
	var f: int = fawn_of(di)
	# 成群護小牛的物種（野牛，Phase 2f 第 3 步）：你盯上的是小牛時，不是牠媽媽的成牛也會擋
	if f < 0 and bool(sp(di).get("guard_calves", false)) and is_fawn(target) and not bool(herd[target]["gone"]):
		f = target
	# 有些物種的母鹿不護幼（馴鹿，Phase 2d 第 4 步）
	if f < 0 or bool(sp(di).get("no_defend", false)):
		return false
	# 物種可以覆寫護幼的數值（駝鹿的母鹿更兇，Phase 2f 第 2 步）
	var cfg: Dictionary = (t["herd"]["defend"] as Dictionary).duplicate()
	cfg.merge(sp(di).get("defend", {}), true)
	var fawn_held: bool = bool(herd[f]["held"])
	# 狼衝著幼鹿去（離幼鹿比離自己近）才算威脅；狼追的是她自己時，她照常逃
	var fawn_close: bool = dist(wolf_pos, herd[f]["pos"]) <= float(cfg["trigger"]) and dist(wolf_pos, herd[f]["pos"]) < dist(wolf_pos, deer_pos)
	var threat: bool = fawn_held or (fawn_close and str(herd[f]["state"]) != "unaware")
	if not threat:
		herd[di]["defend_rounds"] = 0
		return false
	if dist(deer_pos, wolf_pos) > float(cfg["reach"]) or int(herd[di]["defend_rounds"]) >= int(cfg["max_rounds"]):
		if int(herd[di]["defend_rounds"]) >= int(cfg["max_rounds"]) and deer_state != "flee":
			deer_state = "flee"
		return false
	herd[di]["defend_rounds"] = int(herd[di]["defend_rounds"]) + 1
	defends += 1
	deer_state = "flee" # 之後放棄時直接逃
	flee_round = maxi(flee_round, 1)
	# 衝到狼旁邊最近的空格
	var occupied := deer_cells(di)
	var best := deer_pos
	var bd := INF
	for d in DIRS:
		var n: Vector2i = wolf_pos + d
		if in_bounds(n) and not occupied.has(n):
			var dd: float = dist(n, deer_pos)
			if dd < bd:
				bd = dd
				best = n
	deer_pos = best
	deer_facing = _dir_toward(deer_pos, wolf_pos)
	var hit: float = float(cfg["base"]) + (float(cfg["still_bonus"]) if last_mode in ["still", "creep"] else 0.0) + (float(cfg["held_bonus"]) if fawn_held else 0.0)
	if rng.randf() < hit:
		var k: Array = cfg["damage"]
		var dmg: int = rng.randi_range(int(k[0]), int(k[1]))
		wolf["health"] = float(wolf["health"]) - dmg
		damage_taken += dmg
		hits_taken.append(dmg)
		damage_by["mother"] = float(damage_by.get("mother", 0.0)) + dmg
		kicks += 1
		if fawn_held:
			mother_hit_fawn_held = true
		events.append(_tx("tactical.defend.hit").replace("{n}", str(dmg)))
	else:
		events.append(_tx("tactical.defend.miss"))
	return true

func _dir_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	return Vector2i(signi(d.x), signi(d.y)) if d != Vector2i.ZERO else deer_facing

# 沒察覺時：邊吃草邊往目的地（水邊、林緣…）慢慢走，走到了換下一個。有固定的去向，伏擊才有意義（2026-10-15 使用者同意）。
func _deer_wander() -> void:
	var others := deer_cells(di)
	# 幼鹿跟在生母 1～2 格內
	if is_fawn() and int(herd[di]["mother"]) >= 0 and not bool(herd[int(herd[di]["mother"])]["gone"]):
		var mp: Vector2i = herd[int(herd[di]["mother"])]["pos"]
		if dist(deer_pos, mp) <= 2.0:
			return
		var fb := Vector2i.ZERO
		var fd := INF
		for d in DIRS:
			var n: Vector2i = deer_pos + d
			if in_bounds(n) and n != wolf_pos and not others.has(n) and not deer_rough(n) and dist(n, mp) < fd:
				fd = dist(n, mp)
				fb = d
		if fb != Vector2i.ZERO:
			deer_pos += fb
			deer_facing = fb
		return
	if rng.randf() < float(t["deer"]["graze_idle"]):
		return
	var goal: Vector2i = deer_goal()
	if goal == deer_pos or (deer_goal_index >= 0 and dist(deer_pos, goal) <= 1.0):
		deer_goal_index += 1
		goal = deer_goal()
	var best := Vector2i.ZERO
	var bd := INF
	for d in DIRS:
		var n: Vector2i = deer_pos + d
		if not in_bounds(n) or n == wolf_pos or others.has(n) or deer_rough(n):
			continue
		var dd: float = dist(n, goal) + rng.randf() * 0.8 # 一點隨機，路線不會完全筆直
		if dd < bd:
			bd = dd
			best = d
	if best == Vector2i.ZERO:
		return
	deer_pos += best
	deer_facing = best

# 目前的目的地（開局情境的 goals 依序循環）
func deer_goal() -> Vector2i:
	var goals: Array = t["scenarios"][scenario_id].get("goals", [])
	if goals.is_empty():
		return deer_pos
	var g: Array = goals[maxi(0, deer_goal_index) % goals.size()]
	return Vector2i(int(g[0]), int(g[1]))

# 逃跑的方向打分：離狼越遠越好、往場地外（逃得掉）加分、經過倒木扣分；不往狼的方向。
# lead_group ≥ 0：替那一小群算方向（di 是帶頭的那一隻）：慣性看小群上回合的方向、剛分開時往兩側推，不算凝聚力。
# 平常（每一隻自己）：鹿群裡多一項「沿著小群的方向跑」（align），所以整群大致同一方向、左右稍微偏一點。
func flee_options(lead_group: int = -1) -> Array:
	var away := Vector2(deer_pos - wolf_pos).normalized()
	var scored: Array = []
	var budget: float = _flee_budget()
	# 只往大致遠離狼的方向跑（夾角 < 約 80°）；被逼到沒有這種方向時才放寬
	var limit: float = 0.2
	var any_open := false
	for d in DIRS:
		if Vector2(d).normalized().dot(away) >= limit and not bool(_run_line(deer_pos, d, budget)["wall"]):
			any_open = true
			break
	if not any_open:
		limit = -0.2
	for d in DIRS:
		if Vector2(d).normalized().dot(away) < limit:
			continue # 不往狼的方向跑
		var sim := _run_line(deer_pos, d, budget)
		var end: Vector2i = sim["end"]
		var score: float = dist(end, wolf_pos) * 1.0 + Vector2(d).normalized().dot(away) * 3.0
		if sim["out"]:
			score += 8.0
		# 慣性：傾向沿原本的方向繼續跑（貼著邊緣時不會左右來回）
		var prev: Vector2i = deer_facing
		if lead_group >= 0 and group_dirs.has(lead_group):
			prev = group_dirs[lead_group]
		score += Vector2(d).normalized().dot(Vector2(prev).normalized()) * float(t["deer"]["momentum"])
		score -= float(sim["logs"]) * 2.5
		score -= float(sim["blocked"]) * 3.0
		# 往牠想逃去的地形跑（騾鹿往岩坡，Phase 2d 第 3 步）
		var sk: Dictionary = sp().get("seek", {})
		if not sk.is_empty():
			score += min(float(sim["seek"]), float(sk.get("max_cells", 3))) * float(sk.get("per_cell", 1.0))
			if in_bounds(sim["end"]) and terrain(sim["end"]) == str(sk["terrain"]):
				score += float(sk.get("end", 0.0))
			if group_push.has(lead_group):
				score += Vector2(d).normalized().dot(group_push[lead_group]["dir"]) * float(t["herd"]["split_push"])
		else:
			score += _cohesion_score(d)
		if float(sim["moved"]) <= 0.0:
			score -= 20.0
		scored.append({"dir": d, "score": score})
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	return scored

# 鹿群的凝聚力：往同伴的中心跑；幼鹿與生母互相靠攏（跑散了就不管）。狼衝進鹿群的那一回合減半。
func _cohesion_score(d: Vector2i) -> float:
	if herd.size() <= 1:
		return 0.0
	var hc: Dictionary = t["herd"]
	var mult: float = float(hc["scatter_cohesion"]) if scattered else 1.0
	var dn := Vector2(d).normalized()
	var score := 0.0
	var center := Vector2.ZERO
	var n := 0
	var g: int = int(herd[di].get("group", 0))
	for i in active_deer():
		if i != di and int(herd[i].get("group", 0)) == g:
			center += Vector2(herd[i]["pos"])
			n += 1
	# 沿著小群的方向跑（Phase 2d 第 1 步）
	if group_dirs.has(g) and str(herd[di]["state"]) == "flee":
		score += dn.dot(Vector2(group_dirs[g]).normalized()) * float(hc["align"])
	if n > 0:
		var to_c: Vector2 = center / n - Vector2(deer_pos)
		if to_c.length() > 0.5:
			score += dn.dot(to_c.normalized()) * float(hc["cohesion"]) * mult
	var partner: int = -1
	if is_fawn():
		if not bool(herd[di]["separated"]):
			partner = int(herd[di]["mother"])
	else:
		var f: int = fawn_of(di)
		if f >= 0 and not bool(herd[f]["separated"]):
			partner = f
	if partner >= 0 and not bool(herd[partner]["gone"]):
		var to_p := Vector2(herd[partner]["pos"] - deer_pos)
		if to_p.length() > 1.0:
			score += dn.dot(to_p.normalized()) * float(hc["follow"]) * mult
	return score

# --- 鹿群一起逃（Phase 2d 第 1 步） ---

# 鹿群裡的一隻只在小群方向的左右 45° 內挑（跑得動的話）；被擋住時放寬到 90°，再不行才照自己的打分。
func _grouped(opts: Array) -> Array:
	var g: int = int(herd[di].get("group", 0))
	if herd.size() <= 1 or not group_dirs.has(g):
		return opts
	var gd := Vector2(group_dirs[g]).normalized()
	for lim in [0.7, 0.0]:
		var near: Array = opts.filter(func(o): return Vector2(o["dir"]).normalized().dot(gd) >= lim and float(o["score"]) > -10.0)
		if not near.is_empty():
			return near
	return opts

# 這一小群還在場上的鹿（fleeing_only：只算正在逃的、沒被咬住的）
func _group_members(g: int, fleeing_only: bool = true) -> Array:
	var out: Array = []
	for i in active_deer():
		if int(herd[i].get("group", 0)) != g or bool(herd[i]["held"]):
			continue
		if fleeing_only and str(herd[i]["state"]) != "flee":
			continue
		out.append(i)
	return out

func _group_ids(fleeing_only: bool = true) -> Array:
	var out: Array = []
	for i in active_deer():
		var g: int = int(herd[i].get("group", 0))
		if not out.has(g) and not _group_members(g, fleeing_only).is_empty():
			out.append(g)
	return out

func _group_center(members: Array) -> Vector2:
	var c := Vector2.ZERO
	for i in members:
		c += Vector2(herd[i]["pos"])
	return c / max(1, members.size())

# 每一小群算一個逃跑方向：用離狼最遠的那一隻（帶頭的）打分，從最好的兩三個方向挑一個；再看跑散的小群要不要合回來。
func _plan_groups() -> void:
	if herd.size() <= 1:
		return
	var keep := di
	for g in _group_ids():
		var m: Array = _group_members(g)
		var lead: int = m[0]
		for i in m:
			if dist(herd[i]["pos"], wolf_pos) > dist(herd[lead]["pos"], wolf_pos):
				lead = i
		di = lead
		var opts := flee_options(g)
		if not opts.is_empty():
			var weights: Array = t["deer"]["pick_weights"]
			var n: int = mini(3, opts.size())
			var pick: int = 0
			var tot := 0.0
			for k in n:
				tot += float(weights[k])
			var r := rng.randf() * tot
			for k in n:
				r -= float(weights[k])
				if r <= 0.0:
					pick = k
					break
			group_dirs[g] = opts[pick]["dir"]
		if group_push.has(g):
			group_push[g]["rounds"] = int(group_push[g]["rounds"]) - 1
			if int(group_push[g]["rounds"]) <= 0:
				group_push.erase(g)
		if group_split_age.has(g):
			group_split_age[g] = int(group_split_age[g]) + 1
	di = keep
	_merge_groups()

# 衝散：沿狼衝進來的線，把靠近的那一小群分成兩邊（鹿夠多、線上也有鹿時分成三群）。有分開就回傳 true。
func _split_groups() -> bool:
	var hc: Dictionary = t["herd"]
	var any := false
	for g in _group_ids(false):
		var m: Array = _group_members(g, false)
		# 剛分開的小群幾回合內不會再分
		if m.size() < 2 or int(group_split_age.get(g, 99)) < int(hc["split_cooldown"]):
			continue
		var near := false
		for i in m:
			if _cheb(herd[i]["pos"], wolf_pos) <= int(hc["scatter_dist"]):
				near = true
				break
		if not near:
			continue
		var line := Vector2(wolf_pos - wolf_from)
		if line.length() < 0.5:
			line = _group_center(m) - Vector2(wolf_pos)
		line = Vector2(1, 0) if line.length() < 0.01 else line.normalized()
		var normal := Vector2(-line.y, line.x)
		var parts := [[[], normal], [[], -normal], [[], line]]
		for i in m:
			var side: float = (Vector2(herd[i]["pos"]) - Vector2(wolf_pos)).dot(normal)
			if absf(side) < 0.75 and m.size() >= int(hc["split_three_min"]):
				parts[2][0].append(i)
			elif side >= 0.0:
				parts[0][0].append(i)
			else:
				parts[1][0].append(i)
		var used: Array = parts.filter(func(p): return not (p[0] as Array).is_empty())
		if used.size() < 2:
			continue
		var first := true
		for p in used:
			var gid: int = g if first else next_group
			if not first:
				next_group += 1
			first = false
			for i in p[0]:
				herd[i]["group"] = gid
			group_push[gid] = {"dir": p[1], "rounds": int(hc["split_push_rounds"])}
			group_split_age[gid] = 0
			if group_dirs.has(g):
				group_dirs[gid] = group_dirs[g]
		any = true
	# 分到不同群的幼鹿和生母跑散了
	if any:
		for i in active_deer():
			var mo: int = int(herd[i].get("mother", -1))
			if mo >= 0 and not bool(herd[i]["separated"]) and not bool(herd[mo]["gone"]) and int(herd[mo]["group"]) != int(herd[i]["group"]):
				herd[i]["separated"] = true
				events.append(_tx("tactical.separated"))
	return any

# 跑散的小群合回來：分開 regroup_rounds 回合以上、彼此 regroup_dist 格內、狼離兩群都 regroup_wolf_dist 格以上。
func _merge_groups() -> void:
	var hc: Dictionary = t["herd"]
	var ids: Array = _group_ids(false)
	for a in ids:
		for b in ids:
			if a >= b:
				continue
			if int(group_split_age.get(a, 99)) < int(hc["regroup_rounds"]) or int(group_split_age.get(b, 99)) < int(hc["regroup_rounds"]):
				continue
			var ma: Array = _group_members(a, false)
			var mb: Array = _group_members(b, false)
			if ma.is_empty() or mb.is_empty():
				continue
			var ca := _group_center(ma)
			var cb := _group_center(mb)
			if ca.distance_to(cb) > float(hc["regroup_dist"]) or min(ca.distance_to(Vector2(wolf_pos)), cb.distance_to(Vector2(wolf_pos))) < float(hc["regroup_wolf_dist"]):
				continue
			for i in mb:
				herd[i]["group"] = a
			group_push.erase(b)
			group_dirs.erase(b)
			group_split_age.erase(b)
			events.append(_tx("tactical.regroup"))
			return

# 意圖範圍：顯示幾個方向（感知越高越少，觀察過再少一個）
func intent_count() -> int:
	var n: int = 3
	if float(wolf["perception"]) >= float(t["intent"]["perception_one"]):
		n = 1
	elif float(wolf["perception"]) >= float(t["intent"]["perception_two"]):
		n = 2
	return maxi(1, n - mini(observed, 1))

func deer_intent() -> Array:
	if deer_state != "flee":
		return []
	var opts := flee_options()
	var out: Array = []
	for i in mini(intent_count(), opts.size()):
		out.append(opts[i]["dir"])
	return out

# 深雪時每回合少跑幾格：物種可以覆寫（野牛在深雪裡更慢，Phase 2f 第 3 步）
func _snow_slow(k: int) -> float:
	if not game_mods.has("snow_slow"):
		return 0.0
	return float(sp(k).get("snow_slow", game_mods["snow_slow"]))

func _flee_budget(i: int = -1) -> float:
	var k: int = di if i < 0 else i
	var h: Dictionary = herd[k]
	# 幼鹿的逃跑格數：物種可以覆寫（小野牛跟得上牛群，Phase 2f 第 3 步）
	var prof: Array = sp(k).get("calf_flee", t["herd"]["fawn_flee"]) if is_fawn(k) else sp(k).get("flee_profile", t["deer"]["flee_profile"])[h["condition"]]
	# 帶傷：每道傷少 wound_slow 格（最少 1 格）
	var b: float = max(1.0, float(prof[mini(int(h["flee_round"]), prof.size() - 1)]) - int(h["wounds"]) * float(t["hold"]["wound_slow"]) - _snow_slow(k))
	# 生母放慢等幼鹿：最多比幼鹿多跑 mother_slack 格（幼鹿還在附近、沒跑散時）
	if not is_fawn(k):
		var f: int = fawn_of(k)
		if f >= 0 and not bool(herd[f]["separated"]) and not bool(herd[f]["held"]) and dist(herd[f]["pos"], h["pos"]) <= 4.0:
			b = min(b, _flee_budget(f) + float(t["herd"]["mother_slack"]))
	return b

# 沿一個方向跑：撞到邊界就出場；遇到障礙轉 ±45° 繼續。回傳 {end, out, logs, blocked, moved}
func _run_line(start: Vector2i, d: Vector2i, budget: float) -> Dictionary:
	var pos := start
	var left := budget
	var logs := 0 # 經過擋路的格子（倒木；對這隻鹿是障礙的岩坡）
	var blocked := 0
	var moved := 0.0
	var dir := d
	var seek := 0 # 經過牠想逃去的地形（騾鹿的岩坡）
	var seek_t: String = str(sp().get("seek", {}).get("terrain", ""))
	var guard := 0
	var others := deer_cells(di)
	while left > 0.0 and guard < 20:
		guard += 1
		var n: Vector2i = pos + dir
		if not in_bounds(n):
			# 左右兩端（長邊的方向）可以跑出場地＝逃脫；上下邊緣是擋住的（16 格高，往上下跑 2 回合就出去，2026-10-15）
			if n.x < 0 or n.x >= width:
				return {"end": n, "out": true, "wall": false, "logs": logs, "blocked": blocked, "moved": moved + 1.0, "seek": seek}
			return {"end": pos, "out": false, "wall": true, "logs": logs, "blocked": blocked + 1, "moved": moved, "seek": seek}
		if n == wolf_pos:
			blocked += 1
			break
		if others.has(n):
			break # 前面有同伴，停在牠後面
		var c := deer_step_cost(pos, n)
		if deer_rough(n):
			logs += 1
		if seek_t != "" and terrain(n) == seek_t:
			seek += 1
		if c > left and moved > 0.0:
			break
		left -= c
		moved += c
		pos = n
	return {"end": pos, "out": false, "wall": false, "logs": logs, "blocked": blocked, "moved": moved, "seek": seek}

func _deer_flee() -> void:
	if is_fawn() and int(herd[di]["mother"]) >= 0:
		var m: int = int(herd[di]["mother"])
		if bool(herd[di]["separated"]):
			if not bool(herd[m]["gone"]) and dist(herd[m]["pos"], deer_pos) <= 2.0:
				herd[di]["separated"] = false
		elif scattered and rng.randf() < float(t["herd"]["separate_forest" if terrain(deer_pos) == "f" else "separate"]):
			herd[di]["separated"] = true
			events.append(_tx("tactical.separated"))
	var opts := _grouped(flee_options())
	if opts.is_empty() or float(opts[0]["score"]) < -10.0:
		deer_state = "stand"
		deer_facing = _dir_toward(deer_pos, wolf_pos)
		events.append(_tx("tactical.cornered"))
		return
	# 從最好的二到三個方向隨機選一個；在密林裡有機會急轉成第二好的
	var weights: Array = t["deer"]["pick_weights"]
	var n: int = mini(3, opts.size())
	var pick: int = 0
	var r := rng.randf() * (float(weights[0]) + (float(weights[1]) if n > 1 else 0.0) + (float(weights[2]) if n > 2 else 0.0))
	for i in n:
		r -= float(weights[i])
		if r <= 0.0:
			pick = i
			break
	if terrain(deer_pos) == "f" and n > 1 and rng.randf() < float(t["deer"]["forest_turn"]):
		pick = 1
	var d: Vector2i = opts[pick]["dir"]
	var sim := _run_line(deer_pos, d, _flee_budget())
	# 不在兩格之間來回：會回到上上回合的位置時，換下一個方向
	if deer_last_cells.size() >= 2 and sim["end"] == deer_last_cells[-2]:
		for o in opts:
			var alt := _run_line(deer_pos, o["dir"], _flee_budget())
			if alt["end"] != deer_last_cells[-2] and float(o["score"]) > -10.0:
				d = o["dir"]
				sim = alt
				break
	var before := dist(deer_pos, wolf_pos)
	flee_round += 1
	deer_facing = d
	if sim["out"]:
		_deer_gone("escaped", _escape_reason())
		return
	deer_pos = sim["end"]
	# 和狼拉開到 escape_dist 格以上，或已經跑了 max_flee_rounds 回合（狼不會無限追下去）：逃脫
	if dist(deer_pos, wolf_pos) >= float(t["deer"]["escape_dist"]) or flee_round >= int(t["deer"]["max_flee_rounds"]):
		_deer_gone("escaped", _escape_reason())
		return
	if dist(deer_pos, wolf_pos) < before - 0.01:
		stats["toward_wolf"] += 1
	deer_last_cells.append(deer_pos)
	if deer_last_cells.size() > 4:
		deer_last_cells.pop_front()
	if deer_last_cells.size() == 4 and deer_last_cells[0] == deer_last_cells[2] and deer_last_cells[1] == deer_last_cells[3]:
		stats["stuck"] += 1

func _check_lost() -> void:
	if done or deer_state != "flee":
		lost_turns = 0
		return
	if terrain(deer_pos) == "f" and not has_sight():
		lost_turns += 1
		if lost_turns >= int(t["deer"]["lost_sight_turns"]):
			_deer_gone("lost", _tx("tactical.lost").replace("{animal}", label()))
	else:
		lost_turns = 0

func _escape_reason() -> String:
	match detect_cause:
		"scent":
			return _tx("tactical.escape.scent")
		"missed":
			return _tx("tactical.escape.missed")
	if breath < -float(t["move"]["breath_sprint"]):
		return _tx("tactical.escape.breath")
	return _tx("tactical.escape.open")

# 一隻鹿逃掉了：只有一隻時整場結束；鹿群裡就是這一隻離場，全部離場才結束
func _deer_gone(kind: String, text: String) -> void:
	if herd.size() <= 1:
		_finish(kind, text)
		return
	herd[di]["gone"] = true
	herd[di]["held"] = false
	events.append(_tx("tactical.ran_far").replace("{animal}", label()) if kind == "escaped" else text)
	if active_deer().is_empty():
		_finish(kind, _tx("tactical.herd_gone"))

func _finish(p_result: String, text: String) -> void:
	done = true
	result = p_result
	reason = text
	if p_result == "caught":
		caught_kind = "fawn" if is_fawn(target) else "adult"
		meat = int(sp(target).get("meat", t["herd"]["meat"][caught_kind]))
	events.append(text)

# --- 結算（接進主遊戲時用）---

func game_turns() -> int:
	return clampi(int(ceil(rounds / 5.0)), 1, 3)

func stamina_cost() -> float:
	return min(18.0, 2.0 + breath_used * 0.08)

func _weighted(table: Dictionary) -> String:
	var total := 0.0
	for k in table:
		total += float(table[k])
	var r := rng.randf() * total
	for k in table:
		r -= float(table[k])
		if r <= 0.0:
			return k
	return table.keys()[0]
