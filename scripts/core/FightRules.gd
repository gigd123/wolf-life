class_name FightRules
extends RefCounted

# 戰鬥規則集中在這裡（SPEC 1.6「戰鬥模式」：狩獵的搏鬥、灰熊、守住獵物、驅趕狐狸都用同一套）。
# - 共用：狼受傷（部位 → 傷勢影響哪項能力）、瀕危與戰鬥中的死亡（hurt_wolf／in_danger）。
# - 狩獵的搏鬥（獵物）：chance()／counter_chance()／resolve_round()，跨回合狀態在 HuntSystem.fight_state。
# - 與競爭者的戰鬥（灰熊、狐狸，之後的陌生灰狼）：attack_chance()／opponent_hit_chance()／retreat_chance()／
#   threaten_chance()，流程與狀態在 Combat.gd。
#
# 狩獵搏鬥的 state：
# state：一場搏鬥跨回合保留的狀態
#   wounds：獵物累積的傷（咬後腿每次 +1，到 wounds_to_kill 即制伏）
#   next_bonus：閃避等待破綻後，下一招的加成
#   counter_reduction：閃避後，下一次被反擊的機率降低比例
#   chase_bonus：追擊階段帶進搏鬥的有利位置
#   penalty / counter_mult_extra：直接攻擊站定的雄鹿時，成功率降低、反擊加重

static func _cfg() -> Dictionary:
	return GameData.balance.get("hunt", {}).get("fight", {})

static func combat_cfg() -> Dictionary:
	return GameData.balance.get("combat", {})

# --- 共用：受傷、瀕危、死亡 ---

# 目前血量低於上限的 danger_ratio 就是「瀕危」。
static func in_danger(wolf: Wolf) -> bool:
	return wolf.health <= wolf.health_max * float(combat_cfg().get("danger_ratio", 0.25))

# 狼受到一次傷害。parts：部位比例（leg／shoulder／face），決定重傷影響哪項能力。
# lethal = false 時這一擊不會致死（血量最少留 1）：SPEC「未進入瀕危前的一次攻擊不會直接致死」，
# 只有瀕危後仍選擇繼續戰鬥，才傳 lethal = true。回傳 {"damage", "part", "severity"}。
static func hurt_wolf(wolf: Wolf, dmg: float, parts: Dictionary, source: String, lethal: bool) -> Dictionary:
	var c: Dictionary = combat_cfg().get("injury", {})
	if not lethal:
		dmg = min(dmg, max(0.0, wolf.health - 1.0))
	wolf.health -= dmg
	var part: String = RNGService.weighted_pick(parts) if not parts.is_empty() else ""
	var severity: int = Wolf.Injury.NONE
	if dmg >= float(c.get("heavy_damage", 22)):
		severity = Wolf.Injury.HEAVY
		var stat: String = str(combat_cfg().get("part_stat", {}).get(part, "strength"))
		wolf.apply_injury(Wolf.Injury.HEAVY, RNGService.randi_range(int(c.get("heavy_days_min", 3)), int(c.get("heavy_days_max", 5))),
			stat, part, source)
	elif dmg >= float(c.get("light_damage", 8)):
		severity = Wolf.Injury.LIGHT
		wolf.apply_injury(Wolf.Injury.LIGHT, int(c.get("light_days", 2)), "", "", source)
	wolf.clamp_stats()
	return {"damage": dmg, "part": part, "severity": severity}

# 戰鬥或狩獵結束時還在瀕危：算重傷（部位依對手的 parts），已經是重傷就不再加。回傳是否新加了重傷。
static func danger_to_heavy(wolf: Wolf, parts: Dictionary, source: String) -> bool:
	var c: Dictionary = combat_cfg().get("injury", {})
	if not bool(c.get("danger_is_heavy", false)) or not wolf.alive or not in_danger(wolf) or wolf.injury == Wolf.Injury.HEAVY:
		return false
	var part: String = RNGService.weighted_pick(parts) if not parts.is_empty() else "shoulder"
	var stat: String = str(combat_cfg().get("part_stat", {}).get(part, "strength"))
	wolf.apply_injury(Wolf.Injury.HEAVY, RNGService.randi_range(int(c.get("heavy_days_min", 3)), int(c.get("heavy_days_max", 5))),
		stat, part, source)
	return true

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
	# 1.7 第 3 步：成功率看「狼的力量值 − 獵物的力量值」；沒有設定力量值的獵物沿用舊式（40 + 反擊）
	var prey_power: float = float(state.get("prey_power", -1.0))
	var has_power: bool = prey_power >= 0.0
	if not has_power:
		prey_power = 40.0 + prey_counter
	var diff: float = (power(wolf, move) - prey_power) / float(cfg.get("power_divisor", 130))
	# 標籤把體型差一起算進去（獵物力量值已經包含體型；舊式要再扣 difficulty），免得對駝鹿也顯示「力量佔優」
	factors.append(_power_factor(diff - (0.0 if has_power else float(state.get("difficulty", 0.0)))))
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
	# 體型巨大的獵物（駝鹿）：搏鬥本身就很難
	var difficulty: float = float(state.get("difficulty", 0.0))
	if difficulty > 0.0:
		if has_power:
			factors.append({"key": "factor.huge_prey", "good": false, "weight": 0.0, "info": true})
		else:
			factors.append({"key": "factor.huge_prey", "good": false, "weight": difficulty})
			penalty += difficulty
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
	state["lethal"] = in_danger(wolf)
	# 閃避的加成只用一次
	state["next_bonus"] = 0.0
	state["counter_reduction"] = 0.0
	if RNGService.chance(float(info["chance"])):
		if m.get("kill", false):
			return {"outcome": "kill", "success": true, "factors": info["factors"]}
		if m.has("wound"):
			state["wounds"] = int(state.get("wounds", 0)) + int(m["wound"])
			if int(state["wounds"]) >= int(state.get("wounds_to_kill", cfg.get("wounds_to_kill", 2))):
				return {"outcome": "kill", "success": true, "factors": info["factors"]}
		state["next_bonus"] = float(m.get("next_bonus", 0.0))
		state["counter_reduction"] = float(m.get("counter_reduction", 0.0))
		return {"outcome": "continue", "success": true, "factors": info["factors"]}
	var result := {"outcome": "continue", "success": false, "damage": 0.0, "factors": info["factors"]}
	if RNGService.chance(counter):
		var dmg: float = float(RNGService.randi_range(int(cfg.get("counter_damage_min", 5)), int(cfg.get("counter_damage_max", 15)))) \
			* float(state.get("counter_damage_mult", 1.0))
		# 瀕危時仍選擇繼續搏鬥，這一擊才可能致死
		var hit := hurt_wolf(wolf, dmg, state.get("parts", cfg.get("parts", {})), str(state.get("source", "")), bool(state.get("lethal", false)))
		result["damage"] = hit["damage"]
	if RNGService.chance(float(cfg.get("escape_chance_on_fail", 0.3))):
		result["outcome"] = "escape"
	return result

# --- 與競爭者的戰鬥（Combat.gd 使用） ---

static func opponent_profile(animal_id: String, life_stage: String) -> Dictionary:
	var table: Dictionary = combat_cfg().get("opponents", {}).get(animal_id, {})
	return table.get(life_stage, table.get("adult", {}))

static func move_cfg(move: String) -> Dictionary:
	return combat_cfg().get("moves", {}).get(move, {})

static func wolf_power(wolf: Wolf, strength_weight: float = 1.0) -> float:
	return wolf.effective_strength() * strength_weight + wolf.effective_skill() * (2.0 - strength_weight)

# 狼的防守（躲開對手攻擊的能力）：技巧＋速度。
static func wolf_defense(wolf: Wolf) -> float:
	return wolf.effective_skill() + wolf.effective_speed()

# 力量的比較只是顯示用的標籤（成功率照公式）：明顯佔優才寫「力量佔優」，中間是「勢均力敵」（balance.json 的 power_label）。
static func _power_factor(diff: float) -> Dictionary:
	var label: Dictionary = GameData.balance.get("power_label", {})
	if diff >= float(label.get("stronger", 0.15)):
		return {"key": "factor.stronger", "good": true, "weight": diff}
	if diff <= float(label.get("weaker", -0.05)):
		return {"key": "factor.weaker", "good": false, "weight": -diff}
	return {"key": "factor.even", "good": diff >= 0.0, "weight": 0.0, "info": true}

# 攻擊命中率：state 帶 next_bonus（閃避後的破綻）、initiative（先手）、tendency_bonus（強攻型）。
static func attack_chance(wolf: Wolf, opp_power: float, move: String, state: Dictionary) -> Dictionary:
	var a: Dictionary = combat_cfg().get("attack", {})
	var m := move_cfg(move)
	var diff: float = (wolf_power(wolf, float(m.get("strength_weight", 1.0))) - opp_power) / float(a.get("divisor", 200))
	var factors: Array = [_power_factor(diff)]
	var value: float = float(a.get("base", 0.55)) + diff + float(m.get("bonus", 0.0))
	for key in ["next_bonus", "initiative", "tendency_bonus", "probe_bonus"]:
		var v: float = float(state.get(key, 0.0))
		if v > 0.0:
			value += v
			factors.append({"key": "factor.combat." + key, "good": true, "weight": v})
	# 體力耗盡：攻擊的命中下降（1.7 QA-55，和追擊的「體力不足」相同）
	var tired: float = float(GameData.balance.get("low_stamina", {}).get("combat_hit_penalty", 0.0))
	if wolf.stamina <= 0.0 and tired > 0.0:
		value -= tired
		factors.append({"key": "factor.tired", "good": false, "weight": tired})
	return {"chance": clamp(value, float(a.get("min", 0.05)), float(a.get("max", 0.95))), "factors": factors}

# 對手這一回合打中狼的機率；dodge 大幅降低，猛撲提高。
static func opponent_hit_chance(wolf: Wolf, opp_power: float, move: String, divisor: float = 0.0) -> float:
	var h: Dictionary = combat_cfg().get("opponent_hit", {})
	# divisor：對手專屬的尺度（灰熊揮掌範圍大，狼的閃躲能力影響較小）；0 = 用共通的
	var value: float = float(h.get("base", 0.45)) + (opp_power - wolf_defense(wolf)) / (divisor if divisor > 0.0 else float(h.get("divisor", 200)))
	value *= float(move_cfg(move).get("hit_mult", 1.0))
	return clamp(value, float(h.get("min", 0.05)), float(h.get("max", 0.9)))

static func wolf_damage(wolf: Wolf, move: String) -> float:
	var d: Dictionary = combat_cfg().get("wolf_damage", {})
	var spread: float = float(d.get("spread", 3))
	return (float(d.get("base", 6)) + wolf.effective_strength() * float(d.get("strength_mult", 0.12)) + RNGService.randf_range(-spread, spread)) \
		* float(move_cfg(move).get("damage_mult", 1.0))

# 撤退：看速度與腿傷；瀕危時對手多半只想把你趕走，成功率提高；謹慎型加成。
static func retreat_chance(wolf: Wolf, cautious: float) -> Dictionary:
	var m := move_cfg("retreat")
	var diff: float = (wolf.effective_speed() - 40.0) / float(m.get("speed_divisor", 150))
	var factors: Array = [{"key": "factor.combat.fast" if diff >= 0.0 else "factor.combat.slow", "good": diff >= 0.0, "weight": absf(diff)}]
	var value: float = float(m.get("base", 0.55)) + diff
	if in_danger(wolf):
		value += float(m.get("danger_bonus", 0.25))
		factors.append({"key": "factor.combat.they_let_go", "good": true, "weight": float(m.get("danger_bonus", 0.25))})
	if wolf.injury == Wolf.Injury.HEAVY and wolf.injury_stat == "speed":
		value -= float(m.get("leg_injury_penalty", 0.15))
		factors.append({"key": "factor.combat.leg_injury", "good": false, "weight": float(m.get("leg_injury_penalty", 0.15))})
	if cautious > 0.0:
		value += cautious
		factors.append({"key": "factor.tendency.cautious", "good": true, "weight": cautious})
	return {"chance": HuntSystem.clamp_chance(value), "factors": factors}

# 威嚇：力量差、對手抗威嚇 × 這場的利害（搶獵物、護幼時更難嚇走）。
static func threaten_chance(wolf: Wolf, opp: Dictionary, stake_mult: float, outclass_bonus: float = 0.0) -> Dictionary:
	var t: Dictionary = combat_cfg().get("standoff", {}).get("threaten", {})
	var diff: float = (wolf_power(wolf) - float(opp.get("power", 100))) / float(t.get("divisor", 200))
	var resist: float = float(opp.get("threat_resist", 0.3)) * stake_mult
	var factors: Array = [_power_factor(diff)]
	if resist > 0.0:
		factors.append({"key": "factor.combat.determined", "good": false, "weight": resist})
	# 實力差距大時，牠看得出打不過你（Combat.morale_bonus）
	if outclass_bonus > 0.0:
		factors.push_front({"key": "factor.combat.outclassed", "good": true, "weight": outclass_bonus})
	return {"chance": HuntSystem.clamp_chance(float(t.get("base", 0.3)) + diff - resist + outclass_bonus), "factors": factors}
