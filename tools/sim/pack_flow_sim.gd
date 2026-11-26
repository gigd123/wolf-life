extends SceneTree
# Phase 3d 第 3 步：狼群流動的一生模擬（SPEC Phase 3d「假設、驗證方式、通過標準」）。
# 自動玩家（STYLE，預設 assault 強攻：比較常和狼群對峙、打）從四張地圖的巢穴輪流活到死。每一隻記：
#   搬家（pack.moved：被你在核心區連贏、或衝突輸了）、狼群之間的衝突（pack.conflict）、你在核心區連贏造成的搬家、
#   狼群散掉（黑狼一家 dissolved、鄰群 gone）、死時每張地圖住著幾群、活著的狼群總數、壽命。
# 通過標準：一生平均 2～6 次搬家或衝突；狼群不會在一兩年內全部散光；強的玩家一生至少一次在核心區連贏 2 次。
# 用法：bash tools/run_sim.sh pack_flow_sim "" 20（第三個參數是隻數）；STYLE=average
var f := 0
const DENS := ["forest_east", "tundra_south", "mountain_canyon", "grassland_riverwoods"]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var GS = root.get_node("GameState")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 20
	var style: String = OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "assault"
	var tot := {"moved": 0, "conflict": 0, "player_moves": 0, "dissolved": 0, "lifespan": 0.0, "lives_with_player_move": 0, "empty_all_2y": 0}
	var end_maps := {}
	var lines: Array = []
	for r in runs:
		var ap = AP.new("all", style)
		ap.start(DENS[r % DENS.size()])
		var guard := 0
		var all_gone_by := -1.0
		while not ap.done() and guard < 4000:
			guard += 1
			ap.step(1)
			if all_gone_by < 0.0 and GS.wolf.age_years < 2.7:
				var any := false
				for p in GS.all_packs():
					if GS.pack_is_active(p):
						any = true
				if not any:
					all_gone_by = GS.wolf.age_years
		var moved: int = GS.life_events("pack.moved").size()
		var conf: int = GS.life_events("pack.conflict").size()
		var pm: int = moved - conf
		var dis: int = GS.life_events("pack.dissolved").size()
		for p in GS.all_packs():
			if p.stage == "gone":
				dis += 0
		tot["moved"] += moved
		tot["conflict"] += conf
		tot["player_moves"] += pm
		tot["dissolved"] += dis
		tot["lifespan"] += GS.wolf.age_years
		if pm > 0:
			tot["lives_with_player_move"] += 1
		if all_gone_by >= 0.0:
			tot["empty_all_2y"] += 1
		var occ := {}
		for p in GS.all_packs():
			if GS.pack_is_active(p) and not p.off_map:
				occ[p.map_id] = int(occ.get(p.map_id, 0)) + 1
		for m in occ:
			end_maps[m] = int(end_maps.get(m, 0)) + int(occ[m])
		lines.append("  #%d %.1f 歲：搬家 %d（你造成 %d、衝突 %d）散掉 %d；死時 %s" % [r, GS.wolf.age_years, moved, pm, conf, dis, str(occ)])
		ap.finish()
	var n: float = float(maxi(1, runs))
	print("== pack_flow_sim：%s，%d 隻" % [style, runs])
	for l in lines:
		print(l)
	print("  平均：搬家＋衝突 %.1f 次（你造成的搬家 %.1f、衝突 %.1f）、黑狼一家散掉 %.1f、壽命 %.1f；一生至少一次你造成搬家 %d%%；2.7 歲前狼群全部散光 %d%%" % [
		(tot["moved"]) / n, tot["player_moves"] / n, tot["conflict"] / n, tot["dissolved"] / n, tot["lifespan"] / n, roundi(100.0 * tot["lives_with_player_move"] / n), roundi(100.0 * tot["empty_all_2y"] / n)])
	print("  死時各地圖住的狼群（合計）：%s" % str(end_maps))
	quit()
	return true
