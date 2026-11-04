class_name TacticalCombat
extends RefCounted

# 戰術戰鬥的邏輯（原型規格 docs/proposals/tactical-combat-prototype.md，2026-11-04 使用者確認）。
# 純邏輯、不碰 GameState，可以 headless 測試；畫面層與模擬只呼叫這裡的公開函式。數值在 data/tactical_combat.json，
# 移動成本與喘沿用 data/tactical_hunt.json 的 move、breath。
#
# 第 1 步：地圖、單位（你、伴侶、對手）、殘骸、移動範圍（喘、叼著肉時依大小變慢）、叼肉與放下、撤出地圖。
# 之後的步驟：回合流程（表態、同步結算／預告後輪流）、動作庫與 AI、資訊等級、伴侶的合作。

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
var log_lines: Array = []

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
	log_lines.clear()
	var wp: Dictionary = (cfg["wolf_profiles"][str(opts.get("wolf_profile", "average"))] as Dictionary).duplicate()
	units.append(_make_wolf("wolf", "player", _v(sc["wolf"]), wp))
	if with_mate and sc.has("mate"):
		units.append(_make_wolf("mate", "ally", _v(sc["mate"]), wp.duplicate()))
	var o: Dictionary = sc["opponent"]
	var od: Dictionary = cfg["opponents"][str(o["id"])]
	units.append({"id": str(o["id"]), "side": "enemy", "species": str(o["id"]), "pos": _v(o["pos"]), "facing": _v(o.get("facing", [-1, 0])),
		"stats": {"strength": float(od["strength"]), "speed": float(od["speed"])}, "hp": float(od["hp"]), "hp_max": float(od["hp"]),
		"breath": 0.0, "breath_max": 0.0, "carrying": "", "carry_segments": 0, "out": false, "out_reason": "",
		"eating": bool(o.get("eating", false)), "ambush": bool(o.get("ambush", false))})
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
