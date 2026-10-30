extends SceneTree
# Phase 3 第 2 步「離群母狼與配對」的回歸測試（SPEC Phase 3「離群母狼與配對」）：
#   1. 次成年不會遇到；成年後換日時遇到，出現在這一區或相鄰的區域，先是徵兆
#   2. 機率：昨天嚎叫過 ×3、標記過 ×1.5
#   3. 關係升到伴侶：成為伴侶、跳字卡、寫進生命事件
#   4. 搶牠的食物大降，關係 < 0 牠離開；太久沒見會離開
#   5. 嚎叫：牠在相鄰的區域時可能循聲找來
#   6. 你在吃東西時牠來到旁邊：分牠一段（少 1 段、關係 +）
#   7. 在牠面前示弱：關係下降
#   8. 伴侶死去之後可以再找
#   9. 苔原狼只剩一隻母狼、關係友善：換季時留下來成為伴侶
#  10. 存檔 → 讀檔一樣
# 用法：bash tools/run_sim.sh mate_rules
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

func _adult(den: String) -> void:
	gs.new_game(den)
	gs.wolf.age_years = 3.0
	gs.pending_events.clear()
	gs.events_today = 0

func _run() -> void:
	var data = root.get_node("GameData")
	var cfg: Dictionary = data.balance["mate"]
	cfg["daily_chance"] = {"spring": 1.0, "summer": 1.0, "autumn": 1.0, "winter": 1.0}
	# 1
	gs.new_game("forest_east")
	gs.wolf.age_years = 1.0
	gs._update_she_wolf()
	_check(gs.she_wolf() == null, "次成年不會遇到離群母狼")
	_adult("forest_east")
	gs._update_she_wolf()
	var n = gs.she_wolf()
	var near: Array = gs.adjacent_regions() + ["forest_east"]
	_check(n != null and gs.mate_stage() == "candidate" and n.sex == "female" and near.has(n.territory), "成年後遇到：母狼、還在認識、在這一區或相鄰（%s）" % (n.territory if n else "-"))
	_check(gs.pending_events.any(func(e): return str(e.get("type", "")) == "she_wolf_sign"), "先是徵兆（氣味或遠遠看到）")
	# 2
	cfg["daily_chance"] = {"spring": 0.01, "summer": 0.01, "autumn": 0.01, "winter": 0.01}
	_adult("forest_east")
	gs.region_depletion["forest_east"] = {"white_tailed_deer": 0.5}
	var base: float = gs.lone_female_chance()
	gs.life_log["howled_day"] = gs._today() - 1
	var howl: float = gs.lone_female_chance()
	gs.life_log["marked_day"] = gs._today() - 1
	var both: float = gs.lone_female_chance()
	_check(is_equal_approx(howl, base * 3.0) and is_equal_approx(both, base * 4.5), "昨天嚎叫過 ×3、再加標記 ×1.5（%.4f → %.4f → %.4f）" % [base, howl, both])
	cfg["daily_chance"] = {"spring": 1.0, "summer": 1.0, "autumn": 1.0, "winter": 1.0}
	# 3
	_adult("forest_east")
	gs._update_she_wolf()
	n = gs.she_wolf()
	n.territory = gs.current_region
	n.relation = 8
	gs.pending_events.clear()
	gs.she_approach()
	_check(gs.has_mate() and gs.she_relation_key() == "mate", "關係升到伴侶：成為伴侶")
	_check(gs.pending_events.any(func(e): return str(e.get("type", "")) == "she_wolf_mate") and gs.life_events("mate").size() == 1, "跳字卡、寫進生命事件")
	# 4
	_adult("forest_east")
	gs._update_she_wolf()
	n = gs.she_wolf()
	n.territory = gs.current_region
	n.relation = 4
	gs.she_steal()
	_check(gs.she_wolf() != null and gs.she_wolf().relation == 1, "搶牠的食物：關係 −3（%d）" % (gs.she_wolf().relation if gs.she_wolf() else -99))
	gs.she_steal()
	_check(gs.she_wolf() == null and gs.life_events("she_wolf.left").size() == 1, "關係 < 0：牠離開這一帶")
	_adult("forest_east")
	gs._update_she_wolf()
	cfg["leave_chance_per_day"] = 1.0
	cfg["daily_chance"] = {"spring": 0.0, "summer": 0.0, "autumn": 0.0, "winter": 0.0}
	gs.life_log["days_lived"] = gs._today() + int(cfg["absent_days"])
	gs._update_she_wolf()
	_check(gs.she_wolf() == null, "%d 天沒見：牠離開" % int(cfg["absent_days"]))
	cfg["leave_chance_per_day"] = 0.25
	cfg["daily_chance"] = {"spring": 1.0, "summer": 1.0, "autumn": 1.0, "winter": 1.0}
	# 5
	_adult("forest_east")
	gs._update_she_wolf()
	n = gs.she_wolf()
	n.territory = str(gs.adjacent_regions()[0])
	cfg["howl"]["come_chance"] = 1.0
	var res: Dictionary = gs.action_howl()
	_check(res.get("came", false) and n.territory == gs.current_region and str(gs.current_discovery.get("kind", "")) == "she_wolf", "嚎叫：牠從相鄰的區域循聲找來")
	_check(gs.howled_today(), "記下今天嚎叫過")
	gs.clear_discovery()
	# 6
	gs.current_feeding = {"animal_id": "white_tailed_deer", "life_stage": "adult", "segments_left": 3, "segment_value": 20, "turns_stayed": 0, "terrain": "", "src": "kill"}
	var before: int = n.relation
	gs.she_wait_choice(true)
	_check(int(gs.current_feeding["segments_left"]) == 2 and n.relation == before + 2, "分牠一段：少 1 段、關係 +2")
	# 7
	var c = gs.start_combat("red_fox", "adult", "meet")
	c.outcome = "submit"
	before = n.relation
	gs._she_saw_combat(c)
	_check(n.relation == before - 1, "在牠面前示弱：關係 −1")
	# 8
	n.relation = 9
	gs.she_approach()
	n.die("old_age")
	gs._on_npc_died(n)
	_check(not gs.has_mate() and gs.she_wolf() == null and gs.life_events("mate.died").size() == 1, "伴侶死去：寫進生命事件，之後可以再找")
	gs._update_she_wolf()
	_check(gs.she_wolf() != null and gs.mate_stage() == "candidate", "之後又遇到新的離群母狼")
	# 9
	_adult("tundra_south")
	cfg["tundra_replace_chance"] = 1.0
	gs.npcs["tundra_wolf"].alive = false
	var t = gs.npcs["tundra_wolf_mate"]
	t.alive = true
	t.relation = 10
	gs.current_region = gs.tundra_wolves_region() if gs.tundra_wolves_region() != "" else "tundra_south"
	gs._maybe_tundra_mate()
	_check(gs.has_mate() and not t.alive and gs.life_events("mate")[0].get("how", "") == "tundra", "苔原狼只剩母狼、關係友善：留下來成為伴侶")
	# 10
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	var id: String = gs.she_wolf().id
	gs.new_game("forest_east")
	gs.load_from_dict(d)
	_check(gs.has_mate() and gs.she_wolf().id == id, "存檔後伴侶還在")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
