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
	var actions: Array[String] = ["find_tracks", "find_sleep_spot", "short_rest", "rest_until"]
	var region: Dictionary = EncounterSystem.region_data(current_region)
	if not region.get("gather_weights", {}).is_empty():
		actions.append("gather")
	if current_region == den_region or found_sleep_spot_here:
		actions.append("sleep")
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
	var terrain_cost: float = float(EncounterSystem.region_data(target_region).get("terrain_stamina_modifier", 0))
	wolf.stamina -= terrain_cost
	wolf.clamp_stats()
	_check_death()
	if wolf.alive:
		var encounter := EncounterSystem.roll_competitor(current_region, GameTime.current_season())
		if encounter.get("encountered", false):
			encounter_triggered.emit(encounter)
	state_changed.emit()

func action_find_tracks() -> Dictionary:
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("find_tracks", 1)))
	var result := EncounterSystem.find_tracks(current_region, GameTime.current_season(),
		GameTime.current_period(), region_depletion.get(current_region, {}), wind_dir, wolf.effective_perception())
	if result.get("found", false):
		grant_experience(["perception"], float(GameData.balance.get("growth", {}).get("find_tracks_perception_mult", 0.5)))
	state_changed.emit()
	return result

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
	var found := EncounterSystem.find_sleep_spot(current_region)
	if found:
		found_sleep_spot_here = true
	state_changed.emit()
	return found

func action_short_rest() -> void:
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("short_rest", 2)))
	_rest_stamina(float(GameData.balance.get("short_rest_stamina", 15)))
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

func start_hunt(animal_id: String, life_stage: String, prey_dir: int = -1) -> HuntSystem:
	var animal_data: Dictionary = GameData.animals.get(animal_id, {})
	var size: String = animal_data.get("size", "medium")
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	var cost: int = int(costs.get("hunt_small", 2)) if size == "small" else int(costs.get("hunt_medium", 3))
	GameTime.advance_turns(cost)
	# 深夜對狼有利：獵物警覺降低。
	var detection_mod: float = 0.0
	if GameTime.current_period() == "night":
		detection_mod = float(GameData.balance.get("night_prey_detection_mod", -10))
	if prey_dir < 0:
		prey_dir = RNGService.randi_range(0, 3)
	return HuntSystem.new(wolf, animal_id, life_stage, detection_mod, wind_dir, prey_dir)

# 狩獵中花費額外回合（例如繞到下風處）。
func spend_hunt_turns(turns: int) -> void:
	if turns <= 0:
		return
	GameTime.advance_turns(turns)
	_check_death()

# 狩獵結束（成功或失敗）：同步風向、結算各階段累積的經驗。
func finish_hunt(hunt: HuntSystem) -> void:
	wind_dir = hunt.wind_dir
	grant_experience(hunt.experience)
	if hunt.result == HuntSystem.Result.SUCCESS:
		resolve_hunt_success(hunt.animal_id, hunt.life_stage)
	else:
		wolf.clamp_stats()
		_check_death()
		state_changed.emit()

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
	var t: Dictionary = data.get("time", {})
	GameTime.time_mode = t.get("time_mode", "normal")
	GameTime.season_index = int(t.get("season_index", 3))
	GameTime.day = int(t.get("day", 1))
	GameTime.period_index = int(t.get("period_index", 0))
	GameTime.turn_in_period = int(t.get("turn_in_period", 0))
	_connect_time_signals()
	state_changed.emit()
