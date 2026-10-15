extends SceneTree
# 睡覺遇灰熊的頻率（2026-10-15 試玩回報 24）：在灰熊出沒的區域與季節，各種睡處各睡 RUNS 晚，
# 統計被驚醒（灰熊、母熊）與「灰熊路過」的次數。只呼叫 GameState，不改規則。
# 用法：bash tools/run_sim.sh sleep_bear 0 2000
var f := 0
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 1000
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	print("== 睡覺遇灰熊（每種睡處 %d 晚；巢穴在 forest_south（灰熊權重 2），其他睡處在 forest_west（權重 7）；夏季、成年狼、沒有傾向）" % runs)
	for quality in ["den", "good", "normal", "rough"]:
		gs.new_game("forest_south")
		gs.debug_force_transition("adult")
		var woken := 0
		var passing := 0
		for i in runs:
			gt.season_index = 1
			gt.day = 2
			gs.current_region = "forest_south" if quality == "den" else "forest_west"
			gs.found_sleep_spots.erase("forest_west")
			var k: Dictionary = gs.region_knowledge.get("forest_west", {"visited": true, "features": []})
			k["features"].erase("good_sleep_spot")
			if quality == "good":
				k["features"].append("good_sleep_spot")
			gs.region_knowledge["forest_west"] = k
			if quality == "normal":
				gs.found_sleep_spots["forest_west"] = "normal"
			if gs.current_region == "forest_south":
				gs.den_region = "forest_south"
			gs.pending_events.clear()
			gs.wolf.health = gs.wolf.health_max
			gs.wolf.hunger = 80
			var res: Dictionary = gs.action_sleep()
			if res.get("interrupted", false):
				woken += 1
			for e in gs.pending_events:
				if str(e.get("type", "")) == "bear_passing":
					passing += 1
		print("%-6s 被驚醒 %5.1f%%  灰熊路過 %5.1f%%  合計 %5.1f%%（約每 %.1f 晚一次）" % [quality, 100.0 * woken / runs, 100.0 * passing / runs,
			100.0 * (woken + passing) / runs, float(runs) / max(1, woken + passing)])
	return true
