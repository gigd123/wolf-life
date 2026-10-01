extends SceneTree
# 探索分布（SPEC「探索系統」）：在三個區域各探索 1000 次，印出發現種類（線索／特徵／什麼都沒有）、
# 來源、獵物線索類型、新鮮與可追蹤的比例，以及次要特徵是否會被發現。
# 「什麼都沒發現」應該不超過 15%。
# 用法：bash tools/run_sim.sh explore_distribution

func _process(_d):
	var GS = root.get_node("GameState"); var GT = root.get_node("GameTime")
	for region in ["forest_east", "forest_south", "forest_west"]:
		GS.new_game(region)
		var kinds := {}; var sources := {}; var clues := {}; var fresh := 0; var preyclues := 0; var trackable := 0
		var samples := []
		var n := 1000
		for i in n:
			GS.wolf.hunger = 80; GS.wolf.health = 100
			var d = GS.action_explore()
			kinds[d["kind"]] = kinds.get(d["kind"], 0) + 1
			if d["kind"] == "clue":
				sources[d["source"]] = sources.get(d["source"], 0) + 1
				if d["source_kind"] == "prey":
					preyclues += 1
					clues[d["clue"]] = clues.get(d["clue"], 0) + 1
					if d["fresh"]: fresh += 1
					if d["clue"] != "sight" and (d["fresh"] or not d["fresh_known"]): trackable += 1
			if samples.size() < 6 and (samples.size() == 0 or randf() < 0.1):
				samples.append(d)
			GS.clear_discovery()
		print("== ", region, " kinds ", kinds)
		print("   sources ", sources)
		print("   prey clue types ", clues, " fresh %.0f%% trackable %.0f%%" % [100.0 * fresh / preyclues, 100.0 * trackable / preyclues])
		print("   features known ", GS.region_knowledge)
	quit(); return true
