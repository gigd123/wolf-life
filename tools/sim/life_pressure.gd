extends SceneTree
# 一生的生存壓力（2026-10-15 試玩紀錄分析第 1 項：後半生幾乎沒有壓力）：
# 自動玩家（什麼都獵、平均打法）從各地圖的巢穴玩 RUNS 隻狼到死，每天結束時記飽食度，統計
#   - 各生命階段每年的挨餓天數（飽食度 < HUNGRY，預設 30）、吃不飽天數（< 60）
#   - 荒年（暖冬、夏末到秋天、雪兔低谷）與平常年的挨餓天數
#   - 各階段的狩獵成功率、每年獵到的大／中／小型獵物
#   - 死因與壽命
# 通過標準（使用者 2026-10-15 同意的初始值）：成年每年挨餓 2～5 天、荒年 ≥ 10 天、老年每年 ≥ 5 天、
# 餓死約 15～30%、平均壽命 9～11 歲。
# 另外在 2、3、4 歲時，拿那時的狼和那時的黑狼（各複製一份）單挑 DUELS 場（一直撲咬、瀕危就撤退、牠示弱就放牠走），
# 看「正常成長到 2～4 歲打贏黑狼六到八成」（使用者 2026-10-15）有沒有守住。
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
	var duel_ages := [2.0, 3.0, 4.0]
	var duel := {} # 年齡 -> [場數, 贏]
	var stat_sum := {}
	for a in duel_ages:
		duel[a] = [0, 0]
		stat_sum[a] = {}
	var duels := _env_int("DUELS", 30)
	for r in runs:
		var ap = AP.new("all", "average")
		ap.start(DENS[r % DENS.size()])
		var guard := 0
		var dueled := {}
		while not ap.done() and guard < 2000:
			guard += 1
			for a in duel_ages:
				if not dueled.has(a) and GS.wolf.age_years >= a:
					dueled[a] = true
					var res: Array = _duel(GS, duels)
					duel[a][0] += res[0]; duel[a][1] += res[1]
					for st in ["strength", "skill", "speed", "health_max"]:
						stat_sum[a][st] = float(stat_sum[a].get(st, 0.0)) + float(GS.wolf.get(st))
					stat_sum[a]["n"] = int(stat_sum[a].get("n", 0)) + 1
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
			# 對狼的荒年：暖冬、夏末到秋天、雪兔低谷（GameState.lean_effects；嚴冬對狼有利，不算）
			var lean: bool = not GS.lean_effects()["kinds"].is_empty()
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
	for a in duel_ages:
		var sn: float = max(1, int(stat_sum[a].get("n", 0)))
		print("  %.0f 歲單挑黑狼：贏 %d%%（%d 場；黑狼已死的局不算）；這時平均 力量 %.0f 技巧 %.0f 速度 %.0f 血量上限 %.0f" % [a, roundi(100.0 * duel[a][1] / max(1, duel[a][0])), duel[a][0],
			float(stat_sum[a].get("strength", 0)) / sn, float(stat_sum[a].get("skill", 0)) / sn, float(stat_sum[a].get("speed", 0)) / sn, float(stat_sum[a].get("health_max", 0)) / sn])
	quit()
	return true

# 用這時候的狼和黑狼各複製一份單挑 n 場，回傳 [場數, 贏]。不動到正在玩的那隻狼與黑狼。
func _duel(GS, n: int) -> Array:
	var npc0 = GS.stranger()
	if npc0 == null or not npc0.alive:
		return [0, 0]
	var CombatScript = load("res://scripts/core/Combat.gd")
	var FR = load("res://scripts/core/FightRules.gd")
	var WolfScript = load("res://scripts/core/Wolf.gd")
	var NPC = load("res://scripts/core/NpcWolf.gd")
	var keep = GS.wolf
	var wd: Dictionary = keep.to_dict()
	var nd: Dictionary = npc0.to_dict()
	var won := 0
	for i in n:
		var w = WolfScript.from_dict(wd)
		w.health = w.health_max
		w.stamina = 100.0
		w.injury = 0
		GS.wolf = w
		var npc = NPC.from_dict(nd)
		npc.health = npc.health_max
		var c = CombatScript.new(w, "stranger_wolf", "adult", "meet", false)
		c.set_npc(npc)
		var g := 0
		while c.phase != 2 and g < 40:
			g += 1
			var ids: Array = c.options().map(func(o): return o["id"])
			var pick: String = "bite"
			if ids.has("let_go"):
				pick = "let_go"
			elif c.phase == 0:
				pick = "attack"
			elif FR.in_danger(w):
				pick = "submit" if ids.has("submit") else "retreat"
			c.choose(pick)
		if c.outcome in ["drove_off", "killed"]:
			won += 1
	GS.wolf = keep
	return [n, won]
