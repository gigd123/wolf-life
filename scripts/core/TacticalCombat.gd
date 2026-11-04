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
# 第 3 步：對手的 AI（_ai_intent 打分）：注意力（被咬看咬牠的、守食物看最靠近殘骸的）、守食物、假衝（守食物時常見）、
#   背靠岩壁（被圍、受傷）、美洲獅上樹（受傷或被圍；上樹＝離開，殘骸留下）、放棄（血量、耐心、殘骸吃光）、個性（bold）。
# 第 4 步：資訊等級。預告依「見過這個動作幾次＋感知－距離－視線－夜晚＋觀察」分模糊／部分／明確／熟悉（telegraph）；
#   狼的機率依這種動物的經驗顯示成風險高低＋範圍／範圍／約略／精確（display_chance），實際機率不變；看到牠出手就記一次（_witness）。
# 第 5 步：伴侶的簡化合作（ally_plan）：指令牽制、叼肉、退開、自動；血量低自己撤；叼到肉就往邊緣撤；避開看得到的預告範圍。

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
# 第 4 步：知識（「物種|動作」→ {count 0～3, category, source}；category／source 是給之後的傳承預留的欄位）、觀察
var knowledge := {}
var night := false
var observed := {} # 這一回合選了觀察的單位 → 下一回合資訊高一級
var obs_bonus := {} # 這一回合的觀察加成（上一回合觀察過）

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
	observed.clear()
	obs_bonus.clear()
	night = bool(opts.get("night", false))
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
		"stamina": float(cfg["enemy_stamina"].get(str(o["id"]), 80.0)), "stamina_max": float(cfg["enemy_stamina"].get(str(o["id"]), 80.0)),
		"attention": -1, "bitten_by": -1})
	var br: Array = cfg["ai"]["bold"].get(str(o["id"]), [0.0, 0.0])
	units.back()["bold"] = rng.randf_range(float(br[0]), float(br[1]))
	knowledge.clear()
	for act in od["actions"]:
		knowledge[str(o["id"]) + "|" + str(act)] = {"count": knowledge_level, "category": "experience", "source": "self"}
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
		"carrying": "", "carry_segments": 0, "out": false, "out_reason": "", "eating": false, "command": "auto"}

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
	obs_bonus = observed.duplicate()
	observed.clear()
	for i in units.size():
		if active(i) and not player_side(i):
			_drain_patience(i)
			intents[i] = _ai_intent(i)
			intents[i]["seen"] = telegraph(0, i)
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

# intent：{action（實際）, looks（看起來像）, move（表態時要走到的格子）, facing, target（撲擊的格子）, zone, why}
# 第 3 步：AI（打分）。對手只會用 opponents.*.actions 裡的動作。
func _ai_cfg() -> Dictionary:
	return cfg["ai"]

# 注意力：被咬就看咬牠的；有殘骸時看最靠近殘骸的；否則看最近的
func _update_attention(i: int) -> int:
	var u: Dictionary = units[i]
	var b: int = int(u.get("bitten_by", -1))
	u["just_bitten"] = false
	if b >= 0 and active(b):
		u["attention"] = b
		u["bitten_by"] = -1
		u["just_bitten"] = true
		return b
	var cur: int = int(u.get("attention", -1))
	if not carcass.is_empty() and int(carcass["segments"]) > 0 and map.dist(u["pos"], carcass["pos"]) <= 2.5:
		var best := -1
		var bd := INF
		for k in units.size():
			if active(k) and player_side(k):
				var d: float = map.dist(units[k]["pos"], carcass["pos"])
				if d < bd:
					bd = d
					best = k
		if best >= 0 and bd <= 2.5:
			u["attention"] = best
			return best
	if cur >= 0 and active(cur) and map.dist(u["pos"], units[cur]["pos"]) <= 3.0:
		return cur
	u["attention"] = _nearest_threat(i)
	return int(u["attention"])

# 圍住：兩隻以上在 2 格內、而且在牠不同的兩側（前／側／後）
func surrounded(i: int) -> bool:
	var sides := {}
	var n := 0
	for k in units.size():
		if active(k) and player_side(k) and map.dist(units[i]["pos"], units[k]["pos"]) <= 2.5:
			n += 1
			var sd := TacticalGrid.side_of(units[i]["pos"], units[i]["facing"], units[k]["pos"])
			var lr: int = signi(int(round(Vector2(units[k]["pos"] - units[i]["pos"]).cross(Vector2(units[i]["facing"])))))
			sides[sd + str(lr)] = true
	return n >= 2 and sides.size() >= 2

func _drain_patience(i: int) -> void:
	var u: Dictionary = units[i]
	var ai := _ai_cfg()
	if surrounded(i):
		u["stamina"] = max(0.0, float(u["stamina"]) - float(ai["surrounded_drain"]))
	var t := _nearest_threat(i)
	var near: bool = t >= 0 and map.dist(u["pos"], units[t]["pos"]) <= 2.5
	if carcass.is_empty() and not near and rounds > 1:
		u["stamina"] = max(0.0, float(u["stamina"]) - float(ai["idle_drain"]))

func _near_terrain(c: Vector2i, chars: String, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for y in range(c.y - radius, c.y + radius + 1):
		for x in range(c.x - radius, c.x + radius + 1):
			var q := Vector2i(x, y)
			if map.in_bounds(q) and chars.contains(map.terrain(q)):
				var d: float = map.dist(c, q)
				if d < bd:
					bd = d
					best = q
	return best

func _adjacent_to_terrain(c: Vector2i, chars: String) -> bool:
	for d in TacticalGrid.DIRS:
		if chars.contains(map.terrain(c + d)):
			return true
	return false

# 往 goal 走（停在旁邊）：回傳可以走到、離 goal 最近的格子
func _step_toward(i: int, goal: Vector2i, stop_adjacent := true) -> Vector2i:
	var r := reachable(i)
	var pos: Vector2i = units[i]["pos"]
	var best: Vector2i = pos
	var bd: float = map.dist(pos, goal)
	for c in r.keys():
		var d: float = map.dist(c, goal)
		if (not stop_adjacent or d >= 1.0) and d < bd - 0.01:
			bd = d
			best = c
	return best

func _ai_intent(i: int) -> Dictionary:
	var u: Dictionary = units[i]
	var ai := _ai_cfg()
	var sc: Dictionary = ai["scores"]
	var acts := _actions_of(i)
	var sp: String = str(u["species"])
	var bold: float = float(u.get("bold", 0.0))
	var pos: Vector2i = u["pos"]
	var facing: Vector2i = u["facing"]
	var turn_steps: int = int(_opp_cfg(i).get("turn_steps", -1))
	var hp_ratio: float = float(u["hp"]) / max(1.0, float(u["hp_max"]))
	var has_food: bool = not carcass.is_empty() and int(carcass["segments"]) > 0
	var at_food: bool = has_food and map.adjacent(pos, carcass["pos"])
	var nothing := Vector2i(-1, -1)
	var t := _update_attention(i)
	# 被咬（或肉被叼走）的那一回合可以猛然轉身
	if bool(u.get("just_bitten", false)):
		turn_steps = int(_opp_cfg(i).get("turn_when_bitten", turn_steps))
	# 放棄：血量低、耐心用完、殘骸吃光了
	var give: float = float(cfg["give_up"].get(sp, 0.3)) * (1.0 - bold * 0.3)
	if hp_ratio < give or float(u["stamina"]) <= 0.0:
		return _intent(i, "flee", pos, facing, nothing, "hurt" if hp_ratio < give else "patience")
	if not carcass.is_empty() and int(carcass["segments"]) <= 0 and t >= 0 and map.dist(pos, units[t]["pos"]) > 2.0:
		return _intent(i, "flee", pos, facing, nothing, "food_gone")
	var cands: Array = [] # [分數, action, move, facing, target, why]
	var noise: float = float(ai["noise"])
	if t >= 0:
		var tp: Vector2i = units[t]["pos"]
		var d: float = map.dist(pos, tp)
		var want := TacticalGrid.dir_toward(pos, tp)
		var turned := TacticalGrid.turn_toward(facing, want, turn_steps)
		var n_threats := 0
		for k in units.size():
			if active(k) and player_side(k) and map.dist(pos, units[k]["pos"]) <= 3.0:
				n_threats += 1
		var food_bonus: float = float(ai["stake_food"]) if at_food else 1.0
		# 剛被咬：先回頭對付咬牠的
		var bitten_bonus: float = float(ai.get("bitten_bonus", 3.0)) if bool(u.get("just_bitten", false)) else 0.0
		# 叼走牠的肉的那隻：追
		var chase: float = float(ai.get("chase_bonus", 3.0)) if str(units[t]["carrying"]) != "" else 0.0
		# 攻擊：轉過去之後對方在範圍裡
		for a in ["swipe", "bite"]:
			if acts.has(a) and zone_cells(i, a, pos, turned).has(tp):
				cands.append([float(sc["attack"]) * food_bonus + bold * 2.0 + bitten_bonus + chase - (1.5 if a == "bite" and acts.has("swipe") else 0.0), a, pos, turned, nothing, "attack"])
		if acts.has("pounce") and d >= 1.5 and d <= float(_acfg("pounce").get("range", 3)) + 0.5:
			cands.append([float(sc["pounce"]) + bold * 2.0 - (1.5 if n_threats >= 2 else 0.0), "pounce", pos, want, tp, "pounce"])
		if acts.has("charge") and turned == want and d >= 1.5 and d <= float(_acfg("charge").get("length", 4)) + 0.5 and _clear_line(i, pos, want, tp):
			# 守著食物時多半只是假衝嚇你（記述：灰熊在殘骸旁常虛張聲勢）
			cands.append([float(sc["charge"]) + bold * 2.0 + chase - (float(ai.get("charge_food_less", 1.5)) if has_food and chase == 0.0 else 0.0), "charge", pos, want, nothing, "charge"])
			if acts.has("bluff_charge"):
				cands.append([float(sc["bluff_guard"] if has_food else sc["bluff_open"]) - bold * 1.5, "bluff_charge", pos, want, nothing, "bluff"])
		# 沒辦法馬上打：轉身面對
		if turned != facing and not zone_cells(i, "swipe", pos, facing).has(tp):
			cands.append([float(sc["turn"]) + (1.0 if d <= 2.0 else 0.0) + bitten_bonus, "turn", pos, turned, nothing, "turn"])
		# 守食物
		if at_food and acts.has("guard") and d <= 3.0:
			cands.append([float(sc["guard"]) + (1.0 if n_threats >= 2 else 0.0), "guard", pos, turned, nothing, "guard"])
		# 背靠岩壁：被圍、受傷
		if acts.has("back_to_wall") and (n_threats >= 2 or hp_ratio < 0.6) and not _adjacent_to_terrain(pos, "c"):
			var wall := _near_terrain(pos, "c", int(ai["wall_search"]))
			if wall.x >= 0:
				var to := _step_toward(i, wall, true)
				if to != pos:
					cands.append([float(sc["back_to_wall"]) + (1.5 if surrounded(i) else 0.0) - bold, "back_to_wall", to, TacticalGrid.dir_toward(wall, to), nothing, "wall"])
		# 上樹（美洲獅）：受傷或被圍
		if acts.has("climb") and (hp_ratio < float(ai["climb_hurt"]) or n_threats >= 2):
			if _adjacent_to_terrain(pos, "T"):
				cands.append([float(sc["climb"]) - bold * 2.0, "climb", pos, facing, nothing, "climb"])
			else:
				var tree := _near_terrain(pos, "T", int(ai["climb_search"]))
				if tree.x >= 0:
					var to2 := _step_toward(i, tree, true)
					if to2 != pos:
						cands.append([float(sc["climb"]) - 1.5 - bold * 2.0, "move", to2, TacticalGrid.dir_toward(pos, tree), nothing, "to_tree"])
		# 後退
		if acts.has("back_off") and (n_threats >= 2 or hp_ratio < 0.5):
			cands.append([float(sc["back_off"]) - bold, "back_off", pos, facing, nothing, "back_off"])
		# 追叼走肉的
		if chase > 0.0 and d > 1.5:
			var toc := _step_toward(i, tp, true)
			if toc != pos:
				cands.append([float(sc["approach_food"]) + chase, "move", toc, TacticalGrid.dir_toward(toc, tp), nothing, "chase"])
		# 沒有殘骸：靠近（大膽的）或觀望
		if not has_food and d > 1.5:
			var to3 := _step_toward(i, tp, true)
			if to3 != pos:
				cands.append([float(sc["approach_threat"]) + bold * 2.0, "move", to3, TacticalGrid.dir_toward(to3, tp), nothing, "approach"])
		# 在殘骸旁、威脅還遠：吃
		if at_food and acts.has("eat"):
			var safe: bool = d > float(ai["eat_safe_dist"])
			cands.append([float(sc["eat"]) if safe else 1.0, "eat", pos, facing, nothing, "eat"])
	elif at_food and acts.has("eat"):
		cands.append([float(sc["eat"]), "eat", pos, facing, nothing, "eat"])
	# 走向殘骸
	if has_food and not at_food:
		var to4 := _step_toward(i, carcass["pos"], true)
		if to4 != pos:
			cands.append([float(sc["approach_food"]), "move", to4, TacticalGrid.dir_toward(to4, carcass["pos"]), nothing, "to_food"])
	cands.append([float(sc["idle"]), "turn", pos, facing, nothing, "idle"])
	var best: Array = cands[0]
	var bs := -INF
	for c in cands:
		var v: float = float(c[0]) + rng.randf_range(0.0, noise)
		if v > bs:
			bs = v
			best = c
	return _intent(i, str(best[1]), best[2], best[3], best[4], str(best[5]))

func _intent(i: int, action: String, move: Vector2i, facing: Vector2i, target: Vector2i, why: String) -> Dictionary:
	var it := {"action": action, "move": move, "facing": facing, "target": target, "why": why}
	it["looks"] = str(_acfg(action).get("looks_like", action))
	it["zone"] = zone_cells(i, action, move, facing, target)
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
func wolf_chance(i: int, action: String, target: int, from: Vector2i, sprinted: bool = false, kind: String = "piece", moved: bool = false) -> Dictionary:
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
			elif int(units[e].get("attention", -1)) == i and map.dist(units[e]["pos"], from) <= 2.0:
				# 牠沒在吃、正盯著你：從側面靠近牠也看得到
				state = "facing"
		p = float(w.get(state, 0.5))
		factors.append(["take." + state, 0.0])
		var sk: float = (float(u["stats"]["skill"]) - 50.0) / float(w.get("skill_div", 200.0))
		p += sk
		factors.append(["skill", sk])
		if kind != "piece":
			p += float(w.get(kind, 0.0))
			factors.append(["take." + kind, float(w.get(kind, 0.0))])
		if moved:
			p += float(w.get("moved", 0.0))
			factors.append(["take.moved", float(w.get("moved", 0.0))])
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
			plans[i] = ally_plan(i) if str(units[i]["side"]) == "ally" else {"action": "wait"}
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
		_react_turn(i)
		_maybe_change(i)
	_act_in_order(sprinted)

# 出手前朝牠盯著的（或最近的）轉一次：灰熊 45°、美洲獅不限（同步與輪流都一樣；不然繞到背後就永遠打不到）
func _react_turn(i: int) -> void:
	var it: Dictionary = intents[i]
	if not ATTACKS.has(str(it["action"])) or str(it["action"]) in ["charge", "bluff_charge", "pounce"]:
		return
	var t: int = int(units[i].get("attention", -1))
	if t < 0 or not active(t):
		t = _nearest_threat(i)
	if t < 0 or map.dist(units[i]["pos"], units[t]["pos"]) > 1.5:
		return
	var want := TacticalGrid.dir_toward(units[i]["pos"], units[t]["pos"])
	units[i]["facing"] = TacticalGrid.turn_toward(units[i]["facing"], want, int(_opp_cfg(i).get("turn_steps", -1)))

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
		units[i]["facing"] = it["facing"]
		_react_turn(i)
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
	# 叼著肉被打中：有機會把肉甩掉
	if player_side(i) and str(u["carrying"]) != "" and rng.randf() < float(cfg["wolf"].get("drop_on_hit", 0.5)):
		drop_carried(i)
		_ev("dropped", {"who": i})
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
			u["out_reason"] = str(it.get("why", "fled"))
			_ev("fled", {"who": i, "why": str(it.get("why", ""))})
			return hit_units
		"back_off":
			var away: Vector2i = u["pos"] - u["facing"]
			if map.in_bounds(away) and unit_at(away, i) < 0 and not _impassable(i).contains(map.terrain(away)) and not blocks_for(i).has(away):
				u["pos"] = away
			_ev("back_off", {"who": i})
			return hit_units
		"eat":
			if at_carcass(i):
				u["eat_count"] = int(u.get("eat_count", 0)) + 1
				if int(u["eat_count"]) % int(_ai_cfg().get("eat_per_segment", 1)) == 0:
					carcass["segments"] = int(carcass["segments"]) - 1
				u["eating"] = true
				_ev("eat", {"who": i, "left": int(carcass["segments"])})
			return hit_units
		"move", "turn", "back_to_wall":
			if a == "back_to_wall":
				_ev("back_to_wall", {"who": i})
			return hit_units
		"climb":
			u["out"] = true
			u["out_reason"] = "climbed"
			_ev("climbed", {"who": i})
			return hit_units
	var ac := _acfg(a)
	var zone: Array
	_track(i, a)
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
		_witness(i, a)
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
	_witness(i, a)
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
			if a == "observe":
				observed[i] = true
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
			var ch: float = float(wolf_chance(i, "take", -1, u["pos"], sprinted, kind, plans.get(i, {}).has("move"))["chance"])
			if rng.randf() < ch:
				var n := take_from_carcass(i, kind)
				_ev("take", {"who": i, "segments": n, "how": kind})
				# 肉被叼走：對手的注意力轉到小偷，下一回合可以猛然轉身
				var e := enemy_index()
				if active(e):
					units[e]["bitten_by"] = i
					units[e]["eating"] = false
			else:
				_ev("take_fail", {"who": i, "why": "missed"})
				# 叼失敗：牠發現了，下一回合可以猛然轉身對付你
				var e2 := enemy_index()
				if active(e2):
					units[e2]["bitten_by"] = i
					units[e2]["eating"] = false
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
			units[t]["bitten_by"] = i
			_ev("bite", {"who": i, "target": t, "dmg": dmg, "how": a})
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


# =====================================================================
# 第 4 步：資訊等級與機率顯示
# =====================================================================

func _icfg() -> Dictionary:
	return cfg["info"]

func know_count(species: String, action: String) -> int:
	return int(knowledge.get(species + "|" + action, {}).get("count", 0))

# 這種動物的經驗（見過的動作次數平均，四捨五入）
func species_experience(species: String) -> int:
	var n := 0
	var tot := 0
	for k in knowledge.keys():
		if str(k).begins_with(species + "|"):
			n += 1
			tot += int(knowledge[k]["count"])
	return int(round(float(tot) / max(1, n)))

func learn(species: String, action: String) -> void:
	var key := species + "|" + action
	var e: Dictionary = knowledge.get(key, {"count": 0, "category": "experience", "source": "self"})
	if int(e["count"]) < 3:
		e["count"] = int(e["count"]) + 1
		_ev("learned", {"key": key, "count": int(e["count"])})
	knowledge[key] = e

# 看到牠出手：距離內、視線沒被擋的你方單位記一次（假衝：衝到一半停下時才知道是假的）
func _witness(i: int, action: String) -> void:
	if not active(0):
		return
	if map.dist(units[0]["pos"], units[i]["pos"]) <= float(_icfg()["learn_dist"]) and line_of_sight(units[0]["pos"], units[i]["pos"]):
		learn(str(units[i]["species"]), action)

func line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var block: String = str(_icfg()["los_block"])
	var n: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for k in range(1, n):
		var p := Vector2(a).lerp(Vector2(b), float(k) / float(n))
		var c := Vector2i(int(round(p.x)), int(round(p.y)))
		if c != a and c != b and block.contains(map.terrain(c)):
			return false
	return true

# 資訊等級：0 模糊、1 部分、2 明確、3 熟悉
func info_level(viewer: int, e: int, action: String) -> int:
	var ic := _icfg()
	var lv: int = int(ic["base"])
	var k := know_count(str(units[e]["species"]), action)
	if k >= int(ic["know_2"]):
		lv += 1
	if k >= int(ic["know_3"]):
		lv += 1
	var per: float = float(units[viewer]["stats"].get("perception", 50))
	if per >= float(ic["perception_good"]):
		lv += 1
	elif per < float(ic["perception_poor"]):
		lv -= 1
	if map.dist(units[viewer]["pos"], units[e]["pos"]) > float(ic["far"]):
		lv -= 1
	if not line_of_sight(units[viewer]["pos"], units[e]["pos"]):
		lv -= 1
	if night:
		lv -= 1
	if obs_bonus.has(viewer):
		lv += 1
	return clampi(lv, 0, 3)

const ATTACKS := ["swipe", "charge", "bluff_charge", "pounce", "bite", "guard"]

# 預告：{level, text（key 尾）, zone（顯示的範圍）, feint_hint, attack}
func telegraph(viewer: int, e: int) -> Dictionary:
	var it: Dictionary = intents[e]
	var looks: String = str(it.get("looks", it["action"]))
	var lv := info_level(viewer, e, looks)
	var attack: bool = ATTACKS.has(looks)
	var out := {"level": lv, "zone": [], "feint_hint": false, "attack": attack, "looks": looks}
	if lv == 0:
		out["text"] = "vague"
		return out
	if lv == 1:
		out["text"] = "partial." + ("attack" if attack else str(it["action"]))
		if attack:
			# 部分：顯示牠可能用的攻擊範圍的聯集
			var z := {}
			for a in _actions_of(e):
				if ATTACKS.has(a) and a != "bluff_charge":
					for c in zone_cells(e, a, it["move"], it["facing"], it.get("target", Vector2i(-1, -1))):
						z[c] = true
			out["zone"] = z.keys()
		return out
	out["text"] = "clear." + looks
	out["zone"] = zone_cells(e, looks, it["move"], it["facing"], it.get("target", Vector2i(-1, -1)))
	var ic := _icfg()
	# 看不看得出假動作：看「假動作」本身見過幾次（認得牠會虛張聲勢），不是看衝撞
	var bluff: bool = str(it["action"]) != looks
	var kb: int = know_count(str(units[e]["species"]), str(it["action"]) if bluff else "bluff_charge")
	var p: float = float(ic["feint_hint"][kb]) if bluff else float(ic["false_hint"][kb])
	# 用固定的種子擲（同一回合畫面重算時結果不變）
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, rounds, e])
	out["feint_hint"] = r.randf() < p
	return out

# 機率顯示（實際機率不變）：{tier, text, lo, hi, risk}
func display_chance(viewer: int, chance: float, species: String) -> Dictionary:
	var ic := _icfg()
	var tier: int = species_experience(species) + (1 if obs_bonus.has(viewer) else 0)
	tier = clampi(tier, 0, 3)
	var risk := "low"
	if chance < float(ic["risk"]["high"]):
		risk = "high"
	elif chance < float(ic["risk"]["mid"]):
		risk = "mid"
	var out := {"tier": tier, "risk": risk, "lo": chance, "hi": chance}
	match tier:
		0, 1:
			var w: float = float(ic["range0"] if tier == 0 else ic["range1"])
			# 範圍不要剛好以實際值為中心（不然一看就知道），往一邊偏一點，但一定包含實際值
			var r := RandomNumberGenerator.new()
			r.seed = hash([rng.seed, rounds, viewer, snappedf(chance, 0.01)])
			var shift: float = r.randf_range(-w * 0.6, w * 0.6)
			out["lo"] = clamp(snappedf(chance - w + shift, 0.05), 0.0, chance)
			out["hi"] = clamp(snappedf(chance + w + shift, 0.05), chance, 1.0)
			# 範圍至少 2w 寬（被 0、1 夾到時往另一邊補）
			while float(out["hi"]) - float(out["lo"]) < w * 2.0 - 0.001:
				if float(out["hi"]) < 1.0:
					out["hi"] = min(1.0, float(out["hi"]) + 0.05)
				elif float(out["lo"]) > 0.0:
					out["lo"] = max(0.0, float(out["lo"]) - 0.05)
				else:
					break
		2:
			var a: float = snappedf(chance, float(ic["round2"]))
			out["lo"] = a
			out["hi"] = a
	return out

# 畫面與模擬用：這隻從 from 出手時，各動作的實際機率與顯示
func action_options(i: int, from: Vector2i = Vector2i(-1, -1), sprinted := false) -> Array:
	if from.x < 0:
		from = units[i]["pos"]
	var e := enemy_index()
	var sp: String = str(units[e]["species"]) if e >= 0 else ""
	var out: Array = []
	var carrying: bool = str(units[i]["carrying"]) != ""
	for a in ["bite", "pounce", "harass"]:
		if active(e) and not carrying and (map.adjacent(from, units[e]["pos"]) or (a == "pounce" and map.dist(from, units[e]["pos"]) <= float(_wcfg("pounce").get("range", 2)) + 0.5)):
			var c: Dictionary = wolf_chance(i, a, e, from, sprinted)
			out.append({"id": a, "chance": c["chance"], "factors": c["factors"], "show": display_chance(i, float(c["chance"]), sp)})
	var save_pos: Vector2i = units[i]["pos"]
	units[i]["pos"] = from
	for k in take_kinds(i):
		var c2: Dictionary = wolf_chance(i, "take", -1, from, sprinted, k, from != save_pos)
		out.append({"id": "take", "kind": k, "chance": c2["chance"], "factors": c2["factors"], "show": display_chance(i, float(c2["chance"]), sp)})
	units[i]["pos"] = save_pos
	for a2 in ["dodge", "observe", "wait"]:
		out.append({"id": a2})
	if carrying:
		out.append({"id": "drop"})
	if map.on_edge(from):
		out.append({"id": "retreat"})
	return out

# 這一格在不在你看得到的預告範圍裡（畫面用來標危險的格子）
func in_shown_zone(c: Vector2i) -> bool:
	for e in intents.keys():
		var seen: Dictionary = intents[e].get("seen", {})
		if (seen.get("zone", []) as Array).has(c):
			return true
	return false


# =====================================================================
# 第 5 步：伴侶的簡化合作
# =====================================================================

const COMMANDS := ["auto", "harass", "take", "back"]

func set_command(i: int, cmd: String) -> void:
	if COMMANDS.has(cmd):
		units[i]["command"] = cmd

# 這一回合實際照哪個指令做（auto 時依局勢；血量低、叼著肉時另外處理）
func ally_mode(i: int) -> String:
	var u: Dictionary = units[i]
	var ac: Dictionary = cfg["ally"]
	if float(u["hp"]) < float(u["hp_max"]) * float(ac["retreat_hp"]):
		return "escape"
	if str(u["carrying"]) != "":
		return "carry"
	var cmd: String = str(u["command"])
	if cmd != "auto":
		if cmd == "take" and (carcass.is_empty() or int(carcass["segments"]) <= 0):
			return "harass"
		return cmd
	var e := enemy_index()
	if not active(e):
		return "back"
	var watching_me: bool = int(units[e].get("attention", -1)) == i and map.dist(units[e]["pos"], u["pos"]) <= 3.0
	if not carcass.is_empty() and int(carcass["segments"]) > 0 and not watching_me:
		return "take"
	if watching_me:
		return "back"
	return "harass"

# 看得到的預告範圍（伴侶自己的資訊等級）
func _shown_zone_for(viewer: int) -> Dictionary:
	var z := {}
	for e in intents.keys():
		if not active(e):
			continue
		for c in telegraph(viewer, e).get("zone", []):
			z[c] = true
	return z

# 從可到的格子（含原地）裡挑最接近 goal、不在範圍裡的
func _ally_move(i: int, goal: Vector2i, zone: Dictionary, stop_adjacent := false, avoid_front := Vector2i(-1, -1)) -> Vector2i:
	var u: Dictionary = units[i]
	var r := reachable(i)
	r[u["pos"]] = "stay"
	var ac: Dictionary = cfg["ally"]
	var best: Vector2i = u["pos"]
	var bs := -INF
	var e := enemy_index()
	for c in r.keys():
		var d: float = map.dist(c, goal)
		if stop_adjacent and d < 0.5:
			continue
		var sc: float = -d
		if zone.has(c):
			sc -= float(ac["zone_penalty"])
		if str(r[c]) == "sprint":
			sc -= 0.5
		if avoid_front.x >= 0 and active(e) and TacticalGrid.side_of(units[e]["pos"], units[e]["facing"], c) == "front" and map.dist(units[e]["pos"], c) <= 2.5:
			sc -= 3.0
		if sc > bs:
			bs = sc
			best = c
	return best

func _nearest_edge_away(i: int) -> Vector2i:
	var u: Dictionary = units[i]
	var e := enemy_index()
	var best: Vector2i = u["pos"]
	var bs := -INF
	for y in map.height:
		for x in map.width:
			var c := Vector2i(x, y)
			if not map.on_edge(c) or _impassable(i).contains(map.terrain(c)):
				continue
			var sc: float = -map.dist(u["pos"], c)
			if active(e):
				sc += map.dist(units[e]["pos"], c) * 0.7
			if sc > bs:
				bs = sc
				best = c
	return best

func ally_plan(i: int) -> Dictionary:
	var p := _ally_plan(i)
	if p.has("move") and p["move"] == units[i]["pos"]:
		p.erase("move")
	return p

func _ally_plan(i: int) -> Dictionary:
	var u: Dictionary = units[i]
	var e := enemy_index()
	var zone := _shown_zone_for(i)
	var m := ally_mode(i)
	var p := {"mode": m}
	match m:
		"escape", "carry":
			if map.on_edge(u["pos"]):
				p["action"] = "retreat"
				return p
			var edge := _nearest_edge_away(i)
			p["move"] = _ally_move(i, edge, zone)
			p["action"] = "dodge" if zone.has(p["move"]) else "wait"
			if map.on_edge(p["move"]):
				p["action"] = "retreat"
		"back":
			var away: Vector2i = u["pos"]
			if active(e):
				var dirv := Vector2(u["pos"] - units[e]["pos"]).normalized()
				away = u["pos"] + Vector2i(roundi(dirv.x * 3.0), roundi(dirv.y * 3.0))
				away = Vector2i(clampi(away.x, 0, map.width - 1), clampi(away.y, 0, map.height - 1))
			p["move"] = _ally_move(i, away, zone)
			p["action"] = "observe"
		"take":
			var cpos: Vector2i = carcass["pos"]
			if take_kinds(i).has("piece"):
				var watching: bool = active(e) and TacticalGrid.side_of(units[e]["pos"], units[e]["facing"], u["pos"]) == "front" \
					and not bool(units[e]["eating"]) and map.dist(units[e]["pos"], u["pos"]) <= 2.5
				if not watching and not zone.has(u["pos"]):
					p["action"] = "take"
					p["kind"] = "piece"
					return p
			# 從對手背後的方向接近殘骸：目標是殘骸旁、離對手正面最遠的一格
			var goal: Vector2i = cpos
			if active(e):
				var bestc: Vector2i = cpos
				var bs := -INF
				for d in TacticalGrid.DIRS:
					var c: Vector2i = cpos + d
					if not map.in_bounds(c) or blocks_for(i).has(c) or _impassable(i).contains(map.terrain(c)):
						continue
					var sd := TacticalGrid.side_of(units[e]["pos"], units[e]["facing"], c)
					var sc: float = (2.0 if sd == "rear" else (1.0 if sd == "side" else -2.0)) - map.dist(u["pos"], c) * 0.2
					if sc > bs:
						bs = sc
						bestc = c
				goal = bestc
			p["move"] = _ally_move(i, goal, zone, false, Vector2i(0, 0))
			# 到了殘骸旁、牠沒看著：同一回合叼
			var save: Vector2i = u["pos"]
			u["pos"] = p["move"]
			var can: bool = take_kinds(i).has("piece")
			u["pos"] = save
			p["action"] = "take" if can and not zone.has(p["move"]) else "wait"
			p["kind"] = "piece"
		"harass":
			if not active(e):
				p["action"] = "wait"
				return p
			var ep: Vector2i = units[e]["pos"]
			# 站到和你不同的一側：牠旁邊、離你最遠、不在正面
			# 站到和「另一隻」（你或伴侶）不同的一側
			var you: Vector2i = ep
			for k in units.size():
				if k != i and active(k) and player_side(k):
					you = units[k]["pos"]
					break
			var bestc2: Vector2i = u["pos"]
			var bs2 := -INF
			for d in TacticalGrid.DIRS:
				var c: Vector2i = ep + d
				if not map.in_bounds(c) or (blocks_for(i).has(c) and c != u["pos"]) or _impassable(i).contains(map.terrain(c)):
					continue
				var sd := TacticalGrid.side_of(ep, units[e]["facing"], c)
				var sc: float = map.dist(c, you) - (4.0 if sd == "front" else 0.0) - (6.0 if zone.has(c) else 0.0) - map.dist(u["pos"], c) * 0.3
				if sc > bs2:
					bs2 = sc
					bestc2 = c
			p["move"] = _ally_move(i, bestc2, zone)
			var adj: bool = map.adjacent(p["move"], ep)
			p["action"] = "harass" if adj and not zone.has(p["move"]) else ("dodge" if zone.has(p["move"]) else "wait")
			p["target"] = e
	return p

# 交給本能：你也照伴侶的自動規則（有殘骸、牠沒盯著你就叼肉，盯著你就退開，否則牽制；叼到就撤）
func auto_plan(i: int) -> Dictionary:
	var keep: String = str(units[i]["command"])
	units[i]["command"] = "auto"
	var p := ally_plan(i)
	units[i]["command"] = keep
	return p

# 衝撞、撲擊是撲向「目標」的動作：結算時朝牠盯著的那隻現在的位置修正（衝撞最多偏 turn_steps 個 45°；
# 撲擊時目標離原本的落點 track_pounce 格內都追得到）。揮掌、咬已經在 _react_turn 轉過了。
func _track(i: int, a: String) -> void:
	if not (a in ["charge", "pounce"]):
		return
	var u: Dictionary = units[i]
	var t: int = int(u.get("attention", -1))
	if t < 0 or not active(t):
		t = _nearest_threat(i)
	if t < 0:
		return
	var tp: Vector2i = units[t]["pos"]
	var it: Dictionary = intents[i]
	if a == "charge":
		if map.dist(u["pos"], tp) > float(_acfg("charge").get("length", 4)) + 0.5:
			return
		var want := TacticalGrid.dir_toward(u["pos"], tp)
		u["facing"] = TacticalGrid.turn_toward(u["facing"], want, maxi(1, int(_opp_cfg(i).get("turn_steps", 1))))
	else:
		var old: Vector2i = it.get("target", tp)
		if map.dist(old, tp) <= float(cfg["ai"].get("track_pounce", 1.5)) and map.dist(u["pos"], tp) <= float(_acfg("pounce").get("range", 3)) + 1.0:
			it["target"] = tp
