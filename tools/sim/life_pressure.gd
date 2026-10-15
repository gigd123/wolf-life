extends SceneTree
# 一生的生存壓力（2026-10-15 試玩紀錄分析第 1 項：後半生幾乎沒有壓力）：
# 自動玩家（什麼都獵、平均打法）從各地圖的巢穴玩 RUNS 隻狼到死，每天結束時記飽食度，統計
#   - 各生命階段每年的挨餓天數（飽食度 < HUNGRY，預設 30）、吃不飽天數（< 60）
#   - 荒年（嚴冬、乾旱的夏天、雪兔低谷）與平常年的挨餓天數
#   - 各階段的狩獵成功率、每年獵到的大／中／小型獵物
#   - 死因與壽命
# 通過標準（使用者 2026-10-15 同意的初始值）：成年每年挨餓 2～5 天、荒年 ≥ 10 天、老年每年 ≥ 5 天、
# 餓死約 15～30%、平均壽命 9～11 歲。
# 用法：bash tools/run_sim.sh life_pressure 0 40（約數分鐘）

const STAGES := ["subadult", "adult", "elder"]
const DENS := ["forest_east", "tundra_south", "mountain_canyon", "grassland_riverwoods"]

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	var GT = root.get_node("GameTime")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs := _env_int("RUNS", 40)
	var hungry_at := float(_env_int("HUNGRY", 30))
	var days := {}; var hungry := {}; var underfed := {}
	var tries := {}; var wins := {}; var kills := {}
	for s in STAGES:
		days[s] = 0; hungry[s] = 0; underfed[s] = 0; tries[s] = 0; wins[s] = 0
		kills[s] = {"large": 0, "medium": 0, "small": 0}
	var year_days := {"lean": 0, "normal": 0}; var year_hungry := {"lean": 0, "normal": 0}
	var elder_lean := [0, 0] # 老年荒年：天數、挨餓天數
	var deaths := {}; var ages: Array = []
	for r in runs:
		var ap = AP.new("all", "average")
		ap.start(DENS[r % DENS.size()])
		var guard := 0
		while not ap.done() and guard < 2000:
			guard += 1
			var stage: String = STAGES[GS.wolf.life_stage()]
			var t0 := int(GS.life_log.get("hunt_attempts", 0)); var w0 := int(GS.life_log.get("hunt_successes", 0))
			var prey0: Dictionary = GS.life_log.get("prey_count", {}).duplicate()
			ap.step(1)
			tries[stage] += int(GS.life_log.get("hunt_attempts", 0)) - t0
			wins[stage] += int(GS.life_log.get("hunt_successes", 0)) - w0
			for k in GS.life_log.get("prey_count", {}).keys():
				var n: int = int(GS.life_log["prey_count"][k]) - int(prey0.get(k, 0))
				if n > 0:
					var size: String = str(root.get_node("GameData").animals.get(k, {}).get("size", "small"))
					kills[stage][size] = int(kills[stage].get(size, 0)) + n
			if not GS.wolf.alive:
				break
			days[stage] += 1
			var h: float = GS.wolf.hunger
			var y: Dictionary = GS.year_state()
			var season: String = GT.current_season()
			var lean: bool = (season == "winter" and str(y.get("winter", "")) == "severe") \
				or (season == "summer" and str(y.get("summer", "")) == "dry") or GS.hare_mult(false) <= 0.3
			var yk: String = "lean" if lean else "normal"
			year_days[yk] += 1
			if h < hungry_at:
				hungry[stage] += 1
				year_hungry[yk] += 1
			if h < 60.0:
				underfed[stage] += 1
			if stage == "elder" and lean:
				elder_lean[0] += 1
				if h < hungry_at:
					elder_lean[1] += 1
		ap.finish()
		deaths[GS.wolf.death_cause] = int(deaths.get(GS.wolf.death_cause, 0)) + 1
		ages.append(GS.wolf.age_years)
	var dpy: float = 4.0 * float(GT._season_day_count()) # 一年幾天
	print("== life_pressure：%d 隻狼（什麼都獵、平均打法，四張地圖輪流），挨餓 = 飽食度 < %d，一年約 %d 天" % [runs, hungry_at, dpy])
	for s in STAGES:
		var yrs: float = max(0.01, days[s] / dpy)
		var k: Dictionary = kills[s]
		print("  %-8s %5.1f 狼年：每年挨餓 %4.1f 天、吃不飽(<60) %5.1f 天；狩獵成功 %3d%%；每年獵到 大 %4.1f 中 %4.1f 小 %4.1f" % [
			s, yrs, hungry[s] / yrs, underfed[s] / yrs, roundi(100.0 * wins[s] / max(1, tries[s])),
			k["large"] / yrs, k["medium"] / yrs, k["small"] / yrs])
	for yk in ["normal", "lean"]:
		print("  %-6s年：每年挨餓 %4.1f 天（共 %d 天）" % [yk, year_hungry[yk] / max(0.01, year_days[yk] / dpy), year_days[yk]])
	print("  老年的荒年：每年挨餓 %4.1f 天（共 %d 天）" % [elder_lean[1] / max(0.01, elder_lean[0] / dpy), elder_lean[0]])
	ages.sort()
	var total := 0.0
	for a in ages: total += a
	print("  壽命：平均 %.1f、中位數 %.1f、最短 %.1f、最長 %.1f" % [total / ages.size(), ages[ages.size() / 2], ages[0], ages.back()])
	print("  死因：", deaths)
	quit()
	return true
