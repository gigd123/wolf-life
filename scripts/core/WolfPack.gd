class_name WolfPack
extends RefCounted

# 黑狼家族（SPEC Phase 3a「黑狼的一生」）：不逐隻模擬，只記一份狀態，每次換季更新一次。
# 帶頭的是具名 NPC（一開始是黑狼 stranger_wolf，換代後是牠的兒子）；伴侶與子女只記年齡。
# 數值在 balance.json 的 black_pack。

var stage: String = "solo" # solo（獨居）／pair（一對）／pack（狼群）／gone（解散或帶頭的死了沒人接手）
var regions: Array = [] # 牠們的領域，第一個是核心（帶頭的那隻的範圍）
var mate_age: float = -1.0 # 伴侶的年齡；沒有伴侶是 −1
var young: Array = [] # 子女的年齡（幼狼 < 1、年輕 1～2、成年 ≥ 2）
var generation: int = 1 # 第幾代帶頭的（1 = 黑狼）
var history: Array = [] # [{event, age（你的年齡）, size}]：一生模擬與一生回顧用
var heir_age: float = -1.0 # 換代那一季接手的子女的年齡（GameState 用來建立新的帶頭的）

static func cfg() -> Dictionary:
	return GameData.balance.get("black_pack", {})

func has_mate() -> bool:
	return mate_age >= 0.0

func pups() -> int:
	return young.filter(func(a): return float(a) < 1.0).size()

func adults_young() -> int:
	return young.filter(func(a): return float(a) >= float(cfg().get("heir_min_age", 2.0))).size()

# 數量：帶頭的（還活著）＋伴侶＋子女。
func size(leader_alive: bool) -> int:
	return (1 if leader_alive else 0) + (1 if has_mate() else 0) + young.size()

# 換季：ctx = {season, leader（NpcWolf，可能是 null 或死了）, player_age, beaten（你打贏過帶頭的）,
# den（你的巢穴）, own（你的標記還在的區域）, adjacent（區域 → 相鄰區域）}。回傳這一季發生的事件名稱。
func on_season_passed(ctx: Dictionary) -> Array:
	var c := cfg()
	var events: Array = []
	heir_age = -1.0
	if stage == "gone":
		return events
	var season: String = str(ctx.get("season", ""))
	var leader: NpcWolf = ctx.get("leader", null)
	var leader_alive: bool = leader != null and leader.alive
	# 年齡：子女、伴侶一起長大
	for i in young.size():
		young[i] = float(young[i]) + 0.25
	if has_mate():
		mate_age += 0.25
		var d: float = float(c.get("mate_death_per_season", 0.02))
		if mate_age >= float(c.get("mate_old_age", 8.0)):
			d = float(c.get("mate_old_death_per_season", 0.15))
		if RNGService.chance(d):
			mate_age = -1.0
			events.append("mate_died")
	# 幼狼第一年約一半活下來
	var survive: float = float(c.get("pup_survival_per_season", 0.84))
	var before: int = young.size()
	young = young.filter(func(a): return float(a) >= 1.0 or RNGService.chance(survive))
	if young.size() < before:
		events.append("pups_lost")
	# 秋冬：年輕的、成年的子女可能離群
	var leave: float = float(c.get("disperse_per_season", {}).get(season, 0.0))
	if leave > 0.0:
		before = young.size()
		young = young.filter(func(a): return float(a) < 1.0 or not RNGService.chance(leave))
		if young.size() < before:
			events.append("young_left")
	# 帶頭的死了：有伴侶和成年子女就由子女接手（換代），否則解散
	if not leader_alive and stage != "gone":
		if has_mate() and adults_young() > 0:
			heir_age = _remove_oldest_adult()
			generation += 1
			events.append("succession")
		else:
			stage = "gone"
			regions = []
			events.append("dissolved")
			return _log(events, ctx)
	# 獨居時，領域跟著牠的範圍
	if stage == "solo" and leader_alive:
		regions = [leader.territory] if leader.territory != "" else []
	# 成家：你打贏牠之後，或你滿 pair_min_player_age 歲之後；牠還沒老
	if stage == "solo" and leader_alive and leader.life_stage_key() != "elder" \
			and (bool(ctx.get("beaten", false)) or float(ctx.get("player_age", 0.0)) >= float(c.get("pair_min_player_age", 2.5))):
		var chance: float = float(c.get("pair_chance", 0.3)) * float(c.get("pair_season_mult", {}).get(season, 1.0))
		if RNGService.chance(chance):
			var r: Array = c.get("mate_age", [2.0, 3.0])
			mate_age = snapped(RNGService.randf_range(float(r[0]), float(r[1])), 0.25)
			stage = "pair"
			events.append("paired")
	# 換代後新的帶頭的沒有伴侶：之後再找（同成家的機會）
	elif stage != "solo" and not has_mate() and leader_alive and RNGService.chance(float(c.get("pair_chance", 0.3)) * float(c.get("pair_season_mult", {}).get(season, 1.0))):
		var r2: Array = c.get("mate_age", [2.0, 3.0])
		mate_age = snapped(RNGService.randf_range(float(r2[0]), float(r2[1])), 0.25)
		events.append("paired")
	# 春季生幼狼
	if season == "spring" and stage in ["pair", "pack"] and has_mate() and RNGService.chance(float(c.get("pup_chance", 0.8))):
		var litter: Array = c.get("litter", [3, 5])
		var n: int = RNGService.randi_range(int(litter[0]), int(litter[1]))
		n = min(n, int(c.get("max_size", 10)) - size(leader_alive))
		for i in max(0, n):
			young.append(0.0)
		if n > 0:
			stage = "pack"
			events.append("pups")
	# 一對以下又沒子女：回到一對
	if stage == "pack" and young.is_empty():
		stage = "pair" if has_mate() else "solo"
	# 秋季擴張：數量夠多時，往相鄰、沒人守的一區
	if season == "autumn" and stage == "pack" and size(leader_alive) >= int(c.get("expand_min_size", 5)) \
			and regions.size() < int(c.get("max_regions", 2)) and RNGService.chance(float(c.get("expand_chance", 0.5))):
		var target: String = _expand_target(ctx)
		if target != "":
			regions.append(target)
			events.append("expanded")
	return _log(events, ctx)

func _remove_oldest_adult() -> float:
	var oldest := -1
	for i in young.size():
		if float(young[i]) >= float(cfg().get("heir_min_age", 2.0)) and (oldest < 0 or float(young[i]) > float(young[oldest])):
			oldest = i
	if oldest < 0:
		return -1.0
	var age: float = float(young[oldest])
	young.remove_at(oldest)
	return age

# 擴張的目標：和牠們的領域相鄰，不是你的巢穴；優先你的標記已經淡掉的區域。
func _expand_target(ctx: Dictionary) -> String:
	var adjacent: Dictionary = ctx.get("adjacent", {})
	var own: Array = ctx.get("own", [])
	var den: String = str(ctx.get("den", ""))
	var free: Array = []
	var marked: Array = []
	for r in regions:
		for a in adjacent.get(r, []):
			if regions.has(a) or a == den or free.has(a) or marked.has(a):
				continue
			if own.has(a):
				marked.append(a)
			else:
				free.append(a)
	var pool: Array = free if not free.is_empty() else marked
	return str(pool[RNGService.randi_range(0, pool.size() - 1)]) if not pool.is_empty() else ""

func _log(events: Array, ctx: Dictionary) -> Array:
	var leader: NpcWolf = ctx.get("leader", null)
	for e in events:
		history.append({"event": e, "age": snapped(float(ctx.get("player_age", 0.0)), 0.25), "size": size(leader != null and leader.alive)})
	return events

func to_dict() -> Dictionary:
	return {"stage": stage, "regions": regions, "mate_age": mate_age, "young": young, "generation": generation, "history": history}

static func from_dict(data: Dictionary) -> WolfPack:
	var p := WolfPack.new()
	p.stage = str(data.get("stage", "solo"))
	p.regions = data.get("regions", [])
	p.mate_age = float(data.get("mate_age", -1.0))
	p.young = data.get("young", [])
	p.generation = int(data.get("generation", 1))
	p.history = data.get("history", [])
	return p
