class_name FightRules
extends RefCounted

# 搏鬥的勝負判定集中在這裡。Phase 1.6 要改用戰鬥規則（SPEC「戰鬥模式」）時，
# 只替換這個檔案的 chance() / resolve_round()，HuntSystem 與畫面層不需要改。
#
# state：一場搏鬥跨回合保留的狀態
#   wounds：獵物累積的傷（咬後腿每次 +1，到 wounds_to_kill 即制伏）
#   next_bonus：閃避等待破綻後，下一招的加成
#   counter_reduction：閃避後，下一次被反擊的機率降低比例
#   chase_bonus：追擊階段帶進搏鬥的有利位置
#   penalty / counter_mult_extra：直接攻擊站定的雄鹿時，成功率降低、反擊加重

static func _cfg() -> Dictionary:
	return GameData.balance.get("hunt", {}).get("fight", {})

static func move_ids() -> Array:
	return _cfg().get("moves", {}).keys()

static func power(wolf: Wolf, move: String) -> float:
	var m: Dictionary = _cfg().get("moves", {}).get(move, {})
	var sw: float = float(m.get("strength_weight", 1.0))
	return wolf.effective_strength() * sw + wolf.effective_skill() * (2.0 - sw)

static func chance(wolf: Wolf, prey_counter: float, move: String, state: Dictionary) -> Dictionary:
	var cfg := _cfg()
	var m: Dictionary = cfg.get("moves", {}).get(move, {})
	var factors: Array = []
	var diff: float = (power(wolf, move) - 40.0 - prey_counter) / float(cfg.get("power_divisor", 130))
	if diff >= 0.0:
		factors.append({"key": "factor.stronger", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.weaker", "good": false, "weight": -diff})
	var chase_bonus: float = float(state.get("chase_bonus", 0.0))
	if chase_bonus > 0.0:
		factors.append({"key": "factor.chase_bonus", "good": true, "weight": chase_bonus})
	var wound_bonus: float = float(m.get("wound_bonus", 0.0)) * int(state.get("wounds", 0))
	if wound_bonus > 0.0:
		factors.append({"key": "factor.prey_wounded", "good": true, "weight": wound_bonus})
	var next_bonus: float = float(state.get("next_bonus", 0.0))
	if next_bonus > 0.0:
		factors.append({"key": "factor.opening", "good": true, "weight": next_bonus})
	# 強攻型：搏鬥逐步更有利（規格「搏鬥傷害提高」，這裡的搏鬥沒有傷害值，換算成成功率）。
	var tendency_bonus: float = float(state.get("tendency_bonus", 0.0))
	if tendency_bonus > 0.0:
		factors.append({"key": "factor.tendency.assault", "good": true, "weight": tendency_bonus})
	var penalty: float = float(state.get("penalty", 0.0))
	if penalty > 0.0:
		factors.append({"key": "factor.standing_danger", "good": false, "weight": penalty})
	var value: float = float(cfg.get("base", 0.5)) + diff + float(m.get("bonus", 0.0)) + chase_bonus + wound_bonus + next_bonus + tendency_bonus - penalty
	return {"chance": HuntSystem.clamp_chance(value), "factors": factors}

static func counter_chance(prey_counter: float, move: String, state: Dictionary) -> float:
	var m: Dictionary = _cfg().get("moves", {}).get(move, {})
	return (prey_counter / 100.0) * float(m.get("counter_mult", 1.0)) * float(state.get("counter_mult_extra", 1.0)) \
		* (1.0 - float(state.get("counter_reduction", 0.0)))

# 執行一回合。回傳 {"outcome": "kill"|"continue"|"escape", "success": bool, "damage": float, "factors": Array}，
# 並直接更新 state 與狼的血量／傷勢。
static func resolve_round(wolf: Wolf, prey_counter: float, move: String, state: Dictionary) -> Dictionary:
	var cfg := _cfg()
	var m: Dictionary = cfg.get("moves", {}).get(move, {})
	var info := chance(wolf, prey_counter, move, state)
	var counter := counter_chance(prey_counter, move, state)
	# 閃避的加成只用一次
	state["next_bonus"] = 0.0
	state["counter_reduction"] = 0.0
	if RNGService.chance(float(info["chance"])):
		if m.get("kill", false):
			return {"outcome": "kill", "success": true, "factors": info["factors"]}
		if m.has("wound"):
			state["wounds"] = int(state.get("wounds", 0)) + int(m["wound"])
			if int(state["wounds"]) >= int(cfg.get("wounds_to_kill", 2)):
				return {"outcome": "kill", "success": true, "factors": info["factors"]}
		state["next_bonus"] = float(m.get("next_bonus", 0.0))
		state["counter_reduction"] = float(m.get("counter_reduction", 0.0))
		return {"outcome": "continue", "success": true, "factors": info["factors"]}
	var result := {"outcome": "continue", "success": false, "damage": 0.0, "factors": info["factors"]}
	if RNGService.chance(counter):
		var dmg: float = float(RNGService.randi_range(int(cfg.get("counter_damage_min", 5)), int(cfg.get("counter_damage_max", 15))))
		wolf.health -= dmg
		if dmg >= float(cfg.get("counter_injury_damage", 12)):
			wolf.apply_injury(Wolf.Injury.LIGHT, 2)
		result["damage"] = dmg
	if RNGService.chance(float(cfg.get("escape_chance_on_fail", 0.3))):
		result["outcome"] = "escape"
	return result
