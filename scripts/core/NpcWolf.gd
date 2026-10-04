class_name NpcWolf
extends RefCounted

# 具名 NPC 狼（SPEC 1.6「陌生灰狼」）：一隻貫穿一生、持續存在的狼。和玩家一樣有能力值、年齡、傷勢，
# 會到達巔峰、進入老年、衰退，也可能老死或死於其他原因。和玩家之間的每次相遇都記在 record。
# 設計成可以重複使用：Phase 3 可能成為某個狼群的首領，或在玩家成為首領後回來挑戰。
# 數值在 balance.json 的 npc_wolves.<id>。

var id: String = ""
var sex: String = "male"
var age_years: float = 3.5
var speed: float = 65.0
var strength: float = 70.0
var skill: float = 65.0
var perception: float = 60.0
var health_max: float = 110.0
var health: float = 110.0
var alive: bool = true
var death_cause: String = ""
var territory: String = "" # 牠占據的那一帶（區域 id）；被玩家趕走後會換地方
var dominance: int = 0 # 玩家輸給牠或向牠示弱的次數：越高越常把玩家趕走
var yielded_to_player: bool = false # 輸給玩家、示弱離開後，就不再驅趕玩家
var relation: int = 0 # 對玩家的關係值（苔原狼）：越高越熟悉、友善，負的是敵視；Phase 3 用來決定能不能配對或加入狼群
# 每次相遇：{age（玩家年齡）, npc_age, kind（meet／drive_off／follow）, outcome, wolf_damage, npc_damage, region}
var record: Array = []

# base：沿用另一個 NPC 的設定，只覆寫有寫的欄位（例如苔原狼的另一隻）。
static func cfg(npc_id: String) -> Dictionary:
	var table: Dictionary = GameData.balance.get("npc_wolves", {})
	var c: Dictionary = table.get(npc_id, {})
	if c.has("base"):
		var merged: Dictionary = table.get(str(c["base"]), {}).duplicate()
		merged.merge(c, true)
		return merged
	return c

# 開局時建立：年齡與能力在設定的範圍內隨機。
static func create(npc_id: String, territory_region: String) -> NpcWolf:
	var c := cfg(npc_id)
	var n := NpcWolf.new()
	n.id = npc_id
	n.sex = str(c.get("sex", "male"))
	n.territory = territory_region
	var age: Array = c.get("start_age", [3.0, 4.0])
	n.age_years = snapped(RNGService.randf_range(float(age[0]), float(age[1])), 0.25)
	var stats: Dictionary = c.get("start_stats", {})
	for stat in ["speed", "strength", "skill", "perception", "health_max"]:
		var r: Array = stats.get(stat, [60, 70])
		n.set(stat, float(RNGService.randi_range(int(r[0]), int(r[1]))))
	n.health = n.health_max
	return n

func life_stage_key() -> String:
	var ages: Dictionary = cfg(id).get("ages", {})
	if age_years >= float(ages.get("elder", 6.0)):
		return "elder"
	if age_years >= float(ages.get("peak_end", 5.0)):
		return "past_peak"
	return "prime"

# 戰鬥用的力量值（同狼的公式：力量 + 技巧）。
func power() -> float:
	return strength + skill

# 每季：年齡增加、老年衰退、傷勢回復，並判定老死與其他原因的死亡。回傳死因（沒死是空字串）。
func on_season_passed() -> String:
	if not alive:
		return ""
	var c := cfg(id)
	age_years += 0.25
	health = health_max
	var ages: Dictionary = c.get("ages", {})
	var elder_age: float = float(ages.get("elder", 6.0))
	if age_years >= elder_age:
		var decay: Dictionary = c.get("elder_decay_per_season", {})
		for stat in decay.keys():
			set(stat, max(10.0, float(get(stat)) - float(decay[stat])))
		health = min(health, health_max)
		var d: Dictionary = c.get("old_age_death", {})
		if RNGService.chance(float(d.get("base", 0.03)) + (age_years - elder_age) * float(d.get("per_year", 0.04))):
			_die("old_age")
			return death_cause
	if RNGService.chance(float(c.get("other_death_per_season", 0.01))):
		_die("bear")
	return death_cause

func _die(cause: String) -> void:
	alive = false
	death_cause = cause

func die(cause: String) -> void:
	_die(cause)

# 戰鬥對手的資料（FightRules／Combat 用，格式同 balance.json 的 combat.opponents）。
func combat_profile() -> Dictionary:
	var c := cfg(id)
	var d: Dictionary = c.get("combat", {})
	var dmg_base: float = 4.0 + strength * float(d.get("damage_per_strength", 0.15))
	return {"power": power(), "hp": health_max, "damage": [int(dmg_base), int(dmg_base + 8)],
		"parts": d.get("parts", {"leg": 0.4, "shoulder": 0.4, "face": 0.2}),
		"give_up_ratio": float(d.get("give_up_ratio", 0.35)), "threat_resist": float(d.get("threat_resist", 0.3)),
		"can_submit": bool(d.get("can_submit", true)), "never_lethal": bool(d.get("never_lethal", false)), "desperate_hit": float(d.get("desperate_hit", 0.2)), "desperate_damage": float(d.get("desperate_damage", 1.5)), "yields_to_stronger": bool(d.get("yields_to_stronger", false))}

func add_record(entry: Dictionary) -> void:
	entry["npc_age"] = snapped(age_years, 0.25)
	record.append(entry)

func to_dict() -> Dictionary:
	return {"id": id, "sex": sex, "age_years": age_years, "speed": speed, "strength": strength, "skill": skill,
		"perception": perception, "health_max": health_max, "health": health, "alive": alive, "death_cause": death_cause,
		"territory": territory, "dominance": dominance, "yielded_to_player": yielded_to_player, "relation": relation, "record": record}

static func from_dict(data: Dictionary) -> NpcWolf:
	var n := NpcWolf.new()
	for key in ["id", "sex", "death_cause", "territory"]:
		n.set(key, str(data.get(key, n.get(key))))
	for key in ["age_years", "speed", "strength", "skill", "perception", "health_max", "health"]:
		n.set(key, float(data.get(key, n.get(key))))
	n.alive = bool(data.get("alive", true))
	n.dominance = int(data.get("dominance", 0))
	n.relation = int(data.get("relation", 0))
	n.yielded_to_player = bool(data.get("yielded_to_player", false))
	n.record = data.get("record", [])
	return n
