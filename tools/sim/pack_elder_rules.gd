extends SceneTree
# Phase 3 第 9 步「狼群中的老年、一生回顧的家族篇」的回歸測試（SPEC Phase 3「狼群中的老年」「一生回顧」）：
#   1. 外來的公狼（1.9b 的年輕挑戰者）看到你們一群就走的機率：沒有狼群 0、狼群越大越高、有上限
#   2. 牠走了：算來過一次、牠不會變強、過一陣子再來、寫進生命事件
#   3. 牠沒走：探索時遇上的寫成「試探你們的領域」（pack 旗標）
#   4. 把領域留給子女：只在老年、伴侶不在、有 1.5 歲以上的子女；最年長的帶頭成為一群鄰群（和你有血緣：不撞上、不試探），你成為獨居的老狼
#   5. 離群的兒子可能成為鄰群帶頭的公狼（外來的公狼補上空缺時）
#   6. 存檔 → 讀檔：留給子女的那一群還在、態度一樣
#   7. 一生回顧的家族篇：伴侶、幼狼、離群、留給子女
# 用法：bash tools/run_sim.sh pack_elder_rules
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

# 有伴侶、一窩幼狼；n_young 隻長到 age 歲（其他留在幼狼）
func _family(n_young: int, age: float):
	gs.new_game("forest_east")
	gs.wolf.age_years = 4.0
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
	for i in min(n_young, ps.size()):
		ps[i].age_years = age + 0.25 * i
	gs.action_mark()
	return m

func _run() -> void:
	var data = root.get_node("GameData")
	var pe: Dictionary = data.balance["pack_elder"]
	# 1
	gs.new_game("forest_east")
	gs.wolf.age_years = 7.0
	_check(gs.challenger_deter_chance() == 0.0, "沒有狼群：外來的公狼不會因為你們而走")
	var m = _family(3, 2.0)
	var with3: float = gs.challenger_deter_chance()
	m.die("old_age")
	gs._on_npc_died(m)
	var no_mate: float = gs.challenger_deter_chance()
	_check(with3 > no_mate and no_mate > 0.0, "狼群越大越常走（伴侶＋3 隻 %.0f%%、3 隻子女 %.0f%%）" % [with3 * 100.0, no_mate * 100.0])
	_family(9, 1.5)
	_check(gs.challenger_deter_chance() <= float(pe["probe"]["max"]) + 0.001, "有上限（%.0f%%）" % (gs.challenger_deter_chance() * 100.0))
	# 2
	gs.wolf.age_years = 7.0
	pe["probe"]["per_member"] = 1.0
	gs.life_log["challenger_day"] = gs._today()
	var visits: int = int(gs.life_log.get("challenger_visits", 0))
	_check(gs._challenger_backs_off(), "牠看了你們一陣子就走了")
	_check(int(gs.life_log["challenger_visits"]) == visits + 1 and not gs.challenger_grew() and not gs.challenger_due() and gs.life_events("challenger.backed").size() == 1,
		"算來過一次、不會變強、過一陣子再來、寫進生命事件")
	# 3
	pe["probe"]["per_member"] = 0.0
	data.balance["elder"]["challenger"]["explore_chance"] = 1.0
	gs.life_log["challenger_day"] = gs._today()
	_check(gs._maybe_challenger_explore() and bool(gs.current_discovery.get("pack", false)), "沒走：遇上時寫成試探你們的領域")
	gs.clear_discovery()
	pe["probe"]["per_member"] = 0.2
	# 4
	m = _family(2, 2.0)
	gs.wolf.age_years = 7.0
	_check(not gs.can_leave_to_children(), "伴侶還在：不能把領域留給子女")
	m.die("old_age")
	gs._on_npc_died(m)
	gs.wolf.age_years = 5.0
	_check(not gs.can_leave_to_children(), "還沒老：不能")
	gs.wolf.age_years = 7.0
	_check(gs.can_leave_to_children() and gs.available_actions().has("leave_to_children"), "老了、伴侶不在、有長大的子女：可以")
	var eldest = gs._leave_heirs()[0]
	var members: int = gs.young_members().size() + gs.pups().size()
	var r: Dictionary = gs.action_leave_to_children()
	var fp = gs.pack_by_id(str(r.get("pack", "")))
	_check(fp != null and fp.leader_id == eldest.id and fp.regions.has(gs.den_region) and fp.young.size() == members - 1, "最年長的帶頭，其他 %d 隻跟著牠，巢穴在牠們的領域" % (members - 1))
	_check(gs.young_members().is_empty() and gs.pups().is_empty() and gs.own_territories().is_empty() and gs.pack_counted_size() == 1, "你成為獨居的老狼（沒有標記、沒有成員）")
	_check(gs.pack_attitude_of(fp) == "kin" and gs._pack_attitude_value_of(fp, "meet_mult", 1.0) == 0.0 and gs._pack_attitude_value_of(fp, "probe_mult", 1.0) == 0.0, "和你有血緣：不撞上、不試探")
	_check(gs.life_events("pack.left_to_children").size() == 1, "寫進生命事件")
	_check(not gs.can_leave_to_children(), "之後不能再留一次")
	# 6
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.new_game("forest_east")
	gs.load_from_dict(d)
	var fp2 = gs.pack_by_id(str(r.get("pack", "")))
	_check(fp2 != null and fp2.leader_id == eldest.id and gs.pack_attitude_of(fp2) == "kin", "存檔後那一群還在、態度一樣")
	# 5
	_family(1, 3.0)
	var son = gs.young_members()[0]
	son.sex = "male"
	gs._member_leaves(son)
	pe["son_outsider_chance"] = 1.0
	var mp = gs.pack_by_id("mountain")
	_check(gs._dispersed_son_founds(mp) and mp.leader_id == son.id and son.pack_id == "mountain" and gs.life_events("child.founded").size() == 1, "離群的兒子成了鄰群帶頭的公狼")
	pe["son_outsider_chance"] = 0.5
	# 7
	m = _family(2, 2.0)
	var kid = gs.young_members()[0]
	kid.sex = "male"
	gs._member_leaves(kid)
	m.die("old_age")
	gs._on_npc_died(m)
	gs.wolf.age_years = 7.0
	gs.action_leave_to_children()
	gs.add_life_event("death", {"cause": "old_age"})
	var LS = load("res://scripts/ui/LifeSummary.gd").new()
	var lines: Array = LS._family_lines(gs.life_log)
	var all: String = "\n".join(lines)
	print("    " + all.replace("\n", "\n    "))
	_check(all.contains("伴侶") and all.contains("幼狼：") and all.contains("離群的子女 1 隻") and all.contains("把領域留給了"), "家族篇：伴侶、幼狼、離群、留給子女")
	var bio: String = LS._family_bio(gs.life_log)
	_check(bio.contains("養大了") and bio.contains("留給了子女"), "生平：%s" % bio)
	LS.free()
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
