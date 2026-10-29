extends SceneTree
# 牧場自己的探索結果（2026-10-29 QA 第五項）：
#   1. 各區、各時段探索的結果分布：牲畜線索、有人看著、人類痕跡、牧場的空手句子、一般空手、小撲、其他
#   2. 白天「有人看著」比夜裡多；注意高時更多
#   3. 牧場的空手句子都有文字（沒有原始翻譯鍵）；冬季屋舍寫羊在棚裡過冬
# 用法：bash tools/run_sim.sh ranch_explore
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

func _explore(region: String, season: String, period: String, n: int, attention: float, game) -> Dictionary:
	var out := {}
	for i in n:
		gt.season_index = gt.SEASONS.find(season)
		gt.period_index = gt.PERIODS.find(period)
		gt.turn_in_period = 0
		gs.ranch["attention"] = attention
		gs.current_region = region
		gs.wolf.stamina = 90.0
		gs.wolf.hunger = 90.0
		gs.action_explore()
		var d: Dictionary = gs.current_discovery
		var k: String = str(d.get("kind", ""))
		if d.has("ranch_guarded"):
			k = "有人看著"
		elif d.has("ranch_sign"):
			k = "人類痕跡"
		elif d.has("ranch_empty"):
			k = "牧場空手"
			if game != null:
				var txt: String = game._discovery_text(d)
				if txt.contains("ranch.") or txt.contains("{"):
					out["raw"] = int(out.get("raw", 0)) + 1
				if str(d["ranch_empty"]) == "yard_winter" and not txt.contains("過冬"):
					out["bad_winter"] = int(out.get("bad_winter", 0)) + 1
		elif k == "clue" and str(d.get("source", "")) in ["cattle", "sheep"]:
			k = "牲畜線索"
		elif k == "nothing":
			k = "一般空手"
		out[k] = int(out.get(k, 0)) + 1
		gs.clear_discovery()
		gs.pending_events.clear()
	return out

func _run() -> void:
	gs.new_game("grassland_plains")
	gs.wolf.age_years = 3.0
	gs.debug_ranch("open")
	gs.pending_events.clear()
	change_scene_to_file("res://scenes/Game.tscn")
	await _wait(6)
	var game = current_scene
	game.text_watch_timer = 0.0
	var n := 300
	print("== 牧場探索的結果（每格 %d 次，注意 0）" % n)
	var guarded := {}
	for region in ["ranch_pasture", "ranch_yard", "ranch_edge"]:
		for season in ["summer", "winter"]:
			for period in ["day", "dusk", "night"]:
				var r: Dictionary = _explore(region, season, period, n, 0.0, game)
				var ks: Array = r.keys().filter(func(k): return not str(k) in ["raw", "bad_winter"])
				ks.sort()
				var parts: Array = []
				for k in ks:
					parts.append("%s %d%%" % [k, roundi(100.0 * int(r[k]) / n)])
				print("  %-14s %-6s %-5s %s" % [region, season, period, "、".join(parts)])
				guarded[region + "." + season + "." + period] = int(r.get("有人看著", 0))
				if int(r.get("raw", 0)) > 0 or int(r.get("bad_winter", 0)) > 0:
					fails += 1
					print("    ✗ 空手句子有問題：", r)
	_check(guarded["ranch_pasture.summer.day"] > guarded["ranch_pasture.summer.night"] * 2, "白天有人看著比夜裡多（放牧地夏季 白天 %d、夜裡 %d）" % [guarded["ranch_pasture.summer.day"], guarded["ranch_pasture.summer.night"]])
	var hi: Dictionary = _explore("ranch_pasture", "summer", "day", n, 80.0, null)
	_check(int(hi.get("有人看著", 0)) > guarded["ranch_pasture.summer.day"], "注意高時有人看著更多（%d → %d）" % [guarded["ranch_pasture.summer.day"], int(hi.get("有人看著", 0))])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()
