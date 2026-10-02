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
const MAX_ACTIONS_PER_DAY := 80

var prey: String
var style: String
var stop_before_adult: bool = false
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

func _play_day() -> void:
	var start_day: int = GameTime.day
	var guard := 0
	while not done() and GameTime.day == start_day and guard < MAX_ACTIONS_PER_DAY:
		guard += 1
		_handle_pending()
		if done():
			return
		if GameTime.current_period() == "predawn":
			GameState.action_sleep()
			continue
		if GameState.wolf.hunger > 110 or GameState.wolf.stamina < 35:
			GameState.action_short_rest()
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
	while not done():
		var event := GameState.pop_event()
		if event.is_empty():
			break
		match event.get("type", ""):
			"driven_off":
				GameState.apply_drive_off()
			"stranger_confront":
				if style == "assault":
					play_combat(GameState.start_stranger_combat("territory"))
				else:
					GameState.stranger_yield_territory()
			"bear_passing":
				GameState.resolve_bear_passing(event, "leave")

func _explore_once() -> void:
	var d: Dictionary = GameState.action_explore()
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
	if prey == "small_only" and animal == "white_tailed_deer":
		GameState.clear_discovery()
		return
	if prey == "deer_focus" and animal != "white_tailed_deer" and GameState.wolf.hunger > 40:
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
	while GameState.is_feeding() and not done():
		var fr: Dictionary = GameState.feed_once()
		var ev: String = str(fr.get("event", ""))
		if ev == "bear" and not GameState.is_identified("grizzly_bear"):
			GameState.resolve_scavenger(ev, "abandon" if style == "cautious" else "grab")
		elif ev != "":
			play_combat(GameState.start_combat("grizzly_bear" if ev == "bear" else "red_fox", "adult", "carcass"))

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
			for y in ["yield", "abandon" if style == "cautious" else "grab", "grab", "abandon"]:
				if ids.has(y):
					return y
		return "threaten" if c.animal_id == "red_fox" else "attack"
	if FightRules.in_danger(GameState.wolf) or (not fights and ids.has("retreat")):
		return "retreat"
	return "bite"

# 依風格挑選項（見 PREFER）；回傳空字典代表放棄。
func _pick_option(hunt: HuntSystem) -> Dictionary:
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
