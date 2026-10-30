class_name AutoPlayer
extends RefCounted

# 除錯「模擬到死亡」：依選定的獵物偏好與風格，自動玩完一隻狼的一生（規則同 tools/sim 的機器人）。
# 由畫面層每個 frame 呼叫 step()，一次推進幾天；GameState.auto_playing 期間不產生提示卡片。
# prey："all" 遇到什麼吃什麼、"small_only" 只吃小獵物、"deer_focus" 以鹿為主（餓了才吃小獵物）。
# style："average" 每步選成功率最高、"pursuit" 偏追獵（不觀察、追擊選衝刺或跟隨）、
# "stealth" 偏潛伏（觀察、潛近選繞下風、伏低、伏擊等）、"cautious" 謹慎（觀察、潛伏、追不到就放棄、避開灰熊）、
# "assault" 強攻（正面接近、直取咽喉、迎戰灰熊）。
# 除錯「跳到次成年期最後一天」用 start_from_current() + stop_before_adult。

const MAX_YEARS := 15.0
# 照常過日子時不必停下的小事件：照常處理（獵物靠近就獵、聽到狼嚎、下雨）
const ROUTINE_IGNORE := ["prey_nearby", "howl", "storm", "storm_end", "after_rain", "rain_stopped"]
# 照常過日子期間排進的字卡（GameState._queue_notice）：留到結束後顯示，不讓它們打斷（2026-10-15 試玩 BUG-12）
const ROUTINE_NOTICES := ["season_card", "blizzard_over", "yearling", "elder_transition", "adult_transition", "year_review",
	"tendency_changed", "first_big_kill", "fire_over", "stranger_killed"]
const MAX_ACTIONS_PER_DAY := 80

var prey: String
var style: String
# 會判斷獵物（Phase 2b 第 3 步，模擬「理性選擇」）：先試探，健康的中大型獵物不太餓時就放棄。照常過日子也用。
var judge: bool = true
# 模擬用：false 時白尾鹿也用選單式狩獵（和 Phase 2b 比較）
var tactical: bool = true
var daytime_rest: bool = true # Phase 2j：不餓、體力不滿時白天休息到黃昏（模擬對照可以關掉）
const DAY_REST_HUNGER := 70.0
const DAY_REST_STAMINA := 95.0
var _slept_day: int = -1
var _sought_spot_day: int = -1
# 模擬用：不是空的時候，只有這些動物走戰術地圖（Phase 2d 第 5 步對照）
var tactical_only: Array = []
# 藏食物（Phase 2e 第 3 步）：離開殘骸前有剩就藏；沒有殘骸、肚子空出來時吃藏肉；餓了走去藏肉的區域。false 時不藏（模擬對照）
var cache: bool = true
const JUDGE_HUNGER := 40.0
var stop_before_adult: bool = false
# 四處走動（Phase 3a 第 6 步的驗證）：每天清晨有一半機會換到同一張地圖的相鄰區域，不回巢穴
var roam: bool = false
# 找伴侶（Phase 3 第 2 步）：never 不嚎叫；sometimes 秋冬每 3 天嚎叫一次；always 秋冬每天嚎叫。母狼在附近時都會嚎叫叫牠過來
var mate_search: String = "sometimes"
var _howled_day: int = -1
# 四處走動時，夜裡先走回巢穴再睡（模擬對照：四處走動的狼變餓，是不是因為睡在野外）
var roam_sleep_home: bool = false
# 牧場（Phase 4a 第 5 步，ranch.json auto）：never 不去、sometimes 餓了而且注意不高才去、often 注意 < 70 就去；預設照打法
var ranch_policy: String = ""
var ranch_moves: int = 0 # 因為牧場的注意搬巢穴的次數（模擬記錄用）
var _relocate_to: String = ""
var _ranch_hunting: bool = false # 這一步留在放牧地找家畜（不回巢穴）
var explores: int = 0 # 探索次數（模擬記錄用：牧場出現後探索有沒有萎縮）
# 「照常過日子」（Phase 1.7b，提案之十 E）：代為行動 routine_days 天，遇到值得注意的事就停下、交還給玩家。
# routine_style："small" 在附近獵小獵物、"big" 找大型獵物、"heal" 養傷（待在巢穴休息）。
var routine: bool = false
var routine_style: String = "small"
var routine_end_day: int = 0
var routine_start_injury: int = 0
var routine_start_season: int = 0
var stop_reason: String = ""
var stop_encounter: Dictionary = {}
var stop_scavenger: String = "" # 照常過日子進食時有東西來搶：停下交給玩家（2026-10-15 試玩回報 23）
var _finished: bool = false
var _encounter: Dictionary = {}
var _roamed_today: Dictionary = {}

# 偏好的選項依順序，有就選（不看成功率）；都沒有才從其餘選項挑成功率最高的。
const PREFER := {
	"pursuit": ["skip_observe", "pounce", "sprint", "follow"],
	"stealth": ["observe", "creep_pounce", "ambush", "wait", "downwind", "upstream", "edge_strike", "bite_leg", "dodge"],
	"cautious": ["observe", "creep_pounce", "wait", "downwind", "upstream", "ambush", "edge_strike", "dodge"],
	"assault": ["skip_observe", "pounce", "direct", "attack_standing", "bite_throat"],
}
const AVOID := {
	"stealth": ["direct", "bite_throat"],
	"cautious": ["direct", "attack_standing", "bite_throat"],
}

func _init(prey_policy: String, style_policy: String) -> void:
	prey = prey_policy
	style = style_policy
	ranch_policy = str(_ranch_auto().get("styles", {}).get(style_policy, "sometimes"))

func start(den: String) -> void:
	GameState.auto_playing = true
	GameState.new_game(den)
	_connect()

# 從目前這隻狼接著玩（不開新局）。
func start_from_current() -> void:
	GameState.auto_playing = true
	_connect()

func _connect() -> void:
	if not GameState.encounter_triggered.is_connected(_on_encounter):
		GameState.encounter_triggered.connect(_on_encounter)

# 活過上限年齡還沒死，就以老死結束（避免無限跑下去）。
func finish() -> void:
	if GameState.encounter_triggered.is_connected(_on_encounter):
		GameState.encounter_triggered.disconnect(_on_encounter)
	GameState.auto_playing = false

func done() -> bool:
	return _finished or GameState.wolf == null or not GameState.wolf.alive

func step(days: int) -> void:
	for i in days:
		if done():
			return
		if stop_before_adult and GameState.is_last_subadult_day():
			_finished = true
			return
		if GameState.wolf.age_years >= MAX_YEARS:
			GameState.debug_end_life("old_age")
			return
		_play_day()

func _on_encounter(encounter: Dictionary) -> void:
	_encounter = encounter

# 開始照常過日子（呼叫端要先設 GameState.auto_playing = true）。
func start_routine(days: int, style_policy: String) -> void:
	routine = true
	routine_style = style_policy
	prey = "small_only" if style_policy != "big" else "deer_focus"
	style = "cautious"
	ranch_policy = "never"
	routine_end_day = int(GameState.life_log.get("days_lived", 1)) + days
	routine_start_injury = GameState.wolf.injury
	routine_start_season = GameTime.season_index
	_connect()

# 照常過日子要不要停下：有遭遇或事件、受傷變重、餓或血量低、換季到期、天數到了。
func _routine_stop() -> bool:
	if not _encounter.is_empty():
		stop_reason = "encounter"
		stop_encounter = _encounter
		_encounter = {}
	elif GameState.pending_events.any(func(e): return not ROUTINE_IGNORE.has(str(e.get("type", ""))) and not ROUTINE_NOTICES.has(str(e.get("type", "")))):
		stop_reason = "event"
	elif GameState.wolf.injury > routine_start_injury:
		stop_reason = "injured"
	elif GameState.wolf.hunger < 40.0 and routine_style != "heal":
		stop_reason = "hungry"
	elif GameState.wolf.hunger < 25.0:
		stop_reason = "hungry"
	elif GameState.wolf.health < GameState.wolf.health_max * 0.5 and routine_style != "heal":
		stop_reason = "hurt"
	elif GameTime.season_index != routine_start_season:
		# 季節要睡覺才換：到期時照常過到睡覺換季，換了才停（原本到期就停，按幾次都是「過了 0 天」，試玩 BUG-10）
		stop_reason = "season"
	elif int(GameState.life_log.get("days_lived", 1)) >= routine_end_day:
		stop_reason = "done"
	elif routine_style == "heal" and GameState.wolf.injury == Wolf.Injury.NONE and GameState.wolf.health >= GameState.wolf.health_max * 0.95:
		stop_reason = "healed"
	if stop_reason != "":
		_finished = true
		return true
	return false

func _play_day() -> void:
	var start_day: int = GameTime.day
	var guard := 0
	while not done() and GameTime.day == start_day and guard < MAX_ACTIONS_PER_DAY:
		guard += 1
		if routine and _routine_stop():
			return
		_handle_pending()
		if done():
			return
		if routine and routine_style == "heal":
			if GameTime.current_period() == "predawn":
				GameState.action_sleep()
			elif not _go_home():
				GameState.action_short_rest()
			continue
		# 晨昏節奏（Phase 2j）：夜裡睡一覺，黎明前、清晨醒著出獵；原本在黎明前睡、常睡過頭錯過清晨
		if daytime_rest:
			if GameTime.current_period() == "night" and _slept_day != GameTime.day:
				if roam and roam_sleep_home and _go_home():
					continue
				# 不在巢穴、這一區還沒找過睡處：先找一次（真人在野外過夜會先找；原本直接勉強過夜，只回復四成）
				if GameState.sleep_quality() == "rough" and _sought_spot_day != GameTime.day:
					_sought_spot_day = GameTime.day
					GameState.action_find_sleep_spot()
					continue
				_slept_day = GameTime.day
				GameState.action_sleep()
				continue
		elif GameTime.current_period() == "predawn":
			GameState.action_sleep()
			continue
		if _ranch_step():
			continue
		# 吃撐、太累、或守著殘骸還不餓：休息（Phase 2b 第 1 步：吃一頓大型獵物撐好幾天）
		if GameState.wolf.hunger > 110 or GameState.wolf.stamina < 35 \
				or (GameState.carcass_index_here() >= 0 and GameState.wolf.hunger >= 95.0):
			GameState.action_short_rest()
			continue
		# 殘骸還在這一區、肚子空出來了：回去吃（Phase 2b 第 1 步）
		if GameState.carcass_index_here() >= 0 and GameState.wolf.hunger < 95.0:
			var rc: Dictionary = GameState.action_return_to_carcass()
			if str(rc.get("event", "")) != "" and routine:
				# 照常過日子：搶食交給玩家（同 _feed_loop）
				stop_reason = "scavenger"
				stop_scavenger = str(rc["event"])
				_finished = true
				return
			if str(rc.get("event", "")) != "":
				_scavenger(str(rc["event"]))
			_feed_loop()
			continue
		# 藏起來的肉：這一區有就吃（過了新鮮期的很餓才吃）；別區有、餓了就走過去
		if cache and _eat_cache_here():
			continue
		if cache and GameState.wolf.hunger < 60.0 and _go_cache():
			continue
		# 晨昏出獵、白天休息（Phase 2j）：不餓、體力不滿時白天休息到黃昏；餓了或體力夠就照樣活動
		if daytime_rest and GameTime.current_period() == "day" and GameState.wolf.hunger >= DAY_REST_HUNGER and GameState.wolf.stamina < DAY_REST_STAMINA:
			GameState.action_rest_until("dusk")
			continue
		if _maybe_howl():
			continue
		if roam:
			if GameTime.current_period() == "dawn" and not bool(_roamed_today.get(GameTime.day, false)):
				_roamed_today = {GameTime.day: true}
				var adj: Array = GameState.adjacent_regions().filter(func(r): return GameData.map_of(r) == GameState.current_map())
				if not adj.is_empty() and RNGService.chance(0.5):
					GameState.action_move(adj[RNGService.randi_range(0, adj.size() - 1)])
					continue
		elif not _ranch_hunting and _go_home():
			continue
		_explore_once()

# 處理遭遇與事件佇列（自動遊玩時不會顯示畫面）。
func _handle_pending() -> void:
	while not _encounter.is_empty() and not done():
		var e := _encounter
		_encounter = {}
		if e.get("distant", false):
			if style == "assault":
				GameState.action_observe_distant(e)
			else:
				GameState.leave_distant(e)
		elif e.get("stranger_meet", false):
			_meet_stranger()
		else:
			play_combat(GameState.start_combat(str(e.get("animal_id", "grizzly_bear")), str(e.get("life_stage", "adult")), "encounter", e))
	var kept: Array = [] # 照常過日子時，字卡留著給玩家看
	while not done():
		var event := GameState.pop_event()
		if event.is_empty():
			break
		if routine and ROUTINE_NOTICES.has(str(event.get("type", ""))):
			kept.append(event)
			continue
		match event.get("type", ""):
			"driven_off":
				GameState.apply_drive_off()
			"fire_here":
				# 巢穴濃煙竄入時會再選一次（提案之十一）；火已經熄了就不用選
				for attempt in 3:
					if GameState.fire.is_empty():
						break
					var best: Dictionary = {}
					for o in GameState.fire_escape_options():
						if best.is_empty() or float(o["safe"]) > float(best["safe"]):
							best = o
					if best.is_empty():
						break
					if str(GameState.fire_escape(str(best["id"])).get("result", "")) != "smoke":
						break
			"pack_meet":
				# 撞上黑狼一家（Phase 3a 第 3 步）：強攻型對峙或打落單的年輕狼，其他打法退開（被逼近時逃）
				if str(event.get("lone", "")) == "young":
					if style == "assault":
						play_combat(GameState.start_pack_young_combat())
					else:
						GameState.pack_young_avoid()
				elif style == "assault":
					GameState.pack_standoff()
				elif bool(event.get("charge", false)):
					GameState.pack_flee()
				else:
					GameState.pack_retreat()
			"stranger_confront":
				if style == "assault":
					play_combat(GameState.start_stranger_combat("territory"))
				else:
					GameState.stranger_yield_territory()
			"bear_passing":
				GameState.resolve_bear_passing(event, "leave")
			"ranch_humans":
				# 牧場的人類遭遇（Phase 4a 第 4 步）：照本能，每一步挑成功率最高的
				GameState.start_ranch_encounter(str(event.get("kind", "patrol")))
				GameState.ranch_auto_play()
			"blizzard_here":
				_pick_safest(GameState.blizzard_options(), "safe", func(id): GameState.blizzard_choose(id))
			"tundra_howl":
				GameState.tundra_howl_reply(style != "assault")
			"tundra_come":
				if event.get("charge", false):
					play_combat(GameState.start_tundra_combat("meet", true))
				else:
					_meet_tundra()
			"ice_break":
				_pick_safest(GameState.ice_break_options(), "chance", func(id): GameState.ice_break_choose(id))
			"ravens":
				# 餓了才跟著渡鴉去找屍體
				if GameState.wolf.hunger < 80.0 and GameState.ravens_follow(event).get("found", false) and not done():
					var res := GameState.action_return_to_carcass()
					if str(res.get("event", "")) != "":
						_scavenger(str(res["event"]))
					_feed_loop()
	GameState.pending_events.append_array(kept)

func _explore_once() -> void:
	explores += 1
	var d: Dictionary = GameState.action_explore()
	# 照常過日子：值得注意的發現（危險的線索、其他狼、殘骸、地點、記著的那頭…）留給玩家
	if routine and _routine_notable(d):
		stop_reason = "discovery"
		_finished = true
		return
	if d.get("kind", "") == "tundra_wolves":
		_meet_tundra(bool(d.get("charge", false)))
		return
	if d.get("kind", "") == "she_wolf":
		_meet_she_wolf(d)
		return
	if d.get("kind", "") == "tundra_mob":
		# 強攻型幫苔原狼，謹慎型離開，其他在旁邊看
		match style:
			"assault":
				play_combat(GameState.start_mob_combat())
				_feed_loop()
			"cautious":
				GameState.leave_tundra_mob()
			_:
				GameState.watch_tundra_mob()
		return
	if d.get("kind", "") == "pack_remains":
		# 黑狼一家吃剩的殘骸（Phase 3a 第 4 步）：餓了才撿，謹慎型在牠們的領域不撿；一段一段吃，被發現就停
		if GameState.wolf.hunger < 80 and not (style == "cautious" and str(d.get("zone", "")) == "core"):
			while GameState.current_discovery.get("kind", "") == "pack_remains" and GameState.wolf.hunger < 120:
				if GameState.eat_pack_remains()["caught"]:
					break
		GameState.clear_discovery()
		return
	if d.get("kind", "") == "salmon":
		# 鮭魚洄流（Phase 2h 第 5 步）：餓了、體力夠才去河邊，照局勢換位，吃到 stop_at 就走；不硬撐
		var sa: Dictionary = GameData.balance.get("salmon", {}).get("auto", {})
		if GameState.salmon_fishing_enabled() and GameState.wolf.hunger < float(sa.get("go_below", 110)) and GameState.wolf.stamina >= float(sa.get("min_stamina", 20)):
			var rf := GameState.start_salmon_fishing()
			var guard := 0
			while not rf.done and guard < 400:
				guard += 1
				RiverInstinct.step(rf, "adaptive", float(sa.get("stop_at", 130)))
			GameState.finish_salmon_fishing(rf)
		else:
			GameState.clear_discovery()
		return
	if d.get("kind", "") == "small_pounce":
		# 田鼠與地松鼠的小撲（Phase 2g 第 2 步）：未滿 2 歲、體力夠才撲（練習），成年後不理
		var spa: Dictionary = GameData.balance.get("small_pounce", {}).get("auto", {})
		GameState.resolve_small_pounce(GameState.wolf.age_years < float(spa.get("max_age", 2.0)) and GameState.wolf.stamina >= float(spa.get("min_stamina", 30)))
		return
	if d.get("kind", "") == "lynx":
		# 謹慎型悄悄叼走（Phase 2g 第 3 步），其他正面搶
		if d.get("has_kill", false) and style == "cautious":
			GameState.lynx_sneak()
		elif d.get("has_kill", false):
			play_combat(GameState.start_lynx_combat())
		else:
			GameState.leave_lynx()
		return
	if d.get("kind", "") == "cougar_ambush":
		play_combat(GameState.start_cougar_ambush_combat())
		return
	if d.get("kind", "") == "cougar_cache":
		if GameState.wolf.hunger < 70 and style != "cautious":
			GameState.eat_cougar_cache()
			_feed_loop()
		else:
			GameState.clear_discovery()
		return
	if d.get("kind", "") == "challenger":
		if style == "cautious":
			GameState.challenger_yield()
		else:
			play_combat(GameState.start_challenger_combat("territory" if d.get("territory", false) else "meet"))
		return
	if d.get("kind", "") == "tundra_den_bear":
		if style == "assault" and GameState.tundra_relation_key() in ["familiar", "friendly"]:
			if GameState.den_bear_threaten()["result"] == "fight":
				play_combat(GameState.start_den_combat())
		else:
			GameState.den_bear_watch()
		return
	if d.get("kind", "") == "tundra_den":
		GameState.clear_discovery()
		return
	if d.get("kind", "") == "tundra_hunt":
		# 苔原狼在狩獵（1.8 第 9 步）：謹慎型觀望，其他加入
		if style == "cautious" or GameState.too_tired_to_hunt():
			GameState.watch_tundra_hunt()
			_feed_loop()
		else:
			var h := GameState.join_tundra_hunt()
			_play_hunt(h)
		return
	if d.get("kind", "") != "clue":
		GameState.clear_discovery()
		return
	match d.get("source_kind", ""):
		"threat":
			if str(d.get("source", "")) == "stranger_wolf" and GameState.stranger_can_interact():
				GameState.clear_discovery()
				_meet_stranger()
				return
			# 強攻型看到陌生灰狼會停下來觀察（之後才能直接互動）
			if str(d.get("source", "")) == "stranger_wolf" and style == "assault" and d.get("clue", "") == "sight":
				var e := GameState.prepare_threat_sighting("stranger_wolf", str(d.get("location", "")))
				GameState.clear_discovery()
				GameState.action_observe_distant(e)
				return
			if style == "assault":
				GameState.clear_discovery()
			else:
				GameState.action_avoid()
			return
		"gather":
			GameState.action_gather_discovered()
			return
	var animal: String = str(d.get("source", ""))
	var big: bool = str(GameData.animals.get(animal, {}).get("size", "small")) != "small"
	if prey == "small_only" and big:
		GameState.clear_discovery()
		return
	if prey == "deer_focus" and not big and GameState.wolf.hunger > 40:
		GameState.clear_discovery()
		return
	# 牧場的成牛（Phase 4a 第 5 步）：難、會受傷、沒獵到也讓牧場更警戒；快餓死才打（ranch.json auto.skip：動物.階段 → 飽食度低於多少才打）
	var skip_below = _ranch_auto().get("skip", {}).get(animal + "." + str(d.get("life_stage", "adult")))
	if skip_below != null and GameState.wolf.hunger >= float(skip_below):
		GameState.clear_discovery()
		return
	# 太累不能開始狩獵（1.7 QA-55）；還飽的時候不出獵（Phase 2b 第 1 步）
	if GameState.too_tired_to_hunt() or GameState.wolf.hunger >= 90.0:
		GameState.clear_discovery()
		return
	var hunt: HuntSystem = null
	if d.get("clue", "") == "sight":
		hunt = GameState.action_hunt_sighted()
	elif d.get("fresh", false) or not d.get("fresh_known", true):
		var res: Dictionary = GameState.action_track()
		if not res.get("success", false) or not res.has("hunt"):
			return
		hunt = res["hunt"]
	else:
		GameState.clear_discovery()
		return
	_play_hunt(hunt)

func _routine_notable(d: Dictionary) -> bool:
	var kind: String = str(d.get("kind", ""))
	# 新發現的地點照常記下、剩肉照常啃、受傷的獵物照常獵；其他狼、殘骸、危險的線索交給玩家
	if kind == "remains":
		var res: Dictionary = GameState.eat_remains()
		if not (res["encounter"] as Dictionary).is_empty():
			_encounter = res["encounter"]
		return false
	# 其他狼的氣味標記、陳舊的危險痕跡照常略過（記在摘要裡太細）；新鮮的危險、殘骸、苔原狼交給玩家
	if kind in ["carcass", "tundra_wolves", "tundra_mob", "tundra_hunt", "tundra_den", "tundra_den_bear", "overmarked", "challenger", "cougar_ambush", "cougar_cache", "pack_remains"]:
		return true
	return kind == "clue" and d.get("source_kind", "") == "threat" and (d.get("fresh", false) or d.get("clue", "") == "sight")

# 戰術狩獵值不值得追（2026-10-22 使用者選 B：自動玩家比真人笨，會一直追幾乎追不到的獵物，模擬高估難度；照常過日子也用這個）：
# 看出健康又不太餓（同 Phase 2b）；健康的站定大型獵物、成羚群（game.judge.skip_healthy）除非快餓死（desperate_hunger）都不追；
# 虛弱以外的成羚（skip_unless_weak）也一樣；離避難處近的（skip_near_refuge：大角羊離峭壁近）不太餓時不追。
func _tactical_not_worth(hunt: HuntSystem, th: TacticalHunt) -> bool:
	var jc: Dictionary = th.t.get("game", {}).get("judge", {})
	var hunger: float = GameState.wolf.hunger
	var species: String = str(th.herd[th.target].get("species", ""))
	var desperate: bool = hunger < float(jc.get("desperate_hunger", 20.0))
	if th.condition_known and th.condition == "healthy" and hunger >= JUDGE_HUNGER:
		return true
	if desperate:
		return false
	if th.condition_known and th.condition == "healthy" and (jc.get("skip_healthy", []) as Array).has(species):
		return true
	if (jc.get("skip_unless_weak", []) as Array).has(species) and not (th.condition_known and th.condition == "weak"):
		return true
	if hunt.refuge_near and (jc.get("skip_near_refuge", []) as Array).has(species) and hunger >= JUDGE_HUNGER:
		return true
	return false

func _play_hunt(hunt: HuntSystem) -> void:
	# 白尾鹿用戰術地圖（Phase 2c 第 3 步）：交給本能打；會判斷的狼先觀察，看出是健康的成鹿又還不太餓就放棄（同 Phase 2b）
	if tactical and GameState.tactical_eligible(hunt) and (tactical_only.is_empty() or tactical_only.has(hunt.animal_id)):
		var th := GameState.start_tactical(hunt)
		# 同選單式：只對中大型獵物（2026-10-22：兔子進戰術地圖後，健康的兔子也被放棄，一生模擬的挨餓大增）
		# 幼體不判斷（Phase 2i 第 7 步：單獨出場的牛犢、小叉角羚、小河狸不算 is_fawn，原本健康的就被放棄，一生模擬裡牛犢 0%）
		if judge and not th.is_fawn(th.target) and hunt.life_stage != "juvenile" and str(GameData.animals.get(hunt.animal_id, {}).get("size", "small")) != "small":
			th.observe()
			TacticalInstinct.pick_target(th)
			if _tactical_not_worth(hunt, th):
				th.give_up()
		if not th.done:
			TacticalInstinct.play(th)
		GameState.finish_tactical_hunt(hunt, th)
		if not done():
			_feed_loop()
		return
	var guard := 0
	while hunt.stage != HuntSystem.Stage.DONE and not done() and guard < 25:
		guard += 1
		var opt := _pick_option(hunt)
		if opt.is_empty():
			hunt.give_up()
			break
		var sr: Dictionary = hunt.choose(str(opt["id"]))
		GameState.spend_hunt_turns(int(sr.get("turns", 0)), hunt)
	if done():
		return
	GameState.finish_hunt(hunt)
	_feed_loop()

func _feed_loop() -> void:
	while GameState.is_feeding() and not done():
		# 吃到快撐滿（再吃一段會浪費一半以上）就先離開，剩下的留成殘骸，在旁邊休息，餓了再回來吃（Phase 2b 第 1 步）
		var seg_value: float = float(GameState.current_feeding.get("segment_value", 0.0))
		if GameState.wolf.hunger + seg_value * 0.5 > float(GameData.balance.get("hunger_max", 150)):
			# 離開前有剩就叼去藏（Phase 2e）：藏滿為止，滿了而且有過期的就換掉
			while cache and GameState.can_cache() and not done():
				GameState.action_cache_segment()
			GameState.leave_feeding()
			return
		var fr: Dictionary = GameState.feed_once()
		var ev: String = str(fr.get("event", ""))
		# 照常過日子：搶食要不要守、怎麼守是玩家的決定，停下交給玩家（試玩回報 23）
		if ev != "" and routine:
			stop_reason = "scavenger"
			stop_scavenger = ev
			_finished = true
			return
		if ev != "":
			_scavenger(ev)

func _scavenger(ev: String) -> void:
	if ev == "ranch_patrol":
		GameState.start_ranch_encounter("eating", str(GameState.current_feeding.get("terrain", "")))
		GameState.ranch_auto_play()
		return
	if ev in ["cougar", "black_bear", "coyote"]:
		play_combat(GameState.start_combat(ev, "adult", "carcass"))
		return
	if ev == "challenger":
		if style == "cautious":
			GameState.challenger_yield()
		else:
			play_combat(GameState.start_challenger_combat("carcass"))
		return
	if ev == "bear" and not GameState.is_identified("grizzly_bear"):
		GameState.resolve_scavenger(ev, "abandon" if style == "cautious" else "grab")
	elif ev == "bear" and style != "assault":
		# 認得的灰熊（1.8 第 7 步）：健康時咬一塊就跑，成功率夠高可以再試；謹慎的直接放棄
		while style != "cautious" and GameState.is_feeding() and GameState.wolf.alive and GameState.wolf.injury == Wolf.Injury.NONE \
				and GameState.bear_steal_chance("bite") >= 0.4:
			GameState.resolve_bear_steal("bite")
		if GameState.is_feeding():
			GameState.resolve_scavenger(ev, "abandon")
	elif ev == "wolverine":
		play_combat(GameState.start_wolverine_combat(true))
	elif ev == "tundra_wolves":
		play_combat(GameState.start_tundra_combat("carcass"))
	elif ev == "tundra_wait":
		GameState.tundra_wait_choice(style != "assault")
	elif ev == "she_wait":
		GameState.she_wait_choice(style != "assault" or GameState.wolf.hunger > 80.0)
	else:
		play_combat(GameState.start_combat("grizzly_bear" if ev == "bear" else "red_fox", "adult", "carcass"))

# 選平安率／成功率最高的選項。
func _pick_safest(opts: Array, key: String, apply: Callable) -> void:
	var best: Dictionary = {}
	for o in opts:
		if best.is_empty() or float(o[key]) > float(best[key]):
			best = o
	if not best.is_empty():
		apply.call(str(best["id"]))

# 逃離大火或風雪後不在巢穴：一步一步走回去（巢穴正在燒就先不回去）。回傳有沒有移動。
# 這一區有藏肉、沒有殘骸、肚子空出來了：挖一段吃（過了新鮮期的那段很餓才吃）
func _eat_cache_here() -> bool:
	if not GameState.can_eat_cache() or GameState.wolf.hunger >= 80.0:
		return false
	var nxt: Dictionary = GameState.next_cache_piece()
	if GameState.piece_state(nxt) == "stale" and GameState.wolf.hunger >= 40.0:
		return false
	GameState.action_eat_cache()
	return true

# 餓了：往最近一處（照日期算）還沒壞光的藏肉走一步（同一張地圖）；被挖走的要走到那裡才知道
func _go_cache() -> bool:
	for region_id in GameState.caches.keys():
		if region_id == GameState.current_region or GameData.map_of(region_id) != GameState.current_map():
			continue
		var pieces: Array = GameState.caches[region_id].get("pieces", [])
		if not pieces.any(func(pc): return GameState.piece_state(pc, region_id) != "rotten"):
			continue
		var step := GameState.next_step_toward(region_id)
		if step != "":
			GameState.action_move(step)
			return true
	return false

func _go_home() -> bool:
	var home: String = _home_region()
	if GameState.current_region == home or GameState.burn_state(home) == "burning":
		return false
	# 照常過日子是在附近過日子：巢穴在別的地圖時不一路走回去（試玩回報 21；養傷例外，那個選項就是回巢休息）
	if routine and routine_style != "heal" and GameData.map_of(home) != GameState.current_map():
		return false
	var step := GameState.next_step_toward(home)
	if step == "":
		return false
	GameState.action_move(step)
	return true

# --- 牧場（Phase 4a 第 5 步，SPEC「照常過日子與自動玩家」；數值在 ranch.json auto）---
func _ranch_auto() -> Dictionary:
	return GameData.ranch_def.get("auto", {})

func _ranch_pol() -> Dictionary:
	return _ranch_auto().get("policies", {}).get(ranch_policy, {})

# 從 start 走到各區域要幾步（同地圖相鄰、跨地圖連接都算一步）
func _dist_from(start: String) -> Dictionary:
	var dist: Dictionary = {start: 0}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var next: Array = []
		for r in frontier:
			var nb: Array = EncounterSystem.region_data(str(r)).get("adjacent", []).duplicate()
			for l in GameData.links_from(str(r)):
				nb.append(l["to"])
			for n in nb:
				if not dist.has(n):
					dist[n] = int(dist[r]) + 1
					next.append(n)
		frontier = next
	return dist

# 離牧場邊緣幾步（走不到 99）
func _ranch_dist(region_id: String) -> int:
	return int(_dist_from(str(GameData.ranch_def.get("link_region", "ranch_edge"))).get(region_id, 99))

func _in_ranch_area(region_id: String) -> bool:
	return GameData.map_of(region_id) == "ranch" or GameState.ranch_linked_regions().has(region_id)

func _ranch_leave_at() -> float:
	return float(_ranch_pol().get("leave_at", 40))

# 離目前位置最近、符合 ok 的區域（沒有就空字串）
func _nearest(ok: Callable) -> String:
	var dist := _dist_from(GameState.current_region)
	var best := ""
	for r in dist.keys():
		if ok.call(str(r)) and (best == "" or int(dist[r]) < int(dist[best])):
			best = str(r)
	return best

# 回去的地方：巢穴；巢穴在牧場一帶、注意又到了該離開的程度，先待在同一張地圖最近的另一區（不搬巢穴）
func _home_region() -> String:
	var den: String = GameState.den_region
	if GameState.ranch_state() != "open" or not _in_ranch_area(den) or GameState.ranch_attention() < _ranch_leave_at():
		return den
	var away := _nearest(func(r): return not _in_ranch_area(r) and GameData.map_of(r) == GameData.map_of(den))
	return away if away != "" else den

# 要不要去牧場（放牧地）：照策略看飽食度與注意；受傷、太累、這裡有殘骸或藏肉、離太遠都不去
func _want_ranch(att: float) -> bool:
	if routine or ranch_policy == "never":
		return false
	var pol := _ranch_pol()
	if att >= float(pol.get("attention_below", 40)) or GameState.wolf.hunger >= float(pol.get("hunger_below", 60)):
		return false
	if GameState.wolf.injury != Wolf.Injury.NONE or GameState.wolf.health < GameState.wolf.health_max * float(_ranch_auto().get("min_health", 0.5)):
		return false
	if GameState.too_tired_to_hunt() or GameState.carcass_index_here() >= 0 or GameState.can_eat_cache():
		return false
	return _ranch_dist(GameState.current_region) <= int(_ranch_auto().get("max_steps", 3))

# 搬到哪裡：牧場一帶以外、能築巢、最近的區域
func _relocate_target() -> String:
	return _nearest(func(r: String) -> bool:
		return bool(EncounterSystem.region_data(r).get("can_den", false)) and not _in_ranch_area(r) and GameState.burn_state(r) != "burning")

# 每個行動前：搬巢穴、離開牧場一帶、去牧場。回傳這一步有沒有行動
func _ranch_step() -> bool:
	_ranch_hunting = false
	if GameState.ranch_state() != "open":
		return false
	var ac := _ranch_auto()
	var att: float = GameState.ranch_attention()
	# 注意到 move_at、巢穴就在牧場一帶：搬走（照常過日子不搬，留給玩家）；巢穴不在那一帶的照 leave_at 離開就好
	if _relocate_to == "" and not routine and att >= float(ac.get("move_at", 70)) and _in_ranch_area(GameState.den_region):
		_relocate_to = _relocate_target()
	if _relocate_to != "":
		if GameState.current_region == _relocate_to:
			_relocate_to = ""
			if GameState.can_make_den_here():
				GameState.action_make_den()
				ranch_moves += 1
				return true
			return false
		var st := GameState.next_step_toward(_relocate_to)
		if st != "":
			GameState.action_move(st)
			return true
		_relocate_to = ""
	var here: String = GameState.current_region
	# 在牧場一帶、注意到了該離開的程度（不去牧場的狼在牧場裡就走）：往回去的地方走
	if _in_ranch_area(here) and (att >= _ranch_leave_at() or (ranch_policy == "never" and GameData.map_of(here) == "ranch")):
		var target: String = _home_region()
		if _in_ranch_area(target):
			target = _nearest(func(r): return not _in_ranch_area(r))
		var st := GameState.next_step_toward(target) if target != "" else ""
		if st != "":
			GameState.action_move(st)
			return true
	if _want_ranch(att):
		if here == "ranch_pasture":
			_ranch_hunting = true
			return false
		var st := GameState.next_step_toward("ranch_pasture")
		if st != "":
			GameState.action_move(st)
			return true
	return false

# 戰鬥：強攻型會打（灰熊搶食時守住），打到瀕危就撤退；其他打法對灰熊退讓（叼走一塊或放棄），
# 對狐狸先威嚇再咬。
func play_combat(c: Combat) -> void:
	var guard := 0
	while c.phase != Combat.Phase.DONE and not done() and guard < 30:
		guard += 1
		c.choose(_combat_choice(c))
	GameState.finish_combat(c)

# 遇上陌生灰狼：強攻型先跟蹤看清楚，牠不比自己強就挑戰；其他打法避開。
func _meet_stranger() -> void:
	if style != "assault":
		GameState.stranger_avoid()
		return
	var res := GameState.stranger_follow()
	if not res.get("success", false):
		play_combat(GameState.start_stranger_combat("meet"))
	elif str(res["assessment"]["compare"]) in ["even", "weaker", "much_weaker"]:
		play_combat(GameState.start_stranger_combat("meet"))
	else:
		GameState.stranger_avoid()

# 遇上苔原狼：強攻型先跟隨看清楚，牠們不比自己強就挑戰；其他打法避開（不起衝突，關係慢慢變好）。
func _meet_tundra(charge: bool = false) -> void:
	if charge:
		play_combat(GameState.start_tundra_combat("meet", true))
		return
	if style != "assault" and GameState.tundra_relation_key() == "friendly":
		if GameState.tundra_approach().get("lead", false) and GameState.wolf.hunger < 100.0:
			_play_hunt(GameState.action_hunt_sighted())
		else:
			GameState.clear_discovery()
		return
	if style != "assault":
		GameState.tundra_avoid()
		return
	var res := GameState.tundra_follow()
	if not res.get("success", false) or str(res["assessment"]["compare"]) in ["even", "weaker", "much_weaker"]:
		play_combat(GameState.start_tundra_combat("meet"))
	else:
		GameState.tundra_avoid()

func _combat_choice(c: Combat) -> String:
	var ids: Array = c.options().map(func(o): return o["id"])
	# 牠示弱了：強攻型血量還夠就追擊，否則放牠走
	if ids.has("let_go"):
		return "pursue" if style == "assault" and GameState.wolf.health > GameState.wolf.health_max * 0.6 else "let_go"
	# 對陌生灰狼瀕危時示弱（一定能活下來）
	if c.npc != null and c.phase == Combat.Phase.EXCHANGE and FightRules.in_danger(GameState.wolf) and ids.has("submit"):
		return "submit"
	var fights: bool = style == "assault" or c.animal_id == "red_fox"
	if c.phase == Combat.Phase.STANDOFF:
		if not fights:
			for y in ["yield", "guard_together", "share", "abandon" if style == "cautious" else "grab", "grab", "abandon"]:
				if ids.has(y):
					return y
		return "threaten" if c.animal_id == "red_fox" else "attack"
	if FightRules.in_danger(GameState.wolf) or (not fights and ids.has("retreat")):
		return "retreat"
	return "bite"

# 依風格挑選項（見 PREFER）；回傳空字典代表放棄。
func _pick_option(hunt: HuntSystem) -> Dictionary:
	# 搏鬥中瀕危：除了強攻型，都放手（瀕危後繼續才會被反殺，玩家隨時可以放棄）
	if hunt.stage == HuntSystem.Stage.FIGHT and style != "assault" and FightRules.in_danger(GameState.wolf):
		return {}
	var opts: Array = hunt.options()
	var prefer: Array = PREFER.get(style, []).duplicate()
	# 閃避不連續用（否則會一直閃避拖下去）
	if not hunt.decisions.is_empty() and hunt.decisions[-1] == "fight.dodge":
		prefer.erase("dodge")
	var avoid: Array = AVOID.get(style, [])
	var best: Dictionary = {}
	for id in prefer:
		for o in opts:
			if o["id"] == id:
				best = o
				break
		if not best.is_empty():
			break
	if best.is_empty():
		best = _best(opts.filter(func(o): return not avoid.has(o["id"])))
	if best.is_empty():
		return opts[0] if not opts.is_empty() else {}
	# 會判斷的狼（Phase 2b 第 3 步）：追擊前先試探；看得出是健康的中大型獵物、又還不太餓（飽食度 ≥ JUDGE_HUNGER），就放棄
	if judge and hunt.stage == HuntSystem.Stage.CHASE and hunt.condition != "":
		if hunt.condition_known and hunt.condition == "healthy" and GameState.wolf.hunger >= JUDGE_HUNGER:
			return {}
		for o in opts:
			if o["id"] == "probe":
				return o
	# 謹慎：追擊勝算太低或體力見底就放棄。
	if style == "cautious" and hunt.stage == HuntSystem.Stage.CHASE and best.has("chance") \
			and (float(best["chance"]) < 0.3 or GameState.wolf.stamina < 25.0):
		return {}
	return best

# 有成功率的選項取最高；都沒有成功率（例如「不觀察」）就取第一個。
func _best(opts: Array) -> Dictionary:
	var best: Dictionary = {}
	for o in opts:
		if not o.has("chance"):
			if best.is_empty():
				best = o
			continue
		if best.is_empty() or not best.has("chance") or float(o["chance"]) > float(best["chance"]):
			best = o
	return best

# 黃昏嚎叫一次（Phase 3 第 2 步）：還沒有伴侶的成年狼，依 mate_search；母狼在附近時都會嚎叫。
func _maybe_howl() -> bool:
	if GameTime.current_period() != "dusk" or _howled_day == GameState._today() or not GameState.can_howl() or GameState.has_mate():
		return false
	var season: String = GameTime.current_season()
	var near: bool = GameState.she_wolf() != null
	var want: bool = near
	if not want and season in ["autumn", "winter"]:
		want = mate_search == "always" or (mate_search == "sometimes" and GameState._today() % 3 == 0)
	if not want:
		return false
	_howled_day = GameState._today()
	if GameState.action_howl().get("came", false):
		_meet_she_wolf(GameState.current_discovery)
	return true

# 遇上離群母狼：牠在吃東西時，關係夠就一起吃、強攻型餓了就搶；否則靠近，偶爾跟著看看。
func _meet_she_wolf(d: Dictionary) -> void:
	if bool(d.get("eating", false)):
		if style == "assault" and GameState.wolf.hunger < 50.0:
			GameState.she_steal()
			return
		if GameState.she_relation_key() != "wary":
			GameState.she_eat_together()
			return
	if style == "cautious" and GameState.she_relation_key() == "wary" and RNGService.chance(0.5):
		GameState.she_follow()
		GameState.clear_discovery()
		return
	GameState.she_approach()

