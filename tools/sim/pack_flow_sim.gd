extends SceneTree
# Phase 3d 第 3 步：狼群流動的一生模擬（SPEC Phase 3d「假設、驗證方式、通過標準」）。
# 自動玩家（STYLE，預設 assault 強攻：比較常和狼群對峙、打）從四張地圖的巢穴輪流活到死。每一隻記：
#   搬家（pack.moved：被你在核心區連贏、或衝突輸了）、狼群之間的衝突（pack.conflict）、你在核心區連贏造成的搬家、
#   狼群散掉（黑狼一家 dissolved、鄰群 gone）、死時每張地圖住著幾群、活著的狼群總數、壽命。
# 通過標準：一生平均 2～6 次搬家或衝突；狼群不會在一兩年內全部散光；強的玩家一生至少一次在核心區連贏 2 次。
#   SEEK 的玩家走進核心區後會嚎叫（核心區嚎叫 30% 牠們直接循聲過來，撞上狼群）
# 用法：bash tools/run_sim.sh pack_flow_sim "" 20（第三個參數是隻數）；STYLE=average；SEEK=1 會去核心區找狼群（SEEK_CHANCE 每天的機會，預設 0.3）
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
	var seek: bool = OS.get_environment("SEEK") != ""
	var seek_chance: float = float(OS.get_environment("SEEK_CHANCE")) if OS.get_environment("SEEK_CHANCE") != "" else 0.3
	var tot := {"moved": 0, "conflict": 0, "player_moves": 0, "dissolved": 0, "lifespan": 0.0, "lives_with_player_move": 0, "empty_all_2y": 0}
	var end_maps := {}
	var lines: Array = []
	# 依地圖拆開：衝突、搬出去（依原因）、散掉（依原因）
	var by_map := {}
	for r in runs:
		var ap = AP.new("all", style)
		ap.start(DENS[r % DENS.size()])
		var guard := 0
		var all_gone_by := -1.0
		var last_day := -1
		var prev := {} # pack.id → {map, active, conflicts}
		while not ap.done() and guard < 4000:
			guard += 1
			ap.step(1)
			# SEEK=1：會去核心區找狼群的玩家（只在模擬裡）：3 歲以上、血量七成以上時，每天 SEEK_CHANCE 的機會走到這張地圖某一群的核心區
			var today: int = int(GS.life_log.get("days_lived", 0))
			if seek and today != last_day:
				last_day = today
				if GS.wolf.age_years >= 3.0 and GS.wolf.health >= GS.wolf.health_max * 0.7 and randf() < seek_chance:
					var cores: Array = []
					for p in GS.all_packs():
						if GS.pack_is_active(p) and not p.off_map and not p.regions.is_empty() and p.map_id == GS.current_map():
							cores.append(str(p.regions[0]))
					if not cores.is_empty():
						GS.current_region = str(cores[randi() % cores.size()])
						# 在核心區嚎叫（試玩時使用者會循著嚎叫去找牠們）：核心區嚎叫有機率讓牠們直接循聲過來
						GS.action_howl()
			# 每步比對每一群：還在不在、住哪張地圖；散掉時看牠前 10 天（一季）內有沒有打過衝突
			for p in GS.all_packs():
				var act: bool = GS.pack_is_active(p)
				var was: Dictionary = prev.get(p.id, {})
				if not was.is_empty() and was["active"] and not act:
					var bm: Dictionary = by_map.get_or_add(str(was["map"]), {})
					var after_conf := false
					for e in GS.life_events("pack.conflict"):
						if today - int(e.get("day", 0)) <= 10 and (str(e.get("loser", "")) == p.id or str(e.get("winner", "")) == p.id):
							after_conf = true
					# gone＝整群散掉；其他（lone、vacant…）＝只剩一隻或帶頭的空著，之後可能再成群
					var key: String = ("gone" if p.stage == "gone" else "inactive_" + p.stage) + ("_after_conflict" if after_conf else "")
					bm[key] = int(bm.get(key, 0)) + 1
				prev[p.id] = {"map": p.map_id, "active": act}
			if all_gone_by < 0.0 and GS.wolf.age_years < 2.7:
				var any := false
				for p in GS.all_packs():
					if GS.pack_is_active(p):
						any = true
				if not any:
					all_gone_by = GS.wolf.age_years
		for e in GS.life_events("pack.conflict"):
			var d: Dictionary = e
			var bm: Dictionary = by_map.get_or_add(str(d.get("map", "?")), {})
			bm["conflict"] = int(bm.get("conflict", 0)) + 1
			bm["lost_moved_out"] = int(bm.get("lost_moved_out", 0)) + 1
			var bt: Dictionary = by_map.get_or_add(str(d.get("to_map", "?")), {})
			bt["moved_in"] = int(bt.get("moved_in", 0)) + 1
		var moved: int = GS.life_events("pack.moved").size()
		var conf: int = GS.life_events("pack.conflict").size()
		var pm: int = int(GS.life_log.get("stats", {}).get("pack_meet", {}).get("player_moves", 0))
		var dis: int = GS.life_events("pack.dissolved").size()
		var arrived: int = GS.life_events("pack.arrived").size()
		tot["arrived"] = int(tot.get("arrived", 0)) + arrived
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
		if OS.get_environment("DEBUG_MEET") != "":
			print("    pack_meet ", GS.life_log.get("stats", {}).get("pack_meet", {}), " core_wins ", GS.life_log.get("core_wins", {}))
		lines.append("  #%d %.1f 歲：搬家 %d（衝突輸的 %d）散掉 %d、新來 %d；死時 %s" % [r, GS.wolf.age_years, moved, conf, dis, arrived, str(occ)])
		ap.finish()
	var n: float = float(maxi(1, runs))
	print("== pack_flow_sim：%s%s，%d 隻" % [style, "＋去核心區找狼群（每天 %d%%）" % roundi(seek_chance * 100.0) if seek else "", runs])
	for l in lines:
		print(l)
	print("  平均：搬家＋衝突 %.1f 次（你造成的搬家 %.1f、衝突 %.1f）、黑狼一家散掉 %.1f、新來的狼群 %.1f、壽命 %.1f；一生至少一次你造成搬家 %d%%；2.7 歲前狼群全部散光 %d%%" % [
		(tot["moved"]) / n, tot["player_moves"] / n, tot["conflict"] / n, tot["dissolved"] / n, int(tot.get("arrived", 0)) / n, tot["lifespan"] / n, roundi(100.0 * tot["lives_with_player_move"] / n), roundi(100.0 * tot["empty_all_2y"] / n)])
	print("  死時各地圖住的狼群（合計）：%s" % str(end_maps))
	print("  依地圖（%d 隻合計）：conflict＝在這張地圖起衝突、lost_moved_out＝衝突輸的搬走、moved_in＝衝突輸的搬進來、gone＝整群散掉、inactive_*＝暫時不成群（剩一隻等），_after_conflict＝前 10 天內打過衝突" % runs)
	for m in by_map:
		print("    %s：%s" % [m, str(by_map[m])])
	quit()
	return true

