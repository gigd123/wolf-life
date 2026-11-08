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
var season := "" # 主遊戲的季節、時段（只給畫面用：冬天的雪地、時段光線；Phase 2k 第 6 步）
var period := ""
var world_map := "" # 主遊戲的地圖（只給畫面用：每張地圖的樹、地面，2026-11-08）
var observed := {} # 這一回合選了觀察的單位 → 下一回合資訊高一級
# 主遊戲（Phase 2k）：你方被打中時交給主遊戲算傷（重傷線、會不會死）。(i, dmg, by) -> {hp, knocked, died}；沒設定時照原型（打到 0 被打倒、不會死）
var hurt_hook: Callable
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
# 主遊戲（Phase 2k）另外傳：scenario_data（直接給情境的字典，取代 p_scenario）、wolf_stats／mate_stats（能力與血量，取代 wolf_profile）、
# knowledge_counts（「物種|動作」→ 見過幾次，蓋過 knowledge 的預設）、carcass_data（殘骸的字典：pos、animal、segments、size……）
func setup(p_scenario: String, opts: Dictionary = {}) -> void:
	var scs: Dictionary = cfg["scenarios"]
	var sc: Dictionary = opts["scenario_data"] if opts.has("scenario_data") else scs[p_scenario]
	var with_mate: bool = bool(opts.get("with_mate", sc.get("with_mate", false)))
	if sc.has("base"):
		# base：照另一個情境的地圖與位置；opponent_id 換成別的對手（黑熊用灰熊的情境，Phase 2k 第 3 步）
		var over: Dictionary = sc
		sc = (scs[str(sc["base"])] as Dictionary).duplicate(true)
		if over.has("opponent_id"):
			sc["opponent"]["id"] = str(over["opponent_id"])
		# 其他欄位（多隻對手 extra_enemies、成員 allies、伴侶的位置 mate……）蓋過 base 的
		for k in over.keys():
			if not (str(k) in ["base", "opponent_id"]):
				sc[k] = over[k]
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
	season = str(opts.get("season", ""))
	period = str(opts.get("period", ""))
	world_map = str(opts.get("world_map", ""))
	var wp: Dictionary = (cfg["wolf_profiles"][str(opts.get("wolf_profile", "average"))] as Dictionary).duplicate()
	if opts.has("wolf_stats"):
		wp = (opts["wolf_stats"] as Dictionary).duplicate()
	units.append(_make_wolf("wolf", "player", _v(sc["wolf"]), wp))
	if with_mate and sc.has("mate"):
		units.append(_make_wolf("mate", "ally", _v(sc["mate"]), (opts["mate_stats"] as Dictionary).duplicate() if opts.has("mate_stats") else wp.duplicate()))
	# 第 5 步：跟著你的其他成員（自動行動，不能下指令）
	for a in sc.get("allies", []):
		var au := _make_wolf(str(a["id"]), "ally", _v(a["pos"]), (a["stats"] as Dictionary).duplicate() if a.has("stats") else wp.duplicate())
		if a.has("name"):
			au["name"] = str(a["name"])
		units.append(au)
	var o: Dictionary = sc["opponent"]
	_add_enemy(o, opts.get("opponent_stats", {}), float(opts.get("stake", 1.0)))
	# 第 5 步：多隻對手（苔原狼一對、鄰群 2～3 隻）：每隻各自的能力與血量
	for x in sc.get("extra_enemies", []):
		_add_enemy(x, x.get("stats", {}), float(opts.get("stake", 1.0)))
	knowledge.clear()
	var species_seen := {}
	for k0 in units.size():
		if str(units[k0]["side"]) != "enemy" or species_seen.has(str(units[k0]["species"])):
			continue
		var sp0: String = str(units[k0]["species"])
		species_seen[sp0] = true
		for act in cfg["opponents"][sp0]["actions"]:
			var kk: String = sp0 + "|" + str(act)
			knowledge[kk] = {"count": int(opts.get("knowledge_counts", {}).get(kk, knowledge_level)), "category": "experience", "source": "self"}
	carcass = {}
	if opts.has("carcass_data"):
		carcass = (opts["carcass_data"] as Dictionary).duplicate()
	elif sc.has("carcass"):
		var cc: Array = sc["carcass"]
		var cd: Dictionary = cfg["carcass"][str(cc[2])]
		carcass = {"pos": Vector2i(int(cc[0]), int(cc[1])), "animal": str(cc[2]), "segments": int(cd["segments"]),
			"size": str(cd.get("size", "large")), "small_whole": bool(cd.get("small_whole", false)),
			"whole_size": str(cd.get("whole_size", "small")), "leg": cd.get("leg_segments", [2, 3])}

# 對手：o 是情境的 {id（物種）, pos, facing, eating, ambush, uid（同一種有好幾隻時的單位 id）, name}；os 是主遊戲的能力與血量
func _add_enemy(o: Dictionary, os: Dictionary, stake: float) -> void:
	var od: Dictionary = cfg["opponents"][str(o["id"])]
	units.append({"id": str(o.get("uid", o["id"])), "side": "enemy", "species": str(o["id"]), "pos": _v(o["pos"]), "facing": _v(o.get("facing", [-1, 0])),
		"stats": {"strength": float(od["strength"]), "speed": float(od["speed"]), "skill": float(od.get("skill", 50)), "perception": float(od.get("perception", 50))}, "hp": float(od["hp"]), "hp_max": float(od["hp"]),
		"breath": 0.0, "breath_max": 0.0, "carrying": "", "carry_segments": 0, "out": false, "out_reason": "",
		"eating": bool(o.get("eating", false)), "ambush": bool(o.get("ambush", false)),
		"stamina": float(cfg["enemy_stamina"].get(str(o["id"]), 80.0)), "stamina_max": float(cfg["enemy_stamina"].get(str(o["id"]), 80.0)),
		"attention": -1, "bitten_by": -1})
	var eu: Dictionary = units.back()
	var br: Array = cfg["ai"]["bold"].get(str(o["id"]), [0.0, 0.0])
	eu["bold"] = rng.randf_range(float(br[0]), float(br[1]))
	if o.has("name"):
		eu["name"] = str(o["name"])
	# 主遊戲：對手的能力與血量（具名的狼照牠自己的；Phase 2k 第 4 步）、這一場的賭注（在牠的地盤、有殘骸時比較拚）
	for k in ["strength", "speed", "skill", "perception"]:
		if os.has(k):
			eu["stats"][k] = float(os[k])
	eu["hp_max"] = float(os.get("health_max", eu["hp_max"]))
	eu["hp"] = float(os.get("health", eu["hp_max"]))
	eu["stake"] = stake

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

# 第 5 步：多隻對手
func enemies() -> Array:
	var out: Array = []
	for i in units.size():
		if str(units[i]["side"]) == "enemy":
			out.append(i)
	return out

func active_enemies() -> Array:
	return enemies().filter(func(k): return active(k))

# 這隻（從 from 這一格）面對的是哪一隻對手：最近的；一樣近時挑傷得比較重的。都走了時回傳第一隻（不在場上）
func foe_of(i: int, from: Vector2i = Vector2i(-1, -1)) -> int:
	if from.x < 0:
		from = units[i]["pos"]
	var best := -1
	var bs := INF
	for k in active_enemies():
		var sc: float = map.dist(from, units[k]["pos"]) + float(units[k]["hp"]) / maxf(1.0, float(units[k]["hp_max"])) * 0.3
		if sc < bs:
			bs = sc
			best = k
	return best if best >= 0 else enemy_index()

# 再挨對手 risk_hits 下最重的就會掉到重傷線以下（第 6 步：老了血量上限低時，照比例撤會來不及）
func _too_risky(i: int) -> bool:
	var e := foe_of(i)
	if not active(e):
		return false
	var worst := 0.0
	for a in _actions_of(e):
		var dr: Array = _acfg(str(a)).get("dmg", {}).get(str(units[e]["species"]), [])
		if dr.size() == 2:
			var m: float = float(dr[1])
			if bool(_opp_cfg(e).get("wolf", false)):
				m *= float(units[e]["stats"]["strength"]) / 60.0
			worst = maxf(worst, m)
	var ac: Dictionary = cfg["ally"]
	var line: float = float(units[i]["hp_max"]) * float(ac.get("danger_ratio", 0.25))
	return float(units[i]["hp"]) - worst * float(ac.get("risk_hits", 2.0)) <= line

# 跟著你的成員優先對付你正在對付的那一隻（SPEC：你牽制時牠們從側面進）；離你太遠時對付自己最近的
func _ally_foe(i: int) -> int:
	if i != 0 and active(0):
		var f0 := foe_of(0)
		if active(f0) and map.dist(units[0]["pos"], units[f0]["pos"]) <= 2.5 and map.dist(units[i]["pos"], units[f0]["pos"]) <= 6.0:
			return f0
	return foe_of(i)

func _active_count() -> int:
	var n := 0
	for k in units.size():
		if active(k):
			n += 1
	return n

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
	u["last_mode"] = m
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
	for k in units.size():
		if player_side(k):
			units[k]["prev_mode"] = str(units[k].get("last_mode", ""))
			units[k]["last_mode"] = ""
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
		u["alert"] = int(_ai_cfg()["alert"]["rounds"])
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
	# 警戒：有狼在附近徘徊就一直維持；狼走遠了才慢慢放鬆
	var lingering := false
	for k in units.size():
		if active(k) and player_side(k) and map.dist(u["pos"], units[k]["pos"]) <= float(_ai_cfg()["alert"]["linger_dist"]):
			lingering = true
	if int(u.get("alert", 0)) > 0 and lingering:
		u["alert"] = int(_ai_cfg()["alert"]["rounds"])
	else:
		u["alert"] = maxi(0, int(u.get("alert", 0)) - 1)
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
	# 狼對狼（Phase 2k 第 4 步）：另一套 AI（示威、咬、示弱）
	if bool(_opp_cfg(i).get("wolf", false)):
		return _ai_wolf(i)
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
		# 追的時候是邊跑邊轉，不受原地轉身的限制
		if chase > 0.0:
			turned = want
		# 攻擊：轉過去之後對方在範圍裡
		for a in ["swipe", "bite"]:
			if acts.has(a) and zone_cells(i, a, pos, turned).has(tp):
				cands.append([float(sc["attack"]) * food_bonus + bold * 2.0 + bitten_bonus + chase - (1.5 if a == "bite" and acts.has("swipe") else 0.0), a, pos, turned, nothing, "attack"])
		# 旁邊另一隻狼也打得到（例如伴侶從背後叼肉時）：順手揮過去，分數低一點
		for k in units.size():
			if k == t or not active(k) or not player_side(k) or map.dist(pos, units[k]["pos"]) > 1.5:
				continue
			var tk: Vector2i = units[k]["pos"]
			var turned_k := TacticalGrid.turn_toward(facing, TacticalGrid.dir_toward(pos, tk), turn_steps)
			for a in ["swipe", "bite"]:
				if acts.has(a) and zone_cells(i, a, pos, turned_k).has(tk):
					cands.append([float(sc["attack"]) * food_bonus + bold * 2.0 - float(ai.get("other_attack_less", 1.0)) - (1.5 if a == "bite" and acts.has("swipe") else 0.0), a, pos, turned_k, nothing, "attack_other:%d" % k])
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
		# 追叼走肉的（衝得到就衝，追不到才走過去）
		var can_charge: bool = acts.has("charge") and d >= 1.5 and d <= float(_acfg("charge").get("length", 4)) + 0.5 and _clear_line(i, pos, want, tp)
		if chase > 0.0 and d > 1.5 and not can_charge:
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
			var alert: bool = int(u.get("alert", 0)) > 0
			var safe_d: float = float(ai["eat_safe_dist"]) + (float(ai["alert"]["extra_dist"]) if alert else 0.0)
			var safe: bool = d > safe_d or (bool(u["eating"]) and not alert and not _notices(i, t))
			if d <= safe_d and not safe:
				u["alert"] = int(ai["alert"]["rounds"])
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
	var why: String = str(best[5])
	if why.begins_with("attack_other:"):
		u["attention"] = int(why.split(":")[1])
		why = "attack"
	return _intent(i, str(best[1]), best[2], best[3], best[4], why)

# 實力（狼對狼的判斷用）：力量 × 剩下的血量比例
func _power(i: int) -> float:
	var u: Dictionary = units[i]
	return float(u["stats"]["strength"]) * (0.4 + 0.6 * float(u["hp"]) / maxf(1.0, float(u["hp_max"])))

# 一群對一群的實力比（第 5 步）：i 這一邊對 t 這一邊；兩隻附近 3 格內的同伴也算（打個八折）。一對一時就是兩隻的實力比
func _group_pr(i: int, t: int) -> float:
	var mine := _power(i)
	var theirs := _power(t)
	var near: float = float(_ai_cfg().get("wolf", {}).get("group_radius", 3.0))
	var share: float = float(_ai_cfg().get("wolf", {}).get("group_share", 0.8))
	for k in units.size():
		if k == i or k == t or not active(k):
			continue
		if minf(map.dist(units[k]["pos"], units[i]["pos"]), map.dist(units[k]["pos"], units[t]["pos"])) > near:
			continue
		if player_side(k) == player_side(i):
			mine += _power(k) * share
		else:
			theirs += _power(k) * share
	return mine / maxf(1.0, theirs)

# 對手的狼挑誰（第 5 步，SPEC：圍住落單的那一隻）：被咬就看咬牠的；否則挑近、身邊同伴少、已經有自己這邊的狼在旁邊的
func _wolf_target(i: int) -> int:
	var u: Dictionary = units[i]
	var b: int = int(u.get("bitten_by", -1))
	u["just_bitten"] = false
	if b >= 0 and active(b):
		u["attention"] = b
		u["bitten_by"] = -1
		u["just_bitten"] = true
		return b
	var aw: Dictionary = _ai_cfg().get("wolf", {})
	var best := -1
	var bs := INF
	for k in units.size():
		if not active(k) or not player_side(k):
			continue
		var sc: float = map.dist(u["pos"], units[k]["pos"])
		for m in units.size():
			if m == k or m == i or not active(m) or map.dist(units[m]["pos"], units[k]["pos"]) > 2.5:
				continue
			sc += float(aw.get("target_friends", 1.5)) if player_side(m) else -float(aw.get("target_mob", 1.2))
		if k == int(u.get("attention", -1)):
			sc -= float(aw.get("target_keep", 1.0)) # 不要每回合換目標
		if sc < bs:
			bs = sc
			best = k
	u["attention"] = best
	return best

# 包抄（第 5 步）：已經有同伴貼著目標時，走到目標旁、離同伴最遠的一格（側面、背後優先）
func _flank_goal(i: int, t: int) -> Vector2i:
	var tp: Vector2i = units[t]["pos"]
	var mates: Array = active_enemies().filter(func(k): return k != i and map.dist(units[k]["pos"], tp) <= 2.5)
	if mates.is_empty():
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var bs := -INF
	for d in TacticalGrid.DIRS:
		var c: Vector2i = tp + d
		if not map.in_bounds(c) or _impassable(i).contains(map.terrain(c)) or (blocks_for(i).has(c) and c != units[i]["pos"]):
			continue
		var spread := INF
		for m in mates:
			spread = minf(spread, map.dist(c, units[m]["pos"]))
		var sd := TacticalGrid.side_of(tp, units[t]["facing"], c)
		var sc: float = spread + (1.5 if sd == "rear" else (0.8 if sd == "side" else 0.0)) - map.dist(units[i]["pos"], c) * 0.4
		if sc > bs:
			bs = sc
			best = c
	return best

# 狼對狼的對手 AI（Phase 2k 第 4 步；SPEC：多半是示威、壓制與退讓）：
# 依實力差距（pr）、這一場的賭注（stake：在牠的地盤、有殘骸時比較拚）、血量與耐心，決定靠近、示威、咬，或示弱、逃走。
func _ai_wolf(i: int) -> Dictionary:
	var u: Dictionary = units[i]
	var aw: Dictionary = _ai_cfg().get("wolf", {})
	var pos: Vector2i = u["pos"]
	var facing: Vector2i = u["facing"]
	var nothing := Vector2i(-1, -1)
	var bold: float = float(u.get("bold", 0.0))
	var stake: float = float(u.get("stake", 1.0))
	var t := _wolf_target(i)
	var hp_ratio: float = float(u["hp"]) / maxf(1.0, float(u["hp_max"]))
	var give: float = float(cfg["give_up"].get(str(u["species"]), 0.4)) * (1.0 - bold * 0.3) / stake
	if t < 0:
		return _intent(i, "flee", pos, facing, nothing, "patience")
	var pr: float = _group_pr(i, t)
	# 被圍、寡不敵眾時比較早放棄（第 5 步）
	# （只在多隻的戰鬥；一對一照第 4 步校準過的放棄線）
	if pr < 1.0 and _active_count() > 2:
		give = minf(0.9, give / maxf(0.35, pr))
	# 打不過了、耐心沒了：示弱（大多數）或直接逃
	if hp_ratio < give or float(u["stamina"]) <= 0.0:
		if pr < float(aw.get("flee_pr", 0.6)):
			return _intent(i, "flee", pos, facing, nothing, "hurt" if hp_ratio < give else "patience")
		return _intent(i, "submit", pos, facing, nothing, "submit")
	var tp: Vector2i = units[t]["pos"]
	var d: float = map.dist(pos, tp)
	var want := TacticalGrid.dir_toward(pos, tp)
	var cands: Array = []
	var noise: float = float(_ai_cfg()["noise"])
	var early: float = maxf(0.0, 1.0 - float(rounds) * float(aw.get("threaten_fade", 0.25)))
	if map.adjacent(pos, tp):
		cands.append([float(aw.get("attack", 6.0)) + (pr - 1.0) * float(aw.get("attack_pr", 3.0)) + bold * 2.0 + (2.0 if bool(u.get("just_bitten", false)) else 0.0), "bite", pos, want, nothing, "attack"])
		cands.append([float(aw.get("threaten", 4.0)) + stake * early * 2.0 - (pr - 1.0), "threaten", pos, want, nothing, "threaten"])
		# 從側面、背後撲上去壓住（第 5 步：對手的狼也會；被包抄的那隻最危險）
		if bool(aw.get("enemy_pin", true)) and TacticalGrid.side_of(tp, units[t]["facing"], pos) != "front":
			var pc: float = float(wolf_chance(i, "pin", t, pos)["chance"])
			cands.append([float(aw.get("pin", 5.0)) + (pc - 0.4) * float(aw.get("pin_chance", 8.0)) + bold, "pin", pos, want, nothing, "pin"])
		if pr < 1.0:
			cands.append([float(aw.get("back_off", 2.5)) + (1.0 - pr) * 3.0 - bold, "back_off", pos, want, nothing, "back_off"])
	else:
		var to := _step_toward(i, tp, true)
		var fg := _flank_goal(i, t)
		if fg.x >= 0:
			to = _step_toward(i, fg, false)
		if to != pos:
			cands.append([float(aw.get("approach", 5.0)) + (pr - 1.0) * 2.0 + bold, "move", to, TacticalGrid.dir_toward(to, tp), nothing, "approach"])
		if d <= 3.5:
			cands.append([float(aw.get("threaten", 4.0)) + stake * early * 2.5 - (pr - 1.0) * 0.5, "threaten", pos, want, nothing, "threaten"])
	cands.append([1.0, "turn", pos, want, nothing, "idle"])
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
		var e := foe_of(i, from)
		var state := "away"
		if active(e):
			if bool(units[e]["eating"]) and not moved:
				state = "eating"
			elif TacticalGrid.side_of(units[e]["pos"], units[e]["facing"], from) == "front" and map.dist(units[e]["pos"], from) <= 2.5:
				state = "facing"
			elif not bool(units[e]["eating"]) and int(units[e].get("attention", -1)) == i and map.dist(units[e]["pos"], from) <= 2.0:
				# 牠沒在吃、正盯著你：從側面靠近牠也看得到（還在吃的話，這一回合才走過來算 away）
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
	if action == "pin":
		# 壓制：看力量差、技巧、從哪一側撲上去、牠還剩多少力氣
		p = float(w.get("base", 0.25))
		var sd: float = (float(u["stats"]["strength"]) - float(units[target]["stats"]["strength"])) / float(w.get("str_div", 150.0))
		var sk3: float = (float(u["stats"]["skill"]) - 50.0) / float(w.get("skill_div", 200.0))
		var side3 := TacticalGrid.side_of(units[target]["pos"], units[target]["facing"], from)
		var sv3: float = float(w.get("side", {}).get(side3, 0.0))
		var tired: float = (1.0 - float(units[target]["hp"]) / maxf(1.0, float(units[target]["hp_max"]))) * float(w.get("hurt_bonus", 0.4))
		p += sd + sk3 + sv3 + tired
		factors.append_array([["strength_diff", sd], ["skill", sk3], ["side." + side3, sv3], ["target_hurt", tired]])
		return {"chance": clamp(p, 0.05, 0.9), "factors": factors}
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
			# 示弱、撤退是放棄打鬥，不會被打斷（第 6 步：被打斷的示弱讓已經重傷的狼多挨一回合）
			if str(plans.get(k, {}).get("action", "")) in ["submit", "retreat"]:
				continue
			if not acted.has(k) and rng.randf() < float(cfg["initiative"]["interrupt"]):
				interrupted[k] = true
				_ev("interrupted", {"who": k})

func _hurt(i: int, dmg: float, by: int) -> void:
	var u: Dictionary = units[i]
	var hooked := {}
	if player_side(i) and hurt_hook.is_valid():
		hooked = hurt_hook.call(i, dmg, by)
		u["hp"] = float(hooked.get("hp", max(0.0, float(u["hp"]) - dmg)))
	else:
		u["hp"] = max(0.0, float(u["hp"]) - dmg)
	_ev("hit", {"who": by, "target": i, "dmg": dmg})
	# 主遊戲：已經重傷還留在場上被打到 0 → 死亡；還沒重傷被打到 0 → 停在 1、被打倒（SPEC Phase 2k「被打倒與死亡」）
	if not hooked.is_empty():
		if bool(hooked.get("died", false)):
			drop_carried(i)
			u["out"] = true
			u["out_reason"] = "died"
			_ev("died", {"who": i})
			return
		if bool(hooked.get("knocked", false)):
			drop_carried(i)
			u["out"] = true
			u["out_reason"] = "knocked"
			_ev("knocked", {"who": i})
			return
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
		"threaten":
			# 豎毛低吼：不前進；看到的狼記一次
			_ev("threaten", {"who": i})
			_witness(i, a)
			return hit_units
		"pin":
			# 撲上去壓住：被壓住的那隻示弱、退出（第 5 步）
			var pt: int = int(u.get("attention", -1))
			if pt < 0 or not active(pt) or not map.adjacent(u["pos"], units[pt]["pos"]):
				_ev("pin_fail", {"who": i, "target": pt})
				return hit_units
			if rng.randf() < float(wolf_chance(i, "pin", pt, u["pos"])["chance"]):
				_ev("pinned", {"who": i, "target": pt})
				drop_carried(pt)
				units[pt]["out"] = true
				units[pt]["out_reason"] = "submit"
				_ev("submit", {"who": pt})
			else:
				_ev("pin_fail", {"who": i, "target": pt})
			return hit_units
		"submit":
			# 夾尾巴伏低、退開：這一場到此為止（你可以放牠走或追擊，主遊戲照選單式處理）
			u["out"] = true
			u["out_reason"] = "submit"
			_ev("submit", {"who": i})
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
	# 有些動作對不同物種的命中不同（狼咬狼比熊揮掌難命中）
	if ac.has("hit_by"):
		p = float(ac["hit_by"].get(str(units[i]["species"]), p))
	if str(plans.get(k, {}).get("action", "")) == "dodge":
		p *= float(cfg["wolf"]["dodge_mult"])
	if rng.randf() >= p:
		_ev("miss", {"who": i, "target": k})
		return false
	var dr: Array = ac.get("dmg", {}).get(str(units[i]["species"]), [10, 20])
	var dmg := float(rng.randi_range(int(dr[0]), int(dr[1])))
	# 對手是狼：傷害照牠的力量（和你咬牠一樣 × 力量 ÷ 60）
	if bool(_opp_cfg(i).get("wolf", false)):
		dmg *= float(units[i]["stats"]["strength"]) / 60.0
	_hurt(k, dmg, i)
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
		"threaten":
			# 示威（只對狼）：豎毛低吼；你越比牠強，牠的耐心掉得越快
			# 多隻時：範圍裡的每一隻狼都算（第 5 步）
			for e3 in active_enemies():
				if bool(_opp_cfg(e3).get("wolf", false)) and map.dist(u["pos"], units[e3]["pos"]) <= float(w.get("range", 3.0)) + 0.5:
					var ratio: float = clampf(_power(i) / maxf(1.0, _power(e3)), 0.4, 2.0)
					units[e3]["stamina"] = maxf(0.0, float(units[e3].get("stamina", 0.0)) - float(w.get("drain", 14.0)) * ratio)
			_ev("threaten", {"who": i})
		"pin":
			# 壓制（只對狼）：從側面或背後撲上去壓住；成功時牠多半示弱
			var t3: int = int(p.get("target", foe_of(i)))
			if not active(t3) or not map.adjacent(u["pos"], units[t3]["pos"]):
				_ev("whiff", {"who": i, "target": t3})
				return
			u["facing"] = TacticalGrid.dir_toward(u["pos"], units[t3]["pos"])
			if rng.randf() < float(wolf_chance(i, "pin", t3, u["pos"], sprinted)["chance"]):
				_ev("pinned", {"who": i, "target": t3})
				units[t3]["out"] = true
				units[t3]["out_reason"] = "submit"
				_ev("submit", {"who": t3})
			else:
				_ev("pin_fail", {"who": i, "target": t3})
				units[t3]["bitten_by"] = i
		"submit":
			# 示弱（只對狼）：趴低、退開，這一場到此為止
			u["out"] = true
			u["out_reason"] = "submit"
			drop_carried(i)
			_ev("submit", {"who": i})
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
				var e := foe_of(i)
				if active(e):
					units[e]["bitten_by"] = i
					units[e]["eating"] = false
			else:
				_ev("take_fail", {"who": i, "why": "missed"})
				# 叼失敗：牠發現了，下一回合可以猛然轉身對付你
				var e2 := foe_of(i)
				if active(e2):
					units[e2]["bitten_by"] = i
					units[e2]["eating"] = false
		"bite", "pounce", "harass":
			if str(u["carrying"]) != "":
				_ev("cannot", {"who": i, "why": "carrying"})
				return
			var t: int = int(p.get("target", foe_of(i)))
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
	var foes := enemies()
	if active_enemies().is_empty():
		done = true
		if foes.size() > 1:
			outcome = "routed" # 第 5 步：多隻對手都走了（示弱、逃走）
		else:
			outcome = "enemy_submit" if str(units[e]["out_reason"]) == "submit" else "enemy_left"
	elif not active(0):
		done = true
		var why0: String = str(units[0]["out_reason"])
		outcome = why0 if why0 in ["knocked", "died", "submit"] else "retreated"
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
	var e := foe_of(i, from)
	var sp: String = str(units[e]["species"]) if e >= 0 else ""
	var out: Array = []
	var carrying: bool = str(units[i]["carrying"]) != ""
	for a in ["bite", "pounce", "harass"]:
		if active(e) and not carrying and (map.adjacent(from, units[e]["pos"]) or (a == "pounce" and map.dist(from, units[e]["pos"]) <= float(_wcfg("pounce").get("range", 2)) + 0.5)):
			var c: Dictionary = wolf_chance(i, a, e, from, sprinted)
			out.append({"id": a, "target": e, "chance": c["chance"], "factors": c["factors"], "show": display_chance(i, float(c["chance"]), sp)})
	var save_pos: Vector2i = units[i]["pos"]
	units[i]["pos"] = from
	for k in take_kinds(i):
		var c2: Dictionary = wolf_chance(i, "take", -1, from, sprinted, k, from != save_pos)
		out.append({"id": "take", "kind": k, "chance": c2["chance"], "factors": c2["factors"], "show": display_chance(i, float(c2["chance"]), sp)})
	units[i]["pos"] = save_pos
	# 對手是狼：示威（3 格內）、壓制（相鄰）、示弱
	if active(e) and bool(_opp_cfg(e).get("wolf", false)) and not carrying:
		if map.dist(from, units[e]["pos"]) <= float(_wcfg("threaten").get("range", 3.0)) + 0.5:
			out.append({"id": "threaten"})
		if map.adjacent(from, units[e]["pos"]):
			var c3: Dictionary = wolf_chance(i, "pin", e, from, sprinted)
			out.append({"id": "pin", "target": e, "chance": c3["chance"], "factors": c3["factors"], "show": display_chance(i, float(c3["chance"]), sp)})
	for a2 in ["dodge", "observe", "wait"]:
		out.append({"id": a2})
	if active(e) and bool(_opp_cfg(e).get("wolf", false)):
		out.append({"id": "submit"})
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
	# 對手是狼：照一對一的打法（打不過時示弱，不是逃出戰場；Phase 2k 第 4 步）
	var e0 := _ally_foe(i)
	if active(e0) and bool(_opp_cfg(e0).get("wolf", false)) and str(u["carrying"]) == "":
		return "duel"
	# 交給本能的你比同伴早撤（Phase 2k 第 6 步：一生模擬裡撐到過了重傷線才撤、被打死的太多）
	var rh: float = float(ac.get("self_retreat_hp", ac["retreat_hp"])) if i == 0 else float(ac["retreat_hp"])
	if float(u["hp"]) < float(u["hp_max"]) * rh or (i == 0 and _too_risky(i)):
		return "escape"
	if str(u["carrying"]) != "":
		return "carry"
	# 拖太久還沒機會：自己判斷算了、離開（只在「交給牠判斷」時）
	if str(u["command"]) == "auto" and rounds >= int(ac.get("leave_rounds", 999)):
		return "escape"
	var cmd: String = str(u["command"])
	if cmd != "auto":
		if cmd == "take" and (carcass.is_empty() or int(carcass["segments"]) <= 0):
			return "harass"
		return cmd
	var e := _ally_foe(i)
	if not active(e):
		return "back"
	# 對手是狼：一對一的打法（Phase 2k 第 4 步）
	if bool(_opp_cfg(e).get("wolf", false)):
		return "duel"
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
	var e := foe_of(i)
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

func _creep_toward(i: int, goal: Vector2i, zone: Dictionary) -> Vector2i:
	var u: Dictionary = units[i]
	var best: Vector2i = u["pos"]
	var bd: float = map.dist(u["pos"], goal)
	var blocks := blocks_for(i)
	for d in TacticalGrid.DIRS:
		var c: Vector2i = u["pos"] + d
		if not map.in_bounds(c) or blocks.has(c) or _impassable(i).contains(map.terrain(c)) or zone.has(c):
			continue
		var dd: float = map.dist(c, goal)
		if dd < bd - 0.01:
			bd = dd
			best = c
	return best

func _nearest_edge_away(i: int) -> Vector2i:
	var u: Dictionary = units[i]
	var foes := active_enemies()
	var best: Vector2i = u["pos"]
	var bs := -INF
	for y in map.height:
		for x in map.width:
			var c := Vector2i(x, y)
			if not map.on_edge(c) or _impassable(i).contains(map.terrain(c)):
				continue
			var sc: float = -map.dist(u["pos"], c)
			if not foes.is_empty():
				var md := INF
				for e in foes:
					md = minf(md, map.dist(units[e]["pos"], c))
				sc += md * 0.7
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
	var e := _ally_foe(i)
	var zone := _shown_zone_for(i)
	# 牠（或交給本能的你）不會每次都照預告完美閃開：有時看錯或衝得太投入，這一回合當作沒看到範圍。
	# 用固定的種子擲（同一回合重算結果不變）
	var mr := RandomNumberGenerator.new()
	mr.seed = hash([rng.seed, rounds, i, "misread"])
	var misread: bool = mr.randf() < float(cfg["ally"].get("misread", 0.0))
	if misread:
		zone = {}
	var m := ally_mode(i)
	var p := {"mode": m}
	if misread:
		p["misread"] = true
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
			# 靠近在吃的對手時用潛行（一次一格），比較不會被發現
			if active(e) and bool(units[e]["eating"]) and map.dist(u["pos"], units[e]["pos"]) <= float(_ai_cfg()["sneak_dist"]):
				p["move"] = _creep_toward(i, goal, zone)
			# 到了殘骸旁、牠沒看著：同一回合叼
			var save: Vector2i = u["pos"]
			u["pos"] = p["move"]
			var can: bool = take_kinds(i).has("piece")
			u["pos"] = save
			p["action"] = "take" if can and not zone.has(p["move"]) else "wait"
			p["kind"] = "piece"
		"duel":
			return _duel_plan(i, p)
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

# 狼對狼的自動打法（交給本能、伴侶）：打不過就示弱；相鄰時壓制機會夠高就壓，否則繞到側面咬；
# 還沒貼近時，比牠強就先示威，不然貼上去
func _duel_plan(i: int, p: Dictionary) -> Dictionary:
	var e := _ally_foe(i)
	var u: Dictionary = units[i]
	var ep: Vector2i = units[e]["pos"]
	var ef: Vector2i = units[e]["facing"]
	var ad: Dictionary = _ai_cfg().get("wolf", {})
	var pr: float = _group_pr(i, e)
	var hp_ratio: float = float(u["hp"]) / maxf(1.0, float(u["hp_max"]))
	var zone := _shown_zone_for(i)
	# 多隻對手、寡不敵眾（第 5 步，SPEC：獨狼被圍多半該撤退）：你（交給本能時）往離牠們最遠的邊緣撤；同伴跟著你，你撤出就結束
	var n_side := 0
	for k in units.size():
		if active(k) and player_side(k):
			n_side += 1
	if i == 0 and active_enemies().size() > 1 and active_enemies().size() > n_side and pr < float(ad.get("auto_retreat_pr", 0.75)):
		p["mode"] = "escape"
		if map.on_edge(u["pos"]):
			p["action"] = "retreat"
			return p
		p["move"] = _ally_move(i, _nearest_edge_away(i), zone)
		p["action"] = "retreat" if map.on_edge(p["move"]) else ("dodge" if zone.has(p["move"]) else "wait")
		return p
	if hp_ratio <= float(ad.get("auto_submit_hp", 0.3)) and pr < 1.0:
		p["action"] = "submit"
		return p
	# 交給本能的你：血量低就示弱，不硬撐（第 6 步）；血量上限低（老了）時看對手一下打多重
	if i == 0 and (hp_ratio <= float(ad.get("self_submit_hp", 0.4)) or _too_risky(i)):
		p["action"] = "submit"
		return p
	if map.adjacent(u["pos"], ep):
		var pc: float = float(wolf_chance(i, "pin", e, u["pos"])["chance"])
		if pc >= float(ad.get("auto_pin", 0.45)):
			p["action"] = "pin"
			p["target"] = e
			return p
		# 在牠正面：繞到側面再咬
		if TacticalGrid.side_of(ep, ef, u["pos"]) == "front":
			for d in TacticalGrid.DIRS:
				var c: Vector2i = ep + d
				if map.in_bounds(c) and reachable(i).has(c) and TacticalGrid.side_of(ep, ef, c) != "front" and not zone.has(c):
					p["move"] = c
					break
		p["action"] = "bite"
		p["target"] = e
		return p
	if pr >= float(ad.get("auto_threaten_pr", 1.1)) and rounds <= 2 and map.dist(u["pos"], ep) <= 3.5:
		p["action"] = "threaten"
		return p
	# 多隻的戰鬥、還離得遠（第 5 步）：先靠到牠前方 2 格、和同伴站在一起，不要一口氣衝到牠背後（同時移動時會被擋住、跑散）
	if _active_count() > 2 and map.dist(u["pos"], ep) > float(ad.get("close_in", 3.0)):
		var dv := Vector2(u["pos"] - ep).normalized() * 2.0
		var g2 := Vector2i(clampi(ep.x + roundi(dv.x), 0, map.width - 1), clampi(ep.y + roundi(dv.y), 0, map.height - 1))
		p["move"] = _ally_move(i, g2, zone)
		p["action"] = "threaten" if map.dist(p["move"], ep) <= float(_wcfg("threaten").get("range", 3.0)) + 0.5 and pr >= 1.0 else "wait"
		p["target"] = e
		return p
	var bestc: Vector2i = ep
	var bs := -INF
	for d in TacticalGrid.DIRS:
		var c2: Vector2i = ep + d
		if not map.in_bounds(c2) or blocks_for(i).has(c2) or _impassable(i).contains(map.terrain(c2)):
			continue
		var sd := TacticalGrid.side_of(ep, ef, c2)
		var sc: float = (2.0 if sd == "rear" else (1.0 if sd == "side" else -1.0)) - map.dist(u["pos"], c2) * 0.3
		if sc > bs:
			bs = sc
			bestc = c2
	p["move"] = _ally_move(i, bestc, zone)
	var nxt: Vector2i = p["move"]
	p["action"] = "bite" if map.adjacent(nxt, ep) else "wait"
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

# 在吃的時候有沒有發現靠近的狼：看牠在哪一側、上一回合怎麼靠近的（悄悄潛行最不容易被發現，跑過來最容易）
func _notices(i: int, t: int) -> bool:
	var ai := _ai_cfg()
	var sd := TacticalGrid.side_of(units[i]["pos"], units[i]["facing"], units[t]["pos"])
	var p: float = float(ai["notice"]["side"].get(sd, 1.0))
	p *= float(ai["notice"]["mode"].get(str(units[t].get("prev_mode", "")), 1.0))
	return rng.randf() < clamp(p, 0.0, 1.0)
