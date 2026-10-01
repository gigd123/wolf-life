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

var life_log: Dictionary = {}

func new_game(start_den: String) -> void:
	RNGService.randomize_seed()
	rng_seed = RNGService.get_seed()
	wolf = Wolf.new()
	den_region = start_den
	current_region = start_den
	found_sleep_spot_here = false
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
	if wolf.hunger <= 0.0:
		wolf.hunger = 0.0
		wolf.health -= float(balance.get("hunger_zero_health_loss_per_period", 5))
		wolf.health_value -= float(balance.get("hunger_zero_health_value_loss_per_period", 1))
		log_message.emit(tr("log.starving"))
	wolf.clamp_stats()
	_check_death()
	found_sleep_spot_here = false

func _on_day_changed(_day: int) -> void:
	life_log["days_lived"] = int(life_log.get("days_lived", 0)) + 1
	_process_daily_recovery()
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
	wolf.clamp_stats()

func _apply_growth() -> void:
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
	wolf.speed += float(gains.get("speed", 0.0))
	wolf.strength += float(gains.get("strength", 0.0))
	wolf.skill += float(gains.get("skill", 0.0))
	wolf.clamp_stats()
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
			wolf.injury = Wolf.Injury.NONE
	wolf.clamp_stats()
	_check_death()

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
	var result := EncounterSystem.find_tracks(current_region, GameTime.current_season())
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
	wolf.stamina += float(GameData.balance.get("short_rest_stamina", 15))
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
			wolf.stamina += stamina_per_turn
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

func start_hunt(animal_id: String, life_stage: String) -> HuntSystem:
	var animal_data: Dictionary = GameData.animals.get(animal_id, {})
	var size: String = animal_data.get("size", "medium")
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	var cost: int = int(costs.get("hunt_small", 2)) if size == "small" else int(costs.get("hunt_medium", 3))
	GameTime.advance_turns(cost)
	return HuntSystem.new(wolf, animal_id, life_stage)

func resolve_hunt_success(animal_id: String, life_stage: String) -> void:
	var prey_count: Dictionary = life_log.get("prey_count", {})
	prey_count[animal_id] = int(prey_count.get(animal_id, 0)) + 1
	life_log["prey_count"] = prey_count
	var current_rank: int = _prey_rank(str(life_log.get("biggest_prey", "")), str(life_log.get("biggest_prey_stage", "adult")))
	var new_rank: int = _prey_rank(animal_id, life_stage)
	if new_rank > current_rank:
		life_log["biggest_prey"] = animal_id
		life_log["biggest_prey_stage"] = life_stage
	_apply_growth()
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
		var win_chance: float = clamp(0.5 + (wolf.strength + wolf.skill - power) / 200.0, 0.05, 0.7)
		if RNGService.chance(win_chance):
			wolf.stamina -= 15
			_apply_growth()
			wolf.clamp_stats()
			return {"outcome": "win"}
		var dmg: float = float(RNGService.randi_range(15, 35))
		wolf.health -= dmg
		wolf.apply_injury(Wolf.Injury.HEAVY if dmg >= 25.0 else Wolf.Injury.LIGHT, 4 if dmg >= 25.0 else 2)
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
	var t: Dictionary = data.get("time", {})
	GameTime.time_mode = t.get("time_mode", "normal")
	GameTime.season_index = int(t.get("season_index", 3))
	GameTime.day = int(t.get("day", 1))
	GameTime.period_index = int(t.get("period_index", 0))
	GameTime.turn_in_period = int(t.get("turn_in_period", 0))
	_connect_time_signals()
	state_changed.emit()
