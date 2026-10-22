extends SceneTree
# Phase 2b 第 1 步「吃撐與殘骸」的回歸測試：
#   吃撐：喘的上限 × 0.6、不能短衝、移動與探索的體力 × 1.5；在巢穴休息時消化較快但不會低於門檻；不吃撐時一切照舊
#   殘骸：你在同一區時每個時段少 0.1 段、不在時 0.2 段，每天最多 1 段；過了天數會腐壞；剩餘量看得到
# 用法：bash tools/run_sim.sh gorged_rules
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var g: Dictionary = root.get_node("GameData").balance["gorged"]
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	var w = gs.wolf
	# 1. 喘的上限
	w.hunger = 80.0; w.in_burst = false; w.begin_burst(); var normal: float = w.breath_max; w.in_burst = false
	w.hunger = 140.0; w.begin_burst(); var gorged: float = w.breath_max; w.in_burst = false
	_check(w.is_overfed(), "飽食度 140 是吃撐")
	# 吃撐時速度也 ×0.9（原本的「吃太飽」），喘的上限會再低一點
	_check(gorged <= normal * float(g["breath_mult"]) + 0.01, "吃撐時喘的上限至少 × %.1f（%.1f → %.1f）" % [g["breath_mult"], normal, gorged])
	# 2. 短衝
	var hunt = _chase_hunt(gs)
	w.hunger = 80.0
	_check(hunt.options().any(func(o): return o["id"] == "sprint"), "不吃撐時可以短衝")
	w.hunger = 140.0
	_check(not hunt.options().any(func(o): return o["id"] == "sprint"), "吃撐時不能短衝")
	w.in_burst = false
	# 3. 移動、探索的體力
	for action in ["move_region", "explore", "gather"]:
		w.stamina = 80.0; w.hunger = 80.0; gs._spend_action_stamina(action); var c0: float = 80.0 - w.stamina
		w.stamina = 80.0; w.hunger = 140.0; gs._spend_action_stamina(action); var c1: float = 80.0 - w.stamina
		var expect: float = c0 * float(g["move_stamina_mult"]) if action != "gather" else c0
		_check(absf(c1 - expect) < 0.01, "%s 的體力：不吃撐 %.1f、吃撐 %.1f（預期 %.1f）" % [action, c0, c1, expect])
	# 4. 在巢穴休息時消化較快，不低於門檻
	gs.current_region = gs.den_region
	w.hunger = 150.0
	gs._resting = true; gs._on_period_changed(0); gs._resting = false
	var rested: float = 150.0 - w.hunger
	w.hunger = 150.0
	gs._on_period_changed(0)
	var awake: float = 150.0 - w.hunger
	_check(rested > awake, "吃撐時休息消化較快（休息少 %.1f、沒休息少 %.1f）" % [rested, awake])
	w.hunger = 121.0
	gs._resting = true; gs._on_period_changed(0); gs._resting = false
	_check(w.hunger >= 121.0 - float(root.get_node("GameData").balance["hunger_decay_per_period"]) - 0.01 - gs.cold_cost()["hunger"], "消化加快不會多扣到門檻以下（%.1f）" % w.hunger)
	# 5. 殘骸
	gs.carcasses = []
	var today: int = int(gs.life_log.get("days_lived", 1))
	gs.carcasses.append({"region_id": gs.current_region, "terrain": "", "animal_id": "white_tailed_deer", "life_stage": "adult", "segments_left": 3, "segment_value": 25.0, "day": today})
	gs.carcasses.append({"region_id": "forest_west", "terrain": "", "animal_id": "white_tailed_deer", "life_stage": "adult", "segments_left": 3, "segment_value": 25.0, "day": today})
	var here: Dictionary = gs.carcasses[0]; var away: Dictionary = gs.carcasses[1]
	for i in 5:
		gs._decay_carcasses()
	# 2026-10-22 肉量 B：按肉量算（每段 25 的殘骸）：在場每個時段 5 → 一天 25 = 1 段；不在 15 → 一天 75，上限 50 = 2 段
	_check(absf(float(here.get("eaten", 0.0)) + (3 - int(here["segments_left"])) - 1.0) < 0.01, "在場：一天（5 個時段）少約 1 段（飽食度 25）")
	_check(int(away["segments_left"]) == 1 and float(away.get("eaten", 0.0)) < 0.01, "不在場：一天少 2 段（飽食度上限 50，剩 %d 段）" % int(away["segments_left"]))
	for i in 3:
		gs._decay_carcasses()
	_check(int(away["segments_left"]) == 1, "每天最多少飽食度 50（同一天再過幾個時段不再減少）")
	_check(absf(gs.carcass_loss_per_day_absent(away) - 2.0) < 0.01, "畫面寫的「不在時一天大約少」= 2 段")
	# 大型獵物每段比較多：一樣的肉量換成段數比較少（駝鹿每段約 31）
	var big := {"region_id": "forest_west", "segments_left": 7, "segment_value": 220.0 / 7.0}
	_check(gs.carcass_loss_per_day_absent(big) < 2.0, "駝鹿的殘骸一天少的段數比白尾鹿少（%.2f 段）" % gs.carcass_loss_per_day_absent(big))
	gs.life_log["days_lived"] = today + 10
	gs._decay_carcasses()
	_check(gs.carcasses.is_empty(), "放太久就腐壞")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

# 做一場停在追擊階段的白尾鹿狩獵
func _chase_hunt(gs):
	var HS = load("res://scripts/core/HuntSystem.gd")
	var h = HS.new(gs.wolf, "white_tailed_deer", "adult", 0.0, 0, 0, "forest_edge")
	h.stage = HS.Stage.CHASE
	h.reaction = "flee"
	gs.wolf.begin_burst()
	return h

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
