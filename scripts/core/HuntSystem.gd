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
#
# 獵物反應（SPEC「獵物反應」，步驟 5）：flee 逃跑、stand 站定、counter 反擊、
# hide 躲藏、protect 護幼（母鹿在附近）。反應依獵物、是否受傷與地形決定，
# 追擊中可能改變。追擊是多回合：失敗不一定逃掉，超過 free_rounds 後成功率逐回合下降。

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
# 這次狩獵每一步的練習（Growth.apply_practice）：{stat, success, streak, kind}；streak = 這一步之前連續失敗的次數。
var practice: Array = []
var fail_streak: int = 0

var observed: bool = false # 觀察成功，得知獵物狀態
var stalk_bonus: float = 0.0 # 觀察帶到潛近的加成
var chase_bonus: float = 0.0 # 潛近帶到追擊的加成（追擊起點）
var fight_state: Dictionary = {} # 見 FightRules
var fled: bool = false # 獵物逃走（可再追）

var injured: bool = false # 受傷個體：走簡易流程，速度較慢，可能反擊
var reaction: String = "flee"
var mother_nearby: bool = false # 護幼：獵幼鹿時母鹿在附近
var hiding: bool = false # 獵物躲起來了，要靠感知找出來
var hid_once: bool = false # 一次狩獵最多躲一次
var pounce_bonus: float = 0.0 # 找出躲藏的獵物後，下一次撲抓的加成
var chase_round: int = 0 # 已經追了幾回合
var prey_stamina_max: float
var prey_stamina_cur: float
var gave_up_stage: int = -1 # 放棄時所在的階段（記錄狩獵傾向）
var knowledge_bonus: Dictionary = {} # 獵物弱點知識：{option_id: 加成}
var successful_options: Array[String] = [] # 這次狩獵成功過的選項（累積獵物弱點知識）
var storm: bool = false # 暴雨：雨聲掩蓋腳步（潛近較容易），風向每個階段都可能改變
var tendency: Dictionary = {} # 目前的主要狩獵傾向 {"type", "effect"}（見 GameState.current_tendency）
var decisions: Array[String] = [] # 這次狩獵的決策（「階段.選項」），記錄狩獵傾向
var wind_failure: bool = false # 因風向轉變而失敗（試玩紀錄）

# detection_mod：時段等外部因素對獵物警覺的修正（例如深夜 -10）。
# p_terrain：遭遇時所在的地形（探索的地點特徵）。
func _init(p_wolf: Wolf, p_animal_id: String, p_life_stage: String, detection_mod: float = 0.0,
		p_wind_dir: int = 0, p_prey_dir: int = 0, p_terrain: String = "", p_injured: bool = false) -> void:
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
	prey_stamina_max = max(1.0, prey_stamina)
	prey_stamina_cur = prey_stamina_max
	injured = p_injured
	depth = depth_of(animal_id, life_stage)
	if injured:
		depth = "simple"
		prey_speed *= float(_reaction_cfg().get("injured_speed_mult", 0.8))
	_roll_reaction()
	match depth:
		"simple": stage = Stage.POUNCE
		"full": stage = Stage.OBSERVE
		_: stage = Stage.STALK
	fight_state = {"wounds": 0, "next_bonus": 0.0, "counter_reduction": 0.0, "chase_bonus": 0.0, "tendency_bonus": 0.0}

static func depth_of(p_animal_id: String, p_life_stage: String) -> String:
	return str(GameData.animals.get(p_animal_id, {}).get("depth", {}).get(p_life_stage, "standard"))

# 分段進食的段數（0 表示一次吃完）。見 balance.json 的 "feeding"。
static func feeding_segments(p_animal_id: String, p_life_stage: String) -> int:
	return int(GameData.balance.get("feeding", {}).get("segments", {}).get(p_animal_id, {}).get(p_life_stage, 0))

static func depth_turns(p_depth: String) -> int:
	return int(GameData.balance.get("hunt", {}).get("depth_turns", {}).get(p_depth, 2))

static func clamp_chance(value: float) -> float:
	return clamp(value, 0.05, 0.95)

func _tuning() -> Dictionary:
	return GameData.balance.get("hunt", {})

func _reaction_cfg() -> Dictionary:
	return _tuning().get("reactions", {})

func _reaction_table() -> Dictionary:
	return GameData.animals.get(animal_id, {}).get("reactions", {}).get(life_stage, {})

# 決定獵物的反應。受傷個體被逼近時可能反擊；雄鹿背靠密林、倒木時容易站定；
# 幼鹿附近可能有母鹿護幼。躲藏在撲抓失敗時才判定。
func _roll_reaction() -> void:
	var cfg := _reaction_cfg()
	var table := _reaction_table()
	reaction = "flee"
	if injured:
		if RNGService.chance(float(cfg.get("injured_counter_chance", 0.5))):
			reaction = "counter"
		return
	if table.has("stand"):
		var mult: float = float(cfg.get("stand_terrain_mult", {}).get(terrain, 1.0))
		if RNGService.chance(float(table["stand"]) * mult):
			reaction = "stand"
	if table.has("protect") and RNGService.chance(float(table["protect"])):
		mother_nearby = true
		reaction = "protect"

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
	var chance_value: float = float(GameData.events.get("storm", {}).get("wind_shift_chance", 0.5)) if storm \
		else float(_tuning().get("wind_shift_chance_per_stage", 0.08))
	if RNGService.chance(chance_value):
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
			if hiding:
				list.append(_search_option())
			else:
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
			if reaction == "stand":
				list.append(_harass_option())
				list.append({"id": "attack_standing", "label_key": "hunt.option.attack_standing", "turns": 0, "stamina": 0.0,
					"factors": [{"key": "factor.standing_danger", "good": false, "weight": 0.0, "info": true}]})
			else:
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
	for opt in list:
		_annotate(opt)
	return list

# 代價列（SPEC 1.6「選項的代價與收穫」）：除了體力與回合，再補上
# trains（練到的能力，來自 balance.json 的 trains）、next_bonus（對下一階段的加成）、
# injury_risk（這一步可能受傷的機率）。沒有的項目不放。
func _annotate(opt: Dictionary) -> void:
	var t := _tuning()
	var id: String = opt["id"]
	var cfg: Dictionary = {}
	match stage:
		Stage.POUNCE:
			cfg = _reaction_cfg().get("search", {}) if id == "search" else t.get("pounce", {}).get("options", {}).get(id, {})
			var risk: float = 0.0
			if mother_nearby and id != "search":
				risk = float(_reaction_cfg().get("mother_charge_chance", 0.35))
			if reaction == "counter" and id != "search":
				risk = max(risk, (1.0 - float(opt.get("chance", 0.0))) * min(1.0, prey_counter_attack / 100.0 + 0.3))
			if risk > 0.0:
				opt["injury_risk"] = risk
		Stage.OBSERVE:
			if id == "observe":
				cfg = t.get("observe", {})
				opt["next_bonus"] = {"stage": "stalk", "value": float(cfg.get("stalk_bonus", 0.0))}
		Stage.STALK:
			cfg = t.get("stalk", {}).get("options", {}).get(id, {})
			if float(cfg.get("chase_bonus", 0.0)) > 0.0:
				opt["next_bonus"] = {"stage": "chase", "value": float(cfg["chase_bonus"])}
		Stage.CHASE:
			match id:
				"harass":
					cfg = _reaction_cfg().get("harass", {})
					opt["injury_risk"] = (1.0 - float(opt.get("chance", 0.0))) * prey_counter_attack / 100.0
				"attack_standing":
					opt["injury_risk"] = min(1.0, prey_counter_attack / 100.0 * float(_reaction_cfg().get("standing_attack", {}).get("counter_mult", 1.5)))
				_:
					cfg = t.get("chase", {}).get("options", {}).get(id, {})
					if depth == "full" and float(cfg.get("fight_bonus", 0.0)) > 0.0:
						opt["next_bonus"] = {"stage": "fight", "value": float(cfg["fight_bonus"])}
		Stage.FIGHT:
			cfg = t.get("fight", {}).get("moves", {}).get(id, {})
			opt["injury_risk"] = (1.0 - float(opt.get("chance", 0.0))) * FightRules.counter_chance(prey_counter_attack, id, fight_state)
			if float(cfg.get("next_bonus", 0.0)) > 0.0:
				opt["next_bonus"] = {"stage": "fight", "value": float(cfg["next_bonus"])}
	if float(cfg.get("prey_drain", 0.0)) > 0.0:
		opt["prey_drain"] = float(cfg["prey_drain"])
	if cfg.has("trains"):
		opt["trains"] = cfg["trains"]
		opt["train_mult"] = float(cfg.get("train_mult", 1.0))
		opt["train_weights"] = cfg.get("train_weights", {})

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
	if mother_nearby:
		var penalty: float = float(_reaction_cfg().get("mother_pounce_penalty", 0.1))
		factors.append({"key": "factor.mother_nearby", "good": false, "weight": penalty})
		t -= penalty
	if pounce_bonus > 0.0:
		factors.append({"key": "factor.found_hiding", "good": true, "weight": pounce_bonus})
	if reaction == "counter":
		factors.append({"key": "factor.cornered", "good": false, "weight": 0.0, "info": true})
	var value: float = float(cfg.get("base", 0.7)) + diff + w + t + pounce_bonus + float(opt.get("bonus", 0.0))
	return {"id": id, "label_key": "hunt.option." + id, "chance": clamp_chance(value), "factors": factors,
		"turns": int(opt.get("turns", 0)), "stamina": float(opt.get("stamina", 0))}

func _observe_option() -> Dictionary:
	var cfg: Dictionary = _tuning().get("observe", {})
	var factors: Array = []
	var diff: float = (wolf.effective_perception() - prey_detection) / float(cfg.get("perception_divisor", 140))
	_add_alert_factor(factors, diff)
	var t: float = _terrain_mod("observe")
	_add_terrain_factor(factors, t)
	var cautious: float = _tendency_effect("cautious")
	if cautious > 0.0:
		factors.append({"key": "factor.tendency.cautious", "good": true, "weight": cautious})
		t += cautious
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
	if storm:
		var rain: float = float(GameData.events.get("storm", {}).get("stalk_bonus", 0.1))
		factors.append({"key": "factor.storm_cover", "good": true, "weight": rain})
		t += rain
	var stealth: float = _tendency_effect("stealth")
	if stealth > 0.0:
		factors.append({"key": "factor.tendency.stealth", "good": true, "weight": stealth})
		t += stealth
	_add_common_factors(factors)
	var turns: int = int(opt.get("turns", 0)) + (downwind_turns() if opt.get("as_headwind", false) else 0)
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
	# 追太久成功率逐回合下降；獵物體力下降則較容易追上。
	var fatigue: float = max(0, chase_round + 1 - int(cfg.get("free_rounds", 2))) * float(cfg.get("fatigue_per_round", 0.1))
	if fatigue > 0.0:
		factors.append({"key": "factor.long_chase", "good": false, "weight": fatigue})
	var tiring: float = (1.0 - prey_stamina_cur / prey_stamina_max) * float(cfg.get("prey_tired_bonus", 0.25))
	if tiring > 0.01:
		factors.append({"key": "factor.prey_tiring", "good": true, "weight": tiring})
	t += tiring - fatigue
	# 追獵型：追擊的體力消耗逐步降低（顯示在因素欄）。
	var pursuit: float = _tendency_effect("pursuit")
	var cost: float = float(opt.get("stamina", 10)) * (1.0 - pursuit)
	if pursuit > 0.0:
		factors.append({"key": "factor.tendency.pursuit", "good": true, "weight": 0.0, "info": true, "n": int(round(pursuit * 100.0))})
	var exhausted: float = 0.15 if wolf.stamina - cost <= 0.0 else 0.0
	if exhausted > 0.0:
		factors.append({"key": "factor.tired", "good": false, "weight": exhausted})
	_add_common_factors(factors)
	var known: float = float(knowledge_bonus.get(id, 0.0))
	if known > 0.0:
		factors.append({"key": "factor.knowledge", "good": true, "weight": known})
	var value: float = base + diff + t + chase_bonus + known + float(opt.get("bonus", 0.0)) - exhausted
	return {"id": id, "label_key": "hunt.option." + id, "chance": clamp_chance(value), "factors": factors,
		"turns": int(opt.get("turns", 0)), "stamina": cost, "fight_bonus": float(opt.get("fight_bonus", 0.0)),
		"prey_drain": float(opt.get("prey_drain", 15))}

func _search_option() -> Dictionary:
	var cfg: Dictionary = _reaction_cfg().get("search", {})
	var factors: Array = []
	var diff: float = (wolf.effective_perception() - prey_detection) / float(cfg.get("perception_divisor", 120))
	if diff >= 0.0:
		factors.append({"key": "factor.sharp_nose", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.faint_trail", "good": false, "weight": -diff})
	_add_common_factors(factors)
	return {"id": "search", "label_key": "hunt.option.search", "chance": clamp_chance(float(cfg.get("base", 0.5)) + diff),
		"factors": factors, "turns": 0, "stamina": 0.0}

func _harass_option() -> Dictionary:
	var cfg: Dictionary = _reaction_cfg().get("harass", {})
	var factors: Array = []
	var diff: float = (wolf.effective_skill() - 40.0) / float(cfg.get("skill_divisor", 120))
	if diff >= 0.0:
		factors.append({"key": "factor.skilled", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.unskilled", "good": false, "weight": -diff})
	factors.append({"key": "factor.counter_risk", "good": false, "weight": 0.0, "info": true})
	_add_common_factors(factors)
	return {"id": "harass", "label_key": "hunt.option.harass", "chance": clamp_chance(float(cfg.get("base", 0.55)) + diff),
		"factors": factors, "turns": int(cfg.get("turns", 1)), "stamina": float(cfg.get("stamina", 10))}

# 雙方體力的描述（每回合追擊顯示）。感知高時才看得到獵物體力的精確數字。
func wolf_stamina_key() -> String:
	if wolf.stamina >= 60.0:
		return "stamina.wolf.fresh"
	if wolf.stamina >= 30.0:
		return "stamina.wolf.panting"
	return "stamina.wolf.exhausted"

func prey_stamina_key() -> String:
	var ratio: float = prey_stamina_cur / prey_stamina_max
	if ratio >= 0.7:
		return "stamina.prey.fresh"
	if ratio >= 0.4:
		return "stamina.prey.panting"
	return "stamina.prey.slowing"

func prey_stamina_precise() -> int:
	if wolf.effective_perception() < float(_tuning().get("chase", {}).get("precise_perception", 60)):
		return -1
	return int(round(prey_stamina_cur / prey_stamina_max * 100.0))

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

# 每一步都算練習：成功與失敗都記下，失敗的份量由 Growth 依連續失敗次數遞減。
func _practice(opt: Dictionary, success: bool) -> void:
	for stat in opt.get("trains", []):
		var repeat: int = practice.filter(func(p): return p["stat"] == str(stat)).size()
		practice.append({"stat": str(stat), "success": success, "streak": 0 if success else fail_streak, "repeat": repeat,
			"mult": float(opt.get("train_mult", 1.0)) * float(opt.get("train_weights", {}).get(stat, 1.0))})
	if not opt.get("trains", []).is_empty():
		fail_streak = 0 if success else fail_streak + 1

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
	# 感知夠高才能預判牠的反應。
	if wolf.effective_perception() >= prey_detection - float(_reaction_cfg().get("predict_margin", 5)):
		keys.append("prey_reaction." + reaction)
	else:
		keys.append("prey_reaction.unknown")
	return keys

# --- 執行（擲骰） ---
# 回傳 {"success", "text_key", "reason_key", "turns", "wind_shifted", ...}

func _tendency_effect(type: String) -> float:
	return float(tendency.get("effect", 0.0)) if tendency.get("type", "") == type else 0.0

func choose(id: String) -> Dictionary:
	var opt := _find_option(id)
	if opt.is_empty():
		return {"success": false}
	decisions.append(stage_name() + "." + id)
	wolf.stamina -= float(opt.get("stamina", 0.0))
	var res: Dictionary
	match stage:
		Stage.POUNCE: res = _do_search(opt) if hiding else _do_pounce(opt)
		Stage.OBSERVE: res = _do_observe(opt)
		Stage.STALK: res = _do_stalk(opt)
		Stage.CHASE:
			match id:
				"harass": res = _do_harass(opt)
				"attack_standing": res = _do_attack_standing()
				_: res = _do_chase(opt)
		Stage.FIGHT: res = _do_fight(opt)
		_: res = {"success": false}
	res["turns"] = int(res.get("turns", 0)) + int(opt.get("turns", 0))
	_practice(opt, bool(res.get("success", false)))
	return res

func _roll(chance_value: float) -> bool:
	return RNGService.chance(clamp_chance(chance_value))

func _do_pounce(opt: Dictionary) -> Dictionary:
	var cfg := _reaction_cfg()
	var shifted := _maybe_shift_wind()
	var notes: Array = []
	var damage: float = 0.0
	# 護幼：母鹿可能衝過來。
	if mother_nearby and RNGService.chance(float(cfg.get("mother_charge_chance", 0.35))):
		damage += _hurt_wolf(int(cfg.get("mother_damage_min", 8)), int(cfg.get("mother_damage_max", 18)))
		notes.append("hunt.mother.charge")
	pounce_bonus = 0.0
	if _roll(float(opt["chance"])):
		var won := _kill("hunt.pounce.success")
		won["notes"] = notes
		won["damage"] = damage
		return won
	# 反擊：受傷個體被逼近時反撲，跑不遠，可以再撲但每次都可能受傷。
	if reaction == "counter":
		if RNGService.chance(prey_counter_attack / 100.0 + 0.3):
			damage += _hurt_wolf(int(cfg.get("counter_damage_min", 5)), int(cfg.get("counter_damage_max", 12)))
			notes.append("hunt.counter.hit")
		return {"success": false, "text_key": "hunt.counter.miss", "notes": notes, "damage": damage, "turns": 1}
	# 躲藏：一次狩獵最多躲一次，之後要靠感知找出來。
	var hide_chance: float = float(_reaction_table().get("hide", 0.0))
	if not hid_once and RNGService.chance(hide_chance):
		hiding = true
		hid_once = true
		return {"success": false, "text_key": "hunt.hide.start", "notes": notes, "damage": damage}
	var fail := _flee("hunt.pounce.fail", opt["factors"], shifted)
	fail["notes"] = notes
	fail["damage"] = damage
	return fail

func _do_search(opt: Dictionary) -> Dictionary:
	if _roll(float(opt["chance"])):
		hiding = false
		pounce_bonus = float(_reaction_cfg().get("search", {}).get("pounce_bonus", 0.1))
		return {"success": true, "text_key": "hunt.hide.found"}
	# 找不到就失去目標，沒有足跡可追。
	stage = Stage.DONE
	result = Result.PREY_FLED
	return {"success": false, "text_key": "hunt.hide.lost", "reason_key": reason_from_factor(main_negative_factor(opt["factors"]))}

func _do_harass(opt: Dictionary) -> Dictionary:
	if _roll(float(opt["chance"])):
		reaction = "flee"
		return {"success": true, "text_key": "hunt.harass.success"}
	var cfg := _reaction_cfg()
	var damage: float = 0.0
	var notes: Array = []
	if RNGService.chance(prey_counter_attack / 100.0):
		damage = _hurt_wolf(int(cfg.get("counter_damage_min", 5)), int(cfg.get("counter_damage_max", 12)))
		notes.append("hunt.counter.hit")
	return {"success": false, "text_key": "hunt.harass.fail", "notes": notes, "damage": damage}

# 直接攻擊站定的雄鹿：進入搏鬥，但成功率大降、反擊更凶。
func _do_attack_standing() -> Dictionary:
	var cfg: Dictionary = _reaction_cfg().get("standing_attack", {})
	stage = Stage.FIGHT
	fight_state["penalty"] = float(cfg.get("penalty", 0.2))
	fight_state["counter_mult_extra"] = float(cfg.get("counter_mult", 1.5))
	return {"success": true, "text_key": "hunt.stand.attack"}

# 狩獵中的反擊（母鹿衝撞、受傷個體反撲、騷擾失敗）：一次攻擊，不會致死（見 FightRules.hurt_wolf）。
func _hurt_wolf(min_dmg: int, max_dmg: int) -> float:
	var dmg: float = float(RNGService.randi_range(min_dmg, max_dmg))
	return float(FightRules.hurt_wolf(wolf, dmg, _tuning().get("fight", {}).get("parts", {}), animal_id + ".hunt", false)["damage"])

func _do_observe(opt: Dictionary) -> Dictionary:
	stage = Stage.STALK
	if opt["id"] == "skip_observe":
		return {"success": true, "text_key": ""}
	var cfg: Dictionary = _tuning().get("observe", {})
	if _roll(float(opt["chance"])):
		observed = true
		stalk_bonus = float(cfg.get("stalk_bonus", 0.06))
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
		return {"success": true, "text_key": "hunt.stalk.success", "wind_shifted": shifted}
	# 選擇繞到下風處時，已經依當下風向重新站位，不算「風向轉了」。
	return _flee("hunt.stalk.fail", opt["factors"], shifted and not stalk_opt.get("as_headwind", false))

func _do_chase(opt: Dictionary) -> Dictionary:
	var cfg: Dictionary = _tuning().get("chase", {})
	chase_round += 1
	prey_stamina_cur = max(0.0, prey_stamina_cur - float(opt.get("prey_drain", 15)))
	if _roll(float(opt["chance"])):
		successful_options.append(str(opt["id"]))
		if depth == "full":
			stage = Stage.FIGHT
			fight_state["chase_bonus"] = float(opt.get("fight_bonus", 0.0))
			return {"success": true, "text_key": "hunt.chase.success"}
		return _kill("hunt.chase.catch")
	# 沒追上：獵物拉開距離，可能就此逃掉，也可能還在視線內（下一回合多花 1 回合）。
	var over: int = max(0, chase_round - int(cfg.get("free_rounds", 2)))
	var escape: float = float(cfg.get("escape_base", 0.3)) + over * float(cfg.get("escape_per_round", 0.1)) \
		- (1.0 - prey_stamina_cur / prey_stamina_max) * 0.2
	if RNGService.chance(clamp(escape, 0.05, 0.95)):
		return _flee("hunt.chase.fail", opt["factors"], false)
	var notes: Array = []
	# 雄鹿被逼進密林、倒木時可能轉身站定。
	var stand: float = float(_reaction_table().get("stand", 0.0))
	if stand > 0.0 and RNGService.chance(stand * 0.5 * float(_reaction_cfg().get("stand_terrain_mult", {}).get(terrain, 1.0))):
		reaction = "stand"
		notes.append("hunt.stand.start")
	return {"success": false, "text_key": "hunt.chase.continue", "turns": 1, "notes": notes}

func _do_fight(opt: Dictionary) -> Dictionary:
	var r := FightRules.resolve_round(wolf, prey_counter_attack, opt["id"], fight_state)
	match r["outcome"]:
		"kill":
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

# 制伏獵物一定是力氣活，任何深度的成功都累積力量的鍛鍊點。
func _kill(text_key: String) -> Dictionary:
	practice.append({"stat": "strength", "success": true, "kind": "takedown"})
	stage = Stage.DONE
	result = Result.SUCCESS
	# 大型獵物分段吃（GameState 開始進食），小型獵物當場吃完。
	if feeding_segments(animal_id, life_stage) > 1:
		return {"success": true, "text_key": text_key, "feeding": true}
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
		wind_failure = true
	else:
		reason_key = reason_from_factor(main_negative_factor(factors))
	return {"success": false, "text_key": text_key, "reason_key": reason_key, "wind_shifted": wind_shifted}

func give_up() -> void:
	gave_up_stage = stage
	result = Result.PLAYER_GAVE_UP
	stage = Stage.DONE
