class_name Combat
extends RefCounted

# 一場與競爭者的戰鬥（SPEC 1.6「戰鬥模式」）：對峙 → 交鋒（每回合）→ 結束。
# 只放流程與狀態；勝率、傷害、受傷與死亡的規則都在 FightRules.gd。畫面層只呼叫 options()／choose()。
#
# context：為什麼打起來。"carcass"（守住獵物）、"encounter"（遭遇）；mother：護幼的母熊。
# outcome（結束時）："drove_off" 趕走對手、"retreated" 撤退、"yield" 退讓、"abandon" 放棄獵物、
# "grab" 叼走一塊再退、"ignore" 不理（狐狸）、"died" 戰死；對具名 NPC 狼（陌生灰狼）另有
# "submit" 你示弱、"killed" 追擊殺死了牠。牠示弱（opp_submitted）後，你選「放牠走」（drove_off）或「追擊」。

enum Phase { STANDOFF, EXCHANGE, DONE }

const PHASE_NAMES := {Phase.STANDOFF: "standoff", Phase.EXCHANGE: "exchange", Phase.DONE: "done"}

var wolf: Wolf
var animal_id: String
var life_stage: String
var context: String
var mother: bool = false
var opp: Dictionary = {}
var opp_hp: float = 0.0
var opp_hp_max: float = 1.0
# 對手的耐力（只有設定 stamina 的對手才有，例如灰熊）：每次出手、被咬傷都會消耗，耗光就離開
var opp_stamina: float = 0.0
var opp_stamina_max: float = 0.0
var stake_mult: float = 1.0
var phase: int = Phase.STANDOFF
var outcome: String = ""
var rounds: int = 0
var probed: bool = false
var probe_reading: String = "" # 試探後看出的態度："resolute"／"wavering"
var damage_taken: float = 0.0
var start_health: float = 0.0
var start_heavy_count: int = 0 # 開打時的重傷次數：這一戰有沒有受重傷（打贏黑狼的成長用）
# 跨回合的加成：next_bonus（閃避後的破綻）、initiative（先手）、tendency_bonus（強攻型）、probe_bonus（試探）
var state: Dictionary = {}
var tendency: Dictionary = {}
var decisions: Array[String] = []
var practice: Array = []
var fail_streak: int = 0
# 對峙時可以選的退讓方式（依情境）：遭遇 yield、守住灰熊搶食 grab／abandon、狐狸 ignore
var yields: Array = []
var can_submit: bool = false
var terrain: String = "" # 在哪裡打（畫面背景）
var npc: NpcWolf = null # 對手是具名 NPC 狼時（陌生灰狼）
var opp_submitted: bool = false # 對手示弱了：之後可以放牠走或追擊
var desperate: bool = false # 追擊示弱的對手：牠臨死前的反擊特別危險
# 對手有同伴（苔原狼一對）：每回合 partner_chance 的機率另一隻也插進來咬一口（傷害 × partner_damage_mult）
var partner_chance: float = 0.0
var partner_damage_mult: float = 0.6
# 你這邊有同伴（幫苔原狼圍攻狼獾）：每回合 ally_chance 的機率同伴咬中對手（ally_damage 範圍）
var ally_chance: float = 0.0
var ally_damage: Array = [6, 10]

# 對手是具名 NPC 狼：能力、目前血量都來自牠；雙方都可以示弱。
func set_npc(p_npc: NpcWolf) -> void:
	npc = p_npc
	opp = npc.combat_profile()
	opp_hp_max = float(opp.get("hp", 100))
	opp_hp = clamp(npc.health, 1.0, opp_hp_max)
	can_submit = bool(opp.get("can_submit", true)) # 狼獾不示弱，你向牠示弱也沒有意義

func _init(p_wolf: Wolf, p_animal: String, p_stage: String, p_context: String, p_mother: bool = false) -> void:
	wolf = p_wolf
	animal_id = p_animal
	life_stage = p_stage
	context = p_context
	mother = p_mother
	opp = FightRules.opponent_profile(animal_id, life_stage)
	opp_hp_max = float(opp.get("hp", 50))
	opp_hp = opp_hp_max
	opp_stamina_max = float(opp.get("stamina", 0.0))
	opp_stamina = opp_stamina_max
	var stakes: Dictionary = FightRules.combat_cfg().get("stake_mult", {})
	stake_mult = float(stakes.get("mother" if mother else context, 1.0))
	start_health = wolf.health
	start_heavy_count = wolf.heavy_injury_count

func stage_name() -> String:
	return PHASE_NAMES[phase]

func _tendency_effect(type: String) -> float:
	return float(tendency.get("effect", 0.0)) if tendency.get("type", "") == type else 0.0

func opp_power() -> float:
	return float(opp.get("power", 100))

# 對手放棄的門檻：耐力低於 give_up_ratio ÷ 利害倍率（搶獵物、護幼時更晚放棄）。
func opp_give_up_ratio() -> float:
	return float(opp.get("give_up_ratio", 0.4)) / max(0.1, stake_mult)

# 耐力放棄的門檻（同樣 ÷ 利害倍率）；沒有耐力的對手永遠不會因為累而離開。
func opp_tired() -> bool:
	return opp_stamina_max > 0.0 and opp_stamina / opp_stamina_max < float(opp.get("stamina_give_up", 0.2)) / max(0.1, stake_mult)

func _drain_opp(amount: float) -> void:
	if opp_stamina_max > 0.0:
		opp_stamina = max(0.0, opp_stamina - amount)

# 對手的狀態描述鍵。
func opp_condition_key() -> String:
	# 有耐力的對手（灰熊）：血量幾乎不會掉，狀態看耐力，玩家才看得出騷擾有沒有用
	if opp_stamina_max > 0.0:
		var s: float = opp_stamina / opp_stamina_max
		if s > 0.65:
			return "combat.opp.stamina.fresh"
		if s > float(opp.get("stamina_give_up", 0.2)) / max(0.1, stake_mult) + 0.2:
			return "combat.opp.stamina.tiring"
		return "combat.opp.stamina.spent"
	var ratio: float = opp_hp / opp_hp_max
	if ratio > 0.7:
		return "combat.opp.strong"
	if ratio > opp_give_up_ratio() + 0.15:
		return "combat.opp.hurt"
	return "combat.opp.wavering"

# --- 選項（格式同 HuntSystem.options()：id、label_key、chance、factors、stamina、trains、injury_risk） ---

func options() -> Array:
	var list: Array = []
	match phase:
		Phase.STANDOFF:
			list.append(_threaten_option())
			if not probed:
				list.append(_probe_option())
			list.append(_attack_option("bite", true))
			for y in yields:
				list.append({"id": str(y), "label_key": "combat.option." + str(y), "stamina": 0.0})
		Phase.EXCHANGE:
			if opp_submitted and not desperate:
				list.append({"id": "let_go", "label_key": "combat.option.let_go", "stamina": 0.0})
				var pursue := _attack_option("bite", false)
				pursue["id"] = "pursue"
				pursue["label_key"] = "combat.option.pursue"
				pursue["injury_risk"] = min(0.95, float(pursue["injury_risk"]) + float(opp.get("desperate_hit", 0.2)))
				list.append(pursue)
				return list
			list.append(_attack_option("bite", false))
			list.append(_attack_option("lunge", false))
			list.append(_dodge_option())
			if opp_stamina_max > 0.0:
				list.append(_harass_option())
			list.append(_retreat_option())
			if context == "carcass" and yields.has("share"):
				list.append({"id": "share", "label_key": "combat.option.share", "stamina": 0.0})
			if context == "carcass" and yields.has("abandon"):
				list.append({"id": "abandon", "label_key": "combat.option.abandon", "stamina": 0.0})
			if can_submit and not desperate:
				list.append({"id": "submit", "label_key": "combat.option.submit", "stamina": 0.0})
	return list

func _move_trains(opt: Dictionary, move: String) -> Dictionary:
	var m := FightRules.move_cfg(move)
	if m.has("trains"):
		opt["trains"] = m["trains"]
		opt["train_mult"] = float(m.get("train_mult", 1.0))
	opt["stamina"] = float(m.get("stamina", 0.0))
	return opt

func _attack_state(initiative: bool) -> Dictionary:
	var s := state.duplicate()
	s["tendency_bonus"] = _tendency_effect("assault")
	if initiative:
		s["initiative"] = float(FightRules.combat_cfg().get("attack", {}).get("initiative", 0.1))
	return s

func _attack_option(move: String, initiative: bool) -> Dictionary:
	var info := FightRules.attack_chance(wolf, opp_power(), move, _attack_state(initiative))
	var label: String = "combat.option.attack" if initiative else "combat.option." + move
	var risk: float = FightRules.opponent_hit_chance(wolf, opp_power(), move, float(opp.get("hit_divisor", 0.0)))
	var factors: Array = info["factors"]
	if partner_chance > 0.0:
		# 另一隻也可能插進來：被打中的機率 = 1 − 兩下都沒中
		risk = 1.0 - (1.0 - risk) * (1.0 - partner_chance * risk)
		factors = factors.duplicate()
		factors.append({"key": "factor.combat.partner", "good": false, "weight": 0.0, "info": true})
	if ally_chance > 0.0:
		factors = factors.duplicate()
		factors.append({"key": "factor.combat.ally", "good": true, "weight": 0.0, "info": true})
	var opt := {"id": "attack" if initiative else move, "label_key": label, "chance": info["chance"], "chance_key": "chance_label.hit", "factors": factors,
		"injury_risk": risk}
	return _move_trains(opt, move)

func _dodge_option() -> Dictionary:
	var hit: float = FightRules.opponent_hit_chance(wolf, opp_power(), "dodge", float(opp.get("hit_divisor", 0.0)))
	var opt := {"id": "dodge", "label_key": "combat.option.dodge", "chance": 1.0 - hit, "chance_key": "chance_label.dodge",
		"factors": [{"key": "factor.combat.opening", "good": true, "weight": 0.0, "info": true}], "injury_risk": hit}
	opt["next_bonus"] = {"stage": "attack", "value": float(FightRules.move_cfg("dodge").get("next_bonus", 0.1))}
	return _move_trains(opt, "dodge")

# 騷擾：繞著牠打轉、咬一口就跳開。容易咬中但傷害很低，主要是消耗牠的耐力；牠反擊打中的機率低，但一掌就很重（只對有耐力的對手）。
func _harass_option() -> Dictionary:
	var info := FightRules.attack_chance(wolf, opp_power(), "harass", _attack_state(false))
	var factors: Array = info["factors"].duplicate()
	factors.append({"key": "factor.combat.tiring", "good": true, "weight": 0.0, "info": true})
	var opt := {"id": "harass", "label_key": "combat.option.harass", "chance": info["chance"], "chance_key": "chance_label.hit", "factors": factors,
		"injury_risk": FightRules.opponent_hit_chance(wolf, opp_power(), "harass", float(opp.get("hit_divisor", 0.0)))}
	return _move_trains(opt, "harass")

func _retreat_option() -> Dictionary:
	var info := FightRules.retreat_chance(wolf, _tendency_effect("cautious"))
	var opt := {"id": "retreat", "label_key": "combat.option.retreat", "chance": info["chance"], "chance_key": "chance_label.escape", "factors": info["factors"],
		"injury_risk": (1.0 - float(info["chance"])) * FightRules.opponent_hit_chance(wolf, opp_power(), "retreat", float(opp.get("hit_divisor", 0.0)))}
	return _move_trains(opt, "retreat")

func _threaten_option() -> Dictionary:
	var info := FightRules.threaten_chance(wolf, opp, stake_mult)
	var t: Dictionary = FightRules.combat_cfg().get("standoff", {}).get("threaten", {})
	return {"id": "threaten", "label_key": "combat.option.threaten", "chance": info["chance"], "chance_key": "chance_label.drive_off", "factors": info["factors"],
		"stamina": float(t.get("stamina", 3)), "injury_risk": (1.0 - float(info["chance"])) * FightRules.opponent_hit_chance(wolf, opp_power(), "bite", float(opp.get("hit_divisor", 0.0)))}

func _probe_option() -> Dictionary:
	var p: Dictionary = FightRules.combat_cfg().get("standoff", {}).get("probe", {})
	var bonus: float = float(p.get("bonus", 0.08)) + _tendency_effect("cautious")
	var factors: Array = []
	if _tendency_effect("cautious") > 0.0:
		factors.append({"key": "factor.tendency.cautious", "good": true, "weight": _tendency_effect("cautious")})
	return {"id": "probe", "label_key": "combat.option.probe", "stamina": float(p.get("stamina", 4)), "factors": factors,
		"next_bonus": {"stage": "attack", "value": bonus}, "trains": ["perception"], "train_mult": 1.0,
		"injury_risk": float(p.get("swipe_chance", 0.15))}

# --- 執行 ---
# 回傳 {"notes": [翻譯鍵], "wolf_damage", "opp_damage", "wolf_pose", "opp_action"}

func choose(id: String) -> Dictionary:
	var opt: Dictionary = {}
	for o in options():
		if o["id"] == id:
			opt = o
			break
	if opt.is_empty():
		return {"notes": []}
	decisions.append("combat." + id)
	wolf.stamina -= float(opt.get("stamina", 0.0))
	wolf.clamp_stats()
	# 瀕危後仍選擇繼續戰鬥（攻擊、閃避），這一回合才可能戰死。
	# 不想殺狼的對手（狼獾）：任何一擊都不會致死。
	var lethal: bool = phase == Phase.EXCHANGE and FightRules.in_danger(wolf) and id in ["bite", "lunge", "dodge", "pursue", "harass"] \
		and not bool(opp.get("never_lethal", false))
	var res: Dictionary = {"notes": [], "wolf_damage": 0.0, "opp_damage": 0.0, "wolf_pose": "threaten", "opp_action": "idle"}
	match id:
		"threaten": _do_threaten(opt, res)
		"probe": _do_probe(opt, res)
		"attack", "bite", "lunge": _do_attack(opt, "bite" if id == "attack" else id, lethal, res)
		"pursue":
			desperate = true
			_do_attack(opt, "bite", lethal, res)
		"let_go":
			res["notes"].append("combat.let_go")
			_end("drove_off")
		"dodge": _do_dodge(opt, lethal, res)
		"harass": _do_harass(opt, lethal, res)
		"retreat": _do_retreat(opt, res)
		"submit":
			# 示弱一定能活下來，代價是挨一下（不會致死）
			_opponent_strikes("bite", false, res, 1.0, float(NpcWolf.cfg(animal_id).get("interaction", {}).get("submit_damage_mult", 0.6)))
			res["notes"].append("combat.submit")
			res["wolf_pose"] = "submit"
			_end("submit")
		_:
			_end(id) # yield／abandon／grab／ignore／share（讓狼獾吃一段）
	if phase != Phase.DONE and wolf.health <= 0.0:
		_end("died")
	rounds += 1
	return res

func _end(result: String) -> void:
	outcome = result
	phase = Phase.DONE

func _practice(opt: Dictionary, success: bool) -> void:
	for stat in opt.get("trains", []):
		var repeat: int = practice.filter(func(p): return p["stat"] == str(stat)).size()
		practice.append({"stat": str(stat), "success": success, "streak": 0 if success else fail_streak, "repeat": repeat,
			"mult": float(opt.get("train_mult", 1.0))})
	if not opt.get("trains", []).is_empty():
		fail_streak = 0 if success else fail_streak + 1

# 對手打狼一下（lethal 見 FightRules.hurt_wolf）。
func _opponent_strikes(move: String, lethal: bool, res: Dictionary, chance_override: float = -1.0, dmg_mult: float = 1.0) -> bool:
	var hit_chance: float = chance_override if chance_override >= 0.0 else FightRules.opponent_hit_chance(wolf, opp_power(), move, float(opp.get("hit_divisor", 0.0)))
	if desperate:
		hit_chance = min(0.95, hit_chance + float(opp.get("desperate_hit", 0.2)))
		dmg_mult *= float(opp.get("desperate_damage", 1.5))
	# 對手每次出手都耗耐力（打不打中都一樣）
	_drain_opp(float(opp.get("swing_cost", 0.0)))
	if not RNGService.chance(hit_chance):
		return false
	var dmg_range: Array = opp.get("damage", [5, 10])
	var dmg: float = float(RNGService.randi_range(int(dmg_range[0]), int(dmg_range[1]))) * dmg_mult
	if mother:
		dmg *= 1.2
	var hit := FightRules.hurt_wolf(wolf, dmg, opp.get("parts", {}), animal_id + "." + context, lethal)
	damage_taken += float(hit["damage"])
	res["wolf_damage"] = float(res.get("wolf_damage", 0.0)) + float(hit["damage"])
	res["notes"].append("combat.opp_hit." + str(hit["part"]) if str(hit["part"]) != "" else "combat.opp_hit")
	if int(hit["severity"]) == Wolf.Injury.HEAVY:
		res["notes"].append("combat.heavy_injury")
	res["wolf_pose"] = "hurt"
	res["opp_action"] = "attack"
	return true

# 對手評估：耐力低於門檻就放棄（趕走對手就是勝利）。
func _ally_turn(res: Dictionary) -> void:
	if ally_chance <= 0.0 or not RNGService.chance(ally_chance):
		return
	var dmg: float = float(RNGService.randi_range(int(ally_damage[0]), int(ally_damage[1])))
	opp_hp = max(0.0, opp_hp - dmg)
	res["opp_damage"] = float(res.get("opp_damage", 0.0)) + dmg
	res["notes"].append("combat.ally_hits")

func _opponent_turn(move: String, lethal: bool, res: Dictionary) -> void:
	_ally_turn(res)
	if desperate and opp_hp <= 0.0:
		res["notes"].append("combat.opp_killed")
		res["opp_action"] = "down"
		_end("killed")
		return
	if not desperate and opp_tired():
		res["notes"].append("combat.opp_tired")
		_end("drove_off")
		return
	if not desperate and opp_hp / opp_hp_max < opp_give_up_ratio():
		# 會示弱的對手（陌生灰狼）：低頭示弱，由你決定放牠走或追擊
		if bool(opp.get("can_submit", false)):
			res["notes"].append("combat.opp_submits")
			res["opp_action"] = "submit"
			opp_submitted = true
			return
		res["notes"].append("combat.opp_gives_up")
		_end("drove_off")
		return
	if not _opponent_strikes(move, lethal, res) and float(res.get("opp_damage", 0.0)) > 0.0:
		res["opp_action"] = "hurt"
	if partner_chance > 0.0 and phase != Phase.DONE and RNGService.chance(partner_chance):
		res["notes"].append("combat.partner_joins")
		_opponent_strikes(move, lethal, res, -1.0, partner_damage_mult)

func _do_threaten(opt: Dictionary, res: Dictionary) -> void:
	res["wolf_pose"] = "threaten"
	if RNGService.chance(float(opt["chance"])):
		res["notes"].append("combat.threaten.success")
		_end("drove_off")
		return
	# 威嚇不成，對手先動手。
	res["notes"].append("combat.threaten.fail")
	phase = Phase.EXCHANGE
	_opponent_strikes("bite", false, res)

func _do_probe(opt: Dictionary, res: Dictionary) -> void:
	probed = true
	state["probe_bonus"] = float(opt.get("next_bonus", {}).get("value", 0.0))
	# 看出對手有多想要這場勝利
	probe_reading = "resolute" if stake_mult >= 1.0 or float(opp.get("threat_resist", 0.3)) >= 0.4 else "wavering"
	res["notes"].append("combat.probe." + probe_reading)
	_practice(opt, true)
	if _opponent_strikes("bite", false, res, float(opt.get("injury_risk", 0.15))):
		res["notes"].append("combat.probe.swipe")

func _do_attack(opt: Dictionary, move: String, lethal: bool, res: Dictionary) -> void:
	phase = Phase.EXCHANGE
	res["wolf_pose"] = "bite"
	var hit: bool = RNGService.chance(float(opt["chance"]))
	state["next_bonus"] = 0.0
	state["probe_bonus"] = 0.0
	if hit:
		var dmg: float = FightRules.wolf_damage(wolf, move)
		opp_hp = max(0.0, opp_hp - dmg)
		res["opp_damage"] = dmg
		_drain_opp(dmg * float(opp.get("hurt_drain", 0.0)))
		res["notes"].append("combat.hit." + move)
	else:
		res["notes"].append("combat.miss")
	_practice(opt, hit)
	_opponent_turn(move, lethal, res)

func _do_dodge(opt: Dictionary, lethal: bool, res: Dictionary) -> void:
	res["wolf_pose"] = "dodge"
	# 苔原狼的助攻先結算（可能直接把對手逼退），但文字排在你閃開之後：先交代你的動作，再交代隊友
	_ally_turn(res)
	var ally_hit: bool = not res["notes"].is_empty() and res["notes"].back() == "combat.ally_hits"
	if ally_hit:
		res["notes"].pop_back()
	if ally_chance > 0.0 and opp_hp / opp_hp_max < opp_give_up_ratio():
		if ally_hit:
			res["notes"].append("combat.ally_hits")
		res["notes"].append("combat.opp_gives_up")
		_end("drove_off")
		return
	var was_hit: bool = _opponent_strikes("dodge", lethal, res)
	if not was_hit:
		state["next_bonus"] = float(FightRules.move_cfg("dodge").get("next_bonus", 0.1))
		res["notes"].append("combat.dodge.success")
	if ally_hit:
		res["notes"].append("combat.ally_hits")
	_practice(opt, not was_hit)

func _do_harass(opt: Dictionary, lethal: bool, res: Dictionary) -> void:
	res["wolf_pose"] = "bite"
	phase = Phase.EXCHANGE
	state["next_bonus"] = 0.0
	state["probe_bonus"] = 0.0
	# 繞著牠打轉本身就讓牠追著消耗耐力；咬中再加一點傷害（被咬傷也會耗耐力）
	_drain_opp(float(FightRules.move_cfg("harass").get("drain", 6.0)))
	var hit: bool = RNGService.chance(float(opt["chance"]))
	if hit:
		var dmg: float = FightRules.wolf_damage(wolf, "harass")
		opp_hp = max(0.0, opp_hp - dmg)
		_drain_opp(dmg * float(opp.get("hurt_drain", 0.0)))
		res["opp_damage"] = dmg
		res["notes"].append("combat.harass.hit")
	else:
		res["notes"].append("combat.harass.miss")
	_practice(opt, hit)
	_opponent_turn("harass", lethal, res)

func _do_retreat(opt: Dictionary, res: Dictionary) -> void:
	if RNGService.chance(float(opt["chance"])):
		res["notes"].append("combat.retreat.success")
		_practice(opt, true)
		_end("retreated")
		return
	res["notes"].append("combat.retreat.fail")
	_practice(opt, false)
	# 撤退失敗挨的這一下不會致死（只有選擇繼續打才有死亡風險）
	_opponent_strikes("retreat", false, res)

func won() -> bool:
	return outcome == "drove_off" or outcome == "killed"
