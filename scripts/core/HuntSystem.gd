class_name HuntSystem
extends RefCounted

# One hunt attempt: discover -> stalk -> chase -> fight. Small prey (hare,
# red_fox) skip straight to chase per DESIGN.md "小型獵物流程可縮短". Every
# stage can be abandoned; failure at discover/stalk/chase lets the prey flee
# with no cost beyond spent turns/stamina. All tuning numbers live under
# balance.json's "hunt" key, not here, per DESIGN.md's data-driven principle.
#
# Stage choices are meant to trade something for something, not just flavor
# text: stalk/chase approaches trade stamina for odds, a chase tactic can
# bank a bonus for the fight stage instead of boosting itself, and the three
# fight moves lean on different stats (bite_throat -> skill, pin -> strength,
# bite_leg -> balanced/safe) so a wolf's stat profile and life stage actually
# matter for which move is best.

enum Stage { DISCOVER, STALK, CHASE, FIGHT, DONE }
enum Result { ONGOING, SUCCESS, PREY_FLED, PLAYER_GAVE_UP }

var wolf: Wolf
var animal_id: String
var life_stage: String
var size: String

var stage: int = Stage.DISCOVER
var result: int = Result.ONGOING
var fight_bonus_from_chase: float = 0.0

var prey_detection: float
var prey_stamina: float
var prey_speed: float
var prey_counter_attack: float
var prey_hunger_value: float

# detection_mod：時段等外部因素對獵物警覺的修正（例如深夜 -10）。
func _init(p_wolf: Wolf, p_animal_id: String, p_life_stage: String, detection_mod: float = 0.0) -> void:
	wolf = p_wolf
	animal_id = p_animal_id
	life_stage = p_life_stage
	var animal_data: Dictionary = GameData.animals.get(animal_id, {})
	size = animal_data.get("size", "medium")
	var stats: Dictionary = animal_data.get(life_stage, {})
	prey_detection = float(stats.get("detection", 40)) + detection_mod
	prey_stamina = float(stats.get("stamina", 40))
	prey_speed = float(stats.get("speed", 40))
	prey_counter_attack = float(stats.get("counter_attack", 0))
	prey_hunger_value = float(stats.get("hunger_value", 30))
	if size == "small":
		stage = Stage.CHASE

func _tuning() -> Dictionary:
	return GameData.balance.get("hunt", {})

func _roll(success_chance: float) -> bool:
	return RNGService.chance(clamp(success_chance, 0.05, 0.95))

func do_discover() -> Dictionary:
	var t: Dictionary = _tuning()
	var chance_value: float = float(t.get("discover_base", 0.6)) \
		+ (wolf.effective_skill() - prey_detection) / float(t.get("discover_skill_divisor", 140))
	if _roll(chance_value):
		stage = Stage.STALK
		return {"success": true, "text_key": "hunt.discover.success"}
	result = Result.PREY_FLED
	stage = Stage.DONE
	return {"success": false, "text_key": "hunt.discover.fail"}

func do_stalk(approach: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var bonus_table: Dictionary = t.get("stalk_approach_bonus", {})
	var stamina_table: Dictionary = t.get("stalk_approach_stamina", {})
	var chance_value: float = float(t.get("stalk_base", 0.58)) \
		+ (wolf.effective_skill() - prey_detection) / float(t.get("stalk_skill_divisor", 110)) \
		+ float(bonus_table.get(approach, 0.0))
	wolf.stamina -= float(stamina_table.get(approach, 5))
	if _roll(chance_value):
		stage = Stage.CHASE
		return {"success": true, "text_key": "hunt.stalk.success"}
	result = Result.PREY_FLED
	stage = Stage.DONE
	return {"success": false, "text_key": "hunt.stalk.fail"}

func do_chase(tactic: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var bonus_table: Dictionary = t.get("chase_tactic_bonus", {})
	var stamina_table: Dictionary = t.get("chase_tactic_stamina", {})
	var fight_bonus_table: Dictionary = t.get("chase_tactic_fight_bonus", {})
	# Small prey (hare/red_fox) are meant to be the reliable, low-risk food
	# source for a young or old wolf (see DESIGN.md "容易捕捉但營養低"), so
	# their raw speed counts for much less here than a deer's or bear's would.
	var base_key: String = "chase_base_small" if size == "small" else "chase_base"
	var divisor_key: String = "chase_speed_divisor_small" if size == "small" else "chase_speed_divisor"
	var chance_value: float = float(t.get(base_key, 0.58)) \
		+ (wolf.effective_speed() - prey_speed) / float(t.get(divisor_key, 110)) \
		+ float(bonus_table.get(tactic, 0.0))
	wolf.stamina -= float(stamina_table.get(tactic, 10))
	if wolf.stamina <= 0.0:
		chance_value -= 0.15
	if _roll(chance_value):
		stage = Stage.FIGHT
		fight_bonus_from_chase = float(fight_bonus_table.get(tactic, 0.0))
		return {"success": true, "text_key": "hunt.chase.success"}
	result = Result.PREY_FLED
	stage = Stage.DONE
	return {"success": false, "text_key": "hunt.chase.fail"}

func do_fight(move: String) -> Dictionary:
	var t: Dictionary = _tuning()
	var weight_table: Dictionary = t.get("fight_move_strength_weight", {})
	var mod_table: Dictionary = t.get("fight_move_success_mod", {})
	var counter_table: Dictionary = t.get("fight_move_counter_mult", {})
	var strength_weight: float = float(weight_table.get(move, 1.0))
	var power: float = wolf.effective_strength() * strength_weight + wolf.effective_skill() * (2.0 - strength_weight)
	var chance_value: float = float(t.get("fight_base", 0.58)) \
		+ (power - 40.0 - prey_counter_attack) / float(t.get("fight_power_divisor", 130)) \
		+ fight_bonus_from_chase + float(mod_table.get(move, 0.0))
	stage = Stage.DONE
	if _roll(chance_value):
		result = Result.SUCCESS
		# 進食回復固定為獵物的 hunger_value；分段進食在 1.5 第 6 步處理。
		var hunger_gain: float = prey_hunger_value
		wolf.hunger += hunger_gain
		return {"success": true, "text_key": "hunt.fight.success", "hunger_gain": hunger_gain}
	result = Result.PREY_FLED
	var counter_chance: float = (prey_counter_attack / 100.0) * float(counter_table.get(move, 1.0))
	if RNGService.chance(counter_chance):
		var dmg: float = float(RNGService.randi_range(5, 15))
		wolf.health -= dmg
		if dmg >= 12.0:
			wolf.apply_injury(Wolf.Injury.LIGHT, 2)
		return {"success": false, "text_key": "hunt.fight.counter", "damage": dmg}
	return {"success": false, "text_key": "hunt.fight.fail"}

func give_up() -> void:
	result = Result.PLAYER_GAVE_UP
	stage = Stage.DONE
