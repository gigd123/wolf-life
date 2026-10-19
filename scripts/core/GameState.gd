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
# 雪況（1.8 第 2 步）：{地圖: "none"|"light"|"deep"|"crust"}，每天依季節與日子決定。存檔。
var snow: Dictionary = {}
# 會延續的個體（Phase 1.7b 探索改版）：[{id, region, animal, stage, trait, until}]，until 是 days_lived 的期限。存檔。
var notables: Array = []
var hunting_notable: int = 0 # 正在獵的是哪一頭（獵到就從 notables 移除）
var routine_running: bool = false # 「照常過日子」代為行動中：知識最多累積到「通常」
var territory_periods: int = 0
# 具名 NPC 狼（SPEC 1.6「陌生灰狼」）：{id: NpcWolf}。陌生灰狼的範圍同步在 stranger_territory（牠死了就是空字串）。
var npcs: Dictionary = {}
# 黑狼家族（Phase 3a）：一對、狼群、領域、換代；帶頭的是 pack_leader()。存檔。
var black_pack: WolfPack = WolfPack.new()
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
	notables = []
	snow = {}
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
	black_pack = WolfPack.new()
	black_pack.regions = [stranger_territory] if stranger_territory != "" else []
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
	# 雪兔的族群週期（1.8 第 6 步）：從隨機一年開始
	life_log["hare_year"] = RNGService.randi_range(0, GameData.balance.get("hare_cycle", {}).get("mult", [1.0]).size() - 1)
	_roll_year()
	_start_year_stats()
	_apply_start_map_bonus(start_den)
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
	# 年度回顧：差點死掉（血量掉到 15% 以下）
	if wolf.health < wolf.health_max * 0.15:
		_year_flag("near_death")
	# 這一季在各區域待了幾個時段（狐狸避開你常待的區域，1.8 第 6 步）
	var rp: Dictionary = life_log.get("region_periods", {})
	rp[current_region] = int(rp.get(current_region, 0)) + 1
	life_log["region_periods"] = rp
	var decay: float = hunger_decay()
	wolf.hunger -= decay
	_digest_while_resting(decay)
	if not wolf.is_overfed():
		metrics()["gorged_now"] = false
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
	_update_snow()
	# 試玩指標：連續幾天沒有事件（提案之十二 E）
	var m := metrics()
	m["events"] = int(m.get("events", 0)) + events_today
	m["quiet_streak"] = 0 if events_today > 0 else int(m.get("quiet_streak", 0)) + 1
	m["longest_quiet"] = max(int(m.get("longest_quiet", 0)), int(m["quiet_streak"]))
	events_today = 0
	var before_injury: int = wolf.injury if wolf != null else Wolf.Injury.NONE
	var before_injury_stat: String = wolf.injury_stat if wolf != null else ""
	var before_poison: int = wolf.poison_days_remaining if wolf != null else 0
	_process_daily_recovery()
	_apply_daily_hunger_penalty()
	_queue_day_summary(before_injury, before_injury_stat, before_poison)
	_recover_region_depletion()
	_update_marks()
	_move_bison()
	_update_sleep_spots()
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
		_update_black_pack()
		_maybe_schedule_fire()
		_maybe_schedule_blizzard()
		if GameTime.current_season() == "spring":
			_new_year()
		_tundra_breeding_season()
		_roam_tundra_wolves(true)
		_update_snow() # 換季時日期直接歸 1、不經過換日：雪況在這裡結算，冬季第一天不會沿用秋末的
		life_log["region_periods"] = {}
		if GameTime.current_season() == "spring":
			var years: int = GameData.balance.get("hare_cycle", {}).get("mult", [1.0]).size()
			life_log["hare_year"] = (int(life_log.get("hare_year", 0)) + 1) % max(1, years)
		var fed_ratio: float = _season_fed_ratio()
		Growth.settle_season(wolf, fed_ratio)
		_apply_age_decay()
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
	if wolf == null or not wolf.alive:
		return
	# 自動玩家（模擬到死亡）不排字卡；照常過日子時留下重要的字卡，結束後顯示（睡醒的摘要不留，照常過日子的卡片已經寫了成長）
	if auto_playing and not (routine_running and AutoPlayer.ROUTINE_NOTICES.has(str(event.get("type", "")))):
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
	# 年況的徵兆（1.8 第 11 步）：不直接說，從季節卡片察覺
	var hint: String = "normal"
	# 老狼看得最準：秋天就感覺得到這個冬天（1.9b 第 2 步）
	if wolf != null and wolf.life_stage() == Wolf.LifeStage.ELDER and season == "autumn" and str(year_state().get("winter", "normal")) != "normal":
		lines.append({"key": "year.hint.elder.winter." + str(year_state()["winter"])})
	match season:
		"winter":
			hint = str(year_state().get("winter", "normal"))
		"summer":
			hint = str(year_state().get("summer", "normal"))
		"spring":
			hint = "hare_high" if hare_mult(false) >= 1.6 else ("hare_low" if hare_mult(false) <= 0.3 else "normal")
			# 從谷底回升的那年不說「少了很多」（文案稽核 2026-10-16）
			if hint == "hare_low" and hare_mult(false) > hare_mult_last_year():
				hint = "hare_low_rising"
	if hint != "normal":
		lines.append({"key": "year.hint.%s.%s" % [season, hint]})
	# 黑狼家族的變化（Phase 3a 第 2 步）：人在森林才寫，不在就留到回森林的那一季
	if current_map() == "forest" and life_log.has("pack_news"):
		var known: String = "known" if is_identified("stranger_wolf") else "unknown"
		for n in life_log["pack_news"]:
			lines.append({"key": "pack.news.%s.%s" % [n["event"], known], "region": str(n.get("region", ""))})
		life_log.erase("pack_news")
	_queue_notice({"type": "season_card", "season": season, "first": first, "lines": lines, "map": current_map(), "region": current_region, "review": review})

# 第一次在這個季節來到有自己季節卡片的地圖（苔原）：補一張卡片。
# 風雪停的時候人不在苔原：回到苔原時才跳「風雪之後」。
func _maybe_blizzard_aftermath() -> void:
	if life_log.has("blizzard_over_unseen") and current_map() == _blizzard_map() and not blizzard_active():
		var unseen: Dictionary = life_log["blizzard_over_unseen"]
		life_log.erase("blizzard_over_unseen")
		_queue_notice({"type": "blizzard_over", "kills": int(unseen.get("kills", 0)), "later": true})

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
	elif (gains.has("speed") or gains.has("strength")) and int(life_log.get("since_sleep", {}).get("chase", 0)) == 0 \
			and int(life_log.get("since_sleep", {}).get("fight", 0)) == 0:
		reason = str(cfg.get("reasons", {}).get("roam", ""))
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
			# 老了不再長：每季只說一次，不然每晚都同一句（試玩 BUG-12 截圖）
			var season_key: String = "%d" % int(round(wolf.age_years * 4.0)) # 年齡以季為單位增加
			if str(life_log.get("elder_none_season", "")) != season_key:
				life_log["elder_none_season"] = season_key
				reason = str(none.get("elder", ""))
		elif float(settle.get("points", 0.0)) < float(cfg.get("idle_points", 4)):
			reason = str(none.get("idle", ""))
		elif at_peak:
			reason = str(none.get("peak", ""))
		else:
			reason = str(none.get("small", ""))
	# 呈現方式由這裡決定（字卡分級 2026-10-16）：一般是淡出提示＋紀錄；
	# 挨餓長不起來只在連續挨餓的第一晚出卡片，之後幾晚只寫紀錄，等不再挨餓後才重新計算。
	var starved: bool = reason != "" and reason == str(cfg.get("reasons", {}).get("starved", ""))
	var card: bool = starved and not bool(life_log.get("sleep_starved", false))
	life_log["sleep_starved"] = starved
	return {"gains": gains, "amounts": amounts, "reason": reason, "card": card}

# 每個時段飽食度下降多少：次成年期另有數值（Phase 2b 第 5 步）。
func hunger_decay() -> float:
	var b: Dictionary = GameData.balance
	if wolf != null and wolf.life_stage() == Wolf.LifeStage.SUBADULT and b.has("hunger_decay_subadult"):
		return float(b["hunger_decay_subadult"])
	return float(b.get("hunger_decay_per_period", 4))

func _apply_age_decay() -> void:
	Growth.apply_age_decay(wolf)

# 生命階段轉變（SPEC 1.6「潛力與生命階段轉變」）：年齡改變後呼叫。
# 進入成年時結算潛力並顯示成年卡片；進入老年時顯示老年卡片。
func _check_life_stage_transition(prev_stage: int) -> void:
	if wolf == null:
		return
	var stage: int = wolf.life_stage()
	# 一歲：身體已經和成年的狼一樣高，接下來長的是技巧與判斷（Phase 1.7b）
	var yearling: float = float(GameData.balance.get("life_stage_ages", {}).get("yearling", 1.0))
	if stage == Wolf.LifeStage.SUBADULT and wolf.age_years >= yearling and not life_log.has("yearling_age"):
		life_log["yearling_age"] = snapped(wolf.age_years, 0.01)
		_queue_notice({"type": "yearling"})
	if prev_stage == Wolf.LifeStage.SUBADULT and stage != Wolf.LifeStage.SUBADULT:
		_settle_adulthood()
	if prev_stage != Wolf.LifeStage.ELDER and stage == Wolf.LifeStage.ELDER:
		life_log["elder_age"] = snapped(wolf.age_years, 0.01)
		_queue_notice({"type": "elder_transition"})
		_schedule_challenger(_elder_cfg().get("challenger", {}).get("first_days", [5, 15]))

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
	# 成年那一刻的能力值（含成年的成長），一生回顧與試玩紀錄用來比較兩隻狼；死亡時的能力值已經過老年衰退
	var adult_stats: Dictionary = {"age": snapped(wolf.age_years, 0.01)}
	for stat in Growth.ALL_STATS:
		adult_stats[stat] = snapped(float(wolf.get(stat)), 0.1)
	life_log["adult_stats"] = adult_stats
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
	# 傷勢只在睡覺時好轉（1.7 第 2 步）：這一天睡過才減，休養得好減更多、挨餓不減
	if wolf.injury_days_remaining > 0 and _sleep_heal >= 0:
		wolf.injury_days_remaining -= _sleep_heal
		if wolf.injury_days_remaining <= 0:
			if wolf.injury == Wolf.Injury.HEAVY:
				_maybe_old_injury()
			wolf.clear_injury()
	_sleep_heal = -1
	_update_old_injury_flare()
	wolf.clamp_stats()
	_check_death()

# 這一天睡覺時的傷勢好轉天數（-1 = 還沒睡）；換日時結算。
var _sleep_heal: int = -1

# 正在休息或睡覺（短暫休息、休息到…、睡覺推進時間時為 true）：吃撐時消化較快（Phase 2b 第 1 步）。
var _resting: bool = false

# 吃撐時在巢穴、睡處或自己的殘骸旁休息，超過門檻的部分消化較快（不會消化到門檻以下）；並記下吃撐的時段數（試玩指標）。
func _digest_while_resting(base_decay: float) -> void:
	if wolf == null or not wolf.is_overfed():
		return
	var g: Dictionary = GameData.balance.get("gorged", {})
	var m := metrics()
	m["gorged_periods"] = int(m.get("gorged_periods", 0)) + 1
	if not bool(m.get("gorged_now", false)):
		m["gorged_spells"] = int(m.get("gorged_spells", 0)) + 1
	m["gorged_now"] = true
	if _resting and (sleep_quality() != "rough" or carcass_index_here() >= 0):
		var extra: float = base_decay * (float(g.get("rest_digest_mult", 1.0)) - 1.0)
		wolf.hunger = max(float(GameData.balance.get("overfed_threshold", 120)), wolf.hunger - extra)

func _heal_progress(quality: String) -> int:
	var h: Dictionary = GameData.balance.get("sleep", {}).get("heal", {})
	if wolf.hunger < float(h.get("starving_hunger", 30)):
		return int(h.get("starving", 0))
	if quality in ["den", "good"] and wolf.hunger >= float(h.get("good_hunger", 60)):
		return int(h.get("good", 2))
	return int(h.get("normal", 1))

# 帶傷硬撐（1.7 第 2 步）：開打前就是重傷，打完一場戰鬥或狩獵的搏鬥，有機率多養幾天。
func _push_on_injury(start_heavy: bool) -> void:
	if not start_heavy or wolf.injury != Wolf.Injury.HEAVY:
		return
	var p: Dictionary = GameData.balance.get("sleep", {}).get("push_on", {})
	if RNGService.chance(float(p.get("chance", 0.5))):
		wolf.injury_days_remaining = min(int(p.get("max_days", 7)), wolf.injury_days_remaining + int(p.get("days", 1)))
		life_log["pushed_on"] = int(life_log.get("pushed_on", 0)) + 1
		log_message.emit(tr("log.injury_pushed_on"))

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
	# 白天休息的效果好（Phase 2b 第 4 步）
	amount *= float(GameData.balance.get("hunt", {}).get("period", {}).get("rest_stamina_mult", {}).get(GameTime.current_period(), 1.0))
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
	var actions: Array[String] = ["explore", "explore_modes", "find_sleep_spot", "short_rest", "rest_until", "sleep"]
	if can_routine():
		actions.append("routine")
	var region: Dictionary = EncounterSystem.region_data(current_region)
	if not region.get("gather_weights", {}).is_empty():
		actions.append("gather")
	if carcass_index_here() >= 0:
		actions.append("return_to_carcass")
	if can_make_den_here():
		actions.append("make_den")
	if can_mark_here():
		actions.append("mark")
	if can_lie_down():
		actions.append("lie_down")
	return actions

# --- 美洲獅、黑熊（Phase 2 第 3 步）---
func _cougar_cfg() -> Dictionary:
	return GameData.balance.get("cougar", {})

func _black_bear_cfg() -> Dictionary:
	return GameData.balance.get("black_bear", {})

# 黑熊在這一區、這一季出沒的倍率（冬眠時 0）
func black_bear_mult() -> float:
	var cfg := _black_bear_cfg()
	if not cfg.get("seasons", []).has(GameTime.current_season()):
		return 0.0
	return float(cfg.get("regions", {}).get(current_region, 0.0))

func _coyote_cfg() -> Dictionary:
	return GameData.balance.get("coyote", {})

# 郊狼在這一區的倍率：你常待的區域郊狼少（同狐狸）
func coyote_mult() -> float:
	var m: float = float(_coyote_cfg().get("regions", {}).get(current_region, 0.0))
	if current_region == bison_region():
		m *= float(_migration_cfg().get("bison", {}).get("coyote_mult", 1.5))
	if m > 0.0 and int(life_log.get("region_periods", {}).get(current_region, 0)) >= int(_feeding_cfg().get("fox", {}).get("frequent_periods", 12)):
		m *= float(_coyote_cfg().get("frequent_mult", 0.5))
	return m

# --- 猞猁、季節遷徙（Phase 2 第 6 步）---
func _lynx_cfg() -> Dictionary:
	return GameData.balance.get("lynx", {})

func _migration_cfg() -> Dictionary:
	return GameData.balance.get("migration", {})

func _maybe_lynx() -> bool:
	var here: float = float(_lynx_cfg().get("regions", {}).get(current_region, 0.0))
	if here <= 0.0 or blizzard_here():
		return false
	if not RNGService.chance(float(_lynx_cfg().get("chance", 0.04)) * here * clamp(hare_mult(false), 0.2, 2.0)):
		return false
	current_discovery = {"kind": "lynx", "location": _random_terrain(current_region), "has_kill": RNGService.chance(float(_lynx_cfg().get("kill_chance", 0.5))),
		"known": is_identified("lynx")}
	identify("lynx", false)
	return true

func start_lynx_combat() -> Combat:
	var d: Dictionary = current_discovery
	clear_discovery()
	var c := start_combat("lynx", "adult", "meet", {"location": str(d.get("location", ""))})
	c.set_meta("lynx_kill", bool(d.get("has_kill", false)))
	return c

# 遷徙的足跡：秋季後半往低處、春季前段往高處
func _maybe_migration_tracks() -> bool:
	var cfg := _migration_cfg()
	var season: String = GameTime.current_season()
	if season == "autumn" and GameTime.day < int(cfg.get("autumn_from_day", 5)):
		return false
	if season == "spring" and GameTime.day > int(cfg.get("spring_until_day", 6)):
		return false
	var to: String = str(cfg.get("regions", {}).get(season, {}).get(current_region, ""))
	if to == "" or not RNGService.chance(float(cfg.get("track_chance", 0.1))):
		return false
	current_discovery = {"kind": "migration", "to": to, "season": season, "location": _random_terrain(current_region)}
	return true

func follow_migration() -> String:
	var to: String = str(current_discovery.get("to", ""))
	clear_discovery()
	record_decision("migration.follow")
	return to

# 野牛群這陣子在哪一區（每天可能換）
func bison_region() -> String:
	if not life_log.has("bison_region"):
		life_log["bison_region"] = str(RNGService.weighted_pick(_migration_cfg().get("bison", {}).get("herd_weights", {"grassland_plains": 1})))
	return str(life_log["bison_region"])

func _move_bison() -> void:
	var b: Dictionary = _migration_cfg().get("bison", {})
	if RNGService.chance(float(b.get("move_chance", 0.25))):
		life_log["bison_region"] = str(RNGService.weighted_pick(b.get("herd_weights", {"grassland_plains": 1})))

# 遷徙與野牛群對這一區獵物的倍率
func _migration_mults(region_id: String, result: Dictionary) -> void:
	var cfg := _migration_cfg()
	if GameData.map_of(region_id) == "grassland":
		var b: Dictionary = cfg.get("bison", {})
		result["bison"] = float(result.get("bison", 1.0)) * float(b.get("here_mult", 2.5) if region_id == bison_region() else b.get("elsewhere_mult", 0.3))
	if GameTime.current_season() == "autumn" and str(year_state().get("winter", "normal")) == "severe":
		var m: float = float(cfg.get("severe_meadow_mult", 0.4)) if region_id == "mountain_meadow" else (float(cfg.get("severe_foothills_mult", 1.3)) if region_id == "mountain_foothills" else 1.0)
		for a in ["elk", "mule_deer"]:
			result[a] = float(result.get(a, 1.0)) * m

func _cougar_here() -> float:
	return float(_cougar_cfg().get("regions", {}).get(current_region, 0.0))

# 探索時：美洲獅的伏擊（清晨、黃昏、深夜；次成年、老年、帶傷的狼更常被盯上），或發現牠藏起來的獵物
func _maybe_cougar() -> bool:
	var here: float = _cougar_here()
	if here <= 0.0 or blizzard_here():
		return false
	var cfg := _cougar_cfg()
	var vulnerable: bool = wolf.life_stage() != Wolf.LifeStage.ADULT or wolf.injury != Wolf.Injury.NONE
	if cfg.get("ambush_periods", []).has(GameTime.current_period()) \
			and RNGService.chance(float(cfg.get("ambush_chance", 0.006)) * here * (float(cfg.get("vulnerable_mult", 5.0)) if vulnerable else 1.0)):
		var d: Array = cfg.get("ambush_damage", [12, 24])
		var hit := FightRules.hurt_wolf(wolf, float(RNGService.randi_range(int(d[0]), int(d[1]))), FightRules.opponent_profile("cougar", "adult").get("parts", {}), "cougar.encounter", false)
		current_discovery = {"kind": "cougar_ambush", "location": _random_terrain(current_region), "damage": hit["damage"], "known": is_identified("cougar")}
		identify("cougar", false)
		life_log["cougar_ambushes"] = int(life_log.get("cougar_ambushes", 0)) + 1
		return true
	if RNGService.chance(float(cfg.get("cache_chance", 0.05)) * here):
		current_discovery = {"kind": "cougar_cache", "location": _random_terrain(current_region), "animal_id": str(RNGService.weighted_pick(cfg.get("cache_animals", {"mule_deer": 1}))),
			"known": is_identified("cougar")}
		return true
	return false

# 偷吃美洲獅藏起來的獵物：牠已經吃掉一段；吃的時候牠可能回來
func eat_cougar_cache() -> void:
	var d: Dictionary = current_discovery
	clear_discovery()
	record_decision("cougar.cache.eat")
	start_feeding(str(d.get("animal_id", "mule_deer")), "adult", str(d.get("location", "")))
	current_feeding["segments_left"] = max(1, int(current_feeding.get("segments_left", 1)) - 1)
	current_feeding["cougar"] = true
	life_log["cougar_caches"] = int(life_log.get("cougar_caches", 0)) + 1
	state_changed.emit()

func start_cougar_ambush_combat() -> Combat:
	var d: Dictionary = current_discovery
	clear_discovery()
	identify("cougar")
	return start_combat("cougar", "adult", "encounter", {"direct": true, "damage": float(d.get("damage", 0.0)), "location": str(d.get("location", ""))})

# --- 開局選地圖、睡處變差（Phase 2 第 7 步）---
func _apply_start_map_bonus(start_den: String) -> void:
	var map_id: String = GameData.map_of(start_den)
	var stats: Dictionary = GameData.balance.get("start_map", {}).get(map_id, {}).get("stats", {})
	for stat in stats.keys():
		wolf.set(stat, float(wolf.get(stat)) + float(stats[stat]))
	if stats.has("health_max"):
		wolf.health = wolf.health_max
	life_log["start_map"] = map_id

# 每天：記得的好睡處可能因暴風雪、春洪、其他動物而失去
func _update_sleep_spots() -> void:
	var cfg: Dictionary = GameData.balance.get("sleep_spot_loss", {})
	var season: String = GameTime.current_season()
	for region_id in region_knowledge.keys():
		if region_id == den_region or not region_knowledge[region_id].get("features", []).has("good_sleep_spot"):
			continue
		var causes: Dictionary = {"wear": float(cfg.get("base", 0.004))}
		if blizzard_active() and GameData.map_of(region_id) == _blizzard_map():
			causes["blizzard"] = float(cfg.get("blizzard", 0.08))
		var terrains: Array = EncounterSystem.region_data(region_id).get("terrains", [])
		if season == "spring" and terrains.any(func(t): return cfg.get("flood_terrains", []).has(t)):
			causes["flood"] = float(cfg.get("flood", 0.02))
		var bear: float = float(EncounterSystem.region_data(region_id).get("competitor_weights", {}).get("grizzly_bear", {}).get(season, 0))
		if bear > 0.0:
			causes["animal"] = bear * float(cfg.get("animal_per_weight", 0.004))
		var total: float = 0.0
		for k in causes.keys():
			total += float(causes[k])
		if RNGService.chance(total):
			var features: Array = region_knowledge[region_id]["features"]
			features.erase("good_sleep_spot")
			found_sleep_spots.erase(region_id)
			var lost: Dictionary = life_log.get("lost_sleep_spots", {})
			lost[region_id] = str(RNGService.weighted_pick(causes))
			life_log["lost_sleep_spots"] = lost
			# 人就在這一區：當下就說（2026-10-15 試玩回報 25）
			if region_id == current_region:
				_notice_lost_sleep_spot()

# 來到這一區時告訴你好睡處沒了（只說一次）
func _notice_lost_sleep_spot() -> void:
	var lost: Dictionary = life_log.get("lost_sleep_spots", {})
	if lost.has(current_region):
		log_message.emit(tr("sleep_spot.lost." + str(lost[current_region])).replace("{region}", tr("region." + current_region)))
		lost.erase(current_region)
		life_log["lost_sleep_spots"] = lost

# --- 老年（Phase 1.9b 第 2 步）---
func _elder_cfg() -> Dictionary:
	return GameData.balance.get("elder", {})

func challenger() -> NpcWolf:
	return npcs.get("challenger", null)

func _schedule_challenger(days: Array) -> void:
	life_log["challenger_day"] = int(life_log.get("days_lived", 1)) + RNGService.randi_range(int(days[0]), int(days[1]))

# 年輕的挑戰者該來了嗎（老年、到了日子）
func challenger_due() -> bool:
	if wolf == null or wolf.life_stage() != Wolf.LifeStage.ELDER or not life_log.has("challenger_day"):
		return false
	return int(life_log.get("days_lived", 1)) >= int(life_log["challenger_day"])

func _ensure_challenger() -> NpcWolf:
	if challenger() == null or not challenger().alive:
		npcs["challenger"] = NpcWolf.create("challenger", current_region)
		life_log["challenger_visits"] = 0
	return challenger()

# 牠找上門：探索時（在地盤時說要搶地盤）或吃東西時（搶殘骸）。回傳要不要觸發。
func _maybe_challenger_explore() -> bool:
	if not challenger_due() or blizzard_here() or not RNGService.chance(float(_elder_cfg().get("challenger", {}).get("explore_chance", 0.5))):
		return false
	_ensure_challenger()
	current_discovery = {"kind": "challenger", "location": _random_terrain(current_region), "first": int(life_log.get("challenger_visits", 0)) == 0,
		"territory": is_own_territory()}
	return true

func start_challenger_combat(context: String) -> Combat:
	clear_discovery()
	var npc := _ensure_challenger()
	var c := start_combat("challenger", "adult", context)
	c.set_npc(npc)
	return c

# 讓牠：殘骸讓給牠、或這一帶的地盤讓出；牠下次來得更快
func challenger_yield() -> void:
	record_decision("challenger.yield")
	clear_discovery()
	if not current_feeding.is_empty():
		current_feeding = {}
	if is_own_territory():
		var marks: Dictionary = life_log.get("marks", {})
		marks.erase(current_region)
		life_log["marks"] = marks
	_after_challenger(false)
	state_changed.emit()

# 每次牠來過：打贏了牠走，過一陣子再來而且更強；讓了或輸了，牠下次來得更快
# 年輕的狼上次之後有沒有變強（只有你上次打贏牠時才會，_after_challenger）。
func challenger_grew() -> bool:
	var list: Array = life_log.get("challenger_meetings", [])
	return not list.is_empty() and bool(list.back().get("won", false))

func _after_challenger(won: bool) -> void:
	var cfg: Dictionary = _elder_cfg().get("challenger", {})
	var npc := _ensure_challenger()
	life_log["challenger_visits"] = int(life_log.get("challenger_visits", 0)) + 1
	var list: Array = life_log.get("challenger_meetings", [])
	list.append({"age": snapped(wolf.age_years, 0.1), "won": won})
	life_log["challenger_meetings"] = list
	var days: Array = cfg.get("return_days", [10, 16])
	var mult: float = 1.0 if won else float(cfg.get("yield_return_mult", 0.6))
	_schedule_challenger([int(int(days[0]) * mult), int(int(days[1]) * mult)])
	if won:
		life_log["challenger_wins"] = int(life_log.get("challenger_wins", 0)) + 1
		var g: float = float(cfg.get("grow", 3))
		for stat in ["speed", "strength", "skill", "health_max"]:
			npc.set(stat, float(npc.get(stat)) + g)
	npc.health = npc.health_max

# 最後一章：很老、很虛弱時可以選擇「找一個安靜的地方躺下」
func can_lie_down() -> bool:
	if wolf == null or wolf.life_stage() != Wolf.LifeStage.ELDER:
		return false
	var cfg: Dictionary = _elder_cfg().get("lie_down", {})
	var adult_end: float = float(GameData.balance.get("life_stage_ages", {}).get("adult_end", 6.0))
	return wolf.age_years - adult_end >= float(cfg.get("min_elder_years", 3.0)) or wolf.health_max < float(cfg.get("max_health_below", 70))

func action_lie_down() -> void:
	record_decision("lie_down")
	life_log["lie_down_region"] = current_region
	_die("lay_down")

# --- 地盤（Phase 1.9b 第 1 步）---
# life_log["marks"]：{區域: 最後標記的那一天}；life_log["overmarked"]：{區域: true}（黑狼把牠的標記蓋在你的上面）
func _territory_cfg() -> Dictionary:
	return GameData.balance.get("territory", {})

func can_mark_here() -> bool:
	return wolf != null and wolf.life_stage() != Wolf.LifeStage.SUBADULT and not blizzard_here()

func own_territories() -> Array:
	var today: int = int(life_log.get("days_lived", 1))
	var fade: int = int(_territory_cfg().get("fade_days", 5))
	var list: Array = []
	var marks: Dictionary = life_log.get("marks", {})
	for r in marks.keys():
		if today - int(marks[r]) <= fade:
			list.append(r)
	return list

func is_own_territory(region_id: String = "") -> bool:
	return own_territories().has(current_region if region_id == "" else region_id)

# 這一區的標記還剩幾天（不是地盤就是 −1）
func mark_days_left(region_id: String) -> int:
	if not is_own_territory(region_id):
		return -1
	return int(_territory_cfg().get("fade_days", 5)) - (int(life_log.get("days_lived", 1)) - int(life_log.get("marks", {})[region_id]))

# 標記：最多 max_regions 個區域，超過時最舊的那一個不再補（直接移除）。回傳 "new"／"refresh"／"remark"（蓋回黑狼的標記）。
func action_mark() -> String:
	_record_action("mark")
	var cfg := _territory_cfg()
	GameTime.advance_turns(int(cfg.get("mark_turns", 1)))
	wolf.stamina -= float(cfg.get("mark_stamina", 2))
	wolf.clamp_stats()
	var marks: Dictionary = life_log.get("marks", {})
	var result: String = "refresh" if is_own_territory() else "new"
	var over: Dictionary = life_log.get("overmarked", {})
	if over.has(current_region):
		over.erase(current_region)
		life_log["overmarked"] = over
		result = "remark"
	# 淡掉的標記清掉；超過上限時拿掉最舊的
	for r in marks.keys():
		if not own_territories().has(r):
			marks.erase(r)
	if not marks.has(current_region) and marks.size() >= int(cfg.get("max_regions", 2)):
		var oldest: String = ""
		for r in marks.keys():
			if oldest == "" or int(marks[r]) < int(marks[oldest]):
				oldest = r
		marks.erase(oldest)
	marks[current_region] = int(life_log.get("days_lived", 1))
	life_log["marks"] = marks
	life_log["marks_made"] = int(life_log.get("marks_made", 0)) + 1
	state_changed.emit()
	return result

# 每天：黑狼可能把牠的標記蓋在你的地盤上（牠的範圍在你的地盤或相鄰時）
func _update_marks() -> void:
	var npc := stranger()
	if npc == null or not npc.alive or npc.yielded_to_player or stranger_territory == "":
		return
	var near: Array = EncounterSystem.region_data(stranger_territory).get("adjacent", [])
	for r in own_territories():
		if (r == stranger_territory or near.has(r)) and RNGService.chance(float(_territory_cfg().get("overmark_chance", 0.15))):
			var over: Dictionary = life_log.get("overmarked", {})
			over[r] = true
			life_log["overmarked"] = over

func is_overmarked(region_id: String = "") -> bool:
	return bool(life_log.get("overmarked", {}).get(current_region if region_id == "" else region_id, false)) and is_own_territory(region_id)

# 讓出：這一區不再是你的地盤
func yield_territory() -> void:
	record_decision("territory.yield")
	var marks: Dictionary = life_log.get("marks", {})
	marks.erase(current_region)
	life_log["marks"] = marks
	var over: Dictionary = life_log.get("overmarked", {})
	over.erase(current_region)
	life_log["overmarked"] = over
	clear_discovery()
	state_changed.emit()

# 去找牠：可以直接互動時是一場相遇（對峙），否則只是循著氣味找到牠的足跡
func seek_stranger_from_mark() -> Dictionary:
	record_decision("territory.seek")
	clear_discovery()
	if stranger_can_interact():
		return {"combat": start_stranger_combat("meet")}
	current_discovery = {"kind": "clue", "source_kind": "threat", "source": "stranger_wolf", "clue": "wolf_track", "location": _random_terrain(current_region),
		"fresh": true, "fresh_known": true, "wind": "crosswind", "prey_dir": RNGService.randi_range(0, 3), "life_stage": "adult"}
	return {"discovery": current_discovery}

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
	if GameTime.current_season() == "winter":
		mult *= float(year_effects("winter").get("cold_mult", 1.0))
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
	var big_river: String = big_river_crossing(target_region)
	# 大火：離開躲著的溪邊或巢穴就不算躲著；走回還在燒的區域要再提示一次（QA-28）
	if not fire.is_empty():
		if str(fire.get("sheltered", "")) == current_region and target_region != current_region:
			fire["sheltered"] = ""
		fire["alerted"].erase(target_region)
	current_region = target_region
	# 跨地圖（例如森林北部 ↔ 苔原南部）：回合較多、額外消耗體力（SPEC 1.6「苔原」6a）
	if link.is_empty():
		_spend_action_stamina("move_region")
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
	_notice_lost_sleep_spot()
	_note_den_smell()
	if wolf.alive:
		_apply_env_perception()
		_check_blizzard_here()
		_maybe_map_season_card()
		_maybe_blizzard_aftermath()
		if big_river != "":
			_after_big_river(big_river)
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

func action_explore(mode: String = "trail") -> Dictionary:
	_record_action("explore")
	if mode != "trail":
		record_decision("explore." + mode)
	var mc := ExploreSystem.mode_cfg(mode)
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("explore", 1)) + int(mc.get("turns", 0)))
	if not wolf.alive:
		return {}
	_spend_action_stamina("explore")
	wolf.stamina -= float(mc.get("stamina", 0))
	wolf.clamp_stats()
	Growth.train_activity(wolf, "explore")
	# 暴風雪中什麼都看不見，也不能狩獵
	if blizzard_here():
		current_discovery = {"kind": "nothing", "blizzard": true, "location": _random_terrain(current_region)}
		state_changed.emit()
		return current_discovery
	# 苔原狼：在牠們這陣子待的區域探索，有機會撞見牠們圍攻狼獾，或遇上牠們
	# 猞猁、遷徙的足跡（Phase 2 第 6 步）
	if _maybe_lynx() or _maybe_migration_tracks():
		state_changed.emit()
		return current_discovery
	# 美洲獅：伏擊、藏起來的獵物（Phase 2 第 3 步）
	if _maybe_cougar():
		state_changed.emit()
		return current_discovery
	# 年輕的挑戰者（1.9b 第 2 步）
	if _maybe_challenger_explore():
		state_changed.emit()
		return current_discovery
	# 黑狼的標記蓋在你的地盤上：在那一區探索時發現（1.9b 第 1 步）
	if is_overmarked() and RNGService.chance(0.6):
		current_discovery = {"kind": "overmarked", "location": _random_terrain(current_region)}
		state_changed.emit()
		return current_discovery
	if _maybe_tundra_den() or _maybe_tundra_mob() or _maybe_tundra_hunt() or _maybe_meet_tundra_wolves():
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
		"mode": mode,
		"berries_mult": float(year_effects("summer").get("berries", 1.0)),
		"lean_nothing": float(lean_effects().get("nothing_mult", 1.0)),
		"marks": _nearby_marks(),
		"notables": _notables_here(),
	})
	match current_discovery.get("kind", ""):
		"mark":
			Growth.learn_flat(wolf, "perception", "explore_perception")
		"feature":
			var knowledge: Dictionary = region_knowledge.get(current_region, {"visited": true, "features": []})
			knowledge["features"].append(current_discovery["feature_id"])
			region_knowledge[current_region] = knowledge
		"clue":
			Growth.learn_flat(wolf, "perception", "explore_perception")
			# 新鮮線索與直接目擊自動累積「獵物出沒」知識；陳舊線索要玩家選「記下」。
			if current_discovery.get("source_kind", "") == "prey" and (current_discovery.get("fresh", false) or not current_discovery.get("fresh_known", true)):
				_learn_prey_sighting(current_discovery["source"])
			# 看到受傷的成體：記下牠，幾天內在這一區可能再遇到（提案之十 D）
			if current_discovery.get("injured", false) and not current_discovery.get("again", false):
				_add_notable(current_discovery)
	state_changed.emit()
	return current_discovery

# --- 雪況（1.8 第 2 步）---
# 依 events.json 的 snow：每張地圖、每個季節的「早段／晚段」各有雪況的權重；苔原風大，硬雪殼比較多。
# 年況（第 11 步）可以再乘倍率（snow_year_mult）。
# 雪況逐日延續（2026-10-16 使用者選方案 A）：大多維持前一天，否則往這一段的權重擲出的目標走一級；
# 這一段不會有的雪況（權重 0）每天一定往目標走。冬季第一天至少淺雪（換季時也結算一次，不沿用秋末的雪況）。
const SNOW_NEXT := {"none": ["light"], "light": ["none", "deep", "crust"], "deep": ["light", "crust"], "crust": ["light", "deep"]}

func _update_snow() -> void:
	var cfg: Dictionary = GameData.events.get("snow", {})
	var season: String = GameTime.current_season()
	var phase: String = "early" if GameTime.day <= int(cfg.get("early_days", 4)) else "late"
	for map_id in GameData.maps().keys():
		var table: Dictionary = cfg.get("maps", {}).get(map_id, cfg.get("maps", {}).get("forest", {}))
		var w: Dictionary = _snow_year_weights(table.get(season + "_" + phase, table.get(season, {"none": 1})), season)
		var cur: String = str(snow.get(map_id, ""))
		var next: String
		if cur == "" or not SNOW_NEXT.has(cur):
			next = str(RNGService.weighted_pick(w))
		elif float(w.get(cur, 0.0)) > 0.0 and RNGService.chance(float(cfg.get("stay_chance", 0.7))):
			next = cur
		else:
			next = _snow_step(cur, str(RNGService.weighted_pick(w)))
		if season == "winter" and GameTime.day == 1 and next == "none":
			next = "light"
		snow[map_id] = next

# 往目標雪況走一級（最短的路的第一步）。
func _snow_step(cur: String, target: String) -> String:
	if cur == target:
		return cur
	var prev := {cur: ""}
	var queue: Array = [cur]
	while not queue.is_empty():
		var s: String = queue.pop_front()
		for n in SNOW_NEXT.get(s, []):
			if not prev.has(n):
				prev[n] = s
				queue.append(n)
	if not prev.has(target):
		return cur
	var step: String = target
	while str(prev[step]) != cur:
		step = str(prev[step])
	return step

# 年況（1.8 第 11 步）：冬季、秋末、春初的雪況依這一年的冬季
func _snow_year_weights(w: Dictionary, season: String) -> Dictionary:
	var fx: Dictionary = year_effects("winter").get("snow", {})
	if fx.is_empty() or season == "summer" or (season == "spring" and GameTime.day > 3) or (season == "autumn" and GameTime.day <= 5):
		return w
	var out: Dictionary = {}
	for k in w.keys():
		out[k] = float(w[k]) * float(fx.get(k, 1.0))
	return out

# --- 年況與年度回顧（1.8 第 11 步，提案之十二 A）---
func _year_cfg() -> Dictionary:
	return GameData.balance.get("year", {})

func year_state() -> Dictionary:
	return life_log.get("year", {"winter": "normal", "summer": "normal"})

# kind："winter" 或 "summer"：這一年那一季的效果（balance.year.effects）
func year_effects(kind: String) -> Dictionary:
	return _year_cfg().get("effects", {}).get(str(year_state().get(kind, "normal")), {})

func _roll_year() -> void:
	var cfg := _year_cfg()
	var winter: String = str(RNGService.weighted_pick(cfg.get("winter", {"normal": 1})))
	var streak: int = int(life_log.get("severe_streak", 0))
	if winter == "severe" and streak >= int(cfg.get("severe_max_streak", 2)):
		winter = "normal"
	life_log["severe_streak"] = streak + 1 if winter == "severe" else 0
	life_log["year"] = {"winter": winter, "summer": str(RNGService.weighted_pick(cfg.get("summer", {"normal": 1}))), "hare": int(life_log.get("hare_year", 0))}

# 春天：先結算去年（年度回顧卡），再決定今年的年況
func _new_year() -> void:
	var last: Dictionary = year_state()
	life_log["year_harsh"] = str(last.get("winter", "normal")) == "severe"
	life_log["year_mild_last"] = str(last.get("winter", "normal")) == "mild"
	_queue_year_review()
	_roll_year()
	_start_year_stats()

func _start_year_stats() -> void:
	var snap: Dictionary = {}
	for stat in SLEEP_SUMMARY_STATS:
		snap[stat] = float(wolf.get(stat)) if wolf != null else 0.0
	life_log["year_stats"] = {"kills": 0, "biggest": "", "biggest_stage": "", "heavy_start": wolf.heavy_injury_count if wolf != null else 0,
		"snap": snap, "flags": []}

func _year_flag(flag: String) -> void:
	var ys: Dictionary = life_log.get("year_stats", {})
	var flags: Array = ys.get("flags", [])
	if not flags.has(flag):
		flags.append(flag)
	ys["flags"] = flags
	life_log["year_stats"] = ys

# 一年的摘要：依優先順序挑一句總結，加上這一年的數字
func year_summary() -> Dictionary:
	var ys: Dictionary = life_log.get("year_stats", {})
	var flags: Array = ys.get("flags", [])
	var headline: String = "quiet"
	for f in ["near_death", "fire", "stranger_win", "big_prey", "den_moved", "tundra", "bear_steal", "hare_year"]:
		if flags.has(f) or (f == "hare_year" and hare_mult(false) >= 1.6):
			headline = f
			break
	var changes: Dictionary = {}
	var snap: Dictionary = ys.get("snap", {})
	for stat in SLEEP_SUMMARY_STATS:
		if snap.has(stat):
			changes[stat] = float(wolf.get(stat)) - float(snap[stat])
	return {"headline": headline, "kills": int(ys.get("kills", 0)), "biggest": str(ys.get("biggest", "")), "biggest_stage": str(ys.get("biggest_stage", "")),
		"heavy": wolf.heavy_injury_count - int(ys.get("heavy_start", 0)), "changes": changes, "year": year_state()}

func _queue_year_review() -> void:
	if wolf == null:
		return
	var n: int = int(life_log.get("year_no", 0)) + 1
	life_log["year_no"] = n
	var s := year_summary()
	s["n"] = n
	s["age"] = snapped(wolf.age_years, 0.1)
	var years: Array = life_log.get("years", [])
	years.append({"n": n, "age": s["age"], "headline": s["headline"], "kills": s["kills"], "biggest": s["biggest"], "biggest_stage": s["biggest_stage"],
		"heavy": s["heavy"], "winter": str(s["year"].get("winter", "normal")), "summer": str(s["year"].get("summer", "normal"))})
	life_log["years"] = years
	_queue_notice({"type": "year_review", "summary": s})

func snow_state(region_id: String = "") -> String:
	if region_id == "":
		region_id = current_region
	if snow.is_empty():
		_update_snow()
	return str(snow.get(GameData.map_of(region_id), "none"))

# 附近其他狼的氣味：黑狼的範圍在這一區或相鄰；苔原狼這陣子在這一區或相鄰。
func _nearby_marks() -> Array:
	var list: Array = []
	var near: Array = adjacent_regions().duplicate()
	near.append(current_region)
	var npc := stranger()
	if npc != null and npc.alive and stranger_territory != "" and near.has(stranger_territory):
		list.append({"who": "stranger_wolf", "region": stranger_territory})
	var t: String = tundra_wolves_region()
	if t != "" and near.has(t):
		list.append({"who": "tundra_wolf", "region": t})
	return list

func _notables_here() -> Array:
	var today: int = int(life_log.get("days_lived", 1))
	notables = notables.filter(func(n): return int(n.get("until", 0)) >= today)
	return notables.filter(func(n): return str(n.get("region", "")) == current_region)

func _add_notable(d: Dictionary) -> void:
	var id: int = int(life_log.get("next_notable_id", 1))
	life_log["next_notable_id"] = id + 1
	var entry := {"id": id, "region": current_region, "animal": str(d.get("source", "")), "stage": str(d.get("life_stage", "adult")),
		"trait": str(d.get("trait", "lame")), "until": int(life_log.get("days_lived", 1)) + int(GameData.discovery.get("notable", {}).get("days", 5))}
	notables.append(entry)
	current_discovery["notable_id"] = id

# 啃別人吃剩的殘骸（提案之十 B）：一點點飽食度、1 回合。
# 回傳 {"gain": 飽食度, "encounter": 撞見回來的灰熊（空的就是沒有）}；遭遇交給呼叫端，先寫完吃了多少再進遭遇。
func eat_remains() -> Dictionary:
	var tier: String = str(current_discovery.get("tier", "some"))
	current_discovery = {}
	GameTime.advance_turns(1)
	var cfg: Dictionary = GameData.discovery.get("remains_tiers", {}).get(tier, {})
	var range_: Array = cfg.get("hunger", [6, 6])
	var gain: int = RNGService.randi_range(int(range_[0]), int(range_[1]))
	_note_food("remains", gain)
	wolf.hunger += gain
	wolf.clamp_stats()
	record_decision("explore.remains")
	state_changed.emit()
	# 大半具、剛被放下的殘骸：牠可能就在附近，吃的時候撞見回來的灰熊
	var bear: float = float(EncounterSystem.region_data(current_region).get("competitor_weights", {}).get("grizzly_bear", {}).get(GameTime.current_season(), 0))
	var encounter: Dictionary = {}
	if bear > 0.0 and RNGService.chance(float(cfg.get("bear_chance", 0.0)) * threat_mult()):
		encounter = prepare_bear_encounter({"encountered": true, "animal_id": "grizzly_bear", "life_stage": "adult"})
	return {"gain": gain, "encounter": encounter}

# 探索到有值得注意的發現為止（提案之十 E）：最多 max_tries 次；回傳 {"discovery": 最後的發現, "skipped": [略過的發現]}。
func action_explore_until(mode: String = "trail") -> Dictionary:
	var skipped: Array = []
	var tries: int = int(GameData.discovery.get("until", {}).get("max_tries", 4))
	var d: Dictionary = {}
	for i in tries:
		d = action_explore(mode)
		if d.is_empty() or not wolf.alive or is_notable_discovery(d) or pending_events.size() > 0:
			break
		skipped.append(d)
		if i < tries - 1:
			clear_discovery()
	return {"discovery": d, "skipped": skipped}

# 照常過日子（Phase 1.7b，提案之十 E）：成年後才能用；大火、暴風雪、進食、遭遇中不能用。
func can_routine() -> bool:
	if wolf == null or not wolf.alive or wolf.life_stage() == Wolf.LifeStage.SUBADULT:
		return false
	if not fire.is_empty() or blizzard_here() or is_feeding() or not current_discovery.is_empty() or not pending_events.is_empty():
		return false
	return true

# 代為行動 days 天（沿用自動玩家），遇到值得注意的事就停下。回傳摘要：{reason, encounter, days, prey, nights}。
func run_routine(days: int, style: String) -> Dictionary:
	var before_prey: Dictionary = life_log.get("prey_count", {}).duplicate()
	var before_days: int = int(life_log.get("days_lived", 1))
	var before_den: int = int(life_log.get("stats", {}).get("nights", {}).get("den", 0))
	var before_wild: int = int(life_log.get("wild_nights", 0))
	var before_region: String = current_region
	var before_stats: Dictionary = {}
	for stat in SLEEP_SUMMARY_STATS:
		before_stats[stat] = float(wolf.get(stat))
	_record_action("routine")
	record_decision("routine." + style)
	auto_playing = true
	routine_running = true
	var ap := AutoPlayer.new("small_only", "cautious")
	ap.start_routine(days, style)
	var guard := 0
	while not ap.done() and guard < days + 2:
		ap.step(1)
		guard += 1
	if ap.stop_reason == "" and wolf.alive:
		ap.stop_reason = "done"
	ap.finish()
	routine_running = false
	var gained: Dictionary = {}
	for k in life_log.get("prey_count", {}).keys():
		var n: int = int(life_log["prey_count"][k]) - int(before_prey.get(k, 0))
		if n > 0:
			gained[k] = n
	# 摘要寫出這幾天的成長與走到哪裡（試玩回報 21、22）
	var growth: Dictionary = {}
	for stat in SLEEP_SUMMARY_STATS:
		var d: float = float(wolf.get(stat)) - float(before_stats[stat])
		if d >= 0.05:
			growth[stat] = d
	state_changed.emit()
	return {"reason": ap.stop_reason, "encounter": ap.stop_encounter, "scavenger": ap.stop_scavenger, "growth": growth,
		"moved_to": current_region if current_region != before_region else "", "days": int(life_log.get("days_lived", 1)) - before_days,
		"prey": gained, "den_nights": int(life_log.get("stats", {}).get("nights", {}).get("den", 0)) - before_den,
		"wild_nights": int(life_log.get("wild_nights", 0)) - before_wild, "alive": wolf.alive}

# 值得停下來的發現：新鮮可追的獵物、直接看到的獵物、危險的線索、殘骸、地點、其他狼、記著的那頭。
func is_notable_discovery(d: Dictionary) -> bool:
	match str(d.get("kind", "")):
		"nothing":
			return false
		"clue":
			if d.get("source_kind", "") == "gather":
				return false
			if d.get("source_kind", "") == "prey":
				return d.get("fresh", false) or d.get("clue", "") == "sight" or d.get("injured", false)
			return true
	return true

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
	_spend_action_stamina("track")
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
	hunting_notable = int(d.get("notable_id", 0))
	return {"success": true, "hunt": start_hunt(d["source"], d.get("life_stage", "adult"), int(d.get("prey_dir", -1)), true,
		str(d.get("location", "")), bool(d.get("injured", false)), bool(d.get("hidden", false)), _discovery_herd(d))}

# 直接目擊獵物：不用追蹤，直接進入狩獵（從潛近開始）。
func action_hunt_sighted() -> HuntSystem:
	var d: Dictionary = current_discovery
	current_discovery = {}
	hunting_notable = int(d.get("notable_id", 0))
	var h := start_hunt(d["source"], d.get("life_stage", "adult"), int(d.get("prey_dir", -1)), false,
		str(d.get("location", "")), bool(d.get("injured", false)), bool(d.get("hidden", false)), _discovery_herd(d))
	h.ambush_bonus = float(d.get("ambush", 0.0))
	return h

func _discovery_herd(d: Dictionary) -> int:
	return (1 if bool(d["herd"]) else 0) if d.has("herd") else -1

# 採集探索到的採集物。
func action_gather_discovered() -> String:
	var d: Dictionary = current_discovery
	current_discovery = {}
	if d.get("source_kind", "") != "gather":
		return ""
	var costs: Dictionary = GameData.balance.get("action_turn_costs", {})
	GameTime.advance_turns(int(costs.get("gather", 1)))
	if wolf.alive:
		_spend_action_stamina("gather")
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

# 灰熊的季節階段（1.8 第 7 步）：春季分春初、春、春末（各三分之一），其他照季節。
func bear_phase() -> String:
	var season: String = GameTime.current_season()
	if season != "spring":
		return season
	var n: int = int(GameData.balance.get("season_day_count", {}).get(GameTime.time_mode, 10))
	if GameTime.day <= n / 3:
		return "spring_early"
	if GameTime.day > n * 2 / 3:
		return "spring_late"
	return "spring"

func _bear_phase_cfg() -> Dictionary:
	return _bear_cfg().get("phases", {}).get(bear_phase(), {})

# 幼鹿季（春末、夏初）：灰熊也在找幼鹿
func _fawn_bear_season() -> bool:
	var f: Dictionary = _bear_cfg().get("fawn", {})
	var phase: String = bear_phase()
	if not f.get("phases", []).has(phase):
		return false
	return phase != "summer" or GameTime.day <= int(f.get("summer_days", 5))

# --- 從灰熊口中搶肉（1.8 第 7 步，提案之九）---
func _steal_cfg() -> Dictionary:
	return _bear_cfg().get("steal", {})

func bear_steal_chance(kind: String) -> float:
	var s: Dictionary = _steal_cfg().get(kind, {})
	var avg: float = (wolf.effective_speed() + wolf.effective_skill()) * 0.5
	var tries: int = int(current_feeding.get("steal_tries", 0))
	return HuntSystem.clamp_chance(float(s.get("base", 0.5)) + (avg - 60.0) / float(s.get("divisor", 150)) - float(s.get("per_try", 0.1)) * tries)

# 叼走的話能帶走幾段：小殘骸整個，大殘骸撕一條後腿（2～3 段）
func bear_carry_segments() -> int:
	var left: int = int(current_feeding.get("segments_left", 0))
	if HuntSystem.feeding_segments(str(current_feeding.get("animal_id", "")), str(current_feeding.get("life_stage", ""))) <= int(_steal_cfg().get("small_max_segments", 2)):
		return left
	var seg: Array = _steal_cfg().get("carry", {}).get("leg_segments", [2, 3])
	return min(left, int(seg[1]))

func bear_carry_is_whole() -> bool:
	return HuntSystem.feeding_segments(str(current_feeding.get("animal_id", "")), str(current_feeding.get("life_stage", ""))) <= int(_steal_cfg().get("small_max_segments", 2))

# kind："bite" 咬一塊就跑、"carry" 整個叼走（或撕一條後腿）。回傳 {"outcome", "damage", "gain"}。
func resolve_bear_steal(kind: String) -> Dictionary:
	identify("grizzly_bear")
	record_decision("scavenger." + kind)
	var s: Dictionary = _steal_cfg().get(kind, {})
	var chance: float = bear_steal_chance(kind)
	current_feeding["steal_tries"] = int(current_feeding.get("steal_tries", 0)) + 1
	GameTime.advance_turns(1)
	var res := {"outcome": kind + ".fail", "damage": 0.0, "gain": 0.0}
	if RNGService.chance(chance):
		var segs: int = 1
		if kind == "carry":
			var seg: Array = s.get("leg_segments", [2, 3])
			segs = int(current_feeding.get("segments_left", 0)) if bear_carry_is_whole() \
				else min(int(current_feeding.get("segments_left", 0)), RNGService.randi_range(int(seg[0]), int(seg[1])))
			res["outcome"] = "carry.whole" if bear_carry_is_whole() else "carry.leg"
		else:
			res["outcome"] = "bite.ok"
		var gain: float = float(current_feeding.get("segment_value", 0)) * segs
		_note_food("bear_steal:" + str(current_feeding.get("animal_id", "")), gain)
		wolf.hunger += gain
		res["gain"] = gain
		current_feeding["segments_left"] = int(current_feeding.get("segments_left", 0)) - segs
		life_log["bear_steals"] = int(life_log.get("bear_steals", 0)) + 1
		if int(life_log["bear_steals"]) == 1: # 第一次從灰熊口中搶到肉才算這一年的大事
			_year_flag("bear_steal")
		# 叼走就離開了；咬一塊之後熊還在，殘骸吃完也就結束
		if kind == "carry" or int(current_feeding["segments_left"]) <= 0:
			current_feeding = {}
	else:
		var parts: Dictionary = {"shoulder": 0.5, "leg": 0.5}
		if kind == "bite":
			if RNGService.chance(float(s.get("fail_hurt", 0.5))):
				var d: Array = s.get("damage", [5, 12])
				res["damage"] = float(FightRules.hurt_wolf(wolf, float(RNGService.randi_range(int(d[0]), int(d[1]))), parts, "grizzly_bear.steal", false)["damage"])
		else:
			# 熊追上來：獨狼很危險，已經帶傷時可能致命；苔原狼在旁邊會分散牠的注意
			var heavy: bool = RNGService.chance(float(s.get("fail_heavy", 0.55)))
			var d: Array = s.get("damage_heavy" if heavy else "damage_light", [10, 20])
			var dmg: float = float(RNGService.randi_range(int(d[0]), int(d[1])))
			if _tundra_wolves_here() and tundra_relation_key() == "friendly":
				dmg *= float(s.get("tundra_mult", 0.5))
			var lethal: bool = wolf.injury != Wolf.Injury.NONE
			if lethal:
				dmg *= float(s.get("injured_mult", 1.4))
			res["damage"] = float(FightRules.hurt_wolf(wolf, dmg, parts, "grizzly_bear.steal", lethal)["damage"])
			current_feeding = {}
			if wolf.health <= 0.0:
				die_in_combat("grizzly_bear", "adult", "steal")
				return res
	wolf.clamp_stats()
	_check_death()
	state_changed.emit()
	return res

func _abs_period() -> int:
	return int(life_log.get("days_lived", 1)) * GameTime.PERIODS.size() + GameTime.period_index

func _abs_turn() -> int:
	return _abs_period() * GameTime.TURNS_PER_PERIOD + GameTime.turn_in_period

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
	# 帶幼熊的母熊依季節（1.8 第 7 步：春初只有公熊，春末開始有母熊，秋季母熊先少）
	if e.get("life_stage", "adult") == "adult" \
			and RNGService.chance(float(_bear_phase_cfg().get("mother", 0.0))):
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
	identify(animal_id, animal_id != "stranger_wolf")
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
	# 照常過日子（代為行動）時，知識最多累積到「通常」，「確定」要自己經歷（Phase 1.7b）
	if routine_running and int(existing.get("count", 0)) + 1 >= int(GameData.knowledge.get("confirm_count", 3)):
		return int(existing.get("count", 0))
	existing["count"] = int(existing.get("count", 0)) + 1
	# 自己的地盤：這一區的事記得比較快（1.9b 第 1 步）
	if str(entry.get("region", "")) != "" and is_own_territory(str(entry["region"])) and not routine_running \
			and RNGService.chance(float(_territory_cfg().get("knowledge_bonus", 0.3))):
		existing["count"] = min(int(existing["count"]) + 1, int(GameData.knowledge.get("confirm_count", 3)))
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
# 第一次辨識寫「那是一頭灰熊。」（QA-54）；announce 為 false 時不寫（畫面已經有描述，例如遠遠觀察黑狼，QA-52）。
func identify(source: String, announce: bool = true) -> void:
	if not identified.has(source):
		identified.append(source)
		if announce:
			var key: String = "log.identified." + source
			var text: String = tr(key)
			if text == key:
				text = tr("log.identified").replace("{animal}", tr("animal." + source))
			log_message.emit(text)

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
		_spend_action_stamina("gather")
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
	_note_food("gather", float(effects.get("hunger", 0)))
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
	_spend_action_stamina("find_sleep_spot")
	var spot := ""
	if _feature_known_here("sleep_spot"):
		spot = "good"
	elif EncounterSystem.find_sleep_spot(current_region) or (is_own_territory() and RNGService.chance(float(_territory_cfg().get("sleep_bonus", 0.15)))):
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
	_resting = true
	GameTime.advance_turns(int(costs.get("short_rest", 2)))
	_resting = false
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
	# 至少休息一回合，再因為太餓停下（QA-68：已經很餓時原本一回合都沒休息就停）
	var start_turns: int = _abs_turn()
	var res := _rest_loop(func(): return not blizzard_here() or (wolf.hunger <= floor_hunger and _abs_turn() > start_turns), max_turns)
	if wolf.alive and str(res["interrupted"]) == "" and blizzard_here():
		res["interrupted"] = "hungry"
	return res

# 休息到消化完（Phase 2b 第 2 步）：吃撐時才能選，休息到不再吃撐（最多 REST_DIGEST_MAX_DAYS 天）。
const REST_DIGEST_MAX_DAYS := 3

func action_rest_digest() -> Dictionary:
	_record_action("rest_until")
	if wolf == null or not wolf.is_overfed():
		return {"alive": wolf != null and wolf.alive, "interrupted": ""}
	return _rest_loop(func(): return not wolf.is_overfed(), REST_DIGEST_MAX_DAYS * GameTime.PERIODS.size() * GameTime.TURNS_PER_PERIOD)

# 「休息到…」的選項（Phase 2b 第 2 步）：依目的列出，不再列出每個時段。
# 回傳 [{"id", "period"}]：dusk、dawn（好的狩獵時段，現在就是那個時段時不列）、digest（吃撐時）、blizzard（暴風雪中待在巢穴或好睡處）。
const REST_TARGET_PERIODS := ["dusk", "dawn"]

func rest_options() -> Array:
	var out: Array = []
	if can_rest_out_blizzard():
		out.append({"id": "blizzard"})
	if wolf != null and wolf.is_overfed():
		out.append({"id": "digest"})
	for p in REST_TARGET_PERIODS:
		if GameTime.current_period() != p:
			out.append({"id": "period", "period": p})
	return out

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
		_resting = true
		GameTime.advance_turns(1)
		_resting = false
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

# 巢穴有多隱蔽：地圖的 den_hidden（山地的巢穴藏在岩縫、峽谷裡，夜裡最不容易被找上；SPEC Phase 2「山地」）。不在巢穴時是 1。
func den_hidden_mult() -> float:
	if sleep_quality() != "den":
		return 1.0
	return float(GameData.maps().get(current_map(), {}).get("den_hidden", 1.0))

# 快轉每經過一個時段：獵物靠近、灰熊路過（在巢穴休息比在野外安全）。
func _rest_period_events(cfg: Dictionary, gained_stamina: float) -> void:
	var loc_mult: float = float(cfg.get("location_mult", {}).get(sleep_quality(), 1.0)) * den_hidden_mult()
	if _can_trigger_event() and RNGService.chance(float(cfg.get("prey_nearby_per_period", 0.06))):
		var pn: Dictionary = _events_cfg().get("prey_nearby", {})
		var animal: String = _nearby_prey_pick(pn)
		if animal != "":
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
	_sleep_heal = max(_sleep_heal, _heal_progress(quality))
	quiet_sleep = season_sleep
	_resting = true
	GameTime.advance_turns(turns)
	_resting = false
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
	# 1.7 第 2 步：輕傷回復 ×0.8；重傷回復 ×0.5，而且痊癒前最多回到血量上限的 70%（已經比較高就不扣）
	var health_mult: float = mult
	var health_target: float = wolf.health_max
	if wolf.injury == Wolf.Injury.HEAVY:
		health_mult *= float(cfg.get("heavy_injury_health_mult", 0.5))
		health_target = wolf.health_max * float(cfg.get("heavy_health_cap", 1.0))
	elif wolf.injury == Wolf.Injury.LIGHT:
		health_mult *= float(cfg.get("light_injury_health_mult", 1.0))
	wolf.health += max(0.0, health_target - wolf.health) * health_mult
	wolf.stamina += (smax - wolf.stamina) * mult
	wolf.clamp_stats()
	# 灰熊路過：在巢穴或睡處休息時（沒有被驚醒的情況下）。
	if not season_sleep and not encounter.get("encountered", false) and quality != "rough":
		_maybe_bear_passing(wolf.health - before_health, wolf.stamina - before_stamina, quality)
	var summary := sleep_summary(settle)
	var season_changed: bool = season_sleep and wolf.alive
	if season_changed:
		_change_season()
	_snapshot_sleep_stats()
	SaveSystem.save_game()
	state_changed.emit()
	if encounter.get("encountered", false):
		var woken := prepare_bear_encounter(encounter)
		woken["woken"] = true
		encounter_triggered.emit(woken)
	return {"quality": quality, "interrupted": encounter.get("encountered", false), "summary": summary, "season_changed": season_changed}

# 開始狩獵：依狩獵深度消耗回合（簡易 1、標準 2、完整 3）。
# from_tracking：經由追蹤找到獵物（追蹤的感知成長在 action_track 結算）。terrain：遭遇時的地形，空字串則隨機取區域的地形。
# injured：受傷個體，一律走簡易流程。
# herd：發現時決定的成不成群（-1 = 現在才擲，例如獵物靠近、苔原狼的狩獵）。
func start_hunt(animal_id: String, life_stage: String, prey_dir: int = -1, from_tracking: bool = false,
		terrain: String = "", injured: bool = false, hidden: bool = false, herd: int = -1) -> HuntSystem:
	var depth: String = "simple" if injured else HuntSystem.depth_of(animal_id, life_stage)
	_stat_inc("hunts_by_animal", animal_id) # 判斷準不準（Phase 1.7b）看同一種獵物狩獵過幾次
	GameTime.advance_turns(HuntSystem.depth_turns(depth))
	# 深夜對狼有利：獵物警覺降低。
	var detection_mod: float = 0.0
	if GameTime.current_period() == "night":
		detection_mod = float(GameData.balance.get("night_prey_detection_mod", -10))
	if weather == "storm":
		detection_mod += float(_storm_cfg().get("detection_mod", -10))
	# 剛對鹿群失手：這一帶的鹿跺腳、噴鼻息，短時間內更難接近（1.8 第 5 步）
	if is_spooked(current_region, animal_id):
		detection_mod += float(GameData.balance.get("hunt", {}).get("herd", {}).get("spooked_detection", 10))
	if prey_dir < 0:
		prey_dir = RNGService.randi_range(0, 3)
	if terrain == "":
		terrain = _random_terrain(current_region)
	var hunt := HuntSystem.new(wolf, animal_id, life_stage, detection_mod, wind_dir, prey_dir, terrain, injured)
	if herd >= 0 and not injured:
		hunt.set_herd(herd == 1)
	# 夏季躲在草裡的幼鹿：一開始就要搜尋
	if hidden and hunt.stage == HuntSystem.Stage.POUNCE:
		hunt.hiding = true
		hunt.hid_once = true
	hunt.knowledge_bonus = weakness_bonuses(animal_id, life_stage)
	hunt.storm = weather == "storm"
	hunt.set_snow(snow_state())
	_on_hunt_started(hunt)
	hunt.tendency = current_tendency()
	hunt.fight_state["tendency_bonus"] = tendency_effect("assault")
	hunt.fight_state["source"] = animal_id + ".hunt"
	# 友善的苔原狼聽到動靜跟上來（1.8 第 9 步）
	if hunt.tundra_help == 0 and _joint_cfg().get("prey", []).has(animal_id) and life_stage != "juvenile" \
			and _tundra_wolves_here() and tundra_relation_key() == "friendly" and RNGService.chance(float(_joint_cfg().get("follow_chance", 0.3))):
		hunt.apply_tundra_help(tundra_adults(), false)
		log_message.emit(tr("tundra.hunt.followed" + ("" if tundra_pair().size() > 1 else ".single")))
	return hunt

func is_spooked(region_id: String, animal_id: String) -> bool:
	var table: Dictionary = life_log.get("spooked", {}).get(region_id, {})
	return int(table.get(animal_id, -1)) >= int(life_log.get("days_lived", 1))

func _spook(region_id: String, animal_id: String) -> void:
	var all: Dictionary = life_log.get("spooked", {})
	var table: Dictionary = all.get(region_id, {})
	table[animal_id] = int(life_log.get("days_lived", 1)) + int(GameData.balance.get("hunt", {}).get("herd", {}).get("spooked_days", 1))
	all[region_id] = table
	life_log["spooked"] = all

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
	# 1.8 第 1 步：狩獵內部的步驟不各自花時間，結束時一次結算（finish_hunt）
	if hunt != null:
		hunt.pending_turns += turns
		return
	GameTime.advance_turns(turns)
	_check_death()

# 狩獵結束（成功或失敗）：同步風向、結算各階段累積的經驗。
# 獵物逃走時，留下一條往某個地形去的新鮮足跡（current_discovery），可以再追。
func finish_hunt(hunt: HuntSystem) -> void:
	wind_dir = hunt.wind_dir
	# 長距離跟隨、多次試探：結束時多花 1～2 回合；喘回滿，依用掉的喘扣一次體力（1.8 第 1 步）
	var extra: int = min(hunt.pending_turns, int(GameData.balance.get("burst", {}).get("extra_turns_max", 2)))
	hunt.end_stamina = wolf.end_burst()
	# 夏季白天出獵較累（Phase 2b 第 4 步）：結束時扣的體力再乘倍率
	var heat: float = float(GameData.balance.get("hunt", {}).get("period", {}).get("end_stamina_mult", {}).get(GameTime.current_season() + "." + GameTime.current_period(), 1.0))
	if heat > 1.0 and wolf.alive:
		wolf.stamina = max(0.0, wolf.stamina - hunt.end_stamina * (heat - 1.0))
		hunt.end_stamina *= heat
	if extra > 0 and wolf.alive:
		GameTime.advance_turns(extra)
	if hunt.decisions.any(func(d): return str(d).begins_with("fight.")):
		_push_on_injury(hunt.start_heavy)
	FightRules.danger_to_heavy(wolf, hunt.fight_state.get("parts", {"leg": 0.5, "shoulder": 0.5}), hunt.animal_id + ".hunt")
	Growth.apply_practice(wolf, hunt.practice)
	_record_hunt(hunt)
	if hunt.result == HuntSystem.Result.SUCCESS:
		if HuntSystem.feeding_segments(hunt.animal_id, hunt.life_stage) > 1:
			start_feeding(hunt.animal_id, hunt.life_stage, hunt.terrain)
			# 幼鹿季：灰熊也在找幼鹿，剛獵到的幼體容易把牠引來（1.8 第 7 步）
			var fawn: Dictionary = _bear_cfg().get("fawn", {})
			if hunt.life_stage == "juvenile" and fawn.get("animals", []).has(hunt.animal_id) and _fawn_bear_season() \
					and float(EncounterSystem.region_data(current_region).get("competitor_weights", {}).get("grizzly_bear", {}).get(GameTime.current_season(), 0)) > 0.0:
				current_feeding["bear_bonus"] = float(fawn.get("bear_bonus", 0.2))
		resolve_hunt_success(hunt.animal_id, hunt.life_stage)
		# 一起獵到的：苔原狼吃掉一部分，關係上升
		if hunt.tundra_help > 0:
			_tundra_relation_add("joint_hunt")
			_tundra_record("hunt", "joint_" + hunt.animal_id)
			life_log["joint_hunts"] = int(life_log.get("joint_hunts", 0)) + 1
			if int(life_log["joint_hunts"]) == 1: # 第一次和苔原狼一起獵到
				_year_flag("tundra")
			if not current_feeding.is_empty():
				var e: Array = _joint_cfg().get("eat_segments", [1, 2])
				var eaten: int = min(int(current_feeding["segments_left"]) - 1, RNGService.randi_range(int(e[0]), int(e[1])) + max(0, tundra_adults() - 2))
				current_feeding["segments_left"] = int(current_feeding["segments_left"]) - max(0, eaten)
				current_feeding["with_tundra"] = true
			log_message.emit(tr("tundra.hunt.shared" + ("" if tundra_pair().size() > 1 else ".single")))
	else:
		if hunt.in_herd and hunt.stage_reached_stalk():
			_spook(current_region, hunt.animal_id)
		# 分次狩獵（1.8 第 4 步）：咬傷但沒制伏的大型獵物帶傷留在這一帶幾天，之後再遇到時更好抓
		if int(hunt.fight_state.get("wounds", 0)) > 0 and wolf.alive \
				and str(GameData.animals.get(hunt.animal_id, {}).get("size", "small")) == "large" and hunt.life_stage != "juvenile":
			var id: int = int(life_log.get("next_notable_id", 1))
			life_log["next_notable_id"] = id + 1
			notables.append({"id": id, "region": current_region, "animal": hunt.animal_id, "stage": hunt.life_stage, "trait": "wounded",
				"until": int(life_log.get("days_lived", 1)) + int(GameData.discovery.get("notable", {}).get("wounded_days", 4))})
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

# 1.7 行動的體力消耗（balance.action_stamina_costs）：有傷時乘傷勢的體力倍率，最低停在 0。
func _spend_action_stamina(action: String) -> void:
	var cost: float = float(GameData.balance.get("action_stamina_costs", {}).get(action, 0))
	# 深雪裡移動、探索比較累（1.8 第 2 步）
	if wolf != null and snow_state() == "deep":
		var sc: Dictionary = GameData.events.get("snow", {})
		if action == "move_region":
			cost += float(sc.get("deep_move_stamina", 2))
		elif action == "explore":
			cost += float(sc.get("deep_explore_stamina", 1))
	# 吃撐時移動、探索比較累（Phase 2b 第 1 步）
	if wolf != null and wolf.is_overfed() and action in ["move_region", "explore"]:
		cost *= float(GameData.balance.get("gorged", {}).get("move_stamina_mult", 1.0))
	if cost > 0.0 and wolf != null:
		wolf.stamina = max(0.0, wolf.stamina - cost * wolf.injury_stamina_mult())

# 太累不能開始狩獵（QA-55；balance.low_stamina.hunt_min）。
func too_tired_to_hunt() -> bool:
	return wolf != null and wolf.stamina < float(GameData.balance.get("low_stamina", {}).get("hunt_min", 0))

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

# 判斷準不準（Phase 1.7b，提案之七）：次成年期成功率只顯示模糊說法；同一種獵物狩獵過幾次、
# 第二年感知夠高、或打過幾次同一種對手後才顯示數字；成年後一律顯示數字。kind："hunt" 或 "fight"。
func chance_is_precise(kind: String, animal_id: String) -> bool:
	if wolf == null or wolf.life_stage() != Wolf.LifeStage.SUBADULT:
		return true
	var f: Dictionary = GameData.balance.get("youth", {}).get("fuzzy", {})
	var stats: Dictionary = life_log.get("stats", {})
	if kind == "fight":
		return int(stats.get("fights_by_animal", {}).get(animal_id, 0)) > int(f.get("known_fights", 3))
	var yearling: float = float(GameData.balance.get("life_stage_ages", {}).get("yearling", 1.0))
	if wolf.age_years >= yearling and wolf.effective_perception() >= float(f.get("perception", 60)):
		return true
	return int(stats.get("hunts_by_animal", {}).get(animal_id, 0)) > int(f.get("known_hunts", 5))

# 模糊說法的翻譯鍵（依成功率分段）。
func fuzzy_chance_key(chance: float) -> String:
	for pair in GameData.balance.get("youth", {}).get("fuzzy", {}).get("labels", []):
		if chance < float(pair[0]):
			return str(pair[1])
	return "fuzzy.sure"

# --- 試玩紀錄的指標（SPEC 1.7「收尾」，提案之十二 E）：只記錄，不影響遊戲 ---
# play_seconds／stage_seconds：實際遊玩時間（畫面層每幀加）；choices／best_choices：有成功率的選擇裡，選了最高的次數；
# cards／quick_cards：卡片數、出現 1 秒內就按「繼續」的次數；events、quiet_streak、longest_quiet：每天的事件數與最長平淡天數。
func metrics() -> Dictionary:
	if not life_log.has("metrics"):
		life_log["metrics"] = {}
	return life_log["metrics"]

func metric_play_time(delta: float) -> void:
	if wolf == null or not wolf.alive or auto_playing:
		return
	var m := metrics()
	m["play_seconds"] = float(m.get("play_seconds", 0.0)) + delta
	var stage: String = ["subadult", "adult", "elder"][wolf.life_stage()]
	var st: Dictionary = m.get("stage_seconds", {})
	st[stage] = float(st.get(stage, 0.0)) + delta
	m["stage_seconds"] = st

func metric_choice(chosen: float, best: float) -> void:
	if auto_playing:
		return
	var m := metrics()
	m["choices"] = int(m.get("choices", 0)) + 1
	var is_best: bool = chosen >= best - 0.001
	if is_best:
		m["best_choices"] = int(m.get("best_choices", 0)) + 1
	# 做選擇時的狀況（2026-10-16，ChatGPT 建議、使用者同意）：看玩家會不會因為飽食度、傷勢、體力、時段、年紀而選不同的選項。
	# by_context[標籤] = [選擇次數, 選了最高成功率的次數, 刻意冒險（比最高低 15% 以上）的次數]
	var ctx: Dictionary = m.get("by_context", {})
	for tag in _choice_context():
		var row: Array = ctx.get(tag, [0, 0, 0])
		row[0] = int(row[0]) + 1
		if is_best:
			row[1] = int(row[1]) + 1
		if best - chosen >= 0.15:
			row[2] = int(row[2]) + 1
		ctx[tag] = row
	m["by_context"] = ctx

func _choice_context() -> Array:
	var tags: Array = []
	tags.append("hunger." + ("starving" if wolf.hunger < 30.0 else ("hungry" if wolf.hunger < 60.0 else ("ok" if wolf.hunger < 100.0 else "full"))))
	tags.append("injury." + ("heavy" if wolf.injury == Wolf.Injury.HEAVY else ("light" if wolf.injury != Wolf.Injury.NONE else "none")))
	tags.append("stamina." + ("low" if wolf.stamina < 30.0 else ("mid" if wolf.stamina < 70.0 else "high")))
	tags.append("period." + GameTime.current_period())
	tags.append("stage." + ["subadult", "adult", "elder"][wolf.life_stage()])
	return tags

func metric_card(seconds: float) -> void:
	if auto_playing:
		return
	var m := metrics()
	m["cards"] = int(m.get("cards", 0)) + 1
	if seconds < 1.0:
		m["quick_cards"] = int(m.get("quick_cards", 0)) + 1

# 文字問題（TextWatch）：原始翻譯鍵、沒替換的佔位。同一個片段只記一次，最多 TEXT_ISSUE_MAX 筆。
const TEXT_ISSUE_MAX := 50

func metric_text_issue(kind: String, token: String, where: String, text: String) -> void:
	var issues: Dictionary = metrics().get_or_add("text_issues", {})
	if issues.has(token) or issues.size() >= TEXT_ISSUE_MAX:
		return
	issues[token] = {"kind": kind, "where": where, "text": text, "age": snapped(wolf.age_years, 0.01) if wolf != null else 0.0,
		"region": current_region, "routine": routine_running, "auto": auto_playing}

# 給除錯選單與試玩紀錄看的摘要。
func metrics_summary() -> Dictionary:
	var m := metrics()
	var days: int = max(1, int(life_log.get("days_lived", 1)))
	return {"play_minutes": snapped(float(m.get("play_seconds", 0.0)) / 60.0, 0.1),
		"decisions_per_day": snapped(float(_stat_total("option_counts")) / days, 0.1),
		"events_per_day": snapped(float(m.get("events", 0)) / days, 0.01),
		"longest_quiet_days": int(m.get("longest_quiet", 0)),
		"best_choice_ratio": snapped(float(m.get("best_choices", 0)) / max(1, int(m.get("choices", 0))), 0.01),
		"quick_card_ratio": snapped(float(m.get("quick_cards", 0)) / max(1, int(m.get("cards", 0))), 0.01),
		# 各狀況下：選擇次數、選最高成功率的比例、刻意冒險的比例
		"best_choice_by_context": (m.get("by_context", {}) as Dictionary).keys().map(func(k): return "%s %d次 最高%.2f 冒險%.2f" % [k, int(m["by_context"][k][0]),
			float(m["by_context"][k][1]) / max(1, int(m["by_context"][k][0])), float(m["by_context"][k][2]) / max(1, int(m["by_context"][k][0]))]),
		# 吃撐：一次平均幾個時段（Phase 2b 第 1 步，目標約 5～10 個時段＝1～2 天）
		"gorged_avg_periods": snapped(float(m.get("gorged_periods", 0)) / max(1, int(m.get("gorged_spells", 0))), 0.1),
		"stage_minutes": (m.get("stage_seconds", {}) as Dictionary).keys().map(func(k): return "%s %.1f" % [k, float(m["stage_seconds"][k]) / 60.0]),
		"text_issues": (m.get("text_issues", {}) as Dictionary).keys().map(func(k): return "%s %s @ %s「%s」" % [m["text_issues"][k]["kind"], k,
			m["text_issues"][k]["where"], m["text_issues"][k]["text"]])}

func _stat_total(stat_key: String) -> int:
	var total := 0
	for v in life_log.get("stats", {}).get(stat_key, {}).values():
		total += int(v)
	return total

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
	var text := JSON.stringify({"metrics": metrics_summary(), "life_log": life_log, "knowledge": knowledge.values(), "age_years": wolf.age_years,
		"tendency": current_tendency(), "wolf": wolf.to_dict(), "region": current_region, "den": den_region,
		"time": {"season": GameTime.current_season(), "day": GameTime.day, "period": GameTime.current_period()}}, "  ")
	file.store_string(text)
	file.close()
	# 照常過日子時死去也要複製一份（原本 auto_playing 一律略過，只留在 user://）
	if OS.has_feature("editor") and DisplayServer.get_name() != "headless" and (not auto_playing or routine_running):
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
	# 暴風雪期間不會同時下暴雨；冬季不下暴雨（QA-69，Phase 2 其他地圖冬季改成暴風雪）
	if weather == "clear" and not blizzard_here() and cfg.get("seasons", ["spring", "summer", "autumn"]).has(GameTime.current_season()) \
			and _can_trigger_event() and RNGService.chance(float(cfg.get("period_chance", 0.05)) * (float(cfg.get("fire_mult", 0.3)) if not fire.is_empty() else 1.0) * float(year_effects("summer").get("storm", 1.0))):
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
	if GameTime.current_period() != "night" or howl_region() == "" or not _can_trigger_event():
		return
	# 只在同一張地圖聽得到（人在苔原聽不到森林那隻狼）
	if GameData.map_of(howl_region()) != current_map():
		return
	var chance_value: float = float(_events_cfg().get("howl", {}).get("night_chance", 0.35))
	# 輸給你之後，遠方的狼嚎減少
	if stranger() != null and stranger().yielded_to_player:
		chance_value *= float(_stranger_cfg().get("howl_mult_after_yield", 0.5))
	if RNGService.chance(chance_value):
		trigger_howl()

func trigger_howl() -> void:
	learn({"type": "territory", "animal": "stranger_wolf", "region": howl_region()})
	_queue_event({"type": "howl", "region": howl_region(), "pack": black_pack.stage, "pups": black_pack.pups() > 0})

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
	var animal: String = _nearby_prey_pick(cfg)
	if animal == "":
		return
	_queue_event({"type": "prey_nearby", "animal_id": animal,
		"life_stage": str(cfg.get("life_stage", {}).get(animal, "adult")), "terrain": _random_terrain(current_region)})

# 獵物靠近的動物：只從這一區這一季有出沒的動物裡挑（苔原不會有白尾鹿、森林不會有雪兔）。都沒有就不發生。
func _nearby_prey_pick(cfg: Dictionary) -> String:
	var here: Dictionary = EncounterSystem.region_data(current_region).get("prey_weights", {})
	var candidates: Dictionary = {}
	var all: Dictionary = cfg.get("animals", {"hare": 1})
	for animal in all.keys():
		if float(here.get(animal, {}).get(GameTime.current_season(), 0)) > 0.0:
			candidates[animal] = all[animal]
	if candidates.is_empty():
		return ""
	return str(RNGService.weighted_pick(candidates))

func hunt_nearby_prey(event: Dictionary) -> HuntSystem:
	return start_hunt(event["animal_id"], event["life_stage"], -1, false, str(event.get("terrain", "")))

# 灰熊路過：在巢穴或睡處休息時。保持不動（看技巧）或立刻離開（失去這次休息的回復）。
# 機率依那一區灰熊的多寡（權重 ÷ ref_weight，最多 1 倍），巢穴 × den_mult（2026-10-15 試玩回報 24）。
func _maybe_bear_passing(gained_health: float, gained_stamina: float, quality: String = "") -> void:
	var weights: Dictionary = EncounterSystem.region_data(current_region).get("competitor_weights", {}).get("grizzly_bear", {})
	var weight: float = float(weights.get(GameTime.current_season(), 0))
	if weight <= 0.0 or not _can_trigger_event():
		return
	var cfg: Dictionary = _events_cfg().get("bear_passing", {})
	var chance: float = float(cfg.get("sleep_chance", 0.04)) * min(1.0, weight / float(cfg.get("ref_weight", 7.0)))
	if quality == "den":
		chance *= float(cfg.get("den_mult", 0.5)) * den_hidden_mult()
	if RNGService.chance(chance * threat_mult()):
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
	# 每種獵物的試獵、成功、放棄次數（2026-10-17 狩獵難度分析；試玩紀錄也看得到）
	var by: Dictionary = life_log.get_or_add("hunt_by_animal", {})
	var key: String = hunt.animal_id + "." + hunt.life_stage
	var row: Array = by.get(key, [0, 0, 0])
	row[0] = int(row[0]) + 1
	if hunt.result == HuntSystem.Result.SUCCESS:
		row[1] = int(row[1]) + 1
		# 小型獵物當場吃完（HuntSystem._kill），不經過分段進食
		if HuntSystem.feeding_segments(hunt.animal_id, hunt.life_stage) <= 1:
			_note_food("kill:" + hunt.animal_id, float(hunt.prey_hunger_value))
	elif hunt.result == HuntSystem.Result.PLAYER_GAVE_UP:
		row[2] = int(row[2]) + 1
	by[key] = row
	# 依獵物體況（健康、普通、虛弱；沒有體況的小獵物不記）：試、成、放棄（Phase 2b 第 3 步）
	if hunt.condition != "":
		var bc: Dictionary = life_log.get_or_add("hunt_by_condition", {})
		var crow: Array = bc.get(hunt.condition, [0, 0, 0])
		crow[0] = int(crow[0]) + 1
		if hunt.result == HuntSystem.Result.SUCCESS:
			crow[1] = int(crow[1]) + 1
		elif hunt.result == HuntSystem.Result.PLAYER_GAVE_UP:
			crow[2] = int(crow[2]) + 1
		bc[hunt.condition] = crow
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
		"segment_value": total / max(1, segments), "turns_stayed": 0, "terrain": terrain, "src": "kill"}

# 吃到的飽食度依來源累計（life_log.food_by；2026-10-17 狩獵難度分析）。來源：kill:<動物> 自己獵的、carcass:<動物> 回到或找到的殘骸、
# remains 別人吃剩的、gather 採集、bear_steal 從熊口搶的、lynx_steal 搶猞猁的雪兔。
func _note_food(source: String, gain: float) -> void:
	if gain <= 0.0:
		return
	var by: Dictionary = life_log.get_or_add("food_by", {})
	by[source] = snapped(float(by.get(source, 0.0)) + gain, 0.1)

func is_feeding() -> bool:
	return not current_feeding.is_empty()

# 下一段吃完後，灰熊／狐狸來搶食的機率：每多停留 1 回合上升，深夜與密林更高。
func scavenge_chances() -> Dictionary:
	var cfg := _feeding_cfg()
	var bear: float = float(cfg.get("bear_base", 0.1)) + float(cfg.get("bear_per_turn", 0.1)) * int(current_feeding.get("turns_stayed", 0))
	bear += float(current_feeding.get("bear_bonus", 0.0))
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
			wolverine = (float(_wolverine_cfg().get("feed_chance", 0.1)) + bonus) * wolverine_season_mult()
	bear *= float(_bear_phase_cfg().get("scavenge_mult", 1.0))
	return {"bear": clamp(bear, 0.0, 0.95), "fox": fox_chance(float(cfg.get("fox_chance", 0.12))), "wolverine": clamp(wolverine, 0.0, 0.95)}

# 狐狸來偷殘骸（1.8 第 6 步）：冬季、雪兔低谷年更常來；你常待的區域狐狸較少。
func fox_chance(base: float) -> float:
	var f: Dictionary = _feeding_cfg().get("fox", {})
	var c: float = base
	if GameTime.current_season() == "winter":
		c *= float(f.get("winter_mult", 1.5))
	if hare_mult(false) < float(f.get("hare_low", 0.5)):
		c *= float(f.get("hare_low_mult", 1.5))
	if int(life_log.get("region_periods", {}).get(current_region, 0)) >= int(f.get("frequent_periods", 12)):
		c *= float(f.get("frequent_mult", 0.6))
	return clamp(c, 0.0, 0.9)

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
	_note_food(str(current_feeding.get("src", "carcass")) + ":" + str(current_feeding.get("animal_id", "")), gain)
	wolf.hunger += gain
	wolf.clamp_stats()
	current_feeding["segments_left"] = int(current_feeding["segments_left"]) - 1
	current_feeding["turns_stayed"] = int(current_feeding["turns_stayed"]) + 1
	var event: String = ""
	if int(current_feeding["segments_left"]) > 0:
		# 美洲獅回來找牠藏的獵物；黑熊被氣味引來（Phase 2 第 3 步）
		if bool(current_feeding.get("cougar", false)) and RNGService.chance(float(_cougar_cfg().get("return_chance", 0.25))):
			event = "cougar"
		elif RNGService.chance(float(_black_bear_cfg().get("feed_chance", 0.06)) * black_bear_mult()):
			event = "black_bear"
		elif RNGService.chance(float(_coyote_cfg().get("feed_chance", 0.1)) * coyote_mult()):
			event = "coyote"
		# 年輕的挑戰者來搶殘骸（1.9b 第 2 步）
		elif challenger_due() and RNGService.chance(0.5):
			_ensure_challenger()
			event = "challenger"
		elif RNGService.chance(float(chances["bear"]) * threat_mult()):
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
			_note_food(str(current_feeding.get("src", "carcass")) + ":" + str(current_feeding.get("animal_id", "")), float(current_feeding.get("segment_value", 0)))
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
	_spend_action_stamina("return_to_carcass")
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
		"segment_value": c["segment_value"], "turns_stayed": 0, "terrain": c["terrain"], "src": "kill" if own else "carcass"}
	var event: String = ""
	if RNGService.chance(float(cfg.get("return_bear_chance", 0.1)) * threat_mult() * float(_bear_phase_cfg().get("scavenge_mult", 1.0))):
		event = "bear"
	elif _wolverine_alive() and current_map() == str(_wolverine_cfg().get("map", "tundra")) \
			and RNGService.chance(float(_wolverine_cfg().get("return_chance", 0.25)) * wolverine_season_mult()):
		event = "wolverine"
	elif _tundra_wolves_here() and RNGService.chance(_tundra_carcass_chance()):
		event = "tundra_wait" if tundra_relation_key() == "friendly" else "tundra_wolves"
	elif RNGService.chance(float(_black_bear_cfg().get("return_chance", 0.12)) * black_bear_mult()):
		event = "black_bear"
	elif RNGService.chance(float(_coyote_cfg().get("return_chance", 0.18)) * coyote_mult()):
		event = "coyote"
	elif RNGService.chance(fox_chance(float(cfg.get("return_fox_chance", 0.2)))):
		event = "fox"
	state_changed.emit()
	return {"event": event, "own": own}

# 殘骸逐段被渡鴉、狐狸吃掉（Phase 2b 第 1 步，取代每個時段 15% 整個不見）：你在同一區時少、不在時多，每天有上限；
# 放太久就腐壞。凍住的吃得慢；苔原的狼獾照舊加乘。
func _decay_carcasses() -> void:
	var cfg := _feeding_cfg()
	var today: int = int(life_log.get("days_lived", 1))
	var days_limit: int = int(cfg.get("carcass_days_winter" if GameTime.current_season() == "winter" else "carcass_days", 4))
	var kept: Array = []
	for c in carcasses:
		if today - int(c["day"]) > days_limit:
			continue
		var loss: float = carcass_loss_per_period(c)
		if int(c.get("loss_day", -1)) != today:
			c["loss_day"] = today
			c["loss_today"] = 0.0
		loss = min(loss, max(0.0, float(cfg.get("carcass_loss", {}).get("max_per_day", 1.0)) - float(c["loss_today"])))
		c["loss_today"] = float(c["loss_today"]) + loss
		c["eaten"] = float(c.get("eaten", 0.0)) + loss
		while float(c["eaten"]) >= 1.0 and int(c["segments_left"]) > 0:
			c["eaten"] = float(c["eaten"]) - 1.0
			c["segments_left"] = int(c["segments_left"]) - 1
		if int(c["segments_left"]) <= 0:
			continue
		kept.append(c)
	carcasses = kept

# 這具殘骸每個時段大約被吃掉幾段（畫面上「離開時大約會少多少」也用這個）。
func carcass_loss_per_period(c: Dictionary, present: Variant = null) -> float:
	var lc: Dictionary = _feeding_cfg().get("carcass_loss", {})
	var here: bool = (str(c.get("region_id", "")) == current_region) if present == null else bool(present)
	var loss: float = float(lc.get("present" if here else "absent", 0.2))
	if bool(c.get("frozen", false)):
		loss *= float(_blizzard_cfg().get("winter_kill", {}).get("loss_mult", 0.3))
	# 苔原的殘骸還會被狼獾偷吃
	if _wolverine_alive() and GameData.map_of(str(c.get("region_id", ""))) == str(_wolverine_cfg().get("map", "tundra")):
		loss *= float(_wolverine_cfg().get("carcass_loss_mult", 1.0)) * (float(_wolverine_cfg().get("winter_loss_mult", 1.0)) if GameTime.current_season() == "winter" else 1.0)
	return loss

# 你不在時，這具殘骸一天大約少幾段（有每天的上限）。
func carcass_loss_per_day_absent(c: Dictionary) -> float:
	return min(carcass_loss_per_period(c, false) * GameTime.PERIODS.size(), float(_feeding_cfg().get("carcass_loss", {}).get("max_per_day", 1.0)))

func carcass_here() -> Dictionary:
	var idx := carcass_index_here()
	return carcasses[idx] if idx >= 0 else {}

func resolve_hunt_success(animal_id: String, life_stage: String) -> void:
	var prey_count: Dictionary = life_log.get("prey_count", {})
	prey_count[animal_id] = int(prey_count.get(animal_id, 0)) + 1
	life_log["prey_count"] = prey_count
	_deplete_region(current_region, animal_id)
	var ys: Dictionary = life_log.get("year_stats", {})
	ys["kills"] = int(ys.get("kills", 0)) + 1
	if _prey_rank(animal_id, life_stage) > _prey_rank(str(ys.get("biggest", "")), str(ys.get("biggest_stage", "adult"))):
		ys["biggest"] = animal_id
		ys["biggest_stage"] = life_stage
	life_log["year_stats"] = ys
	var current_rank: int = _prey_rank(str(life_log.get("biggest_prey", "")), str(life_log.get("biggest_prey_stage", "adult")))
	var new_rank: int = _prey_rank(animal_id, life_stage)
	if new_rank > current_rank:
		if new_rank >= 100: # 一生最大的獵物刷新（駝鹿、馬鹿）才算這一年的大事
			_year_flag("big_prey")
		life_log["biggest_prey"] = animal_id
		life_log["biggest_prey_stage"] = life_stage
	if hunting_notable != 0:
		notables = notables.filter(func(n): return int(n.get("id", 0)) != hunting_notable)
		hunting_notable = 0
	# 第一次獨自獵倒成年的大型獵物（Phase 1.7b 的里程碑）
	var stats: Dictionary = GameData.animals.get(animal_id, {}).get(life_stage, {})
	if not life_log.has("first_big_kill") and life_stage != "juvenile" \
			and float(stats.get("fight_power", 0.0)) >= float(GameData.balance.get("youth", {}).get("big_prey_power", 50)):
		life_log["first_big_kill"] = {"age": snapped(wolf.age_years, 0.1), "animal": animal_id, "stage": life_stage}
		_queue_notice({"type": "first_big_kill", "animal": animal_id, "stage": life_stage})
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
	if animal_id in ["cougar", "black_bear", "coyote", "lynx"]:
		identify(animal_id)
	_stat_inc("fights_by_animal", animal_id)
	var c := Combat.new(wolf, animal_id, life_stage, context, bool(encounter.get("mother", false)))
	# 在自己的地盤和黑狼、苔原狼衝突：你更拚（1.9b 第 1 步）
	if animal_id in ["stranger_wolf", "tundra_wolf"] and is_own_territory():
		c.stake_mult *= float(_territory_cfg().get("stake_mult", 1.25))
	# 和友善的苔原狼一起吃殘骸時灰熊來搶：牠們在你這一邊騷擾灰熊（1.8 第 9 步；不算單獨擊退）
	if animal_id == "grizzly_bear" and context == "carcass" and (bool(current_feeding.get("with_tundra", false)) \
			or (_tundra_wolves_here() and tundra_relation_key() == "friendly")):
		var ba: Dictionary = _joint_cfg().get("bear_ally", {})
		c.ally_chance = clamp(float(ba.get("ally_chance", 0.3)) * tundra_count_effect(), 0.0, 0.6)
		c.ally_damage = ba.get("ally_damage", [6, 12])
		c.set_meta("tundra_ally", true)
	c.tendency = current_tendency()
	c.terrain = str(current_feeding.get("terrain", "")) if context == "carcass" else str(encounter.get("location", ""))
	if c.terrain == "":
		c.terrain = _random_terrain(current_region)
	match context:
		"carcass":
			match animal_id:
				"grizzly_bear", "cougar", "black_bear": c.yields = ["grab", "abandon"]
				"coyote": c.yields = ["ignore"]
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

# 第一次打贏危險的對手（灰熊、美洲獅、黑熊、黑狼；balance.growth.first_win）：提高潛力上限、成長一次、跳一張卡片。
# 每種對手只限第一次打贏；這一戰受了重傷（從開打後算）只給 heavy 的少量加成，之後不再補（2026-10-15 試玩回報 13）。
func _after_first_win(c: Combat) -> void:
	var table: Dictionary = GameData.balance.get("growth", {}).get("first_win", {})
	if not table.has(c.animal_id):
		return
	var wins: Dictionary = life_log.get("first_wins", {})
	if wins.has(c.animal_id) or (c.animal_id == "grizzly_bear" and life_log.has("bear_first_win")):
		return
	var age: float = snapped(wolf.age_years, 0.1)
	wins[c.animal_id] = age
	life_log["first_wins"] = wins
	if c.animal_id == "grizzly_bear":
		life_log["bear_first_win"] = age # 一生回顧用
	var clean: bool = wolf.heavy_injury_count == c.start_heavy_count
	var cfg: Dictionary = table[c.animal_id]
	var cap_src: Dictionary = cfg.get("caps", {}) if clean else cfg.get("heavy", {})
	var gain_src: Dictionary = cfg.get("gains", {}) if clean else cfg.get("heavy", {})
	var caps: Dictionary = {}
	for stat in cap_src.keys():
		var raised: float = Growth.raise_cap(wolf, str(stat), float(cap_src[stat]))
		if raised > 0.0:
			caps[stat] = raised
	var gains: Dictionary = {}
	for stat in gain_src.keys():
		var g: float = Growth.bonus(wolf, str(stat), float(gain_src[stat]))
		if g > 0.0:
			gains[stat] = g
	var event := {"type": "first_win", "animal": c.animal_id, "clean": clean, "caps": caps, "gains": gains}
	# 咬死黑狼已經有「那隻黑狼」卡片：成長接在那張卡片裡，不另外跳一張
	if c.outcome == "killed":
		for e in pending_events:
			if str(e.get("type", "")) == "stranger_killed" and c.animal_id == "stranger_wolf":
				e["first_win"] = event
				return
	_queue_notice(event)

# 戰鬥結束：記錄決策、成長、知識，處理獵物的去留。回傳 {"outcome", "grow": "clean"|"costly"|""}。
func finish_combat(c: Combat) -> Dictionary:
	for d in c.decisions:
		record_decision(d)
	# 戰鬥：喘回滿、扣一次體力；打得久（超過 combat_free_rounds 回合）多花 1 回合（1.8 第 1 步）
	c.end_stamina = wolf.end_burst()
	if c.rounds > int(GameData.balance.get("burst", {}).get("combat_free_rounds", 3)) and wolf.alive:
		GameTime.advance_turns(1)
	if c.rounds > 0:
		_push_on_injury(c.start_heavy)
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
			# 老年技巧不再長，不說「越來越熟練」（文案稽核 2026-10-16）
			result["grow"] = "clean_elder" if wolf.life_stage() == Wolf.LifeStage.ELDER else "clean"
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
		_after_stranger_combat(c)
	elif c.npc != null and c.npc.id == "wolverine":
		_wolverine_record(c)
		if c.context == "mob":
			_after_mob_combat(c)
	elif c.npc != null and TUNDRA_WOLF_IDS.has(c.npc.id):
		_after_tundra_combat(c)
	if c.context == "den":
		_after_den_combat(c)
	# 趕走剛抓到雪兔的猞猁，雪兔歸你（Phase 2 第 6 步）
	if c.animal_id == "lynx" and c.won() and bool(c.get_meta("lynx_kill", false)):
		_note_food("lynx_steal", float(_lynx_cfg().get("hare_value", 12)))
		wolf.hunger += float(_lynx_cfg().get("hare_value", 12))
		wolf.clamp_stats()
		result["lynx_hare"] = true
	if c.npc != null and c.npc.id == "challenger":
		c.npc.health = c.opp_hp
		_after_challenger(c.won())
		if not c.won():
			if not current_feeding.is_empty() and c.context == "carcass":
				current_feeding = {}
			if c.context == "territory" and is_own_territory():
				var marks: Dictionary = life_log.get("marks", {})
				marks.erase(current_region)
				life_log["marks"] = marks
	if c.won() and c.life_stage == "adult" and c.ally_chance <= 0.0:
		_after_first_win(c)
	GameTime.advance_turns(1)
	wolf.clamp_stats()
	_check_death()
	state_changed.emit()
	return result

# 搶食後獵物的去留：趕走對手就繼續吃；叼走一塊、不理狐狸、退讓、撤退都會失去部分或全部。
func _carcass_after_combat(c: Combat) -> void:
	var by_bear: bool = c.animal_id == "grizzly_bear"
	# 咬死來偷肉的狐狸：殘骸還是你的；狐狸通常不吃，餓壞了才吃（1.8 第 6 步）
	if c.outcome == "killed" and c.animal_id in ["red_fox", "coyote"]:
		var f: Dictionary = _feeding_cfg().get("fox", {})
		if wolf.hunger < float(f.get("eat_hunger", 20)):
			wolf.hunger += float(f.get("eat_value", 15))
			wolf.clamp_stats()
			log_message.emit(tr("fox.killed.eaten").replace("{animal}", tr("animal." + c.animal_id)))
		else:
			log_message.emit(tr("fox.killed.left").replace("{animal}", tr("animal." + c.animal_id)))
		return
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
				elif c.outcome == "guard_together":
					# 一起守著：之後灰熊來搶時牠們在你這一邊（2026-10-15 試玩回報 19，和一起獵到的殘骸相同）
					current_feeding["with_tundra"] = true
			return
		"grab":
			_note_food(str(current_feeding.get("src", "carcass")) + ":" + str(current_feeding.get("animal_id", "")), float(current_feeding.get("segment_value", 0)))
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
	if RNGService.chance(float(cfg.get("year_chance", 0.15)) * float(year_effects("summer").get("fire", 1.0))):
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
	# 草木新生分兩段：剛冒新芽（sprout_days 天內），之後已經長滿嫩草灌木（文字不同，各描述一次）
	if state == "regrowth" and regrowth_late(region_id):
		state = "regrown"
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

# 草木新生的後段：焦黑期之後再過 sprout_days 天，新芽已經長成嫩草與灌木（鹿仍然比較多，地圖不再標示）。
func regrowth_late(region_id: String) -> bool:
	if burn_state(region_id) != "regrowth":
		return false
	var after: Dictionary = _fire_cfg().get("after", {})
	var days: int = int(life_log.get("days_lived", 1)) - int(region_burn[region_id])
	return days >= int(after.get("ash_days", 12)) + int(after.get("sprout_days", 10))

# 獵物出現率的倍率：資源消耗 × 火後（焦黑時稀少、草木新生時鹿變多）。
# 年況對大型獵物體況的倍率（1.8 第 11 步）：嚴冬冬季虛弱多；暖冬後春季駝鹿被冬蜱拖垮
func year_weak_mult(animal_id: String) -> float:
	var season: String = GameTime.current_season()
	if season == "winter":
		return float(year_effects("winter").get("weak_mult", 1.0))
	if season == "spring" and animal_id == "moose" and bool(life_log.get("year_mild_last", false)):
		return float(_year_cfg().get("effects", {}).get("mild", {}).get("moose_tick_spring", 1.0))
	return 1.0

# 雪兔週期這一年的倍率（夏末秋初再乘 late_summer_mult）。
# 去年的雪兔倍率（週期的前一年），用來說「比去年多／少」。
func hare_mult_last_year() -> float:
	var table: Array = GameData.balance.get("hare_cycle", {}).get("mult", [1.0])
	return float(table[posmod(int(life_log.get("hare_year", 0)) - 1, table.size())])

func hare_mult(with_season: bool = true) -> float:
	var cfg: Dictionary = GameData.balance.get("hare_cycle", {})
	var table: Array = cfg.get("mult", [1.0])
	var m: float = float(table[int(life_log.get("hare_year", 0)) % table.size()])
	if with_season:
		var season: String = GameTime.current_season()
		var half: int = int(GameData.balance.get("season_day_count", {}).get(GameTime.time_mode, 10)) / 2
		if (season == "summer" and GameTime.day > half) or (season == "autumn" and GameTime.day <= int(cfg.get("late_autumn_days", 7))):
			m *= float(cfg.get("late_summer_mult", 1.4))
	return m

# 對狼的荒年（2026-10-15 使用者同意方案三）：暖冬（獵物體況好）、夏末到秋天（幼獸長大、成獸肥壯）、雪兔低谷。
# 嚴冬對狼有利，不算。幾種同時成立時倍率相乘。回傳 {prey_mult：中大型獵物出現的倍率, nothing_mult：探索落空的倍率, kinds}
func lean_effects() -> Dictionary:
	var cfg: Dictionary = GameData.balance.get("lean", {})
	var prey: float = 1.0
	var nothing: float = 1.0
	var kinds: Array = []
	var season: String = GameTime.current_season()
	var half: int = int(GameData.balance.get("season_day_count", {}).get(GameTime.time_mode, 10)) / 2
	if season == "winter" and str(year_state().get("winter", "normal")) == "mild":
		kinds.append("mild_winter")
	if (season == "summer" and GameTime.day > half) or season == "autumn":
		kinds.append("late_summer")
	if hare_mult(false) <= float(cfg.get("hare_low_at", 0.3)):
		kinds.append("hare_low")
	for k in kinds:
		var e: Dictionary = cfg.get(k, {})
		prey *= float(e.get("prey_mult", 1.0))
		nothing *= float(e.get("nothing_mult", 1.0))
	return {"prey_mult": prey, "nothing_mult": nothing, "kinds": kinds}

func prey_mults(region_id: String) -> Dictionary:
	var result: Dictionary = region_depletion.get(region_id, {}).duplicate()
	_migration_mults(region_id, result)
	result["snowshoe_hare"] = float(result.get("snowshoe_hare", 1.0)) * hare_mult()
	# 冬季的保護色：雪兔在雪地裡比較難被發現
	for animal_id in GameData.animals.keys():
		var camo: float = HuntSystem.camouflage(animal_id)
		if camo != 0.0:
			result[animal_id] = float(result.get(animal_id, 1.0)) * (1.0 - camo)
	# 荒年（2026-10-15 後半生的生存壓力）：中、大型獵物變少
	var lean_prey: float = float(lean_effects().get("prey_mult", 1.0))
	if lean_prey != 1.0:
		for animal_id in GameData.animals.keys():
			if HuntSystem.size_of(animal_id) in ["medium", "large"]:
				result[animal_id] = float(result.get(animal_id, 1.0)) * lean_prey
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
	# 暴雨澆熄大火（QA-73）：徵兆階段就不會起火；燃燒中的區域在這個時段熄滅（算燒過）
	if weather == "storm":
		_rain_out_fire()
		return
	if fire["phase"] == "warning":
		_maybe_notice_fire()
		if now >= int(fire["ignite_at"]):
			fire["phase"] = "burning"
			fire["regions"] = {str(fire["origin"]): now}
			if not bool(fire.get("noticed", false)) and _fire_notice_range() != "":
				fire["noticed"] = true
				pending_events.append({"type": "fire_warning", "origin": fire["origin"], "late": true, "far": _fire_notice_range() == "far"})
		_check_fire_here()
		return
	# 一直在別的地圖、沒察覺到的大火：回到森林（或森林旁的苔原林線）時，濃煙已經看得到了（1.7-1）
	if not bool(fire.get("noticed", false)) and _fire_notice_range() != "":
		fire["noticed"] = true
		pending_events.append({"type": "fire_warning", "origin": fire["origin"], "late": true, "far": _fire_notice_range() == "far"})
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

func _rain_out_fire() -> void:
	var noticed: bool = bool(fire.get("noticed", false))
	if fire["phase"] == "warning":
		if noticed:
			log_message.emit(tr("fire.rain_warning"))
		fire = {}
		return
	for region_id in fire["regions"].keys():
		if not fire["burned"].has(region_id):
			fire["burned"].append(region_id)
			_region_burned(region_id)
	fire["regions"] = {}
	fire["rained_out"] = true
	if noticed:
		log_message.emit(tr("fire.rain_out"))
	_end_fire()

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
	# 起火前的徵兆只有人在森林裡才察覺得到；苔原林線要等真的燒起來、看到煙
	if bool(fire.get("noticed", false)) or _fire_notice_range() != "near":
		return
	var n: Dictionary = _fire_cfg().get("notice", {})
	var chance_value: float = min(float(n.get("max", 0.9)), float(n.get("base", 0.35)) + (wolf.effective_perception() - 40.0) * float(n.get("per_perception", 0.01)))
	if RNGService.chance(chance_value):
		fire["noticed"] = true
		pending_events.append({"type": "fire_warning", "origin": fire["origin"], "late": false})

# 察覺得到大火的範圍（1.7-1）：人在起火的地圖（森林）是 "near"；在和那張地圖相連的區域（苔原林線）只看得到遠處的煙，是 "far"；其他地方察覺不到，是 ""。
func _fire_notice_range() -> String:
	if fire.is_empty():
		return ""
	var fire_map: String = GameData.map_of(str(fire.get("origin", "")))
	if current_map() == fire_map:
		return "near"
	for link in GameData.links_from(current_region):
		if GameData.map_of(str(link["to"])) == fire_map:
			return "far"
	return ""

# 火燒到你所在的區域：跳出逃生選擇（待在同一區只提示一次；躲在溪邊或巢穴就不再提示）。entered：自己走進還在燒的區域。
func _check_fire_here(entered: bool = false) -> void:
	if fire.is_empty() or not wolf.alive or not fire.get("regions", {}).has(current_region):
		return
	if fire["alerted"].has(current_region) or fire["sheltered"] == current_region:
		return
	fire["alerted"].append(current_region)
	pending_events.append({"type": "fire_here", "region": current_region, "entered": entered})
	_year_flag("fire")

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
		# 濃煙竄進巢穴之後（第二次逃生選擇），「繼續躲」的危險比第一次高
		list.append(_escape_option("den_stay" if bool(fire.get("smoke", false)) else "den", ""))
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
	var probs := _fire_outcome_probs(float(opt["danger"]))
	var roll: float = RNGService.randf()
	var result: String = "safe"
	if roll < float(probs["death"]):
		result = "death"
	elif roll < float(probs["death"]) + float(probs["heavy"]):
		result = "heavy"
	elif roll < float(probs["death"]) + float(probs["heavy"]) + float(probs["light"]):
		result = "light"
	var flee: bool = opt["kind"] in ["flee", "other_map"]
	if not flee:
		# 躲在燃燒中的區域：直接快轉到這一區的火燒完（提案之十一）；巢穴途中可能濃煙竄入，跳第二次逃生選擇
		var hid := _hide_until_fire_passes(str(opt["kind"]))
		if hid == "smoke":
			record_decision("fire." + str(opt["kind"]))
			state_changed.emit()
			return {"result": "smoke", "kind": opt["kind"], "region": ""}
	if flee:
		fire.erase("smoke")
	# 一場大火裡最重的那次逃生記入一生回顧
	var order := ["safe", "light", "heavy", "death"]
	if fire.is_empty():
		# 躲到火燒完時大火已經結束、寫進紀錄了：補上這次的結果
		var fires: Array = life_log.get("fires", [])
		if not fires.is_empty() and order.find(result) >= order.find(str(fires.back().get("result", "safe"))):
			fires.back()["escape"] = opt["kind"]
			fires.back()["result"] = result
	elif not fire.has("result") or order.find(result) >= order.find(str(fire.get("result", "safe"))):
		fire["escape"] = opt["kind"]
		fire["escape_region"] = opt["region"]
		fire["result"] = result
	# 先記下逃生結果再過回合：大火可能在這一回合熄滅（_end_fire 會清空 fire），之後不能再寫 fire
	if flee:
		GameTime.advance_turns(1)
	if flee:
		wolf.stamina -= float(e.get("flee_stamina", 20))
		action_move_silent(str(opt["region"]))
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
			# 大火已在這一回合熄滅時，_end_fire 已經記下（結果是 death）
			if not fire.is_empty():
				_end_fire_on_death()
			_die("fire")
			return {"result": result, "kind": opt["kind"], "region": opt["region"]}
	wolf.clamp_stats()
	if wolf.injury_source == "fire" or result != "safe":
		life_log["burned"] = int(life_log.get("burned", 0)) + (1 if result != "safe" else 0)
	_check_fire_here()
	state_changed.emit()
	return {"result": result, "kind": opt["kind"], "region": opt["region"]}

# 躲在燃燒中的區域（溪流、巢穴）：一回合一回合過到這一區的火燒完或大火結束（照常扣飽食度，不回體力、不能做別的事）。
# 巢穴每過一個時段有機率濃煙竄入：停下來回傳 "smoke"（第二次逃生選擇）；繼續躲（den_stay）就不再判定。
func _hide_until_fire_passes(kind: String) -> String:
	fire["sheltered"] = current_region
	var cfg: Dictionary = _fire_cfg().get("hide", {})
	var smoke_chance: float = float(cfg.get("den_smoke_per_period", 0.3)) if kind == "den" else 0.0
	var max_turns: int = int(cfg.get("max_periods", 8)) * GameTime.TURNS_PER_PERIOD
	for i in range(max_turns):
		if fire.is_empty() or not fire.get("regions", {}).has(current_region) or not wolf.alive:
			break
		var period_before: int = GameTime.period_index
		GameTime.advance_turns(1)
		if smoke_chance > 0.0 and GameTime.period_index != period_before and not fire.is_empty() \
				and fire.get("regions", {}).has(current_region) and RNGService.chance(smoke_chance):
			fire["smoke"] = true
			fire["sheltered"] = ""
			return "smoke"
	return ""

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
	_year_flag("den_moved")
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

# 黑狼家族的換季更新（Phase 3a 第 1 步）。換代時建立新的帶頭的（黑狼的兒子），領域照舊。
func _update_black_pack() -> void:
	var leader := pack_leader()
	var core_before: String = str(black_pack.regions[0]) if not black_pack.regions.is_empty() else stranger_territory
	var beaten: bool = stranger() != null and (stranger().yielded_to_player or stranger().death_cause == "killed_by_player")
	var adjacent: Dictionary = {}
	for r in GameData.map_regions("forest"):
		adjacent[r] = EncounterSystem.region_data(r).get("adjacent", [])
	var events: Array = black_pack.on_season_passed({"season": GameTime.current_season(), "leader": leader,
		"player_age": wolf.age_years, "beaten": beaten, "den": den_region, "own": own_territories(), "adjacent": adjacent})
	if events.has("succession"):
		var core: String = str(black_pack.regions[0]) if not black_pack.regions.is_empty() else ""
		var heir := NpcWolf.create("black_heir", core)
		heir.age_years = snapped(max(2.0, black_pack.heir_age), 0.25)
		npcs["black_heir"] = heir
	if not events.is_empty():
		var log_list: Array = life_log.get("black_pack_events", [])
		for e in events:
			log_list.append({"event": e, "age": snapped(wolf.age_years, 0.25)})
		life_log["black_pack_events"] = log_list
	# 徵兆（第 2 步）：記下來，下一張森林的季節卡片寫出來（人不在森林時等回到森林）
	var news: Array = life_log.get("pack_news", [])
	for e in events:
		if e in PACK_NEWS:
			var region: String = str(black_pack.regions.back()) if e == "expanded" else (str(black_pack.regions[0]) if not black_pack.regions.is_empty() else core_before)
			news.append({"event": e, "region": region})
	if not news.is_empty():
		life_log["pack_news"] = news

const PACK_NEWS := ["paired", "pups", "expanded", "succession", "dissolved"]

# 徵兆的文字（第 2 步）：一對、狼群時，足跡、氣味、遠觀、標記、狼嚎多一句；獨居照舊（回傳空字串）。
func pack_sign_key(kind: String) -> String:
	if black_pack.stage in ["pair", "pack"]:
		return "pack.sign.%s.%s" % [kind, black_pack.stage]
	return ""

# 遠遠觀察黑狼：獨居照舊，一對、狼群換成描述牠們的句子；帶頭的老了再加一句。
func pack_observed_text_keys() -> Array:
	var keys: Array = ["encounter.observed.stranger_wolf" + ("." + black_pack.stage if black_pack.stage in ["pair", "pack"] else "")]
	var leader := pack_leader()
	if black_pack.stage in ["pair", "pack"] and leader != null and leader.alive and leader.life_stage_key() == "elder":
		keys.append("pack.sign.observed.old")
	return keys

# 狼嚎從哪一區傳來：成家後是牠們的核心領域（帶頭的換代後也一樣），獨居時是黑狼的範圍。
func howl_region() -> String:
	if black_pack.stage in ["pair", "pack"] and not black_pack.regions.is_empty():
		return str(black_pack.regions[0])
	return stranger_territory

# 黑狼家族帶頭的：第一代是黑狼，換代後是接手的兒子（black_heir）。
func pack_leader() -> NpcWolf:
	if black_pack.generation > 1:
		return npcs.get("black_heir", null)
	return stranger()

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
			_year_flag("stranger_win")
			# 第一次打贏牠的成長改由 _after_first_win 統一處理（2026-10-15）
			# 你贏了：牠占據的那一帶變成你的範圍，之後不再被驅趕
			life_log["own_territory"] = npc.territory
			var marks: Dictionary = life_log.get("marks", {})
			marks[npc.territory] = int(life_log.get("days_lived", 1)) # 打贏的那一帶接上地盤（1.9b 第 1 步）
			life_log["marks"] = marks
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
	var kills: int = max(0, RNGService.randi_range(int(wk.get("count_min", 1)), int(wk.get("count_max", 3))) + int(year_effects("winter").get("winter_kill_extra", 0)))
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
	# 人在苔原才看得到風雪停了；逃離苔原的話，下次回到苔原再看到風雪之後的景象（QA-69）
	if current_map() == _blizzard_map():
		_queue_notice({"type": "blizzard_over", "kills": kills})
	elif entry["in_tundra"]:
		life_log["blizzard_over_unseen"] = {"kills": kills}
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
	var big := big_river_crossing(target_region)
	if big != "":
		return big
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

# 草原的大河（Phase 2 第 4 步）：春季 flood（水急，先跳字卡）、夏季 deep、秋季 wade、冬季 frozen；不經過大河就是空字串。
func _big_river_cfg() -> Dictionary:
	return GameData.events.get("big_river", {})

func big_river_crossing(target_region: String) -> String:
	var river: String = str(_big_river_cfg().get("region", ""))
	if river == "" or (current_region != river and target_region != river) or not _link_to(target_region).is_empty():
		return ""
	match GameTime.current_season():
		"spring": return "flood"
		"summer": return "deep"
		"winter": return "frozen"
	return "wade"

# 渡過大河之後：春季可能被沖走一段，夏季水深比較累。回傳結果文字的鍵（沒事是空字串）。
func _after_big_river(kind: String) -> void:
	var cfg := _big_river_cfg()
	match kind:
		"deep":
			wolf.stamina -= float(cfg.get("deep_stamina", 6))
		"flood":
			if not RNGService.chance(float(cfg.get("flood_chance", 0.35))):
				return
			var swim: float = HuntSystem.clamp_chance(float(cfg.get("swim_base", 0.55)) + ((wolf.effective_speed() + wolf.effective_strength()) * 0.5 - 50.0) / float(cfg.get("swim_divisor", 150)))
			if RNGService.chance(swim):
				wolf.stamina -= float(cfg.get("ok_stamina", 10))
				log_message.emit(tr("river.flood.swept_ok"))
			else:
				var d: Array = cfg.get("fail_damage", [6, 14])
				wolf.stamina -= float(cfg.get("fail_stamina", 35))
				wolf.hunger -= float(cfg.get("fail_hunger", 8))
				FightRules.hurt_wolf(wolf, float(RNGService.randi_range(int(d[0]), int(d[1]))), {"leg": 0.6, "shoulder": 0.4}, "river.flood", false)
				log_message.emit(tr("river.flood.swept_bad"))
			life_log["river_swept"] = int(life_log.get("river_swept", 0)) + 1
	wolf.clamp_stats()

# 春融：春季進出河谷要過河，河冰可能在腳下裂開。
func _maybe_ice_break() -> void:
	var cfg := _ice_cfg()
	if GameTime.current_season() != str(cfg.get("season", "spring")) or not wolf.alive:
		return
	if RNGService.chance(float(cfg.get("move_chance", 0.2))):
		_learn_ice(true)
		pending_events.append({"type": "ice_break"})

# 選項：跳到對岸（看速度）、趴低慢慢爬到對岸（較穩，多花回合）。
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
	# 跟過渡鴉之後幾天內不再出現（QA-63）
	if int(life_log.get("days_lived", 1)) < int(life_log.get("ravens_cooldown_until", 0)):
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
	life_log["ravens_cooldown_until"] = int(life_log.get("days_lived", 1)) + int(cfg.get("follow_cooldown_days", 2)) + 1
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
# waiting：你正在吃時牠找上門（多半在附近等），趕走牠比較容易（1.8 第 8 步）。
func start_wolverine_combat(waiting: bool = false) -> Combat:
	identify("wolverine")
	var c := start_combat("wolverine", "adult", "carcass")
	c.set_npc(wolverine())
	if waiting:
		c.stake_mult *= float(_wolverine_cfg().get("waiting_stake_mult", 0.5))
	return c

# 狼獾的季節倍率（秋冬為主、夏季很少）
func wolverine_season_mult() -> float:
	var table: Dictionary = _wolverine_cfg().get("season_mult", {})
	var season: String = GameTime.current_season()
	var n: int = int(GameData.balance.get("season_day_count", {}).get(GameTime.time_mode, 10))
	if season == "winter" and GameTime.day > n / 2 and table.has("winter_late"):
		return float(table["winter_late"])
	return float(table.get(season, 1.0))

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

# 苔原狼現身的開頭句：上次見到的也只有一隻時，不說「這次只有牠一隻」（文案稽核 2026-10-16）。
# 每次看到牠們都記下這次有幾隻（note_tundra_seen）。
func tundra_meet_key(first: bool) -> String:
	var n: int = tundra_pair().size()
	var key: String = "tundra.meet.first." if first else "tundra.meet.again."
	if n > 1:
		key += "pair"
	elif not first and int(life_log.get("tundra_seen_size", 2)) <= 1:
		key += "single_same"
	else:
		key += "single"
	note_tundra_seen()
	return key

func note_tundra_seen() -> void:
	life_log["tundra_seen_size"] = tundra_pair().size()

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
	# 春夏育幼：留在巢穴附近（1.8 第 10 步）
	if tundra_pups() > 0 and GameTime.current_season() in ["spring", "summer"]:
		weights = {str(_breeding_cfg().get("den_region", "tundra_south")): 1}
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
	# 被狼群接納的方向（Phase 1.7b）：年輕的狼、或這對狼只剩一隻而你們已經熟悉時，關係比較容易變好
	if delta > 0 and (wolf.life_stage() == Wolf.LifeStage.SUBADULT \
			or (tundra_pair().size() == 1 and tundra_relation_key() in ["familiar", "friendly"])):
		delta = int(ceil(delta * float(GameData.balance.get("youth", {}).get("tundra_relation_mult", 1.0))))
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
	if not RNGService.chance(float(_tundra_cfg().get("meet_chance", 0.1)) * (float(_territory_cfg().get("tundra_meet_mult", 1.5)) if is_own_territory() else 1.0)):
		return false
	current_discovery = {"kind": "tundra_wolves", "location": _random_terrain(current_region), "first": not is_identified("tundra_wolf"),
		"charge": tundra_relation_key() == "hostile" and RNGService.chance(float(_tundra_effects().get("hostile_charge", 0.35)))}
	identify("tundra_wolf", false) # 第一次相遇的描述已經介紹牠們（一對住在苔原的灰狼），不另寫「那是一對苔原狼」
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
		c.partner_chance = clamp(c.partner_chance * tundra_count_effect(), 0.0, 0.7) # 數量多更危險（1.8 第 10 步）
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

func _joint_cfg() -> Dictionary:
	return _tundra_cfg().get("joint", {})

# 撞見苔原狼在追馴鹿或駝鹿（熟悉以上，1.8 第 9 步）
func _maybe_tundra_hunt() -> bool:
	if not _tundra_wolves_here() or blizzard_here() or wolf.life_stage() == Wolf.LifeStage.SUBADULT and wolf.age_years < 1.0:
		return false
	var key := tundra_relation_key()
	if not RNGService.chance(float(_joint_cfg().get("meet_chance", {}).get(key, 0.0))):
		return false
	var prey: Dictionary = {}
	var weights: Dictionary = EncounterSystem.region_data(current_region).get("prey_weights", {})
	for a in _joint_cfg().get("prey", []):
		var w: float = float(weights.get(a, {}).get(GameTime.current_season(), 0))
		if w > 0.0:
			prey[a] = w
	if prey.is_empty():
		return false
	current_discovery = {"kind": "tundra_hunt", "animal_id": RNGService.weighted_pick(prey), "location": _random_terrain(current_region)}
	return true

# 加入牠們的狩獵：直接從追擊開始（鹿群已經被衝散）
func join_tundra_hunt() -> HuntSystem:
	var d: Dictionary = current_discovery
	clear_discovery()
	record_decision("tundra.hunt.join")
	var h := start_hunt(str(d["animal_id"]), "adult", -1, false, str(d.get("location", "")))
	h.apply_tundra_help(tundra_adults(), true)
	return h

# 觀望：牠們有時獵到；熟悉以上可以在殘骸邊緣等著吃剩的。回傳 {"result": "killed"|"missed", "leftover"}。
func watch_tundra_hunt() -> Dictionary:
	var d: Dictionary = current_discovery
	clear_discovery()
	GameTime.advance_turns(1)
	record_decision("tundra.hunt.watch")
	Growth.learn_flat(wolf, "perception", "track_perception")
	var killed: bool = RNGService.chance(float(_joint_cfg().get("watch_kill", 0.4)))
	var leftover: bool = killed and tundra_relation_key() in ["familiar", "friendly"]
	if leftover:
		var a: String = str(d["animal_id"])
		var total: float = float(GameData.animals.get(a, {}).get("adult", {}).get("hunger_value", 0))
		var per: int = HuntSystem.feeding_segments(a, "adult")
		current_feeding = {"animal_id": a, "life_stage": "adult", "segments_left": int(_joint_cfg().get("leftover_segments", 1)),
			"segment_value": total / max(1, per), "turns_stayed": 0, "terrain": str(d.get("location", "")), "shared": true}
	_tundra_record("hunt", "watched_" + ("killed" if killed else "missed"))
	state_changed.emit()
	return {"result": "killed" if killed else "missed", "leftover": leftover}

# --- 苔原狼繁殖（1.8 第 10 步）---
# life_log["tundra_young"]：{"pups": 今年的幼狼隻數, "young": 年輕的成狼隻數（= young_ages 的隻數 + settled）,
# "young_ages": [還沒定下來的年輕成狼的年齡…], "settled": 決定留下來當幫手的隻數, "born": [出生時你的年齡…], "knows_you": 生下時關係熟悉以上}
func _breeding_cfg() -> Dictionary:
	return _tundra_cfg().get("breeding", {})

func _tundra_young() -> Dictionary:
	return life_log.get("tundra_young", {"pups": 0, "young": 0})

func tundra_pups() -> int:
	return int(_tundra_young().get("pups", 0)) if not tundra_pair().is_empty() else 0

func tundra_young_adults() -> int:
	return int(_tundra_young().get("young", 0)) if not tundra_pair().is_empty() else 0

# 會幫忙的成狼隻數（這對狼 + 年輕的成狼；當年的幼狼不算）
func tundra_adults() -> int:
	return tundra_pair().size() + tundra_young_adults()

# 看得到的隻數：秋冬幼狼開始跟著行動
func tundra_pack_size() -> int:
	var n: int = tundra_adults()
	if GameTime.current_season() in ["autumn", "winter"]:
		n += tundra_pups()
	return n

# 隻數的效果（遞減，約 4 隻到頂）
func tundra_count_effect(count: int = -1) -> float:
	var table: Array = _breeding_cfg().get("count_effect", [0.0, 1.0, 1.0])
	var n: int = tundra_adults() if count < 0 else count
	return float(table[clamp(n, 0, table.size() - 1)])

# 嚴冬或馴鹿少的年（第 11 步的年況接上；目前看 life_log.year_harsh）
func _harsh_year() -> bool:
	return bool(life_log.get("year_harsh", false))

func _tundra_breeding_season() -> void:
	var cfg := _breeding_cfg()
	var y: Dictionary = _tundra_young()
	if tundra_pair().is_empty():
		life_log["tundra_young"] = {"pups": 0, "young": 0}
		return
	match GameTime.current_season():
		"spring":
			# 年輕的成狼：2～3 歲才可能離群，也可能一直留下來當幫手（2026-10-15 試玩回報 18，使用者決定）
			var ages: Array = y.get("young_ages", [])
			if ages.is_empty() and int(y.get("young", 0)) > int(y.get("settled", 0)):
				for i in int(y["young"]) - int(y.get("settled", 0)): # 舊紀錄沒有年齡：當成 1 歲
					ages.append(1)
			# 留下來的幫手也會老、會死（每年 settled_death），不然十幾年後會塞滿整群
			var settled: int = int(y.get("settled", 0))
			for i in settled:
				if RNGService.chance(float(cfg.get("settled_death", 0.15))):
					y["settled"] = int(y["settled"]) - 1
			var leave_chance: Dictionary = cfg.get("leave_chance", {"2": 0.5, "3": 0.7})
			var kept: Array = []
			var left: int = 0
			for a in ages:
				var age: int = int(a) + 1
				var c: float = float(leave_chance.get(str(mini(age, 3)), 0.0))
				if c > 0.0 and RNGService.chance(c):
					left += 1
				elif age >= 3:
					y["settled"] = int(y.get("settled", 0)) + 1 # 3 歲還沒走：長期留下
				else:
					kept.append(age)
			# 活過冬天的幼狼算 1 歲的年輕成狼；兩隻都活著才生
			for i in int(y.get("pups", 0)):
				kept.append(1)
			y["pups"] = 0
			var chance: float = float(cfg.get("birth_chance", 0.8)) * (float(cfg.get("harsh_mult", 0.5)) if _harsh_year() else 1.0)
			if tundra_pair().size() >= 2 and RNGService.chance(chance):
				var l: Array = cfg.get("litter", [3, 4])
				y["pups"] = RNGService.randi_range(int(l[0]), int(l[1]))
				y["knows_you"] = tundra_relation_key() in ["familiar", "friendly"]
				var born: Array = y.get("born", [])
				born.append(snapped(wolf.age_years, 0.1))
				y["born"] = born
				life_log["tundra_litters"] = int(life_log.get("tundra_litters", 0)) + 1
			# 整群最多 max_pack 隻：超過時年紀最大、還沒定下來的先走
			var over: int = tundra_pair().size() + kept.size() + int(y.get("settled", 0)) + int(y["pups"]) - int(cfg.get("max_pack", 10))
			if over > 0:
				kept.sort()
				var leave: int = mini(over, kept.size())
				kept = kept.slice(0, kept.size() - leave)
				left += leave
			y["young_ages"] = kept
			y["young"] = kept.size() + int(y.get("settled", 0))
			if left > 0 and is_identified("tundra_wolf"):
				log_message.emit(tr("tundra.young_left" + (".many" if left > 1 else "")).replace("{n}", str(left)))
		"autumn", "winter":
			var p: float = float(cfg.get("pup_death", 0.3)) * (float(cfg.get("harsh_death_mult", 1.4)) if _harsh_year() else 1.0)
			var alive: int = 0
			for i in int(y.get("pups", 0)):
				if not RNGService.chance(p):
					alive += 1
			y["pups"] = alive
	life_log["tundra_young"] = y

# 在巢穴區探索：發現巢穴的線索，或撞見灰熊朝巢穴走去（春夏、有幼狼時）
func _maybe_tundra_den() -> bool:
	var cfg := _breeding_cfg()
	if tundra_pups() <= 0 or not GameTime.current_season() in ["spring", "summer"] or blizzard_here():
		return false
	if current_region != str(cfg.get("den_region", "tundra_south")) or not _tundra_wolves_here():
		return false
	var bear_ok: bool = float(EncounterSystem.region_data(current_region).get("competitor_weights", {}).get("grizzly_bear", {}).get(GameTime.current_season(), 0)) > 0.0
	if bear_ok and is_identified("grizzly_bear") and RNGService.chance(float(cfg.get("den_bear", {}).get("chance", 0.04))):
		current_discovery = {"kind": "tundra_den_bear", "location": _random_terrain(current_region),
			"mother": RNGService.chance(float(_bear_phase_cfg().get("mother", 0.0)))}
		return true
	if RNGService.chance(float(cfg.get("den_clue_chance", 0.08))):
		current_discovery = {"kind": "tundra_den", "location": _random_terrain(current_region), "pups": tundra_pups()}
		return true
	return false

# 靠近巢穴：友善時牠們讓你看一眼；否則拚命保護（關係下降，可能撲上來）。回傳 {"result": "seen"|"warned"|"charge"}。
func approach_tundra_den() -> Dictionary:
	clear_discovery()
	GameTime.advance_turns(1)
	record_decision("tundra.den.approach")
	if tundra_relation_key() == "friendly":
		_tundra_record("den", "seen")
		state_changed.emit()
		return {"result": "seen"}
	_tundra_relation_add("den_intrude")
	var charge: bool = RNGService.chance(float(_breeding_cfg().get("den_charge", 0.4)))
	_tundra_record("den", "charged" if charge else "warned")
	state_changed.emit()
	return {"result": "charge" if charge else "warned"}

func tundra_den_threaten_chance(mother: bool) -> float:
	var b: Dictionary = _breeding_cfg().get("den_bear", {})
	var c: float = float(b.get("threaten_base", 0.72)) + float(b.get("per_adult", 0.04)) * max(0, tundra_adults() - 2) \
		+ (FightRules.wolf_power(wolf) - 60.0) / float(b.get("power_divisor", 200))
	if mother:
		c -= float(b.get("mother_penalty", 0.15))
	return HuntSystem.clamp_chance(c)

func _lose_tundra_pup() -> bool:
	var y: Dictionary = _tundra_young()
	if int(y.get("pups", 0)) <= 0:
		return false
	y["pups"] = int(y["pups"]) - 1
	life_log["tundra_young"] = y
	return true

# 一起威嚇灰熊（熟悉以上）。回傳 {"result": "drove_off"|"fight"}；"fight" 時接 start_den_combat。
func den_bear_threaten() -> Dictionary:
	var d: Dictionary = current_discovery
	record_decision("tundra.den.threaten")
	GameTime.advance_turns(1)
	if RNGService.chance(tundra_den_threaten_chance(bool(d.get("mother", false)))):
		clear_discovery()
		_tundra_relation_add("den_defend")
		_tundra_record("den", "bear_driven_off")
		life_log["den_defended"] = int(life_log.get("den_defended", 0)) + 1
		_year_flag("tundra")
		state_changed.emit()
		return {"result": "drove_off"}
	return {"result": "fight"}

# 熊沒被嚇退：和熊打，苔原狼同一邊（隻數越多越常插進來）；熊沒有要守什麼，比搶食時更早離開。
func start_den_combat() -> Combat:
	var d: Dictionary = current_discovery
	clear_discovery()
	var c := start_combat("grizzly_bear", "adult", "den", {"mother": bool(d.get("mother", false))})
	var b: Dictionary = _breeding_cfg().get("den_bear", {})
	c.ally_chance = clamp(float(b.get("ally_base", 0.2)) + float(b.get("ally_per_adult", 0.08)) * tundra_adults() * tundra_count_effect() / max(1.0, float(tundra_adults())), 0.0, 0.7)
	c.ally_damage = b.get("ally_damage", [6, 12])
	c.phase = Combat.Phase.EXCHANGE
	return c

func _after_den_combat(c: Combat) -> void:
	if c.won():
		_tundra_relation_add("den_defend")
		_tundra_record("den", "bear_fought_off", c.damage_taken)
		life_log["den_defended"] = int(life_log.get("den_defended", 0)) + 1
		_year_flag("tundra")
	else:
		var lost: bool = RNGService.chance(float(_breeding_cfg().get("den_bear", {}).get("lose_pup", 0.6))) and _lose_tundra_pup()
		_tundra_record("den", "pup_lost" if lost else "bear_stayed", c.damage_taken)
		c.set_meta("pup_lost", lost)

# 旁觀：苔原狼自己守。回傳 {"result": "held"|"pup_lost"|"lost_nothing"}。
func den_bear_watch() -> Dictionary:
	clear_discovery()
	record_decision("tundra.den.watch")
	GameTime.advance_turns(1)
	var b: Dictionary = _breeding_cfg().get("den_bear", {})
	var result: String = "held"
	if not RNGService.chance(float(b.get("watch_hold", 0.8))):
		result = "pup_lost" if RNGService.chance(float(b.get("lose_pup", 0.6))) and _lose_tundra_pup() else "lost_nothing"
	_tundra_record("den", "watched_" + result)
	state_changed.emit()
	return {"result": result}

func _mob_cfg() -> Dictionary:
	return _tundra_cfg().get("mob", {})

func _maybe_tundra_mob() -> bool:
	if not _tundra_wolves_here() or tundra_pair().size() < 2 or not _wolverine_alive() or blizzard_here():
		return false
	if not _mob_cfg().get("seasons", ["autumn", "winter"]).has(GameTime.current_season()):
		return false
	if not RNGService.chance(float(_mob_cfg().get("mob_chance", 0.05)) * wolverine_season_mult()):
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
		_mob_share(c.terrain)

# 在旁邊看：多半是狼獾被趕走，偶爾被咬死。回傳 {"result": "drove_off"|"killed"|"held"}。
func watch_tundra_mob() -> Dictionary:
	clear_discovery()
	GameTime.advance_turns(1)
	var m := _mob_cfg()
	var result: String = "held"
	var roll: float = RNGService.randf()
	var kill: float = float(m.get("watch_kill", 0.1))
	var drive: float = min(0.85, float(m.get("watch_drive_off", 0.55)) * tundra_count_effect())
	if roll >= kill + drive and roll < kill + drive + float(m.get("watch_both_left", 0.15)):
		result = "both_left"
	elif roll < kill:
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

# 圍攻狼獾時的分到的肉（馴鹿殘骸的一段）
func _mob_share(terrain: String) -> void:
	var segments: int = int(_mob_cfg().get("share_segments", 1))
	var total: float = float(GameData.animals.get("caribou", {}).get("adult", {}).get("hunger_value", 0))
	var per: int = HuntSystem.feeding_segments("caribou", "adult")
	current_feeding = {"animal_id": "caribou", "life_stage": "adult", "segments_left": segments,
		"segment_value": total / max(1, per), "turns_stayed": 0, "terrain": terrain, "shared": true}

# 幫狼獾（1.8 第 8 步）：和苔原狼交手；牠們退開後你和狼獾分食。不論成敗都算動手。回傳 {"result": "won"|"lost", "damage"}。
func mob_side_wolverine() -> Dictionary:
	var terrain: String = str(current_discovery.get("location", ""))
	clear_discovery()
	GameTime.advance_turns(1)
	record_decision("tundra.mob.side_wolverine")
	var m := _mob_cfg()
	var leader := tundra_leader()
	var chance: float = HuntSystem.clamp_chance(float(m.get("side_base", 0.35)) + (FightRules.wolf_power(wolf) - leader.power()) / float(m.get("side_divisor", 120)))
	var won: bool = RNGService.chance(chance)
	var d: Array = m.get("side_damage" if won else "side_fail_damage", [8, 16])
	var dmg: float = float(FightRules.hurt_wolf(wolf, float(RNGService.randi_range(int(d[0]), int(d[1]))), _tundra_cfg_parts(), "tundra_wolf.carcass", false)["damage"])
	_tundra_relation_add("fight")
	_tundra_record("mob", "sided_wolverine_" + ("won" if won else "lost"), dmg)
	if won:
		_mob_share(terrain)
	_check_death()
	state_changed.emit()
	return {"result": "won" if won else "lost", "damage": dmg}

# 自己搶（1.8 第 8 步）：趁亂去咬殘骸；苔原狼或狼獾可能轉而對付你，關係小降。回傳 {"result": "got"|"missed", "turned", "damage"}。
func mob_grab() -> Dictionary:
	var terrain: String = str(current_discovery.get("location", ""))
	clear_discovery()
	GameTime.advance_turns(1)
	record_decision("tundra.mob.grab")
	var m := _mob_cfg()
	var got: bool = RNGService.chance(float(m.get("grab_chance", 0.7)))
	var turned: bool = RNGService.chance(float(m.get("grab_turn", 0.35)))
	var dmg: float = 0.0
	if turned:
		var d: Array = m.get("grab_damage", [6, 14])
		dmg = float(FightRules.hurt_wolf(wolf, float(RNGService.randi_range(int(d[0]), int(d[1]))), _tundra_cfg_parts(), "tundra_wolf.carcass", false)["damage"])
	_tundra_relation_add("grab")
	_tundra_record("mob", "grabbed_" + ("got" if got else "missed"), dmg)
	if got:
		_mob_share(terrain)
	_check_death()
	state_changed.emit()
	return {"result": "got" if got else "missed", "turned": turned, "damage": dmg}

func _tundra_cfg_parts() -> Dictionary:
	return NpcWolf.cfg("tundra_wolf").get("combat", {}).get("parts", {"leg": 0.5, "shoulder": 0.5})

# 苔原狼的體型和你相比（1.8 第 8 步）："bigger" 牠們比你高大、"equal" 差不多、"smaller" 你比牠們壯。
func tundra_size_key() -> String:
	var leader := tundra_leader()
	if leader == null:
		return "equal"
	match power_compare(leader.power()):
		"much_stronger", "stronger":
			return "bigger"
		"much_weaker", "weaker":
			return "smaller"
	return "equal"

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
		_apply_age_decay()
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
	identify("tundra_wolf", false)
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

# 獵物靠近：照這一區這一季的動物挑（苔原是雪兔或小馴鹿，森林是野兔或幼鹿）。
func debug_prey_nearby() -> void:
	var cfg: Dictionary = _events_cfg().get("prey_nearby", {})
	var animal: String = _nearby_prey_pick(cfg)
	if animal == "":
		return
	_queue_event({"type": "prey_nearby", "animal_id": animal,
		"life_stage": str(cfg.get("life_stage", {}).get(animal, "adult")), "terrain": _random_terrain(current_region)})

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
		"notables": notables,
		"snow": snow,
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
		"black_pack": black_pack.to_dict(),
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
		# 還沒顯示的字卡與事件、今天睡覺的傷勢好轉：存檔後離開再讀檔不會不見（文案一致性 D，2026-10-16）
		"pending_events": pending_events,
		"sleep_heal": _sleep_heal,
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
	notables = data.get("notables", [])
	snow = data.get("snow", {})
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
	# 2026-10-08 以前的 bug：大火熄滅的那一回合逃生，會留下沒有 phase 的殘缺資料
	if not fire.is_empty() and not fire.has("phase"):
		fire = {}
	region_burn = data.get("region_burn", {})
	fire_at = int(data.get("fire_at", -1))
	fire_season = str(data.get("fire_season", ""))
	last_fire_abs = int(data.get("last_fire_abs", -100000))
	npcs = {}
	for npc_id in data.get("npcs", {}).keys():
		npcs[npc_id] = NpcWolf.from_dict(data["npcs"][npc_id])
	if not npcs.has("stranger_wolf"):
		npcs["stranger_wolf"] = NpcWolf.create("stranger_wolf", stranger_territory)
	black_pack = WolfPack.from_dict(data.get("black_pack", {"regions": [stranger_territory] if stranger_territory != "" else []}))
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
	pending_events = data.get("pending_events", [])
	_sleep_heal = int(data.get("sleep_heal", -1))
	var t: Dictionary = data.get("time", {})
	GameTime.time_mode = t.get("time_mode", "normal")
	GameTime.season_index = int(t.get("season_index", 3))
	GameTime.day = int(t.get("day", 1))
	GameTime.period_index = int(t.get("period_index", 0))
	GameTime.turn_in_period = int(t.get("turn_in_period", 0))
	_connect_time_signals()
	_apply_env_perception()
	state_changed.emit()
