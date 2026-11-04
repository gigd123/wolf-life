class_name TacticalCombat
extends RefCounted

# 戰術戰鬥的邏輯（原型規格 docs/proposals/tactical-combat-prototype.md，2026-11-04 使用者確認）。
# 純邏輯、不碰 GameState，可以 headless 測試；畫面層與模擬只呼叫這裡的公開函式。數值在 data/tactical_combat.json，
# 移動成本與喘沿用 data/tactical_hunt.json 的 move、breath。
#
# 第 1 步：地圖、單位（你、伴侶、對手）、殘骸、移動範圍（喘、叼著肉時依大小變慢）、叼肉與放下、撤出地圖。
# 第 2 步：回合流程。begin_round() 對手表態 → plan() 你方的移動＋一個動作 → resolve() 依 mode 結算：
#   sync 同步：雙方移動 → 變卦 → 照先後出手（對手打範圍、狼打目標）→ 先打中的可能打斷後出手的
#   alternate 預告後輪流：你方先移動、出手 → 對手朝最近的威脅轉一次（≤45°）→ 變卦 → 出手
# 之後的步驟：動作庫與 AI（第 3 步，現在對手用 _simple_intent 的簡單規則）、資訊等級、伴侶的合作。

const CFG_PATH := "res://data/tactical_combat.json"
const HUNT_CFG_PATH := "res://data/tactical_hunt.json"

var cfg: Dictionary = {}
var hunt_cfg: Dictionary = {}
var map: TacticalGrid
var rng := RandomNumberGenerator.new()
var scenario_id := ""
var mode := "sync" # sync 同步結算／alternate 預告後輪流
var knowledge_level := 0 # 原型：0 沒見過 ～ 3 熟悉（第 4 步會改成每個動作各自累積）

# 單位：{id, side(player/ally/enemy), species, pos, facing, stats, hp, hp_max, breath, breath_max,
#   carrying(""/small/medium/large), carry_segments, out(離開戰鬥), out_reason, eating}
var units: Array = []
# 殘骸：{pos, animal, segments, size, small_whole, whole_size, leg}；沒有殘骸時是空的
var carcass: Dictionary = {}
# 放下的肉：[{pos, segments, size}]
var drops: Array = []
var rounds := 0
var done := false
var outcome := "" # 結束時：retreated 你撤出、enemy_left 對手走了、knocked 你被打倒、timeout
var log_lines: Array = []
# 這一回合：對手的表態 {i: intent}、你方的計畫 {i: plan}、結算的事件
var intents := {}
var plans := {}
var events: Array = []

func _init() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
	hunt_cfg = JSON.parse_string(FileAccess.get_file_as_string(HUNT_CFG_PATH))

func _move_cfg() -> Dictionary:
	var m: Dictionary = (hunt_cfg["move"] as Dictionary).duplicate(true)
	var te: Dictionary = m["terrain_extra"]
	for k in (cfg.get("terrain_extra", {}) as Dictionary).keys():
		te[k] = cfg["terrain_extra"][k]
	return m

# opts：wolf_profile（novice/average/veteran）、knowledge（novice/experienced/veteran）、mode（sync/alternate）、seed、with_mate
func setup(p_scenario: String, opts: Dictionary = {}) -> void:
	var scs: Dictionary = cfg["scenarios"]
	var sc: Dictionary = scs[p_scenario]
	var with_mate: bool = bool(opts.get("with_mate", sc.get("with_mate", false)))
	if sc.has("base"):
		sc = scs[str(sc["base"])]
	scenario_id = p_scenario
	rng.seed = int(opts.get("seed", 1))
	mode = str(opts.get("mode", "sync"))
	knowledge_level = int(cfg["knowledge_presets"].get(str(opts.get("knowledge", "novice")), 0))
	map = TacticalGrid.new(sc["map"], _move_cfg())
	units.clear()
	drops.clear()
	rounds = 0
	done = false
	outcome = ""
	log_lines.clear()
	intents.clear()
	plans.clear()
	events.clear()
	var wp: Dictionary = (cfg["wolf_profiles"][str(opts.get("wolf_profile", "average"))] as Dictionary).duplicate()
	units.append(_make_wolf("wolf", "player", _v(sc["wolf"]), wp))
	if with_mate and sc.has("mate"):
		units.append(_make_wolf("mate", "ally", _v(sc["mate"]), wp.duplicate()))
	var o: Dictionary = sc["opponent"]
	var od: Dictionary = cfg["opponents"][str(o["id"])]
	units.append({"id": str(o["id"]), "side": "enemy", "species": str(o["id"]), "pos": _v(o["pos"]), "facing": _v(o.get("facing", [-1, 0])),
		"stats": {"strength": float(od["strength"]), "speed": float(od["speed"])}, "hp": float(od["hp"]), "hp_max": float(od["hp"]),
		"breath": 0.0, "breath_max": 0.0, "carrying": "", "carry_segments": 0, "out": false, "out_reason": "",
		"eating": bool(o.get("eating", false)), "ambush": bool(o.get("ambush", false)),
		"stamina": float(cfg["enemy_stamina"].get(str(o["id"]), 80.0)), "stamina_max": float(cfg["enemy_stamina"].get(str(o["id"]), 80.0))})
	carcass = {}
	if sc.has("carcass"):
		var cc: Array = sc["carcass"]
		var cd: Dictionary = cfg["carcass"][str(cc[2])]
		carcass = {"pos": Vector2i(int(cc[0]), int(cc[1])), "animal": str(cc[2]), "segments": int(cd["segments"]),
			"size": str(cd.get("size", "large")), "small_whole": bool(cd.get("small_whole", false)),
			"whole_size": str(cd.get("whole_size", "small")), "leg": cd.get("leg_segments", [2, 3])}

func _v(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))

func _make_wolf(id: String, side: String, pos: Vector2i, st: Dictionary) -> Dictionary:
	var b: Dictionary = hunt_cfg["breath"]
	var bmax: float = clamp(float(b["base"]) + float(st["stamina"]) * float(b["per_stamina"]) + float(st["speed"]) * float(b["per_speed"]), float(b["min"]), float(b["max"]))
	return {"id": id, "side": side, "species": "wolf", "pos": pos, "facing": Vector2i(1, 0), "stats": st,
		"hp": float(st["health"]), "hp_max": float(st["health_max"]), "breath": bmax, "breath_max": bmax,
		"carrying": "", "carry_segments": 0, "out": false, "out_reason": "", "eating": false}

# --- 查詢 ---

func index_of(id: String) -> int:
	for i in units.size():
		if str(units[i]["id"]) == id:
			return i
	return -1

func enemy_index() -> int:
	for i in units.size():
		if str(units[i]["side"]) == "enemy":
			return i
	return -1

func active(i: int) -> bool:
	return i >= 0 and i < units.size() and not bool(units[i]["out"])

# 其他單位與殘骸佔的格子（i 自己不算）
func blocks_for(i: int) -> Dictionary:
	var b := {}
	for k in units.size():
		if k != i and active(k):
			b[units[k]["pos"]] = true
	if not carcass.is_empty():
		b[carcass["pos"]] = true
	return b

func _opp_cfg(i: int) -> Dictionary:
	return cfg["opponents"].get(str(units[i]["species"]), {})

# 物種的地形代價覆寫（灰熊爬大石頭比較慢）
func terrain_cost(i: int) -> Dictionary:
	return _opp_cfg(i).get("terrain_cost", {})

func _impassable(i: int) -> String:
	var s: String = str(_opp_cfg(i).get("impassable", cfg.get("impassable", "cTt")))
	return s

# --- 移動 ---

func _carry_less(i: int) -> float:
	var c: String = str(units[i]["carrying"])
	return float(cfg["carry"]["move_less"].get(c, 0.0)) if c != "" else 0.0

func can_sprint(i: int) -> bool:
	var u: Dictionary = units[i]
	if (cfg["carry"]["no_sprint"] as Array).has(str(u["carrying"])):
		return false
	if str(u["species"]) != "wolf":
		return true
	return float(u["breath"]) >= -float(map.move["breath_sprint"])

func trot_range(i: int) -> float:
	var u: Dictionary = units[i]
	if str(u["species"]) != "wolf":
		return float(_opp_cfg(i).get("move", 3.0))
	var m: Dictionary = map.move
	return float(m["trot_range_slow"]) if float(u["stats"]["speed"]) < float(m["trot_slow_speed"]) else float(m["trot_range"])

func sprint_range(i: int) -> float:
	var u: Dictionary = units[i]
	if str(u["species"]) != "wolf":
		return float(_opp_cfg(i).get("charge_move", 5.0))
	for pair in map.move["sprint_by_speed"]:
		if float(u["stats"]["speed"]) < float(pair[0]):
			return float(pair[1])
	return 4.0

func max_move(i: int) -> float:
	var r: float = sprint_range(i) if can_sprint(i) else trot_range(i)
	return max(1.0, r - _carry_less(i))

# 能到的格子：{cell: "creep"|"trot"|"sprint"}（不含原地）
func reachable(i: int) -> Dictionary:
	var out := {}
	if not active(i):
		return out
	var u: Dictionary = units[i]
	var costs: Dictionary = map.costs_from(u["pos"], max_move(i), blocks_for(i), terrain_cost(i), _impassable(i))
	var trot: float = max(1.0, trot_range(i) - _carry_less(i))
	for c in costs.keys():
		if c == u["pos"]:
			continue
		var cost: float = float(costs[c])
		out[c] = "creep" if cost <= float(map.move["creep_range"]) + 0.001 else ("trot" if cost <= trot + 0.001 else "sprint")
	return out

# 移動（第 1 步：直接移動；第 2 步起由回合流程呼叫）。回傳方式；不能到時回傳 ""。
func move_unit(i: int, cell: Vector2i) -> String:
	var r := reachable(i)
	if not r.has(cell):
		return ""
	var m: String = r[cell]
	var u: Dictionary = units[i]
	var from: Vector2i = u["pos"]
	u["pos"] = cell
	u["facing"] = TacticalGrid.dir_toward(from, cell)
	u["eating"] = false
	if str(u["species"]) == "wolf":
		_spend_breath(i, "breath_" + m)
	return m

func _spend_breath(i: int, key: String) -> void:
	var u: Dictionary = units[i]
	var v: float = float(map.move.get(key, 0.0))
	u["breath"] = clamp(float(u["breath"]) + v, 0.0, float(u["breath_max"]))

# --- 殘骸、叼肉、放下 ---

func at_carcass(i: int) -> bool:
	return not carcass.is_empty() and int(carcass["segments"]) > 0 and active(i) and map.adjacent(units[i]["pos"], carcass["pos"])

# 這隻能從殘骸拿哪幾種：piece 叼一塊（medium、1 段）、leg 撕一條腿（large、2～3 段）、whole 整個叼走（小殘骸）
func take_kinds(i: int) -> Array:
	if not at_carcass(i) or str(units[i]["carrying"]) != "":
		return []
	if bool(carcass["small_whole"]):
		return ["whole"]
	var out: Array = ["piece"]
	if int(carcass["segments"]) >= int(carcass["leg"][0]):
		out.append("leg")
	return out

# 拿到肉（成功與否由回合流程擲；這裡只處理結果）。回傳拿到的段數。
func take_from_carcass(i: int, kind: String) -> int:
	if not take_kinds(i).has(kind):
		return 0
	var u: Dictionary = units[i]
	var n := 1
	var size := "medium"
	match kind:
		"whole":
			n = int(carcass["segments"])
			size = str(carcass["whole_size"])
		"leg":
			n = mini(int(carcass["segments"]), rng.randi_range(int(carcass["leg"][0]), int(carcass["leg"][1])))
			size = "large"
	carcass["segments"] = int(carcass["segments"]) - n
	u["carrying"] = size
	u["carry_segments"] = n
	return n

# 放下叼著的肉（不花動作）：肉留在那一格
func drop_carried(i: int) -> void:
	var u: Dictionary = units[i]
	if str(u["carrying"]) == "":
		return
	drops.append({"pos": u["pos"], "segments": int(u["carry_segments"]), "size": str(u["carrying"])})
	u["carrying"] = ""
	u["carry_segments"] = 0

# 撿起放下的肉（站在那一格或旁邊、沒叼著東西）
func pick_up(i: int) -> bool:
	var u: Dictionary = units[i]
	if str(u["carrying"]) != "":
		return false
	for k in drops.size():
		var d: Dictionary = drops[k]
		if d["pos"] == u["pos"] or map.adjacent(d["pos"], u["pos"]):
			u["carrying"] = str(d["size"])
			u["carry_segments"] = int(d["segments"])
			drops.remove_at(k)
			return true
	return false

# --- 撤出地圖 ---

func can_exit(i: int) -> bool:
	return active(i) and map.on_edge(units[i]["pos"])

func exit_unit(i: int, reason: String = "retreated") -> void:
	if not can_exit(i) and reason == "retreated":
		return
	units[i]["out"] = true
	units[i]["out_reason"] = reason

# 你和伴侶帶出地圖的肉（段數）
func meat_taken() -> int:
	var n := 0
	for u in units:
		if str(u["side"]) != "enemy" and bool(u["out"]) and str(u["out_reason"]) == "retreated":
			n += int(u["carry_segments"])
	return n


# =====================================================================
# 第 2 步：回合流程
# =====================================================================

func _ev(kind: String, data: Dictionary = {}) -> void:
	var e := data.duplicate()
	e["kind"] = kind
	e["round"] = rounds
	events.append(e)

func _acfg(id: String) -> Dictionary:
	return cfg["actions"].get(id, {})

func _wcfg(id: String) -> Dictionary:
	return cfg["wolf"].get(id, {})

func _rot(d: Vector2i, steps: int) -> Vector2i:
	var k: int = TacticalGrid.DIRS.find(d)
	return TacticalGrid.DIRS[posmod(k + steps, 8)] if k >= 0 else d

func unit_at(c: Vector2i, except: int = -1) -> int:
	for i in units.size():
		if i != except and active(i) and units[i]["pos"] == c:
			return i
	return -1

func player_side(i: int) -> bool:
	return str(units[i]["side"]) != "enemy"

# 對手的動作範圍（照表態時的位置與面向）
func zone_cells(i: int, action: String, pos: Vector2i, facing: Vector2i, target: Vector2i = Vector2i(-1, -1)) -> Array:
	var a := _acfg(action)
	var out: Array = []
	match str(a.get("zone", "")):
		"front1":
			out.append(pos + facing)
		"front3":
			out.append(pos + facing)
			out.append(pos + _rot(facing, 1))
			out.append(pos + _rot(facing, -1))
		"around":
			for k in [-2, -1, 0, 1, 2]:
				out.append(pos + _rot(facing, k))
		"line":
			var c := pos
			for n in int(a.get("length", 3)):
				c += facing
				if not map.in_bounds(c) or _impassable(i).contains(map.terrain(c)):
					break
				out.append(c)
		"target2":
			if target.x >= 0:
				out.append(target)
				var beyond: Vector2i = target + TacticalGrid.dir_toward(pos, target)
				if map.in_bounds(beyond):
					out.append(beyond)
	return out.filter(func(c): return map.in_bounds(c))

# --- 對手表態（第 2 步的簡單規則；第 3 步換成 AI） ---

func begin_round() -> Dictionary:
	if done:
		return {}
	rounds += 1
	intents.clear()
	plans.clear()
	events.clear()
	for i in units.size():
		if active(i) and not player_side(i):
			intents[i] = _simple_intent(i)
	return intents

func _nearest_threat(i: int) -> int:
	var best := -1
	var bd := INF
	for k in units.size():
		if active(k) and player_side(k):
			var d: float = map.dist(units[i]["pos"], units[k]["pos"])
			if d < bd:
				bd = d
				best = k
	return best

func _actions_of(i: int) -> Array:
	return _opp_cfg(i).get("actions", [])

# intent：{action（實際）, looks（看起來像）, move（表態時要走到的格子）, facing, target（撲擊的格子）, zone}
func _simple_intent(i: int) -> Dictionary:
	var u: Dictionary = units[i]
	var acts := _actions_of(i)
	var t := _nearest_threat(i)
	var pos: Vector2i = u["pos"]
	var facing: Vector2i = u["facing"]
	var it := {"action": "turn", "move": pos, "facing": facing, "target": Vector2i(-1, -1)}
	if float(u["hp"]) < float(u["hp_max"]) * float(cfg["give_up"].get(str(u["species"]), 0.3)) \
			or float(u["stamina"]) <= 0.0:
		it["action"] = "flee"
	elif t >= 0:
		var tp: Vector2i = units[t]["pos"]
		var want := TacticalGrid.dir_toward(pos, tp)
		var turned := TacticalGrid.turn_toward(facing, want, int(_opp_cfg(i).get("turn_steps", -1)))
		var d: float = map.dist(pos, tp)
		if map.adjacent(pos, tp):
			it["facing"] = turned
			it["action"] = "swipe" if acts.has("swipe") and rng.randf() < 0.6 else "bite"
		elif acts.has("pounce") and d <= float(_acfg("pounce").get("range", 3)) + 0.5:
			it["facing"] = want
			it["action"] = "pounce"
			it["target"] = tp
		elif acts.has("charge") and turned == want and d <= float(_acfg("charge").get("length", 4)) + 0.5 and _clear_line(i, pos, want, tp):
			it["facing"] = want
			it["action"] = "bluff_charge" if acts.has("bluff_charge") and rng.randf() < 0.4 else "charge"
		elif bool(u["eating"]) and at_carcass(i) and d > 3.0:
			it["action"] = "eat"
		elif at_carcass(i):
			it["facing"] = turned
			it["action"] = "guard"
		else:
			# 走近一點（停在對方旁邊）
			var r := reachable(i)
			var best: Vector2i = pos
			var bd: float = d
			for c in r.keys():
				var dd: float = map.dist(c, tp)
				if dd >= 1.0 and dd < bd:
					bd = dd
					best = c
			it["action"] = "move"
			it["move"] = best
			it["facing"] = TacticalGrid.dir_toward(best, tp)
	it["looks"] = str(_acfg(str(it["action"])).get("looks_like", it["action"]))
	it["zone"] = zone_cells(i, str(it["action"]), it["move"], it["facing"], it["target"])
	return it

func _clear_line(i: int, from: Vector2i, d: Vector2i, to: Vector2i) -> bool:
	var c := from
	for n in 8:
		c += d
		if c == to:
			return true
		if not map.in_bounds(c) or _impassable(i).contains(map.terrain(c)) or unit_at(c) >= 0:
			return false
	return false

# --- 你方的計畫 ---

# plan：{move（格子，可省略）, action（bite/pounce/harass/take/guard/dodge/observe/wait/retreat/drop）, target（單位索引）, kind（take 的 piece/leg/whole）}
func plan(i: int, p: Dictionary) -> void:
	plans[i] = p

# 狼的動作機率（第 4 步會依知識改變「顯示」；實際機率只看這裡）。回傳 {chance, factors:[[鍵, 加減]]}
func wolf_chance(i: int, action: String, target: int, from: Vector2i, sprinted: bool = false, kind: String = "piece") -> Dictionary:
	var u: Dictionary = units[i]
	var w := _wcfg(action)
	var factors: Array = []
	var p := 0.0
	if action == "take":
		var e := enemy_index()
		var state := "away"
		if active(e):
			if bool(units[e]["eating"]):
				state = "eating"
			elif TacticalGrid.side_of(units[e]["pos"], units[e]["facing"], from) == "front" and map.dist(units[e]["pos"], from) <= 2.5:
				state = "facing"
		p = float(w.get(state, 0.5))
		factors.append(["take." + state, 0.0])
		var sk: float = (float(u["stats"]["skill"]) - 50.0) / float(w.get("skill_div", 200.0))
		p += sk
		factors.append(["skill", sk])
		if kind != "piece":
			p += float(w.get(kind, 0.0))
			factors.append(["take." + kind, float(w.get(kind, 0.0))])
		if active(e) and intents.has(e) and str(intents[e]["action"]) == "guard":
			p += float(w.get("guard", 0.0))
			factors.append(["take.guard", float(w.get("guard", 0.0))])
		return {"chance": clamp(p, 0.05, 0.95), "factors": factors}
	if target < 0 or not active(target):
		return {"chance": 0.0, "factors": factors}
	p = float(w.get("base", 0.5))
	var sk2: float = (float(u["stats"]["skill"]) - 50.0) / float(w.get("skill_div", 150.0))
	p += sk2
	factors.append(["skill", sk2])
	var side := TacticalGrid.side_of(units[target]["pos"], units[target]["facing"], from)
	var sv: float = float(w.get("side", {}).get(side, 0.0))
	p += sv
	factors.append(["side." + side, sv])
	if sprinted:
		p += float(w.get("after_sprint", 0.0))
		factors.append(["after_sprint", float(w.get("after_sprint", 0.0))])
	return {"chance": clamp(p, 0.05, 0.95), "factors": factors}

func _can_reach_target(i: int, action: String, target: int, from: Vector2i) -> bool:
	if target < 0 or not active(target):
		return false
	var d: float = map.dist(from, units[target]["pos"])
	if action == "pounce":
		return d <= float(_wcfg("pounce").get("range", 2)) + 0.5
	return map.adjacent(from, units[target]["pos"])

# --- 結算 ---

func resolve() -> Array:
	if done:
		return events
	for i in units.size():
		if active(i) and player_side(i) and not plans.has(i):
			plans[i] = {"action": "wait"}
	if mode == "alternate":
		_resolve_alternate()
	else:
		_resolve_sync()
	_check_end()
	return events

# 同步：雙方同時移動（搶同一格時速度快的先到）→ 變卦 → 照先後出手
func _resolve_sync() -> void:
	var sprinted := {}
	var targets := {}
	for i in plans.keys():
		if plans[i].has("move"):
			targets[i] = plans[i]["move"]
	for i in intents.keys():
		if intents[i]["move"] != units[i]["pos"]:
			targets[i] = intents[i]["move"]
	var order: Array = targets.keys()
	order.sort_custom(func(a, b): return float(units[a]["stats"].get("speed", 50)) > float(units[b]["stats"].get("speed", 50)))
	for i in order:
		var c: Vector2i = targets[i]
		if player_side(i):
			var m := move_unit(i, c)
			if m == "":
				_ev("blocked", {"who": i})
			else:
				sprinted[i] = m == "sprint"
				_ev("move", {"who": i, "to": c, "mode": m})
		else:
			if unit_at(c, i) < 0:
				units[i]["pos"] = c
				units[i]["eating"] = false
				_ev("move", {"who": i, "to": c})
			else:
				_ev("blocked", {"who": i})
	for i in intents.keys():
		units[i]["facing"] = intents[i]["facing"]
		_maybe_change(i)
	_act_in_order(sprinted)

# 預告後輪流：你方先動（移動＋出手），對手朝最近的威脅轉一次再出手
func _resolve_alternate() -> void:
	var sprinted := {}
	for i in plans.keys():
		if not active(i):
			continue
		if plans[i].has("move"):
			var m := move_unit(i, plans[i]["move"])
			sprinted[i] = m == "sprint"
			_ev("move" if m != "" else "blocked", {"who": i, "to": plans[i]["move"], "mode": m})
		_do_wolf_action(i, sprinted.get(i, false))
	for i in intents.keys():
		if not active(i):
			continue
		var it: Dictionary = intents[i]
		if it["move"] != units[i]["pos"] and unit_at(it["move"], i) < 0:
			units[i]["pos"] = it["move"]
			units[i]["eating"] = false
		var t := _nearest_threat(i)
		if t >= 0 and str(it["action"]) != "flee":
			var want := TacticalGrid.dir_toward(units[i]["pos"], units[t]["pos"])
			units[i]["facing"] = TacticalGrid.turn_toward(it["facing"], want, 1)
		else:
			units[i]["facing"] = it["facing"]
		_maybe_change(i)
		_do_enemy_action(i)

# 變卦：結算時臨時改成後退
func _maybe_change(i: int) -> void:
	var it: Dictionary = intents[i]
	if str(it["action"]) in ["flee", "eat", "move", "turn"]:
		return
	if rng.randf() < float(cfg["change_chance"].get(str(units[i]["species"]), 0.0)):
		it["changed_from"] = it["action"]
		it["action"] = "back_off"
		_ev("changed", {"who": i, "from": it["changed_from"]})

func _init_of(i: int) -> float:
	var a: String
	var bonus: float
	if player_side(i):
		a = str(plans[i].get("action", "wait"))
		bonus = float(_wcfg(a).get("init", 0))
	else:
		a = str(intents[i]["action"])
		bonus = float(_acfg(a).get("init", 0))
	var j: float = float(cfg["initiative"]["jitter"])
	return float(units[i]["stats"].get("speed", 50)) + bonus + rng.randf_range(-j, j)

func _act_in_order(sprinted: Dictionary) -> void:
	var actors: Array = []
	for i in plans.keys():
		actors.append(i)
	for i in intents.keys():
		actors.append(i)
	var ini := {}
	for i in actors:
		ini[i] = _init_of(i)
	actors.sort_custom(func(a, b): return float(ini[a]) > float(ini[b]))
	var acted := {}
	var interrupted := {}
	for i in actors:
		if not active(i) or interrupted.has(i):
			continue
		acted[i] = true
		var hit_units: Array
		if player_side(i):
			_do_wolf_action(i, sprinted.get(i, false))
			hit_units = []
		else:
			hit_units = _do_enemy_action(i)
		# 先打中的可能打斷還沒出手的
		for k in hit_units:
			if not acted.has(k) and rng.randf() < float(cfg["initiative"]["interrupt"]):
				interrupted[k] = true
				_ev("interrupted", {"who": k})

func _hurt(i: int, dmg: float, by: int) -> void:
	var u: Dictionary = units[i]
	u["hp"] = max(0.0, float(u["hp"]) - dmg)
	_ev("hit", {"who": by, "target": i, "dmg": dmg})
	if player_side(i) and float(u["hp"]) <= 0.0:
		drop_carried(i)
		u["out"] = true
		u["out_reason"] = "knocked"
		_ev("knocked", {"who": i})

# 對手出手：打範圍裡的單位。回傳被打中的單位。
func _do_enemy_action(i: int) -> Array:
	var it: Dictionary = intents[i]
	var a: String = str(it["action"])
	var u: Dictionary = units[i]
	var hit_units: Array = []
	match a:
		"flee":
			u["out"] = true
			u["out_reason"] = "fled"
			_ev("fled", {"who": i})
			return hit_units
		"back_off":
			var away: Vector2i = u["pos"] - u["facing"]
			if map.in_bounds(away) and unit_at(away, i) < 0 and not _impassable(i).contains(map.terrain(away)) and not blocks_for(i).has(away):
				u["pos"] = away
			_ev("back_off", {"who": i})
			return hit_units
		"eat":
			if at_carcass(i):
				carcass["segments"] = int(carcass["segments"]) - 1
				u["eating"] = true
				_ev("eat", {"who": i, "left": int(carcass["segments"])})
			return hit_units
		"move", "turn":
			return hit_units
	var ac := _acfg(a)
	var zone: Array
	if str(ac.get("zone", "")) == "line":
		zone = zone_cells(i, a, u["pos"], u["facing"])
		# 衝撞：一直線衝過去，停在第一個撞到的單位前並打中牠；假衝衝一兩格就停
		var last: Vector2i = u["pos"]
		var struck := -1
		for c in zone:
			var k := unit_at(c, i)
			if k >= 0:
				struck = k
				break
			if blocks_for(i).has(c):
				break
			last = c
		u["pos"] = last
		_ev(a, {"who": i, "to": last})
		if struck >= 0 and float(ac.get("hit", 0.0)) > 0.0:
			if _roll_hit(i, struck, ac):
				hit_units.append(struck)
		return hit_units
	zone = zone_cells(i, a, u["pos"], u["facing"], it.get("target", Vector2i(-1, -1)))
	if a == "pounce" and zone.size() > 0:
		# 撲擊：落在目標旁邊
		var land: Vector2i = zone[0] - TacticalGrid.dir_toward(u["pos"], zone[0])
		if map.in_bounds(land) and unit_at(land, i) < 0 and not blocks_for(i).has(land) and not _impassable(i).contains(map.terrain(land)):
			u["pos"] = land
	_ev(a, {"who": i, "zone": zone})
	for c in zone:
		var k := unit_at(c, i)
		if k >= 0 and player_side(k) and _roll_hit(i, k, ac):
			hit_units.append(k)
	return hit_units

func _roll_hit(i: int, k: int, ac: Dictionary) -> bool:
	var p: float = float(ac.get("hit", 0.8))
	if str(plans.get(k, {}).get("action", "")) == "dodge":
		p *= float(cfg["wolf"]["dodge_mult"])
	if rng.randf() >= p:
		_ev("miss", {"who": i, "target": k})
		return false
	var dr: Array = ac.get("dmg", {}).get(str(units[i]["species"]), [10, 20])
	_hurt(k, float(rng.randi_range(int(dr[0]), int(dr[1]))), i)
	return true

# 狼出手：打目標；目標不在攻擊距離內就撲空
func _do_wolf_action(i: int, sprinted: bool) -> void:
	var p: Dictionary = plans.get(i, {})
	var a: String = str(p.get("action", "wait"))
	var u: Dictionary = units[i]
	var w := _wcfg(a)
	if w.has("breath") and a != "wait":
		u["breath"] = clamp(float(u["breath"]) + float(w["breath"]), 0.0, float(u["breath_max"]))
	match a:
		"wait", "observe":
			if a == "wait":
				u["breath"] = clamp(float(u["breath"]) + float(w.get("breath", 0.0)), 0.0, float(u["breath_max"]))
			_ev(a, {"who": i})
		"dodge", "guard":
			_ev(a, {"who": i})
		"drop":
			drop_carried(i)
			_ev("drop", {"who": i})
		"retreat":
			if can_exit(i):
				exit_unit(i)
				_ev("retreat", {"who": i, "meat": int(u["carry_segments"])})
		"take":
			var kind: String = str(p.get("kind", "piece"))
			if not take_kinds(i).has(kind):
				_ev("take_fail", {"who": i, "why": "cannot"})
				return
			var ch: float = float(wolf_chance(i, "take", -1, u["pos"], sprinted, kind)["chance"])
			if rng.randf() < ch:
				var n := take_from_carcass(i, kind)
				_ev("take", {"who": i, "segments": n, "kind": kind})
			else:
				_ev("take_fail", {"who": i, "why": "missed"})
		"bite", "pounce", "harass":
			if str(u["carrying"]) != "":
				_ev("cannot", {"who": i, "why": "carrying"})
				return
			var t: int = int(p.get("target", enemy_index()))
			if not _can_reach_target(i, a, t, u["pos"]):
				_ev("whiff", {"who": i, "target": t})
				return
			var ch2: float = float(wolf_chance(i, a, t, u["pos"], sprinted)["chance"])
			u["facing"] = TacticalGrid.dir_toward(u["pos"], units[t]["pos"])
			if rng.randf() >= ch2:
				_ev("whiff", {"who": i, "target": t})
				return
			var dr: Array = w.get("dmg", [8, 14])
			var dmg: float = float(rng.randi_range(int(dr[0]), int(dr[1]))) * float(u["stats"]["strength"]) / 60.0
			units[t]["hp"] = max(0.0, float(units[t]["hp"]) - dmg)
			units[t]["stamina"] = max(0.0, float(units[t].get("stamina", 0.0)) - float(w.get("drain", dmg * 0.5)))
			units[t]["eating"] = false
			_ev("bite", {"who": i, "target": t, "dmg": dmg, "kind": a})
			if a == "harass":
				# 咬一下就退一格
				var away: Vector2i = u["pos"] + (u["pos"] - units[t]["pos"]).sign()
				if map.in_bounds(away) and not blocks_for(i).has(away) and not _impassable(i).contains(map.terrain(away)):
					u["pos"] = away

func _check_end() -> void:
	var e := enemy_index()
	var any_player := false
	for i in units.size():
		if player_side(i) and active(i):
			any_player = true
	if not active(e):
		done = true
		outcome = "enemy_left"
	elif not active(0):
		done = true
		outcome = "knocked" if str(units[0]["out_reason"]) == "knocked" else "retreated"
	elif not any_player:
		done = true
		outcome = "retreated"
	elif rounds >= int(cfg.get("max_rounds", 30)):
		done = true
		outcome = "timeout"
	if done:
		_ev("end", {"outcome": outcome, "meat": meat_taken()})
