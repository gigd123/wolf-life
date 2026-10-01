class_name HuntSystem
extends RefCounted

# 一次狩獵。依 SPEC「狩獵深度分級」分三種深度：
# - 簡易（simple）：野兔、各種幼體——一次撲抓判定
# - 標準（standard）：狐狸、白尾鹿母鹿——潛近 → 追擊（追上即制伏）
# - 完整（full）：健康的成年雄鹿——觀察 → 潛近 → 追擊 → 搏鬥（多回合）
# 深度寫在 animals.json 的 depth；所有數值在 balance.json 的 "hunt"。
#
# 畫面層只透過 options() 取得目前階段的選項（含成功率與關鍵因素），再呼叫
# choose(option_id)。每個選項都要看得出取捨：體力、回合、成功率，以及成功後
# 帶到下一階段的好處（追擊起點、搏鬥位置）。地形決定可用的專屬選項。
#
# 失敗也有結果：獵物逃走時 fled = true，GameState 會把它變成一條可再追的
# 新鮮足跡；觀察失敗只會讓獵物更警覺。搏鬥判定在 FightRules，
# Phase 1.6 改用戰鬥規則時只換那邊。
#
# 風向以相對狀態 headwind（逆風）/ crosswind（側風）/ tailwind（順風）表示，
# 潛近、撲抓前有機率轉變，最後由 GameState 同步回全域風向。

enum Stage { OBSERVE, STALK, CHASE, FIGHT, POUNCE, DONE }
enum Result { ONGOING, SUCCESS, PREY_FLED, PLAYER_GAVE_UP }

const STAGE_NAMES := {
	Stage.OBSERVE: "observe", Stage.STALK: "stalk", Stage.CHASE: "chase",
	Stage.FIGHT: "fight", Stage.POUNCE: "pounce",
}

var wolf: Wolf
var animal_id: String
var life_stage: String
var depth: String
var terrain: String

var stage: int = Stage.STALK
var result: int = Result.ONGOING

var prey_detection: float
var prey_stamina: float
var prey_speed: float
var prey_counter_attack: float
var prey_hunger_value: float

var is_night: bool = false
var wind_dir: int = 0 # 全域風向（0～3），狩獵途中可能轉變
var prey_dir: int = 0 # 獵物相對於狼的方位（0～3）
var experience: Array[String] = [] # 這次狩獵累積經驗的能力值（不重複）

var observed: bool = false # 觀察成功，得知獵物狀態
var stalk_bonus: float = 0.0 # 觀察帶到潛近的加成
var chase_bonus: float = 0.0 # 潛近帶到追擊的加成（追擊起點）
var fight_state: Dictionary = {} # 見 FightRules
var fled: bool = false # 獵物逃走（可再追）

# detection_mod：時段等外部因素對獵物警覺的修正（例如深夜 -10）。
# p_terrain：遭遇時所在的地形（探索的地點特徵）。
func _init(p_wolf: Wolf, p_animal_id: String, p_life_stage: String, detection_mod: float = 0.0,
		p_wind_dir: int = 0, p_prey_dir: int = 0, p_terrain: String = "") -> void:
	wolf = p_wolf
	animal_id = p_animal_id
	life_stage = p_life_stage
	is_night = detection_mod < 0.0
	wind_dir = p_wind_dir
	prey_dir = p_prey_dir
	terrain = p_terrain
	var animal_data: Dictionary = GameData.animals.get(animal_id, {})
	var stats: Dictionary = animal_data.get(life_stage, animal_data.get("adult", {}))
	prey_detection = float(stats.get("detection", 40)) + detection_mod
	prey_stamina = float(stats.get("stamina", 40))
	prey_speed = float(stats.get("speed", 40))
	prey_counter_attack = float(stats.get("counter_attack", 0))
	prey_hunger_value = float(stats.get("hunger_value", 30))
	depth = depth_of(animal_id, life_stage)
	match depth:
		"simple": stage = Stage.POUNCE
		"full": stage = Stage.OBSERVE
		_: stage = Stage.STALK
	fight_state = {"wounds": 0, "next_bonus": 0.0, "counter_reduction": 0.0, "chase_bonus": 0.0}

static func depth_of(p_animal_id: String, p_life_stage: String) -> String:
	return str(GameData.animals.get(p_animal_id, {}).get("depth", {}).get(p_life_stage, "standard"))

static func depth_turns(p_depth: String) -> int:
	return int(GameData.balance.get("hunt", {}).get("depth_turns", {}).get(p_depth, 2))

static func clamp_chance(value: float) -> float:
	return clamp(value, 0.05, 0.95)

func _tuning() -> Dictionary:
	return GameData.balance.get("hunt", {})

func stage_name() -> String:
	return STAGE_NAMES.get(stage, "")

# --- 風向 ---

# 風從哪個方向吹來（wind_dir）與獵物方位相同 = 逆風；相反 = 順風；其他 = 側風。
static func relative_wind(p_wind_dir: int, p_prey_dir: int) -> String:
	var diff: int = posmod(p_wind_dir - p_prey_dir, 4)
	if diff == 0:
		return "headwind"
	if diff == 2:
		return "tailwind"
	return "crosswind"

func wind_state() -> String:
	return relative_wind(wind_dir, prey_dir)

func _maybe_shift_wind() -> bool:
	if RNGService.chance(float(_tuning().get("wind_shift_chance_per_stage", 0.08))):
		wind_dir = posmod(wind_dir + (1 if RNGService.chance(0.5) else -1), 4)
		return true
	return false

# 繞到下風處需要的額外回合：逆風 0、側風 1、順風 2。
func downwind_turns() -> int:
	return int(_tuning().get("stalk", {}).get("downwind_turns", {}).get(wind_state(), 0))

func _terrain_mod(key: String) -> float:
	return float(_tuning().get("terrain_mods", {}).get(terrain, {}).get(key, 0.0))

func _option_available(opt: Dictionary) -> bool:
	return not opt.has("terrain") or opt["terrain"].has(terrain)

# --- 選項（可預覽，不擲骰） ---
# 每個選項：{"id", "label_key", "chance", "factors", "turns", "stamina"}
# 因素格式：{"key": 翻譯鍵, "good": bool, "weight": 對成功率的影響大小, "n": 選填, "info": 只是資訊}

func options() -> Array:
	var list: Array = []
	match stage:
		Stage.POUNCE:
			for id in _tuning().get("pounce", {}).get("options", {}).keys():
				list.append(_pounce_option(id))
		Stage.OBSERVE:
			list.append(_observe_option())
			list.append({"id": "skip_observe", "label_key": "hunt.option.skip_observe", "turns": 0, "stamina": 0.0})
		Stage.STALK:
			var opts: Dictionary = _tuning().get("stalk", {}).get("options", {})
			for id in opts.keys():
				if _option_available(opts[id]):
					list.append(_stalk_option(id))
		Stage.CHASE:
			var opts: Dictionary = _tuning().get("chase", {}).get("options", {})
			for id in opts.keys():
				if _option_available(opts[id]):
					list.append(_chase_option(id))
		Stage.FIGHT:
			for id in FightRules.move_ids():
				var info := FightRules.chance(wolf, prey_counter_attack, id, fight_state)
				_add_common_factors(info["factors"])
				list.append({"id": id, "label_key": "hunt.option." + id, "chance": info["chance"],
					"factors": info["factors"], "turns": 0, "stamina": 0.0})
	return list

func _pounce_option(id: String) -> Dictionary:
	var cfg: Dictionary = _tuning().get("pounce", {})
	var opt: Dictionary = cfg.get("options", {}).get(id, {})
	var factors: Array = []
	var avg: float = (wolf.effective_speed() + wolf.effective_skill()) * 0.5
	var diff: float = (avg - prey_speed) / float(cfg.get("divisor", 200))
	_add_speed_factor(factors, diff)
	var wind: String = wind_state()
	var w: float = float(_tuning().get("stalk", {}).get("wind_bonus", {}).get(wind, 0.0)) * float(cfg.get("wind_mult", 0.5))
	_add_wind_factor(factors, wind, w)
	var t: float = _terrain_mod("stalk") * float(cfg.get("terrain_mult", 0.5))
	_add_terrain_factor(factors, t)
	_add_common_factors(factors)
	_add_turns_factor(factors, int(opt.get("turns", 0)))
	var value: float = float(cfg.get("base", 0.7)) + diff + w + t + float(opt.get("bonus", 0.0))
	return {"id": id, "label_key": "hunt.option." + id, "chance": clamp_chance(value), "factors": factors,
		"turns": int(opt.get("turns", 0)), "stamina": float(opt.get("stamina", 0))}

func _observe_option() -> Dictionary:
	var cfg: Dictionary = _tuning().get("observe", {})
	var factors: Array = []
	var diff: float = (wolf.effective_perception() - prey_detection) / float(cfg.get("perception_divisor", 140))
	_add_alert_factor(factors, diff)
	var t: float = _terrain_mod("observe")
	_add_terrain_factor(factors, t)
	_add_common_factors(factors)
	return {"id": "observe", "label_key": "hunt.option.observe", "chance": clamp_chance(float(cfg.get("base", 0.65)) + diff + t),
		"factors": factors, "turns": 0, "stamina": 0.0}

func _stalk_option(id: String) -> Dictionary:
	var cfg: Dictionary = _tuning().get("stalk", {})
	var opt: Dictionary = cfg.get("options", {}).get(id, {})
	var factors: Array = []
	var diff: float = (wolf.effective_skill() - prey_detection) / float(cfg.get("skill_divisor", 110))
	_add_alert_factor(factors, diff)
	var wind: String = "headwind" if opt.get("as_headwind", false) else wind_state()
	var w: float = float(cfg.get("wind_bonus", {}).get(wind, 0.0))
	_add_wind_factor(factors, wind, w)
	var t: float = _terrain_mod("stalk")
	_add_terrain_factor(factors, t)
	if stalk_bonus > 0.0:
		factors.append({"key": "factor.observed", "good": true, "weight": stalk_bonus})
	_add_common_factors(factors)
	var turns: int = int(opt.get("turns", 0)) + (downwind_turns() if opt.get("as_headwind", false) else 0)
	_add_turns_factor(factors, turns)
	var value: float = float(cfg.get("base", 0.58)) + diff + w + t + stalk_bonus + float(opt.get("bonus", 0.0))
	return {"id": id, "label_key": "hunt.option." + id, "chance": clamp_chance(value), "factors": factors,
		"turns": turns, "stamina": float(opt.get("stamina", 0))}

func _chase_option(id: String) -> Dictionary:
	var cfg: Dictionary = _tuning().get("chase", {})
	var opt: Dictionary = cfg.get("options", {}).get(id, {})
	var factors: Array = []
	var stat: String = str(opt.get("stat", "speed"))
	var stat_value: float = wolf.effective_skill() if stat == "skill" else wolf.effective_speed()
	# 小型獵物（狐狸等）是年輕或年老的狼可靠的食物來源，牠們的速度影響比鹿小
	# （DESIGN.md「容易捕捉但營養低」）。
	var small: bool = str(GameData.animals.get(animal_id, {}).get("size", "")) == "small"
	var base: float = float(cfg.get("base_small", 0.75)) if small else float(cfg.get("base", 0.58))
	var diff: float = (stat_value - prey_speed) / float(cfg.get("speed_divisor_small" if small else "speed_divisor", 110))
	if stat == "speed_half":
		diff *= 0.5
	if stat == "skill":
		if diff >= 0.0:
			factors.append({"key": "factor.skilled", "good": true, "weight": diff})
		else:
			factors.append({"key": "factor.unskilled", "good": false, "weight": -diff})
	else:
		_add_speed_factor(factors, diff)
	var t: float = _terrain_mod("chase") + (_terrain_mod("sprint") if id == "sprint" else 0.0)
	_add_terrain_factor(factors, t)
	if chase_bonus > 0.0:
		factors.append({"key": "factor.close_start", "good": true, "weight": chase_bonus})
	var cost: float = float(opt.get("stamina", 10))
	var exhausted: float = 0.15 if wolf.stamina - cost <= 0.0 else 0.0
	if exhausted > 0.0:
		factors.append({"key": "factor.tired", "good": false, "weight": exhausted})
	_add_common_factors(factors)
	_add_turns_factor(factors, int(opt.get("turns", 0)))
	var value: float = base + diff + t + chase_bonus + float(opt.get("bonus", 0.0)) - exhausted
	return {"id": id, "label_key": "hunt.option." + id, "chance": clamp_chance(value), "factors": factors,
		"turns": int(opt.get("turns", 0)), "stamina": cost, "fight_bonus": float(opt.get("fight_bonus", 0.0))}

func _add_alert_factor(factors: Array, diff: float) -> void:
	if diff >= 0.0:
		factors.append({"key": "factor.prey_unaware", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.prey_alert", "good": false, "weight": -diff})
	if is_night:
		factors.append({"key": "factor.night", "good": true, "weight": 0.07})

func _add_speed_factor(factors: Array, diff: float) -> void:
	if diff >= 0.0:
		factors.append({"key": "factor.faster", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.slower", "good": false, "weight": -diff})

func _add_wind_factor(factors: Array, state: String, bonus: float) -> void:
	factors.append({"key": "factor.wind." + state, "good": bonus >= 0.0, "weight": absf(bonus)})

func _add_terrain_factor(factors: Array, bonus: float) -> void:
	if terrain == "" or absf(bonus) < 0.001:
		return
	factors.append({"key": "factor.terrain." + terrain, "good": bonus > 0.0, "weight": absf(bonus)})

func _add_turns_factor(factors: Array, turns: int) -> void:
	if turns > 0:
		factors.append({"key": "factor.extra_turns", "good": false, "weight": 0.0, "n": turns, "info": true})

# 飢餓、吃太撐、重傷：只在有影響時列出。
func _add_common_factors(factors: Array) -> void:
	var p: Dictionary = GameData.balance.get("hunger_penalties", {})
	if wolf.hunger < float(p.get("severe_threshold", 10)):
		factors.append({"key": "factor.hungry", "good": false, "weight": 0.06})
	if wolf.is_overfed():
		factors.append({"key": "factor.overfed", "good": false, "weight": 0.05})
	if wolf.injury == Wolf.Injury.HEAVY:
		factors.append({"key": "factor.injured", "good": false, "weight": 0.08})

# 依影響大小排序，取前 count 個。
static func top_factors(factors: Array, count: int) -> Array:
	var sorted := factors.duplicate()
	sorted.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	return sorted.slice(0, count)

static func main_negative_factor(factors: Array) -> Dictionary:
	var worst: Dictionary = {}
	for f in factors:
		if not f["good"] and not f.get("info", false) and (worst.is_empty() or float(f["weight"]) > float(worst["weight"])):
			worst = f
	return worst

static func reason_from_factor(factor: Dictionary) -> String:
	if factor.is_empty():
		return ""
	return "reason." + str(factor["key"]).trim_prefix("factor.").replace(".", "_")

func _gain(stat: String) -> void:
	if not experience.has(stat):
		experience.append(stat)

func _find_option(id: String) -> Dictionary:
	for opt in options():
		if opt["id"] == id:
			return opt
	return {}

# 獵物狀態（觀察成功後顯示）：用描述而非數字。
func prey_state_keys() -> Array:
	var keys: Array = []
	keys.append("prey_state.alert" if prey_detection >= wolf.effective_perception() else "prey_state.calm")
	keys.append("prey_state.strong" if prey_stamina >= 50.0 else "prey_state.tired")
	if prey_counter_attack >= 20.0:
		keys.append("prey_state.dangerous")
	return keys

# --- 執行（擲骰） ---
# 回傳 {"success", "text_key", "reason_key", "turns", "wind_shifted", ...}

func choose(id: String) -> Dictionary:
	var opt := _find_option(id)
	if opt.is_empty():
		return {"success": false}
	wolf.stamina -= float(opt.get("stamina", 0.0))
	var res: Dictionary
	match stage:
		Stage.POUNCE: res = _do_pounce(opt)
		Stage.OBSERVE: res = _do_observe(opt)
		Stage.STALK: res = _do_stalk(opt)
		Stage.CHASE: res = _do_chase(opt)
		Stage.FIGHT: res = _do_fight(opt)
		_: res = {"success": false}
	res["turns"] = int(res.get("turns", 0)) + int(opt.get("turns", 0))
	return res

func _roll(chance_value: float) -> bool:
	return RNGService.chance(clamp_chance(chance_value))

func _do_pounce(opt: Dictionary) -> Dictionary:
	var shifted := _maybe_shift_wind()
	if _roll(float(opt["chance"])):
		_gain("speed")
		_gain("skill")
		return _kill("hunt.pounce.success")
	return _flee("hunt.pounce.fail", opt["factors"], shifted)

func _do_observe(opt: Dictionary) -> Dictionary:
	stage = Stage.STALK
	if opt["id"] == "skip_observe":
		return {"success": true, "text_key": ""}
	var cfg: Dictionary = _tuning().get("observe", {})
	if _roll(float(opt["chance"])):
		observed = true
		stalk_bonus = float(cfg.get("stalk_bonus", 0.06))
		_gain("perception")
		return {"success": true, "text_key": "hunt.observe.success", "prey_state": prey_state_keys()}
	# 觀察失敗：獵物察覺到動靜，變得更警覺，但還沒逃。
	prey_detection += float(cfg.get("fail_alert", 10))
	return {"success": false, "text_key": "hunt.observe.fail"}

func _do_stalk(opt: Dictionary) -> Dictionary:
	var shifted := _maybe_shift_wind()
	var stalk_opt: Dictionary = _tuning().get("stalk", {}).get("options", {}).get(opt["id"], {})
	if _roll(float(opt["chance"])):
		stage = Stage.CHASE
		chase_bonus = float(stalk_opt.get("chase_bonus", 0.0))
		_gain("skill")
		return {"success": true, "text_key": "hunt.stalk.success", "wind_shifted": shifted}
	# 選擇繞到下風處時，已經依當下風向重新站位，不算「風向轉了」。
	return _flee("hunt.stalk.fail", opt["factors"], shifted and not stalk_opt.get("as_headwind", false))

func _do_chase(opt: Dictionary) -> Dictionary:
	if _roll(float(opt["chance"])):
		_gain("speed")
		if depth == "full":
			stage = Stage.FIGHT
			fight_state["chase_bonus"] = float(opt.get("fight_bonus", 0.0))
			return {"success": true, "text_key": "hunt.chase.success"}
		return _kill("hunt.chase.catch")
	return _flee("hunt.chase.fail", opt["factors"], false)

func _do_fight(opt: Dictionary) -> Dictionary:
	var r := FightRules.resolve_round(wolf, prey_counter_attack, opt["id"], fight_state)
	if r["success"]:
		_gain("strength" if opt["id"] == "bite_leg" else "skill")
	match r["outcome"]:
		"kill":
			_gain("strength")
			return _kill("hunt.fight.success")
		"escape":
			var escaped := _flee("hunt.fight.escape", r["factors"], false)
			escaped["damage"] = r.get("damage", 0.0)
			return escaped
	# 搏鬥繼續：下一回合要多花回合。
	var key: String = "hunt.fight.miss"
	if r["success"]:
		key = "hunt.fight.hit_" + str(opt["id"])
	elif float(r.get("damage", 0.0)) > 0.0:
		key = "hunt.fight.counter"
	return {"success": r["success"], "text_key": key, "damage": r.get("damage", 0.0),
		"turns": int(_tuning().get("fight", {}).get("extra_round_turns", 1)), "wounds": int(fight_state.get("wounds", 0))}

# 制伏獵物一定是力氣活，任何深度的成功都累積力量經驗。
func _kill(text_key: String) -> Dictionary:
	_gain("strength")
	stage = Stage.DONE
	result = Result.SUCCESS
	# 進食回復固定為獵物的 hunger_value；分段進食在 1.5 第 6 步處理。
	wolf.hunger += prey_hunger_value
	return {"success": true, "text_key": text_key, "hunger_gain": prey_hunger_value}

# 獵物逃走：GameState 會把它變成可再追的新鮮足跡。
# 失敗主因：風向剛轉成順風時以「風向轉了」為主因，否則取影響最大的不利因素。
func _flee(text_key: String, factors: Array, wind_shifted: bool) -> Dictionary:
	stage = Stage.DONE
	result = Result.PREY_FLED
	fled = true
	var reason_key: String = ""
	if wind_shifted and wind_state() == "tailwind":
		reason_key = "reason.wind_turned"
	else:
		reason_key = reason_from_factor(main_negative_factor(factors))
	return {"success": false, "text_key": text_key, "reason_key": reason_key, "wind_shifted": wind_shifted}

func give_up() -> void:
	result = Result.PLAYER_GAVE_UP
	stage = Stage.DONE
