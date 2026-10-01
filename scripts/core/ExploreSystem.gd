class_name ExploreSystem
extends RefCounted

# 探索（SPEC「探索系統」）：每次產生一個「發現」，由四個欄位組合而成——
# 地點特徵（區域的地形）× 線索類型 × 來源 × 新鮮度。這裡只產生資料（翻譯鍵與參數），
# 文字組合由畫面層負責。數值都在 data/discovery.json。
#
# 發現的種類（kind）：
# - "clue"：獵物或採集物的線索，可追蹤、狩獵或採集
# - "feature"：發現區域的次要特徵（好睡處、獵物小徑等），寫入區域知識
# - "nothing"：什麼都沒發現，但附帶一點資訊（哪種動物最近沒來過）
# 之後的步驟會加入灰熊、陌生灰狼的線索與知識修正，來源清單由資料決定。

static func _cfg() -> Dictionary:
	return GameData.discovery

# ctx：region_id, season, period, depletion, wind_dir, known_features(Array)
static func generate(ctx: Dictionary) -> Dictionary:
	var cfg := _cfg()
	var region_id: String = ctx["region_id"]
	var region: Dictionary = EncounterSystem.region_data(region_id)
	var terrains: Array = region.get("terrains", ["dense_forest"])
	var location: String = terrains[RNGService.randi_range(0, terrains.size() - 1)]
	var known_features: Array = ctx.get("known_features", [])

	var prey := EncounterSystem.prey_weights(region_id, ctx["season"], ctx["period"],
		ctx.get("depletion", {}), feature_prey_mults(known_features))
	var weights: Dictionary = prey["weights"]
	var ratio: float = 0.0
	if float(prey["base_total"]) > 0.0:
		ratio = float(prey["adjusted_total"]) / float(prey["base_total"])

	# 什麼都沒發現：8%～15%，獵物越少（時段不對、資源消耗）越容易落空。
	var nothing_min: float = float(cfg.get("nothing_chance_min", 0.08))
	var nothing_max: float = float(cfg.get("nothing_chance_max", 0.15))
	var nothing_chance: float = nothing_min + (nothing_max - nothing_min) * clamp(1.0 - ratio, 0.0, 1.0)
	if RNGService.chance(nothing_chance):
		return {"kind": "nothing", "location": location, "absent_source": _least_likely(weights)}

	var unknown: Array = []
	for f in region.get("secondary_features", []):
		if not known_features.has(f):
			unknown.append(f)
	if not unknown.is_empty() and RNGService.chance(float(cfg.get("feature_chance", 0.12))):
		return {"kind": "feature", "location": location, "feature_id": unknown[RNGService.randi_range(0, unknown.size() - 1)]}

	var sources: Dictionary = {}
	for animal_id in weights.keys():
		if float(weights[animal_id]) > 0.0:
			sources[animal_id] = weights[animal_id]
	var gather := EncounterSystem.gather_weights(region_id, ctx["season"])
	for item_id in gather.keys():
		sources[item_id] = float(gather[item_id]) * float(cfg.get("gather_source_weight_mult", 0.5))
	if sources.is_empty():
		return {"kind": "nothing", "location": location, "absent_source": _least_likely(weights)}
	var source: String = RNGService.weighted_pick(sources)

	if gather.has(source):
		return {"kind": "clue", "source_kind": "gather", "source": source, "clue": "sight",
			"location": location, "fresh": true, "fresh_known": true}

	var prey_dir: int = RNGService.randi_range(0, 3)
	var wind: String = HuntSystem.relative_wind(int(ctx.get("wind_dir", 0)), prey_dir)
	var clue_weights: Dictionary = cfg.get("clue_weights", {}).get(source, {"track": 1}).duplicate()
	if clue_weights.has("scent"):
		clue_weights["scent"] = float(clue_weights["scent"]) * float(cfg.get("scent_wind_mult", {}).get(wind, 1.0))
	var clue: String = RNGService.weighted_pick(clue_weights)

	var fresh: bool = true
	if not cfg.get("always_fresh_clues", []).has(clue):
		var activity: Dictionary = GameData.animals.get(source, {}).get("period_activity", {})
		var fresh_chance: float = float(cfg.get("fresh_chance_base", 0.55)) * float(activity.get(ctx["period"], 1.0))
		fresh = RNGService.chance(clamp(fresh_chance, float(cfg.get("fresh_chance_min", 0.2)), float(cfg.get("fresh_chance_max", 0.85))))
	# 逆風時氣味可判斷新鮮度；側風、順風時聞不出來。其他線索都看得出新舊。
	var fresh_known: bool = clue != "scent" or wind == "headwind"
	var life_stage: String = "juvenile" if RNGService.chance(float(cfg.get("juvenile_chance", 0.3))) else "adult"
	# 成體的變體（例如白尾鹿雄鹿），狩獵深度不同。
	if life_stage == "adult":
		var variants: Dictionary = cfg.get("adult_variants", {}).get(source, {})
		for variant in variants.keys():
			if RNGService.chance(float(variants[variant])):
				life_stage = variant
				break
	return {"kind": "clue", "source_kind": "prey", "source": source, "clue": clue, "location": location,
		"fresh": fresh, "fresh_known": fresh_known, "wind": wind, "prey_dir": prey_dir, "life_stage": life_stage}

static func _least_likely(weights: Dictionary) -> String:
	var best: String = ""
	for animal_id in weights.keys():
		if best == "" or float(weights[animal_id]) < float(weights[best]):
			best = animal_id
	return best

# 已知區域特徵對獵物出現率的加成（例如獵物小徑 → 鹿 ×1.3）。
static func feature_prey_mults(known_features: Array) -> Dictionary:
	var mults: Dictionary = {}
	var all_features: Dictionary = GameData.region_features()
	for f in known_features:
		var table: Dictionary = all_features.get(f, {}).get("prey_mult", {})
		for animal_id in table.keys():
			mults[animal_id] = float(mults.get(animal_id, 1.0)) * float(table[animal_id])
	return mults

# 追蹤：感知判定，受風向影響。只有獵物線索可以追蹤；看得出是陳舊的線索不能追蹤。
static func can_track(discovery: Dictionary) -> bool:
	if discovery.get("kind", "") != "clue" or discovery.get("source_kind", "") != "prey":
		return false
	if discovery.get("clue", "") == "sight":
		return false
	return discovery.get("fresh", false) or not discovery.get("fresh_known", true)

static func track_chance(discovery: Dictionary, perception: float) -> Dictionary:
	var t: Dictionary = _cfg().get("track", {})
	var stats: Dictionary = GameData.animals.get(discovery["source"], {}).get(discovery.get("life_stage", "adult"), {})
	var detection: float = float(stats.get("detection", 40))
	var factors: Array = []
	var diff: float = (perception - detection) / float(t.get("perception_divisor", 150))
	if diff >= 0.0:
		factors.append({"key": "factor.sharp_nose", "good": true, "weight": diff})
	else:
		factors.append({"key": "factor.faint_trail", "good": false, "weight": -diff})
	var wind: String = discovery.get("wind", "crosswind")
	var w: float = float(t.get("wind_bonus", {}).get(wind, 0.0))
	factors.append({"key": "factor.wind." + wind, "good": w >= 0.0, "weight": absf(w)})
	if not discovery.get("fresh_known", true):
		factors.append({"key": "factor.fresh_unknown", "good": false, "weight": 0.0, "info": true})
	return {"chance": HuntSystem.clamp_chance(float(t.get("base", 0.6)) + diff + w), "factors": factors}
