extends SceneTree
# Phase 3 第 5 步「繁殖與育幼」的回歸測試（SPEC Phase 3「繁殖與育幼」）：
#   1. 冬季換春季：有伴侶、吃得夠時懷孕（字卡）；沒有伴侶不會
#   2. 春季第 5 天生幼狼：一窩 3～6 隻、具名、父母；伴侶改成留守；字卡
#   3. 存糧：每天扣伴侶＋每隻幼狼；不夠時幼狼挨餓（事件）、伴侶出去找（巢穴沒人看著）
#   4. 叼一段回去：走到巢穴才放下；反芻：扣你的飽食度、存糧增加
#   5. 威脅：你在巢穴時是事件（趕走、護住）；不在時自動結算
#   6. 夏季斷奶：搬到集合點、伴侶回到原本的指派；秋季幼狼跟著走、不用再帶回去
#   7. 存檔 → 讀檔：育幼的狀態、幼狼一樣
# 用法：bash tools/run_sim.sh breeding_rules
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

func _types() -> Array:
	return gs.pending_events.map(func(e): return str(e.get("type", "")))

func _run() -> void:
	var cfg: Dictionary = root.get_node("GameData").balance["breeding"]
	cfg["pregnant"] = 1.0
	cfg["pregnant_first_year"] = 1.0
	cfg["threat_chance"] = 0.0
	cfg["pup_death_daily"] = 0.0
	cfg["hunger_death_daily"] = 0.0
	cfg["weather_death_daily"] = 0.0
	# 1
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	gt.season_index = 0
	gs._breeding_on_season(1.0)
	_check(not bool(gs.breeding().get("pregnant", false)), "沒有伴侶不會懷孕")
	var m = _mated("forest_east")
	gt.season_index = 0
	gs._breeding_on_season(1.0)
	_check(bool(gs.breeding().get("pregnant", false)) and _types().has("pups_expected"), "有伴侶、冬天吃得夠：懷孕（字卡）")
	# 2
	gt.day = 5
	gs.pending_events.clear()
	gs._update_breeding()
	var ps: Array = gs.pups()
	_check(ps.size() >= 3 and ps.size() <= 6 and _types().has("pups_born"), "春季第 5 天生了 %d 隻（字卡）" % ps.size())
	_check(ps.all(func(p): return p.parents.has(m.id) and p.pack_id == "player" and p.age_years == 0.0), "幼狼具名、記著父母")
	_check(m.task == "den" and m.territory == gs.den_region, "伴侶改成留守巢穴")
	# 3
	var need: float = gs.den_daily_need()
	_check(is_equal_approx(need, float(cfg["mate_need"]) + float(cfg["pup_need"]["spring"]) * ps.size()), "每天的需求 = 伴侶 + 每隻幼狼（%.0f）" % need)
	gs.breeding()["den_food"] = need * 1.5
	gs.pending_events.clear()
	gs._update_breeding()
	_check(is_equal_approx(float(gs.breeding()["den_food"]), need * 0.5) and not _types().has("pups_hungry"), "存糧扣掉一天的量")
	gs._update_breeding()
	_check(_types().has("pups_hungry") and int(gs.breeding()["hungry_days"]) == 1, "存糧不夠：幼狼挨餓（事件）")
	# 4
	gs.current_region = "forest_north"
	gs.start_feeding("white_tailed_deer", "adult", "forest_edge")
	var seg0: int = int(gs.current_feeding["segments_left"])
	gs.carry_to_den()
	_check(int(gs.current_feeding.get("segments_left", 0)) == seg0 - 1 and float(gs.breeding()["carrying"]) > 0.0 and float(gs.breeding()["den_food"]) == 0.0, "叼一段：還沒走到巢穴不算進存糧")
	gs.current_feeding = {}
	gs.current_region = gs.den_region
	gs._deliver_food()
	var after_carry: float = float(gs.breeding()["den_food"])
	_check(after_carry > 0.0 and float(gs.breeding()["carrying"]) == 0.0, "走到巢穴：放下（存糧 %.0f）" % after_carry)
	gs.wolf.hunger = 100.0
	var got: float = gs.regurgitate()
	_check(got > 0.0 and gs.wolf.hunger < 100.0 and float(gs.breeding()["den_food"]) > after_carry, "反芻：扣你的飽食度、存糧增加 %.0f" % got)
	# 5
	gs.pending_events.clear()
	gs._den_threat(true)
	var te: Array = gs.pending_events.filter(func(e): return str(e.get("type", "")) == "den_threat")
	_check(not te.is_empty(), "你在巢穴：有東西靠近是事件")
	var n0: int = gs.pups().size()
	cfg["defend"]["base"][str(te[0]["animal"])] = 2.0
	var res: Dictionary = gs.den_threat_choice(str(te[0]["animal"]), true)
	_check(res["ok"] and gs.pups().size() == n0, "趕走了：一隻都沒少")
	gs.current_region = "forest_north"
	cfg["unguarded_loss"] = 1.0
	gs._den_threat(false)
	_check(gs.pups().size() < n0, "你不在、沒人看著：少了幼狼（%d → %d）" % [n0, gs.pups().size()])
	# 6
	gt.season_index = 1
	gs._breeding_on_season(1.0)
	var spot: String = gs.pup_spot()
	var near: Array = [gs.den_region] + root.get_node("GameData").regions()[gs.den_region].get("adjacent", [])
	_check(near.has(spot) and m.task == "follow", "夏季斷奶：集合點在巢穴附近（%s）、伴侶回到原本的指派" % spot)
	_check(is_equal_approx(gs.den_daily_need(), float(cfg["pup_need"]["summer"]) * gs.pups().size()), "夏季只算幼狼")
	gt.season_index = 2
	gs._breeding_on_season(1.0)
	_check(not gs.pups_need_food() and gs.pups().all(func(p): return p.task == "follow"), "秋季：幼狼跟著走，不用再帶回去")
	# 7
	var ids: Array = gs.pups().map(func(p): return p.id)
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game("forest_east")
	gs.load_from_dict(d)
	_check(gs.pups().map(func(p): return p.id) == ids, "存檔後幼狼一樣")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
