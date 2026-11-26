extends SceneTree
# 2026-11-24 試玩回報的回歸測試：
#   A. 黑狼已經有家人時，單獨打贏帶頭的黑狼不會拿到牠們那一帶（own_territory、marks 不變，c 帶 family_kept）；還沒有家人時照舊拿到
#   C. 撞上整群打贏後追擊帶頭的（Phase 3d）：可不可以追、被擋住的機率、被擋挨一口、追上咬死
#   B. 撞上整群打贏：選單式有年輕成員時咬死一隻（killed=1、少一隻）、沒有年輕成員時 killed=0；戰術戰鬥照傳進來的實際死亡數
# 用法：bash tools/run_sim.sh pack_fight_result_rules
var gs
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _combat():
	var c = load("res://scripts/core/Combat.gd").new(gs.wolf, "stranger_wolf", "adult", "territory")
	c.outcome = "drove_off"
	c.opp_hp = 5.0
	c.opp_hp_max = 30.0
	return c

func _run() -> void:
	print("== A. 單獨打贏帶頭的黑狼")
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	var terr: String = gs.stranger_territory
	gs.black_pack.stage = "pack"
	gs.black_pack.regions = [terr]
	var before = gs.life_log.get("own_territory", "")
	var c = _combat()
	gs._after_stranger_combat(c)
	_check(gs.life_log.get("own_territory", "") == before, "有家人：地盤沒有轉給你（%s）" % str(gs.life_log.get("own_territory", "")))
	_check(not gs.life_log.get("marks", {}).has(terr) or before == terr, "有家人：牠們那一帶沒有記成你的記號")
	_check(bool(c.get_meta("family_kept", false)), "有家人：結果帶 family_kept（顯示「牠退回家人那邊」）")
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	terr = gs.stranger_territory
	gs.black_pack.stage = "lone"
	c = _combat()
	gs._after_stranger_combat(c)
	_check(gs.life_log.get("own_territory", "") == terr, "沒有家人：照舊拿到牠的地盤")
	_check(not bool(c.get_meta("family_kept", true)), "沒有家人：不帶 family_kept")

	print("== B. 撞上整群打贏")
	gs.new_game("forest_east")
	gs.wolf.age_years = 3.0
	var mp = gs.black_pack
	mp.stage = "pack"
	mp.regions = [gs.stranger_territory]
	mp.young = [1.5, 1.2, 0.5]
	var r: Dictionary = gs._pack_fight_after(mp, true, "")
	_check(int(r.get("killed", -1)) == 1 and mp.young.size() == 2, "選單式、有年輕成員：咬死一隻（killed=%d，剩 %d 隻）" % [int(r.get("killed", -1)), mp.young.size()])
	mp.young = [0.5]
	r = gs._pack_fight_after(mp, true, "")
	_check(int(r.get("killed", -1)) == 0 and mp.young.size() == 1, "選單式、沒有滿一歲的：沒有咬死（killed=%d）" % int(r.get("killed", -1)))
	mp.young = [1.5, 1.2]
	r = gs._pack_fight_after(mp, true, "", 0)
	_check(int(r.get("killed", -1)) == 0 and mp.young.size() == 2, "戰術、沒有死的：killed=0、成員不變")
	r = gs._pack_fight_after(mp, true, "", 2)
	_check(int(r.get("killed", -1)) == 2 and mp.young.is_empty(), "戰術、死了兩隻：killed=2、少兩隻")
	mp.young = [1.5]
	r = gs._pack_fight_after(mp, false, "")
	_check(int(r.get("killed", -1)) == 0 and mp.young.size() == 1, "打輸：沒有咬死")
	print("== C. 撞上整群打贏後追擊帶頭的（Phase 3d 第 1 步）")
	var pc: Dictionary = root.get_node("GameData").balance["black_pack"]["pursuit"]
	var keep := pc.duplicate()
	gs.new_game("forest_east")
	gs.wolf.age_years = 4.0
	mp = gs.black_pack
	mp.stage = "pack"
	mp.regions = [gs.stranger_territory]
	mp.mate_age = 4.0
	mp.young = [1.5]
	gs.meet_pack_id = "black"
	var rr := {"won": true, "leader_submitted": true, "blockers": 2}
	_check(gs.can_pursue_pack(rr), "打贏、帶頭的示弱：可以追擊")
	_check(not gs.can_pursue_pack({"won": true, "leader_submitted": false}), "帶頭的沒示弱：不能追擊")
	var od: Dictionary = gs.pack_pursuit_odds(rr)
	_check(absf(float(od["block"]) - 0.4375) < 0.001, "兩隻家人：被擋住 1 − 0.75² = 44%%（%.3f）" % float(od["block"]))
	pc["block_each"] = 1.0
	var hp0: float = gs.wolf.health
	var pr: Dictionary = gs.pack_pursue(rr)
	_check(pr["result"] == "blocked" and gs.wolf.health < hp0 and gs.pack_leader_of(mp).alive, "被家人擋住：挨一口、帶頭的逃掉（%s，傷 %.0f）" % [pr["result"], float(pr["dmg"])])
	pc["block_each"] = 0.0
	pc["base"] = 1.0
	# 追上的機率上限 95%：最多追 20 次（沒追上帶頭的還活著，可以再追）
	for k in 20:
		pr = gs.pack_pursue(rr)
		if pr["result"] == "caught":
			break
	_check(pr["result"] == "caught" and not gs.pack_leader_of(mp).alive, "沒被擋、追上：咬死帶頭的（%s）" % pr["result"])
	for k in keep:
		pc[k] = keep[k]
	print("結果：%s（失敗 %d）" % ["全部通過" if fails == 0 else "有失敗", fails])
	quit(1 if fails > 0 else 0)
