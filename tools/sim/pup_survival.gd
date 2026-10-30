extends SceneTree
# Phase 3 第 5 步「繁殖與育幼」的一生模擬（SPEC Phase 3 待確認「育幼的食物需求、幼狼的存活：目標第一年存活約一半；不預設要降低難度」）。
# 自動玩家住在巢穴附近（四張地圖輪流）、認真找伴侶（MATE=always），玩到 UNTIL 歲或死亡，統計：
#   1. 懷孕、生了幾窩、一窩幾隻；幼狼活到 1 歲的比例（還沒滿 1 歲就結束的不算）；死因
#   3. 狼群的大小、子女離群的年齡（第 6 步）
#   2. 育幼的負擔：叼回去、反芻的次數；幼狼挨餓的天數；有幼狼的春夏你自己的挨餓天數（對照沒有幼狼的成年）
# 用法：bash tools/run_sim.sh pup_survival 0 30；UNTIL=7
const DENS := ["forest_east", "tundra_south", "mountain_canyon", "grassland_riverwoods"]

func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	var GT = root.get_node("GameTime")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs := int(_env("RUNS", "20"))
	var until := float(_env("UNTIL", "7"))
	var litters := 0
	var born := 0
	var survived := 0
	var counted := 0
	var causes := {}
	var pregnant := 0
	var carried := 0
	var regurg := 0
	var care_days := 0
	var care_hungry := 0
	var other_days := 0
	var other_hungry := 0
	var pup_hungry_days := 0
	var size_sum := 0
	var size_days := 0
	var size_max := 0
	var left_ages: Array = []
	for r in runs:
		var ap = AP.new("all", "average")
		ap.mate_search = "always"
		ap.start(DENS[r % DENS.size()])
		var guard := 0
		while not ap.done() and guard < 4000 and GS.wolf.alive and GS.wolf.age_years < until:
			guard += 1
			ap.step(1)
			if GS.wolf.life_stage() == 0:
				continue
			if GS.has_mate():
				size_sum += GS.pack_counted_size()
				size_days += 1
				size_max = max(size_max, GS.pack_counted_size())
			if GS.pups_need_food():
				care_days += 1
				if GS.wolf.hunger < 30.0:
					care_hungry += 1
				if int(GS.breeding().get("hungry_days", 0)) > 0:
					pup_hungry_days += 1
			elif GT.current_season() in ["spring", "summer"]:
				other_days += 1
				if GS.wolf.hunger < 30.0:
					other_hungry += 1
		ap.finish()
		pregnant += GS.life_events("mate.pregnant").size()
		for e in GS.life_events("pups.born"):
			litters += 1
			born += int(e["n"])
			for id in e.get("ids", []):
				var n = GS.npcs.get(id, null)
				if n == null:
					continue
				if n.age_years >= 1.0:
					counted += 1
					survived += 1
				elif not n.alive:
					counted += 1
		for e in GS.life_events("pup.died"):
			var c: String = str(e.get("cause", ""))
			causes[c] = int(causes.get(c, 0)) + 1
		for dd in GS.life_log.get("dispersed", []):
			left_ages.append(float(dd["age"]))
		var st: Dictionary = GS.life_log.get("stats", {}).get("den", {})
		carried += int(st.get("carried", 0))
		regurg += int(st.get("regurgitated", 0))
	print("== pup_survival：%d 隻（認真找伴侶、住在巢穴附近，玩到 %.0f 歲）" % [runs, until])
	print("  懷孕 %d 次、生了 %d 窩、共 %d 隻（一窩平均 %.1f）" % [pregnant, litters, born, float(born) / max(1, litters)])
	print("  活到 1 歲：%d／%d（%d%%，目標約一半）；死因 %s" % [survived, counted, roundi(100.0 * survived / max(1, counted)), causes])
	print("  叼回去 %d 次、反芻 %d 次；幼狼挨餓的天數 %d（有幼狼要餵的天數 %d）" % [carried, regurg, pup_hungry_days, care_days])
	print("  你自己挨餓（飽食度 < 30）：有幼狼要餵的春夏 %d%% 的天、其他春夏 %d%% 的天" % [roundi(100.0 * care_hungry / max(1, care_days)), roundi(100.0 * other_hungry / max(1, other_days))])
	left_ages.sort()
	print("  狼群（第 6 步）：有伴侶時算進上限的平均 %.1f 隻、最多 %d；離群 %d 隻，離開時的年齡中位數 %.2f（%s）" % [float(size_sum) / max(1, size_days), size_max, left_ages.size(), left_ages[left_ages.size() / 2] if not left_ages.is_empty() else 0.0, str(left_ages.slice(0, 30))])
	quit()
	return true
