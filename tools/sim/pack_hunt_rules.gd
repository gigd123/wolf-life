extends SceneTree
# Phase 3 第 7 步「群獵擴充與狼群的衝突」的回歸測試（SPEC Phase 3「群獵」「衝突與戰鬥」）：
#   1. 好幾隻跟著你：一起出獵到這種獵物的上限（含你；鹿類 4），伴侶排第一，每隻照自己的角色上戰術地圖
#   2. 只有子女跟著（伴侶留守）：戰術地圖的文字寫「同伴」，不寫苔原狼
#   3. 一起獵到：伴侶一段、其他每兩隻一段
#   4. 戰鬥時跟著的越多，每回合咬中的機會越高（有上限）
#   5. 6 歲以上的狼在鄰群衝突中是優勢
#   6. 撲上去打：贏了牠們少一隻、戒備你；輸了被趕走，跟著你的成員可能死一隻
# 用法：bash tools/run_sim.sh pack_hunt_rules
var gs
var gt
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

# 有伴侶、n 隻滿 1 歲跟著你的子女
func _pack(n_young: int):
	gs.new_game("forest_east")
	gs.wolf.age_years = 4.0
	for st in [["speed", 66.0], ["skill", 62.0], ["strength", 70.0], ["perception", 70.0]]:
		gs.debug_set_stat(st[0], st[1])
	gs.pending_events.clear()
	gs._spawn_she_wolf()
	var m = gs.she_wolf()
	m.territory = gs.current_region
	m.relation = 8
	gs.she_approach()
	gs.pending_events.clear()
	gt.season_index = 0
	gs.breeding()["pregnant"] = true
	gs.breeding()["winter_fed"] = 1.0
	gs._give_birth()
	gs.pending_events.clear()
	var ps: Array = gs.pups()
	for i in ps.size():
		if i < n_young:
			ps[i].age_years = 2.0
			gs._grow_young()
			ps[i].task = "follow"
		else:
			ps[i].die("test")
	m.task = "follow"
	gs.breeding().erase("prev_task")
	gt.season_index = 2
	return m

func _run() -> void:
	var data = root.get_node("GameData")
	# 1
	var m = _pack(4)
	var h = gs.start_hunt("white_tailed_deer", "adult", -1, false, "forest_edge")
	_check(h.mate_help == m.id and h.pack_allies.size() == 2, "鹿類上限 4（含你）：伴侶＋%d 隻子女" % h.pack_allies.size())
	var th = gs.start_tactical(h)
	var own: Array = th.wolves.filter(func(w): return bool(w.get("own", false)))
	_check(own.size() == 3 and own.filter(func(w): return bool(w.get("mate", false))).size() == 1, "戰術地圖上 3 隻你的狼，其中 1 隻是伴侶")
	_check(th._atx("tactical.ally.snap").contains("同伴"), "好幾隻一起：文字寫「同伴」")
	var hm = gs.start_hunt("moose", "adult", -1, false, "stream")
	_check(hm.pack_allies.size() == 3, "駝鹿上限 5（地圖上最多 4 隻同伴）：伴侶＋%d 隻" % hm.pack_allies.size())
	# 2
	m.task = "den"
	var h2 = gs.start_hunt("white_tailed_deer", "adult", -1, false, "forest_edge")
	var th2 = gs.start_tactical(h2)
	_check(not th2.has_mate_ally() and th2._atx("tactical.ally.snap").contains("同伴") and not th2._atx("tactical.ally.snap").contains("苔原"), "只有子女跟著：寫「同伴」不寫苔原狼")
	m.task = "follow"
	# 3
	gs.start_feeding("white_tailed_deer", "adult", "forest_edge")
	var seg0: int = int(gs.current_feeding["segments_left"])
	gs.current_feeding = {}
	var h3 = gs.start_hunt("white_tailed_deer", "adult", -1, false, "forest_edge")
	h3.result = 1 # HuntSystem.Result.SUCCESS（-s 執行時不能直接引用 class_name 的列舉）
	gs.finish_hunt(h3)
	var want: int = seg0 - 1 - ceili(h3.pack_allies.size() / 2.0)
	_check(int(gs.current_feeding.get("segments_left", 0)) == max(1, want), "一起獵到：伴侶一段、其他每兩隻一段（%d → %d）" % [seg0, int(gs.current_feeding.get("segments_left", 0))])
	gs.current_feeding = {}
	# 4
	var c1 = gs.start_combat("grizzly_bear", "adult", "carcass")
	var one: float = c1.ally_chance
	m = _pack(0)
	var c0 = gs.start_combat("grizzly_bear", "adult", "carcass")
	_check(one > c0.ally_chance and one <= float(data.balance["pack_life"]["combat"]["max"]), "跟著的越多，戰鬥時咬中的機會越高（1 隻 %.0f%%、5 隻 %.0f%%）" % [c0.ally_chance * 100.0, one * 100.0])
	# 5
	gs.meet_pack_id = "black"
	gs._debug_ensure_pack()
	gs.wolf.age_years = 4.0
	var young_c: float = gs.pack_standoff_chance()
	gs.wolf.age_years = 6.5
	_check(gs.pack_standoff_chance() > young_c or gs.pack_standoff_chance() >= float(data.balance["black_pack"]["meet"]["standoff"]["max"]), "6 歲以上在鄰群衝突中是優勢（%.0f%% → %.0f%%）" % [young_c * 100.0, gs.pack_standoff_chance() * 100.0])
	gs.wolf.age_years = 4.0
	# 6
	var fc: Dictionary = data.balance["black_pack"]["meet"]["fight"]
	m = _pack(2)
	gs.current_region = "mountain_canyon"
	gs.meet_pack_id = "mountain"
	var mp = gs.pack_by_id("mountain")
	mp.young = [1.5, 2.0, 0.5]
	fc["min"] = 1.0
	fc["max"] = 1.0
	var r: Dictionary = gs.pack_fight()
	_check(r["won"] and mp.young.size() == 2 and gs.pack_attitude_of(mp) == "wary", "打贏了：牠們少一隻、之後戒備你")
	fc["min"] = 0.0
	fc["max"] = 0.0
	fc["member_death"] = 1.0
	gs.current_region = "mountain_canyon"
	var before: int = gs.followers().size()
	r = gs.pack_fight()
	_check(not r["won"] and str(r["member_lost"]) != "" and gs.followers().size() == before - 1 and gs.current_region != "mountain_canyon", "打輸了：被趕走、跟著你的成員少一隻")
	_check(gs.life_events("pack.fight").size() == 2, "寫進生命事件")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
