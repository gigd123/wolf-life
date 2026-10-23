extends SceneTree
# 牧場的配對比較（Phase 4a 第 5 步）：ranch_life 各組的狼不同，一生的挨餓差異被個體差異蓋過（同一組兩輪差 2～3 天）。
# 這裡讓同一隻狼在 OPEN_AGE 歲時牧場開放（候選照規則挑），存一份；之後同一份存檔、同一個種子分別用 POLICIES 的打法玩到死，
# 比較開放後的每年挨餓（成年、老年）、壽命、食物從哪裡來、牧場的事件。
# 用法：bash tools/run_sim.sh ranch_pair 0 24（RUNS 隻狼）；POLICIES=never,sometimes,often；OPEN_AGE=2.5；DENS_ONLY=forest_east；RANCH_SET='{...}' 覆寫 ranch.json

const DENS := ["forest_east", "grassland_riverwoods", "tundra_south", "mountain_canyon"]

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _food_total(fb: Dictionary, ranch_only: bool) -> float:
	var t := 0.0
	for k in fb.keys():
		var is_ranch: bool = str(k).ends_with(":cattle") or str(k).ends_with(":sheep")
		if not ranch_only or is_ranch:
			t += float(fb[k])
	return t

func _process(_d):
	var GS = root.get_node("GameState")
	var GT = root.get_node("GameTime")
	var GD = root.get_node("GameData")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs := _env_int("RUNS", 24)
	var policies: Array = Array(OS.get_environment("POLICIES").split(",")) if OS.get_environment("POLICIES") != "" else ["never", "sometimes", "often"]
	var dens: Array = Array(OS.get_environment("DENS_ONLY").split(",")) if OS.get_environment("DENS_ONLY") != "" else DENS
	var open_age: float = float(OS.get_environment("OPEN_AGE")) if OS.get_environment("OPEN_AGE") != "" else 2.5
	var dpy: float = 4.0 * float(GT._season_day_count())
	GD.ranch_def["enabled"] = false # 不自然出現；到 open_age 由這裡打開
	# RANCH_SET='{"attention": {...}}'：覆寫 ranch.json 的部分設定（字典逐層合併；校準用）
	if OS.get_environment("RANCH_SET") != "":
		_merge(GD.ranch_def, JSON.parse_string(OS.get_environment("RANCH_SET")))
	var agg := {} # 打法 -> 合計
	var by_den := {} # 巢穴 -> 打法 -> [成年天數, 成年挨餓]
	for pol in policies:
		agg[pol] = {"adult": [0, 0], "elder": [0, 0], "life": 0.0, "food": 0.0, "ranch_food": 0.0, "deaths": {}, "kills": 0, "patrols": 0, "hunts": 0, "shots": 0, "damage": 0.0}
	var used := 0
	for r in runs:
		var den: String = dens[r % dens.size()]
		var ap = AP.new("all", "average")
		ap.ranch_policy = "never"
		ap.start(den)
		var guard := 0
		while not ap.done() and GS.wolf.age_years < open_age and guard < 2000:
			guard += 1
			ap.step(1)
		ap.finish()
		if ap.done() or not GS.wolf.alive:
			continue
		GS.debug_ranch("open")
		var snap: String = JSON.stringify(GS.to_dict())
		var fb0: Dictionary = (GS.life_log.get("food_by", {}) as Dictionary).duplicate()
		var age0: float = GS.wolf.age_years
		used += 1
		var line := "  %-22s 候選 %s：" % [den, str(GS.ranch.get("candidate", ""))]
		for pol in policies:
			GS.load_from_dict(JSON.parse_string(snap))
			var a = AP.new("all", "average")
			a.ranch_policy = pol
			a.start_from_current()
			var life := {1: [0, 0], 2: [0, 0]}
			var g := 0
			while not a.done() and g < 2000:
				g += 1
				a.step(1)
				if not GS.wolf.alive:
					break
				var ls: int = GS.wolf.life_stage()
				if life.has(ls):
					life[ls][0] += 1
					if GS.wolf.hunger < 30.0:
						life[ls][1] += 1
			a.finish()
			var ag: Dictionary = agg[pol]
			for i in 2:
				ag["adult"][i] += life[1][i]
				ag["elder"][i] += life[2][i]
			ag["life"] += GS.wolf.age_years - age0
			var fb: Dictionary = GS.life_log.get("food_by", {})
			ag["food"] += _food_total(fb, false) - _food_total(fb0, false)
			ag["ranch_food"] += _food_total(fb, true) - _food_total(fb0, true)
			var cause: String = str(GS.wolf.death_cause)
			ag["deaths"][cause] = int(ag["deaths"].get(cause, 0)) + 1
			var rl: Dictionary = GS.life_log.get("ranch", {})
			for key in ["kills", "patrols", "hunts", "shots"]:
				ag[key] += int(rl.get(key, 0))
			ag["damage"] += float(rl.get("damage", 0.0))
			var bd: Dictionary = by_den.get_or_add(den, {})
			var dv: Array = bd.get_or_add(pol, [0, 0])
			dv[0] += life[1][0]
			dv[1] += life[1][1]
			line += " %s 成年挨餓 %.1f／年、活到 %.1f；" % [pol, life[1][1] / max(0.01, life[1][0] / dpy), GS.wolf.age_years]
		print(line)
	print("== ranch_pair：%d 隻狼在 %.1f 歲時牧場開放，同一份存檔分別玩（%s）" % [used, open_age, ",".join(policies)])
	for pol in policies:
		var ag: Dictionary = agg[pol]
		var yrs: float = max(0.01, ag["life"])
		print("  %-9s 每年挨餓 成年 %.1f、老年 %.1f 天；開放後平均再活 %.1f 年；每年吃到 %.0f（牧場 %.0f）；死因 %s；獵到家畜 %d、巡查 %d、追獵 %d、中槍 %d、傷 %.0f" % [pol,
			ag["adult"][1] / max(0.01, ag["adult"][0] / dpy), ag["elder"][1] / max(0.01, ag["elder"][0] / dpy), ag["life"] / max(1, used),
			ag["food"] / yrs, ag["ranch_food"] / yrs, ag["deaths"], ag["kills"], ag["patrols"], ag["hunts"], ag["shots"], ag["damage"]])
	for den in by_den.keys():
		var parts: Array = []
		for pol in policies:
			var dv: Array = by_den[den].get(pol, [0, 0])
			parts.append("%s %.1f" % [pol, dv[1] / max(0.01, dv[0] / dpy)])
		print("  %s 成年每年挨餓：%s" % [den, "、".join(parts)])
	quit()
	return true

func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		if dst.get(k) is Dictionary and src[k] is Dictionary:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]
