extends SceneTree
# 狩獵難度（2026-10-17，使用者試玩 WolfQuest 後覺得狩獵偏簡單）：自動玩家玩 RUNS 隻狼到死（四張地圖輪流），統計
#   - 各生命階段、每種獵物（含幼體）的試獵次數、成功率、放棄率（life_log.hunt_by_animal）
#   - 各階段吃到的飽食度來自哪裡（自己獵的大／中／小型、殘骸、別人吃剩的、採集、搶來的；life_log.food_by）
#   - 打法 all（什麼都獵）與 small_only（只吃小獵物）的對照：每年挨餓天數、壽命、死因
# 用法：bash tools/run_sim.sh hunt_difficulty 0 30（RUNS 預設 30；約數分鐘）
const STAGES := ["subadult", "adult", "elder"]
const DENS := ["forest_east", "tundra_south", "mountain_canyon", "grassland_riverwoods"]
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 30
	for prey in ["all", "small_only"]:
		_run(prey, runs)
	return true

func _size(animal: String) -> String:
	return str(root.get_node("GameData").animals.get(animal, {}).get("size", "small"))

func _run(prey: String, runs: int) -> void:
	var GS = root.get_node("GameState")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var hunts := {}   # stage -> key -> [試, 成, 放棄]
	var conds := {}   # "stage.tier" -> condition -> [試, 成, 放棄]；tier 依當下 (速度+力量+技巧)/3：一般 < 80 ≤ 強
	var food := {}    # stage -> 來源類別 -> 飽食度
	var days := {}; var hungry := {}
	for s in STAGES:
		hunts[s] = {}; food[s] = {}; days[s] = 0; hungry[s] = 0
	var deaths := {}; var ages: Array = []
	for r in runs:
		var ap = AP.new(prey, "average")
		ap.start(DENS[r % DENS.size()])
		var guard := 0
		while not ap.done() and guard < 2000:
			guard += 1
			var stage: String = STAGES[GS.wolf.life_stage()]
			var h0: Dictionary = (GS.life_log.get("hunt_by_animal", {}) as Dictionary).duplicate(true)
			var f0: Dictionary = (GS.life_log.get("food_by", {}) as Dictionary).duplicate()
			var c0: Dictionary = (GS.life_log.get("hunt_by_condition", {}) as Dictionary).duplicate(true)
			var avg_stat: float = (GS.wolf.speed + GS.wolf.strength + GS.wolf.skill) / 3.0
			var ck: String = stage + ("." + ("strong" if avg_stat >= 80.0 else "average") if stage != "subadult" else "")
			ap.step(1)
			var h1: Dictionary = GS.life_log.get("hunt_by_animal", {})
			for k in h1.keys():
				var a: Array = h1[k]; var b: Array = h0.get(k, [0, 0, 0])
				var row: Array = hunts[stage].get(k, [0, 0, 0])
				for i in 3:
					row[i] = int(row[i]) + int(a[i]) - int(b[i])
				hunts[stage][k] = row
			var c1: Dictionary = GS.life_log.get("hunt_by_condition", {})
			for k in c1.keys():
				var a2: Array = c1[k]; var b2: Array = c0.get(k, [0, 0, 0])
				if not conds.has(ck):
					conds[ck] = {}
				var row2: Array = conds[ck].get(k, [0, 0, 0])
				for i in 3:
					row2[i] = int(row2[i]) + int(a2[i]) - int(b2[i])
				conds[ck][k] = row2
			var f1: Dictionary = GS.life_log.get("food_by", {})
			for k in f1.keys():
				var d: float = float(f1[k]) - float(f0.get(k, 0.0))
				if d <= 0.0:
					continue
				var cat: String = str(k)
				if cat.contains(":"):
					var parts: PackedStringArray = cat.split(":")
					cat = parts[0] + "_" + _size(parts[1]) if parts[0] in ["kill", "carcass"] else parts[0]
				food[stage][cat] = float(food[stage].get(cat, 0.0)) + d
			if not GS.wolf.alive:
				break
			days[stage] += 1
			if GS.wolf.hunger < 30.0:
				hungry[stage] += 1
		ages.append(GS.wolf.age_years)
		var c: String = str(GS.wolf.death_cause)
		deaths[c] = int(deaths.get(c, 0)) + 1
		ap.finish()
	var year_days: float = 4.0 * float(root.get_node("GameData").balance.get("season_day_count", {}).get("normal", 10))
	ages.sort()
	var avg := 0.0
	for a in ages:
		avg += a
	var ckeys: Array = conds.keys()
	ckeys.sort()
	for ck in ckeys:
		var parts2: Array = []
		for cond in ["healthy", "average", "weak"]:
			var r2: Array = conds[ck].get(cond, [0, 0, 0])
			parts2.append("%s 試 %d 次 成 %d%%（出手後 %d%%）" % [{"healthy": "健康", "average": "普通", "weak": "虛弱"}[cond], int(r2[0]),
				roundi(100.0 * int(r2[1]) / max(1, int(r2[0]))), roundi(100.0 * int(r2[1]) / max(1, int(r2[0]) - int(r2[2])))])
		print("   體況 %-16s %s" % [ck, "；".join(parts2)])
	print("\n== 打法 %s：%d 隻狼；壽命平均 %.1f、中位數 %.1f；死因 %s" % [prey, runs, avg / max(1, ages.size()), ages[ages.size() / 2], deaths])
	for s in STAGES:
		if days[s] == 0:
			continue
		var yrs: float = days[s] / year_days
		print("-- %s（%.0f 狼年）：每年挨餓 %.1f 天" % [s, yrs, hungry[s] / max(0.01, yrs)])
		# 依體型合計
		var by_size := {}
		for k in hunts[s].keys():
			var sz: String = _size(str(k).split(".")[0])
			var row: Array = by_size.get(sz, [0, 0, 0])
			for i in 3:
				row[i] = int(row[i]) + int(hunts[s][k][i])
			by_size[sz] = row
		for sz in ["large", "medium", "small"]:
			if by_size.has(sz):
				var r: Array = by_size[sz]
				print("   %-6s 每年試 %5.1f 次、成功 %3d%%、放棄 %3d%%" % [sz, int(r[0]) / max(0.01, yrs), roundi(100.0 * int(r[1]) / max(1, int(r[0]))), roundi(100.0 * int(r[2]) / max(1, int(r[0])))])
		var keys: Array = hunts[s].keys()
		keys.sort_custom(func(a, b): return int(hunts[s][a][0]) > int(hunts[s][b][0]))
		var parts: Array = []
		for k in keys.slice(0, 10):
			var r: Array = hunts[s][k]
			parts.append("%s %d次 %d%%" % [k, int(r[0]), roundi(100.0 * int(r[1]) / max(1, int(r[0])))])
		print("   最常試的：" + "；".join(parts))
		var total := 0.0
		for v in food[s].values():
			total += float(v)
		var fparts: Array = []
		var fk: Array = food[s].keys()
		fk.sort_custom(func(a, b): return float(food[s][a]) > float(food[s][b]))
		for k in fk:
			fparts.append("%s %d%%" % [k, roundi(100.0 * float(food[s][k]) / max(1.0, total))])
		print("   食物來源（每年 %.0f 飽食度）：%s" % [total / max(0.01, yrs), "、".join(fparts)])
