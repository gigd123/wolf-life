extends Node

# Orchestrates a single life: owns the Wolf, the current/den region, and the
# life-review log, and is the only thing UI code is allowed to mutate game
# state through. Autosaves on new day and after sleeping, per DESIGN.md.

signal state_changed
signal log_message(text: String)
signal wolf_died(cause: String)
signal encounter_triggered(data: Dictionary)
signal growth_applied

var wolf: Wolf
var den_region: String = ""
var current_region: String = ""
var found_sleep_spot_here: bool = false
var rng_seed: int = 0
# 區域資源消耗：{region_id: {animal_id: 出現率倍率}}，沒有紀錄就是 1。
var region_depletion: Dictionary = {}
# 全域風向（0～3，風從哪個方位吹來）。不做羅盤，遭遇時換算成逆風／側風／順風。
var wind_dir: int = 0
# 區域知識：{region_id: {"visited": bool, "features": [已發現的次要特徵]}}。
# 開局只認得巢穴所在區域的樣貌；第一次進入其他區域時揭露主要地形。
var region_knowledge: Dictionary = {}
# 目前探索到、還沒處理的發現（見 ExploreSystem）。
var current_discovery: Dictionary = {}
# 分段進食：目前正在吃的獵物 {animal_id, life_stage, segments_left, segment_value, turns_stayed, terrain}。
var current_feeding: Dictionary = {}
# 吃不完留下的殘骸：[{region_id, terrain, animal_id, life_stage, segments_left, segment_value, day}]，最多留 2 天。
var carcasses: Array = []

var life_log: Dictionary = {}

func new_game(start_den: String) -> void:
	RNGService.randomize_seed()
	rng_seed = RNGService.get_seed()
	wolf = Wolf.new()
	den_region = start_den
	current_region = start_den
	found_sleep_spot_here = false
	region_depletion = {}
	wind_dir = RNGService.randi_range(0, 3)
	region_knowledge = {start_den: {"visited": true, "features": []}}
	current_discovery = {}
	current_feeding = {}
	carcasses = []
	life_log = {
		"regions_visited": [start_den],
		"prey_count": {},
		"biggest_prey": "",
		"biggest_prey_stage": "",
		"days_lived": 1,
		"death_cause": "",
	}
	var start_season: String = GameData.balance.get("start_season", "winter")
	GameTime.setup(start_season, "normal")
	_connect_time_signals()
	SaveSystem.save_game()
	state_changed.emit()

func _connect_time_signals() -> void:
	if not GameTime.period_changed.is_connected(_on_period_changed):
		GameTime.period_changed.connect(_on_period_changed)
	if not GameTime.day_changed.is_connected(_on_day_changed):
		GameTime.day_changed.connect(_on_day_changed)
	if not GameTime.season_changed.is_connected(_on_season_changed):
		GameTime.season_changed.connect(_on_season_changed)

func _on_period_changed(_period_index: int) -> void:
	if wolf == null or not wolf.alive:
		return
	var balance: Dictionary = GameData.balance
	wolf.hunger -= float(balance.get("hunger_decay_per_period", 4))
	wolf.clamp_stats()
	_decay_carcasses()
	# 平常每個時段 15% 機率轉變；暴雨時每回合都可能改變（暴雨尚未實作）。
	if RNGService.chance(float(balance.get("wind_change_chance_per_period", 0.15))):
		wind_dir = posmod(wind_dir + (1 if RNGService.chance(0.5) else -1), 4)
	_check_death()
	found_sleep_spot_here = false

func _on_day_changed(_day: int) -> void:
	life_log["days_lived"] = int(life_log.get("days_lived", 0)) + 1
	_process_daily_recovery()
	_apply_daily_hunger_penalty()
	_recover_region_depletion()
	_maybe_elder_death_check()
	SaveSystem.save_game()

func _on_season_changed(_season_index: int) -> void:
	if wolf != null:
		wolf.age_years += 0.25
		_apply_elder_decay()
	log_message.emit(tr("log.season_changed"))

func _apply_elder_decay() -> void:
	if wolf.life_stage() != Wolf.LifeStage.ELDER:
		return
	var decay: Dictionary = GameData.balance.get("growth", {}).get("elder_decay_per_season", {})
	wolf.speed -= float(decay.get("speed", 0.0))
	wolf.strength -= float(decay.get("strength", 0.0))
	wolf.skill -= float(decay.get("skill", 0.0))
	wolf.perception -= float(decay.get("perception", 0.0))
	wolf.clamp_stats()

# 依行為累積經驗：探索與追蹤 → 感知；潛近與搏鬥 → 技巧；追擊 → 速度；搏鬥 → 力量。
# mult 用來調整單次經驗的份量（例如找到蹤跡只算一半）。
func grant_experience(stats: Array, mult: float = 1.0) -> void:
	if wolf == null or stats.is_empty():
		return
	var growth: Dictionary = GameData.balance.get("growth", {})
	var gains: Dictionary = {}
	match wolf.life_stage():
		Wolf.LifeStage.SUBADULT:
			gains = growth.get("subadult_gain", {})
		Wolf.LifeStage.ADULT:
			var peak_age: float = float(growth.get("peak_age", 4.0))
			if wolf.age_years < peak_age:
				gains = growth.get("adult_gain_before_peak", {})
	if gains.is_empty():
		return
	for stat in stats:
		var amount: float = float(gains.get(stat, 0.0)) * mult
		match stat:
			"speed": wolf.speed += amount
			"strength": wolf.strength += amount
			"skill": wolf.skill += amount
			"perception": wolf.perception += amount
	wolf.clamp_stats()
	if mult >= 1.0:
		growth_applied.emit()

func _process_daily_recovery() -> void:
	if wolf == null:
		return
	if wolf.poison_days_remaining > 0:
		wolf.poison_days_remaining -= 1
		wolf.health_value -= float(GameData.balance.get("poison_health_value_loss_per_day", 1))
	if wolf.injury_days_remaining > 0:
		wolf.injury_days_remaining -= 1
		if wolf.injury_days_remaining <= 0:
			wolf.clear_injury()
	wolf.clamp_stats()
	_check_death()

# 三段式飢餓懲罰，每天結算一次（以換日當下的飽食度判定）。段數累進：歸零時也算「低於 10」。
func _apply_daily_hunger_penalty() -> void:
	if wolf == null or not wolf.alive:
		return
	var p: Dictionary = GameData.balance.get("hunger_penalties", {})
	if wolf.hunger < float(p.get("severe_threshold", 10)):
		wolf.health_value -= float(p.get("severe_health_value_loss_per_day", 3))
		log_message.emit(tr("log.starving"))
	elif wolf.hunger < float(p.get("low_threshold", 30)):
		wolf.health_value -= float(p.get("low_health_value_loss_per_day", 1))
		log_message.emit(tr("log.hungry"))
	if wolf.hunger <= 0.0:
		wolf.health -= float(p.get("zero_health_loss_per_day", 10))
	wolf.clamp_stats()
	_check_death()

func _recover_region_depletion() -> void:
	var recovery: float = float(GameData.balance.get("region_depletion", {}).get("recovery_per_day", 0.05))
	for region_id in region_depletion.keys():
		var table: Dictionary = region_depletion[region_id]
		for animal_id in table.keys():
			table[animal_id] = min(1.0, float(table[animal_id]) + recovery)

func _deplete_region(region_id: String, animal_id: String) -> void:
	var cfg: Dictionary = GameData.balance.get("region_depletion", {})
	var table: Dictionary = region_depletion.get(region_id, {})
	var current: float = float(table.get(animal_id, 1.0))
	table[animal_id] = max(float(cfg.get("min_mult", 0.2)), current - float(cfg.get("per_hunt", 0.2)))
	region_depletion[region_id] = table

# 短暫休息與快轉只能把體力回到上限 rest_stamina_cap，只有睡覺能回滿；已經超過上限就不變。
func _rest_stamina(amount: float) -> void:
	var cap: float = float(GameData.balance.get("rest_stamina_cap", 80))
	if wolf.stamina < cap:
		wolf.stamina = min(cap, wolf.stamina + amount)

func _maybe_elder_death_check() -> void:
	if wolf == null or wolf.life_stage() != Wolf.LifeStage.ELDER:
		return
	var balance: Dictionary = GameData.balance
	var base_chance: float = float(balance.get("elder_death_base_chance", 0.01))
	var age_factor: float = float(balance.get("elder_death_age_factor", 0.01))
	var hv_factor: float = float(balance.get("elder_death_health_value_factor", 0.0005))
	var ages: Dictionary = balance.get("life_stage_ages", {})
	var elder_start: float = float(ages.get("adult_end", 6.0))
	var age_over: float = max(0.0, wolf.age_years - elder_start)
	var chance_value: float = base_chance + age_over * age_factor - wolf.health_value * hv_factor
	chance_value = clamp(chance_value, 0.0, 0.5)
	if RNGService.chance(chance_value):
		_die("old_age")

func _check_death() -> void:
	if wolf != null and wolf.alive and wolf.health <= 0.0:
		_die("starvation" if wolf.hunger <= 0.0 else "injury")

func _die(cause: String) -> void:
	if wolf == null or not wolf.alive:
		return
	wolf.alive = false
	wolf.death_cause = cause
	life_log["death_cause"] = cause
	SaveSystem.save_game()
	wolf_died.emit(cause)

# --- Player actions ---

func available_actions() -> Array[String]:
	var actions: Array[String] = ["explore", "find_sleep_spot", "short_rest", "rest_until"]
	var region: Dictionary = EncounterSystem.region_data(current_region)
	if not region.get("gather_weights", {}).is_empty():
		actions.append("gather")
	if current_region == den_region or found_sleep_spot_here:
		actions.append("sleep")
	if carcass_index_here() >= 0:
		actions.append("return_to_carcass")
	return actions

func adjacent_regions() -> Array:
	var region: Dictionary = EncounterSystem.region_data(current_region)
	return region.get("adjacent", [])

func action_move(target_region: String) -> void:
	if not adjacent_regions().has(target_region):
		return
	current_region = target_region
	found_sleep_spot_here = false
	if not life_log["regions_visited"].has(target_region):
		life_log["regions_visited"].append(target_region)
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("move_region", 1)))
	log_message.emit(tr("log.moved").replace("{region}", tr("region." + target_region)))
	if not is_region_visited(target_region):
		var knowledge: Dictionary = region_knowledge.get(target_region, {"features": []})
		knowledge["visited"] = true
		region_knowledge[target_region] = knowledge
		var main: String = str(EncounterSystem.region_data(target_region).get("main_feature", ""))
		log_message.emit(tr("log.region_first_visit").replace("{region}", tr("region." + target_region))
			.replace("{main}", tr("region_main." + main)))
	var terrain_cost: float = float(EncounterSystem.region_data(target_region).get("terrain_stamina_modifier", 0))
	wolf.stamina -= terrain_cost
	wolf.clamp_stats()
	_check_death()
	if wolf.alive:
		var encounter := EncounterSystem.roll_competitor(current_region, GameTime.current_season())
		if encounter.get("encountered", false):
			encounter_triggered.emit(encounter)
	state_changed.emit()

# --- 探索（取代「尋找獵物蹤跡」） ---

func is_region_visited(region_id: String) -> bool:
	return bool(region_knowledge.get(region_id, {}).get("visited", false))

func known_features(region_id: String) -> Array:
	return region_knowledge.get(region_id, {}).get("features", [])

func _feature_known_here(flag: String) -> bool:
	var all_features: Dictionary = GameData.region_features()
	for f in known_features(current_region):
		if all_features.get(f, {}).has(flag):
			return true
	return false

func action_explore() -> Dictionary:
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("explore", 1)))
	if not wolf.alive:
		return {}
	current_discovery = ExploreSystem.generate({
		"region_id": current_region,
		"season": GameTime.current_season(),
		"period": GameTime.current_period(),
		"depletion": region_depletion.get(current_region, {}),
		"wind_dir": wind_dir,
		"known_features": known_features(current_region),
	})
	match current_discovery.get("kind", ""):
		"feature":
			var knowledge: Dictionary = region_knowledge.get(current_region, {"visited": true, "features": []})
			knowledge["features"].append(current_discovery["feature_id"])
			region_knowledge[current_region] = knowledge
		"clue":
			grant_experience(["perception"], float(GameData.discovery.get("explore_perception_mult", 0.15)))
	state_changed.emit()
	return current_discovery

func track_chance() -> Dictionary:
	return ExploreSystem.track_chance(current_discovery, wolf.effective_perception())

# 追蹤目前的線索：成功時回傳 {"success": true, "hunt": HuntSystem}，狩獵直接從潛近開始。
func action_track() -> Dictionary:
	var d: Dictionary = current_discovery
	current_discovery = {}
	if not ExploreSystem.can_track(d):
		return {"success": false}
	var info := ExploreSystem.track_chance(d, wolf.effective_perception())
	GameTime.advance_turns(int(GameData.discovery.get("track", {}).get("turns", 1)))
	if not wolf.alive:
		return {"success": false}
	if not d.get("fresh", false):
		state_changed.emit()
		return {"success": false, "reason_key": "reason.stale"}
	if not RNGService.chance(float(info["chance"])):
		state_changed.emit()
		var worst := HuntSystem.main_negative_factor(info["factors"])
		var reason: String = "" if worst.is_empty() else "reason." + str(worst["key"]).trim_prefix("factor.").replace(".", "_")
		return {"success": false, "reason_key": reason}
	return {"success": true, "hunt": start_hunt(d["source"], d.get("life_stage", "adult"), int(d.get("prey_dir", -1)), true,
		str(d.get("location", "")), bool(d.get("injured", false)))}

# 直接目擊獵物：不用追蹤，直接進入狩獵（從潛近開始）。
func action_hunt_sighted() -> HuntSystem:
	var d: Dictionary = current_discovery
	current_discovery = {}
	return start_hunt(d["source"], d.get("life_stage", "adult"), int(d.get("prey_dir", -1)), false,
		str(d.get("location", "")), bool(d.get("injured", false)))

# 採集探索到的採集物。
func action_gather_discovered() -> String:
	var d: Dictionary = current_discovery
	current_discovery = {}
	if d.get("source_kind", "") != "gather":
		return ""
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("gather", 1)))
	if wolf.alive:
		_apply_gather_effect(d["source"])
	state_changed.emit()
	return d["source"]

func clear_discovery() -> void:
	current_discovery = {}

func action_gather() -> Dictionary:
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("gather", 1)))
	var result := EncounterSystem.gather(current_region, GameTime.current_season())
	if result.get("found", false):
		_apply_gather_effect(result["item_id"])
	state_changed.emit()
	return result

func _apply_gather_effect(item_id: String) -> void:
	var effects: Dictionary = GameData.balance.get("gather_effects", {}).get(item_id, {})
	wolf.hunger += float(effects.get("hunger", 0))
	wolf.stamina += float(effects.get("stamina", 0))
	wolf.health += float(effects.get("health", 0))
	if effects.has("poison_chance") and RNGService.chance(float(effects["poison_chance"])):
		var balance: Dictionary = GameData.balance
		wolf.poison_days_remaining = RNGService.randi_range(
			int(balance.get("poison_duration_min", 2)), int(balance.get("poison_duration_max", 4))
		)
		log_message.emit(tr("log.poisoned"))
	if effects.has("sting_chance") and RNGService.chance(float(effects["sting_chance"])):
		wolf.health -= float(effects.get("sting_health_loss", 5))
		log_message.emit(tr("log.stung"))
	wolf.clamp_stats()
	_check_death()

func action_find_sleep_spot() -> bool:
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("find_sleep_spot", 1)))
	# 已發現好睡處的區域一定找得到。
	var found := _feature_known_here("sleep_spot") or EncounterSystem.find_sleep_spot(current_region)
	if found:
		found_sleep_spot_here = true
	state_changed.emit()
	return found

func action_short_rest() -> void:
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("short_rest", 2)))
	var bonus: float = 0.0
	for f in known_features(current_region):
		bonus += float(GameData.region_features().get(f, {}).get("short_rest_stamina_bonus", 0))
	_rest_stamina(float(GameData.balance.get("short_rest_stamina", 15)) + bonus)
	wolf.clamp_stats()
	state_changed.emit()

# 快轉：一回合一回合休息到指定時段開始，途中照常結算時段與每日變化；狼死亡就停止。
func action_rest_until(target_period: String) -> bool:
	var target_index := GameTime.PERIODS.find(target_period)
	if target_index < 0 or target_index == GameTime.period_index:
		return false
	var stamina_per_turn: float = float(GameData.balance.get("rest_until_stamina_per_turn", 7.5))
	var max_turns := GameTime.PERIODS.size() * GameTime.TURNS_PER_PERIOD
	for i in range(max_turns):
		if not wolf.alive or GameTime.period_index == target_index:
			break
		GameTime.advance_turns(1)
		if wolf.alive:
			_rest_stamina(stamina_per_turn)
			wolf.clamp_stats()
	state_changed.emit()
	return wolf.alive

func action_sleep() -> void:
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("sleep", 3)))
	var balance: Dictionary = GameData.balance
	var is_den: bool = current_region == den_region
	var mult: float = 1.0 if is_den else float(balance.get("wild_sleep_multiplier", 0.6))
	wolf.health += float(balance.get("den_sleep_health", 30)) * mult
	wolf.stamina += float(balance.get("den_sleep_stamina", 60)) * mult
	wolf.clamp_stats()
	found_sleep_spot_here = false
	SaveSystem.save_game()
	state_changed.emit()

# 開始狩獵：依狩獵深度消耗回合（簡易 1、標準 2、完整 3）。
# from_tracking：經由追蹤找到獵物時累積一次感知經驗。terrain：遭遇時的地形，空字串則隨機取區域的地形。
# injured：受傷個體，一律走簡易流程。
func start_hunt(animal_id: String, life_stage: String, prey_dir: int = -1, from_tracking: bool = false,
		terrain: String = "", injured: bool = false) -> HuntSystem:
	var depth: String = "simple" if injured else HuntSystem.depth_of(animal_id, life_stage)
	GameTime.advance_turns(HuntSystem.depth_turns(depth))
	# 深夜對狼有利：獵物警覺降低。
	var detection_mod: float = 0.0
	if GameTime.current_period() == "night":
		detection_mod = float(GameData.balance.get("night_prey_detection_mod", -10))
	if prey_dir < 0:
		prey_dir = RNGService.randi_range(0, 3)
	if terrain == "":
		terrain = _random_terrain(current_region)
	var hunt := HuntSystem.new(wolf, animal_id, life_stage, detection_mod, wind_dir, prey_dir, terrain, injured)
	if from_tracking:
		hunt.experience.append("perception")
	return hunt

func _random_terrain(region_id: String) -> String:
	var terrains: Array = EncounterSystem.region_data(region_id).get("terrains", [])
	if terrains.is_empty():
		return ""
	return terrains[RNGService.randi_range(0, terrains.size() - 1)]

# 狩獵中花費額外回合（例如繞到下風處）。
func spend_hunt_turns(turns: int) -> void:
	if turns <= 0:
		return
	GameTime.advance_turns(turns)
	_check_death()

# 狩獵結束（成功或失敗）：同步風向、結算各階段累積的經驗。
# 獵物逃走時，留下一條往某個地形去的新鮮足跡（current_discovery），可以再追。
func finish_hunt(hunt: HuntSystem) -> void:
	wind_dir = hunt.wind_dir
	grant_experience(hunt.experience)
	_record_hunt(hunt)
	if hunt.result == HuntSystem.Result.SUCCESS:
		if HuntSystem.feeding_segments(hunt.animal_id, hunt.life_stage) > 1:
			start_feeding(hunt.animal_id, hunt.life_stage, hunt.terrain)
		resolve_hunt_success(hunt.animal_id, hunt.life_stage)
	else:
		if hunt.fled and wolf.alive:
			var prey_dir: int = RNGService.randi_range(0, 3)
			current_discovery = {"kind": "clue", "source_kind": "prey", "source": hunt.animal_id,
				"clue": "track", "location": _random_terrain(current_region), "fresh": true, "fresh_known": true,
				"wind": HuntSystem.relative_wind(wind_dir, prey_dir), "prey_dir": prey_dir,
				"life_stage": hunt.life_stage, "injured": hunt.injured, "fled": true}
		wolf.clamp_stats()
		_check_death()
		state_changed.emit()

# 狩獵紀錄（之後的狩獵傾向與一生回顧使用）：次數、成功、追擊中途放棄。
func _record_hunt(hunt: HuntSystem) -> void:
	life_log["hunt_attempts"] = int(life_log.get("hunt_attempts", 0)) + 1
	if hunt.result == HuntSystem.Result.SUCCESS:
		life_log["hunt_successes"] = int(life_log.get("hunt_successes", 0)) + 1
	elif hunt.result == HuntSystem.Result.PLAYER_GAVE_UP and hunt.gave_up_stage == HuntSystem.Stage.CHASE:
		life_log["chase_give_ups"] = int(life_log.get("chase_give_ups", 0)) + 1

# --- 分段進食與搶食（SPEC「狩獵後續事件」） ---

func _feeding_cfg() -> Dictionary:
	return GameData.balance.get("feeding", {})

func start_feeding(animal_id: String, life_stage: String, terrain: String) -> void:
	var segments: int = HuntSystem.feeding_segments(animal_id, life_stage)
	var total: float = float(GameData.animals.get(animal_id, {}).get(life_stage, {}).get("hunger_value", 0))
	current_feeding = {"animal_id": animal_id, "life_stage": life_stage, "segments_left": segments,
		"segment_value": total / max(1, segments), "turns_stayed": 0, "terrain": terrain}

func is_feeding() -> bool:
	return not current_feeding.is_empty()

# 下一段吃完後，灰熊／狐狸來搶食的機率：每多停留 1 回合上升，深夜與密林更高。
func scavenge_chances() -> Dictionary:
	var cfg := _feeding_cfg()
	var bear: float = float(cfg.get("bear_base", 0.1)) + float(cfg.get("bear_per_turn", 0.1)) * int(current_feeding.get("turns_stayed", 0))
	if GameTime.current_period() == "night":
		bear += float(cfg.get("night_bonus", 0.05))
	if current_feeding.get("terrain", "") == "dense_forest":
		bear += float(cfg.get("dense_forest_bonus", 0.05))
	return {"bear": clamp(bear, 0.0, 0.95), "fox": float(cfg.get("fox_chance", 0.12))}

# 吃一段：1 回合、飽食度 + 一段。之後判定搶食事件。回傳 {"gain", "event": "bear"|"fox"|""}。
func feed_once() -> Dictionary:
	if not is_feeding():
		return {}
	var chances := scavenge_chances()
	GameTime.advance_turns(int(_feeding_cfg().get("eat_turns", 1)))
	if not wolf.alive:
		current_feeding = {}
		return {}
	var gain: float = float(current_feeding["segment_value"])
	wolf.hunger += gain
	wolf.clamp_stats()
	current_feeding["segments_left"] = int(current_feeding["segments_left"]) - 1
	current_feeding["turns_stayed"] = int(current_feeding["turns_stayed"]) + 1
	var event: String = ""
	if int(current_feeding["segments_left"]) > 0:
		if RNGService.chance(float(chances["bear"])):
			event = "bear"
		elif RNGService.chance(float(chances["fox"])):
			event = "fox"
	else:
		current_feeding = {}
	state_changed.emit()
	return {"gain": gain, "event": event}

# 離開：吃不完的部分留成殘骸。
func leave_feeding() -> void:
	if is_feeding() and int(current_feeding["segments_left"]) > 0:
		carcasses.append({"region_id": current_region, "terrain": current_feeding["terrain"],
			"animal_id": current_feeding["animal_id"], "life_stage": current_feeding["life_stage"],
			"segments_left": current_feeding["segments_left"], "segment_value": current_feeding["segment_value"],
			"day": int(life_log.get("days_lived", 1))})
	current_feeding = {}
	state_changed.emit()

# 灰熊搶食：guard 守住（打鬥，風險極高）、grab 叼走一部分（多一段後撤退）、abandon 放棄。
# 狐狸偷食：drive 驅趕、ignore 不理（少一段）。
func resolve_scavenger(event: String, choice: String) -> Dictionary:
	var cfg := _feeding_cfg()
	var result := {"outcome": choice}
	if event == "fox":
		if choice == "ignore":
			current_feeding["segments_left"] = int(current_feeding["segments_left"]) - 1
			if int(current_feeding["segments_left"]) <= 0:
				current_feeding = {}
		state_changed.emit()
		return result
	match choice:
		"guard":
			var g: Dictionary = cfg.get("guard", {})
			if RNGService.chance(guard_win_chance()):
				wolf.stamina -= float(g.get("win_stamina", 20))
				grant_experience(["strength", "skill"])
				result["outcome"] = "guard_win"
			else:
				var dmg: float = float(RNGService.randi_range(int(g.get("damage_min", 20)), int(g.get("damage_max", 45))))
				wolf.health -= dmg
				if dmg >= float(g.get("heavy_damage", 25)):
					var b: Dictionary = GameData.balance
					wolf.apply_injury(Wolf.Injury.HEAVY, RNGService.randi_range(int(b.get("heavy_injury_days_min", 3)), int(b.get("heavy_injury_days_max", 5))),
						"speed" if RNGService.chance(0.5) else "strength")
				else:
					wolf.apply_injury(Wolf.Injury.LIGHT, 2)
				result["outcome"] = "guard_lose"
				result["damage"] = dmg
				current_feeding = {}
		"grab":
			wolf.hunger += float(current_feeding.get("segment_value", 0))
			current_feeding = {}
		_:
			current_feeding = {}
	wolf.clamp_stats()
	_check_death()
	state_changed.emit()
	return result

func guard_win_chance() -> float:
	var g: Dictionary = _feeding_cfg().get("guard", {})
	var power: float = float(GameData.animals.get("grizzly_bear", {}).get("adult", {}).get("power", 95))
	return clamp(float(g.get("base", 0.25)) + (wolf.effective_strength() + wolf.effective_skill() - power) / float(g.get("divisor", 250)),
		float(g.get("min", 0.03)), float(g.get("max", 0.4)))

func carcass_index_here() -> int:
	for i in carcasses.size():
		if carcasses[i]["region_id"] == current_region:
			return i
	return -1

# 回到殘骸：1 回合；可能撞見正在吃的狐狸或灰熊。回傳 {"event": ...}，沒有殘骸時回傳空字典。
func action_return_to_carcass() -> Dictionary:
	var idx := carcass_index_here()
	if idx < 0:
		return {}
	var cfg := _feeding_cfg()
	GameTime.advance_turns(int(cfg.get("return_turns", 1)))
	if not wolf.alive:
		return {}
	# 回程途中殘骸也可能被搶走或腐壞
	idx = carcass_index_here()
	if idx < 0:
		state_changed.emit()
		return {"gone": true}
	var c: Dictionary = carcasses[idx]
	carcasses.remove_at(idx)
	current_feeding = {"animal_id": c["animal_id"], "life_stage": c["life_stage"], "segments_left": c["segments_left"],
		"segment_value": c["segment_value"], "turns_stayed": 0, "terrain": c["terrain"]}
	var event: String = ""
	if RNGService.chance(float(cfg.get("return_bear_chance", 0.1))):
		event = "bear"
	elif RNGService.chance(float(cfg.get("return_fox_chance", 0.2))):
		event = "fox"
	state_changed.emit()
	return {"event": event}

# 每個時段：殘骸有 15% 機率被搶走或腐壞，超過 2 天一定消失。
func _decay_carcasses() -> void:
	var cfg := _feeding_cfg()
	var today: int = int(life_log.get("days_lived", 1))
	var kept: Array = []
	for c in carcasses:
		if today - int(c["day"]) > int(cfg.get("carcass_days", 2)):
			continue
		if RNGService.chance(float(cfg.get("carcass_loss_per_period", 0.15))):
			continue
		kept.append(c)
	carcasses = kept

func resolve_hunt_success(animal_id: String, life_stage: String) -> void:
	var prey_count: Dictionary = life_log.get("prey_count", {})
	prey_count[animal_id] = int(prey_count.get(animal_id, 0)) + 1
	life_log["prey_count"] = prey_count
	_deplete_region(current_region, animal_id)
	var current_rank: int = _prey_rank(str(life_log.get("biggest_prey", "")), str(life_log.get("biggest_prey_stage", "adult")))
	var new_rank: int = _prey_rank(animal_id, life_stage)
	if new_rank > current_rank:
		life_log["biggest_prey"] = animal_id
		life_log["biggest_prey_stage"] = life_stage
	wolf.clamp_stats()
	_check_death()
	state_changed.emit()

func _prey_rank(animal_id: String, life_stage: String) -> int:
	if animal_id == "":
		return -1
	var animal_data: Dictionary = GameData.animals.get(animal_id, {})
	var stats: Dictionary = animal_data.get(life_stage, {})
	return int(stats.get("hunger_value", 0))

func resolve_competitor_encounter(choice: String, encounter: Dictionary) -> Dictionary:
	var animal_id: String = encounter.get("animal_id", "grizzly_bear")
	var stage: String = encounter.get("life_stage", "adult")
	var stats: Dictionary = GameData.animals.get(animal_id, {}).get(stage, {})
	var power: float = float(stats.get("power", 60))
	if choice == "fight":
		var win_chance: float = clamp(0.5 + (wolf.effective_strength() + wolf.effective_skill() - power) / 200.0, 0.05, 0.7)
		if RNGService.chance(win_chance):
			wolf.stamina -= 15
			grant_experience(["strength", "skill"])
			wolf.clamp_stats()
			return {"outcome": "win"}
		var dmg: float = float(RNGService.randi_range(15, 35))
		wolf.health -= dmg
		if dmg >= 25.0:
			var b: Dictionary = GameData.balance
			var days := RNGService.randi_range(int(b.get("heavy_injury_days_min", 3)), int(b.get("heavy_injury_days_max", 5)))
			wolf.apply_injury(Wolf.Injury.HEAVY, days, "speed" if RNGService.chance(0.5) else "strength")
		else:
			wolf.apply_injury(Wolf.Injury.LIGHT, 2)
		wolf.clamp_stats()
		_check_death()
		return {"outcome": "lose", "damage": dmg}
	wolf.stamina -= 5
	wolf.clamp_stats()
	return {"outcome": choice}

# --- Debug helpers (see DESIGN.md "測試與除錯") ---

func debug_set_stat(stat_name: String, value: float) -> void:
	if wolf == null:
		return
	match stat_name:
		"health": wolf.health = value
		"stamina": wolf.stamina = value
		"speed": wolf.speed = value
		"strength": wolf.strength = value
		"skill": wolf.skill = value
		"perception": wolf.perception = value
		"hunger": wolf.hunger = value
		"health_value": wolf.health_value = value
		"age_years": wolf.age_years = value
	wolf.clamp_stats()
	state_changed.emit()

func debug_skip_day() -> void:
	GameTime.advance_turns(GameTime.TURNS_PER_PERIOD * GameTime.PERIODS.size())
	state_changed.emit()

func debug_skip_to_next_season() -> void:
	var target_season := GameTime.season_index
	var guard := 0
	while GameTime.season_index == target_season and guard < 40:
		if wolf != null and not wolf.alive:
			break
		GameTime.advance_turns(GameTime.TURNS_PER_PERIOD * GameTime.PERIODS.size())
		guard += 1
	state_changed.emit()

# 跳年齡：以季為單位增加年齡，每季照常套用老年衰退，但不推進遊戲時間。
func debug_add_age(years: float) -> void:
	if wolf == null:
		return
	var steps := int(round(years / 0.25))
	for i in range(steps):
		wolf.age_years += 0.25
		_apply_elder_decay()
	log_message.emit(tr("log.debug.age").replace("{age}", "%.2f" % wolf.age_years))
	state_changed.emit()

func debug_jump_to_stage(stage: int) -> void:
	if wolf == null or wolf.life_stage() >= stage:
		return
	var ages: Dictionary = GameData.balance.get("life_stage_ages", {})
	var target: float = float(ages.get("subadult_end", 2.0)) if stage == Wolf.LifeStage.ADULT else float(ages.get("adult_end", 6.0))
	debug_add_age(ceil((target - wolf.age_years) / 0.25 - 0.0001) * 0.25)

func debug_animal_ids() -> Array:
	return GameData.animals.keys()

# 強制觸發遭遇：獵物回傳與「尋找獵物蹤跡」相同格式的結果，競爭動物直接發出遭遇訊號。
func debug_force_encounter(animal_id: String, life_stage: String) -> Dictionary:
	if not GameData.animals.get(animal_id, {}).has(life_stage):
		life_stage = "adult"
	var role: String = str(GameData.animals.get(animal_id, {}).get("type", ""))
	if role == "competitor":
		encounter_triggered.emit({"encountered": true, "animal_id": animal_id, "life_stage": life_stage})
		return {}
	return {"found": true, "animal_id": animal_id, "life_stage": life_stage}

# --- Persistence ---

func to_dict() -> Dictionary:
	return {
		"wolf": wolf.to_dict() if wolf != null else {},
		"den_region": den_region,
		"current_region": current_region,
		"found_sleep_spot_here": found_sleep_spot_here,
		"rng_seed": rng_seed,
		"region_depletion": region_depletion,
		"wind_dir": wind_dir,
		"region_knowledge": region_knowledge,
		"carcasses": carcasses,
		"life_log": life_log,
		"time": {
			"season_index": GameTime.season_index,
			"day": GameTime.day,
			"period_index": GameTime.period_index,
			"turn_in_period": GameTime.turn_in_period,
			"time_mode": GameTime.time_mode,
		},
	}

func load_from_dict(data: Dictionary) -> void:
	wolf = Wolf.from_dict(data.get("wolf", {}))
	den_region = data.get("den_region", "")
	current_region = data.get("current_region", den_region)
	found_sleep_spot_here = data.get("found_sleep_spot_here", false)
	rng_seed = int(data.get("rng_seed", 0))
	RNGService.set_seed(rng_seed)
	life_log = data.get("life_log", {})
	region_depletion = data.get("region_depletion", {})
	wind_dir = int(data.get("wind_dir", 0))
	region_knowledge = data.get("region_knowledge", {den_region: {"visited": true, "features": []}})
	current_discovery = {}
	current_feeding = {}
	carcasses = data.get("carcasses", [])
	var t: Dictionary = data.get("time", {})
	GameTime.time_mode = t.get("time_mode", "normal")
	GameTime.season_index = int(t.get("season_index", 3))
	GameTime.day = int(t.get("day", 1))
	GameTime.period_index = int(t.get("period_index", 0))
	GameTime.turn_in_period = int(t.get("turn_in_period", 0))
	_connect_time_signals()
	state_changed.emit()
