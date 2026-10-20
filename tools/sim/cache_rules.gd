extends SceneTree
# Phase 2e 第 1 步「藏食物」的回歸測試（SPEC「Phase 2e：藏食物」）：
#   1. 吃殘骸時可以叼一段去藏，一區最多 2 段；殘骸少一段
#   2. 新鮮、過了新鮮期、壞光（依新鮮期與 rot_mult）
#   3. 挖出來吃：同殘骸一段一段吃，不會引來搶食的動物
#   4. 過了新鮮期吃，有機會吃壞肚子，越久越容易
#   5. 每天有機會被挖走（灰熊多的區域比較高），回到那一區才知道
#   6. 存檔、讀檔
# 用法：bash tools/run_sim.sh cache_rules
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var rng = root.get_node("RNGService")
	rng.set_seed(42)
	gs.new_game("forest_east")
	gs.debug_force_transition("adult")
	# 1. 叼一段去藏
	gs.start_feeding("elk", "adult", "clearing")
	var seg0: int = int(gs.current_feeding["segments_left"])
	_check(gs.can_cache(), "吃殘骸時可以藏")
	_check(gs.action_cache_segment() and int(gs.cache_here()["segments"]) == 1 and int(gs.current_feeding["segments_left"]) == seg0 - 1, "藏一段：藏肉 1 段、殘骸少一段")
	_check(gs.action_cache_segment() and int(gs.cache_here()["segments"]) == 2, "再藏一段：2 段")
	_check(not gs.can_cache() and not gs.action_cache_segment(), "一區最多 2 段")
	_check(not gs.can_eat_cache(), "正在吃殘骸時不能吃藏肉")
	gs.leave_feeding()
	# 2. 新鮮度
	var c: Dictionary = gs.cache_here()
	var today: int = int(gs.life_log.get("days_lived", 1))
	var fresh: float = gs.cache_fresh_days()
	c["day"] = today
	_check(gs.cache_state(c) == "fresh", "剛藏：新鮮（新鮮期 %.0f 天）" % fresh)
	c["day"] = today - int(fresh) - 1
	_check(gs.cache_state(c) == "stale", "過了新鮮期：stale")
	c["day"] = today - int(fresh * 2.0) - 1
	_check(gs.cache_state(c) == "rotten" and gs.cache_days_left(c) == 0, "超過新鮮期兩倍：壞光")
	c["day"] = today
	# 3. 挖出來吃，不引來搶食的動物
	_check(gs.can_eat_cache(), "可以吃藏肉")
	var h0: float = gs.wolf.hunger
	gs.wolf.hunger = 20.0
	var r: Dictionary = gs.action_eat_cache()
	_check(not r.is_empty() and not bool(r["stale"]) and gs.is_feeding() and str(gs.current_feeding["src"]) == "cache" and int(gs.current_feeding["segments_left"]) == 2, "挖出來：進食 2 段")
	_check(gs.cache_here().is_empty(), "挖出來後這一區沒有藏肉了")
	var events := 0
	for i in 300:
		gs.current_feeding = {"animal_id": "elk", "life_stage": "adult", "segments_left": 5, "segment_value": 10.0, "turns_stayed": 0, "terrain": "clearing", "src": "cache", "no_scavenger": true}
		gs.wolf.hunger = 20.0
		var fr: Dictionary = gs.feed_once()
		if str(fr.get("event", "")) != "":
			events += 1
	_check(events == 0, "吃藏肉不會引來搶食（%d 次）" % events)
	gs.current_feeding = {}
	gs.wolf.hunger = h0
	# 4. 吃壞肚子：剛過新鮮期 vs 快壞光
	var sick := [0, 0]
	for k in 2:
		for i in 200:
			gs.wolf.poison_days_remaining = 0
			gs.wolf.hunger = 100.0
			gs.wolf.health = gs.wolf.health_max
			today = int(gs.life_log.get("days_lived", 1))
			fresh = gs.cache_fresh_days()
			gs.caches[gs.current_region] = {"segments": 1, "segment_value": 10.0, "animal_id": "elk", "life_stage": "adult",
				"day": today - int(fresh) - 1 - (0 if k == 0 else int(fresh * 0.6))}
			var er: Dictionary = gs.action_eat_cache()
			if bool(er.get("sick", false)) and gs.wolf.poison_days_remaining > 0:
				sick[k] += 1
			gs.current_feeding = {}
	_check(sick[0] > 10 and sick[1] > sick[0], "過了新鮮期會吃壞肚子，越久越容易（%d → %d／200）" % sick)
	# 已經壞光但還沒到每天的檢查：動手挖時才發現，不能吃
	today = int(gs.life_log.get("days_lived", 1))
	fresh = gs.cache_fresh_days()
	gs.caches[gs.current_region] = {"segments": 1, "segment_value": 10.0, "animal_id": "elk", "life_stage": "adult", "day": today - int(fresh * 2.0) - 2}
	_check(gs.action_eat_cache().is_empty() and gs.cache_here().is_empty() and not gs.is_feeding(), "壞光的藏肉：發現壞了、不能吃")
	# 5. 被挖走：灰熊多的區域（夏季權重 2）比較常；回到那一區才知道
	var lost := {}
	for region_id in ["forest_east", "forest_north"]:
		lost[region_id] = 0
		for i in 400:
			gs.caches = {region_id: {"segments": 1, "segment_value": 10.0, "animal_id": "elk", "life_stage": "adult", "day": int(gs.life_log.get("days_lived", 1))}}
			gs._update_caches()
			if str(gs.caches[region_id].get("lost", "")) in ["grizzly", "fox", "wolverine"]:
				lost[region_id] += 1
	print("  一天被挖走：", lost)
	_check(int(lost["forest_east"]) > 0, "會被挖走")
	gs.caches = {"forest_north": {"segments": 1, "segment_value": 10.0, "animal_id": "elk", "life_stage": "adult", "day": 1, "lost": "grizzly"}}
	_check(not gs.can_eat_cache(), "別區的藏肉不能在這裡吃")
	gs._cache_arrival_notice("forest_north")
	_check(gs.caches.is_empty(), "回到那一區才知道被挖走，清掉")
	# 6. 存檔、讀檔
	gs.caches = {"forest_east": {"segments": 2, "segment_value": 12.5, "animal_id": "elk", "life_stage": "adult", "day": 3}}
	var d = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.caches = {}
	gs.load_from_dict(d)
	_check(int(gs.caches.get("forest_east", {}).get("segments", 0)) == 2, "存檔、讀檔保留藏肉")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
