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
var stop_before_adult: bool = false
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
		if GameTime.current_period() == "predawn":
			GameState.action_sleep()
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
		if _go_home():
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
				# 巢穴濃煙竄入時會再選一次（提案之十一）
				for attempt in 3:
					var best: Dictionary = {}
					for o in GameState.fire_escape_options():
						if best.is_empty() or float(o["safe"]) > float(best["safe"]):
							best = o
					if best.is_empty():
						break
					if str(GameState.fire_escape(str(best["id"])).get("result", "")) != "smoke":
						break
			"stranger_confront":
				if style == "assault":
					play_combat(GameState.start_stranger_combat("territory"))
				else:
					GameState.stranger_yield_territory()
			"bear_passing":
				GameState.resolve_bear_passing(event, "leave")
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
	var d: Dictionary = GameState.action_explore()
	# 照常過日子：值得注意的發現（危險的線索、其他狼、殘骸、地點、記著的那頭…）留給玩家
	if routine and _routine_notable(d):
		stop_reason = "discovery"
		_finished = true
		return
	if d.get("kind", "") == "tundra_wolves":
		_meet_tundra(bool(d.get("charge", false)))
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
	if d.get("kind", "") == "lynx":
		if d.get("has_kill", false) and style != "cautious":
			play_combat(GameState.start_lynx_combat())
		else:
			GameState.clear_discovery()
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
	if kind in ["carcass", "tundra_wolves", "tundra_mob", "tundra_hunt", "tundra_den", "tundra_den_bear", "overmarked", "challenger", "cougar_ambush", "cougar_cache"]:
		return true
	return kind == "clue" and d.get("source_kind", "") == "threat" and (d.get("fresh", false) or d.get("clue", "") == "sight")

func _play_hunt(hunt: HuntSystem) -> void:
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
func _go_home() -> bool:
	if GameState.current_region == GameState.den_region or GameState.burn_state(GameState.den_region) == "burning":
		return false
	# 照常過日子是在附近過日子：巢穴在別的地圖時不一路走回去（試玩回報 21；養傷例外，那個選項就是回巢休息）
	if routine and routine_style != "heal" and GameData.map_of(GameState.den_region) != GameState.current_map():
		return false
	var step := GameState.next_step_toward(GameState.den_region)
	if step == "":
		return false
	GameState.action_move(step)
	return true

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
