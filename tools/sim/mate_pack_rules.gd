extends SceneTree
# Phase 3 第 3 步「伴侶同行、狼群面板、戰術地圖上的伴侶」的回歸測試（SPEC Phase 3「同行與指派」「群獵」）：
#   1. 成為伴侶後預設跟著你；指派一直有效：留守、休息在巢穴，自由行動在巢穴附近
#   2. 傷太重（血量低於 follow_min_health）不跟，留在巢穴養傷；休息養傷回得比較快
#   3. 跟著你：追蹤的感知多一點、夜裡比較不會被撞見、戰鬥時一起上（ally_chance）
#   4. 狩獵：伴侶在戰術地圖上（mate 旗標、牠自己的能力、照角色）；自動分配角色；文字寫「伴侶」
#   5. 埋伏：趴著等的伴侶獵物不躲（逃跑方向、離狼的距離不算牠）
#   6. 一起獵到：牠吃一段；還在認識、關係友善的母狼跟上來一起獵到，關係 +2
#   7. 存檔 → 讀檔：指派、角色一樣
# 用法：bash tools/run_sim.sh mate_pack_rules
var gs
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _mated(den: String):
	gs.new_game(den)
	gs.wolf.age_years = 3.0
	gs.pending_events.clear()
	gs._spawn_she_wolf()
	var n = gs.she_wolf()
	n.territory = gs.current_region
	n.relation = 8
	gs.she_approach()
	gs.pending_events.clear()
	return n

func _run() -> void:
	var data = root.get_node("GameData")
	# 1
	var n = _mated("forest_east")
	_check(gs.has_mate() and n.task == "follow" and gs.followers().has(n), "成為伴侶後預設跟著你")
	gs.current_region = "forest_north"
	gs.set_task(n.id, "den")
	_check(n.territory == gs.den_region and gs.followers().is_empty(), "留守巢穴：在巢穴、不跟著你")
	gs.set_task(n.id, "free")
	var near: Array = ["forest_east"] + data.regions()["forest_east"].get("adjacent", [])
	_check(near.has(n.territory), "自由行動：在巢穴附近（%s）" % n.territory)
	gs.set_task(n.id, "follow")
	_check(n.territory == gs.current_region, "改回跟著你：到你身邊")
	# 2
	n.health = n.health_max * 0.3
	_check(gs.followers().is_empty() and not gs.mate_follows_here(), "傷太重不跟")
	gs.set_task(n.id, "rest")
	var hp0: float = n.health
	gs._heal_npcs()
	gs._rest_members()
	var per: float = float(data.balance["npc_wolves"]["stranger_wolf"]["heal_per_day"])
	_check(n.health - hp0 >= per * 1.9, "休息養傷：一天回兩倍（%.0f）" % (n.health - hp0))
	n.health = n.health_max
	gs.set_task(n.id, "follow")
	# 3
	var p_solo: float = gs.wolf.effective_perception()
	_check(gs.team_perception() > p_solo, "跟著你：追蹤的感知 %.0f → %.0f" % [p_solo, gs.team_perception()])
	var c = gs.start_combat("grizzly_bear", "adult", "carcass")
	_check(c.ally_chance > 0.0, "戰鬥時一起上（每回合 %.0f%%）" % (c.ally_chance * 100.0))
	# 4
	gs.debug_set_stat("perception", 70.0)
	var h = gs.start_hunt("white_tailed_deer", "adult", -1, false, "forest_edge")
	_check(h.mate_help == n.id and h.mate_role == gs.hunt_role_of(n), "狩獵：伴侶一起出獵（角色 %s）" % h.mate_role)
	var th = gs.start_tactical(h)
	var ally: Dictionary = {}
	for w in th.wolves:
		if bool(w.get("mate", false)):
			ally = w
	_check(not ally.is_empty() and float(ally["stats"]["speed"]) == n.speed and str(ally["role"]) == h.mate_role, "戰術地圖上有伴侶（牠自己的速度 %.0f）" % (float(ally["stats"]["speed"]) if not ally.is_empty() else -1.0))
	_check(th._atx("tactical.ally.snap").contains("伴侶"), "同伴的文字寫「伴侶」")
	n.hunt_role = "auto"
	n.speed = 75.0
	_check(gs.hunt_role_of(n) == "drive", "自動分配：快的去驅趕")
	n.speed = 60.0
	n.strength = 70.0
	_check(gs.hunt_role_of(n) == "ambush", "自動分配：力量大的埋伏")
	n.strength = 60.0
	_check(gs.hunt_role_of(n) == "chase", "自動分配：其他追擊")
	# 5
	gs.set_hunt_role(n.id, "ambush")
	var th2 = gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult", -1, false, "forest_edge"))
	var k := -1
	for i in th2.wolves.size():
		if bool(th2.wolves[i].get("mate", false)):
			k = i
	th2.wolves[k]["intent"] = "ambushing"
	th2.wolves[k]["pos"] = th2.deer_pos + Vector2i(1, 0)
	_check(th2._wolf_dist(th2.deer_pos) == th2.dist(th2.deer_pos, th2.wolf_pos), "趴著埋伏的伴侶：獵物不把牠算進離狼的距離")
	th2.wolves[k]["intent"] = "chasing"
	_check(th2._wolf_dist(th2.deer_pos) <= 1.5, "撲出來之後就算")
	# 6
	gs.start_feeding("white_tailed_deer", "adult", "forest_edge")
	var seg0: int = int(gs.current_feeding["segments_left"])
	gs.current_feeding = {}
	var h3 = gs.start_hunt("white_tailed_deer", "adult", -1, false, "forest_edge")
	h3.result = 1 # HuntSystem.Result.SUCCESS（-s 執行時不能直接引用 class_name 的列舉）
	gs.finish_hunt(h3)
	_check(bool(gs.current_feeding.get("with_mate", false)) and int(gs.current_feeding["segments_left"]) == seg0 - 1, "一起獵到：伴侶吃一段（%d → %s）" % [seg0, str(gs.current_feeding.get("segments_left", "-"))])
	gs.current_feeding = {}
	# 還在認識、友善的母狼跟上來
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	gs._spawn_she_wolf()
	var cand = gs.she_wolf()
	cand.territory = gs.current_region
	cand.relation = 6
	data.balance["pack_life"]["candidate_join_chance"] = 1.0
	var h4 = gs.start_hunt("white_tailed_deer", "adult", -1, false, "forest_edge")
	_check(h4.mate_help == cand.id, "友善的母狼在這一區：跟上來一起獵")
	var r0: int = cand.relation
	h4.result = 1 # HuntSystem.Result.SUCCESS（-s 執行時不能直接引用 class_name 的列舉）
	gs.finish_hunt(h4)
	_check(cand.relation == r0 + 2, "一起獵到：關係 +2（%d → %d）" % [r0, cand.relation])
	# 7
	n = _mated("forest_east")
	gs.set_task(n.id, "patrol")
	gs.set_hunt_role(n.id, "ambush")
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game("forest_east")
	gs.load_from_dict(d)
	_check(gs.she_wolf().task == "patrol" and gs.she_wolf().hunt_role == "ambush", "存檔後指派、角色一樣")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
