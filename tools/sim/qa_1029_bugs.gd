extends SceneTree
# 2026-10-29 QA 回報的三個 bug（docs/proposals/qa-2026-10-29.md）：
#   1. 黑狼成家後，贏過牠（威嚇成功）留在原地：牠不再單獨出來要你離開；任何黑狼事件後 quiet_periods 個時段內不再有
#   2. 進食時灰熊來搶食只在這一區、這一季有灰熊的地方（牧場、苔原北部不會）；森林照舊
#   3. 這一區這一季沒有任何獵物（冬季的屋舍與畜欄）時，探索空手的句子不出現原始的翻譯鍵
# 用法：bash tools/run_sim.sh qa_1029_bugs
var gs
var gt
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ✓ " if ok else "  ✗ ") + what)

func _run() -> void:
	# 1
	var quiet: int = int(root.get_node("GameData").balance["black_pack"]["meet"]["quiet_periods"])
	var confront := 0
	var early := 0
	var later := 0
	for run in 200:
		gs.new_game("forest_east")
		gs.wolf.age_years = 3.0
		gs.life_log["stranger_observed"] = true
		gs.life_log["stranger_unlock"] = "subadult"
		var terr: String = gs.stranger_territory
		gs.current_region = terr
		gs.black_pack.stage = "pack"
		gs.black_pack.regions = [terr]
		var c = gs.start_stranger_combat("territory")
		c.outcome = "drove_off"
		gs.finish_combat(c)
		gs.pending_events.clear()
		var p0: int = gs._abs_period()
		for p in 40:
			gt.advance_turns(4)
			gs.current_region = terr
			for e in gs.pending_events:
				var ty: String = str(e.get("type", ""))
				if ty == "stranger_confront":
					confront += 1
				# 只算黑狼一家（Phase 3 第 4 步之後，一般鄰群也會撞上，牠們有自己的冷卻）
				if ty in ["stranger_confront", "driven_off"] or (ty == "pack_meet" and str(e.get("pack", "black")) == "black"):
					if gs._abs_period() - p0 < quiet:
						early += 1
					else:
						later += 1
			gs.pending_events.clear()
	_check(confront == 0 and early == 0, "黑狼成家、贏過牠之後：不再單獨出來要你離開（%d）、%d 個時段內沒有黑狼的事件（%d）；之後撞上狼群 %d 次" % [confront, quiet, early, later])
	# 2
	gs.new_game("grassland_plains")
	gs.wolf.age_years = 3.0
	gs.debug_ranch("open")
	gt.season_index = gt.SEASONS.find("summer")
	gs.start_feeding("cattle", "adult", "prairie")
	var bears := {}
	for r in ["ranch_pasture", "ranch_yard", "tundra_north", "forest_east", "forest_west"]:
		gs.current_region = r
		bears[r] = snappedf(float(gs.scavenge_chances()["bear"]), 0.01)
	gs.current_feeding = {}
	_check(bears["ranch_pasture"] == 0.0 and bears["ranch_yard"] == 0.0 and bears["tundra_north"] == 0.0 and bears["forest_east"] > 0.0,
		"進食時灰熊來搶：只在有灰熊的區域（%s）" % [bears])
	# 3
	gs.new_game("grassland_plains")
	gs.wolf.age_years = 3.0
	gs.debug_ranch("open")
	gs.pending_events.clear()
	change_scene_to_file("res://scenes/Game.tscn")
	await _wait(6)
	var game = current_scene
	game.text_watch_timer = 0.0
	gt.season_index = gt.SEASONS.find("winter")
	var raw := 0
	var empty := 0
	for i in 150:
		gs.current_region = "ranch_yard"
		gs.wolf.stamina = 90.0
		gs.wolf.hunger = 90.0
		gs.action_explore()
		var d: Dictionary = gs.current_discovery
		if str(d.get("kind", "")) == "nothing" and str(d.get("absent_source", "")) == "" and not d.has("ranch_sign"):
			empty += 1
			var txt: String = game._discovery_text(d)
			if txt.contains("animal.") or txt.contains("{"):
				raw += 1
		gs.clear_discovery()
		gs.pending_events.clear()
		gt.season_index = gt.SEASONS.find("winter")
	_check(empty > 0 and raw == 0, "冬季的屋舍與畜欄空手 %d 次：句子都沒有原始的翻譯鍵（%d）" % [empty, raw])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
