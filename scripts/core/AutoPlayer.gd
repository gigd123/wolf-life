class_name AutoPlayer
extends RefCounted

# 除錯「模擬到死亡」：依選定的獵物偏好與風格，自動玩完一隻狼的一生（規則同 tools/sim 的機器人）。
# 由畫面層每個 frame 呼叫 step()，一次推進幾天；GameState.auto_playing 期間不產生提示卡片。
# prey："small_only" 只吃小獵物、"deer_focus" 以鹿為主（餓了才吃小獵物）。
# style："cautious" 謹慎（觀察、潛伏、追不到就放棄、避開灰熊）、"assault" 強攻（正面接近、直取咽喉、迎戰灰熊）。

const MAX_YEARS := 15.0
const MAX_ACTIONS_PER_DAY := 80

var prey: String
var style: String
var _encounter: Dictionary = {}

func _init(prey_policy: String, style_policy: String) -> void:
	prey = prey_policy
	style = style_policy

func start(den: String) -> void:
	GameState.auto_playing = true
	GameState.new_game(den)
	if not GameState.encounter_triggered.is_connected(_on_encounter):
		GameState.encounter_triggered.connect(_on_encounter)

# 活過上限年齡還沒死，就以老死結束（避免無限跑下去）。
func finish() -> void:
	if GameState.encounter_triggered.is_connected(_on_encounter):
		GameState.encounter_triggered.disconnect(_on_encounter)
	GameState.auto_playing = false

func done() -> bool:
	return GameState.wolf == null or not GameState.wolf.alive

func step(days: int) -> void:
	for i in days:
		if done():
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
		elif style == "assault":
			GameState.resolve_competitor_encounter("fight", e)
		else:
			GameState.resolve_competitor_encounter("flee" if e.get("direct", false) else "retreat", e)
	while not done():
		var event := GameState.pop_event()
		if event.is_empty():
			break
		match event.get("type", ""):
			"driven_off":
				GameState.apply_drive_off()
			"bear_passing":
				GameState.resolve_bear_passing(event, "leave")

func _explore_once() -> void:
	var d: Dictionary = GameState.action_explore()
	if d.get("kind", "") != "clue":
		GameState.clear_discovery()
		return
	match d.get("source_kind", ""):
		"threat":
			if style == "cautious":
				GameState.action_avoid()
			else:
				GameState.clear_discovery()
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
		GameState.spend_hunt_turns(int(sr.get("turns", 0)))
	if done():
		return
	GameState.finish_hunt(hunt)
	while GameState.is_feeding() and not done():
		var fr: Dictionary = GameState.feed_once()
		var ev: String = str(fr.get("event", ""))
		if ev == "bear":
			GameState.resolve_scavenger(ev, "guard" if style == "assault" else "abandon")
		elif ev != "":
			GameState.resolve_scavenger(ev, "drive")

# 依風格挑選項；回傳空字典代表放棄。
func _pick_option(hunt: HuntSystem) -> Dictionary:
	var opts: Array = hunt.options()
	var by_id: Dictionary = {}
	for o in opts:
		by_id[o["id"]] = o
	var prefer: Array = []
	var avoid: Array = []
	if style == "assault":
		prefer = ["skip_observe", "direct", "attack_standing", "bite_throat"]
	else:
		prefer = ["observe"]
		avoid = ["direct", "attack_standing", "bite_throat"]
	for id in prefer:
		if by_id.has(id):
			return by_id[id]
	var best: Dictionary = {}
	for o in opts:
		if not o.has("chance") or avoid.has(o["id"]):
			continue
		if best.is_empty() or float(o["chance"]) > float(best["chance"]):
			best = o
	if best.is_empty():
		return opts[0] if not opts.is_empty() else {}
	# 謹慎：追擊勝算太低或體力見底就放棄。
	if style == "cautious" and hunt.stage == HuntSystem.Stage.CHASE \
			and (float(best["chance"]) < 0.3 or GameState.wolf.stamina < 25.0):
		return {}
	return best
