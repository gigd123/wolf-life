class_name TacticalGrid
extends RefCounted

# 戰術地圖的共用工具（2026-11-04，戰術戰鬥原型第 1 步）：格子、地形、移動成本、可到的格子、距離、角度、轉身。
# 戰術戰鬥（TacticalCombat）用；戰術狩獵（TacticalHunt）目前還用自己的同一套寫法，之後再改用這裡（行為一樣）。
# 座標是格子（Vector2i），x 往右、y 往下。

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

var grid: Array = [] # grid[y] 是一列字元
var width := 0
var height := 0
var move: Dictionary = {} # diag_cost、terrain_extra（同 tactical_hunt.json 的 move）

func _init(rows: Array = [], move_cfg: Dictionary = {}) -> void:
	grid = rows.duplicate()
	height = grid.size()
	width = String(grid[0]).length() if height > 0 else 0
	move = move_cfg

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func terrain(c: Vector2i) -> String:
	return String(grid[c.y])[c.x] if in_bounds(c) else ""

func on_edge(c: Vector2i) -> bool:
	return c.x == 0 or c.y == 0 or c.x == width - 1 or c.y == height - 1

# extra：物種的地形代價覆寫（{地形字元: 代價}，負的不算）；impassable：走不進去的地形
func step_cost(from: Vector2i, to: Vector2i, extra: Dictionary = {}) -> float:
	var d := to - from
	var base: float = float(move.get("diag_cost", 1.5)) if d.x != 0 and d.y != 0 else 1.0
	var k := terrain(to)
	var e: float = float(extra[k]) if extra.has(k) else float(move.get("terrain_extra", {}).get(k, 0.0))
	return base + e

func dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func adjacent(a: Vector2i, b: Vector2i) -> bool:
	return a != b and cheb(a, b) <= 1

# 從 start 出發、花費不超過 limit 能到的格子：{cell: cost}。blocks 的格子不能走進去；impassable 是走不進的地形字元。
func costs_from(start: Vector2i, limit: float, blocks: Dictionary = {}, extra: Dictionary = {}, impassable: String = "") -> Dictionary:
	var best := {start: 0.0}
	var open: Array = [start]
	while not open.is_empty():
		var cur: Vector2i = open.pop_front()
		for d in DIRS:
			var n: Vector2i = cur + d
			if not in_bounds(n) or blocks.has(n) or (impassable != "" and impassable.contains(terrain(n))):
				continue
			var c: float = float(best[cur]) + step_cost(cur, n, extra)
			if c <= limit + 0.001 and (not best.has(n) or c < float(best[n])):
				best[n] = c
				open.append(n)
	return best

static func dir_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var v := Vector2(to - from)
	if v.length() < 0.001:
		return Vector2i(1, 0)
	var best := DIRS[0]
	var bd := -INF
	for d in DIRS:
		var s: float = Vector2(d).normalized().dot(v.normalized())
		if s > bd:
			bd = s
			best = d
	return best

# 從 facing 轉向 want，最多 max_steps 個 45°（< 0 不限）
static func turn_toward(facing: Vector2i, want: Vector2i, max_steps: int) -> Vector2i:
	var cur: int = DIRS.find(facing)
	var goal: int = DIRS.find(want)
	if cur < 0 or goal < 0 or max_steps < 0:
		return want
	var diff: int = posmod(goal - cur, 8)
	if diff == 0:
		return facing
	var steps: int = mini(diff if diff <= 4 else 8 - diff, max_steps)
	return DIRS[posmod(cur + (steps if diff <= 4 else -steps), 8)]

# 在 at（面向 facing）的哪一側：front / side / rear
static func side_of(at: Vector2i, facing: Vector2i, other: Vector2i) -> String:
	var to_o := Vector2(other - at)
	if to_o.length() < 0.001:
		return "front"
	var c: float = to_o.normalized().dot(Vector2(facing).normalized())
	if c > 0.5:
		return "front"
	if c < -0.5:
		return "rear"
	return "side"
