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
# 灰熊與陌生灰狼（threat）的前置線索：爪痕、危險氣味、翻倒的木頭、狼的腳印、相似氣味，
# 以及遠距目擊。權重依區域與季節（灰熊冬眠時沒有線索），文字依是否已辨識而不同。

static func _cfg() -> Dictionary:
	return GameData.discovery

# 探索方式（Phase 1.7b）：trail 沿獸徑走、ridge 登高嗅風、water 守在水邊、border 巡一圈邊界。
static func mode_cfg(mode: String) -> Dictionary:
	return _cfg().get("modes", {}).get(mode, _cfg().get("modes", {}).get("trail", {}))

# 這一區能不能用這種方式（守在水邊要有溪流、河谷柳叢或知道水潭）。
static func mode_available(mode: String, region_id: String, known_features: Array) -> bool:
	var needs: Array = mode_cfg(mode).get("needs", [])
	if needs.is_empty():
		return true
	var terrains: Array = EncounterSystem.region_data(region_id).get("terrains", [])
	for n in needs:
		if terrains.has(n) or known_features.has(n):
			return true
	return false

# ctx：region_id, season, period, depletion, wind_dir, known_features(Array)；
# Phase 1.7b 另外有 mode（探索方式）、marks（附近其他狼的氣味：[{who, region}]）、notables（這一區會延續的個體）。
static func generate(ctx: Dictionary) -> Dictionary:
	var cfg := _cfg()
	var region_id: String = ctx["region_id"]
	var region: Dictionary = EncounterSystem.region_data(region_id)
	var terrains: Array = region.get("terrains", ["dense_forest"])
	var location: String = terrains[RNGService.randi_range(0, terrains.size() - 1)]
	var known_features: Array = ctx.get("known_features", [])
	var mode: String = str(ctx.get("mode", "trail"))
	var mc := mode_cfg(mode)
	var spot_known: bool = mc.has("spot") and known_features.has(str(mc["spot"]))
	# 守在水邊：在水邊等，看到的就是來喝水的獵物
	if mode == "water":
		for t in ["stream", "river_willow"]:
			if terrains.has(t):
				location = t
	# 登高嗅風看風向：順風時遠處的氣味都聞得到，逆風時幾乎沒用（文字寫出來）
	var wind_good: bool = mode != "ridge" or RNGService.chance(float(mc.get("wind_good_chance", 0.5)) + (0.25 if spot_known else 0.0))

	var mults := feature_prey_mults(known_features)
	var knowledge_mults: Dictionary = ctx.get("prey_knowledge", {})
	for animal_id in knowledge_mults.keys():
		mults[animal_id] = float(mults.get(animal_id, 1.0)) * float(knowledge_mults[animal_id])
	var prey := EncounterSystem.prey_weights(region_id, ctx["season"], ctx["period"],
		ctx.get("depletion", {}), mults)
	var weights: Dictionary = prey["weights"]
	var ratio: float = 0.0
	if float(prey["base_total"]) > 0.0:
		ratio = float(prey["adjusted_total"]) / float(prey["base_total"])

	# 什麼都沒發現：8%～15%，獵物越少（時段不對、資源消耗）越容易落空。
	var nothing_min: float = float(cfg.get("nothing_chance_min", 0.08))
	var nothing_max: float = float(cfg.get("nothing_chance_max", 0.15))
	var nothing_chance: float = nothing_min + (nothing_max - nothing_min) * clamp(1.0 - ratio, 0.0, 1.0)
	nothing_chance *= float(mc.get("nothing_mult", 1.0))
	if spot_known:
		nothing_chance *= float(mc.get("spot_nothing_mult", 1.0))
	if not wind_good:
		nothing_chance *= float(mc.get("wind_bad_nothing_mult", 1.0))
	if mode == "water" and not ctx["period"] in ["dawn", "dusk"]:
		nothing_chance = 1.0 - (1.0 - nothing_chance) * float(mc.get("dawn_dusk_mult", 1.0))
	if RNGService.chance(nothing_chance):
		return {"kind": "nothing", "location": location, "absent_source": _least_likely(weights), "mode": mode, "wind_bad": not wind_good}

	# 別人吃剩的殘骸（骨頭、碎肉）與其他狼的氣味標記（Phase 1.7b 的多樣結果）
	var scorched_now: bool = str(ctx.get("burn", "")) in ["burning", "ash"]
	if not scorched_now and RNGService.chance(float(mc.get("remains", 0.0))):
		var big: Array = []
		for animal_id in weights.keys():
			if str(GameData.animals.get(animal_id, {}).get("size", "small")) != "small":
				big.append(animal_id)
		if not big.is_empty():
			# 剩多少：骨頭、一些肉、少見的大半具（2026-10-15 試玩回報 11）
			var tiers: Dictionary = {}
			for t in GameData.discovery.get("remains_tiers", {}):
				tiers[t] = float(GameData.discovery["remains_tiers"][t].get("weight", 1))
			var tier: String = str(RNGService.weighted_pick(tiers)) if not tiers.is_empty() else "some"
			return {"kind": "remains", "location": location, "animal_id": big[RNGService.randi_range(0, big.size() - 1)], "mode": mode, "tier": tier}
	var marks: Array = ctx.get("marks", [])
	if not marks.is_empty() and RNGService.chance(float(mc.get("mark", 0.0))):
		var m: Dictionary = marks[RNGService.randi_range(0, marks.size() - 1)]
		return {"kind": "mark", "location": location, "who": str(m.get("who", "")), "region": str(m.get("region", region_id)), "mode": mode}

	# 燒過一片焦黑（ctx.burn = burning／ash）：找不到次要特徵與採集物（SPEC 1.6「火後」）
	var scorched: bool = str(ctx.get("burn", "")) in ["burning", "ash"]
	var unknown: Array = []
	for f in ([] if scorched else region.get("secondary_features", [])):
		if not known_features.has(f):
			unknown.append(f)
	if not unknown.is_empty() and RNGService.chance(float(cfg.get("feature_chance", 0.12)) * float(mc.get("feature_mult", 1.0))):
		return {"kind": "feature", "location": location, "feature_id": unknown[RNGService.randi_range(0, unknown.size() - 1)]}

	var sources: Dictionary = {}
	for animal_id in weights.keys():
		if float(weights[animal_id]) > 0.0:
			sources[animal_id] = weights[animal_id]
	var gather := {} if scorched else EncounterSystem.gather_weights(region_id, ctx["season"])
	# 年況：乾夏漿果少、濕夏多（1.8 第 11 步）
	for item_id in gather.keys():
		if str(item_id).contains("berr"):
			gather[item_id] = float(gather[item_id]) * float(ctx.get("berries_mult", 1.0))
	for item_id in gather.keys():
		sources[item_id] = float(gather[item_id]) * float(cfg.get("gather_source_weight_mult", 0.5))
	var threats := threat_weights(region_id, ctx["season"], str(ctx.get("stranger_territory", "?")))
	for threat_id in threats.keys():
		sources[threat_id] = float(threats[threat_id]) * float(mc.get("threat_mult", 1.0))
	# 守在水邊只看得到來喝水的獵物（不採集）
	if mode == "water":
		for item_id in gather.keys():
			sources.erase(item_id)
	if sources.is_empty():
		return {"kind": "nothing", "location": location, "absent_source": _least_likely(weights)}
	var source: String = RNGService.weighted_pick(sources)
	# 只出現在某些地形的動物（河狸在水邊、大角羊在岩坡）：地點換成那些地形（Phase 2 第 2 步）
	var only_terrains: Array = cfg.get("source_terrains", {}).get(source, [])
	if not only_terrains.is_empty():
		var ok: Array = terrains.filter(func(t): return only_terrains.has(t))
		if not ok.is_empty():
			location = ok[RNGService.randi_range(0, ok.size() - 1)]

	if threats.has(source):
		var t_cfg: Dictionary = cfg.get("threat_sources", {}).get(source, {})
		var t_clue: String = RNGService.weighted_pick(t_cfg.get("clues", {"sight": 1}))
		var t_fresh: bool = t_clue == "sight" or RNGService.chance(float(cfg.get("fresh_chance_base", 0.55)))
		return {"kind": "clue", "source_kind": "threat", "source": source, "clue": t_clue, "location": location,
			"fresh": t_fresh, "fresh_known": true, "wind": "crosswind", "prey_dir": RNGService.randi_range(0, 3), "life_stage": "adult"}

	if gather.has(source):
		return {"kind": "clue", "source_kind": "gather", "source": source, "clue": "sight",
			"location": location, "fresh": true, "fresh_known": true}

	var prey_dir: int = RNGService.randi_range(0, 3)
	var wind: String = HuntSystem.relative_wind(int(ctx.get("wind_dir", 0)), prey_dir)
	var clue_weights: Dictionary = cfg.get("clue_weights", {}).get(source, {"track": 1}).duplicate()
	var weather: String = str(ctx.get("weather", "clear"))
	var storm_cfg: Dictionary = GameData.events.get("storm", {})
	if clue_weights.has("scent"):
		clue_weights["scent"] = float(clue_weights["scent"]) * float(cfg.get("scent_wind_mult", {}).get(wind, 1.0))
		if weather == "storm":
			clue_weights["scent"] = float(clue_weights["scent"]) * float(storm_cfg.get("scent_mult", 0.2))
	if weather == "after_rain" and clue_weights.has("track"):
		clue_weights["track"] = float(clue_weights["track"]) * float(storm_cfg.get("after_track_mult", 2.0))
	# 探索方式限制線索種類（登高嗅風：遠遠看到或聞到；守在水邊：直接看到）
	var only: Array = mc.get("clues", [])
	if not only.is_empty():
		var limited: Dictionary = {}
		for c in only:
			limited[c] = float(clue_weights.get(c, 1.0))
		clue_weights = limited
	# 繁殖期的公鹿會吼叫：聲音線索變多，聽到的是公鹿（1.8 第 5 步）
	var bugle: Dictionary = cfg.get("bugle", {}).get(source, {})
	var bugling: bool = not bugle.is_empty() and str(bugle.get("season", "")) == str(ctx["season"])
	if bugling and clue_weights.has("sound"):
		clue_weights["sound"] = float(clue_weights["sound"]) * float(bugle.get("sound_mult", 3.0))
	# 草原視野好：比較容易直接看到獵物（Phase 2 第 4 步）
	var sight_mult: float = float(GameData.maps().get(GameData.map_of(region_id), {}).get("sight_mult", 1.0))
	if sight_mult != 1.0 and clue_weights.has("sight"):
		clue_weights["sight"] = float(clue_weights["sight"]) * sight_mult
	var clue: String = RNGService.weighted_pick(clue_weights)

	var fresh: bool = true
	if not cfg.get("always_fresh_clues", []).has(clue):
		var activity: Dictionary = GameData.animals.get(source, {}).get("period_activity", {})
		var fresh_chance: float = float(cfg.get("fresh_chance_base", 0.55)) * float(activity.get(ctx["period"], 1.0))
		if weather == "after_rain":
			fresh_chance += float(storm_cfg.get("after_fresh_bonus", 0.2))
		fresh = RNGService.chance(clamp(fresh_chance, float(cfg.get("fresh_chance_min", 0.2)), float(cfg.get("fresh_chance_max", 0.85))))
		# 暴雨把舊足跡沖掉：雨中看到的足跡、痕跡都是剛留下的
		if weather == "storm" and ["track", "sign"].has(clue):
			fresh = true
	# 逆風時氣味可判斷新鮮度；側風、順風時聞不出來。其他線索都看得出新舊。
	var fresh_known: bool = clue != "scent" or wind == "headwind"
	# 幼體的機率依季節（1.8 第 5 步：產仔季幼體多、早冬的小馬鹿…）
	var juv_chance: float = float(cfg.get("juvenile_season", {}).get(source, {}).get(ctx["season"], cfg.get("juvenile_chance", 0.3)))
	var life_stage: String = "juvenile" if RNGService.chance(juv_chance) else "adult"
	if bugling and clue == "sound":
		life_stage = str(bugle.get("stage", "buck"))
	# 成體的變體（例如白尾鹿雄鹿），狩獵深度不同。
	if life_stage == "adult" and not (bugling and clue == "sound"):
		var variants: Dictionary = cfg.get("adult_variants", {}).get(source, {})
		for variant in variants.keys():
			if RNGService.chance(float(variants[variant])):
				life_stage = variant
				break
	if spot_known and not fresh:
		fresh = RNGService.chance(float(mc.get("spot_fresh_bonus", 0.0)))
	# 偶爾遇到受傷的成體（走簡易狩獵流程）。
	var injured: bool = life_stage != "juvenile" and RNGService.chance(float(cfg.get("injured_chance", 0.08)))
	var result := {"kind": "clue", "source_kind": "prey", "source": source, "clue": clue, "location": location,
		"fresh": fresh, "fresh_known": fresh_known, "wind": wind, "prey_dir": prey_dir, "life_stage": life_stage,
		"injured": injured, "mode": mode}
	if bugling and clue == "sound":
		result["bugle"] = true
	# 夏季剛出生的幼鹿躲在草裡、沒有氣味：找到的是母鹿留下的線索，要靠搜尋把牠找出來
	if life_stage == "juvenile" and cfg.get("hidden_young", {}).get(source, []).has(str(ctx["season"])):
		result["hidden"] = true
		if result["clue"] == "scent":
			result["clue"] = "track"
	if bool(mc.get("ambush", false)):
		result["ambush"] = float(mc.get("ambush_bonus", 0.1))
	# 會延續的個體（提案之十 D）：這一區記著的那頭（跛腳、年老）又出現了
	var n_cfg: Dictionary = cfg.get("notable", {})
	for n in ctx.get("notables", []):
		if str(n.get("animal", "")) == source and RNGService.chance(float(n_cfg.get("again_chance", 0.35))):
			result["life_stage"] = str(n.get("stage", "adult"))
			result["injured"] = true
			result["notable_id"] = int(n.get("id", 0))
			result["trait"] = str(n.get("trait", "lame"))
			result["again"] = true
			result.erase("hidden")
			result.erase("bugle")
			return result
	if injured:
		result["trait"] = str(RNGService.weighted_pick(n_cfg.get("traits", {"lame": 1})))
	return result

# 灰熊依區域的競爭動物季節權重，陌生灰狼依固定的區域權重。
# stranger_territory：陌生灰狼目前的範圍（"" = 牠已經死了，不再有牠的線索；"?" = 不考慮）。
# 牠會在範圍附近出沒，範圍所在的區域權重至少 3。
static func threat_weights(region_id: String, season: String, stranger_territory: String = "?") -> Dictionary:
	var result: Dictionary = {}
	var threat_cfg: Dictionary = _cfg().get("threat_sources", {})
	for threat_id in threat_cfg.keys():
		var t: Dictionary = threat_cfg[threat_id]
		var w: float = 0.0
		if t.has("weight_from"):
			var table: Dictionary = EncounterSystem.region_data(region_id).get(t["weight_from"], {}).get(threat_id, {})
			w = float(table.get(season, 0))
		else:
			w = float(t.get("region_weights", {}).get(region_id, 0))
		if threat_id == "stranger_wolf" and stranger_territory != "?":
			w = 0.0 if stranger_territory == "" else (max(w, 3.0) if region_id == stranger_territory else w)
		if w > 0.0:
			result[threat_id] = w * float(t.get("weight_mult", 0.3))
	return result

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
	if discovery.get("kind", "") != "clue" or not ["prey", "threat"].has(discovery.get("source_kind", "")):
		return false
	if discovery.get("clue", "") == "sight":
		return false
	return discovery.get("fresh", false) or not discovery.get("fresh_known", true)

# knowledge_bonus：「確定」的獵物出沒知識帶來的追蹤加成。
# weather_penalty：暴雨中容易跟丟。
static func track_chance(discovery: Dictionary, perception: float, knowledge_bonus: float = 0.0, weather_penalty: float = 0.0) -> Dictionary:
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
	if knowledge_bonus > 0.0:
		factors.append({"key": "factor.knowledge", "good": true, "weight": knowledge_bonus})
	if weather_penalty > 0.0:
		factors.append({"key": "factor.storm_scent", "good": false, "weight": weather_penalty})
	var camo: float = HuntSystem.camouflage(str(discovery["source"]))
	if camo > 0.0:
		factors.append({"key": "factor.snow_camouflage", "good": false, "weight": camo})
	return {"chance": HuntSystem.clamp_chance(float(t.get("base", 0.6)) + diff + w + knowledge_bonus - weather_penalty - camo), "factors": factors}

# 「確定」的知識：預估此時此地探索發現某種獵物（線索或目擊）的機率，給畫面顯示。
static func estimate_prey_chance(ctx: Dictionary, animal_id: String) -> float:
	var cfg := _cfg()
	var region: Dictionary = EncounterSystem.region_data(ctx["region_id"])
	var mults := feature_prey_mults(ctx.get("known_features", []))
	var knowledge_mults: Dictionary = ctx.get("prey_knowledge", {})
	for a in knowledge_mults.keys():
		mults[a] = float(mults.get(a, 1.0)) * float(knowledge_mults[a])
	var prey := EncounterSystem.prey_weights(ctx["region_id"], ctx["season"], ctx["period"], ctx.get("depletion", {}), mults)
	var weights: Dictionary = prey["weights"]
	var ratio: float = float(prey["adjusted_total"]) / max(0.001, float(prey["base_total"]))
	var nothing: float = float(cfg.get("nothing_chance_min", 0.08)) + (float(cfg.get("nothing_chance_max", 0.15)) - float(cfg.get("nothing_chance_min", 0.08))) * clamp(1.0 - ratio, 0.0, 1.0)
	var total: float = 0.0
	for a in weights.keys():
		total += float(weights[a])
	for item in EncounterSystem.gather_weights(ctx["region_id"], ctx["season"]).values():
		total += float(item) * float(cfg.get("gather_source_weight_mult", 0.5))
	if total <= 0.0:
		return 0.0
	var unknown_features: int = 0
	for f in region.get("secondary_features", []):
		if not ctx.get("known_features", []).has(f):
			unknown_features += 1
	var feature: float = float(cfg.get("feature_chance", 0.12)) if unknown_features > 0 else 0.0
	return (1.0 - nothing) * (1.0 - feature) * float(weights.get(animal_id, 0.0)) / total
