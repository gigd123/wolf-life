class_name EncounterSystem
extends RefCounted

# Stateless rolls against the region/season tables in data/regions.json.
# Every animal, whether prey or competitor, is just a row in that data —
# adding a new one for Phase 2 needs no change here.

static func region_data(region_id: String) -> Dictionary:
	return GameData.regions().get(region_id, {})

# period：獵物出現率依時段（animals.json 的 period_activity）；
# depletion：該區域各獵物的資源消耗倍率（GameState.region_depletion），沒有就是 1。
static func find_tracks(region_id: String, season: String, period: String = "", depletion: Dictionary = {}) -> Dictionary:
	var region: Dictionary = region_data(region_id)
	var weights: Dictionary = _seasonal_weights(region.get("prey_weights", {}), season)
	if weights.is_empty():
		return {"found": false}
	# 找到機率依「調整後總權重 / 原始總權重」縮放，時段與資源消耗才會真的影響出現率。
	var base_total := 0.0
	var adjusted_total := 0.0
	for animal_id in weights.keys():
		base_total += float(weights[animal_id])
		var activity: Dictionary = GameData.animals.get(animal_id, {}).get("period_activity", {})
		weights[animal_id] = float(weights[animal_id]) * float(activity.get(period, 1.0)) * float(depletion.get(animal_id, 1.0))
		adjusted_total += float(weights[animal_id])
	var b: Dictionary = GameData.balance
	var find_chance: float = float(b.get("find_tracks_base_chance", 0.6)) * adjusted_total / base_total
	if not RNGService.chance(min(find_chance, float(b.get("find_tracks_max_chance", 0.9)))):
		return {"found": false}
	var picked: String = RNGService.weighted_pick(weights)
	var stage: String = "adult" if RNGService.chance(0.7) else "juvenile"
	return {"found": true, "animal_id": picked, "life_stage": stage}

static func roll_competitor(region_id: String, season: String) -> Dictionary:
	var region: Dictionary = region_data(region_id)
	var weights: Dictionary = _seasonal_weights(region.get("competitor_weights", {}), season)
	if weights.is_empty():
		return {"encountered": false}
	var total: float = 0.0
	for w in weights.values():
		total += float(w)
	var chance_value: float = clamp(total / 40.0, 0.0, 0.35)
	if not RNGService.chance(chance_value):
		return {"encountered": false}
	var picked: String = RNGService.weighted_pick(weights)
	var stage: String = "adult" if RNGService.chance(0.85) else "juvenile"
	return {"encountered": true, "animal_id": picked, "life_stage": stage}

static func find_sleep_spot(region_id: String) -> bool:
	var region: Dictionary = region_data(region_id)
	var chance_value: float = float(region.get("sleep_find_chance", 0.5))
	return RNGService.chance(chance_value)

static func gather(region_id: String, season: String) -> Dictionary:
	var region: Dictionary = region_data(region_id)
	var weights: Dictionary = _seasonal_weights(region.get("gather_weights", {}), season)
	if weights.is_empty():
		return {"found": false}
	var picked: String = RNGService.weighted_pick(weights)
	return {"found": true, "item_id": picked}

static func _seasonal_weights(table: Dictionary, season: String) -> Dictionary:
	var weights: Dictionary = {}
	for item_id in table.keys():
		var seasonal: Dictionary = table[item_id]
		var w: float = float(seasonal.get(season, 0))
		if w > 0.0:
			weights[item_id] = w
	return weights
