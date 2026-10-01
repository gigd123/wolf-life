class_name HuntSystem
extends RefCounted

# One hunt attempt: discover -> stalk -> chase -> fight. Small prey (hare,
# red_fox) skip straight to chase per DESIGN.md "小型獵物流程可縮短". Every
# stage can be abandoned; failure at discover/stalk/chase lets the prey flee
# with no cost beyond spent turns/stamina. All tuning numbers live under
# balance.json's "hunt" key, not here, per DESIGN.md's data-driven principle.
#
# Stage choices are meant to trade something for something, not just flavor
# text: stalk/chase approaches trade stamina for odds, a chase tactic can
# bank a bonus for the fight stage instead of boosting itself, and the three
# fight moves lean on different stats (bite_throat -> skill, pin -> strength,
# bite_leg -> balanced/safe) so a wolf's stat profile and life stage actually
# matter for which move is best.
#
# Phase 1.5 步驟 2：發現階段改用「感知」，潛近與搏鬥用「技巧」。每個選項都能先
# 預覽成功率與關鍵因素（chance_* / factors），失敗時回傳主因（reason_key）。
# 風向以相對狀態 headwind（逆風）/ crosswind（側風）/ tailwind（順風）表示，
# 每個階段有機率轉變，最後由 GameState 同步回全域風向。

enum Stage { DISCOVER, STALK, CHASE, FIGHT, DONE }
enum Result { ONGOING, SUCCESS, PREY_FLED, PLAYER_GAVE_UP }

const WIND_STATES := ["headwind", "crosswind", "tailwind"]

var wolf: Wolf
var animal_id: String
var life_stage: String
var size: String

var stage: int = Stage.DISCOVER
var result: int = Result.ONGOING
var fight_bonus_from_chase: float = 0.0

var prey_detection: float
var prey_stamina: float
var prey_speed: float
var prey_counter_attack: float
var prey_hunger_value: float

var is_night: bool = false
var wind_dir: int = 0 # 全域風向（0～3），狩獵途中可能轉變
var prey_dir: int = 0 # 獵物相對於狼的方位（0～3）
var experience: Array[String] = [] # 這次狩獵累積經驗的能力值（不重複）

# detection_mod：時段等外部因素對獵物警覺的修正（例如深夜 -10）。
func _init(p_wolf: Wolf, p_animal_id: String, p_life_stage: String, detection_mod: float = 0.0,
		p_wind_dir: int = 0, p_prey_dir: int = 0) -> void:
	wolf = p_wolf
	animal_id = p_animal_id
	life_stage = p_life_stage
	is_night = detection_mod < 0.0
	wind_dir = p_wind_dir
	prey_dir = p_prey_dir
	var animal_data: Dictionary = GameData.animals.get(animal_id, {})
	size = animal_data.get("size", "medium")
	var stats: Dictionary = animal_data.get(life_stage, {})
	prey_detection = float(stats.get("detection", 40)) + detection_mod
	prey_stamina = float(stats.get("stamina", 40))
	prey_speed = float(stats.get("speed", 40))
	prey_counter_attack = float(stats.get("counter_attack", 0))
	prey_hunger_value = float(stats.get("hunger_value", 30))
	if size == "small":
		stage = Stage.CHASE

func _tuning() -> Dictionary:
	return GameData.balance.get("hunt", {})

func _roll(success_chance: float) -> bool:
	return RNGService.chance(clamp(success_chance, 0.05, 0.95))

static func clamp_chance(value: float) -> float:
	return clamp(value, 0.05, 0.95)

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

# 每個階段開始時，風向有機率轉變。回傳是否轉變。
func _maybe_shift_wind() -> bool:
	if RNGService.chance(float(_tuning().get("wind_shift_chance_per_stage", 0.08))):
		wind_dir = posmod(wind_dir + (1 if RNGService.chance(0.5) else -1), 4)
		return true
	return false

func _wind_bonus(table_key: String, state: String) -> float:
	return float(_tuning().get(table_key, {}).get(state, 0.0))

# 繞到下風處需要的額外回合：逆風 0、側風 1、順風 2。
func downwind_turns() -> int:
	return int(_tuning().get("downwind_turns", {}).get(wind_state(), 0))

# --- 成功率與因素（可預覽，不擲骰） ---
# 因素格式：{"key": 翻譯鍵, "good": bool, "weight": 對成功率的影響大小, "n": 選填的數字}

func chance_discover() -> Dictionary:
	var t: Dictionary = _tuning()
	var factors: Array = []
	var diff: float = (wolf.effective_perception() - prey_detection) / float(t.get("discover_perception_divisor", 140))
	_add_alert_factor(factors, diff)
	var w: float = _wind_bonus("discover_wind_bonus", wind_state())
	_add_wind_factor(factors, wind_state(), w)
	_add_common_factors(factors)
	var value: float = float(t.get("discover_base", 0.6)) + diff + w
	return {"chance": clamp_chance(value), "factors": factors}

func chance_stalk(approach: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var factors: Array = []
	var diff: float = (wolf.effective_skill() - prey_detection) / float(t.get("stalk_skill_divisor", 110))
	_add_alert_factor(factors, diff)
	var state: String = "headwind" if approach == "downwind" else wind_state()
	var w: float = _wind_bonus("stalk_wind_bonus", state)
	_add_wind_factor(factors, state, w)
	if approach == "downwind" and downwind_turns() > 0:
		factors.append({"key": "factor.extra_turns", "good": false, "weight": 0.05, "n": downwind_turns(), "info": true})
	var bonus: float = float(t.get("stalk_approach_bonus", {}).get(approach, 0.0))
	_add_common_factors(factors)
	var value: float = float(t.get("stalk_base", 0.58)) + diff + w + bonus
	return {"chance": clamp_chance(value), "factors": factors}

func chance_chase(tactic: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var factors: Array = []
	# Small prey (hare/red_fox) are meant to be the reliable, low-risk food
	# source for a young or old wolf (see DESIGN.md "容易捕捉但營養低"), so
	# their raw speed counts for much less here than a deer's or bear's would.
	var base_key: String = "chase_base_small" if size == "small" else "chase_base"
	var divisor_key: String = "chase_speed_divisor_small" if size == "small" else "chase_speed_divisor"
	var diff: float = (wolf.effective_speed() - prey_speed) / float(t.get(divisor_key, 110))
	if diff >= 0.0:
		factors.append({"key": "factor.faster", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.slower", "good": false, "weight": -diff})
	var cost: float = float(t.get("chase_tactic_stamina", {}).get(tactic, 10))
	var exhausted_penalty: float = 0.0
	if wolf.stamina - cost <= 0.0:
		exhausted_penalty = 0.15
		factors.append({"key": "factor.tired", "good": false, "weight": exhausted_penalty})
	_add_common_factors(factors)
	var value: float = float(t.get(base_key, 0.58)) + diff \
		+ float(t.get("chase_tactic_bonus", {}).get(tactic, 0.0)) - exhausted_penalty
	return {"chance": clamp_chance(value), "factors": factors}

func _fight_power(move: String) -> float:
	var strength_weight: float = float(_tuning().get("fight_move_strength_weight", {}).get(move, 1.0))
	return wolf.effective_strength() * strength_weight + wolf.effective_skill() * (2.0 - strength_weight)

func chance_fight(move: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var factors: Array = []
	var diff: float = (_fight_power(move) - 40.0 - prey_counter_attack) / float(t.get("fight_power_divisor", 130))
	if diff >= 0.0:
		factors.append({"key": "factor.stronger", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.weaker", "good": false, "weight": -diff})
	if fight_bonus_from_chase > 0.0:
		factors.append({"key": "factor.chase_bonus", "good": true, "weight": fight_bonus_from_chase})
	_add_common_factors(factors)
	var value: float = float(t.get("fight_base", 0.58)) + diff + fight_bonus_from_chase \
		+ float(t.get("fight_move_success_mod", {}).get(move, 0.0))
	return {"chance": clamp_chance(value), "factors": factors}

func _add_alert_factor(factors: Array, diff: float) -> void:
	if diff >= 0.0:
		factors.append({"key": "factor.prey_unaware", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.prey_alert", "good": false, "weight": -diff})
	if is_night:
		factors.append({"key": "factor.night", "good": true, "weight": 0.07})

func _add_wind_factor(factors: Array, state: String, bonus: float) -> void:
	factors.append({"key": "factor.wind." + state, "good": bonus >= 0.0, "weight": absf(bonus)})

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

func _gain(stat: String) -> void:
	if not experience.has(stat):
		experience.append(stat)

# --- 執行（擲骰） ---

func do_discover() -> Dictionary:
	var shifted := _maybe_shift_wind()
	var info := chance_discover()
	if _roll(info["chance"]):
		stage = Stage.STALK
		_gain("perception")
		return {"success": true, "text_key": "hunt.discover.success", "wind_shifted": shifted}
	result = Result.PREY_FLED
	stage = Stage.DONE
	return _fail("hunt.discover.fail", info["factors"], shifted)

func do_stalk(approach: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var turns: int = downwind_turns() if approach == "downwind" else 0
	var shifted := _maybe_shift_wind()
	var info := chance_stalk(approach)
	wolf.stamina -= float(t.get("stalk_approach_stamina", {}).get(approach, 5))
	if _roll(info["chance"]):
		stage = Stage.CHASE
		_gain("skill")
		return {"success": true, "text_key": "hunt.stalk.success", "turns": turns, "wind_shifted": shifted}
	result = Result.PREY_FLED
	stage = Stage.DONE
	# 選擇繞到下風處時，已經依當下風向重新站位，不算「風向轉了」。
	var fail := _fail("hunt.stalk.fail", info["factors"], shifted and approach != "downwind")
	fail["turns"] = turns
	return fail

func do_chase(tactic: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var info := chance_chase(tactic)
	wolf.stamina -= float(t.get("chase_tactic_stamina", {}).get(tactic, 10))
	if _roll(info["chance"]):
		stage = Stage.FIGHT
		fight_bonus_from_chase = float(t.get("chase_tactic_fight_bonus", {}).get(tactic, 0.0))
		_gain("speed")
		return {"success": true, "text_key": "hunt.chase.success"}
	result = Result.PREY_FLED
	stage = Stage.DONE
	return _fail("hunt.chase.fail", info["factors"], false)

func do_fight(move: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var info := chance_fight(move)
	stage = Stage.DONE
	if _roll(info["chance"]):
		result = Result.SUCCESS
		_gain("strength")
		_gain("skill")
		# 進食回復固定為獵物的 hunger_value；分段進食在 1.5 第 6 步處理。
		var hunger_gain: float = prey_hunger_value
		wolf.hunger += hunger_gain
		return {"success": true, "text_key": "hunt.fight.success", "hunger_gain": hunger_gain}
	result = Result.PREY_FLED
	var counter_chance: float = (prey_counter_attack / 100.0) * float(t.get("fight_move_counter_mult", {}).get(move, 1.0))
	if RNGService.chance(counter_chance):
		var dmg: float = float(RNGService.randi_range(5, 15))
		wolf.health -= dmg
		if dmg >= 12.0:
			wolf.apply_injury(Wolf.Injury.LIGHT, 2)
		var counter := _fail("hunt.fight.counter", info["factors"], false)
		counter["damage"] = dmg
		return counter
	return _fail("hunt.fight.fail", info["factors"], false)

# 失敗主因：風向剛轉成順風時以「風向轉了」為主因，否則取影響最大的不利因素。
func _fail(text_key: String, factors: Array, wind_shifted: bool) -> Dictionary:
	var reason_key: String = ""
	if wind_shifted and wind_state() == "tailwind":
		reason_key = "reason.wind_turned"
	else:
		var worst := main_negative_factor(factors)
		if not worst.is_empty():
			reason_key = "reason." + str(worst["key"]).trim_prefix("factor.").replace(".", "_")
	return {"success": false, "text_key": text_key, "reason_key": reason_key, "wind_shifted": wind_shifted}

func give_up() -> void:
	result = Result.PLAYER_GAVE_UP
	stage = Stage.DONE
