class_name RiverFishing
extends RefCounted

# 鮭魚洄流的河岸模式（Phase 2h 第 2 步，SPEC「Phase 2h」）：鮭魚溪的戰術地圖上，狼移動、站上淺灘撲魚、邊捕邊吃、隨時離開。
# 只管這一場的局面；時間、體力、飽食度由 GameState.finish_salmon_fishing 結算（同戰術狩獵）。
# 地圖、地形的移動代價沿用戰術狩獵（data/tactical_hunt.json 的 maps（family salmon）與 move.terrain_extra）；數值在 balance.salmon.river。
# 灰熊（第 3 步）之後加在這裡。

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
var result: String = "" # "left" 自己離開、"full" 吃不下了也算離開、"timeout" 待太久
var events: Array = []

func _init() -> void:
	t = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))

# ctx：{stage, seed, hunger, hunger_max, overfed_at, cfg（balance.salmon.river）, map（可省略：地圖 id）}
func setup(ctx: Dictionary) -> void:
	cfg = ctx.get("cfg", {})
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
	wolf_pos = _start_cell()

# 開場的位置：離水 1～2 格的岸邊（不在淺灘上）
func _start_cell() -> Vector2i:
	var cands: Array = []
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if terrain(c) != ".":
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
			if not in_bounds(n):
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
		if in_bounds(n) and not out.has(n):
			out[n] = step_cost(wolf_pos, n)
	return out

# --- 行動 ---

func move_to(c: Vector2i) -> void:
	if done or not reachable().has(c):
		return
	wolf_pos = c
	_end_round()

# 撲魚的成功率（站的這一格）；不在淺灘或吃不下時是 0
func fish_chance() -> float:
	var q := fish_at(wolf_pos)
	if q <= 0 or terrain(wolf_pos) != "s" or hunger >= hunger_max:
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

func leave() -> void:
	if done:
		return
	done = true
	result = "full" if hunger >= hunger_max else "left"

func _end_round() -> void:
	rounds += 1
	if rounds >= int(cfg.get("max_rounds", 160)):
		events.append(_tx("river.timeout"))
		done = true
		result = "timeout"

# 換算成遊戲時間：rounds_per_turn 個戰術回合 = 1 個遊戲回合（至少 1）
func game_turns() -> int:
	return maxi(1, int(ceil(float(rounds) / float(cfg.get("rounds_per_turn", 8)))))

func _tx(key: String) -> String:
	return TranslationServer.translate(key)
