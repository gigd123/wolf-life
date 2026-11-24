extends SceneTree
# Phase 3c 第 4 步：用嚎叫找伴侶的模擬（SPEC Phase 3c「假設、驗證方式、通過標準」）。
# 自動玩家從 2 歲成年、秋季第 1 天開始（四張地圖的巢穴輪流），玩 SIM_DAYS 天（預設 80＝兩年）。
# 玩法 MATE：always 每個時段嚎、dusk 清晨與黃昏、sometimes 三天一次黃昏、never 不嚎（有一隻狼的聲音就循聲；合聲不跟）。
# 印：第一次遇上離群母狼（秋冬 20 天內、一年內）、遇上後一季內配對、嚎叫與循聲的次數、循聲到達後的結果、
#     撞上狼群（每年）、挨餓天數（飽食度 < 30 的日子，每年）。
# PART=risk：暴露的累積（howl_risk）——站在山地鄰群的領域核心、邊界、兩區外，每天嚎 0／1／2／5 次，SIM_DAYS 天，每天撞上幾次。
# 用法：MATE=always bash tools/run_sim.sh mate_howl_sim 0 100（第三個參數是隻數）；PART=risk bash tools/run_sim.sh mate_howl_sim
const DENS := ["forest_east", "tundra_south", "mountain_canyon", "grassland_riverwoods"]
var f := 0

func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var runs: int = int(_env("RUNS", "100"))
	if _env("PART", "") == "risk":
		_risk()
	else:
		_search(runs)
	quit()
	return true

func _search(runs: int) -> void:
	var GS = root.get_node("GameState")
	var GT = root.get_node("GameTime")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var policy := _env("MATE", "always")
	var days := int(_env("SIM_DAYS", "80"))
	var met20 := 0
	var met40 := 0
	var mated_season := 0
	var met_any := 0
	var met_day_sum := 0
	var howls := 0
	var follows := 0
	var pack_meets := 0
	var follow_res := {}
	var starve := 0
	var alive_days := 0
	for r in runs:
		var ap = AP.new("all", "average")
		ap.mate_search = policy
		ap.start(DENS[r % DENS.size()])
		GS.wolf.age_years = 2.0
		GS.debug_force_transition("adult")
		GT.season_index = 2
		GT.day = 1
		var start_day: int = GS._today()
		var last_day: int = start_day
		var guard := 0
		while not ap.done() and guard < 6000 and GS.wolf.alive and GS._today() - start_day < days:
			guard += 1
			ap.step(1)
			if GS._today() != last_day:
				last_day = GS._today()
				alive_days += 1
				if GS.wolf.hunger < 30.0:
					starve += 1
		ap.finish()
		howls += ap.howls
		follows += ap.follows
		var met := -1
		var mate := -1
		for e in GS.life_events():
			var t: String = str(e.get("type", ""))
			if t == "she_wolf.met" and met < 0:
				met = int(e["day"]) - start_day
			elif t == "mate" and mate < 0:
				mate = int(e["day"]) - start_day
		if met >= 0:
			met_any += 1
			met_day_sum += met
			if met < 20:
				met20 += 1
			if met < 40:
				met40 += 1
			if mate >= 0 and mate - met <= 10:
				mated_season += 1
		pack_meets += (GS.life_log.get("pack_meetings", []) as Array).size()
		var st: Dictionary = GS.life_log.get("stats", {}).get("howl_follow", {})
		for k in st:
			follow_res[k] = int(follow_res.get(k, 0)) + int(st[k])
	var years: float = maxf(0.01, float(alive_days) / 40.0)
	print("== mate_howl_sim：%s，%d 隻，每隻 %d 天（從 2 歲、秋季開始）" % [policy, runs, days])
	print("  遇上離群母狼：秋冬 20 天內 %d%%、一年內 %d%%、玩到結束 %d%%（平均第 %.1f 天）" % [roundi(100.0 * met20 / runs), roundi(100.0 * met40 / runs), roundi(100.0 * met_any / runs), float(met_day_sum) / maxi(1, met_any)])
	print("  遇上後一季內配對 %d%%（遇上的 %d 隻裡 %d 隻）" % [roundi(100.0 * mated_season / maxi(1, met_any)), met_any, mated_season])
	print("  每隻每年 嚎叫 %.0f 次、循聲 %.1f 次；循聲到達後 %s" % [howls / years, follows / years, str(follow_res)])
	print("  撞上狼群 每年 %.2f 次；挨餓 每年 %.1f 天" % [pack_meets / years, starve / years])

# 暴露的累積：站在一群的核心、邊界、兩區外，每天嚎 k 次（每個時段至多一次，從黃昏開始排），每天撞上幾次
func _risk() -> void:
	var GS = root.get_node("GameState")
	var GT = root.get_node("GameTime")
	var days := int(_env("SIM_DAYS", "200"))
	GS.new_game("mountain_canyon")
	GS.wolf.age_years = 3.0
	GS.debug_force_transition("adult")
	var p = GS.pack_by_id("mountain")
	if p == null or not GS.pack_is_active(p):
		print("山地的鄰群不在")
		return
	var core: String = str(p.regions[0])
	var border := ""
	var far := ""
	for r in root.get_node("GameData").maps().get("mountain", {}).get("layout", []):
		var st: int = GS._map_steps(core, str(r))
		if st == 1 and border == "":
			border = str(r)
		elif st >= 2:
			far = str(r)
	print("== howl_risk：山地鄰群（核心 %s、邊界 %s、兩區外 %s），每格 %d 天；每天撞上幾次" % [core, border, far, days])
	var order := ["dusk", "dawn", "night", "predawn", "day"]
	for place in [["核心", core], ["邊界", border], ["兩區外", far]]:
		if str(place[1]) == "":
			continue
		var line := "  %-4s" % place[0]
		for k in [0, 1, 2, 5]:
			GS.new_game("mountain_canyon")
			GS.wolf.age_years = 3.0
			GS.debug_force_transition("adult")
			var meets := 0
			for d in days:
				for per_i in GT.PERIODS.size():
					GS.current_region = str(place[1])
					GS.wolf.hunger = 100.0
					GS.wolf.stamina = 100.0
					GS.wolf.health = GS.wolf.health_max
					if order.slice(0, k).has(GT.current_period()):
						GS.action_howl()
					GS.events_today = 0
					GT.advance_turns(GT.TURNS_PER_PERIOD) # 換時段時照遊戲擲撞上狼群
					for e in GS.pending_events:
						if str(e.get("type", "")) in ["pack_meet", "stranger_confront"]:
							meets += 1
					GS.pending_events.clear()
			line += "  嚎 %d 次 %.2f" % [k, float(meets) / days]
		print(line)
