class_name Wolf
extends RefCounted

# Pure data + rules for the player wolf. No node, no drawing — Game.gd only
# reads this to render, and every mutation happens through GameState so the
# UI layer can be swapped for Phase 5 without touching any of this.

enum LifeStage { SUBADULT, ADULT, ELDER }
enum Injury { NONE, LIGHT, HEAVY }

var health: float = 80.0
var stamina: float = 80.0
var speed: float = 40.0
var strength: float = 40.0
var skill: float = 40.0

var hunger: float = 70.0
var health_value: float = 80.0
var age_years: float = 0.6667

var injury: int = Injury.NONE
var injury_days_remaining: int = 0
var poison_days_remaining: int = 0

var alive: bool = true
var death_cause: String = ""

func _init() -> void:
	age_years = float(GameData.balance.get("start_age_years", 0.6667))

func life_stage() -> int:
	var ages: Dictionary = GameData.balance.get("life_stage_ages", {})
	var subadult_end: float = float(ages.get("subadult_end", 2.0))
	var adult_end: float = float(ages.get("adult_end", 6.0))
	if age_years < subadult_end:
		return LifeStage.SUBADULT
	elif age_years < adult_end:
		return LifeStage.ADULT
	return LifeStage.ELDER

func clamp_stats() -> void:
	var smin: float = float(GameData.balance.get("stat_min", 0))
	var smax: float = float(GameData.balance.get("stat_max", 100))
	health = clamp(health, smin, smax)
	stamina = clamp(stamina, smin, smax)
	speed = clamp(speed, smin, smax)
	strength = clamp(strength, smin, smax)
	skill = clamp(skill, smin, smax)
	hunger = clamp(hunger, smin, smax)
	health_value = clamp(health_value, smin, smax)

func apply_injury(severity: int, days: int) -> void:
	if severity >= injury:
		injury = severity
		injury_days_remaining = max(injury_days_remaining, days)

func to_dict() -> Dictionary:
	return {
		"health": health, "stamina": stamina, "speed": speed,
		"strength": strength, "skill": skill,
		"hunger": hunger, "health_value": health_value, "age_years": age_years,
		"injury": injury, "injury_days_remaining": injury_days_remaining,
		"poison_days_remaining": poison_days_remaining,
		"alive": alive, "death_cause": death_cause,
	}

static func from_dict(data: Dictionary) -> Wolf:
	var w := Wolf.new()
	w.health = float(data.get("health", 80.0))
	w.stamina = float(data.get("stamina", 80.0))
	w.speed = float(data.get("speed", 40.0))
	w.strength = float(data.get("strength", 40.0))
	w.skill = float(data.get("skill", 40.0))
	w.hunger = float(data.get("hunger", 70.0))
	w.health_value = float(data.get("health_value", 80.0))
	w.age_years = float(data.get("age_years", 0.6667))
	w.injury = int(data.get("injury", Injury.NONE))
	w.injury_days_remaining = int(data.get("injury_days_remaining", 0))
	w.poison_days_remaining = int(data.get("poison_days_remaining", 0))
	w.alive = bool(data.get("alive", true))
	w.death_cause = str(data.get("death_cause", ""))
	return w
