extends Node

# Central seeded RNG so a run can be reproduced from its seed for debugging.
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	randomize_seed()

func randomize_seed() -> void:
	rng.randomize()

func set_seed(value: int) -> void:
	rng.seed = value

func get_seed() -> int:
	return rng.seed

func randf() -> float:
	return rng.randf()

func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)

func chance(probability: float) -> bool:
	return rng.randf() < probability

func weighted_pick(weights: Dictionary) -> String:
	var total := 0.0
	for key in weights.keys():
		total += float(weights[key])
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	var cumulative := 0.0
	var keys: Array = weights.keys()
	for key in keys:
		cumulative += float(weights[key])
		if roll <= cumulative:
			return key
	return keys[keys.size() - 1]
