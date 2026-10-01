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
var perception: float = 40.0

var hunger: float = 70.0
var health_value: float = 80.0
var age_years: float = 0.6667

var injury: int = Injury.NONE
var injury_days_remaining: int = 0
var injury_stat: String = "" # 重傷影響的能力："speed" 或 "strength"
var heavy_injury_count: int = 0 # 一生中受過幾次重傷（一生回顧）
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
	perception = clamp(perception, smin, smax)
	hunger = clamp(hunger, smin, float(GameData.balance.get("hunger_max", smax)))
	health_value = clamp(health_value, smin, smax)

func apply_injury(severity: int, days: int, stat: String = "") -> void:
	if severity == Injury.HEAVY:
		heavy_injury_count += 1
	if severity >= injury:
		if severity == Injury.HEAVY and (injury != Injury.HEAVY or injury_stat == ""):
			injury_stat = stat
		injury = severity
		injury_days_remaining = max(injury_days_remaining, days)

func clear_injury() -> void:
	injury = Injury.NONE
	injury_days_remaining = 0
	injury_stat = ""

# 判定用的實際能力值：基礎值再乘上飢餓、吃太撐、重傷的修正。畫面上的素質條顯示基礎值。
func effective_speed() -> float:
	var b: Dictionary = GameData.balance
	var mult := _hunger_stat_mult() * _injury_mult("speed")
	if hunger > float(b.get("overfed_threshold", 120)):
		mult *= float(b.get("overfed_speed_mult", 0.9))
	return speed * mult

func effective_strength() -> float:
	return strength * _hunger_stat_mult() * _injury_mult("strength")

func effective_skill() -> float:
	return skill * _hunger_stat_mult()

func effective_perception() -> float:
	return perception * _hunger_stat_mult()

func is_overfed() -> bool:
	return hunger > float(GameData.balance.get("overfed_threshold", 120))

func _hunger_stat_mult() -> float:
	var p: Dictionary = GameData.balance.get("hunger_penalties", {})
	if hunger < float(p.get("severe_threshold", 10)):
		return float(p.get("severe_stat_mult", 0.9))
	return 1.0

func _injury_mult(stat: String) -> float:
	if injury == Injury.HEAVY and injury_stat == stat:
		return float(GameData.balance.get("heavy_injury_stat_mult", 0.8))
	return 1.0

func to_dict() -> Dictionary:
	return {
		"health": health, "stamina": stamina, "speed": speed,
		"strength": strength, "skill": skill, "perception": perception,
		"hunger": hunger, "health_value": health_value, "age_years": age_years,
		"injury": injury, "injury_days_remaining": injury_days_remaining, "injury_stat": injury_stat, "heavy_injury_count": heavy_injury_count,
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
	w.perception = float(data.get("perception", 40.0))
	w.hunger = float(data.get("hunger", 70.0))
	w.health_value = float(data.get("health_value", 80.0))
	w.age_years = float(data.get("age_years", 0.6667))
	w.injury = int(data.get("injury", Injury.NONE))
	w.injury_days_remaining = int(data.get("injury_days_remaining", 0))
	w.injury_stat = str(data.get("injury_stat", ""))
	w.heavy_injury_count = int(data.get("heavy_injury_count", 0))
	w.poison_days_remaining = int(data.get("poison_days_remaining", 0))
	w.alive = bool(data.get("alive", true))
	w.death_cause = str(data.get("death_cause", ""))
	return w
