extends SceneTree
# 灰熊藏的獵物（2026-11-04，使用者選 B，提案 docs/proposals/grizzly-cache.md）的回歸測試：
#   1. 出現：春天灰熊多的區域會有、冬天沒有、牧場沒有
#   2. 跡象大約四分之三照實際
#   3. 觀察：花一個時段、感知越高越準
#   4. 熊在時偷吃：牠一定衝出來，約 30% 先挨一下（不會被這一下打死）
#   5. 熊不在時偷吃：開始吃（少一段），吃的時候牠可能回來（grizzly_return，不先挨打）
#   6. 自動玩家遇到時不會卡住
# 用法：bash tools/run_sim.sh grizzly_cache_rules
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

func _count(region: String, season: int, n: int) -> int:
	gs.new_game(region)
	gt.season_index = season
	var c := 0
	for i in n:
		gs.clear_discovery()
		if gs._maybe_grizzly_cache():
			c += 1
	gs.clear_discovery()
	return c

func _run() -> void:
	var cfg: Dictionary = root.get_node("GameData").balance["grizzly_cache"]
	# 1
	var spring: int = _count("forest_east", 0, 4000)
	var winter: int = _count("forest_east", 3, 2000)
	_check(spring > 100 and spring < 300 and winter == 0, "春天森林東部 %d／4000（約 5%%）、冬天 %d" % [spring, winter])
	# 2、4、5
	var truth := 0
	var present := 0
	var hits := 0
	var hit_ok := true
	var feeding_ok := true
	var n := 600
	for i in n:
		gs.new_game("forest_east")
		gt.season_index = 0
		gs.wolf.health = gs.wolf.health_max
		gs.debug_grizzly_cache()
		var d: Dictionary = gs.current_discovery
		var p: bool = bool(d["present"])
		if p == str(d["sign"]).begins_with("present"):
			truth += 1
		var before: float = gs.wolf.health
		var r: Dictionary = gs.eat_grizzly_cache()
		if bool(r["charge"]) != p:
			hit_ok = false
		if p:
			present += 1
			if float(r["damage"]) > 0.0:
				hits += 1
				if gs.wolf.health >= before or not gs.wolf.alive:
					hit_ok = false
		elif float(r["damage"]) > 0.0 or not gs.is_feeding() or not bool(gs.current_feeding.get("grizzly_cache", false)):
			feeding_ok = false
		gs.leave_feeding() if gs.is_feeding() else null
	_check(abs(float(truth) / n - 0.75) < 0.07, "跡象照實際 %d／%d" % [truth, n])
	_check(abs(float(present) / n - 0.5) < 0.08, "春天熊還在附近 %d／%d（約一半）" % [present, n])
	_check(hit_ok and abs(float(hits) / max(1, present) - 0.3) < 0.08, "熊在：一定衝出來，先挨一下 %d／%d（約 30%%），不會被這一下打死" % [hits, present])
	_check(feeding_ok, "熊不在：開始吃，不先挨打")
	# 5 回來
	cfg["return_chance"] = 1.0
	var returned := false
	for i in 30:
		gs.new_game("forest_east")
		gt.season_index = 0
		gs.debug_grizzly_cache()
		gs.current_discovery["present"] = false
		gs.eat_grizzly_cache()
		if gs.is_feeding() and int(gs.current_feeding.get("segments_left", 0)) > 1:
			var fr: Dictionary = gs.feed_once()
			if str(fr.get("event", "")) == "grizzly_return":
				returned = true
				break
	_check(returned, "熊不在時吃到一半，牠會回來（grizzly_return）")
	cfg["return_chance"] = 0.2
	# 3
	var acc := {}
	for per in [35.0, 80.0]:
		var right := 0
		for i in 400:
			gs.new_game("forest_east")
			gt.season_index = 0
			gs.wolf.perception = per
			gs.debug_grizzly_cache()
			var p: bool = bool(gs.current_discovery["present"])
			var t0: int = gt.period_index * 4 + gt.turn_in_period + gt.day * 100
			var seen: String = gs.grizzly_cache_observe()
			if (seen == "present") == p:
				right += 1
			if i == 0:
				var t1: int = gt.period_index * 4 + gt.turn_in_period + gt.day * 100
				_check(t1 != t0, "觀察花時間")
		acc[per] = right / 400.0
	_check(acc[80.0] > acc[35.0] + 0.15, "感知越高越準（感知 35：%.0f%%、80：%.0f%%）" % [acc[35.0] * 100.0, acc[80.0] * 100.0])
	# 6
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var ok := true
	var seen := 0
	cfg["cache_chance"] = 100.0
	for style in ["average", "cautious", "assault"]:
		for i in 10:
			gs.new_game("forest_east")
			gt.season_index = 0
			gs.wolf.hunger = 20.0
			var ap = AP.new("all", style)
			ap._explore_once()
			if str(gs.current_discovery.get("kind", "")) == "grizzly_cache":
				ok = false
			seen += int(gs.life_log.get("grizzly_caches_found", 0))
	cfg["cache_chance"] = 0.05
	ok = ok and seen > 0
	_check(ok, "自動玩家處理完不會留著這個發現（遇到 %d 次）" % seen)
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
