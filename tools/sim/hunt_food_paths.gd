extends SceneTree
# 所有狩獵成功都會增加飽食度（2026-10-25 試玩回報：戰術地圖獵到河狸飽食度沒增加，使用者要求全部確認一次）：
#   1. 戰術地圖：每種獵物 × 每個生命階段（animals.json 有的）獵到 → 一次吃完的飽食度增加；分段吃的開始進食，吃一段飽食度增加
#   2. 選單式（模擬對照、小撲以外的入口都已改成戰術地圖，程式保留）：同上
#   3. 受傷的個體、躲在草裡的幼鹿、獵物靠近、和苔原狼一起獵到
#   4. 田鼠、地松鼠的小撲撲到
#   5. 猞猁的雪兔：悄悄叼走成功、正面打贏
#   6. 鮭魚：捕到的有吃下去
# 用法：bash tools/run_sim.sh hunt_food_paths
var f := 0
var gs
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

# 獵到之後吃得到東西：分段吃的開始進食、吃一段有加；一次吃完的至少加了 hunger_value − 9（結算經過 1～3 個回合，最多扣約 8）
func _ate(h0: float, h) -> String:
	if gs.is_feeding():
		var a: float = gs.wolf.hunger
		gs.feed_once()
		var got: float = gs.wolf.hunger - a
		gs.current_feeding = {}
		return "" if got > 0.0 else "進食一段沒加（%.1f）" % got
	var want: float = float(root.get_node("GameData").animals[h.animal_id][h.life_stage]["hunger_value"])
	return "" if gs.wolf.hunger >= h0 + want - 9.0 else "沒加（%.1f → %.1f，應該約 +%d）" % [h0, gs.wolf.hunger, roundi(want)]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	var gd = root.get_node("GameData")
	var gt = root.get_node("GameTime")
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	gs.pending_events.clear()
	gt.season_index = gt.SEASONS.find("summer")
	var tun: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical_hunt.json"))
	var animals: Array = tun["game"]["animals"]
	# 1、2
	for mode in ["tactical", "menu"]:
		var bad: Array = []
		var n := 0
		for a in animals:
			for st in ["juvenile", "adult", "buck"]:
				if not (gd.animals[a] as Dictionary).has(st):
					continue
				n += 1
				gs.wolf.hunger = 20.0
				gs.current_feeding = {}
				var h = gs.start_hunt(a, st, -1, false, "")
				if mode == "tactical":
					var th = gs.start_tactical(h)
					th._finish("caught", "test")
					gs.finish_tactical_hunt(h, th)
				else:
					h._kill("hunt.success")
					gs.finish_hunt(h)
				var why: String = _ate(20.0, h)
				if why != "":
					bad.append("%s.%s %s" % [a, st, why])
		_check(bad.is_empty(), "%s：%d 種獵物與階段獵到都吃得到%s" % ["戰術地圖" if mode == "tactical" else "選單式", n, "" if bad.is_empty() else "（沒有：" + "、".join(bad) + "）"])
	# 3. 其他入口
	var bad3: Array = []
	var cases := [["受傷的白尾鹿", "white_tailed_deer", "adult", "injured"], ["受傷的河狸", "beaver", "adult", "injured"], ["躲在草裡的幼鹿", "white_tailed_deer", "juvenile", "hidden"],
		["獵物靠近的雪兔", "snowshoe_hare", "adult", "nearby"], ["和苔原狼一起獵到馴鹿", "caribou", "adult", "tundra"]]
	for c in cases:
		gs.wolf.hunger = 20.0
		gs.current_feeding = {}
		var h
		if c[3] == "nearby":
			h = gs.hunt_nearby_prey({"animal_id": c[1], "life_stage": c[2], "terrain": ""})
		else:
			h = gs.start_hunt(c[1], c[2], -1, false, "", c[3] == "injured", c[3] == "hidden")
		if c[3] == "tundra":
			h.apply_tundra_help(2, true)
		var th = gs.start_tactical(h)
		th._finish("caught", "test")
		gs.finish_tactical_hunt(h, th)
		var why: String = _ate(20.0, h)
		if why != "":
			bad3.append(c[0] + " " + why)
	_check(bad3.is_empty(), "受傷的個體、躲在草裡的幼鹿、獵物靠近、和苔原狼一起獵到都吃得到%s" % ("" if bad3.is_empty() else "（沒有：" + "、".join(bad3) + "）"))
	# 4. 小撲
	var sp_ok := false
	for i in 60:
		gs.debug_small_pounce()
		gs.wolf.hunger = 20.0
		var r: Dictionary = gs.resolve_small_pounce(true)
		if bool(r.get("caught", false)):
			sp_ok = gs.wolf.hunger > 20.0 and float(r.get("gain", 0.0)) > 0.0
			break
	_check(sp_ok, "田鼠、地松鼠的小撲撲到有加飽食度")
	# 5. 猞猁的雪兔
	var sneak_ok := false
	for i in 80:
		gs.current_discovery = {"kind": "lynx", "location": "dense_forest", "has_kill": true, "known": true}
		gs.wolf.hunger = 20.0
		var r2: Dictionary = gs.lynx_sneak()
		if bool(r2.get("success", false)):
			sneak_ok = gs.wolf.hunger > 20.0
			break
	_check(sneak_ok, "猞猁的雪兔：悄悄叼走成功有加飽食度")
	var fight_ok := true
	for outcome in ["drove_off", "killed"]:
		gs.current_discovery = {"kind": "lynx", "location": "dense_forest", "has_kill": true, "known": true}
		gs.wolf.hunger = 20.0
		gs.wolf.health = gs.wolf.health_max
		var c = gs.start_lynx_combat()
		c.outcome = outcome
		gs.finish_combat(c)
		if gs.wolf.hunger <= 20.0:
			fight_ok = false
			print("    打贏（%s）沒加：%.1f" % [outcome, gs.wolf.hunger])
	_check(fight_ok, "猞猁的雪兔：正面打贏（趕走、咬死）有加飽食度")
	# 6. 鮭魚
	gs.wolf.hunger = 20.0
	var RF = load("res://scripts/core/RiverFishing.gd")
	var rf = RF.new()
	rf.setup({"stage": "peak", "seed": 7, "hunger": 20.0, "hunger_max": 150.0, "overfed_at": 120.0, "cfg": gs._salmon_cfg().get("river", {}), "clue": ""})
	rf.eaten = 15.0
	rf.done = true
	gs.finish_salmon_fishing(rf)
	_check(gs.wolf.hunger > 20.0, "鮭魚：捕到吃下的有加飽食度（%.1f）" % gs.wolf.hunger)
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
	return true
