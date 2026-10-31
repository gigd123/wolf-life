extends SceneTree
# Phase 3 第 8 步「加入既有狼群、取而代之」的回歸測試（SPEC Phase 3「加入既有狼群」）：
#   1. 繁殖公狼不在、沒有子女接手：有空缺（事件）；你有資格時那隻母狼成為「還在認識的母狼」
#   2. 你已經有伴侶：沒有資格
#   3. 那隻母狼不會因為你太久沒去就走
#   4. 關係到伴侶：接手那一群（地盤、巢穴、成員都留下、前任的子女是「熟悉」），那一群解散
#   5. 空缺一季沒人補：解散、母狼也走
#   6. 挑戰：繁殖公狼老了或受傷才可以；有伴侶、黑狼一家不行
#   7. 挑戰贏了：接手（成員一部分留下）、母狼成為伴侶
# 用法：bash tools/run_sim.sh join_rules
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

func _vacant_setup():
	gs.new_game("mountain_foothills")
	gs.wolf.age_years = 3.0
	gs.pending_events.clear()
	var p = gs.pack_by_id("mountain")
	p.regions = ["mountain_canyon", "mountain_headwaters"]
	p.stage = "pack"
	p.young = [0.25, 0.75]
	p.mate_age = 4.0
	root.get_node("GameData").balance["black_pack"]["pup_survival_per_season"] = 1.0
	gs.npcs[p.leader_id].die("old_age")
	gt.season_index = 1
	gs._update_neighbor_packs()
	return p

func _run() -> void:
	var data = root.get_node("GameData")
	# 1
	var p = _vacant_setup()
	var n = gs.she_wolf()
	_check(p.vacant and gs.pending_events.any(func(e): return str(e.get("type", "")) == "pack_vacancy"), "有空缺（事件）")
	_check(n != null and n.pack_id == "mountain" and gs.mate_stage() == "candidate", "那隻母狼成為還在認識的母狼（屬於山地的那一群）")
	# 3
	gs.life_log["days_lived"] = gs._today() + 20
	data.balance["mate"]["leave_chance_per_day"] = 1.0
	gs._update_she_wolf()
	data.balance["mate"]["leave_chance_per_day"] = 0.25
	_check(gs.she_wolf() == n and p.regions.has(n.territory), "太久沒去也不會走，待在牠們的地方（%s）" % n.territory)
	# 4
	gs.current_region = n.territory
	n.relation = 8
	gs.she_approach()
	_check(gs.has_mate() and p.stage == "gone" and p.regions.is_empty(), "關係到伴侶：接手那一群（那一群解散）")
	_check(gs.is_own_territory("mountain_canyon") and gs.is_own_territory("mountain_headwaters") and gs.den_region == "mountain_canyon", "牠們的地方變成你的地盤，巢穴搬到峽谷")
	var kids: Array = gs.pack_members().filter(func(m): return m.pack_id == "player")
	_check(kids.size() == 2 and kids.all(func(m): return m.relation == 3 and m.parents == ["pack_mountain"]), "成員都留下，前任的子女一開始是熟悉（%d 隻）" % kids.size())
	_check(gs.life_events("pack.joined").size() == 1 and str(gs.life_events("mate").back().get("how", "")) == "pack", "寫進生命事件")
	var grown = kids.filter(func(m): return m.age_years >= 1.0)
	_check(not grown.is_empty() and grown[0].speed > 40.0, "前任的年輕成員能力照年紀（速度 %.0f）" % grown[0].speed)
	# 2
	p = gs.pack_by_id("grassland")
	p.stage = "pack"
	p.young = []
	p.regions = ["grassland_plains"]
	gs.npcs[p.leader_id].die("old_age")
	gs.pending_events.clear()
	gs._update_neighbor_packs()
	_check(gs.she_wolf() != null and gs.she_wolf().pack_id == "", "已經有伴侶：沒有資格（不會換成那一群的母狼）")
	# 5
	p = _vacant_setup()
	gt.season_index = 2
	gs._update_neighbor_packs()
	_check(p.stage == "gone" and gs.she_wolf() == null, "空缺一季沒人補：解散、母狼也走")
	# 6
	gs.new_game("mountain_foothills")
	gs.wolf.age_years = 3.0
	var mp = gs.pack_by_id("mountain")
	var leader = gs.npcs[mp.leader_id]
	leader.age_years = 4.0
	_check(not gs.can_challenge_pack(mp), "年輕健康的繁殖公狼不能挑戰")
	leader.age_years = 6.5
	_check(gs.can_challenge_pack(mp), "老了可以挑戰")
	leader.age_years = 4.0
	leader.health = leader.health_max * 0.4
	_check(gs.can_challenge_pack(mp), "受傷可以挑戰")
	_check(not gs.can_challenge_pack(gs.black_pack), "黑狼一家不行")
	gs._spawn_she_wolf()
	gs.she_wolf().territory = gs.current_region
	gs.she_wolf().relation = 8
	gs.she_approach()
	_check(not gs.can_challenge_pack(mp), "有伴侶不行")
	# 7
	gs.new_game("mountain_foothills")
	gs.wolf.age_years = 3.0
	mp = gs.pack_by_id("mountain")
	mp.young = [1.0, 1.5, 2.0, 2.5]
	gs.meet_pack_id = "mountain"
	gs.npcs[mp.leader_id].age_years = 7.0
	var c = gs.start_pack_challenge()
	c.outcome = "drove_off"
	gs.finish_combat(c)
	var kept: int = gs.pack_members().filter(func(m): return m.pack_id == "player").size()
	_check(gs.has_mate() and mp.stage == "gone" and not gs.npcs[mp.leader_id].alive and kept <= 4, "挑戰贏了：接手，母狼成為伴侶，成員留下 %d／4" % kept)
	_check(gs.life_events("pack.taken").size() == 1, "寫進生命事件（取而代之）")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
