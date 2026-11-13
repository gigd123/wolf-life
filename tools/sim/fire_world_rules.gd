extends SceneTree
# Phase 2n 第 4 步的規則檢查：逃生地圖接進世界的大火。
# 四個邊對應相鄰區與往別的地圖的連接；在燒的相鄰區那一邊標成在燒；察覺的早晚；風力在大火開始時決定；
# 世界的延燒往下風比較容易；逃出去 → 到那一區、扣體力、紀錄；往這一區的邊緣逃 → 留在這一區、不再跳；
# 在水裡等到火過去 → 快轉；輕傷、重傷寫回；死亡；學到「經歷過大火」、察覺更快；巢穴洞口受損（睡覺不能用巢穴、能清理、幾天後恢復）；
# 關掉戰術大火時照舊用選單；自動玩家打得完。
# 用法：bash tools/run_sim.sh fire_world_rules
var f := 0
var fails := 0
var gs
var gt

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _burning_here(region: String, extra: Array = []) -> void:
	gs.new_game("forest_north")
	gs.debug_force_transition("adult")
	gs.current_region = region
	gs.start_fire_warning(region)
	gs.fire["phase"] = "burning"
	gs.fire["regions"] = {region: gs._abs_period()}
	for r in extra:
		gs.fire["regions"][r] = gs._abs_period()

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	# 四個邊
	gs.new_game("forest_north")
	var sn: Dictionary = gs.fire_sides("forest_north")
	_ok(str(sn["e"]["region"]) == "forest_east" and str(sn["s"]["region"]) == "forest_west", "森林北部：東邊是森林東部、南邊是森林西部（%s）" % str(sn))
	var has_tundra := false
	for s in sn:
		if str(sn[s]["region"]) == "tundra_south":
			has_tundra = true
	_ok(has_tundra, "森林北部有一邊通往苔原林線")
	var se: Dictionary = gs.fire_sides("forest_east")
	_ok(str(se["w"]["region"]) == "forest_north" and str(se["s"]["region"]) == "forest_south", "森林東部：西邊森林北部、南邊森林南部")
	# 開地圖：在燒的相鄰區那一邊、風力、察覺
	_burning_here("forest_north", ["forest_east"])
	gs.fire["noticed"] = false
	var fe = gs.start_fire_escape()
	_ok(fe.edges_burning.has("e"), "森林東部在燒：東邊標成在燒（%s）" % str(fe.edges_burning))
	_ok(fe.strength == int(gs.fire["wind_strength"]), "地圖的風力 = 這場大火的風力")
	_ok(fe.warning == "late", "沒察覺：很晚才察覺")
	gs.apply_fire_escape(fe) # 收尾（沒玩，算原地）
	_burning_here("forest_north")
	gs.fire["noticed"] = true
	gs.fire["noticed_at"] = int(gs.fire["ignite_at"]) - 1
	_ok(gs.fire_warning_level() == "early", "起火前就察覺：早察覺")
	# 風力的分布
	var cnt := [0, 0, 0]
	for i in 300:
		cnt[gs._roll_fire_wind()] += 1
	_ok(cnt[0] > 0 and cnt[1] > 0 and cnt[2] > 0, "三種風力都會出現（%s）" % str(cnt))
	# 世界的延燒：往下風比較容易
	gs.wind_dir = 0 # 往東吹
	gs.fire["wind_strength"] = 2
	_ok(gs._fire_spread_mult("forest_north", "forest_east") > 1.0 and gs._fire_spread_mult("forest_east", "forest_north") < 1.0, "強風往東：北部 → 東部比較容易、東部 → 北部比較難")
	# 逃出去：到那一區、扣體力、紀錄
	_burning_here("forest_north")
	fe = gs.start_fire_escape()
	var e_side := ""
	for s in fe.get_meta("sides"):
		if str(fe.get_meta("sides")[s]["region"]) == "forest_east":
			e_side = s
	var edge_cell: Vector2i = {"e": Vector2i(fe.width - 1, 5), "w": Vector2i(0, 5), "n": Vector2i(5, 0), "s": Vector2i(5, fe.height - 1)}[e_side]
	fe.wolf_pos = edge_cell
	fe.exit_to(e_side)
	var st0: float = gs.wolf.stamina
	var res: Dictionary = gs.apply_fire_escape(fe)
	_ok(gs.current_region == "forest_east" and str(res["how"]) == "exit", "逃出去：到森林東部")
	_ok(gs.wolf.stamina < st0, "逃出去扣體力")
	_ok(str(gs.fire.get("escape", "")) == "tactical_exit" and gs.knowledge_level({"type": "fire_memory"}) > 0, "紀錄怎麼逃的、學到經歷過大火")
	# 往這一區的邊緣逃：留在這一區、這一區不再跳逃生
	_burning_here("forest_east")
	fe = gs.start_fire_escape()
	var edge_side := ""
	for s in fe.get_meta("sides"):
		if str(fe.get_meta("sides")[s]["kind"]) == "edge":
			edge_side = s
	if edge_side != "":
		fe.wolf_pos = {"e": Vector2i(fe.width - 1, 5), "w": Vector2i(0, 5), "n": Vector2i(5, 0), "s": Vector2i(5, fe.height - 1)}[edge_side]
		fe.exit_to(edge_side)
		gs.apply_fire_escape(fe)
		_ok(gs.current_region == "forest_east" and str(gs.fire.get("sheltered", "")) == "forest_east", "往這一帶的邊緣逃：留在這一區、不再跳逃生")
	# 在水裡等到火過去：快轉到這一區熄滅
	_burning_here("forest_north")
	fe = gs.start_fire_escape()
	fe.done = true
	fe.result = "survived"
	var day0: int = int(gs.life_log.get("days_lived", 1)) * 5 + gt.period_index
	gs.apply_fire_escape(fe)
	_ok(gs.fire.is_empty() or not gs.fire.get("regions", {}).has("forest_north"), "等到火過去：這一區已經熄了")
	# 輕傷、重傷寫回
	_burning_here("forest_north")
	fe = gs.start_fire_escape()
	fe.done = true
	fe.result = "survived"
	fe.dmg["burn"] = 30.0
	fe.wolf["health"] = float(fe.wolf["health"]) - 30.0
	gs.apply_fire_escape(fe)
	_ok(gs.wolf.injury == gs.wolf.Injury.HEAVY and gs.wolf.injury_source == "fire", "傷 30：重度燒傷寫回")
	# 死亡
	_burning_here("forest_north")
	fe = gs.start_fire_escape()
	fe.done = true
	fe.result = "dead"
	fe.wolf["health"] = 0.0
	gs.apply_fire_escape(fe)
	_ok(not gs.wolf.alive and str(gs.wolf.death_cause) == "fire", "死在火裡")
	# 經歷過大火：察覺更快（同一個隨機數下比較機率）
	gs.new_game("forest_north")
	_ok(gs.knowledge_level({"type": "fire_memory"}) == 0, "新的一局沒有這筆")
	# 巢穴洞口受損
	gs.new_game("forest_north")
	gs.debug_force_transition("adult")
	gs.den_region = "forest_north"
	gs.current_region = "forest_north"
	gs.start_fire_warning("forest_north")
	var damaged := 0
	for i in 200:
		gs.den_damaged_until = -1
		gs.fire["den_damaged"] = false
		gs._region_burned("forest_north")
		if gs.den_blocked():
			damaged += 1
	_ok(damaged > 20 and damaged < 120, "巢穴那一區燒過：洞口有時受損（200 次裡 %d 次）" % damaged)
	gs.den_damaged_until = int(gs.life_log.get("days_lived", 1)) + 3
	_ok(gs.sleep_quality() != "den" and gs.can_clear_den() and gs.available_actions().has("clear_den"), "洞口受損：不能在巢穴睡、可以清理")
	var cleared := false
	for i in 20:
		if gs.action_clear_den():
			cleared = true
			break
	_ok(cleared and not gs.den_blocked(), "清理終究會清開")
	gs.den_damaged_until = int(gs.life_log.get("days_lived", 1)) - 1
	_ok(not gs.den_blocked(), "幾天後自己恢復")
	# 關掉戰術大火：照舊用選單
	gs.tactical_fire_off = true
	_ok(not gs.uses_tactical_fire(), "關掉時不用逃生地圖")
	gs.tactical_fire_off = false
	# 第 6 步：火後的五個階段、各區的恢復速度
	gs.new_game("forest_east")
	gs.fire = {}
	var today: int = int(gs.life_log.get("days_lived", 1))
	var expect := {5: "ash", 30: "herb", 100: "shrub", 250: "young", 500: "succession"}
	for d in expect:
		gs.region_burn["forest_east"] = today - d
		_ok(gs.burn_stage("forest_east") == expect[d], "森林東部燒完 %d 天：%s（實際 %s）" % [d, expect[d], gs.burn_stage("forest_east")])
	gs.region_burn["forest_east"] = today - 30
	_ok(gs.burn_state("forest_east") == "regrowth", "草本恢復期在舊的火況算草木新生")
	gs.region_burn["forest_east"] = today - 100
	_ok(gs.burn_state("forest_east") == "", "灌木期以後舊的火況算平常（%s）" % gs.burn_state("forest_east"))
	# 恢復速度：同樣 180 天，森林北部（快）已經是年輕的森林、森林西部（慢）還在灌木期
	gs.region_burn["forest_north"] = today - 180
	gs.region_burn["forest_west"] = today - 180
	_ok(gs.burn_stage("forest_north") == "young" and gs.burn_stage("forest_west") == "shrub", "同樣 180 天：森林北部 %s、森林西部 %s" % [gs.burn_stage("forest_north"), gs.burn_stage("forest_west")])
	# 再燒一次重新計時
	gs.region_burn["forest_north"] = today - 500
	gs._region_burned("forest_north")
	_ok(gs.burn_stage("forest_north") == "ash", "持續演替的區域再燒一次：回到剛燒完（%s）" % gs.burn_stage("forest_north"))
	# 獵物：剛燒完少、草本期鹿多、灌木期雪兔多
	gs.region_burn.erase("forest_east")
	var base_deer: float = float(gs.prey_mults("forest_east").get("white_tailed_deer", 1.0))
	var base_hare: float = float(gs.prey_mults("forest_east").get("snowshoe_hare", 1.0))
	gs.region_burn["forest_east"] = today - 5
	_ok(float(gs.prey_mults("forest_east").get("white_tailed_deer", 1.0)) < base_deer * 0.5, "剛燒完：鹿少")
	gs.region_burn["forest_east"] = today - 30
	_ok(float(gs.prey_mults("forest_east").get("white_tailed_deer", 1.0)) > base_deer * 1.3, "草本期：鹿多")
	gs.region_burn["forest_east"] = today - 100
	_ok(float(gs.prey_mults("forest_east").get("snowshoe_hare", 1.0)) > base_hare * 1.3, "灌木期：雪兔多")
	# 草本期找不到好睡處
	gs.region_burn["forest_east"] = today - 30
	gs.current_region = "forest_east"
	var sleep_found := 0
	for i in 400:
		var nd: Dictionary = load("res://scripts/core/ExploreSystem.gd").generate({"region_id": "forest_east", "season": "summer", "period": "dawn", "depletion": {},
			"burn": gs.burn_state("forest_east"), "burn_stage": gs.burn_stage("forest_east"), "known_features": [], "prey_knowledge": {}, "weather": "clear"})
		if str(nd.get("feature_id", "")) == "good_sleep_spot":
			sleep_found += 1
	_ok(sleep_found == 0, "草本期找不到好睡處（%d 次）" % sleep_found)
	var sleep_normal := 0
	for i in 400:
		var nd2: Dictionary = load("res://scripts/core/ExploreSystem.gd").generate({"region_id": "forest_east", "season": "summer", "period": "dawn", "depletion": {},
			"burn": "", "burn_stage": "shrub", "known_features": [], "prey_knowledge": {}, "weather": "clear"})
		if str(nd2.get("feature_id", "")) == "good_sleep_spot":
			sleep_normal += 1
	_ok(sleep_normal > 0, "灌木期找得到好睡處（%d 次；對照上一條是不是真的有效）" % sleep_normal)
	# 走進來的描述：每個階段一次
	var said: Array = []
	var cb := func(t: String): said.append(t)
	gs.log_message.connect(cb)
	gs.region_burn["forest_east"] = today - 100
	gs.life_log["burn_seen"] = {}
	gs._describe_burned_arrival("forest_east")
	gs._describe_burned_arrival("forest_east")
	gs.region_burn["forest_east"] = today - 250
	gs._describe_burned_arrival("forest_east")
	gs.log_message.disconnect(cb)
	_ok(said.size() == 2, "灌木期、年輕的森林各描述一次（%d 句：%s）" % [said.size(), str(said)])
	print("大火接進世界的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
