extends RefCounted

# 戰術狩獵原型的邏輯（docs/proposals/tactical-hunt-prototype.md）。純邏輯、不碰 GameState，可以 headless 測試；
# 畫面層與模擬都只呼叫這裡的公開函式。數值在 tuning.json。
#
# 一回合：狼行動（移動／觀察／撲咬／放棄）→ 鹿行動 → 更新。座標是格子（Vector2i），x 往右、y 往下。
# 風向 wind 是風吹「往」的方向：狼在上風＝氣味從狼吹向鹿。

const TUNING_PATH := "res://prototypes/tactical_hunt/tuning.json"
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
var herd: Array = [] # {pos, facing, state(unaware/suspicious/flee/stand), alert, flee_round, condition, condition_known, held, wounds, lost_turns, goal_index, last_cells}
var wi: int = 0
var di: int = 0
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
var stats := {"stuck": 0, "toward_wolf": 0}

func _init() -> void:
	t = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))

# --- 開局 ---

func setup(p_scenario: String, wolf_profile: String, seed: int, stamina_mult: float = 1.0) -> void:
	rng.seed = seed
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
	herd = [{"pos": Vector2i(int(sc["deer"][0]), int(sc["deer"][1])), "facing": DIRS[rng.randi_range(0, 7)], "state": "unaware", "alert": 0.0,
		"flee_round": 0, "condition": str(_weighted(t["deer"]["condition_weights"])), "condition_known": false, "held": false, "wounds": 0,
		"lost_turns": 0, "goal_index": 0, "last_cells": []}]
	wi = 0
	di = 0
	observed = 0
	rounds = 0
	done = false
	result = ""
	reason = ""
	detect_cause = ""
	kicks = 0
	events = []
	stats = {"stuck": 0, "toward_wolf": 0}

# --- 地形與距離 ---

func terrain(c: Vector2i) -> String:
	return String(grid[c.y])[c.x]

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height

func step_cost(from: Vector2i, to: Vector2i) -> float:
	var d := to - from
	var base: float = float(t["move"]["diag_cost"]) if d.x != 0 and d.y != 0 else 1.0
	return base + float(t["move"]["terrain_extra"].get(terrain(to), 0.0))

func dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

# 從 start 出發、花費不超過 limit 能到的格子：{cell: cost}（不能走進鹿那一格）。
func costs_from(start: Vector2i, limit: float, block: Vector2i = Vector2i(-99, -99)) -> Dictionary:
	var best := {start: 0.0}
	var open: Array = [start]
	while not open.is_empty():
		var cur: Vector2i = open.pop_front()
		for d in DIRS:
			var n: Vector2i = cur + d
			if not in_bounds(n) or n == block:
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
	if breath >= -float(m["breath_sprint"]):
		return sprint_range()
	if breath >= -float(m["breath_trot"]):
		return trot_range()
	return float(m["creep_range"])

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
	var costs := costs_from(wolf_pos, max_move(), deer_pos)
	for c in costs.keys():
		if c != wolf_pos:
			out[c] = mode_for_cost(float(costs[c]))
	# 潛行一定能走一格（密林、倒木裡也能慢慢潛行；原本密林一格花 2，潛行走不動）
	for d in DIRS:
		var n: Vector2i = wolf_pos + d
		if in_bounds(n) and n != deer_pos:
			out[n] = "creep" # 相鄰的一格永遠算潛行
	return out

func move_to(cell: Vector2i) -> void:
	if done:
		return
	var r := reachable()
	if not r.has(cell):
		return
	var mode: String = r[cell]
	wolf_pos = cell
	_spend("breath_" + mode)
	_end_wolf_turn(mode)

func observe() -> void:
	if done:
		return
	_spend("breath_observe")
	condition_known = true
	observed += 1
	events.append("你停下來觀察。牠的體況：%s。" % {"healthy": "健康", "average": "普通", "weak": "虛弱"}[condition])
	_end_wolf_turn("still")

func give_up() -> void:
	if done:
		return
	_finish("gave_up", "你放棄了。")

func _spend(key: String) -> void:
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
	return clamp(float(flee_round - 2) / 3.0, 0.0, 1.0)

# 撲咬命中率與因素（狼在 wolf_pos）：{"chance", "factors": [[文字, 加減]], "side", "kick"}
func pounce_chance(mode: String = "still") -> Dictionary:
	var p: Dictionary = t["pounce"]
	var side := angle_side()
	var factors: Array = []
	var v: float = float(p["base"])
	var a: float = float(p["angle"][side])
	v += a
	factors.append([{"rear": "從後方", "side": "從側面", "front": "從正面"}[side], a])
	var tired: float = deer_fatigue() * float(p["tired_max"])
	if tired > 0.0:
		v += tired
		factors.append(["牠累了", tired])
	var ab: float = ((float(wolf["speed"]) + float(wolf["skill"])) * 0.5 - float(t["deer"]["speed"])) / float(p["ability_divisor"])
	v += ab
	factors.append(["你的速度與技巧", ab])
	if terrain(deer_pos) == "l":
		v += float(p["in_logs"])
		factors.append(["牠在倒木裡", float(p["in_logs"])])
	# 牠還沒發現你（沒察覺）就撲到：最好的機會
	if deer_state == "unaware" and not (mode in ["trot", "sprint"] and alert + float(alert_gain(mode)["gain"]) >= float(t["deer"]["flee_at"])):
		v += float(p["unaware"])
		factors.append(["牠還沒發現你", float(p["unaware"])])
	# 鹿還沒逃、你用小跑或衝刺衝過去：這一步的動靜會讓牠警覺；會讓牠跳開的話命中大降
	if deer_state != "flee" and mode in ["trot", "sprint"]:
		var bolt: bool = alert + float(alert_gain(mode)["gain"]) >= float(t["deer"]["flee_at"])
		var r: float = float(p["rush_bolt"]) if bolt else float(p["rush"])
		v -= r
		factors.append(["衝過去，牠先跳開" if bolt else "衝過去，牠先驚覺", -r])
	return {"chance": clamp(v, 0.05, 0.95), "factors": factors, "side": side, "kick": kick_chance()}

func kick_chance() -> float:
	var side := angle_side()
	var k: Dictionary = t["pounce"]["kick"]
	if side == "rear":
		return float(k["rear"]) if deer_state == "flee" else 0.0
	if side == "front":
		return float(k["front"]) if deer_state != "flee" else 0.0
	return float(k["side"])

func pounce() -> void:
	pounce_at(wolf_pos)

func pounce_at(cell: Vector2i) -> void:
	var targets := pounce_targets()
	if not targets.has(cell):
		return
	var info: Dictionary = targets[cell]
	if str(info["mode"]) != "still":
		wolf_pos = cell
		_spend("breath_" + str(info["mode"]))
	_spend("breath_pounce")
	var side: String = info["side"]
	if rng.randf() < float(info["kick"]):
		var k: Array = t["pounce"]["kick_damage"]
		var dmg: int = rng.randi_range(int(k[0]), int(k[1]))
		wolf["health"] = float(wolf["health"]) - dmg
		kicks += 1
		events.append(("牠的後腿踢中了你" if side == "rear" else "牠的蹄子踢中了你") + "（血量 −%d）。" % dmg)
	if rng.randf() < float(info["chance"]):
		# 咬住了：不是馬上獵到，接下來要壓倒或咬喉，牠會掙扎（2026-10-15 使用者同意的兩步）
		held = true
		hold_side = side
		events.append({"rear": "你從後方咬住了牠的後腿！", "side": "你從側面咬住了牠！", "front": "你正面咬住了牠的脖子！"}[side])
		rounds += 1
		_deer_turn()
		return
	events.append("撲空了！")
	if deer_state != "flee":
		_start_flee("missed")
	flee_round = maxi(flee_round, 1) # 受驚：下一回合從衝刺開始
	rounds += 1
	_deer_turn()
	if not done and rounds >= int(t["max_rounds"]):
		_finish("timeout", "拖太久了，牠走遠了。")

# --- 咬住之後：壓倒（力量）、咬喉（技巧，成功就咬死）、鬆口 ---

func hold_options() -> Dictionary:
	if not held or done:
		return {}
	var h: Dictionary = t["hold"]
	var fat: float = deer_fatigue_any()
	var out := {}
	var td: float = float(h["takedown_base"]) + (float(wolf["strength"]) - 50.0) / float(h["divisor"]) + fat * float(h["tired"]) \
		+ (float(h["rear"]) if hold_side == "rear" else 0.0) + wounds * float(h["per_wound"])
	out["takedown"] = {"chance": clamp(td, 0.05, 0.95), "breath": float(h["takedown_breath"]),
		"factors": [["你的力量", (float(wolf["strength"]) - 50.0) / float(h["divisor"])], ["牠累了", fat * float(h["tired"])]]}
	var th: float = float(h["throat_base"]) + (float(wolf["skill"]) - 50.0) / float(h["divisor"]) + fat * float(h["tired"]) + wounds * float(h["per_wound"])
	out["throat"] = {"chance": clamp(th, 0.05, 0.95), "breath": float(h["throat_breath"]),
		"factors": [["你的技巧", (float(wolf["skill"]) - 50.0) / float(h["divisor"])], ["牠累了", fat * float(h["tired"])]]}
	for k in out.keys():
		if breath < float(out[k]["breath"]):
			out.erase(k)
	out["release"] = {"chance": 1.0, "breath": 0.0, "factors": []}
	return out

# 牠掙脫的機率（每回合）：越累越低；咬喉失敗那一回合更容易掙脫
func break_chance(after_throat_miss: bool = false) -> float:
	var h: Dictionary = t["hold"]
	return clamp(float(h["break_base"]) - deer_fatigue_any() * float(h["break_tired"]) + (float(h["throat_miss_break"]) if after_throat_miss else 0.0), 0.05, 0.95)

# 疲勞：逃跑的回合數，或咬住時掙扎的消耗（沒在逃也算）
func deer_fatigue_any() -> float:
	return clamp(float(flee_round - 2) / 3.0 + float(herd[di].get("struggle", 0)) * 0.15, 0.0, 1.0)

func hold_action(id: String) -> void:
	var opts := hold_options()
	if not opts.has(id):
		return
	var o: Dictionary = opts[id]
	if id == "release":
		_let_go("你鬆開了口，牠一跛一跛地跑開。")
		rounds += 1
		_deer_turn()
		return
	breath = max(0.0, breath - float(o["breath"]))
	breath_used += float(o["breath"])
	if rng.randf() < float(o["chance"]):
		rounds += 1
		_finish("caught", "你把牠壓倒在地，獵到了。" if id == "takedown" else "你咬住牠的咽喉，牠倒了下去。")
		return
	events.append("牠還在掙扎。" if id == "takedown" else "沒咬到要害，牠猛力一甩。")
	rounds += 1
	_deer_turn(id == "throat")
	if not done and rounds >= int(t["max_rounds"]):
		_finish("timeout", "拖太久了。")

func _let_go(text: String) -> void:
	held = false
	wounds += 1
	deer_state = "flee"
	flee_round = maxi(flee_round, 1)
	events.append(text)

# 咬住時鹿的回合：掙扎（可能踢中你），可能掙脫、帶傷逃跑
func _deer_struggle(after_throat_miss: bool) -> void:
	herd[di]["struggle"] = int(herd[di].get("struggle", 0)) + 1
	var h: Dictionary = t["hold"]
	if rng.randf() < float(h["kick"]):
		var k: Array = t["pounce"]["kick_damage"]
		var dmg: int = rng.randi_range(int(k[0]), int(k[1]))
		wolf["health"] = float(wolf["health"]) - dmg
		kicks += 1
		events.append("掙扎中牠踢中了你（血量 −%d）。" % dmg)
	if rng.randf() < break_chance(after_throat_miss):
		_let_go("牠掙脫了，帶著傷逃跑！")
		_deer_flee()

# --- 回合結束：警覺值、鹿行動 ---

func _end_wolf_turn(mode: String) -> void:
	rounds += 1
	if deer_state in ["unaware", "suspicious"]:
		_raise_alert(mode)
	_deer_turn()
	if not done and rounds >= int(t["max_rounds"]):
		_finish("timeout", "拖太久了，牠走遠了。")

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
	sight *= 1.0 - (float(wolf["skill"]) - 40.0) / float(al["skill_divisor"])
	var scent: float = _band(al["scent"].get(wind_side(), []), d)
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
		events.append("牠抬起頭，朝你這邊張望。")

func _start_flee(cause: String) -> void:
	deer_state = "flee"
	flee_round = 0
	if detect_cause == "":
		detect_cause = cause
	events.append({"scent": "風把你的氣味送了過去，牠猛地跳開！", "noise": "牠聽到動靜，拔腿就跑！", "close": "牠發現你了，拔腿就跑！", "missed": "牠受驚，拔腿就跑！"}.get(cause, "牠跑了！"))

func _deer_turn(after_throat_miss: bool = false) -> void:
	if done:
		return
	if held:
		breath = max(0.0, breath - float(t["hold"]["hold_breath"])) # 咬著不放也很累
		_deer_struggle(after_throat_miss)
		return
	match deer_state:
		"unaware":
			_deer_wander()
		"suspicious", "stand":
			deer_facing = _dir_toward(deer_pos, wolf_pos)
		"flee":
			_deer_flee()
	_check_lost()

func _dir_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	return Vector2i(signi(d.x), signi(d.y)) if d != Vector2i.ZERO else deer_facing

# 沒察覺時：邊吃草邊往目的地（水邊、林緣…）慢慢走，走到了換下一個。有固定的去向，伏擊才有意義（2026-10-15 使用者同意）。
func _deer_wander() -> void:
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
		if not in_bounds(n) or n == wolf_pos or terrain(n) == "l":
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
func flee_options() -> Array:
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
		score += Vector2(d).normalized().dot(Vector2(deer_facing).normalized()) * float(t["deer"]["momentum"])
		score -= float(sim["logs"]) * 2.5
		score -= float(sim["blocked"]) * 3.0
		if float(sim["moved"]) <= 0.0:
			score -= 20.0
		scored.append({"dir": d, "score": score})
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	return scored

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

func _flee_budget() -> float:
	var prof: Array = t["deer"]["flee_profile"][condition]
	# 帶傷：每道傷少 wound_slow 格（最少 1 格）
	return max(1.0, float(prof[mini(flee_round, prof.size() - 1)]) - wounds * float(t["hold"]["wound_slow"]))

# 沿一個方向跑：撞到邊界就出場；遇到障礙轉 ±45° 繼續。回傳 {end, out, logs, blocked, moved}
func _run_line(start: Vector2i, d: Vector2i, budget: float) -> Dictionary:
	var pos := start
	var left := budget
	var logs := 0
	var blocked := 0
	var moved := 0.0
	var dir := d
	var guard := 0
	while left > 0.0 and guard < 20:
		guard += 1
		var n: Vector2i = pos + dir
		if not in_bounds(n):
			# 左右兩端（長邊的方向）可以跑出場地＝逃脫；上下邊緣是擋住的（16 格高，往上下跑 2 回合就出去，2026-10-15）
			if n.x < 0 or n.x >= width:
				return {"end": n, "out": true, "wall": false, "logs": logs, "blocked": blocked, "moved": moved + 1.0}
			return {"end": pos, "out": false, "wall": true, "logs": logs, "blocked": blocked + 1, "moved": moved}
		if n == wolf_pos:
			blocked += 1
			break
		var c := step_cost(pos, n)
		if terrain(n) == "l":
			logs += 1
		if c > left and moved > 0.0:
			break
		left -= c
		moved += c
		pos = n
	return {"end": pos, "out": false, "wall": false, "logs": logs, "blocked": blocked, "moved": moved}

func _deer_flee() -> void:
	var opts := flee_options()
	if opts.is_empty() or float(opts[0]["score"]) < -10.0:
		deer_state = "stand"
		deer_facing = _dir_toward(deer_pos, wolf_pos)
		events.append("牠被逼到角落，轉身站定。")
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
		_finish("escaped", _escape_reason())
		return
	deer_pos = sim["end"]
	# 和狼拉開到 escape_dist 格以上，或已經跑了 max_flee_rounds 回合（狼不會無限追下去）：逃脫
	if dist(deer_pos, wolf_pos) >= float(t["deer"]["escape_dist"]) or flee_round >= int(t["deer"]["max_flee_rounds"]):
		_finish("escaped", _escape_reason())
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
			_finish("lost", "牠鑽進密林，不見了。")
	else:
		lost_turns = 0

func _escape_reason() -> String:
	match detect_cause:
		"scent":
			return "牠從上風聞到你，早早就跑了。"
		"missed":
			return "撲空之後，牠跑掉了。"
	if breath < -float(t["move"]["breath_sprint"]):
		return "你喘不過氣，追不上了。"
	return "開闊地上，你追不上牠。"

func _finish(p_result: String, text: String) -> void:
	done = true
	result = p_result
	reason = text
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
