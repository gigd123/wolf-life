class_name Growth
extends RefCounted

# 成長規則（SPEC 1.6「成長系統」「潛力與生命階段轉變」）。數值都在 balance.json 的 growth。
# - 技巧、感知靠「學」：做了就當下成長（learn），失敗約為成功的 1/4。
# - 速度、力量、血量上限靠「練＋吃＋睡」：白天累積鍛鍊點（train），睡覺時依飽食度結算（settle_sleep）。
# - 進入成年時結算潛力（settle_potential）：巔峰上限 = 基礎上限 + 次成年期累積成長 × 1.5。
# 成年期朝自己的上限成長，越接近上限越慢；老年期速度、力量、血量上限不再成長，逐季衰退。

const BODY_STATS := ["speed", "strength", "health_max"]
const MIND_STATS := ["skill", "perception"]
const ALL_STATS := ["speed", "strength", "skill", "perception", "health_max"]

static func cfg() -> Dictionary:
	return GameData.balance.get("growth", {})

static func _stage_key(wolf: Wolf) -> String:
	match wolf.life_stage():
		Wolf.LifeStage.SUBADULT: return "subadult"
		Wolf.LifeStage.ELDER: return "elder"
	return "adult"

# 生命階段倍率：body（速度、力量、血量上限）或個別能力（老年的技巧、感知分開設定）。
static func stage_mult(wolf: Wolf, stat: String) -> float:
	var table: Dictionary = cfg().get("stage_mult", {}).get(_stage_key(wolf), {})
	if table.has(stat):
		return float(table[stat])
	return float(table.get("body" if BODY_STATS.has(stat) else "mind", 1.0))

static func get_stat(wolf: Wolf, stat: String) -> float:
	return float(wolf.get(stat))

# 成長量套用到能力值：成年後越接近潛力上限越慢，不會超過上限；沒結算潛力前上限是 stat_max。
# 外部直接加成長（例如成年時的一次成長），同樣受潛力上限限制。
static func add(wolf: Wolf, stat: String, amount: float) -> float:
	return _add(wolf, stat, amount)

static func _add(wolf: Wolf, stat: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var value: float = get_stat(wolf, stat)
	var cap: float = cap_of(wolf, stat)
	if wolf.potential.has(stat):
		var near: float = float(cfg().get("approach_range", 10.0))
		amount *= clamp((cap - value) / near, 0.0, 1.0)
	var new_value: float = min(cap, value + amount)
	var gained: float = max(0.0, new_value - value)
	wolf.set(stat, value + gained)
	return gained

static func cap_of(wolf: Wolf, stat: String) -> float:
	if wolf.potential.has(stat):
		return float(wolf.potential[stat])
	return float(cfg().get("potential", {}).get("max", {}).get(stat, GameData.balance.get("stat_max", 100)))

# 技巧、感知的當下成長。units：成功 1、失敗 fail_mult（再依連續失敗遞減）。
static func learn(wolf: Wolf, stat: String, units: float) -> float:
	var base: float = float(cfg().get("learn_per_unit", {}).get(stat, 0.0))
	return _add(wolf, stat, base * units * stage_mult(wolf, stat))

# 固定份量的當下成長（探索、追蹤、遠距觀察、採集的感知）：cfg_key 是 growth 裡的數值鍵。
static func learn_flat(wolf: Wolf, stat: String, cfg_key: String, units: float = 1.0) -> float:
	return _add(wolf, stat, float(cfg().get(cfg_key, 0.0)) * units * stage_mult(wolf, stat))

# 鍛鍊點：記在速度、力量、血量上限，睡覺時結算。同時有很少量的當下成長。
static func train(wolf: Wolf, stat: String, points: float) -> void:
	if points <= 0.0 or not BODY_STATS.has(stat):
		return
	wolf.training[stat] = float(wolf.training.get(stat, 0.0)) + points
	if stat != "health_max":
		_add(wolf, stat, points * float(cfg().get("immediate_body_per_point", 0.0)) * stage_mult(wolf, stat))

# 依活動種類分配鍛鍊點（training_points 的 kind：action／takedown／guard／gather／explore）。
# action、takedown、guard 記在指定能力，另外分一部分給血量上限；gather、explore 三項平均。
static func train_activity(wolf: Wolf, kind: String, stat: String = "", mult: float = 1.0) -> void:
	var tp: Dictionary = cfg().get("training_points", {})
	var points: float = float(tp.get(kind, 0.0)) * mult
	if stat == "":
		for s in BODY_STATS:
			train(wolf, s, points / BODY_STATS.size())
		return
	train(wolf, stat, points)
	train(wolf, "health_max", points * float(tp.get("health_share", 0.3)))

# 狩獵中每一步的練習（HuntSystem.practice）：技巧、感知當下成長；速度、力量累積鍛鍊點。
static func apply_practice(wolf: Wolf, practice: Array) -> void:
	var fail_mult: float = float(cfg().get("fail_mult", 0.25))
	var decay: float = float(cfg().get("fail_streak_decay", 0.5))
	for p in practice:
		var stat: String = str(p.get("stat", ""))
		var success: bool = bool(p.get("success", false))
		# 同一場狩獵裡同一項能力練超過 repeat_free 次，之後每次再遞減（避免一直閃避刷技巧）。
		var mult: float = float(p.get("mult", 1.0)) \
			* pow(float(cfg().get("repeat_decay", 0.7)), max(0, int(p.get("repeat", 0)) - int(cfg().get("repeat_free", 3)) + 1))
		var units: float = 1.0 if success else fail_mult * pow(decay, int(p.get("streak", 0)))
		if MIND_STATS.has(stat):
			learn(wolf, stat, units * mult)
		elif BODY_STATS.has(stat):
			# 鍛鍊點看實際出力：成功失敗都算滿，只有連續失敗遞減。
			train_activity(wolf, str(p.get("kind", "action")), stat, mult * pow(decay, int(p.get("streak", 0))))

# 飽食倍率：睡覺時的飽食度依折線內插；連續多天睡覺時飽食度都在門檻以上，再加成。
static func hunger_mult(hunger: float, fed_streak: int) -> float:
	var points: Array = cfg().get("hunger_mult", [[0, 0.0], [150, 1.0]])
	var mult: float = float(points[-1][1])
	for i in range(points.size() - 1):
		var a: Array = points[i]
		var b: Array = points[i + 1]
		if hunger <= float(b[0]):
			var t: float = clamp((hunger - float(a[0])) / max(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
			mult = lerp(float(a[1]), float(b[1]), t)
			break
	var fs: Dictionary = cfg().get("fed_streak", {})
	return mult * (1.0 + min(float(fs.get("max_bonus", 0.3)), fed_streak * float(fs.get("bonus_per_day", 0.05))))

# 睡覺結算：成長量 = 鍛鍊點 × 每點成長量 × 飽食倍率 × 生命階段倍率，然後鍛鍊點歸零。
# 回傳 {"gains": {stat: 成長量}, "points": 鍛鍊點合計, "hunger_mult": 倍率}。
static func settle_sleep(wolf: Wolf) -> Dictionary:
	var fs: Dictionary = cfg().get("fed_streak", {})
	if wolf.hunger >= float(fs.get("threshold", 100)):
		wolf.fed_streak += 1
	else:
		wolf.fed_streak = 0
	var mult: float = hunger_mult(wolf.hunger, max(0, wolf.fed_streak - 1))
	var per_point: Dictionary = cfg().get("stat_per_point", {})
	var reserve: float = float(cfg().get("season_reserve", 0.0))
	var gains: Dictionary = {}
	var total: float = 0.0
	for stat in BODY_STATS:
		var points: float = float(wolf.training.get(stat, 0.0))
		total += points
		var amount: float = points * float(per_point.get(stat, 0.02)) * mult * stage_mult(wolf, stat)
		# 一部分留到換季時發放（settle_season）
		wolf.season_reserve[stat] = float(wolf.season_reserve.get(stat, 0.0)) + amount * reserve
		var g: float = _add(wolf, stat, amount * (1.0 - reserve))
		if g > 0.0:
			gains[stat] = g
	wolf.training = {}
	wolf.clamp_stats()
	return {"gains": gains, "points": total, "hunger_mult": mult}

# 換季成長：這一季保留的成長 × 吃飽的天數比例（0～1），受潛力上限限制；沒拿到的部分不保留。回傳各項實際成長。
static func settle_season(wolf: Wolf, fed_ratio: float) -> Dictionary:
	var gains: Dictionary = {}
	for stat in BODY_STATS:
		var g: float = _add(wolf, stat, float(wolf.season_reserve.get(stat, 0.0)) * clamp(fed_ratio, 0.0, 1.0))
		if g > 0.0:
			gains[stat] = g
	wolf.season_reserve = {}
	wolf.clamp_stats()
	return gains

# 重大勝利的成長：只受上限限制，不套用「越接近上限長得越慢」（要讓玩家完整拿到）。回傳實際成長。
static func bonus(wolf: Wolf, stat: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var value: float = get_stat(wolf, stat)
	var gained: float = max(0.0, min(cap_of(wolf, stat), value + amount) - value)
	wolf.set(stat, value + gained)
	return gained

# 重大勝利提高潛力上限（成年後才有上限；次成年期上限是最高值，不用提高）。回傳實際提高的量。
static func raise_cap(wolf: Wolf, stat: String, amount: float) -> float:
	if not wolf.potential.has(stat) or amount <= 0.0:
		return 0.0
	var top: float = float(cfg().get("potential", {}).get("max", {}).get(stat, 100))
	var old: float = float(wolf.potential[stat])
	wolf.potential[stat] = min(top, old + amount)
	return float(wolf.potential[stat]) - old

# 潛力結算（進入成年時）：巔峰上限 = 基礎上限 + 次成年期累積成長 × growth_mult，再限制在最高值。
static func settle_potential(wolf: Wolf) -> Dictionary:
	var p: Dictionary = cfg().get("potential", {})
	var result: Dictionary = {}
	for stat in ALL_STATS:
		var growth: float = max(0.0, get_stat(wolf, stat) - float(wolf.start_stats.get(stat, get_stat(wolf, stat))))
		var cap: float = float(p.get("base_cap", {}).get(stat, 60)) + growth * float(p.get("growth_mult", 1.5))
		cap = min(cap, float(p.get("max", {}).get(stat, 100)))
		result[stat] = max(cap, get_stat(wolf, stat))
	wolf.potential = result
	return result

# 次成年期累積的成長（成年描述依這個挑「潛力最高的能力」）。
static func subadult_growth(wolf: Wolf) -> Dictionary:
	var g: Dictionary = {}
	for stat in ALL_STATS:
		var ref: float = get_stat(wolf, stat)
		if wolf.potential.has(stat):
			var p: Dictionary = cfg().get("potential", {})
			ref = float(p.get("base_cap", {}).get(stat, 60)) # 由上限反推：成長 = (上限 - 基礎上限) / growth_mult
			g[stat] = max(0.0, (float(wolf.potential[stat]) - ref) / float(p.get("growth_mult", 1.5)))
		else:
			g[stat] = max(0.0, ref - float(wolf.start_stats.get(stat, ref)))
	return g

# 老年每季衰退。
static func apply_elder_decay(wolf: Wolf) -> void:
	if wolf.life_stage() != Wolf.LifeStage.ELDER:
		return
	var decay: Dictionary = cfg().get("elder_decay_per_season", {})
	for stat in decay.keys():
		wolf.set(stat, get_stat(wolf, stat) - float(decay[stat]))
	wolf.clamp_stats()
