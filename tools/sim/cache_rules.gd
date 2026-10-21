extends SceneTree
# Phase 2e「藏食物」的回歸測試（SPEC「Phase 2e：藏食物」，每段各自記日期，2026-10-21 使用者選 B）：
#   1. 吃殘骸時可以叼一段去藏，殘骸少一段；一區最多 2 段
#   2. 滿了：兩段都新鮮 → 不能藏；有過了新鮮期的 → 換掉最舊的那段
#   3. 每段各自新鮮、過期、壞光；只壞一段時只少那一段，回來才說
#   4. 吃：每次挖一段、先吃比較新鮮的；不在吃殘骸時才能吃；過了新鮮期有機會吃壞肚子、越久越容易
#   5. 整份被挖走、被大火燒掉，回到那一區（或動手藏、挖）才知道；之後可以藏新的
#   6. 存檔、讀檔
# 用法：bash tools/run_sim.sh cache_rules
var f := 0
var fails := 0
var gs

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	root.get_node("RNGService").set_seed(42)
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	var region: String = gs.current_region
	# 1. 藏
	gs.start_feeding("elk", "adult", "clearing")
	var seg0: int = int(gs.current_feeding["segments_left"])
	_check(gs.cache_status() == "ok" and gs.action_cache_segment(), "吃殘骸時可以藏")
	_check(gs.cache_pieces().size() == 1 and int(gs.current_feeding["segments_left"]) == seg0 - 1, "藏一段：藏肉 1 段、殘骸少一段")
	_check(gs.action_cache_segment() and gs.cache_pieces().size() == 2, "再藏一段：2 段")
	# 2. 滿了
	_check(gs.cache_status() == "full" and not gs.action_cache_segment(), "兩段都新鮮：不能再藏")
	var fresh: float = gs.cache_fresh_days()
	var today: int = _today()
	gs.cache_pieces()[0]["day"] = today - int(fresh) - 1
	_check(gs.cache_status() == "replace", "有一段過了新鮮期：可以換")
	var left0: int = int(gs.current_feeding["segments_left"])
	_check(gs.action_cache_segment() and gs.cache_pieces().size() == 2 and gs.cache_pieces().all(func(pc): return gs.piece_state(pc) == "fresh") \
		and int(gs.current_feeding["segments_left"]) == left0 - 1, "換掉最舊的那段：還是 2 段、都新鮮")
	_check(not gs.can_eat_cache(), "正在吃殘骸時不能吃藏肉")
	gs.leave_feeding()
	# 3. 各自新鮮度：一段新鮮、一段過期 → 先吃新鮮的；只壞一段時只少那一段
	today = _today()
	fresh = gs.cache_fresh_days()
	gs.caches = {region: {"pieces": [_piece(today - int(fresh) - 1, 30.0), _piece(today, 40.0)]}}
	_check(gs.piece_state(gs.cache_pieces()[0]) == "stale" and gs.piece_state(gs.cache_pieces()[1]) == "fresh", "兩段各自的新鮮度")
	gs.wolf.hunger = 20.0
	var r: Dictionary = gs.action_eat_cache()
	# 剩下的只會是比較舊的那段（挖的這一回合剛好換季、新鮮期變短時，牠可能已經壞掉被拿掉）
	_check(not r.is_empty() and float(r["gain"]) == 40.0 and not bool(r["stale"]) and not gs.cache_pieces().any(func(pc): return float(pc["value"]) == 40.0) \
		and not gs.is_feeding(), "先吃比較新鮮的那段（飽食度照那段）")
	gs.caches = {region: {"pieces": [_piece(today - int(fresh * 2.0) - 2, 30.0), _piece(today, 40.0)]}}
	gs._update_caches()
	_check(gs.cache_pieces().size() == 1 and int(gs.cache_here().get("rotten_seen", 0)) == 1, "壞光的那段拿掉、記下")
	gs._cache_arrival_notice(region)
	_check(not gs.cache_here().has("rotten_seen") and gs.cache_pieces().size() == 1, "回來才說有一段壞了，新鮮的還在")
	# 4. 吃壞肚子：剛過新鮮期 vs 快壞光
	var sick := [0, 0]
	for k in 2:
		for i in 200:
			gs.wolf.poison_days_remaining = 0
			gs.wolf.hunger = 60.0
			gs.wolf.health = gs.wolf.health_max
			today = _today()
			fresh = gs.cache_fresh_days()
			gs.caches = {region: {"pieces": [_piece(today - int(fresh) - 1 - (0 if k == 0 else int(fresh * 0.6)), 10.0)]}}
			var er: Dictionary = gs.action_eat_cache()
			if bool(er.get("sick", false)) and gs.wolf.poison_days_remaining > 0:
				sick[k] += 1
	_check(sick[0] > 10 and sick[1] > sick[0], "過了新鮮期會吃壞肚子，越久越容易（%d → %d／200）" % sick)
	# 已經壞光但還沒到每天的檢查：動手挖時才發現
	today = _today()
	fresh = gs.cache_fresh_days()
	gs.caches = {region: {"pieces": [_piece(today - int(fresh * 2.0) - 2, 10.0)]}}
	_check(gs.action_eat_cache().is_empty() and gs.caches.is_empty(), "壞光的藏肉：動手挖時發現、不能吃")
	# 5. 被挖走、燒掉
	var lost := 0
	for i in 400:
		gs.caches = {region: {"pieces": [_piece(_today(), 10.0)]}}
		gs._update_caches()
		if str(gs.caches[region].get("lost", "")) in ["grizzly", "fox", "wolverine"]:
			lost += 1
	print("  一天被挖走：%d／400" % lost)
	_check(lost > 0, "會被挖走")
	gs.caches = {region: {"pieces": [_piece(_today(), 10.0)], "lost": "grizzly"}}
	_check(not gs.can_eat_cache(), "被挖走的不能吃")
	gs.start_feeding("elk", "adult", "clearing")
	_check(gs.action_cache_segment() and gs.cache_pieces().size() == 1 and str(gs.cache_here().get("lost", "")) == "", "動手藏時發現被挖走，清掉後藏新的")
	gs.leave_feeding()
	gs.fire = {"regions": {region: 1}}
	gs._update_caches()
	_check(str(gs.cache_here().get("lost", "")) == "fire", "大火燒過：藏的肉燒掉")
	gs.fire = {}
	gs._cache_arrival_notice(region)
	_check(gs.caches.is_empty(), "回來才知道燒掉了")
	# 6. 存檔、讀檔
	gs.caches = {region: {"pieces": [_piece(3, 12.5), _piece(4, 20.0)]}}
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.caches = {}
	gs.load_from_dict(d)
	_check(gs.cache_pieces(region).size() == 2, "存檔、讀檔保留藏肉")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _today() -> int:
	return int(gs.life_log.get("days_lived", 1))

func _piece(day: int, value: float) -> Dictionary:
	return {"day": day, "value": value, "animal_id": "elk", "life_stage": "adult"}

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
