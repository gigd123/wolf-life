extends Node

# Orchestrates a single life: owns the Wolf, the current/den region, and the
# life-review log, and is the only thing UI code is allowed to mutate game
# state through. Autosaves on new day and after sleeping, per DESIGN.md.

signal state_changed
signal log_message(text: String)
signal wolf_died(cause: String)
signal encounter_triggered(data: Dictionary)
signal growth_applied
signal knowledge_learned(entry: Dictionary)

var wolf: Wolf
var den_region: String = ""
var current_region: String = ""
# 找到過的普通睡處：{region_id: "normal"}。離開再回來還在（好睡處記在區域知識）；大火燒過的區域會失效。
# 未來（Phase 2）睡處可能因環境變化或其他動物入侵而變差、失去。
var found_sleep_spots: Dictionary = {}
var rng_seed: int = 0
# 區域資源消耗：{region_id: {animal_id: 出現率倍率}}，沒有紀錄就是 1。
var region_depletion: Dictionary = {}
# 全域風向（0～3，風從哪個方位吹來）。不做羅盤，遭遇時換算成逆風／側風／順風。
var wind_dir: int = 0
# 區域知識：{region_id: {"visited": bool, "features": [已發現的次要特徵]}}。
# 開局只認得巢穴所在區域的樣貌；第一次進入其他區域時揭露主要地形。
var region_knowledge: Dictionary = {}
# 目前探索到、還沒處理的發現（見 ExploreSystem）。
var current_discovery: Dictionary = {}
# 分段進食：目前正在吃的獵物 {animal_id, life_stage, segments_left, segment_value, turns_stayed, terrain}。
var current_feeding: Dictionary = {}
# 這隻狼的知識（SPEC「知識系統」）：{key: {"type", ...參數, "count"}}，count 1／2／3 = 似乎／通常／確定。
# type：prey（獵物出沒：animal, region, period）、danger（危險：animal, region, season）、
# weakness（獵物弱點：animal, life_stage, option）、overhunt（過度狩獵：animal, region）。
var knowledge: Dictionary = {}
# 已辨識的線索來源（白尾鹿、野兔、狐狸一開始就認得；灰熊、陌生灰狼要親眼見過）。
var identified: Array = []
# --- 主動事件（SPEC「主動事件」）---
# 事件先放進佇列，畫面層在目前的行動結束後依序處理（避免在狩獵途中被打斷）。
var pending_events: Array = []
var events_today: int = 0
# 陌生灰狼的範圍（開新狼時決定）；在範圍內連續停留的時段數。
var stranger_territory: String = ""
var territory_periods: int = 0
# 具名 NPC 狼（SPEC 1.6「陌生灰狼」）：{id: NpcWolf}。陌生灰狼的範圍同步在 stranger_territory（牠死了就是空字串）。
var npcs: Dictionary = {}
# 森林大火（SPEC 1.6「森林大火」）：fire 是進行中的大火 {origin, phase: "warning"|"burning", ignite_at, noticed,
# regions: {region_id: 起火的絕對時段}, burned: [燒完的區域], alerted: 已經提示過「火燒到這裡」的區域, sheltered: 躲在溪邊或巢穴的區域}。
# region_burn：燒過的區域 {region_id: 燒完那天的 days_lived}，決定焦黑與草木新生。fire_at：排定的起火時段（-1 = 沒有）。
var fire: Dictionary = {}
# 換季睡眠的那幾回合：暫停隨機的世界事件（_on_period_changed）
var quiet_sleep: bool = false
var region_burn: Dictionary = {}
var fire_at: int = -1
# 排到秋季的大火：秋季開始時才排定時段（"" = 沒有）
var fire_season: String = ""
var last_fire_abs: int = -100000
# 苔原的暴風雪（1.6 第 6d 步）：blizzard 是進行中的風雪 {phase: "warning"|"active", start_at, end_at, days, noticed,
# alerted: 已經提示過的區域, shelter: "dig"|"den"|"", shelter_region, in_tundra, choice, result}。blizzard_at：排定的時段（-1 = 沒有）。
var blizzard: Dictionary = {}
var blizzard_at: int = -1
# 白矇天：結束的絕對時段（-1 = 沒有），只在 events.json whiteout.regions 的區域有效。
var whiteout_until: int = -1
# 跟著渡鴉移動時不另外寫「你移動到了…」（發現殘骸的句子會交代來到哪裡）
var _quiet_move_log: bool = false
# 天氣："clear"、"storm"（暴雨）、"after_rain"（雨停後）；weather_until 是結束的絕對時段編號。
var weather: String = "clear"
var weather_until: int = -1
# 避開灰熊線索：{region_id, until}，until 是絕對時段編號（見 _abs_period），期間該區域的灰熊遭遇機率降低。
var avoid_bear: Dictionary = {}
# 吃不完留下的殘骸：[{region_id, terrain, animal_id, life_stage, segments_left, segment_value, day}]，最多留 2 天。
var carcasses: Array = []

var life_log: Dictionary = {}
# 自動遊玩（除錯「模擬到死亡」）期間不產生提示卡片。
var auto_playing: bool = false

func new_game(start_den: String) -> void:
	RNGService.randomize_seed()
	rng_seed = RNGService.get_seed()
	wolf = Wolf.new()
	den_region = start_den
	current_region = start_den
	found_sleep_spots = {}
	region_depletion = {}
	wind_dir = RNGService.randi_range(0, 3)
	region_knowledge = {start_den: {"visited": true, "features": []}}
	current_discovery = {}
	current_feeding = {}
	carcasses = []
	knowledge = {}
	identified = GameData.knowledge.get("identified_at_start", []).duplicate()
	avoid_bear = {}
	pending_events = []
	events_today = 0
	territory_periods = 0
	weather = "clear"
	weather_until = -1
	var territory_weights: Dictionary = GameData.discovery.get("threat_sources", {}).get("stranger_wolf", {}).get("region_weights", {})
	stranger_territory = RNGService.weighted_pick(territory_weights) if not territory_weights.is_empty() else ""
	npcs = {"stranger_wolf": NpcWolf.create("stranger_wolf", stranger_territory)}
	fire = {}
	region_burn = {}
	fire_at = -1
	fire_season = ""
	last_fire_abs = -100000
	blizzard = {}
	blizzard_at = -1
	whiteout_until = -1
	npcs["wolverine"] = NpcWolf.create("wolverine", "")
	for id in TUNDRA_WOLF_IDS:
		npcs[id] = NpcWolf.create(id, "")
	life_log = {
		"regions_visited": [start_den],
		"prey_count": {},
		"biggest_prey": "",
		"biggest_prey_stage": "",
		"days_lived": 1,
		"death_cause": "",
	}
	# 第一次可以和陌生灰狼直接互動的時機：50% 在次成年期、50% 在成年後（都要先遠距觀察過）
	life_log["stranger_unlock"] = "subadult" if RNGService.chance(float(_stranger_cfg().get("unlock_subadult_chance", 0.5))) else "adult"
	var start_season: String = GameData.balance.get("start_season", "winter")
	GameTime.setup(start_season, "normal")
	_connect_time_signals()
	_maybe_schedule_blizzard()
	_roam_tundra_wolves(true)
	_snapshot_sleep_stats()
	_start_season_review()
	_queue_season_card()
	SaveSystem.save_game()
	state_changed.emit()

func _connect_time_signals() -> void:
	if not GameTime.period_changed.is_connected(_on_period_changed):
		GameTime.period_changed.connect(_on_period_changed)
	if not GameTime.day_changed.is_connected(_on_day_changed):
		GameTime.day_changed.connect(_on_day_changed)
	if not GameTime.season_changed.is_connected(_on_season_changed):
		GameTime.season_changed.connect(_on_season_changed)

func _on_period_changed(_period_index: int) -> void:
	if wolf == null or not wolf.alive:
		return
	var balance: Dictionary = GameData.balance
	wolf.hunger -= float(balance.get("hunger_decay_per_period", 4))
	var cold := cold_cost()
	wolf.hunger -= float(cold["hunger"])
	wolf.stamina -= float(cold["stamina"])
	wolf.clamp_stats()
	_decay_carcasses()
	# 換季睡眠期間暫停隨機的世界事件（SPEC「季節轉換」）；大火、暴風雪進行中不會是換季睡眠
	if not quiet_sleep:
		_update_weather()
		_maybe_howl()
		_update_territory()
		_update_fire()
		_update_tundra_events()
	# 平常每個時段 15% 機率轉變；暴雨時每回合都可能改變（暴雨尚未實作）。
	if RNGService.chance(float(balance.get("wind_change_chance_per_period", 0.15))):
		wind_dir = posmod(wind_dir + (1 if RNGService.chance(0.5) else -1), 4)
	_check_death()

func _on_day_changed(_day: int) -> void:
	life_log["days_lived"] = int(life_log.get("days_lived", 0)) + 1
	_count_season_day()
	events_today = 0
	var before_injury: int = wolf.injury if wolf != null else Wolf.Injury.NONE
	var before_injury_stat: String = wolf.injury_stat if wolf != null else ""
	var before_poison: int = wolf.poison_days_remaining if wolf != null else 0
	_process_daily_recovery()
	_apply_daily_hunger_penalty()
	_queue_day_summary(before_injury, before_injury_stat, before_poison)
	_recover_region_depletion()
	_heal_npcs()
	_roam_tundra_wolves()
	_maybe_elder_death_check()
	SaveSystem.save_game()

# --- 換季（SPEC 1.6「季節轉換」）：天數到了只記為到期，下一次睡覺時才換 ---

# 大火或暴風雪進行中（含徵兆）不換季，等事件結束後的下一覺。
func season_change_blocked() -> bool:
	return not fire.is_empty() or not blizzard.is_empty()

func _change_season() -> void:
	GameTime.change_season()

# 到期後滿一天還沒睡：短暫休息、「休息到…」也會換季（被事件打斷的那次不換）。
func _maybe_rest_season_change() -> void:
	if wolf.alive and GameTime.days_overdue() >= 2 and not season_change_blocked():
		_change_season()

# 換季的結算順序（SPEC「季節轉換」）：季節狀態、年齡、NPC、排定這一季的事件 → 老年衰退 → 成年、老年轉變 → 換季字卡。
# 卡片依排入的順序顯示，所以轉變卡片在前、換季字卡最後，關掉後回到已更新的主畫面。
func _on_season_changed(_season_index: int) -> void:
	if wolf != null:
		var prev_stage: int = wolf.life_stage()
		wolf.age_years += 0.25
		_age_npcs()
		_maybe_schedule_fire()
		_maybe_schedule_blizzard()
		_roam_tundra_wolves(true)
		var fed_ratio: float = _season_fed_ratio()
		Growth.settle_season(wolf, fed_ratio)
		_apply_elder_decay()
		_check_life_stage_transition(prev_stage)
		var review: Dictionary = _season_review(fed_ratio)
		_start_season_review()
		log_message.emit(tr("log.season_changed"))
		_queue_season_card(review)

# 這一季的成長回顧（SPEC「季節轉換」）：換季時和季初的能力比較，加上吃飽的天數比例。
func _start_season_review() -> void:
	var snap: Dictionary = {}
	for stat in SLEEP_SUMMARY_STATS:
		snap[stat] = float(wolf.get(stat))
	life_log["season_snapshot"] = snap
	life_log["season_days"] = 0
	life_log["season_fed_days"] = 0

# 換日時記一天；飽食度夠高算吃飽的一天。
func _count_season_day() -> void:
	if wolf == null:
		return
	life_log["season_days"] = int(life_log.get("season_days", 0)) + 1
	if wolf.hunger >= float(Growth.cfg().get("season_fed_hunger", 60)):
		life_log["season_fed_days"] = int(life_log.get("season_fed_days", 0)) + 1

func _season_fed_ratio() -> float:
	var days: int = int(life_log.get("season_days", 0))
	if days <= 0:
		return 1.0 if wolf.hunger >= float(Growth.cfg().get("season_fed_hunger", 60)) else 0.0
	return float(life_log.get("season_fed_days", 0)) / float(days)

# 回傳 {"changes": {能力: 變化量}, "fed_ratio"}；舊存檔沒有季初紀錄時回傳空的（字卡不寫回顧）。
func _season_review(fed_ratio: float) -> Dictionary:
	var snap: Dictionary = life_log.get("season_snapshot", {})
	if snap.is_empty():
		return {}
	var changes: Dictionary = {}
	for stat in SLEEP_SUMMARY_STATS:
		if snap.has(stat):
			changes[stat] = float(wolf.get(stat)) - float(snap[stat])
	return {"changes": changes, "fed_ratio": fed_ratio}

# --- 轉變與回饋提示（SPEC 1.6「轉變與回饋提示」）---
# 提示放進 pending_events，畫面層在目前的行動結束後依序顯示；不佔每天的事件上限。

func _queue_notice(event: Dictionary) -> void:
	if auto_playing or wolf == null or not wolf.alive:
		return
	pending_events.append(event)

# 季節卡片：第一次經歷某個季節顯示完整描述，之後顯示精簡版；變化依這隻狼的辨識與知識決定。
# 人在苔原時用苔原的卡片（notices.json 的 season_cards_by_map），第一次與否分開記（seasons_seen 的 "tundra:winter"）。
func _queue_season_card(review: Dictionary = {}) -> void:
	var season: String = GameTime.current_season()
	var map_cards: Dictionary = GameData.notices.get("season_cards_by_map", {}).get(current_map(), {})
	var seen_key: String = season if map_cards.is_empty() else current_map() + ":" + season
	var seen: Array = life_log.get("seasons_seen", [])
	var first: bool = not seen.has(seen_key)
	if first:
		seen.append(seen_key)
		life_log["seasons_seen"] = seen
	var lines: Array = []
	var cards: Array = map_cards.get(season, []) if not map_cards.is_empty() else GameData.notices.get("season_cards", {}).get(season, [])
	for line in cards:
		if line.has("full"):
			lines.append({"key": str(line["full"] if first else line["short"])})
		elif _notice_condition(str(line.get("if", ""))):
			lines.append({"key": str(line["text"]), "region": _sensed_region(str(line.get("animal", "")))})
	_queue_notice({"type": "season_card", "season": season, "first": first, "lines": lines, "map": current_map(), "region": current_region, "review": review})

# 第一次在這個季節來到有自己季節卡片的地圖（苔原）：補一張卡片。
func _maybe_map_season_card() -> void:
	if GameData.notices.get("season_cards_by_map", {}).get(current_map(), {}).is_empty():
		return
	if life_log.get("seasons_seen", []).has(current_map() + ":" + GameTime.current_season()):
		return
	_queue_season_card()

func _notice_condition(cond: String) -> bool:
	var parts: PackedStringArray = cond.split(":")
	if parts.size() != 2:
		return cond == ""
	match parts[0]:
		"identified": return is_identified(parts[1])
		"seen": return not life_log.get(parts[1], []).is_empty()
		"sensed": return not is_identified(parts[1]) and _sensed_region(parts[1]) != ""
	return false

# 還沒辨識、但已經在某個區域察覺過的危險來源（記得最清楚的那一區）。
func _sensed_region(animal_id: String) -> String:
	var best: String = ""
	var best_count: int = 0
	for entry in knowledge.values():
		if entry.get("type", "") == "danger" and entry.get("animal", "") == animal_id and int(entry.get("count", 0)) > best_count:
			best = str(entry["region"])
			best_count = int(entry["count"])
	return best

# 飢餓懲罰的段數：0 無、1 輕度（低於 30）、2 重度（低於 10）。
func hunger_tier() -> int:
	var p: Dictionary = GameData.balance.get("hunger_penalties", {})
	if wolf.hunger < float(p.get("severe_threshold", 10)):
		return 2
	if wolf.hunger < float(p.get("low_threshold", 30)):
		return 1
	return 0

# 換日摘要：飢餓懲罰生效或解除、傷勢與中毒痊癒時才顯示（舊傷在第 3 步加入）。
func _queue_day_summary(before_injury: int, before_injury_stat: String, before_poison: int) -> void:
	if wolf == null or not wolf.alive:
		return
	var cfg: Dictionary = GameData.notices.get("day_summary", {})
	var lines: Array = []
	var tier: int = hunger_tier()
	var last_tier: int = int(life_log.get("hunger_tier", 0))
	if tier != last_tier:
		lines.append({"key": str(cfg.get("hunger_tier_%d" % tier, ""))})
		life_log["hunger_tier"] = tier
	var old_formed: bool = _day_events.any(func(e): return e.get("replaces_heal", false))
	if before_injury != Wolf.Injury.NONE and wolf.injury == Wolf.Injury.NONE and not old_formed:
		if before_injury == Wolf.Injury.HEAVY:
			lines.append({"key": str(cfg.get("heavy_healed_" + before_injury_stat, cfg.get("heavy_healed", "")))})
		else:
			lines.append({"key": str(cfg.get("light_healed", ""))})
	if before_poison > 0 and wolf.poison_days_remaining <= 0:
		lines.append({"key": str(cfg.get("poison_healed", ""))})
	lines.append_array(_day_events)
	_day_events = []
	if not lines.is_empty():
		_queue_notice({"type": "day_summary", "lines": lines, "day": int(life_log.get("days_lived", 1))})

# 睡覺結算：記下這次睡覺時的能力值，下次睡覺時比較。
const SLEEP_SUMMARY_STATS := ["speed", "strength", "health_max", "skill", "perception"]

func _snapshot_sleep_stats() -> void:
	var snap: Dictionary = {}
	for stat in SLEEP_SUMMARY_STATS:
		snap[stat] = float(wolf.get(stat))
	life_log["sleep_snapshot"] = snap
	life_log["since_sleep"] = {}

# 上次睡覺到現在提升的能力，以及速度或力量提升時的原因句（依飽食度與活動組合）。
# settle 是 Growth.settle_sleep 的結果：鍛鍊了不少、卻因為太餓幾乎沒長時，也給一句原因。
func sleep_summary(settle: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = GameData.notices.get("sleep_summary", {})
	var snap: Dictionary = life_log.get("sleep_snapshot", {})
	var gains: Array = []
	var amounts: Dictionary = {}
	for stat in SLEEP_SUMMARY_STATS:
		if snap.has(stat) and float(wolf.get(stat)) > float(snap[stat]) + float(cfg.get("min_gain", 0.05)):
			gains.append(stat)
			amounts[stat] = float(wolf.get(stat)) - float(snap[stat])
	var reason: String = ""
	if float(settle.get("points", 0.0)) >= float(cfg.get("starved_points", 15)) \
			and float(settle.get("hunger_mult", 1.0)) < float(cfg.get("starved_mult", 0.3)):
		reason = str(cfg.get("reasons", {}).get("starved", ""))
		# 太餓時身體只長了一點點，不標 ▲，免得和原因句矛盾。
		gains = gains.filter(func(stat): return not Growth.BODY_STATS.has(stat))
	elif gains.has("speed") or gains.has("strength"):
		var since: Dictionary = life_log.get("since_sleep", {})
		var fed: String = "hungry" if hunger_tier() > 0 else ("full" if wolf.hunger >= float(cfg.get("full_hunger", 70)) else "ok")
		var activity: String = "chase" if int(since.get("chase", 0)) >= int(since.get("fight", 0)) else "fight"
		if not gains.has("speed"):
			activity = "fight"
		elif not gains.has("strength"):
			activity = "chase"
		reason = str(cfg.get("reasons", {}).get(fed + "." + activity, ""))
	# 什麼都沒長、也沒有挨餓的原因時，說明為什麼（QA-47）
	if gains.is_empty() and reason == "":
		var none: Dictionary = cfg.get("none_reasons", {})
		var at_peak: bool = not wolf.potential.is_empty() and Growth.BODY_STATS.all(
			func(stat): return Growth.cap_of(wolf, stat) - float(wolf.get(stat)) < float(cfg.get("peak_margin", 2.0)))
		if wolf.life_stage() == Wolf.LifeStage.ELDER:
			reason = str(none.get("elder", ""))
		elif float(settle.get("points", 0.0)) < float(cfg.get("idle_points", 4)):
			reason = str(none.get("idle", ""))
		elif at_peak:
			reason = str(none.get("peak", ""))
		else:
			reason = str(none.get("small", ""))
	return {"gains": gains, "amounts": amounts, "reason": reason}

func _apply_elder_decay() -> void:
	Growth.apply_elder_decay(wolf)

# 生命階段轉變（SPEC 1.6「潛力與生命階段轉變」）：年齡改變後呼叫。
# 進入成年時結算潛力並顯示成年卡片；進入老年時顯示老年卡片。
func _check_life_stage_transition(prev_stage: int) -> void:
	if wolf == null:
		return
	var stage: int = wolf.life_stage()
	if prev_stage == Wolf.LifeStage.SUBADULT and stage != Wolf.LifeStage.SUBADULT:
		_settle_adulthood()
	if prev_stage != Wolf.LifeStage.ELDER and stage == Wolf.LifeStage.ELDER:
		life_log["elder_age"] = snapped(wolf.age_years, 0.01)
		_queue_notice({"type": "elder_transition"})

func _settle_adulthood() -> void:
	var potential := Growth.settle_potential(wolf)
	life_log["potential"] = potential.duplicate()
	# 成年的那一刻，身體再長一次（SPEC「成年轉變」），寫在成年卡片上
	var bonus: Dictionary = {}
	var table: Dictionary = GameData.balance.get("growth", {}).get("adult_bonus", {})
	for stat in table.keys():
		var g: float = Growth.add(wolf, str(stat), float(table[stat]))
		if g > 0.0:
			bonus[stat] = g
	life_log["adult_bonus"] = bonus
	wolf.clamp_stats()
	life_log["adult_body"] = adult_body_key()
	_queue_notice({"type": "adult_transition"})

# 成年描述：依次成年期成長最突出的能力（成長 ÷ 一般玩法的成長）與主要狩獵傾向，從 notices.json 的 adult_transition.rules 挑第一條符合的。
func adult_body_key() -> String:
	var growth := Growth.subadult_growth(wolf)
	var ref: Dictionary = Growth.cfg().get("potential", {}).get("reference_growth", {})
	var top: String = ""
	var top_score: float = -1.0
	for stat in Growth.ALL_STATS:
		var score: float = float(growth.get(stat, 0.0)) / max(0.1, float(ref.get(stat, 1.0)))
		if score > top_score:
			top = stat
			top_score = score
	var tendency: String = str(current_tendency().get("type", ""))
	for rule in GameData.notices.get("adult_transition", {}).get("rules", []):
		if rule.has("stat") and str(rule["stat"]) != top:
			continue
		if rule.has("tendency") and str(rule["tendency"]) != tendency:
			continue
		return str(rule.get("key", ""))
	return ""

func _process_daily_recovery() -> void:
	if wolf == null:
		return
	_day_events = []
	if wolf.poison_days_remaining > 0:
		wolf.poison_days_remaining -= 1
		wolf.health_value -= float(GameData.balance.get("poison_health_value_loss_per_day", 1))
	if wolf.injury_days_remaining > 0:
		wolf.injury_days_remaining -= 1
		if wolf.injury_days_remaining <= 0:
			if wolf.injury == Wolf.Injury.HEAVY:
				_maybe_old_injury()
			wolf.clear_injury()
	_update_old_injury_flare()
	wolf.clamp_stats()
	_check_death()

# 換日摘要要顯示的舊傷變化（_queue_day_summary 取用後清空）。
var _day_events: Array = []

# 重傷痊癒時有機率留下永久的舊傷（SPEC 1.6「傷勢與舊傷」），記下部位、來源與年齡。
func _maybe_old_injury() -> void:
	var c: Dictionary = GameData.balance.get("combat", {}).get("old_injury", {})
	if not RNGService.chance(float(c.get("chance", 0.35))):
		return
	var part: String = wolf.injury_part if wolf.injury_part != "" else "shoulder"
	var side: String = "" if part == "face" else ("left" if RNGService.chance(0.5) else "right")
	var record := {"part": part, "part_key": "injury_part.%s%s" % [part, ("." + side) if side != "" else ""],
		"stat": wolf.injury_stat, "source": wolf.injury_source, "age": snapped(wolf.age_years, 0.1)}
	# 同一個部位只留一個舊傷（記最早的那次）
	if wolf.old_injuries.any(func(o): return o.get("part_key", "") == record["part_key"]):
		return
	wolf.old_injuries.append(record)
	_day_events.append({"key": "day_summary.old_injury_new", "part": record["part_key"], "replaces_heal": true})

# 舊傷平常沒有影響；冬季或老年之後偶爾發作 1～2 天（對應能力 −10%）。
func _update_old_injury_flare() -> void:
	if wolf.old_injuries.is_empty():
		return
	if wolf.flare_index >= 0:
		wolf.flare_days -= 1
		if wolf.flare_days <= 0:
			_day_events.append({"key": "day_summary.old_injury_calm", "part": str(wolf.old_injuries[wolf.flare_index].get("part_key", ""))})
			wolf.flare_index = -1
		return
	var c: Dictionary = GameData.balance.get("combat", {}).get("old_injury", {})
	var chance_value: float = 0.0
	if GameTime.current_season() == "winter":
		chance_value += float(c.get("flare_chance_winter", 0.08))
	if wolf.life_stage() == Wolf.LifeStage.ELDER:
		chance_value += float(c.get("flare_chance_elder", 0.08))
	if chance_value > 0.0 and RNGService.chance(chance_value):
		wolf.flare_index = RNGService.randi_range(0, wolf.old_injuries.size() - 1)
		wolf.flare_days = RNGService.randi_range(int(c.get("flare_days_min", 1)), int(c.get("flare_days_max", 2)))
		_day_events.append({"key": "day_summary.old_injury_flare", "part": str(wolf.old_injuries[wolf.flare_index].get("part_key", ""))})

# 三段式飢餓懲罰，每天結算一次（以換日當下的飽食度判定）。段數累進：歸零時也算「低於 10」。
func _apply_daily_hunger_penalty() -> void:
	if wolf == null or not wolf.alive:
		return
	var p: Dictionary = GameData.balance.get("hunger_penalties", {})
	if wolf.hunger < float(p.get("severe_threshold", 10)):
		wolf.health_value -= float(p.get("severe_health_value_loss_per_day", 3))
		log_message.emit(tr("log.starving"))
	elif wolf.hunger < float(p.get("low_threshold", 30)):
		wolf.health_value -= float(p.get("low_health_value_loss_per_day", 1))
		log_message.emit(tr("log.hungry"))
	if wolf.hunger <= 0.0:
		wolf.health -= float(p.get("zero_health_loss_per_day", 10))
	wolf.clamp_stats()
	_check_death()

func _recover_region_depletion() -> void:
	var recovery: float = float(GameData.balance.get("region_depletion", {}).get("recovery_per_day", 0.05))
	for region_id in region_depletion.keys():
		var table: Dictionary = region_depletion[region_id]
		for animal_id in table.keys():
			table[animal_id] = min(1.0, float(table[animal_id]) + recovery)

func _deplete_region(region_id: String, animal_id: String) -> void:
	var cfg: Dictionary = GameData.balance.get("region_depletion", {})
	var table: Dictionary = region_depletion.get(region_id, {})
	var current: float = float(table.get(animal_id, 1.0))
	table[animal_id] = max(float(cfg.get("min_mult", 0.2)), current - float(cfg.get("per_hunt", 0.2)))
	region_depletion[region_id] = table
	# 狼自己造成的改變也是知識：資源掉到門檻以下時學到「連續狩獵，牠們會離開」。
	if current > float(GameData.knowledge.get("overhunt_threshold", 0.6)) and float(table[animal_id]) <= float(GameData.knowledge.get("overhunt_threshold", 0.6)):
		learn({"type": "overhunt", "animal": animal_id, "region": region_id})

# 短暫休息與快轉只能把體力回到上限 rest_stamina_cap，只有睡覺能回滿；已經超過上限就不變。
func _rest_stamina(amount: float) -> void:
	var cap: float = float(GameData.balance.get("rest_stamina_cap", 80))
	if wolf.stamina < cap:
		wolf.stamina = min(cap, wolf.stamina + amount)

func _maybe_elder_death_check() -> void:
	if wolf == null or wolf.life_stage() != Wolf.LifeStage.ELDER:
		return
	var balance: Dictionary = GameData.balance
	var base_chance: float = float(balance.get("elder_death_base_chance", 0.01))
	var age_factor: float = float(balance.get("elder_death_age_factor", 0.01))
	var hv_factor: float = float(balance.get("elder_death_health_value_factor", 0.0005))
	var ages: Dictionary = balance.get("life_stage_ages", {})
	var elder_start: float = float(ages.get("adult_end", 6.0))
	var age_over: float = max(0.0, wolf.age_years - elder_start)
	var chance_value: float = base_chance + age_over * age_factor - wolf.health_value * hv_factor
	chance_value = clamp(chance_value, 0.0, 0.5)
	if RNGService.chance(chance_value):
		_die("old_age")

func _check_death() -> void:
	if wolf != null and wolf.alive and wolf.health <= 0.0:
		_die("starvation" if wolf.hunger <= 0.0 else "injury")

# 戰死：記下對手與情境，一生回顧用（例如「為了守住獵物，死在灰熊掌下」）。
func die_in_combat(animal_id: String, life_stage: String, context: String) -> void:
	life_log["death_detail"] = {"animal": animal_id, "life_stage": life_stage, "context": context, "age": snapped(wolf.age_years, 0.1)}
	_die("combat")

func _die(cause: String) -> void:
	if wolf == null or not wolf.alive:
		return
	wolf.alive = false
	wolf.death_cause = cause
	life_log["death_cause"] = cause
	_write_playtest_log()
	SaveSystem.save_game()
	wolf_died.emit(cause)

# --- Player actions ---

func available_actions() -> Array[String]:
	var actions: Array[String] = ["explore", "find_sleep_spot", "short_rest", "rest_until", "sleep"]
	var region: Dictionary = EncounterSystem.region_data(current_region)
	if not region.get("gather_weights", {}).is_empty():
		actions.append("gather")
	if carcass_index_here() >= 0:
		actions.append("return_to_carcass")
	if can_make_den_here():
		actions.append("make_den")
	return actions

func current_map() -> String:
	return GameData.map_of(current_region)

func _link_to(target_region: String) -> Dictionary:
	for link in GameData.links_from(current_region):
		if link["to"] == target_region:
			return link
	return {}

# 嚴寒（苔原）：每個時段額外消耗飽食度與體力，依季節與區域的 cold_mult。回傳 {"hunger", "stamina"}。
func cold_cost(region_id: String = "") -> Dictionary:
	if region_id == "":
		region_id = current_region
	var table: Dictionary = GameData.maps().get(GameData.map_of(region_id), {}).get("cold", {}).get(GameTime.current_season(), {})
	var mult: float = float(EncounterSystem.region_data(region_id).get("cold_mult", 1.0))
	# 沙脊的巢穴：又深又乾燥，待在巢穴這一區時比較不冷
	if region_id == den_region:
		mult *= float(den_bonus().get("cold_mult", 1.0))
	# 暴風雪：沒躲的話消耗 ×3，挖雪洞照常，巢穴或沙脊減半
	if blizzard_active() and GameData.map_of(region_id) == _blizzard_map():
		var shelter: String = str(blizzard.get("shelter", "")) if blizzard.get("shelter_region", "") == region_id else ""
		mult *= float(_blizzard_cfg().get("cold_mult", {}).get(shelter if shelter != "" else "none", 1.0))
	return {"hunger": float(table.get("hunger", 0)) * mult, "stamina": float(table.get("stamina", 0)) * mult}

# 頂部的嚴寒圖示：苔原的冬季。
func is_freezing() -> bool:
	return GameTime.current_season() == "winter" and float(cold_cost()["stamina"]) > 0.0

func adjacent_regions() -> Array:
	var region: Dictionary = EncounterSystem.region_data(current_region)
	return region.get("adjacent", [])

# 冰面捷徑（regions.json maps.<map>.ice）：和冰原地圖接壤的跨地圖連接少 turns_saved 回合，加上地圖內的冰面直通路線。
# 只列出這一季能走的：[{to, turns, thin（冰薄）, break（河冰裂開的機率）}]。
func ice_shortcuts() -> Array:
	var list: Array = []
	var season: String = GameTime.current_season()
	for link in GameData.links_from(current_region):
		var ice := _map_ice(current_map())
		if ice.is_empty():
			ice = _map_ice(GameData.map_of(str(link["to"])))
		if ice.get("break_chance", {}).has(season):
			list.append(_ice_entry(str(link["to"]), max(1, int(link["turns"]) - int(ice.get("turns_saved", 1))), ice))
	for map_id in GameData.maps().keys():
		var ice := _map_ice(map_id)
		if not ice.get("break_chance", {}).has(season):
			continue
		for p in ice.get("paths", []):
			if str(p["from"]) == current_region:
				list.append(_ice_entry(str(p["to"]), int(p.get("turns", 1)), ice))
			elif str(p["to"]) == current_region:
				list.append(_ice_entry(str(p["from"]), int(p.get("turns", 1)), ice))
	return list

func _map_ice(map_id: String) -> Dictionary:
	return GameData.maps().get(map_id, {}).get("ice", {})

func _ice_entry(target: String, turns: int, ice: Dictionary) -> Dictionary:
	var chance_value: float = float(ice.get("break_chance", {}).get(GameTime.current_season(), 0.0))
	return {"to": target, "turns": turns, "thin": chance_value > 0.0, "break": chance_value}

func ice_shortcut(target_region: String) -> Dictionary:
	for e in ice_shortcuts():
		if e["to"] == target_region:
			return e
	return {}

# 走過冰厚或冰薄的冰面之後，捷徑按鈕才直接顯示「冰厚」「冰薄」；之前只能憑腳下的感覺判斷。
func ice_known(thin: bool) -> bool:
	return bool(life_log.get("ice_known", {}).get("thin" if thin else "solid", false))

func _learn_ice(thin: bool) -> void:
	var known: Dictionary = life_log.get("ice_known", {})
	known["thin" if thin else "solid"] = true
	life_log["ice_known"] = known

# via_ice：沿著結冰的河面走捷徑（回合較少，春季可能踩破河冰）。
func action_move(target_region: String, via_ice: bool = false) -> void:
	_record_action("move")
	var link := _link_to(target_region)
	var ice: Dictionary = ice_shortcut(target_region) if via_ice else {}
	if not adjacent_regions().has(target_region) and link.is_empty() and ice.is_empty():
		return
	# 白矇天：看不清方向，可能走到另一個相鄰區域
	var lost_from: String = ""
	if link.is_empty() and ice.is_empty() and whiteout_here() and RNGService.chance(float(_events_cfg().get("whiteout", {}).get("lost_chance", 0.3))):
		var others: Array = adjacent_regions().filter(func(r): return r != target_region and GameData.map_of(r) == current_map())
		if not others.is_empty():
			lost_from = target_region
			target_region = others[RNGService.randi_range(0, others.size() - 1)]
	var ice_check: bool = link.is_empty() and ice.is_empty() and (current_region == _ice_cfg().get("region", "") or target_region == _ice_cfg().get("region", ""))
	# 大火：離開躲著的溪邊或巢穴就不算躲著；走回還在燒的區域要再提示一次（QA-28）
	if not fire.is_empty():
		if str(fire.get("sheltered", "")) == current_region and target_region != current_region:
			fire["sheltered"] = ""
		fire["alerted"].erase(target_region)
	current_region = target_region
	# 跨地圖（例如森林北部 ↔ 苔原南部）：回合較多、額外消耗體力（SPEC 1.6「苔原」6a）
	if not link.is_empty():
		wolf.stamina -= float(link["stamina"]) * wolf.injury_stamina_mult()
		var maps_visited: Array = life_log.get("maps_visited", [GameData.map_of(den_region)])
		if not maps_visited.has(GameData.map_of(target_region)):
			maps_visited.append(GameData.map_of(target_region))
		life_log["maps_visited"] = maps_visited
	if not life_log["regions_visited"].has(target_region):
		life_log["regions_visited"].append(target_region)
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	var turns: int = int(link["turns"]) if not link.is_empty() else int(costs.get("move_region", 1))
	if not ice.is_empty():
		record_decision("move.ice_shortcut")
		turns = int(ice["turns"])
		_learn_ice(bool(ice["thin"]))
	GameTime.advance_turns(turns)
	if not _quiet_move_log:
		log_message.emit(tr("log.moved").replace("{region}", tr("region." + target_region)))
	if lost_from != "":
		log_message.emit(tr("log.whiteout_lost").replace("{target}", tr("region." + lost_from)).replace("{region}", tr("region." + target_region)))
	if not is_region_visited(target_region):
		var knowledge: Dictionary = region_knowledge.get(target_region, {"features": []})
		knowledge["visited"] = true
		region_knowledge[target_region] = knowledge
		var main: String = str(EncounterSystem.region_data(target_region).get("main_feature", ""))
		log_message.emit(tr("log.region_first_visit").replace("{region}", tr("region." + target_region))
			.replace("{main}", tr("region_main." + main)))
	_describe_burned_arrival(target_region)
	var terrain_cost: float = float(EncounterSystem.region_data(target_region).get("terrain_stamina_modifier", 0))
	wolf.stamina -= terrain_cost * wolf.injury_stamina_mult()
	wolf.clamp_stats()
	_check_death()
	if wolf.alive:
		var encounter := EncounterSystem.roll_competitor(current_region, GameTime.current_season())
		if encounter.get("encountered", false) and RNGService.chance(threat_mult()):
			encounter_triggered.emit(prepare_bear_encounter(encounter))
	_check_fire_here(true)
	_note_den_smell()
	if wolf.alive:
		_apply_env_perception()
		_check_blizzard_here()
		_maybe_map_season_card()
		if ice_check:
			_maybe_ice_break()
		elif not ice.is_empty() and RNGService.chance(float(ice["break"])):
			pending_events.append({"type": "ice_break", "shortcut": true})
	state_changed.emit()

# --- 探索（取代「尋找獵物蹤跡」） ---

func is_region_visited(region_id: String) -> bool:
	return bool(region_knowledge.get(region_id, {}).get("visited", false))

func known_features(region_id: String) -> Array:
	return region_knowledge.get(region_id, {}).get("features", [])

func _feature_known_here(flag: String) -> bool:
	var all_features: Dictionary = GameData.region_features()
	for f in known_features(current_region):
		if all_features.get(f, {}).has(flag):
			return true
	return false

func action_explore() -> Dictionary:
	_record_action("explore")
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("explore", 1)))
	if not wolf.alive:
		return {}
	Growth.train_activity(wolf, "explore")
	# 暴風雪中什麼都看不見，也不能狩獵
	if blizzard_here():
		current_discovery = {"kind": "nothing", "blizzard": true, "location": _random_terrain(current_region)}
		state_changed.emit()
		return current_discovery
	# 苔原狼：在牠們這陣子待的區域探索，有機會撞見牠們圍攻狼獾，或遇上牠們
	if _maybe_tundra_mob() or _maybe_meet_tundra_wolves():
		state_changed.emit()
		return current_discovery
	# 風雪後凍死的動物：還沒找到的屍體，探索時有機會發現
	var hidden := _hidden_carcass_here()
	if hidden >= 0 and RNGService.chance(float(_blizzard_cfg().get("winter_kill", {}).get("explore_find_chance", 0.5))):
		carcasses[hidden]["found"] = true
		current_discovery = {"kind": "carcass", "animal_id": carcasses[hidden]["animal_id"], "life_stage": carcasses[hidden]["life_stage"],
			"location": carcasses[hidden]["terrain"], "frozen": bool(carcasses[hidden].get("frozen", false))}
		state_changed.emit()
		return current_discovery
	current_discovery = ExploreSystem.generate({
		"region_id": current_region,
		"season": GameTime.current_season(),
		"period": GameTime.current_period(),
		"depletion": prey_mults(current_region),
		"burn": burn_state(current_region),
		"wind_dir": wind_dir,
		"known_features": known_features(current_region),
		"prey_knowledge": prey_knowledge_mults(current_region, GameTime.current_period()),
		"weather": weather,
		"stranger_territory": stranger_territory,
	})
	match current_discovery.get("kind", ""):
		"feature":
			var knowledge: Dictionary = region_knowledge.get(current_region, {"visited": true, "features": []})
			knowledge["features"].append(current_discovery["feature_id"])
			region_knowledge[current_region] = knowledge
		"clue":
			Growth.learn_flat(wolf, "perception", "explore_perception")
			# 新鮮線索與直接目擊自動累積「獵物出沒」知識；陳舊線索要玩家選「記下」。
			if current_discovery.get("source_kind", "") == "prey" and (current_discovery.get("fresh", false) or not current_discovery.get("fresh_known", true)):
				_learn_prey_sighting(current_discovery["source"])
	state_changed.emit()
	return current_discovery

func track_chance() -> Dictionary:
	return ExploreSystem.track_chance(current_discovery, wolf.effective_perception(), _track_knowledge_bonus(current_discovery), _track_weather_penalty())

# 暴雨中氣味被沖散、容易跟丟。
func _track_weather_penalty() -> float:
	return float(_storm_cfg().get("track_penalty", 0.2)) if weather == "storm" else 0.0

# 確定的獵物出沒知識帶來的追蹤加成。
func _track_knowledge_bonus(d: Dictionary) -> float:
	if d.get("source_kind", "") != "prey":
		return 0.0
	if is_confirmed({"type": "prey", "animal": d["source"], "region": current_region, "period": GameTime.current_period()}):
		return float(GameData.knowledge.get("prey_confirmed_track_bonus", 0.1))
	return 0.0

# 追蹤目前的線索：成功時回傳 {"success": true, "hunt": HuntSystem}，狩獵直接從潛近開始。
func action_track() -> Dictionary:
	var d: Dictionary = current_discovery
	current_discovery = {}
	if not ExploreSystem.can_track(d):
		return {"success": false}
	var info := ExploreSystem.track_chance(d, wolf.effective_perception(), _track_knowledge_bonus(d), _track_weather_penalty())
	GameTime.advance_turns(int(GameData.discovery.get("track", {}).get("turns", 1)))
	if not wolf.alive:
		return {"success": false}
	if not d.get("fresh", false):
		state_changed.emit()
		return {"success": false, "reason_key": "reason.stale"}
	# 追蹤是感知的練習：成功一份，失敗 fail_mult 份。
	var tracked: bool = RNGService.chance(float(info["chance"]))
	Growth.learn_flat(wolf, "perception", "track_perception", 1.0 if tracked else float(Growth.cfg().get("fail_mult", 0.25)))
	if d.get("source_kind", "") == "threat":
		# 追蹤灰熊或陌生灰狼的足跡：成功就遇上牠（辨識前一律是遠距目擊）。
		if not tracked:
			state_changed.emit()
			return {"success": false, "reason_key": ""}
		state_changed.emit()
		return {"success": true, "encounter": prepare_threat_sighting(d["source"], str(d.get("location", "")))}
	if not tracked:
		state_changed.emit()
		var worst := HuntSystem.main_negative_factor(info["factors"])
		var reason: String = "" if worst.is_empty() else "reason." + str(worst["key"]).trim_prefix("factor.").replace(".", "_")
		return {"success": false, "reason_key": reason}
	return {"success": true, "hunt": start_hunt(d["source"], d.get("life_stage", "adult"), int(d.get("prey_dir", -1)), true,
		str(d.get("location", "")), bool(d.get("injured", false)))}

# 直接目擊獵物：不用追蹤，直接進入狩獵（從潛近開始）。
func action_hunt_sighted() -> HuntSystem:
	var d: Dictionary = current_discovery
	current_discovery = {}
	return start_hunt(d["source"], d.get("life_stage", "adult"), int(d.get("prey_dir", -1)), false,
		str(d.get("location", "")), bool(d.get("injured", false)))

# 採集探索到的採集物。
func action_gather_discovered() -> String:
	var d: Dictionary = current_discovery
	current_discovery = {}
	if d.get("source_kind", "") != "gather":
		return ""
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("gather", 1)))
	if wolf.alive:
		_practice_gather()
		_apply_gather_effect(d["source"])
	state_changed.emit()
	return d["source"]

func clear_discovery() -> void:
	current_discovery = {}

# 記下陳舊線索。
func note_discovery() -> bool:
	var d: Dictionary = current_discovery
	current_discovery = {}
	match d.get("source_kind", ""):
		"prey":
			_learn_prey_sighting(d["source"])
		"threat":
			_learn_threat(d["source"])
		_:
			return false
	state_changed.emit()
	return true

# --- 灰熊與陌生灰狼（SPEC「世界探索與未知線索」、DESIGN.md「灰熊行為」） ---

func _bear_cfg() -> Dictionary:
	return GameData.balance.get("bear_encounter", {})

func _abs_period() -> int:
	return int(life_log.get("days_lived", 1)) * GameTime.PERIODS.size() + GameTime.period_index

# 避開灰熊線索：這個時段內，此區域的灰熊遭遇機率降低。
func action_avoid() -> void:
	record_decision("avoid")
	Growth.learn_flat(wolf, "perception", "avoid_perception")
	avoid_bear = {"region_id": current_region, "until": _abs_period()}
	current_discovery = {}
	state_changed.emit()

# 灰熊遭遇機率的倍率：避開線索（×0.3）、謹慎型（更早察覺危險）。
func threat_mult() -> float:
	var mult: float = 1.0 - tendency_effect("cautious")
	if avoid_bear.get("region_id", "") == current_region and int(avoid_bear.get("until", -1)) >= _abs_period():
		mult *= float(GameData.discovery.get("avoid_mult", 0.3))
	return mult

func _learn_threat(source: String) -> void:
	if source == "grizzly_bear":
		_learn_danger(source)
	else:
		learn({"type": "stranger", "animal": source, "region": current_region})

# 辨識前的灰熊遭遇一律是遠距目擊；辨識後依 DESIGN.md：春季可能是母熊帶幼熊，
# 對次成年與老年的狼有機率不示威、直接攻擊（立刻受傷，接著選戰鬥或逃跑）。
func prepare_bear_encounter(encounter: Dictionary) -> Dictionary:
	var e := encounter.duplicate()
	var animal_id: String = e.get("animal_id", "grizzly_bear")
	if not is_identified(animal_id):
		e["distant"] = true
		return e
	var cfg := _bear_cfg()
	if GameTime.current_season() == "spring" and e.get("life_stage", "adult") == "adult" \
			and RNGService.chance(float(cfg.get("mother_chance_spring", 0.4))):
		e["mother"] = true
	var direct: float = 0.0
	if wolf.life_stage() != Wolf.LifeStage.ADULT:
		direct = float(cfg.get("direct_attack_chance", 0.25))
	if e.get("mother", false):
		direct = max(direct, float(cfg.get("direct_attack_chance", 0.25))) * float(cfg.get("mother_direct_mult", 2.0))
	if RNGService.chance(direct):
		var dmg: float = float(RNGService.randi_range(int(cfg.get("direct_damage_min", 10)), int(cfg.get("direct_damage_max", 25))))
		var parts: Dictionary = FightRules.opponent_profile(animal_id, str(e.get("life_stage", "adult"))).get("parts", {})
		var hit := FightRules.hurt_wolf(wolf, dmg, parts, animal_id + ".encounter", false)
		e["direct"] = true
		e["damage"] = hit["damage"]
		state_changed.emit()
	return e

# 遠距目擊灰熊或陌生灰狼（追蹤線索、或目擊線索）。
func prepare_threat_sighting(source: String, location: String) -> Dictionary:
	if source == "stranger_wolf" and stranger_can_interact():
		return {"encountered": true, "animal_id": source, "life_stage": "adult", "stranger_meet": true, "location": location}
	if source == "grizzly_bear":
		var e := prepare_bear_encounter({"encountered": true, "animal_id": source, "life_stage": "adult"})
		e["location"] = location
		return e
	return {"encountered": true, "animal_id": source, "life_stage": "adult", "distant": true, "location": location}

# 遠距觀察：1 回合，建立辨識、累積知識與感知經驗。牠沒有發現狼，雙方沒有互動。
func action_observe_distant(encounter: Dictionary) -> void:
	GameTime.advance_turns(int(_bear_cfg().get("observe_turns", 1)))
	var animal_id: String = encounter.get("animal_id", "grizzly_bear")
	identify(animal_id)
	_learn_threat(animal_id)
	if animal_id == "stranger_wolf":
		life_log["stranger_observed"] = true
	Growth.learn_flat(wolf, "perception", "observe_distant_perception")
	state_changed.emit()

# 只是看見、沒有觀察就離開：灰熊也算見過（建立辨識），之後的遭遇才套用一般規則。
func leave_distant(encounter: Dictionary) -> void:
	var animal_id: String = encounter.get("animal_id", "grizzly_bear")
	if animal_id == "grizzly_bear":
		identify(animal_id)

# --- 知識系統 ---

static func knowledge_key(entry: Dictionary) -> String:
	match entry["type"]:
		"prey": return "prey|%s|%s|%s" % [entry["animal"], entry["region"], entry["period"]]
		"danger": return "danger|%s|%s|%s" % [entry["animal"], entry["region"], entry["season"]]
		"weakness": return "weakness|%s|%s|%s" % [entry["animal"], entry["life_stage"], entry["option"]]
		"overhunt": return "overhunt|%s|%s" % [entry["animal"], entry["region"]]
		"stranger": return "stranger|%s|%s" % [entry["animal"], entry["region"]]
		"territory": return "territory|%s|%s" % [entry["animal"], entry["region"]]
		"opponent": return "opponent|%s|%s" % [entry["animal"], entry["life_stage"]]
	return ""

# 累積一次。回傳新的次數。
func learn(entry: Dictionary) -> int:
	var key := knowledge_key(entry)
	if key == "":
		return 0
	var existing: Dictionary = knowledge.get(key, entry.duplicate())
	existing["count"] = int(existing.get("count", 0)) + 1
	knowledge[key] = existing
	if existing["count"] <= int(GameData.knowledge.get("confirm_count", 3)):
		knowledge_learned.emit(existing)
	return existing["count"]

func knowledge_level(entry: Dictionary) -> int:
	var count: int = int(knowledge.get(knowledge_key(entry), {}).get("count", 0))
	return min(count, int(GameData.knowledge.get("confirm_count", 3)))

func is_confirmed(entry: Dictionary) -> bool:
	return knowledge_level(entry) >= int(GameData.knowledge.get("confirm_count", 3))

func _learn_prey_sighting(animal_id: String) -> void:
	var entry := {"type": "prey", "animal": animal_id, "region": current_region, "period": GameTime.current_period()}
	# 一天最多累積 1 次（knowledge.json 的 prey_once_per_day）
	var today: int = int(life_log.get("days_lived", 1))
	var existing: Dictionary = knowledge.get(knowledge_key(entry), {})
	if bool(GameData.knowledge.get("prey_once_per_day", true)) and int(existing.get("last_day", -1)) == today:
		return
	learn(entry)
	knowledge[knowledge_key(entry)]["last_day"] = today

# 確定的獵物出沒知識：此時此地該獵物的出現權重倍率。
func prey_knowledge_mults(region_id: String, period: String) -> Dictionary:
	var mults: Dictionary = {}
	for animal_id in GameData.animals.keys():
		if is_confirmed({"type": "prey", "animal": animal_id, "region": region_id, "period": period}):
			mults[animal_id] = float(GameData.knowledge.get("prey_confirmed_weight_mult", 1.2))
	return mults

func is_identified(source: String) -> bool:
	return identified.has(source) or GameData.knowledge.get("identified_at_start", []).has(source)

# 親眼見過才辨識。辨識後同類線索與舊的知識紀錄一律改用已辨識的文字（文字在畫面層依 identified 決定）。
func identify(source: String) -> void:
	if not identified.has(source):
		identified.append(source)
		log_message.emit(tr("log.identified").replace("{animal}", tr("animal." + source)))

# 這一季在某區域是否知道有危險（例如灰熊出沒）。
func known_dangers(region_id: String, season: String) -> Array:
	var list: Array = []
	for entry in knowledge.values():
		if entry["type"] == "danger" and entry["region"] == region_id and entry["season"] == season:
			list.append(entry)
	return list

func _learn_danger(animal_id: String) -> void:
	learn({"type": "danger", "animal": animal_id, "region": current_region, "season": GameTime.current_season()})

# 獵物弱點：對某種獵物某個追擊選項的加成。
func weakness_bonuses(animal_id: String, life_stage: String) -> Dictionary:
	var bonuses: Dictionary = {}
	var per: float = float(GameData.knowledge.get("weakness_bonus_per_level", 0.04))
	for option in GameData.knowledge.get("weakness_options", []):
		var level := knowledge_level({"type": "weakness", "animal": animal_id, "life_stage": life_stage, "option": option})
		if level > 0:
			bonuses[option] = per * level
	return bonuses

func action_gather() -> Dictionary:
	_record_action("gather")
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("gather", 1)))
	if wolf.alive:
		_practice_gather()
	var result := EncounterSystem.gather(current_region, GameTime.current_season())
	if burn_state(current_region) in ["burning", "ash"]:
		result = {"found": false}
	if result.get("found", false):
		_apply_gather_effect(result["item_id"])
	state_changed.emit()
	return result

# 採集：少量感知，鍛鍊點三項平均。
func _practice_gather() -> void:
	Growth.learn_flat(wolf, "perception", "gather_perception")
	Growth.train_activity(wolf, "gather")

func _apply_gather_effect(item_id: String) -> void:
	var effects: Dictionary = GameData.balance.get("gather_effects", {}).get(item_id, {})
	wolf.hunger += float(effects.get("hunger", 0))
	wolf.stamina += float(effects.get("stamina", 0))
	wolf.health += float(effects.get("health", 0))
	if effects.has("poison_chance") and RNGService.chance(float(effects["poison_chance"])):
		var balance: Dictionary = GameData.balance
		wolf.poison_days_remaining = RNGService.randi_range(
			int(balance.get("poison_duration_min", 2)), int(balance.get("poison_duration_max", 4))
		)
		log_message.emit(tr("log.poisoned"))
	if effects.has("sting_chance") and RNGService.chance(float(effects["sting_chance"])):
		wolf.health -= float(effects.get("sting_health_loss", 5))
		log_message.emit(tr("log.stung"))
	wolf.clamp_stats()
	_check_death()

# 找睡處：成功時是普通睡處；區域裡有好睡處時有機會找到它，並寫入區域知識（之後不用再找）。
# 回傳 "good"、"normal" 或 ""（沒找到）。
func action_find_sleep_spot() -> String:
	_record_action("find_sleep_spot")
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("find_sleep_spot", 1)))
	var spot := ""
	if _feature_known_here("sleep_spot"):
		spot = "good"
	elif EncounterSystem.find_sleep_spot(current_region):
		spot = "normal"
		found_sleep_spots[current_region] = "normal"
		var region: Dictionary = EncounterSystem.region_data(current_region)
		if region.get("secondary_features", []).has("good_sleep_spot") \
				and RNGService.chance(float(GameData.balance.get("sleep", {}).get("good_spot_find_chance", 0.35))):
			spot = "good"
			var knowledge: Dictionary = region_knowledge.get(current_region, {"visited": true, "features": []})
			if not knowledge["features"].has("good_sleep_spot"):
				knowledge["features"].append("good_sleep_spot")
			region_knowledge[current_region] = knowledge
	state_changed.emit()
	return spot

# 現在睡覺的睡處等級：巢穴 > 已知好睡處 > 找到的睡處 > 勉強過夜。
func sleep_quality() -> String:
	if current_region == den_region:
		return "den"
	if _feature_known_here("sleep_spot"):
		return "good"
	return str(found_sleep_spots.get(current_region, "rough"))

func action_short_rest() -> void:
	_record_action("short_rest")
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("short_rest", 2)))
	var bonus: float = 0.0
	for f in known_features(current_region):
		bonus += float(GameData.region_features().get(f, {}).get("short_rest_stamina_bonus", 0))
	_rest_stamina(float(GameData.balance.get("short_rest_stamina", 15)) + bonus)
	wolf.clamp_stats()
	var events_before: int = pending_events.size()
	_maybe_prey_nearby()
	if pending_events.size() == events_before:
		_maybe_rest_season_change()
	state_changed.emit()

# 快轉：一回合一回合休息到指定時段開始，途中照常結算時段與每日變化；狼死亡就停止。
# 快轉：途中的主動事件與遭遇照常判定；重要事件（灰熊路過、獵物靠近、陌生灰狼現身、暴雨、大火徵兆）
# 會打斷快轉，剩下的時間取消（每次最多打斷一次）。回傳 {"alive", "interrupted": 事件類型或 ""}。
func action_rest_until(target_period: String) -> Dictionary:
	_record_action("rest_until")
	var target_index := GameTime.PERIODS.find(target_period)
	if target_index < 0 or target_index == GameTime.period_index:
		return {"alive": wolf.alive, "interrupted": ""}
	return _rest_loop(func(): return GameTime.period_index == target_index, GameTime.PERIODS.size() * GameTime.TURNS_PER_PERIOD)

# 暴風雪中待在巢穴或好睡處：可以休息到風雪結束（SPEC 1.6「苔原的事件」）。
func can_rest_out_blizzard() -> bool:
	return blizzard_here() and str(blizzard.get("phase", "")) == "active" and sleep_quality() in ["den", "good"]

# 一回合一回合休息到風雪停：照常扣飽食度、體力與受凍，被事件打斷就停；
# 餓到門檻以下也會停下來（interrupted = "hungry"），不讓快轉直接把狼餓死。
func action_rest_out_blizzard() -> Dictionary:
	_record_action("rest_until")
	var floor_hunger: float = float(GameData.balance.get("hunger_low_threshold", 20))
	var max_turns: int = int(blizzard.get("days", 3)) * GameTime.PERIODS.size() * GameTime.TURNS_PER_PERIOD
	var res := _rest_loop(func(): return not blizzard_here() or wolf.hunger <= floor_hunger, max_turns)
	if wolf.alive and str(res["interrupted"]) == "" and blizzard_here():
		res["interrupted"] = "hungry"
	return res

# 快轉的共用迴圈：每回合休息回體力，每過一個時段判定快轉中的事件；stop 成立或被事件打斷就停。
func _rest_loop(stop: Callable, max_turns: int) -> Dictionary:
	var cfg: Dictionary = _events_cfg().get("rest", {})
	var interrupt: Array = cfg.get("interrupt", [])
	var start_events: int = pending_events.size()
	var stamina_per_turn: float = float(GameData.balance.get("rest_until_stamina_per_turn", 7.5))
	var interrupted: String = ""
	var gained_stamina: float = 0.0
	for i in range(max_turns):
		if not wolf.alive or stop.call():
			break
		var period_before: int = GameTime.period_index
		GameTime.advance_turns(1)
		if not wolf.alive:
			break
		var before: float = wolf.stamina
		_rest_stamina(stamina_per_turn)
		wolf.clamp_stats()
		gained_stamina += wolf.stamina - before
		if GameTime.period_index != period_before:
			_rest_period_events(cfg, gained_stamina)
		for j in range(start_events, pending_events.size()):
			if interrupt.has(str(pending_events[j].get("type", ""))):
				interrupted = str(pending_events[j]["type"])
				break
		if interrupted != "":
			break
	if interrupted == "":
		_maybe_rest_season_change()
	state_changed.emit()
	return {"alive": wolf.alive, "interrupted": interrupted}

# 快轉每經過一個時段：獵物靠近、灰熊路過（在巢穴休息比在野外安全）。
func _rest_period_events(cfg: Dictionary, gained_stamina: float) -> void:
	var loc_mult: float = float(cfg.get("location_mult", {}).get(sleep_quality(), 1.0))
	if _can_trigger_event() and RNGService.chance(float(cfg.get("prey_nearby_per_period", 0.06))):
		var pn: Dictionary = _events_cfg().get("prey_nearby", {})
		var animal: String = RNGService.weighted_pick(pn.get("animals", {"hare": 1}))
		_queue_event({"type": "prey_nearby", "animal_id": animal,
			"life_stage": str(pn.get("life_stage", {}).get(animal, "adult")), "terrain": _random_terrain(current_region)})
	var weights: Dictionary = EncounterSystem.region_data(current_region).get("competitor_weights", {}).get("grizzly_bear", {})
	if float(weights.get(GameTime.current_season(), 0)) > 0.0 and _can_trigger_event() \
			and RNGService.chance(float(cfg.get("bear_per_period", 0.03)) * loc_mult * threat_mult()):
		_queue_event({"type": "bear_passing", "health": 0.0, "stamina": gained_stamina})

# 睡覺：可以在任何區域睡，隔天從這裡開始。回復缺少的血量與體力 × 睡處倍率；
# 野外可能在夜裡被灰熊驚醒（回復減半，接著進入遭遇）。回傳 {"quality", "interrupted"}。
func action_sleep() -> Dictionary:
	_record_action("sleep")
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	var cfg: Dictionary = GameData.balance.get("sleep", {})
	var quality := sleep_quality()
	if quality != "den":
		life_log["wild_nights"] = int(life_log.get("wild_nights", 0)) + 1
	else:
		_stat_inc("nights", "den")
	var turns: int = int(costs.get("sleep", 3))
	# 換季睡眠（SPEC「季節轉換」）：睡醒時已經到期、而且沒有大火或暴風雪，這一覺不會被打斷，睡醒時換季
	var season_sleep: bool = GameTime.season_due_after(turns) and not season_change_blocked()
	quiet_sleep = season_sleep
	GameTime.advance_turns(turns)
	quiet_sleep = false
	if not wolf.alive:
		return {}
	var encounter: Dictionary = {}
	if not season_sleep and RNGService.chance(float(cfg.get("night_encounter", {}).get(quality, 0.0)) * threat_mult()):
		encounter = EncounterSystem.roll_competitor(current_region, GameTime.current_season(), true)
	var mult: float = float(cfg.get("recovery", {}).get(quality, 0.4))
	if encounter.get("encountered", false):
		mult *= float(cfg.get("interrupted_mult", 0.5))
	# 暴雨中，沒有遮蔽的睡處回復再降低。
	if weather == "storm" and ["normal", "rough"].has(quality):
		mult *= float(_storm_cfg().get("exposed_sleep_mult", 0.7))
	var smax: float = float(GameData.balance.get("stat_max", 100))
	var before_health: float = wolf.health
	var before_stamina: float = wolf.stamina
	# 睡覺才結算鍛鍊點（SPEC 1.6「成長系統」），血量回復到新的血量上限。
	var settle := Growth.settle_sleep(wolf)
	if not settle["gains"].is_empty():
		growth_applied.emit()
	# 重傷期間血量回復減半（SPEC「傷勢與舊傷」）：重傷之後要休養幾天，體力照常回復
	var health_mult: float = mult * (float(cfg.get("heavy_injury_health_mult", 0.5)) if wolf.injury == Wolf.Injury.HEAVY else 1.0)
	wolf.health += (wolf.health_max - wolf.health) * health_mult
	wolf.stamina += (smax - wolf.stamina) * mult
	wolf.clamp_stats()
	# 灰熊路過：在巢穴或睡處休息時（沒有被驚醒的情況下）。
	if not season_sleep and not encounter.get("encountered", false) and quality != "rough":
		_maybe_bear_passing(wolf.health - before_health, wolf.stamina - before_stamina)
	var summary := sleep_summary(settle)
	var season_changed: bool = season_sleep and wolf.alive
	if season_changed:
		_change_season()
	_snapshot_sleep_stats()
	SaveSystem.save_game()
	state_changed.emit()
	if encounter.get("encountered", false):
		encounter_triggered.emit(prepare_bear_encounter(encounter))
	return {"quality": quality, "interrupted": encounter.get("encountered", false), "summary": summary, "season_changed": season_changed}

# 開始狩獵：依狩獵深度消耗回合（簡易 1、標準 2、完整 3）。
# from_tracking：經由追蹤找到獵物（追蹤的感知成長在 action_track 結算）。terrain：遭遇時的地形，空字串則隨機取區域的地形。
# injured：受傷個體，一律走簡易流程。
func start_hunt(animal_id: String, life_stage: String, prey_dir: int = -1, from_tracking: bool = false,
		terrain: String = "", injured: bool = false) -> HuntSystem:
	var depth: String = "simple" if injured else HuntSystem.depth_of(animal_id, life_stage)
	GameTime.advance_turns(HuntSystem.depth_turns(depth))
	# 深夜對狼有利：獵物警覺降低。
	var detection_mod: float = 0.0
	if GameTime.current_period() == "night":
		detection_mod = float(GameData.balance.get("night_prey_detection_mod", -10))
	if weather == "storm":
		detection_mod += float(_storm_cfg().get("detection_mod", -10))
	if prey_dir < 0:
		prey_dir = RNGService.randi_range(0, 3)
	if terrain == "":
		terrain = _random_terrain(current_region)
	var hunt := HuntSystem.new(wolf, animal_id, life_stage, detection_mod, wind_dir, prey_dir, terrain, injured)
	hunt.knowledge_bonus = weakness_bonuses(animal_id, life_stage)
	hunt.storm = weather == "storm"
	_on_hunt_started(hunt)
	hunt.tendency = current_tendency()
	hunt.fight_state["tendency_bonus"] = tendency_effect("assault")
	hunt.fight_state["source"] = animal_id + ".hunt"
	return hunt

func _random_terrain(region_id: String) -> String:
	var terrains: Array = EncounterSystem.region_data(region_id).get("terrains", [])
	if terrains.is_empty():
		return ""
	return terrains[RNGService.randi_range(0, terrains.size() - 1)]

# 狩獵中花費額外回合（例如繞到下風處）。
# hunt：搏鬥中瀕危仍繼續而倒下時，死因記為戰死（SPEC 1.6「戰鬥中的死亡」）。
func spend_hunt_turns(turns: int, hunt: HuntSystem = null) -> void:
	if hunt != null and wolf.alive and wolf.health <= 0.0:
		die_in_combat(hunt.animal_id, hunt.life_stage, "hunt")
		return
	if turns <= 0:
		return
	GameTime.advance_turns(turns)
	_check_death()

# 狩獵結束（成功或失敗）：同步風向、結算各階段累積的經驗。
# 獵物逃走時，留下一條往某個地形去的新鮮足跡（current_discovery），可以再追。
func finish_hunt(hunt: HuntSystem) -> void:
	wind_dir = hunt.wind_dir
	FightRules.danger_to_heavy(wolf, hunt.fight_state.get("parts", {"leg": 0.5, "shoulder": 0.5}), hunt.animal_id + ".hunt")
	Growth.apply_practice(wolf, hunt.practice)
	_record_hunt(hunt)
	if hunt.result == HuntSystem.Result.SUCCESS:
		if HuntSystem.feeding_segments(hunt.animal_id, hunt.life_stage) > 1:
			start_feeding(hunt.animal_id, hunt.life_stage, hunt.terrain)
		resolve_hunt_success(hunt.animal_id, hunt.life_stage)
	else:
		if hunt.fled and wolf.alive:
			var prey_dir: int = RNGService.randi_range(0, 3)
			current_discovery = {"kind": "clue", "source_kind": "prey", "source": hunt.animal_id,
				"clue": "track", "location": _random_terrain(current_region), "fresh": true, "fresh_known": true,
				"wind": HuntSystem.relative_wind(wind_dir, prey_dir), "prey_dir": prey_dir,
				"life_stage": hunt.life_stage, "injured": hunt.injured, "fled": true}
		wolf.clamp_stats()
		_check_death()
		state_changed.emit()

# --- 試玩自動紀錄（SPEC「遊戲內自動紀錄」）---
# life_log["stats"]：option_counts（每個決策的次數）、counters（觀察機會、因風向失敗…）、
# nights（巢穴／野外）、after_deer（獵到鹿之後到下一次狩獵的天數與行動）。

func _stat_inc(group: String, key: String, amount: int = 1) -> void:
	var stats: Dictionary = life_log.get("stats", {})
	var table: Dictionary = stats.get(group, {})
	table[key] = int(table.get(key, 0)) + amount
	stats[group] = table
	life_log["stats"] = stats

func _record_action(action: String) -> void:
	var after: Dictionary = life_log.get("after_deer", {})
	if not after.is_empty():
		after["actions"][action] = int(after["actions"].get(action, 0)) + 1

func _on_hunt_started(hunt: HuntSystem) -> void:
	_stat_inc("counters", "hunts")
	if hunt.stage == HuntSystem.Stage.OBSERVE:
		_stat_inc("counters", "observe_opportunities")
	var after: Dictionary = life_log.get("after_deer", {})
	if not after.is_empty():
		var stats: Dictionary = life_log.get("stats", {})
		var list: Array = stats.get("after_deer", [])
		list.append({"days": int(life_log.get("days_lived", 1)) - int(after["day"]), "actions": after["actions"]})
		stats["after_deer"] = list
		life_log["stats"] = stats
		life_log["after_deer"] = {}

# 死亡時把試玩紀錄寫成 JSON（user://playtest_logs/），方便比較兩隻狼。
# 試玩紀錄：寫到 user://playtest_logs/。在 Godot 編輯器裡、有視窗地遊玩時（不是 headless、不是自動遊玩或模擬），
# 另外存一份到專案的 playtest_logs/（資料夾有 .gdignore，Godot 不會匯入），commit 後 Claude Code 就讀得到。
# life_log 含最近的戰鬥逐回合紀錄（recent_combats）與主畫面最後約 40 段訊息（recent_messages）。
func _write_playtest_log() -> String:
	DirAccess.make_dir_recursive_absolute("user://playtest_logs")
	var name := "wolf_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://playtest_logs/" + name
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	var text := JSON.stringify({"life_log": life_log, "knowledge": knowledge.values(), "age_years": wolf.age_years,
		"tendency": current_tendency(), "wolf": wolf.to_dict(), "region": current_region, "den": den_region,
		"time": {"season": GameTime.current_season(), "day": GameTime.day, "period": GameTime.current_period()}}, "  ")
	file.store_string(text)
	file.close()
	if OS.has_feature("editor") and DisplayServer.get_name() != "headless" and not auto_playing:
		var project_dir := ProjectSettings.globalize_path("res://playtest_logs")
		DirAccess.make_dir_recursive_absolute(project_dir)
		var copy := FileAccess.open(project_dir.path_join(name), FileAccess.WRITE)
		if copy != null:
			copy.store_string(text)
			copy.close()
			return project_dir.path_join(name)
	return ProjectSettings.globalize_path(path)

# --- 狩獵傾向（SPEC「經歷與一生回顧」） ---
# 最近 window 次決策中比例最高的傾向就是主要傾向，效果 = max_effect × 比例；
# 主要傾向改變時記入 tendency_history，一生回顧用來描述「牠在哪個時期變了」。

func record_decision(decision: String) -> void:
	_stat_inc("option_counts", decision)
	var cfg: Dictionary = GameData.tendency
	var category: String = str(cfg.get("decision_map", {}).get(decision, "other"))
	var list: Array = life_log.get("decisions", [])
	list.append(category)
	while list.size() > int(cfg.get("window", 30)):
		list.pop_front()
	life_log["decisions"] = list
	var since: Dictionary = life_log.get("since_sleep", {})
	if decision.begins_with("chase."):
		since["chase"] = int(since.get("chase", 0)) + 1
	elif decision.begins_with("fight.") or decision in ["bear.fight", "scavenger.guard"]:
		since["fight"] = int(since.get("fight", 0)) + 1
	life_log["since_sleep"] = since
	_update_main_tendency()

# 主要傾向的遲滯判定（SPEC 1.6「狩獵傾向」）：累積 min_decisions 次後才判定；
# 新傾向的比例要比目前的主要傾向多 switch_margin 才轉變。
func _update_main_tendency() -> void:
	var cfg: Dictionary = GameData.tendency
	var list: Array = life_log.get("decisions", [])
	if list.size() < int(cfg.get("min_decisions", 10)):
		return
	var shares := tendency_shares()
	var best: String = ""
	for t in cfg.get("types", []):
		if float(shares.get(t, 0.0)) > 0.0 and (best == "" or float(shares[t]) > float(shares[best])):
			best = t
	var current: String = str(life_log.get("main_tendency", ""))
	if best == "" or best == current:
		return
	if current != "" and float(shares[best]) - float(shares.get(current, 0.0)) < float(cfg.get("switch_margin", 0.1)) - 0.0001:
		return
	life_log["main_tendency"] = best
	var history: Array = life_log.get("tendency_history", [])
	history.append({"type": best, "age": snapped(wolf.age_years, 0.1), "day": int(life_log.get("days_lived", 1))})
	life_log["tendency_history"] = history
	_queue_notice({"type": "tendency_changed", "tendency": best, "from": current})

# 最近 window 次決策中，各傾向所佔的比例（分母含不屬於任何傾向的決策）。
func tendency_shares() -> Dictionary:
	var list: Array = life_log.get("decisions", [])
	var shares: Dictionary = {}
	for t in GameData.tendency.get("types", []):
		shares[t] = float(list.count(t)) / float(list.size()) if not list.is_empty() else 0.0
	return shares

func current_tendency() -> Dictionary:
	var best: String = str(life_log.get("main_tendency", ""))
	if best == "":
		return {}
	var share: float = float(tendency_shares().get(best, 0.0))
	return {"type": best, "share": share, "effect": float(GameData.tendency.get("max_effect", 0.15)) * share}

func tendency_effect(type: String) -> float:
	var t := current_tendency()
	return float(t.get("effect", 0.0)) if t.get("type", "") == type else 0.0

# --- 主動事件 ---

func _events_cfg() -> Dictionary:
	return GameData.events

func _storm_cfg() -> Dictionary:
	return GameData.events.get("storm", {})

func _can_trigger_event() -> bool:
	return wolf != null and wolf.alive and events_today < int(_events_cfg().get("max_per_day", 2))

func _queue_event(event: Dictionary) -> void:
	events_today += 1
	pending_events.append(event)

func pop_event() -> Dictionary:
	if pending_events.is_empty():
		return {}
	return pending_events.pop_front()

# 暴雨：隨機一個時段；雨停後 1 個時段足跡特別清楚。暴雨中每個時段體力額外消耗，風向每時段都會變。
func _update_weather() -> void:
	var cfg := _storm_cfg()
	var now := _abs_period()
	match weather:
		"storm":
			if now > weather_until:
				weather = "after_rain"
				weather_until = now + int(cfg.get("after_rain_periods", 1)) - 1
				pending_events.append({"type": "rain_stopped"})
			else:
				wolf.stamina -= float(cfg.get("stamina_drain_per_period", 5))
				wind_dir = RNGService.randi_range(0, 3)
		"after_rain":
			if now > weather_until:
				weather = "clear"
	# 暴風雪期間不會同時下暴雨
	if weather == "clear" and not blizzard_here() and _can_trigger_event() and RNGService.chance(float(cfg.get("period_chance", 0.05))):
		start_storm()

func start_storm() -> void:
	weather = "storm"
	weather_until = _abs_period()
	# 已發現但未追蹤的足跡被雨沖掉
	if current_discovery.get("clue", "") == "track":
		current_discovery = {}
	_queue_event({"type": "storm"})

# 遠方狼嚎：深夜隨機。逐步累積成「這一帶是其他狼的範圍」。
func _maybe_howl() -> void:
	if GameTime.current_period() != "night" or stranger_territory == "" or not _can_trigger_event():
		return
	# 只在同一張地圖聽得到（人在苔原聽不到森林那隻狼）
	if GameData.map_of(stranger_territory) != current_map():
		return
	var chance_value: float = float(_events_cfg().get("howl", {}).get("night_chance", 0.35))
	# 輸給你之後，遠方的狼嚎減少
	if stranger() != null and stranger().yielded_to_player:
		chance_value *= float(_stranger_cfg().get("howl_mult_after_yield", 0.5))
	if RNGService.chance(chance_value):
		trigger_howl()

func trigger_howl() -> void:
	learn({"type": "territory", "animal": "stranger_wolf", "region": stranger_territory})
	_queue_event({"type": "howl", "region": stranger_territory})

# 在陌生灰狼的範圍停留太久：被驅趕（輕傷、被迫離開、失去這裡的獵物）。
func _update_territory() -> void:
	var npc := stranger()
	if current_region != stranger_territory or npc == null or not npc.alive or npc.yielded_to_player:
		territory_periods = 0
		return
	territory_periods += 1
	var cfg: Dictionary = _events_cfg().get("howl", {})
	# 輸給牠或向牠示弱越多次，越常被趕
	var chance_value: float = float(cfg.get("drive_off_chance", 0.5)) + npc.dominance * float(_stranger_cfg().get("drive_off_dominance_bonus", 0.15))
	if territory_periods >= int(cfg.get("drive_off_periods", 4)) and _can_trigger_event() and RNGService.chance(chance_value):
		territory_periods = 0
		# 可以直接互動後，「被驅趕」改為牠現身、由你選擇退讓或對峙（SPEC 1.6「陌生灰狼」）
		_queue_event({"type": "stranger_confront" if stranger_can_interact() else "driven_off"})

# 實際執行被驅趕（畫面層處理事件時呼叫）。回傳被趕到的區域。
func apply_drive_off() -> String:
	var cfg: Dictionary = _events_cfg().get("howl", {})
	FightRules.hurt_wolf(wolf, float(RNGService.randi_range(int(cfg.get("drive_off_damage_min", 5)), int(cfg.get("drive_off_damage_max", 12)))),
		{"leg": 0.5, "shoulder": 0.5}, "stranger_wolf.encounter", false)
	wolf.apply_injury(Wolf.Injury.LIGHT, 2)
	identify("stranger_wolf")
	return _leave_stranger_territory()

# 離開陌生灰狼的範圍：這一帶的殘骸與進食中斷，移到相鄰的區域。回傳新的區域。
func _leave_stranger_territory() -> String:
	learn({"type": "territory", "animal": "stranger_wolf", "region": current_region})
	var kept: Array = []
	for c in carcasses:
		if c["region_id"] != current_region:
			kept.append(c)
	carcasses = kept
	current_feeding = {}
	current_discovery = {}
	var targets: Array = adjacent_regions()
	if not targets.is_empty():
		current_region = targets[RNGService.randi_range(0, targets.size() - 1)]
		if not is_region_visited(current_region):
			var knowledge_entry: Dictionary = region_knowledge.get(current_region, {"features": []})
			knowledge_entry["visited"] = true
			region_knowledge[current_region] = knowledge_entry
	wolf.clamp_stats()
	_check_death()
	state_changed.emit()
	return current_region

# 獵物靠近：短暫休息或伏低（快轉）時，野兔或幼鹿走近，可以直接撲抓（簡易狩獵）。
func _maybe_prey_nearby() -> void:
	var cfg: Dictionary = _events_cfg().get("prey_nearby", {})
	if not _can_trigger_event() or not RNGService.chance(float(cfg.get("rest_chance", 0.15))):
		return
	var animal: String = RNGService.weighted_pick(cfg.get("animals", {"hare": 1}))
	_queue_event({"type": "prey_nearby", "animal_id": animal,
		"life_stage": str(cfg.get("life_stage", {}).get(animal, "adult")), "terrain": _random_terrain(current_region)})

func hunt_nearby_prey(event: Dictionary) -> HuntSystem:
	return start_hunt(event["animal_id"], event["life_stage"], -1, false, str(event.get("terrain", "")))

# 灰熊路過：在巢穴或睡處休息時。保持不動（看技巧）或立刻離開（失去這次休息的回復）。
func _maybe_bear_passing(gained_health: float, gained_stamina: float) -> void:
	var weights: Dictionary = EncounterSystem.region_data(current_region).get("competitor_weights", {}).get("grizzly_bear", {})
	if float(weights.get(GameTime.current_season(), 0)) <= 0.0 or not _can_trigger_event():
		return
	if RNGService.chance(float(_events_cfg().get("bear_passing", {}).get("sleep_chance", 0.08)) * threat_mult()):
		_queue_event({"type": "bear_passing", "health": gained_health, "stamina": gained_stamina})

func bear_hide_chance() -> float:
	var cfg: Dictionary = _events_cfg().get("bear_passing", {})
	return HuntSystem.clamp_chance(float(cfg.get("hide_base", 0.7)) + (wolf.effective_skill() - 40.0) / float(cfg.get("hide_divisor", 200)))

func resolve_bear_passing(event: Dictionary, choice: String) -> Dictionary:
	if choice == "hide":
		if RNGService.chance(bear_hide_chance()):
			return {"outcome": "hidden"}
		return {"outcome": "spotted", "encounter": prepare_bear_encounter({"encountered": true, "animal_id": "grizzly_bear", "life_stage": "adult"})}
	wolf.health -= float(event.get("health", 0))
	wolf.stamina -= float(event.get("stamina", 0))
	wolf.clamp_stats()
	state_changed.emit()
	return {"outcome": "left"}

# 狩獵紀錄（之後的狩獵傾向與一生回顧使用）：次數、成功、追擊中途放棄。
func _record_hunt(hunt: HuntSystem) -> void:
	if hunt.wind_failure:
		_stat_inc("counters", "wind_failures")
	if hunt.animal_id == "white_tailed_deer" and hunt.result == HuntSystem.Result.SUCCESS:
		life_log["after_deer"] = {"day": int(life_log.get("days_lived", 1)), "actions": {}}
	for d in hunt.decisions:
		record_decision(d)
	if hunt.result == HuntSystem.Result.PLAYER_GAVE_UP:
		record_decision("give_up")
	for option in hunt.successful_options:
		if GameData.knowledge.get("weakness_options", []).has(option):
			learn({"type": "weakness", "animal": hunt.animal_id, "life_stage": hunt.life_stage, "option": option})
	life_log["hunt_attempts"] = int(life_log.get("hunt_attempts", 0)) + 1
	if hunt.result == HuntSystem.Result.SUCCESS:
		life_log["hunt_successes"] = int(life_log.get("hunt_successes", 0)) + 1
	elif hunt.result == HuntSystem.Result.PLAYER_GAVE_UP and hunt.gave_up_stage == HuntSystem.Stage.CHASE:
		life_log["chase_give_ups"] = int(life_log.get("chase_give_ups", 0)) + 1

# --- 分段進食與搶食（SPEC「狩獵後續事件」） ---

func _feeding_cfg() -> Dictionary:
	return GameData.balance.get("feeding", {})

func start_feeding(animal_id: String, life_stage: String, terrain: String) -> void:
	var segments: int = HuntSystem.feeding_segments(animal_id, life_stage)
	var total: float = float(GameData.animals.get(animal_id, {}).get(life_stage, {}).get("hunger_value", 0))
	current_feeding = {"animal_id": animal_id, "life_stage": life_stage, "segments_left": segments,
		"segment_value": total / max(1, segments), "turns_stayed": 0, "terrain": terrain}

func is_feeding() -> bool:
	return not current_feeding.is_empty()

# 下一段吃完後，灰熊／狐狸來搶食的機率：每多停留 1 回合上升，深夜與密林更高。
func scavenge_chances() -> Dictionary:
	var cfg := _feeding_cfg()
	var bear: float = float(cfg.get("bear_base", 0.1)) + float(cfg.get("bear_per_turn", 0.1)) * int(current_feeding.get("turns_stayed", 0))
	if GameTime.current_period() == "night":
		bear += float(cfg.get("night_bonus", 0.05))
	if current_feeding.get("terrain", "") == "dense_forest":
		bear += float(cfg.get("dense_forest_bonus", 0.05))
	# 苔原：渡鴉在上空盤旋，吃得越久，越多動物知道這裡有肉
	var wolverine: float = 0.0
	if current_map() == str(_ravens_cfg().get("map", "tundra")):
		var bonus: float = float(_ravens_cfg().get("feeding_bonus_per_turn", 0.04)) * int(current_feeding.get("turns_stayed", 0))
		bear += bonus
		if _wolverine_alive() and current_map() == str(_wolverine_cfg().get("map", "tundra")):
			wolverine = float(_wolverine_cfg().get("feed_chance", 0.1)) + bonus
	return {"bear": clamp(bear, 0.0, 0.95), "fox": float(cfg.get("fox_chance", 0.12)), "wolverine": clamp(wolverine, 0.0, 0.95)}

# 吃一段：1 回合、飽食度 + 一段。之後判定搶食事件。回傳 {"gain", "event": "bear"|"fox"|""}。
func feed_once() -> Dictionary:
	if not is_feeding():
		return {}
	var chances := scavenge_chances()
	GameTime.advance_turns(int(_feeding_cfg().get("eat_turns", 1)))
	if not wolf.alive:
		current_feeding = {}
		return {}
	var gain: float = float(current_feeding["segment_value"])
	wolf.hunger += gain
	wolf.clamp_stats()
	current_feeding["segments_left"] = int(current_feeding["segments_left"]) - 1
	current_feeding["turns_stayed"] = int(current_feeding["turns_stayed"]) + 1
	var event: String = ""
	if int(current_feeding["segments_left"]) > 0:
		if RNGService.chance(float(chances["bear"]) * threat_mult()):
			event = "bear"
		elif RNGService.chance(float(chances["wolverine"])):
			event = "wolverine"
		elif _tundra_wolves_here() and RNGService.chance(_tundra_carcass_chance()):
			event = "tundra_wait" if tundra_relation_key() == "friendly" else "tundra_wolves"
		elif RNGService.chance(float(chances["fox"])):
			event = "fox"
	else:
		current_feeding = {}
	state_changed.emit()
	return {"gain": gain, "event": event}

# 離開：吃不完的部分留成殘骸。
func leave_feeding() -> void:
	if is_feeding() and int(current_feeding["segments_left"]) > 0:
		carcasses.append({"region_id": current_region, "terrain": current_feeding["terrain"],
			"animal_id": current_feeding["animal_id"], "life_stage": current_feeding["life_stage"],
			"segments_left": current_feeding["segments_left"], "segment_value": current_feeding["segment_value"],
			"day": int(life_log.get("days_lived", 1))})
	current_feeding = {}
	state_changed.emit()

# 還沒辨識的大型動物搶食（不能守住）：grab 叼走一部分、abandon 放棄。
# 辨識後的灰熊與狐狸改走戰鬥模式（start_combat，context = "carcass"）。
func resolve_scavenger(event: String, choice: String) -> Dictionary:
	var result := {"outcome": choice}
	if event == "bear":
		identify("grizzly_bear")
		_learn_danger("grizzly_bear")
		record_decision("scavenger." + choice)
		life_log["scavenged"] = int(life_log.get("scavenged", 0)) + 1
		life_log["scavenged_by_bear"] = int(life_log.get("scavenged_by_bear", 0)) + 1
	elif choice == "ignore":
		life_log["scavenged"] = int(life_log.get("scavenged", 0)) + 1
	if event == "fox":
		if choice == "ignore":
			current_feeding["segments_left"] = int(current_feeding["segments_left"]) - 1
			if int(current_feeding["segments_left"]) <= 0:
				current_feeding = {}
		state_changed.emit()
		return result
	match choice:
		"grab":
			wolf.hunger += float(current_feeding.get("segment_value", 0))
			current_feeding = {}
		_:
			current_feeding = {}
	wolf.clamp_stats()
	_check_death()
	state_changed.emit()
	return result

func carcass_index_here() -> int:
	for i in carcasses.size():
		if carcasses[i]["region_id"] == current_region and bool(carcasses[i].get("found", true)):
			return i
	return -1

# 這一區還沒被找到的屍體（風雪後凍死的動物、渡鴉盤旋處的殘骸）。
func _hidden_carcass_here() -> int:
	for i in carcasses.size():
		if carcasses[i]["region_id"] == current_region and not bool(carcasses[i].get("found", true)):
			return i
	return -1

# 回到殘骸：1 回合；可能撞見正在吃的狐狸或灰熊。回傳 {"event": ...}，沒有殘骸時回傳空字典。
func action_return_to_carcass() -> Dictionary:
	_record_action("return_to_carcass")
	var idx := carcass_index_here()
	if idx < 0:
		return {}
	var cfg := _feeding_cfg()
	GameTime.advance_turns(int(cfg.get("return_turns", 1)))
	if not wolf.alive:
		return {}
	# 回程途中殘骸也可能被搶走或腐壞
	idx = carcass_index_here()
	if idx < 0:
		state_changed.emit()
		return {"gone": true}
	var c: Dictionary = carcasses[idx]
	# own：是不是你自己獵到、吃剩的（凍死的、渡鴉找到的殘骸不是）；畫面依此寫「你回來時」或「發現殘骸」
	var own: bool = bool(c.get("own", true))
	carcasses.remove_at(idx)
	current_feeding = {"animal_id": c["animal_id"], "life_stage": c["life_stage"], "segments_left": c["segments_left"],
		"segment_value": c["segment_value"], "turns_stayed": 0, "terrain": c["terrain"]}
	var event: String = ""
	if RNGService.chance(float(cfg.get("return_bear_chance", 0.1)) * threat_mult()):
		event = "bear"
	elif _wolverine_alive() and current_map() == str(_wolverine_cfg().get("map", "tundra")) \
			and RNGService.chance(float(_wolverine_cfg().get("return_chance", 0.25))):
		event = "wolverine"
	elif _tundra_wolves_here() and RNGService.chance(_tundra_carcass_chance()):
		event = "tundra_wait" if tundra_relation_key() == "friendly" else "tundra_wolves"
	elif RNGService.chance(float(cfg.get("return_fox_chance", 0.2))):
		event = "fox"
	state_changed.emit()
	return {"event": event, "own": own}

# 每個時段：殘骸有 15% 機率被搶走或腐壞，超過 2 天一定消失。
func _decay_carcasses() -> void:
	var cfg := _feeding_cfg()
	var today: int = int(life_log.get("days_lived", 1))
	var kept: Array = []
	for c in carcasses:
		if today - int(c["day"]) > int(cfg.get("carcass_days", 2)):
			continue
		var loss: float = float(cfg.get("carcass_loss_per_period", 0.15))
		if bool(c.get("frozen", false)):
			loss *= float(_blizzard_cfg().get("winter_kill", {}).get("loss_mult", 0.3))
		# 苔原的殘骸還會被狼獾偷吃
		if _wolverine_alive() and GameData.map_of(str(c["region_id"])) == str(_wolverine_cfg().get("map", "tundra")):
			loss *= float(_wolverine_cfg().get("carcass_loss_mult", 1.0))
		if RNGService.chance(loss):
			continue
		kept.append(c)
	carcasses = kept

func resolve_hunt_success(animal_id: String, life_stage: String) -> void:
	var prey_count: Dictionary = life_log.get("prey_count", {})
	prey_count[animal_id] = int(prey_count.get(animal_id, 0)) + 1
	life_log["prey_count"] = prey_count
	_deplete_region(current_region, animal_id)
	var current_rank: int = _prey_rank(str(life_log.get("biggest_prey", "")), str(life_log.get("biggest_prey_stage", "adult")))
	var new_rank: int = _prey_rank(animal_id, life_stage)
	if new_rank > current_rank:
		life_log["biggest_prey"] = animal_id
		life_log["biggest_prey_stage"] = life_stage
	wolf.clamp_stats()
	_check_death()
	state_changed.emit()

func _prey_rank(animal_id: String, life_stage: String) -> int:
	if animal_id == "":
		return -1
	var animal_data: Dictionary = GameData.animals.get(animal_id, {})
	var stats: Dictionary = animal_data.get(life_stage, {})
	return int(stats.get("hunger_value", 0))

# --- 戰鬥模式（SPEC 1.6「戰鬥模式」；規則在 FightRules.gd、流程在 Combat.gd） ---

# 開始一場戰鬥。encounter 是灰熊遭遇的資料（mother、direct）；direct 時對手已經先撲上來，從交鋒開始。
func start_combat(animal_id: String, life_stage: String, context: String, encounter: Dictionary = {}) -> Combat:
	if animal_id == "grizzly_bear":
		identify(animal_id)
		_learn_danger(animal_id)
	var c := Combat.new(wolf, animal_id, life_stage, context, bool(encounter.get("mother", false)))
	c.tendency = current_tendency()
	c.terrain = str(current_feeding.get("terrain", "")) if context == "carcass" else str(encounter.get("location", ""))
	if c.terrain == "":
		c.terrain = _random_terrain(current_region)
	match context:
		"carcass":
			match animal_id:
				"grizzly_bear": c.yields = ["grab", "abandon"]
				"wolverine": c.yields = ["share", "abandon"]
				"tundra_wolf": c.yields = ["let_eat", "guard_together", "abandon"]
				_: c.yields = ["ignore"]
		_:
			c.yields = ["yield"]
	if encounter.get("direct", false):
		c.phase = Combat.Phase.EXCHANGE
		c.damage_taken = float(encounter.get("damage", 0.0))
	_stat_inc("combat", animal_id + ".started")
	return c

# 最近 5 場戰鬥的逐回合紀錄寫進 life_log（試玩紀錄會一起匯出，QA-49）。
func _record_combat_log(c: Combat) -> void:
	var list: Array = life_log.get("recent_combats", [])
	list.append({"age": snapped(wolf.age_years, 0.1), "animal": c.animal_id, "context": c.context, "outcome": c.outcome,
		"wolf_start_hp": snapped(c.start_health, 0.1), "wolf_hp_max": wolf.health_max, "opp_hp_max": c.opp_hp_max,
		"opp_power": c.opp_power(), "wolf_at_start": c.start_effective,
		"rounds": c.round_log})
	life_log["recent_combats"] = list.slice(-5)

# 這一筆「對手」知識：撤退或退讓後，記得「現在的自己還不是對手」。
func opponent_knowledge(animal_id: String, life_stage: String) -> Dictionary:
	return {"type": "opponent", "animal": animal_id, "life_stage": life_stage}

# 和這種對手最近一次交手的結果："beaten"（贏過牠）、"lost"（還不是牠的對手）、""（沒有紀錄）。
# 打贏時清掉「還不是牠的對手」的知識；之後又輸了，再重新記下。
func opponent_history(animal_id: String, life_stage: String) -> String:
	if knowledge_level(opponent_knowledge(animal_id, life_stage)) > 0:
		return "lost"
	if life_log.get("beaten_opponents", []).has(animal_id + "|" + life_stage):
		return "beaten"
	return ""

func _set_opponent_beaten(animal_id: String, life_stage: String, beaten: bool) -> void:
	var key: String = animal_id + "|" + life_stage
	var list: Array = life_log.get("beaten_opponents", [])
	list.erase(key)
	if beaten:
		list.append(key)
		knowledge.erase(knowledge_key(opponent_knowledge(animal_id, life_stage)))
	life_log["beaten_opponents"] = list

# 第一次獨自擊退成年灰熊（SPEC「灰熊：血量與耐力」）：提高潛力上限，再成長一次，跳一張卡片。只限第一次。
func _after_bear_first_win() -> void:
	if bool(life_log.get("bear_first_win", false)):
		return
	life_log["bear_first_win"] = snapped(wolf.age_years, 0.1)
	var cfg: Dictionary = GameData.balance.get("growth", {}).get("bear_first_win", {})
	var caps: Dictionary = {}
	for stat in cfg.get("caps", {}).keys():
		var raised: float = Growth.raise_cap(wolf, str(stat), float(cfg["caps"][stat]))
		if raised > 0.0:
			caps[stat] = raised
	var gains: Dictionary = {}
	for stat in cfg.get("gains", {}).keys():
		var g: float = Growth.bonus(wolf, str(stat), float(cfg["gains"][stat]))
		if g > 0.0:
			gains[stat] = g
	_queue_notice({"type": "bear_first_win", "caps": caps, "gains": gains})

# 戰鬥結束：記錄決策、成長、知識，處理獵物的去留。回傳 {"outcome", "grow": "clean"|"costly"|""}。
func finish_combat(c: Combat) -> Dictionary:
	for d in c.decisions:
		record_decision(d)
	_record_combat_log(c)
	_stat_inc("combat", c.animal_id + "." + c.outcome)
	var result := {"outcome": c.outcome, "grow": ""}
	if c.npc != null:
		c.npc.health = c.opp_hp
	if c.outcome == "died":
		if c.npc != null and c.npc.id == "stranger_wolf":
			_stranger_record("drive_off" if c.context == "territory" else "meet", "died", c.damage_taken, c.opp_hp_max - c.opp_hp)
		elif c.npc != null and TUNDRA_WOLF_IDS.has(c.npc.id):
			_tundra_record(c.context, "died", c.damage_taken, c.opp_hp_max - c.opp_hp)
		die_in_combat(c.animal_id, c.life_stage, c.context)
		return result
	# 打到瀕危才結束：算重傷（QA-46），不是睡一覺就能好
	FightRules.danger_to_heavy(wolf, c.opp.get("parts", {}), c.animal_id + "." + c.context)
	Growth.apply_practice(wolf, c.practice)
	var w: Dictionary = GameData.balance.get("combat", {}).get("win", {})
	if c.won():
		_set_opponent_beaten(c.animal_id, c.life_stage, true)
		# 幾乎沒受傷就獲勝：成長較大；慘勝：偏向技巧、感知與戰鬥的知識（SPEC「戰鬥的成長與知識」）。
		var taken: float = c.damage_taken / max(1.0, wolf.health_max)
		if taken <= float(w.get("clean_ratio", 0.15)):
			Growth.train_activity(wolf, "guard", "strength", float(w.get("clean_mult", 1.5)))
			Growth.learn(wolf, "skill", float(w.get("clean_mult", 1.5)))
			result["grow"] = "clean"
		else:
			Growth.train_activity(wolf, "guard", "strength")
			Growth.learn(wolf, "skill", 1.0)
			if taken >= float(w.get("costly_ratio", 0.4)):
				Growth.learn(wolf, "perception", 1.0)
				result["grow"] = "costly"
	elif c.outcome in ["retreated", "submit"] or (c.outcome in ["yield", "abandon", "grab"] and (c.rounds > 1 or c.probed)):
		# 撤退與示弱不算失敗：知道現在的自己還不是對手
		_set_opponent_beaten(c.animal_id, c.life_stage, false)
		learn(opponent_knowledge(c.animal_id, c.life_stage))
	if c.context == "carcass":
		_carcass_after_combat(c)
	if c.npc != null and c.npc.id == "stranger_wolf":
		result["first_win_skill"] = _after_stranger_combat(c)
	elif c.npc != null and c.npc.id == "wolverine":
		_wolverine_record(c)
		if c.context == "mob":
			_after_mob_combat(c)
	elif c.npc != null and TUNDRA_WOLF_IDS.has(c.npc.id):
		_after_tundra_combat(c)
	if c.won() and c.animal_id == "grizzly_bear" and c.life_stage == "adult" and c.ally_chance <= 0.0:
		_after_bear_first_win()
	GameTime.advance_turns(1)
	wolf.clamp_stats()
	_check_death()
	state_changed.emit()
	return result

# 搶食後獵物的去留：趕走對手就繼續吃；叼走一塊、不理狐狸、退讓、撤退都會失去部分或全部。
func _carcass_after_combat(c: Combat) -> void:
	var by_bear: bool = c.animal_id == "grizzly_bear"
	match c.outcome:
		"drove_off":
			return
		"share":
			# 讓狼獾吃掉一段，換牠離開
			if not current_feeding.is_empty():
				current_feeding["segments_left"] = int(current_feeding["segments_left"]) - 1
				if int(current_feeding["segments_left"]) <= 0:
					current_feeding = {}
			life_log["shared_with_wolverine"] = int(life_log.get("shared_with_wolverine", 0)) + 1
			return
		"let_eat", "guard_together":
			# 讓苔原狼先吃（失去 2 段）或保持距離一起守著（牠們吃掉 1 段），之後可以繼續吃
			var lost: int = int(_tundra_cfg().get("let_eat_segments", 2)) if c.outcome == "let_eat" else 1
			if not current_feeding.is_empty():
				current_feeding["segments_left"] = int(current_feeding["segments_left"]) - lost
				if int(current_feeding["segments_left"]) <= 0:
					current_feeding = {}
			return
		"grab":
			wolf.hunger += float(current_feeding.get("segment_value", 0))
			current_feeding = {}
		"ignore":
			if not current_feeding.is_empty():
				current_feeding["segments_left"] = int(current_feeding["segments_left"]) - 1
				if int(current_feeding["segments_left"]) <= 0:
					current_feeding = {}
		_:
			current_feeding = {}
	life_log["scavenged"] = int(life_log.get("scavenged", 0)) + 1
	if by_bear:
		life_log["scavenged_by_bear"] = int(life_log.get("scavenged_by_bear", 0)) + 1
	elif c.animal_id == "wolverine":
		life_log["scavenged_by_wolverine"] = int(life_log.get("scavenged_by_wolverine", 0)) + 1

# --- 森林大火（SPEC 1.6「森林大火」） ---

func _fire_cfg() -> Dictionary:
	return _events_cfg().get("fire", {})

# 夏季開始時擲一次：今年乾季（夏秋）會不會有大火，會的話挑夏或秋，排在那一季的第 2～7 天（start_days），
# 確保季末前燒完（SPEC「森林大火」）。換季要睡覺才發生、每季長度不固定，所以排到秋季時等秋季開始才決定時段（fire_season）。大火後冷卻 2 年。
func _maybe_schedule_fire() -> void:
	var cfg := _fire_cfg()
	var season: String = GameTime.current_season()
	if fire_season != "":
		if fire_season == season and fire.is_empty():
			fire_at = _fire_time_this_season(cfg)
			fire_season = ""
		return
	var dry: Array = cfg.get("dry_seasons", ["summer"])
	if season != str(dry[0]) or not fire.is_empty() or fire_at >= 0:
		return
	var per_day: int = GameTime.PERIODS.size()
	if _abs_period() - last_fire_abs < int(cfg.get("cooldown_days", 80)) * per_day:
		return
	if RNGService.chance(float(cfg.get("year_chance", 0.15))):
		var pick: String = str(dry[RNGService.randi_range(0, dry.size() - 1)])
		if pick == season:
			fire_at = _fire_time_this_season(cfg)
		else:
			fire_season = pick

# 這一季第 start_days[0]～start_days[1] 天中的某個時段（絕對時段）。
func _fire_time_this_season(cfg: Dictionary) -> int:
	var per_day: int = GameTime.PERIODS.size()
	var days: Array = cfg.get("start_days", [2, 7])
	var day_one: int = _abs_period() - GameTime.period_index - (GameTime.day - 1) * per_day
	return max(_abs_period() + 1, day_one + RNGService.randi_range((int(days[0]) - 1) * per_day, int(days[1]) * per_day - 1))

# 區域的火況：burning 正在燒、ash 剛燒過一片焦黑、regrowth 草木新生、"" 平常。
# 走進燒過的區域：焦黑、草木新生各描述一次（同一場火、同一個狀態只說一次；巢穴所在的區域另有一句）。
# 正在燒的區域由 fire_here 事件處理。
func _describe_burned_arrival(region_id: String) -> void:
	var state: String = burn_state(region_id)
	if not state in ["ash", "regrowth"]:
		return
	var seen: Dictionary = life_log.get("burn_seen", {})
	var mark: String = "%s@%d" % [state, int(region_burn.get(region_id, 0))]
	if str(seen.get(region_id, "")) == mark:
		# 已經描述過：還是焦黑的話每次回來補一句短的，草木新生就不再重複
		if state == "ash":
			log_message.emit(tr("fire.arrive.ash.again").replace("{region}", tr("region." + region_id)))
		return
	seen[region_id] = mark
	life_log["burn_seen"] = seen
	var key: String = "fire.arrive." + state + (".den" if state == "ash" and region_id == den_region else "")
	log_message.emit(tr(key).replace("{region}", tr("region." + region_id)))

func burn_state(region_id: String) -> String:
	if fire.get("regions", {}).has(region_id):
		return "burning"
	if not region_burn.has(region_id):
		return ""
	var after: Dictionary = _fire_cfg().get("after", {})
	var days: int = int(life_log.get("days_lived", 1)) - int(region_burn[region_id])
	if days < int(after.get("ash_days", 12)):
		return "ash"
	if days < int(after.get("ash_days", 12)) + int(after.get("regrowth_days", 40)):
		return "regrowth"
	return ""

# 獵物出現率的倍率：資源消耗 × 火後（焦黑時稀少、草木新生時鹿變多）。
func prey_mults(region_id: String) -> Dictionary:
	var result: Dictionary = region_depletion.get(region_id, {}).duplicate()
	# 冬季的保護色：雪兔在雪地裡比較難被發現
	for animal_id in GameData.animals.keys():
		var camo: float = HuntSystem.camouflage(animal_id)
		if camo > 0.0:
			result[animal_id] = float(result.get(animal_id, 1.0)) * (1.0 - camo)
	var after: Dictionary = _fire_cfg().get("after", {})
	match burn_state(region_id):
		"burning", "ash":
			for animal_id in GameData.animals.keys():
				result[animal_id] = float(result.get(animal_id, 1.0)) * float(after.get("ash_prey_mult", 0.3))
		"regrowth":
			var m: Dictionary = after.get("regrowth_prey_mult", {})
			for animal_id in m.keys():
				result[animal_id] = float(result.get(animal_id, 1.0)) * float(m[animal_id])
	return result

func _update_fire() -> void:
	var cfg := _fire_cfg()
	var now: int = _abs_period()
	if fire.is_empty():
		if fire_at >= 0 and now >= fire_at:
			start_fire_warning("")
		return
	if fire["phase"] == "warning":
		_maybe_notice_fire()
		if now >= int(fire["ignite_at"]):
			fire["phase"] = "burning"
			fire["regions"] = {str(fire["origin"]): now}
			if not bool(fire.get("noticed", false)):
				fire["noticed"] = true
				pending_events.append({"type": "fire_warning", "origin": fire["origin"], "late": true})
		_check_fire_here()
		return
	# 燃燒：燒滿 burn_periods 的區域熄滅（記為燒過），其餘依機率延燒到相鄰區域。
	var regions: Dictionary = fire["regions"]
	var went_out: Array = []
	var spread: Array = []
	for region_id in regions.keys().duplicate():
		if now - int(regions[region_id]) >= int(cfg.get("burn_periods", 3)):
			regions.erase(region_id)
			fire["burned"].append(region_id)
			_region_burned(region_id)
			went_out.append(region_id)
	for region_id in regions.keys().duplicate():
		for adj in EncounterSystem.region_data(region_id).get("adjacent", []):
			if not regions.has(adj) and not fire["burned"].has(adj) and RNGService.chance(float(cfg.get("spread_chance", 0.55))):
				regions[adj] = now
				spread.append(adj)
	if regions.is_empty():
		_end_fire()
		return
	# 火勢的變化寫進紀錄（察覺到大火之後）：哪裡熄了、蔓延到哪裡，玩家才知道大火還沒結束
	if bool(fire.get("noticed", false)):
		var burning: Array = regions.keys().map(func(r): return tr("region." + str(r)))
		for r in went_out:
			log_message.emit(tr("fire.region_out").replace("{region}", tr("region." + str(r))).replace("{list}", "、".join(burning)))
		for r in spread:
			log_message.emit(tr("fire.spread").replace("{region}", tr("region." + str(r))))
	_check_fire_here()

# 起火前的徵兆：origin 空字串時隨機選一個森林區域。除錯可以指定起火區域。
func start_fire_warning(origin: String) -> void:
	if origin == "":
		# 只在會起火的地圖（森林）；苔原不會發生森林大火
		var ids: Array = []
		for region_id in GameData.regions().keys():
			if bool(GameData.maps().get(GameData.map_of(region_id), {}).get("fire", true)):
				ids.append(region_id)
		origin = ids[RNGService.randi_range(0, ids.size() - 1)]
	fire = {"origin": origin, "phase": "warning", "ignite_at": _abs_period() + int(_fire_cfg().get("warning_periods", 2)),
		"noticed": false, "regions": {}, "burned": [], "alerted": [], "sheltered": "",
		"start_age": snapped(wolf.age_years, 0.1), "season": GameTime.current_season()}
	fire_at = -1
	_maybe_notice_fire()

# 感知越高越早察覺：聞到煙味、看到動物往同一個方向逃。
func _maybe_notice_fire() -> void:
	if bool(fire.get("noticed", false)):
		return
	var n: Dictionary = _fire_cfg().get("notice", {})
	var chance_value: float = min(float(n.get("max", 0.9)), float(n.get("base", 0.35)) + (wolf.effective_perception() - 40.0) * float(n.get("per_perception", 0.01)))
	if RNGService.chance(chance_value):
		fire["noticed"] = true
		pending_events.append({"type": "fire_warning", "origin": fire["origin"], "late": false})

# 火燒到你所在的區域：跳出逃生選擇（待在同一區只提示一次；躲在溪邊或巢穴就不再提示）。entered：自己走進還在燒的區域。
func _check_fire_here(entered: bool = false) -> void:
	if fire.is_empty() or not wolf.alive or not fire.get("regions", {}).has(current_region):
		return
	if fire["alerted"].has(current_region) or fire["sheltered"] == current_region:
		return
	fire["alerted"].append(current_region)
	pending_events.append({"type": "fire_here", "region": current_region, "entered": entered})

func _region_burned(region_id: String) -> void:
	region_burn[region_id] = int(life_log.get("days_lived", 1))
	# 次要特徵（好睡處、獸徑等）失效；巢穴在地下，不會被燒毀
	var rk: Dictionary = region_knowledge.get(region_id, {})
	if not rk.is_empty():
		rk["features"] = []
		region_knowledge[region_id] = rk
	found_sleep_spots.erase(region_id)
	var kept: Array = []
	for c in carcasses:
		if c["region_id"] != region_id:
			kept.append(c)
	carcasses = kept
	# 陌生灰狼可能死在火裡
	var npc := stranger()
	if npc != null and npc.alive and npc.territory == region_id and RNGService.chance(float(_fire_cfg().get("npc_death_chance", 0.3))):
		npc.die("fire")
		_on_npc_died(npc)

func _end_fire() -> void:
	var entry := {"age": fire.get("start_age", snapped(wolf.age_years, 0.1)), "season": fire.get("season", ""),
		"origin": fire["origin"], "burned": fire["burned"].duplicate(), "escape": fire.get("escape", ""),
		"result": fire.get("result", ""), "escape_region": fire.get("escape_region", ""), "den_burned": fire["burned"].has(den_region)}
	var list: Array = life_log.get("fires", [])
	list.append(entry)
	life_log["fires"] = list
	last_fire_abs = _abs_period()
	_queue_notice({"type": "fire_over", "burned": entry["burned"], "den_burned": entry["den_burned"]})
	fire = {}

# 逃生選擇：逃往還沒燒到的相鄰區域、到溪邊避難（區域有溪流）、躲進巢穴（正在巢穴）。
# 每個選項附「平安率」（不受傷的機率）。
func fire_escape_options() -> Array:
	var list: Array = []
	for adj in adjacent_regions():
		if not fire.get("regions", {}).has(adj):
			list.append(_escape_option("flee", adj))
	# 從森林北部逃進苔原（不會起火的地圖）
	for link in GameData.links_from(current_region):
		if not bool(GameData.maps().get(GameData.map_of(str(link["to"])), {}).get("fire", true)):
			list.append(_escape_option("other_map", str(link["to"])))
	if EncounterSystem.region_data(current_region).get("terrains", []).has("stream"):
		list.append(_escape_option("stream", ""))
	if current_region == den_region:
		list.append(_escape_option("den", ""))
	return list

func _escape_option(kind: String, region_id: String) -> Dictionary:
	var e: Dictionary = _fire_cfg().get("escape", {})
	var danger: float = float(e.get(kind, 0.5))
	if kind in ["flee", "other_map"]:
		if wolf.stamina < 30.0:
			danger += float(e.get("low_stamina", 0.3))
		danger -= (wolf.effective_speed() - 40.0) / float(e.get("speed_divisor", 200))
		if not is_region_visited(region_id):
			danger *= float(e.get("unknown_region_mult", 1.3))
	if wolf.health < wolf.health_max * 0.5:
		danger += float(e.get("low_health", 0.3))
	danger = clamp(danger, 0.05, 1.5)
	var probs := _fire_outcome_probs(danger)
	return {"id": kind + (":" + region_id if region_id != "" else ""), "kind": kind, "region": region_id,
		"danger": danger, "safe": probs["safe"]}

func _fire_outcome_probs(danger: float) -> Dictionary:
	var o: Dictionary = _fire_cfg().get("outcome", {})
	var death: float = float(o.get("death", 0.12)) * danger
	var heavy: float = float(o.get("heavy", 0.3)) * danger
	var light: float = float(o.get("light", 0.35)) * danger
	var total: float = death + heavy + light
	if total > 1.0:
		death /= total
		heavy /= total
		light /= total
		total = 1.0
	return {"death": death, "heavy": heavy, "light": light, "safe": 1.0 - total}

# 執行逃生。回傳 {"result": "safe"|"light"|"heavy"|"death", "kind", "region"}。
func fire_escape(id: String) -> Dictionary:
	var opt: Dictionary = {}
	for o in fire_escape_options():
		if o["id"] == id:
			opt = o
	if opt.is_empty():
		return {}
	var e: Dictionary = _fire_cfg().get("escape", {})
	GameTime.advance_turns(1)
	var probs := _fire_outcome_probs(float(opt["danger"]))
	var roll: float = RNGService.randf()
	var result: String = "safe"
	if roll < float(probs["death"]):
		result = "death"
	elif roll < float(probs["death"]) + float(probs["heavy"]):
		result = "heavy"
	elif roll < float(probs["death"]) + float(probs["heavy"]) + float(probs["light"]):
		result = "light"
	if opt["kind"] in ["flee", "other_map"]:
		wolf.stamina -= float(e.get("flee_stamina", 20))
		action_move_silent(str(opt["region"]))
	else:
		fire["sheltered"] = current_region
	# 一場大火裡最重的那次逃生記入一生回顧
	var order := ["safe", "light", "heavy", "death"]
	if not fire.has("result") or order.find(result) >= order.find(str(fire.get("result", "safe"))):
		fire["escape"] = opt["kind"]
		fire["escape_region"] = opt["region"]
		fire["result"] = result
	record_decision("fire." + str(opt["kind"]))
	var b: Dictionary = _fire_cfg().get("burn", {})
	match result:
		"light":
			var r: Array = b.get("light_damage", [8, 15])
			wolf.health = max(1.0, wolf.health - RNGService.randi_range(int(r[0]), int(r[1])))
			wolf.apply_injury(Wolf.Injury.LIGHT, int(b.get("light_days", 2)), "", "", "fire")
		"heavy":
			var r2: Array = b.get("heavy_damage", [20, 35])
			wolf.health = max(1.0, wolf.health - RNGService.randi_range(int(r2[0]), int(r2[1])))
			wolf.apply_injury(Wolf.Injury.HEAVY, RNGService.randi_range(int(b.get("heavy_days_min", 4)), int(b.get("heavy_days_max", 6))), "speed", "leg", "fire")
		"death":
			if fire.has("start_age"):
				fire["result"] = "death"
			_end_fire_on_death()
			_die("fire")
			return {"result": result, "kind": opt["kind"], "region": opt["region"]}
	wolf.clamp_stats()
	if wolf.injury_source == "fire" or result != "safe":
		life_log["burned"] = int(life_log.get("burned", 0)) + (1 if result != "safe" else 0)
	_check_fire_here()
	state_changed.emit()
	return {"result": result, "kind": opt["kind"], "region": opt["region"]}

# 死在火裡：先把這場大火寫進一生回顧。
func _end_fire_on_death() -> void:
	var list: Array = life_log.get("fires", [])
	list.append({"age": fire.get("start_age", snapped(wolf.age_years, 0.1)), "season": fire.get("season", ""),
		"origin": fire["origin"], "burned": fire.get("burned", []).duplicate(), "escape": fire.get("escape", ""),
		"result": "death", "escape_region": fire.get("escape_region", ""), "den_burned": false})
	life_log["fires"] = list

# 逃命時移動到相鄰區域（不另外判定灰熊遭遇與地形體力）。
func action_move_silent(target_region: String) -> void:
	current_region = target_region
	if not life_log["regions_visited"].has(target_region):
		life_log["regions_visited"].append(target_region)
	var maps_visited: Array = life_log.get("maps_visited", [GameData.map_of(den_region)])
	if not maps_visited.has(GameData.map_of(target_region)):
		maps_visited.append(GameData.map_of(target_region))
	life_log["maps_visited"] = maps_visited
	var rk: Dictionary = region_knowledge.get(target_region, {"features": []})
	rk["visited"] = true
	region_knowledge[target_region] = rk
	_apply_env_perception()
	_maybe_map_season_card()

# 回到被燒過的巢穴：聞到很重的焦味（每場火提示一次）。
func _note_den_smell() -> void:
	if current_region != den_region or burn_state(den_region) != "ash":
		return
	var key: int = int(region_burn.get(den_region, -1))
	if int(life_log.get("den_smell_noted", -2)) == key:
		return
	life_log["den_smell_noted"] = key
	log_message.emit(tr("log.den_burned"))

# 在這裡安家：把巢穴搬到目前的區域（火後重新選巢；一般時候也可以）。
func can_make_den_here() -> bool:
	return current_region != den_region and bool(EncounterSystem.region_data(current_region).get("can_den", false)) \
		and burn_state(current_region) not in ["burning"]

# 巢穴所在區域的加成（regions.json 的 den_bonus，例如遠北的沙脊）。
func den_bonus() -> Dictionary:
	return EncounterSystem.region_data(den_region).get("den_bonus", {})

func action_make_den() -> void:
	if not can_make_den_here():
		return
	_record_action("make_den")
	GameTime.advance_turns(int(GameData.balance.get("action_turn_costs", {}).get("make_den", 2)))
	var list: Array = life_log.get("den_moves", [])
	list.append({"from": den_region, "to": current_region, "age": snapped(wolf.age_years, 0.1)})
	life_log["den_moves"] = list
	den_region = current_region
	log_message.emit(tr("log.made_den").replace("{region}", tr("region." + current_region)))
	if not den_bonus().is_empty():
		log_message.emit(tr("log.made_den.bonus." + current_region))
	state_changed.emit()

# --- 陌生灰狼（SPEC 1.6「陌生灰狼」；牠的資料在 NpcWolf.gd） ---

func _stranger_cfg() -> Dictionary:
	return NpcWolf.cfg("stranger_wolf").get("interaction", {})

func stranger() -> NpcWolf:
	return npcs.get("stranger_wolf", null)

# 可以直接互動：牠還活著、至少遠距觀察過一次，而且到了這一局決定的時機（次成年期或成年後）。
func stranger_can_interact() -> bool:
	var npc := stranger()
	if npc == null or not npc.alive or not bool(life_log.get("stranger_observed", false)):
		return false
	if str(life_log.get("stranger_unlock", "subadult")) == "adult" and wolf.life_stage() == Wolf.LifeStage.SUBADULT:
		return false
	return true

func _heal_npcs() -> void:
	for npc in npcs.values():
		if npc.alive:
			npc.health = min(npc.health_max, npc.health + float(NpcWolf.cfg(npc.id).get("heal_per_day", 10)))

# 每季：牠也會變老；老死或死於其他原因後，那一帶就空了。
func _age_npcs() -> void:
	for npc in npcs.values():
		var cause: String = npc.on_season_passed()
		if cause != "":
			_on_npc_died(npc)
	_maybe_new_wolverine()

# 狼獾死後，每一季有機會從別處遷進一隻新的（第幾隻記在 life_log.wolverine_gen）。
func _maybe_new_wolverine() -> void:
	var npc := wolverine()
	if npc != null and npc.alive:
		return
	if RNGService.chance(float(_wolverine_cfg().get("replace_chance_per_season", 0.5))):
		npcs["wolverine"] = NpcWolf.create("wolverine", "")
		life_log["wolverine_gen"] = int(life_log.get("wolverine_gen", 1)) + 1

func _on_npc_died(npc: NpcWolf) -> void:
	if npc.id == "wolverine":
		var deaths: Array = life_log.get("wolverine_deaths", [])
		deaths.append({"cause": npc.death_cause, "npc_age": snapped(npc.age_years, 0.25), "age": snapped(wolf.age_years, 0.1)})
		life_log["wolverine_deaths"] = deaths
		return
	if npc.id != "stranger_wolf":
		life_log[npc.id + "_death"] = {"cause": npc.death_cause, "npc_age": snapped(npc.age_years, 0.25), "age": snapped(wolf.age_years, 0.1)}
		return
	stranger_territory = ""
	life_log["stranger_death"] = {"cause": npc.death_cause, "npc_age": snapped(npc.age_years, 0.25), "age": snapped(wolf.age_years, 0.1)}

# 和牠相比：依力量值差與牠的年紀，給出「牠比你強壯得多／不相上下／已經不如你」這類判斷。
func stranger_assessment() -> Dictionary:
	return npc_assessment(stranger())

func npc_assessment(npc: NpcWolf) -> Dictionary:
	return {"compare": power_compare(npc.power()), "age": npc.life_stage_key()}

# 對手的力量值和你現在的力量值相比：much_stronger／stronger／even／weaker／much_weaker（對手的角度）。
func power_compare(opp_power: float) -> String:
	var diff: float = opp_power - FightRules.wolf_power(wolf)
	if diff > 25.0:
		return "much_stronger"
	if diff > 8.0:
		return "stronger"
	if diff < -25.0:
		return "much_weaker"
	if diff < -8.0:
		return "weaker"
	return "even"

func _stranger_record(kind: String, outcome: String, wolf_damage: float = 0.0, npc_damage: float = 0.0) -> void:
	var entry := {"age": snapped(wolf.age_years, 0.1), "kind": kind, "outcome": outcome, "region": current_region,
		"wolf_damage": snapped(wolf_damage, 1.0), "npc_damage": snapped(npc_damage, 1.0)}
	stranger().add_record(entry.duplicate())
	var list: Array = life_log.get("stranger_meetings", [])
	list.append(entry)
	life_log["stranger_meetings"] = list

# 避開：悄悄繞開，不起衝突。
func stranger_avoid() -> void:
	record_decision("avoid")
	_stranger_record("meet", "avoided")
	state_changed.emit()

# 跟蹤：看感知。成功就看清楚牠現在的狀態（和你相比的強弱、年紀）；失敗被牠發現，牠轉身對峙。
func stranger_follow() -> Dictionary:
	GameTime.advance_turns(1)
	var npc := stranger()
	var cfg := _stranger_cfg()
	var chance_value: float = HuntSystem.clamp_chance(float(cfg.get("follow_base", 0.45)) + (wolf.effective_perception() - npc.perception) / float(cfg.get("follow_divisor", 150)))
	var ok: bool = RNGService.chance(chance_value)
	Growth.learn_flat(wolf, "perception", "track_perception", 1.0 if ok else float(Growth.cfg().get("fail_mult", 0.25)))
	if not ok:
		return {"success": false}
	var a := stranger_assessment()
	life_log["stranger_assessment"] = {"compare": a["compare"], "age": a["age"], "wolf_age": snapped(wolf.age_years, 0.1)}
	_stranger_record("follow", "assessed")
	state_changed.emit()
	return {"success": true, "assessment": a}

func stranger_follow_chance() -> float:
	var cfg := _stranger_cfg()
	return HuntSystem.clamp_chance(float(cfg.get("follow_base", 0.45)) + (wolf.effective_perception() - stranger().perception) / float(cfg.get("follow_divisor", 150)))

# 和牠對峙或戰鬥。context：meet（主動遇上、挑戰）、territory（在牠的範圍被牠找上，牠護地盤更拚）。
func start_stranger_combat(context: String) -> Combat:
	var c := start_combat("stranger_wolf", "adult", context)
	c.set_npc(stranger())
	return c

# 被牠找上時退讓：離開這一帶，不受傷。
func stranger_yield_territory() -> String:
	record_decision("combat.yield")
	_stranger_record("drive_off", "yielded")
	return _leave_stranger_territory()

# 戰鬥後：牠的血量、你們的紀錄、範圍的歸屬（SPEC「勝負的結果」）。
# 回傳第一次打贏牠時技巧的成長量（沒有就是 0）。
func _after_stranger_combat(c: Combat) -> float:
	var npc := stranger()
	npc.health = c.opp_hp
	_stranger_record("drive_off" if c.context == "territory" else "meet", c.outcome, c.damage_taken, c.opp_hp_max - c.opp_hp)
	var skill_gain: float = 0.0
	match c.outcome:
		"drove_off", "killed":
			# 第一次打贏牠、這一戰沒有受重傷：技巧大幅成長一次（SPEC「陌生灰狼」勝負的結果）。
			# 只看第一次勝利，之後再打贏也不會有，避免反覆找牠打來刷成長。
			if not bool(life_log.get("stranger_first_win", false)):
				life_log["stranger_first_win"] = true
				if wolf.heavy_injury_count == c.start_heavy_count:
					# 先提高技巧上限，成年後接近上限時也拿得到這次成長（SPEC「陌生灰狼」）
					Growth.raise_cap(wolf, "skill", float(GameData.balance.get("growth", {}).get("stranger_first_win_cap", 4)))
					skill_gain = Growth.bonus(wolf, "skill", float(GameData.balance.get("growth", {}).get("stranger_first_win_skill", 4)))
			# 你贏了：牠占據的那一帶變成你的範圍，之後不再被驅趕
			life_log["own_territory"] = npc.territory
			if c.outcome == "killed":
				_queue_notice({"type": "stranger_killed", "region": npc.territory})
			npc.yielded_to_player = true
			npc.dominance = 0
			if c.outcome == "killed":
				npc.die("killed_by_player")
				_on_npc_died(npc)
			else:
				npc.territory = _npc_new_territory(npc.territory)
				stranger_territory = npc.territory
		"submit":
			# 示弱：活下來，但失去那一帶的範圍，之後更常被趕
			npc.dominance += 1
			if current_region == npc.territory:
				_leave_stranger_territory()
		"retreated", "yield":
			if c.rounds > 0:
				npc.dominance += 1
			if c.context == "territory" and current_region == npc.territory:
				_leave_stranger_territory()
	return skill_gain

# 牠輸了之後搬到另一帶（不是你的巢穴，也不是剛讓出來的地方）。
func _npc_new_territory(old: String) -> String:
	var options: Array = []
	for region_id in GameData.map_regions(GameData.map_of(old)):
		if region_id != old and region_id != den_region:
			options.append(region_id)
	return options[RNGService.randi_range(0, options.size() - 1)] if not options.is_empty() else ""

# --- 苔原的事件（1.6 第 6d 步，docs/tundra-detail.md；數值在 events.json 與 balance.json npc_wolves.wolverine） ---

func _blizzard_cfg() -> Dictionary:
	return _events_cfg().get("blizzard", {})

func _blizzard_map() -> String:
	return str(_blizzard_cfg().get("map", "tundra"))

func _ice_cfg() -> Dictionary:
	return _events_cfg().get("ice_break", {})

func _ravens_cfg() -> Dictionary:
	return _events_cfg().get("ravens", {})

func _update_tundra_events() -> void:
	_update_blizzard()
	_update_whiteout()
	_maybe_ravens()
	_maybe_tundra_howl()

# 冬季開始時擲一次：這個冬天會不會有暴風雪，會的話排定在冬季中的某個時段（留下風雪持續的天數）。
func _maybe_schedule_blizzard() -> void:
	var cfg := _blizzard_cfg()
	if GameTime.current_season() != str(cfg.get("season", "winter")) or not blizzard.is_empty() or blizzard_at >= 0:
		return
	if RNGService.chance(float(cfg.get("winter_chance", 0.4))):
		var per_day: int = GameTime.PERIODS.size()
		var last_day: int = GameTime._season_day_count() - int(cfg.get("duration_days_max", 3))
		blizzard_at = _abs_period() + RNGService.randi_range(per_day, max(per_day, last_day * per_day - 1))

func blizzard_active() -> bool:
	return not blizzard.is_empty() and blizzard.get("phase", "") == "active"

# 狼正在風雪裡（在苔原）。
func blizzard_here() -> bool:
	return blizzard_active() and current_map() == _blizzard_map()

func _update_blizzard() -> void:
	var now: int = _abs_period()
	if blizzard.is_empty():
		if blizzard_at >= 0 and now >= blizzard_at:
			start_blizzard_warning()
		return
	if blizzard["phase"] == "warning":
		_maybe_notice_blizzard()
		if now >= int(blizzard["start_at"]):
			blizzard["phase"] = "active"
			if not bool(blizzard.get("noticed", false)) and current_map() == _blizzard_map():
				blizzard["noticed"] = true
				pending_events.append({"type": "blizzard_warning", "late": true})
		_check_blizzard_here()
		return
	if now >= int(blizzard["end_at"]):
		_end_blizzard()
		return
	_check_blizzard_here()

# 起風雪前的徵兆（start_at 前 warning_periods 個時段）。
func start_blizzard_warning(warning_periods: int = -1) -> void:
	var cfg := _blizzard_cfg()
	if warning_periods < 0:
		warning_periods = int(cfg.get("warning_periods", 2))
	var start: int = _abs_period() + warning_periods
	var days: int = RNGService.randi_range(int(cfg.get("duration_days_min", 2)), int(cfg.get("duration_days_max", 3)))
	blizzard = {"phase": "warning", "start_at": start, "end_at": start + days * GameTime.PERIODS.size(), "days": days,
		"noticed": false, "alerted": [], "shelter": "", "shelter_region": "", "in_tundra": false, "far_noted": false,
		"choice": "", "result": "", "start_age": snapped(wolf.age_years, 0.1)}
	blizzard_at = -1
	_maybe_notice_blizzard()

# 感知越高越早察覺：風突然停了、天色發黃，雪兔躲進雪裡，馴鹿背風擠成一團。只有在苔原才看得到。
func _maybe_notice_blizzard() -> void:
	if bool(blizzard.get("noticed", false)) or current_map() != _blizzard_map():
		return
	var n: Dictionary = _blizzard_cfg().get("notice", {})
	var chance_value: float = min(float(n.get("max", 0.9)), float(n.get("base", 0.35)) + (wolf.effective_perception() - 40.0) * float(n.get("per_perception", 0.01)))
	if RNGService.chance(chance_value):
		blizzard["noticed"] = true
		pending_events.append({"type": "blizzard_warning", "late": false})

# 風雪中、狼在苔原：每個區域提示一次「要怎麼躲」；已經在這一區躲好就不再提示。在森林只聽到北方的風聲。
func _check_blizzard_here() -> void:
	if not blizzard_active() or wolf == null or not wolf.alive:
		return
	if current_map() != _blizzard_map():
		if not bool(blizzard.get("far_noted", false)) and not bool(blizzard.get("in_tundra", false)):
			blizzard["far_noted"] = true
			pending_events.append({"type": "blizzard_far"})
		return
	blizzard["in_tundra"] = true
	if blizzard.get("shelter_region", "") == current_region and str(blizzard.get("shelter", "")) != "":
		return
	if blizzard["alerted"].has(current_region):
		return
	blizzard["alerted"].append(current_region)
	pending_events.append({"type": "blizzard_here", "region": current_region})

# 選擇：挖雪洞躲著、躲進巢穴或好睡處（巢穴、沙脊）、頂著風往林線撤退。每個選項附「平安率」（不凍傷的機率）。
func blizzard_options() -> Array:
	var list: Array = [_blizzard_option("dig")]
	if current_region == den_region or _feature_known_here("sleep_spot"):
		list.append(_blizzard_option("den"))
	var target := _retreat_target()
	if target != "":
		list.append(_blizzard_option("retreat", target))
	return list

func _blizzard_option(kind: String, target: String = "") -> Dictionary:
	var e: Dictionary = _blizzard_cfg().get("escape", {})
	var danger: float = float(e.get(kind, 0.4))
	if kind == "retreat":
		if wolf.stamina < 30.0:
			danger += float(e.get("low_stamina", 0.3))
		danger -= (wolf.effective_speed() - 40.0) / float(e.get("speed_divisor", 200))
	elif wolf.hunger < 40.0:
		# 躲著不動：肚子空空撐不久
		danger += float(e.get("low_hunger", 0.2))
	if wolf.health < wolf.health_max * 0.5:
		danger += float(e.get("low_health", 0.2))
	if kind == "den" and current_region == den_region:
		danger *= float(den_bonus().get("blizzard_danger_mult", 1.0))
	danger = clamp(danger, 0.05, 1.5)
	var o: Dictionary = _blizzard_cfg().get("outcome", {})
	var heavy: float = float(o.get("heavy", 0.3)) * danger
	var light: float = float(o.get("light", 0.45)) * danger
	if heavy + light > 1.0:
		var total: float = heavy + light
		heavy /= total
		light /= total
	return {"id": kind, "kind": kind, "region": target, "danger": danger, "heavy": heavy, "light": light, "safe": 1.0 - heavy - light}

# 撤退的方向：離開苔原最近的那一步（林線就直接進森林）。
func _retreat_target() -> String:
	for link in GameData.links_from(current_region):
		if GameData.map_of(str(link["to"])) != _blizzard_map():
			return str(link["to"])
	var best: String = ""
	var best_steps: int = 99
	for adj in adjacent_regions():
		var steps := _steps_to_exit(str(adj))
		if steps < best_steps:
			best = str(adj)
			best_steps = steps
	return best

func _steps_to_exit(start: String) -> int:
	var frontier: Array = [start]
	var seen: Array = [start]
	var steps: int = 0
	while not frontier.is_empty() and steps < 10:
		var next: Array = []
		for r in frontier:
			for link in GameData.links_from(str(r)):
				if GameData.map_of(str(link["to"])) != _blizzard_map():
					return steps
			for adj in EncounterSystem.region_data(str(r)).get("adjacent", []):
				if not seen.has(adj):
					seen.append(adj)
					next.append(adj)
		frontier = next
		steps += 1
	return 99

# 執行選擇。回傳 {"result": "safe"|"light"|"heavy", "kind", "region", "lost"}。
func blizzard_choose(id: String) -> Dictionary:
	var opt: Dictionary = {}
	for o in blizzard_options():
		if o["id"] == id:
			opt = o
	if opt.is_empty():
		return {}
	var e: Dictionary = _blizzard_cfg().get("escape", {})
	var roll: float = RNGService.randf()
	var result: String = "safe"
	if roll < float(opt["heavy"]):
		result = "heavy"
	elif roll < float(opt["heavy"]) + float(opt["light"]):
		result = "light"
	record_decision("blizzard." + id)
	var lost: bool = false
	var target: String = str(opt["region"])
	if id == "retreat":
		# 在白茫茫中走錯區域（跨地圖那一步沿著林線，不會走錯）
		var link := _link_to(target)
		if link.is_empty() and RNGService.chance(float(e.get("lost_chance", 0.3))):
			var others: Array = adjacent_regions().filter(func(r): return r != target)
			if not others.is_empty():
				target = others[RNGService.randi_range(0, others.size() - 1)]
				lost = true
		wolf.stamina -= float(e.get("retreat_stamina", 15)) + (float(link["stamina"]) if not link.is_empty() else 0.0)
		action_move_silent(target)
		GameTime.advance_turns(int(link["turns"]) if not link.is_empty() else 1)
	else:
		blizzard["shelter"] = id
		blizzard["shelter_region"] = current_region
		GameTime.advance_turns(1)
	# 一場風雪裡最重的那次記入一生回顧
	var order := ["safe", "light", "heavy"]
	if blizzard.is_empty():
		pass
	elif str(blizzard.get("result", "")) == "" or order.find(result) >= order.find(str(blizzard.get("result", "safe"))):
		blizzard["choice"] = id
		blizzard["result"] = result
	_apply_frostbite(result)
	wolf.clamp_stats()
	_check_death()
	_check_blizzard_here()
	state_changed.emit()
	return {"result": result, "kind": id, "region": current_region, "lost": lost}

# 凍傷：耳朵（臉）或腳掌（腿）。不會致死；重度凍傷可能留下舊傷（同其他重傷）。
func _apply_frostbite(result: String) -> void:
	if result == "safe":
		return
	var f: Dictionary = _blizzard_cfg().get("frostbite", {})
	var part: String = str(RNGService.weighted_pick(f.get("parts", {"face": 0.5, "leg": 0.5})))
	var stat: String = str(GameData.balance.get("combat", {}).get("part_stat", {}).get(part, ""))
	if result == "light":
		var r: Array = f.get("light_damage", [5, 10])
		wolf.health = max(1.0, wolf.health - RNGService.randi_range(int(r[0]), int(r[1])))
		wolf.apply_injury(Wolf.Injury.LIGHT, int(f.get("light_days", 2)), "", "", "blizzard")
	else:
		var r2: Array = f.get("heavy_damage", [15, 25])
		wolf.health = max(1.0, wolf.health - RNGService.randi_range(int(r2[0]), int(r2[1])))
		wolf.apply_injury(Wolf.Injury.HEAVY, RNGService.randi_range(int(f.get("heavy_days_min", 4)), int(f.get("heavy_days_max", 6))), stat, part, "blizzard")
	life_log["frostbite"] = int(life_log.get("frostbite", 0)) + 1

# 風雪停了：苔原上出現凍死的馴鹿或駝鹿（冬殺），要自己找到（探索、渡鴉）；比平常的殘骸保存得久。
func _end_blizzard() -> void:
	var wk: Dictionary = _blizzard_cfg().get("winter_kill", {})
	var regions: Array = GameData.map_regions(_blizzard_map())
	var today: int = int(life_log.get("days_lived", 1))
	var kills: int = RNGService.randi_range(int(wk.get("count_min", 1)), int(wk.get("count_max", 3)))
	for i in kills:
		var region_id: String = str(regions[RNGService.randi_range(0, regions.size() - 1)])
		var animal_id: String = str(RNGService.weighted_pick(wk.get("animals", {"caribou": 1})))
		var segments: int = HuntSystem.feeding_segments(animal_id, "adult")
		var total: float = float(GameData.animals.get(animal_id, {}).get("adult", {}).get("hunger_value", 0))
		carcasses.append({"region_id": region_id, "terrain": _random_terrain(region_id), "animal_id": animal_id, "life_stage": "adult",
			"segments_left": segments, "segment_value": total / max(1, segments), "day": today + int(wk.get("extra_days", 2)),
			"frozen": true, "found": false, "own": false})
	var entry := {"age": blizzard.get("start_age", snapped(wolf.age_years, 0.1)), "days": int(blizzard.get("days", 2)),
		"in_tundra": bool(blizzard.get("in_tundra", false)), "choice": str(blizzard.get("choice", "")), "result": str(blizzard.get("result", ""))}
	var list: Array = life_log.get("blizzards", [])
	list.append(entry)
	life_log["blizzards"] = list
	if entry["in_tundra"] or current_map() == _blizzard_map():
		_queue_notice({"type": "blizzard_over", "kills": kills})
	blizzard = {}

# 白矇天：開闊苔原、遠北偶爾起霧或刮白毛風，持續 1～2 個時段。感知 −20%，移動可能走錯區域。
func _update_whiteout() -> void:
	var cfg: Dictionary = _events_cfg().get("whiteout", {})
	var now: int = _abs_period()
	if whiteout_until >= 0 and now > whiteout_until:
		whiteout_until = -1
	if whiteout_until < 0 and not blizzard_active() and cfg.get("regions", []).has(current_region) and _can_trigger_event() \
			and RNGService.chance(float(cfg.get("period_chance", 0.04))):
		whiteout_until = now + RNGService.randi_range(int(cfg.get("periods_min", 1)), int(cfg.get("periods_max", 2))) - 1
		life_log["whiteouts"] = int(life_log.get("whiteouts", 0)) + 1
		_queue_event({"type": "whiteout"})
	_apply_env_perception()

func whiteout_here() -> bool:
	return whiteout_until >= _abs_period() and _events_cfg().get("whiteout", {}).get("regions", []).has(current_region)

func _apply_env_perception() -> void:
	if wolf != null:
		wolf.env_perception_mult = float(_events_cfg().get("whiteout", {}).get("perception_mult", 0.8)) if whiteout_here() else 1.0

# 進出河谷（一般移動，不是地圖連結或冰面捷徑）要過河："frozen" 冬季走冰、"thaw" 春季冰薄、"wade" 夏秋涉水；不用過河回傳 ""。
func river_crossing(target_region: String) -> String:
	var river: String = str(_ice_cfg().get("region", ""))
	if river == "" or (current_region != river and target_region != river):
		return ""
	if not _link_to(target_region).is_empty():
		return ""
	var season: String = GameTime.current_season()
	if season == "winter":
		return "frozen"
	if season == str(_ice_cfg().get("season", "spring")):
		return "thaw"
	return "wade"

# 春融：春季進出河谷要過河，河冰可能在腳下裂開。
func _maybe_ice_break() -> void:
	var cfg := _ice_cfg()
	if GameTime.current_season() != str(cfg.get("season", "spring")) or not wolf.alive:
		return
	if RNGService.chance(float(cfg.get("move_chance", 0.2))):
		_learn_ice(true)
		pending_events.append({"type": "ice_break"})

# 選項：跳回岸上（看速度）、趴低慢慢爬回（較穩，多花回合）。
func ice_break_options() -> Array:
	var cfg := _ice_cfg()
	var jump: float = HuntSystem.clamp_chance(float(cfg.get("jump_base", 0.6)) + (wolf.effective_speed() - 40.0) / float(cfg.get("speed_divisor", 150)))
	return [{"id": "jump", "chance": jump, "turns": 1}, {"id": "crawl", "chance": float(cfg.get("crawl_chance", 0.8)), "turns": int(cfg.get("crawl_turns", 2))}]

# 失敗就落水：體力大減、受凍（飽食度下降）、輕傷，不會致死。回傳 {"success"}。
func ice_break_choose(id: String) -> Dictionary:
	var opt: Dictionary = {}
	for o in ice_break_options():
		if o["id"] == id:
			opt = o
	if opt.is_empty():
		return {}
	var cfg := _ice_cfg()
	record_decision("ice." + id)
	var ok: bool = RNGService.chance(float(opt["chance"]))
	if id == "jump":
		Growth.train_activity(wolf, "action", "speed", 0.5)
	if not ok:
		wolf.stamina -= float(cfg.get("fail_stamina", 100))
		wolf.hunger -= float(cfg.get("fail_hunger", 10))
		wolf.health = max(1.0, wolf.health - float(cfg.get("fail_damage", 8)))
		life_log["fell_through_ice"] = int(life_log.get("fell_through_ice", 0)) + 1
	wolf.clamp_stats()
	GameTime.advance_turns(int(opt["turns"]))
	_check_death()
	state_changed.emit()
	return {"success": ok}

# 渡鴉：白天在苔原看到遠處盤旋（地圖上有屍體時更常見）。跟過去有機會找到屍體。
func _maybe_ravens() -> void:
	var cfg := _ravens_cfg()
	if current_map() != str(cfg.get("map", "tundra")) or is_feeding() or not _can_trigger_event():
		return
	if not cfg.get("periods", ["day"]).has(GameTime.current_period()):
		return
	var chance_value: float = float(cfg.get("period_chance", 0.03))
	var target: String = ""
	var nearby: Array = [current_region] + adjacent_regions().filter(func(r): return GameData.map_of(r) == current_map())
	for c in carcasses:
		if nearby.has(c["region_id"]):
			target = str(c["region_id"])
			chance_value *= float(cfg.get("carcass_chance_mult", 3.0))
			break
	if not RNGService.chance(chance_value):
		return
	if target == "":
		target = str(nearby[RNGService.randi_range(0, nearby.size() - 1)])
	life_log["ravens_seen"] = int(life_log.get("ravens_seen", 0)) + 1
	_queue_event({"type": "ravens", "region": target})

# 跟著渡鴉過去：1 回合（到相鄰區域照常移動）。找到屍體就標記為已找到，接著可以回到殘骸吃。回傳 {"found"}。
func ravens_follow(event: Dictionary) -> Dictionary:
	var target: String = str(event.get("region", current_region))
	record_decision("ravens.follow")
	if target != current_region and adjacent_regions().has(target):
		_quiet_move_log = true
		action_move(target)
		_quiet_move_log = false
		if not wolf.alive:
			return {}
	else:
		GameTime.advance_turns(1)
	var idx := -1
	for i in carcasses.size():
		if carcasses[i]["region_id"] == current_region:
			idx = i
			break
	var cfg := _ravens_cfg()
	if idx < 0 and RNGService.chance(float(cfg.get("found_chance", 0.6))):
		var left: Dictionary = cfg.get("leftover", {})
		var animal_id: String = str(RNGService.weighted_pick(left.get("animals", {"caribou": 1})))
		var segments: int = HuntSystem.feeding_segments(animal_id, "adult")
		var total: float = float(GameData.animals.get(animal_id, {}).get("adult", {}).get("hunger_value", 0))
		carcasses.append({"region_id": current_region, "terrain": _random_terrain(current_region), "animal_id": animal_id, "life_stage": "adult",
			"segments_left": min(segments, RNGService.randi_range(int(left.get("segments_min", 1)), int(left.get("segments_max", 2)))),
			"segment_value": total / max(1, segments), "day": int(life_log.get("days_lived", 1)), "own": false})
		idx = carcasses.size() - 1
	life_log["ravens_followed"] = int(life_log.get("ravens_followed", 0)) + 1
	state_changed.emit()
	if idx < 0:
		return {"found": false}
	carcasses[idx]["found"] = true
	return {"found": true, "animal_id": carcasses[idx]["animal_id"]}

# --- 狼獾（具名 NPC，沿用 NpcWolf；牠爭的是你的食物，不是地盤） ---

func wolverine() -> NpcWolf:
	return npcs.get("wolverine", null)

func _wolverine_cfg() -> Dictionary:
	return NpcWolf.cfg("wolverine").get("interaction", {})

func _wolverine_alive() -> bool:
	var npc := wolverine()
	return npc != null and npc.alive

# 狼獾來搶食：進入戰鬥模式（對峙時可以讓牠吃一段換牠離開，或放棄）。
func start_wolverine_combat() -> Combat:
	identify("wolverine")
	var c := start_combat("wolverine", "adult", "carcass")
	c.set_npc(wolverine())
	return c

func _wolverine_record(c: Combat) -> void:
	var npc := wolverine()
	var entry := {"age": snapped(wolf.age_years, 0.1), "outcome": c.outcome, "region": current_region, "context": c.context,
		"wolf_damage": snapped(c.damage_taken, 1.0), "npc_damage": snapped(c.opp_hp_max - c.opp_hp, 1.0), "gen": int(life_log.get("wolverine_gen", 1))}
	npc.add_record(entry.duplicate())
	var list: Array = life_log.get("wolverine_meetings", [])
	list.append(entry)
	life_log["wolverine_meetings"] = list

# --- 苔原狼（1.6 第 6e 步；一對跟著馴鹿遷徙的狼，沿用 NpcWolf） ---

const TUNDRA_WOLF_IDS := ["tundra_wolf", "tundra_wolf_mate"]

func _tundra_cfg() -> Dictionary:
	return NpcWolf.cfg("tundra_wolf").get("interaction", {})

# 還活著的苔原狼（0～2 隻），第一隻是帶頭的那隻。
func tundra_pair() -> Array:
	var list: Array = []
	for id in TUNDRA_WOLF_IDS:
		var npc: NpcWolf = npcs.get(id, null)
		if npc != null and npc.alive:
			list.append(npc)
	return list

func tundra_leader() -> NpcWolf:
	var pair := tundra_pair()
	return pair[0] if not pair.is_empty() else null

# 牠們現在在哪一區（死光了是空字串）。
func tundra_wolves_region() -> String:
	var leader := tundra_leader()
	return leader.territory if leader != null else ""

func _tundra_wolves_here() -> bool:
	return tundra_wolves_region() != "" and tundra_wolves_region() == current_region

# 依季節選牠們這陣子待的區域（兩隻一起行動）。
func _roam_tundra_wolves(force: bool = false) -> void:
	if tundra_pair().is_empty():
		return
	if not force and not RNGService.chance(float(_tundra_cfg().get("roam_change_per_day", 0.4))):
		return
	var weights: Dictionary = _tundra_cfg().get("roam", {}).get(GameTime.current_season(), {})
	if weights.is_empty():
		return
	var region: String = RNGService.weighted_pick(weights)
	for npc in tundra_pair():
		npc.territory = region

# 牠們來爭食的機率（敵視時更常來）。
func _tundra_carcass_chance() -> float:
	var c: float = float(_tundra_cfg().get("carcass_chance", 0.1))
	if tundra_relation_key() == "hostile":
		c *= float(_tundra_effects().get("hostile_carcass_mult", 2.0))
	return c

func tundra_relation() -> int:
	var leader := tundra_leader()
	return leader.relation if leader != null else 0

# 關係的程度：hostile（敵視）、wary（戒備）、familiar（熟悉）、friendly（友善）。
func tundra_relation_key() -> String:
	var levels: Dictionary = _tundra_cfg().get("relation", {}).get("levels", {})
	var r := tundra_relation()
	if r <= int(levels.get("hostile", -3)):
		return "hostile"
	if r >= int(levels.get("friendly", 6)):
		return "friendly"
	if r >= int(levels.get("familiar", 3)):
		return "familiar"
	return "wary"

func _tundra_effects() -> Dictionary:
	return _tundra_cfg().get("effects", {})

func _tundra_relation_add(kind: String) -> void:
	var delta: int = int(_tundra_cfg().get("relation", {}).get(kind, 0))
	# 避開只在還不熟的時候加分（一直避開不會變成好朋友）
	if kind == "avoid" and tundra_relation_key() in ["familiar", "friendly"]:
		delta = 0
	for npc in tundra_pair():
		npc.relation += delta

func _tundra_record(kind: String, outcome: String, wolf_damage: float = 0.0, npc_damage: float = 0.0) -> void:
	var entry := {"age": snapped(wolf.age_years, 0.1), "kind": kind, "outcome": outcome, "region": current_region,
		"wolf_damage": snapped(wolf_damage, 1.0), "npc_damage": snapped(npc_damage, 1.0), "pair": tundra_pair().size()}
	for npc in tundra_pair():
		npc.add_record(entry.duplicate())
	var list: Array = life_log.get("tundra_meetings", [])
	list.append(entry)
	life_log["tundra_meetings"] = list
	life_log["tundra_relation"] = tundra_relation()

# 深夜聽到牠們的嚎叫：牠們在同一區或相鄰的區域時。
func _maybe_tundra_howl() -> void:
	if GameTime.current_period() != "night" or tundra_pair().is_empty():
		return
	if not _tundra_wolves_here() and not adjacent_regions().has(tundra_wolves_region()):
		return
	if blizzard_active() or not _can_trigger_event():
		return
	if RNGService.chance(float(_tundra_cfg().get("howl_night_chance", 0.3))):
		_queue_event({"type": "tundra_howl", "region": tundra_wolves_region()})

# 回應嚎叫（關係 +）或保持安靜。
func tundra_howl_reply(reply: bool) -> void:
	record_decision("tundra.howl." + ("reply" if reply else "silent"))
	if reply:
		var key := tundra_relation_key()
		# 敵視時回應嚎叫只會把牠們引來；友善時牠們可能過來找你
		if key != "hostile":
			_tundra_relation_add("howl_reply")
		_tundra_record("howl", "replied")
		if key in ["hostile", "friendly"] and RNGService.chance(float(_tundra_effects().get("howl_come_chance", 0.3))):
			for npc in tundra_pair():
				npc.territory = current_region
			pending_events.append({"type": "tundra_come", "charge": key == "hostile"})
	state_changed.emit()

# 探索時在牠們所在的區域遇上。回傳 true 表示這次探索的發現換成遇上苔原狼。
func _maybe_meet_tundra_wolves() -> bool:
	if not _tundra_wolves_here() or blizzard_here():
		return false
	if not RNGService.chance(float(_tundra_cfg().get("meet_chance", 0.1))):
		return false
	current_discovery = {"kind": "tundra_wolves", "location": _random_terrain(current_region), "first": not is_identified("tundra_wolf"),
		"charge": tundra_relation_key() == "hostile" and RNGService.chance(float(_tundra_effects().get("hostile_charge", 0.35)))}
	identify("tundra_wolf")
	return true

# 避開：不起衝突的相遇，牠們會慢慢熟悉你。
func tundra_avoid() -> void:
	record_decision("avoid")
	_tundra_relation_add("avoid")
	_tundra_record("meet", "avoided")
	clear_discovery()
	state_changed.emit()

func tundra_follow_chance() -> float:
	var cfg := _tundra_cfg()
	return HuntSystem.clamp_chance(float(cfg.get("follow_base", 0.45)) + (wolf.effective_perception() - tundra_leader().perception) / float(cfg.get("follow_divisor", 150)))

# 跟隨：看清楚牠們和你相比的強弱；失敗被牠們發現，帶頭的那隻轉身對峙。
func tundra_follow() -> Dictionary:
	GameTime.advance_turns(1)
	var ok: bool = RNGService.chance(tundra_follow_chance())
	Growth.learn_flat(wolf, "perception", "track_perception", 1.0 if ok else float(Growth.cfg().get("fail_mult", 0.25)))
	if not ok:
		return {"success": false}
	var a := npc_assessment(tundra_leader())
	_tundra_record("follow", "assessed")
	state_changed.emit()
	return {"success": true, "assessment": a}

# 和牠們對峙或戰鬥。context：meet（遇上、挑戰）、carcass（牠們來爭你的獵物）。
# charge：牠們直接撲上來（敵視），從交鋒開始。
func start_tundra_combat(context: String, charge: bool = false) -> Combat:
	identify("tundra_wolf")
	clear_discovery()
	var c := start_combat("tundra_wolf", "adult", context)
	c.set_npc(tundra_leader())
	var key := tundra_relation_key()
	if tundra_pair().size() > 1:
		c.partner_chance = float(_tundra_effects().get("hostile_partner_chance", 0.3)) if key == "hostile" else float(_tundra_cfg().get("partner_chance", 0.2))
		c.partner_damage_mult = float(_tundra_cfg().get("partner_damage_mult", 0.6))
	if key == "familiar" and context == "carcass":
		c.stake_mult *= float(_tundra_effects().get("familiar_stake_mult", 0.7))
	if charge:
		c.phase = Combat.Phase.EXCHANGE
	return c

# 友善時遇上：走近牠們，陪牠們走一段（關係 +1）；馴鹿在這一區出沒的季節，牠們可能帶你找到馴鹿。
# 回傳 {"lead": true} 時 current_discovery 是目擊到的馴鹿（接著可以狩獵）。
func tundra_approach() -> Dictionary:
	clear_discovery()
	GameTime.advance_turns(1)
	record_decision("tundra.approach")
	_tundra_relation_add("howl_reply")
	_tundra_record("meet", "approached")
	var caribou_here: bool = float(EncounterSystem.region_data(current_region).get("prey_weights", {}).get("caribou", {}).get(GameTime.current_season(), 0)) > 0.0
	if caribou_here and RNGService.chance(float(_tundra_effects().get("friendly_lead_chance", 0.5))):
		current_discovery = {"kind": "clue", "source_kind": "prey", "source": "caribou", "clue": "sight", "location": "open_tundra",
			"fresh": true, "fresh_known": true, "wind": "crosswind", "prey_dir": RNGService.randi_range(0, 3), "life_stage": "adult", "led": true}
		state_changed.emit()
		return {"lead": true}
	state_changed.emit()
	return {"lead": false}

# 友善時爭食：牠們不動手，在旁邊等。share：讓牠們一起吃（失去 1 段，關係 +1）；否則繼續吃。
func tundra_wait_choice(share: bool) -> void:
	record_decision("tundra.wait." + ("share" if share else "keep"))
	if share and not current_feeding.is_empty():
		current_feeding["segments_left"] = int(current_feeding["segments_left"]) - 1
		if int(current_feeding["segments_left"]) <= 0:
			current_feeding = {}
		_tundra_relation_add("guard_together")
	_tundra_record("carcass", "shared" if share else "kept")
	state_changed.emit()

# 戰鬥後：關係值、紀錄、生死。威嚇或動手過就是起了衝突（關係 −）；讓牠們先吃、一起守著屍體、退開則是不起衝突。
func _after_tundra_combat(c: Combat) -> void:
	var leader: NpcWolf = c.npc
	leader.health = c.opp_hp
	var fought: bool = c.decisions.any(func(d): return d in ["combat.threaten", "combat.attack", "combat.bite", "combat.lunge", "combat.pursue"])
	_tundra_record(c.context, c.outcome, c.damage_taken, c.opp_hp_max - c.opp_hp)
	if fought:
		_tundra_relation_add("fight")
	elif c.outcome in ["let_eat", "guard_together", "yield"]:
		_tundra_relation_add(c.outcome)
	if c.outcome == "killed":
		_tundra_relation_add("killed")
	# 先記下關係值（兩隻都死了之後就讀不到了）
	life_log["tundra_relation"] = tundra_relation()
	if c.outcome == "killed":
		leader.die("killed_by_player")
		_on_npc_died(leader)

# --- 苔原狼圍攻狼獾（兩隻苔原狼都在、狼獾還活著） ---

func _mob_cfg() -> Dictionary:
	return _tundra_cfg().get("mob", {})

func _maybe_tundra_mob() -> bool:
	if not _tundra_wolves_here() or tundra_pair().size() < 2 or not _wolverine_alive() or blizzard_here():
		return false
	if not RNGService.chance(float(_mob_cfg().get("mob_chance", 0.05))):
		return false
	current_discovery = {"kind": "tundra_mob", "location": _random_terrain(current_region),
		"wolverine_known": is_identified("wolverine"), "tundra_known": is_identified("tundra_wolf")}
	identify("wolverine")
	identify("tundra_wolf")
	return true

# 幫苔原狼：從交鋒開始，狼獾已經被咬傷，苔原狼每回合也會咬牠。
func start_mob_combat() -> Combat:
	clear_discovery()
	var c := start_combat("wolverine", "adult", "mob")
	c.set_npc(wolverine())
	var m := _mob_cfg()
	c.opp_hp = min(c.opp_hp, c.opp_hp_max * float(m.get("start_hp_ratio", 0.7)))
	c.ally_chance = float(m.get("ally_chance", 0.5))
	c.ally_damage = m.get("ally_damage", [6, 10])
	c.phase = Combat.Phase.EXCHANGE
	return c

# 幫忙之後：趕走狼獾，苔原狼把殘骸分你一段（關係 +3）；撤退也算有幫（+1）；動手的對象不是牠們，不算衝突。
func _after_mob_combat(c: Combat) -> void:
	var won: bool = c.won()
	_tundra_relation_add("help_won" if won else "help_tried")
	_tundra_record("mob", "helped_won" if won else "helped_" + c.outcome, c.damage_taken, c.opp_hp_max - c.opp_hp)
	if won and tundra_relation_key() != "hostile":
		var segments: int = int(_mob_cfg().get("share_segments", 1))
		var total: float = float(GameData.animals.get("caribou", {}).get("adult", {}).get("hunger_value", 0))
		var per: int = HuntSystem.feeding_segments("caribou", "adult")
		current_feeding = {"animal_id": "caribou", "life_stage": "adult", "segments_left": segments,
			"segment_value": total / max(1, per), "turns_stayed": 0, "terrain": c.terrain, "shared": true}

# 在旁邊看：多半是狼獾被趕走，偶爾被咬死。回傳 {"result": "drove_off"|"killed"|"held"}。
func watch_tundra_mob() -> Dictionary:
	clear_discovery()
	GameTime.advance_turns(1)
	var m := _mob_cfg()
	var result: String = "held"
	var roll: float = RNGService.randf()
	if roll < float(m.get("watch_kill", 0.1)):
		result = "killed"
		var npc := wolverine()
		npc.die("tundra_wolves")
		_on_npc_died(npc)
	elif roll < float(m.get("watch_kill", 0.1)) + float(m.get("watch_drive_off", 0.7)):
		result = "drove_off"
	record_decision("tundra.mob.watch")
	_tundra_record("mob", "watched_" + result)
	Growth.learn_flat(wolf, "perception", "track_perception")
	state_changed.emit()
	return {"result": result}

func leave_tundra_mob() -> void:
	clear_discovery()
	record_decision("tundra.mob.leave")

# 回家的下一步（自動遊玩用）：往 target 走的相鄰區域（含跨地圖連接），已經在 target 或走不到就回傳空字串。
func next_step_toward(target: String) -> String:
	if current_region == target:
		return ""
	var prev: Dictionary = {current_region: ""}
	var frontier: Array = [current_region]
	while not frontier.is_empty():
		var next: Array = []
		for r in frontier:
			var neighbors: Array = EncounterSystem.region_data(str(r)).get("adjacent", []).duplicate()
			for link in GameData.links_from(str(r)):
				neighbors.append(link["to"])
			for n in neighbors:
				if prev.has(n):
					continue
				prev[n] = r
				if n == target:
					var step: String = str(n)
					while str(prev[step]) != current_region:
						step = str(prev[step])
					return step
				next.append(n)
		frontier = next
	return ""

# --- Debug helpers (see DESIGN.md "測試與除錯") ---

func debug_set_stat(stat_name: String, value: float) -> void:
	if wolf == null:
		return
	match stat_name:
		"health": wolf.health = value
		"health_max": wolf.health_max = value
		"stamina": wolf.stamina = value
		"speed": wolf.speed = value
		"strength": wolf.strength = value
		"skill": wolf.skill = value
		"perception": wolf.perception = value
		"hunger": wolf.hunger = value
		"health_value": wolf.health_value = value
		"age_years": wolf.age_years = value
	wolf.clamp_stats()
	state_changed.emit()

# 除錯「模擬到死亡」跑到年齡上限時，直接結束這一生。
func debug_end_life(cause: String) -> void:
	_die(cause)

func debug_skip_day() -> void:
	GameTime.advance_turns(GameTime.TURNS_PER_PERIOD * GameTime.PERIODS.size())
	state_changed.emit()

func debug_skip_to_next_season() -> void:
	# 跳到這一季的天數到期，再直接換季（除錯用，不必睡覺、不管大火或暴風雪）
	var guard := 0
	while not GameTime.season_due() and guard < 40:
		if wolf != null and not wolf.alive:
			break
		GameTime.advance_turns(GameTime.TURNS_PER_PERIOD * GameTime.PERIODS.size())
		guard += 1
	if wolf != null and wolf.alive:
		_change_season()
	state_changed.emit()

# 跳年齡：以季為單位增加年齡，每季照常套用老年衰退，但不推進遊戲時間。
func debug_add_age(years: float) -> void:
	if wolf == null:
		return
	var steps := int(round(years / 0.25))
	for i in range(steps):
		var prev_stage: int = wolf.life_stage()
		wolf.age_years += 0.25
		_apply_elder_decay()
		_check_life_stage_transition(prev_stage)
	log_message.emit(tr("log.debug.age").replace("{age}", "%.2f" % wolf.age_years))
	state_changed.emit()

func debug_jump_to_stage(stage: int) -> void:
	if wolf == null or wolf.life_stage() >= stage:
		return
	var ages: Dictionary = GameData.balance.get("life_stage_ages", {})
	var target: float = float(ages.get("subadult_end", 2.0)) if stage == Wolf.LifeStage.ADULT else float(ages.get("adult_end", 6.0))
	debug_add_age(ceil((target - wolf.age_years) / 0.25 - 0.0001) * 0.25)

# 跳到老年前一天：年齡加到再過一季就進入老年，日期跳到這一季的最後一天（不經過中間的日子）。
func debug_jump_to_elder_eve() -> void:
	if wolf == null or wolf.life_stage() == Wolf.LifeStage.ELDER:
		return
	var adult_end: float = float(GameData.balance.get("life_stage_ages", {}).get("adult_end", 6.0))
	var steps: int = int(ceil((adult_end - 0.25 - wolf.age_years) / 0.25 - 0.0001))
	if steps > 0:
		debug_add_age(steps * 0.25)
	GameTime.day = GameTime._season_day_count()
	state_changed.emit()

# 是否在次成年期的最後一天（再換季就成年）。
func is_last_subadult_day() -> bool:
	var subadult_end: float = float(GameData.balance.get("life_stage_ages", {}).get("subadult_end", 1.16))
	return wolf.life_stage() == Wolf.LifeStage.SUBADULT and wolf.age_years + 0.25 >= subadult_end \
		and GameTime.day >= GameTime._season_day_count()

# 強制顯示成年／老年轉變卡片（成年會用目前的能力值重新結算潛力）。
func debug_force_transition(stage: String) -> void:
	if wolf == null:
		return
	if stage == "adult":
		_settle_adulthood()
	else:
		_queue_notice({"type": "elder_transition"})
	state_changed.emit()

# 舊傷發作：沒有舊傷就先加一個（左後腿），然後發作兩天並顯示換日摘要卡片。
func debug_old_injury_flare() -> void:
	if wolf == null:
		return
	if wolf.old_injuries.is_empty():
		wolf.old_injuries.append({"part": "leg", "part_key": "injury_part.leg.left", "stat": "speed",
			"source": "grizzly_bear.carcass", "age": snapped(wolf.age_years, 0.1)})
	wolf.flare_index = 0
	wolf.flare_days = 2
	_queue_notice({"type": "day_summary", "day": int(life_log.get("days_lived", 1)),
		"lines": [{"key": "day_summary.old_injury_flare", "part": str(wolf.old_injuries[0]["part_key"])}]})
	state_changed.emit()

# 森林大火：從指定區域（空字串＝隨機）開始徵兆，下一個時段起火。
func debug_start_fire(origin: String) -> void:
	if not fire.is_empty():
		return
	start_fire_warning(origin)
	state_changed.emit()

# 跳到下一個乾季：一直換季到夏季的第一天。
func debug_skip_to_dry_season() -> void:
	var guard := 0
	debug_skip_to_next_season()
	while GameTime.current_season() != str(_fire_cfg().get("dry_seasons", ["summer"])[0]) and guard < 4:
		debug_skip_to_next_season()
		guard += 1

# 苔原的事件（除錯）：暴風雪 1 個時段後開始；白矇天、渡鴉、河冰直接觸發。
func debug_start_blizzard() -> void:
	if not blizzard.is_empty():
		return
	start_blizzard_warning(1)
	state_changed.emit()

func debug_whiteout() -> void:
	whiteout_until = _abs_period() + 1
	_apply_env_perception()
	pending_events.append({"type": "whiteout"})
	state_changed.emit()

func debug_ravens() -> void:
	pending_events.append({"type": "ravens", "region": current_region})

func debug_ice_break() -> void:
	pending_events.append({"type": "ice_break"})

# 苔原狼（除錯）：把牠們移到目前的區域。meet 直接遇上；howl 深夜的嚎叫。
func debug_tundra_wolves_here() -> void:
	for npc in tundra_pair():
		npc.territory = current_region

func debug_tundra_meet() -> Dictionary:
	debug_tundra_wolves_here()
	current_discovery = {"kind": "tundra_wolves", "location": _random_terrain(current_region), "first": not is_identified("tundra_wolf")}
	identify("tundra_wolf")
	return current_discovery

func debug_tundra_mob() -> Dictionary:
	debug_tundra_wolves_here()
	if not _wolverine_alive():
		npcs["wolverine"] = NpcWolf.create("wolverine", "")
	current_discovery = {"kind": "tundra_mob", "location": _random_terrain(current_region),
		"wolverine_known": is_identified("wolverine"), "tundra_known": is_identified("tundra_wolf")}
	identify("wolverine")
	identify("tundra_wolf")
	return current_discovery

func debug_tundra_howl() -> void:
	pending_events.append({"type": "tundra_howl", "region": tundra_wolves_region()})

# 狼獾搶食（除錯）：先在這裡擺一具馴鹿讓狼吃。
func debug_wolverine_feed() -> void:
	start_feeding("caribou", "adult", _random_terrain(current_region))

# 陌生灰狼：當作已經遠距觀察過、而且到了可以互動的時機。
func debug_unlock_stranger() -> void:
	identify("stranger_wolf")
	life_log["stranger_observed"] = true
	life_log["stranger_unlock"] = "subadult"

func debug_export_playtest_log() -> String:
	return _write_playtest_log() if wolf != null else ""

func debug_animal_ids() -> Array:
	return GameData.animals.keys()

# 強制觸發遭遇：獵物回傳與「尋找獵物蹤跡」相同格式的結果，競爭動物直接發出遭遇訊號。
func debug_force_encounter(animal_id: String, life_stage: String) -> Dictionary:
	if not GameData.animals.get(animal_id, {}).has(life_stage):
		life_stage = "adult"
	var role: String = str(GameData.animals.get(animal_id, {}).get("type", ""))
	if role == "competitor":
		encounter_triggered.emit(prepare_bear_encounter({"encountered": true, "animal_id": animal_id, "life_stage": life_stage}))
		return {}
	return {"found": true, "animal_id": animal_id, "life_stage": life_stage}

# --- Persistence ---

func _npcs_to_dict() -> Dictionary:
	var d: Dictionary = {}
	for npc_id in npcs.keys():
		d[npc_id] = npcs[npc_id].to_dict()
	return d

func to_dict() -> Dictionary:
	return {
		"wolf": wolf.to_dict() if wolf != null else {},
		"den_region": den_region,
		"current_region": current_region,
		"found_sleep_spots": found_sleep_spots,
		"rng_seed": rng_seed,
		"region_depletion": region_depletion,
		"wind_dir": wind_dir,
		"region_knowledge": region_knowledge,
		"carcasses": carcasses,
		"knowledge": knowledge,
		"identified": identified,
		"stranger_territory": stranger_territory,
		"territory_periods": territory_periods,
		"npcs": _npcs_to_dict(),
		"fire": fire,
		"region_burn": region_burn,
		"fire_at": fire_at,
		"fire_season": fire_season,
		"last_fire_abs": last_fire_abs,
		"blizzard": blizzard,
		"blizzard_at": blizzard_at,
		"whiteout_until": whiteout_until,
		"weather": weather,
		"weather_until": weather_until,
		"events_today": events_today,
		"life_log": life_log,
		"time": {
			"season_index": GameTime.season_index,
			"day": GameTime.day,
			"period_index": GameTime.period_index,
			"turn_in_period": GameTime.turn_in_period,
			"time_mode": GameTime.time_mode,
		},
	}

func load_from_dict(data: Dictionary) -> void:
	wolf = Wolf.from_dict(data.get("wolf", {}))
	den_region = data.get("den_region", "")
	current_region = data.get("current_region", den_region)
	found_sleep_spots = data.get("found_sleep_spots", {})
	rng_seed = int(data.get("rng_seed", 0))
	RNGService.set_seed(rng_seed)
	life_log = data.get("life_log", {})
	region_depletion = data.get("region_depletion", {})
	wind_dir = int(data.get("wind_dir", 0))
	region_knowledge = data.get("region_knowledge", {den_region: {"visited": true, "features": []}})
	current_discovery = {}
	current_feeding = {}
	carcasses = data.get("carcasses", [])
	knowledge = data.get("knowledge", {})
	identified = data.get("identified", GameData.knowledge.get("identified_at_start", []).duplicate())
	stranger_territory = str(data.get("stranger_territory", "forest_north"))
	territory_periods = int(data.get("territory_periods", 0))
	fire = data.get("fire", {})
	region_burn = data.get("region_burn", {})
	fire_at = int(data.get("fire_at", -1))
	fire_season = str(data.get("fire_season", ""))
	last_fire_abs = int(data.get("last_fire_abs", -100000))
	npcs = {}
	for npc_id in data.get("npcs", {}).keys():
		npcs[npc_id] = NpcWolf.from_dict(data["npcs"][npc_id])
	if not npcs.has("stranger_wolf"):
		npcs["stranger_wolf"] = NpcWolf.create("stranger_wolf", stranger_territory)
	if not npcs.has("wolverine"):
		npcs["wolverine"] = NpcWolf.create("wolverine", "")
	for id in TUNDRA_WOLF_IDS:
		if not npcs.has(id):
			npcs[id] = NpcWolf.create(id, "")
	blizzard = data.get("blizzard", {})
	blizzard_at = int(data.get("blizzard_at", -1))
	whiteout_until = int(data.get("whiteout_until", -1))
	weather = str(data.get("weather", "clear"))
	weather_until = int(data.get("weather_until", -1))
	events_today = int(data.get("events_today", 0))
	pending_events = []
	var t: Dictionary = data.get("time", {})
	GameTime.time_mode = t.get("time_mode", "normal")
	GameTime.season_index = int(t.get("season_index", 3))
	GameTime.day = int(t.get("day", 1))
	GameTime.period_index = int(t.get("period_index", 0))
	GameTime.turn_in_period = int(t.get("turn_in_period", 0))
	_connect_time_signals()
	_apply_env_perception()
	state_changed.emit()
