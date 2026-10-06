class_name Wolf
extends RefCounted

# Pure data + rules for the player wolf. No node, no drawing — Game.gd only
# reads this to render, and every mutation happens through GameState so the
# UI layer can be swapped for Phase 5 without touching any of this.

enum LifeStage { SUBADULT, ADULT, ELDER }
enum Injury { NONE, LIGHT, HEAVY }

var health: float = 80.0
var health_max: float = 80.0 # 血量上限（SPEC 1.6）：目前血量最多能回到的數值，會成長、納入潛力
var stamina: float = 80.0
var speed: float = 40.0
var strength: float = 40.0
var skill: float = 40.0
var perception: float = 40.0

var hunger: float = 70.0
var health_value: float = 80.0 # 「體質」：長期狀態（變數名沿用 health_value）
var age_years: float = 0.6667

var injury: int = Injury.NONE
var injury_days_remaining: int = 0
var injury_stat: String = "" # 重傷影響的能力："speed"、"strength" 或 "perception"
var injury_part: String = "" # 受傷部位：leg／shoulder／face（SPEC 1.6「傷勢與舊傷」）
var injury_source: String = "" # 傷從哪裡來（例如 "grizzly_bear.carcass"），重傷留下舊傷時記下
var last_injury_source: String = "" # 最近一次受傷（含輕傷）的來源，受傷提示用（QA-51），不存檔
# 舊傷：[{part, stat, source, age}]；flare_index／flare_days：目前發作的舊傷與剩下的天數（-1 = 沒有發作）。
var old_injuries: Array = []
var flare_index: int = -1
var flare_days: int = 0
var heavy_injury_count: int = 0 # 一生中受過幾次重傷（一生回顧）
var poison_days_remaining: int = 0

var alive: bool = true
var death_cause: String = ""

# 成長（見 Growth.gd）：開局能力值、成年時結算的巔峰上限、還沒睡覺結算的鍛鍊點、連續吃飽睡覺的天數。
var start_stats: Dictionary = {}
var potential: Dictionary = {}
var training: Dictionary = {}
var fed_streak: int = 0
# 換季成長：每晚保留的身體成長，換季時發放（SPEC 1.6「成長系統」）
var season_reserve: Dictionary = {}
# 環境對感知的倍率（苔原的白矇天），由 GameState 每個時段設定，不存檔。
var env_perception_mult: float = 1.0

func _init() -> void:
	age_years = float(GameData.balance.get("start_age_years", 0.6667))
	health_max = float(GameData.balance.get("start_health_max", 80))
	health = health_max
	start_stats = {"speed": speed, "strength": strength, "skill": skill, "perception": perception, "health_max": health_max}

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
	health_max = clamp(health_max, 1.0, float(GameData.balance.get("growth", {}).get("potential", {}).get("max", {}).get("health_max", 120)))
	health = clamp(health, smin, health_max)
	stamina = clamp(stamina, smin, smax)
	speed = clamp(speed, smin, smax)
	strength = clamp(strength, smin, smax)
	skill = clamp(skill, smin, smax)
	perception = clamp(perception, smin, smax)
	hunger = clamp(hunger, smin, float(GameData.balance.get("hunger_max", smax)))
	health_value = clamp(health_value, smin, smax)

func apply_injury(severity: int, days: int, stat: String = "", part: String = "", source: String = "") -> void:
	if severity == Injury.HEAVY:
		heavy_injury_count += 1
	if source != "":
		last_injury_source = source
	if severity >= injury:
		if severity == Injury.HEAVY and (injury != Injury.HEAVY or injury_stat == ""):
			injury_stat = stat
			injury_part = part
			injury_source = source
		injury = severity
		injury_days_remaining = max(injury_days_remaining, days)

func clear_injury() -> void:
	injury = Injury.NONE
	injury_days_remaining = 0
	injury_stat = ""
	injury_part = ""
	injury_source = ""

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
	return perception * _hunger_stat_mult() * _injury_mult("perception") * env_perception_mult

# 身上有傷時的體力消耗倍率（1.6 試玩回饋：輕傷原本沒有任何影響）。重傷也適用，重傷另外會降低能力。
func injury_stamina_mult() -> float:
	return float(GameData.balance.get("injury_stamina_mult", 1.15)) if injury != Injury.NONE else 1.0

func is_overfed() -> bool:
	return hunger > float(GameData.balance.get("overfed_threshold", 120))

func _hunger_stat_mult() -> float:
	var p: Dictionary = GameData.balance.get("hunger_penalties", {})
	if hunger < float(p.get("severe_threshold", 10)):
		return float(p.get("severe_stat_mult", 0.9))
	return 1.0

# 重傷與舊傷發作：影響對應的能力（技巧不受傷勢影響）。
func _injury_mult(stat: String) -> float:
	var mult: float = 1.0
	if injury == Injury.HEAVY and injury_stat == stat:
		mult *= float(GameData.balance.get("heavy_injury_stat_mult", 0.8))
	if flare_index >= 0 and flare_index < old_injuries.size() and str(old_injuries[flare_index].get("stat", "")) == stat:
		mult *= float(GameData.balance.get("combat", {}).get("old_injury", {}).get("flare_mult", 0.9))
	return mult

func to_dict() -> Dictionary:
	return {
		"health": health, "health_max": health_max, "stamina": stamina, "speed": speed,
		"strength": strength, "skill": skill, "perception": perception,
		"hunger": hunger, "health_value": health_value, "age_years": age_years,
		"injury": injury, "injury_days_remaining": injury_days_remaining, "injury_stat": injury_stat, "heavy_injury_count": heavy_injury_count,
		"poison_days_remaining": poison_days_remaining,
		"injury_part": injury_part, "injury_source": injury_source,
		"old_injuries": old_injuries, "flare_index": flare_index, "flare_days": flare_days,
		"alive": alive, "death_cause": death_cause,
		"start_stats": start_stats, "potential": potential, "training": training, "fed_streak": fed_streak, "season_reserve": season_reserve,
	}

static func from_dict(data: Dictionary) -> Wolf:
	var w := Wolf.new()
	w.health_max = float(data.get("health_max", 80.0))
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
	w.injury_part = str(data.get("injury_part", ""))
	w.injury_source = str(data.get("injury_source", ""))
	w.old_injuries = data.get("old_injuries", [])
	w.flare_index = int(data.get("flare_index", -1))
	w.flare_days = int(data.get("flare_days", 0))
	w.alive = bool(data.get("alive", true))
	w.death_cause = str(data.get("death_cause", ""))
	w.start_stats = data.get("start_stats", w.start_stats)
	w.potential = data.get("potential", {})
	w.training = data.get("training", {})
	w.fed_streak = int(data.get("fed_streak", 0))
	w.season_reserve = data.get("season_reserve", {})
	return w
