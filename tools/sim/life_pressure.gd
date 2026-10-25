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
# 用法：bash tools/run_sim.sh life_pressure 0 40（約數分鐘）；NO_TACTICAL=1 時鹿類都用選單式狩獵（對照 Phase 2b）；
# TACTICAL_ONLY=white_tailed_deer 時只有列出的動物走戰術地圖（對照 Phase 2c）；NO_CACHE=1 時不藏食物（對照 Phase 2e）；DENS_ONLY=forest_east 只從這些巢穴開始；NO_SALMON=1 沒有鮭魚洄流；SALMON_SET='{...}' 覆寫鮭魚的設定

const STAGES := ["subadult", "adult", "elder"]
const FOOD_CATS := ["大中型獵物", "小獵物", "殘骸撿食", "藏肉", "採集", "小撲", "猞猁的雪兔", "鮭魚", "其他"]

# 食物來源分類（Phase 2g 第 4 步）：kill:／carcass: 這類「來源:動物」依動物大小分；其他照名稱
func _food_cat(src: String) -> String:
	if src == "small_pounce":
		return "小撲"
	if src == "salmon":
		return "鮭魚"
	if src.begins_with("lynx"):
		return "猞猁的雪兔"
	if src.begins_with("cache:"):
		return "藏肉"
	if src == "gather":
		return "採集"
	if src in ["remains", "pack_remains"] or src.begins_with("bear_steal") or src.begins_with("winter") or src.begins_with("found"):
		return "殘骸撿食"
	if src.begins_with("carcass:"):
		return "殘骸撿食" # 不是自己獵到的屍體（凍死的、別人留下的）
	if src.contains(":"):
		var animal: String = src.get_slice(":", 1)
		return "小獵物" if str(root.get_node("GameData").animals.get(animal, {}).get("size", "small")) == "small" else "大中型獵物"
	return "其他"
const SNAP_AGES := [1.0, 1.5, 2.0, 3.0, 5.0]
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
	var season_days := {}; var season_hungry := {} # 各季的天數、挨餓天數（Phase 2e：冬季的挨餓要少一點但不歸零）
	var cache_log := {"caches_made": 0, "caches_eaten": 0, "caches_lost": 0}
	var elder_lean := [0, 0] # 老年荒年：天數、挨餓天數
	var deaths := {}; var ages: Array = []
	var starved: Array = [] # 餓死的年齡與巢穴（Phase 2f 第 4 步）
	var duel_ages := [2.0, 3.0, 4.0]
	var duel := {} # 年齡 -> [場數, 贏]
	var stat_sum := {}
	var snap := {} # 各年齡的平均能力值（Phase 2c 第 5 步：次成年 1～2 歲和成年比）
	for a in SNAP_AGES:
		snap[a] = {}
	for a in duel_ages:
		duel[a] = [0, 0]
		stat_sum[a] = {}
	var duels := _env_int("DUELS", 30)
	# 黑狼家族（Phase 3a）：你在這些年齡時，牠們是什麼階段、幾隻、佔幾區；各事件第一次發生時你幾歲
	var pack_ages := [2.0, 3.0, 4.0, 5.0, 6.0, 8.0]
	var pack_at := {} # 年齡 -> {stage: 次數, size: 總和, regions: 總和, n}
	for a in pack_ages:
		pack_at[a] = {"n": 0, "size": 0, "regions": 0}
	var first_event := {} # 事件 -> [你的年齡…]
	var event_count := {}
	var sub_days := {} # 次成年分成未滿 1 歲、1～2 歲：天數、挨餓天數
	var sub_hungry := {}
	var tac := {} # 戰術狩獵（Phase 2c）：階段.結果 -> 次數；階段 -> 扣的體力總和
	var tac_sp := {} # 物種.結果 -> 次數（Phase 2d）
	var entry := {} # 入口.年齡.n／ok／turns／hurt（Phase 2i 第 7 步）
	var tac_sps := {} # 物種.年齡.結果 -> 次數（2026-10-22：雪兔各年齡的捕捉率）
	var tac_spx := {} # 物種.stamina／物種.turns -> 總和
	var tac_st := {}
	var meet_count := {} # 撞上黑狼一家（第 3 步）：kind.outcome -> 次數
	var meet_lives := 0
	# 食物從哪裡來（Phase 2g 第 4 步）：年齡（young 未滿 1 歲、yearling 1～2 歲、life 一生）-> 類別 -> 飽食度總和
	var food := {"young": {}, "yearling": {}, "life": {}}
	var sp_log := {"tries": 0, "caught": 0, "young_tries": 0} # 小撲
	var lynx_log := {} # 猞猁的雪兔：選擇 -> 次數
	var food_season := {} # 鮭魚（Phase 2h 第 5 步）：巢穴 -> 季節 -> [食物合計, 鮭魚]
	var salmon_log := {} # life_log.salmon 的合計（trips、fish、warns、pushes、scraps、stands）
	# DENS_ONLY=forest_east,...：只從這些巢穴開始（校準某一區的系統時用，例如鮭魚，Phase 2h 第 5 步）
	# SALMON_SET='{"find": {...}}'：覆寫 balance.salmon 的部分設定（字典逐層合併；校準 Phase 2h 第 5 步用）
	if OS.get_environment("SALMON_SET") != "":
		_merge(GS.get_node("/root/GameData").balance["salmon"], JSON.parse_string(OS.get_environment("SALMON_SET")))
	# NO_SALMON=1：沒有鮭魚洄流（對照 Phase 2h）
	if OS.get_environment("NO_SALMON") != "":
		GS.get_node("/root/GameData").balance["salmon"]["find"] = {}
		GS.get_node("/root/GameData").balance["salmon"]["fishing_enabled"] = false
	# TACTICAL_SET='{"allies": {"game": {...}}}'：覆寫 tactical_hunt.json 的部分設定（Phase 2i 校準用）
	if OS.get_environment("TACTICAL_SET") != "":
		GS.tactical_overrides = JSON.parse_string(OS.get_environment("TACTICAL_SET"))
	var dens: Array = Array(OS.get_environment("DENS_ONLY").split(",")) if OS.get_environment("DENS_ONLY") != "" else DENS
	for r in runs:
		var ap = AP.new("all", "average")
		ap.tactical = OS.get_environment("NO_TACTICAL") == ""
		ap.cache = OS.get_environment("NO_CACHE") == ""
		if OS.get_environment("TACTICAL_ONLY") != "":
			ap.tactical_only = OS.get_environment("TACTICAL_ONLY").split(",")
		ap.start(dens[r % dens.size()])
		var guard := 0
		var dueled := {}
		var sampled := {}
		var snapped_at := {}
		var food_at := {} # 1 歲、2 歲時的 food_by（累計）
		var stuck := 0 # 一步之後遊戲日沒有前進的次數（Phase 2f 第 4 步：發現有一隻狼一直停在 0.7 歲）
		var same_age := 0 # 年齡（換季才長）連續幾天沒變：季節要睡覺才換，一直沒睡的話天數照走、年齡不動（2026-10-22 又出現一次）
		var last_age: float = -1.0
		# YOUNG_PREY=small_only：未滿 1 歲只獵小獵物（殘骸照吃），1 歲後照常（2026-10-22：小狼「先吃小的」能不能活）；
		# MAX_AGE：到這個年紀就停（只看前半生時省時間）
		var young_prey: String = OS.get_environment("YOUNG_PREY")
		var max_age: float = float(OS.get_environment("MAX_AGE")) if OS.get_environment("MAX_AGE") != "" else 99.0
		while not ap.done() and guard < 2000:
			guard += 1
			if young_prey != "":
				ap.prey = young_prey if GS.wolf.age_years < 1.0 else "all"
			if GS.wolf.age_years >= max_age:
				break
			for a in duel_ages:
				if not dueled.has(a) and GS.wolf.age_years >= a:
					dueled[a] = true
					var res: Array = _duel(GS, duels)
					duel[a][0] += res[0]; duel[a][1] += res[1]
					for st in ["strength", "skill", "speed", "health_max"]:
						stat_sum[a][st] = float(stat_sum[a].get(st, 0.0)) + float(GS.wolf.get(st))
					stat_sum[a]["n"] = int(stat_sum[a].get("n", 0)) + 1
			for a in SNAP_AGES:
				if not snapped_at.has(a) and GS.wolf.age_years >= a:
					snapped_at[a] = true
					if a == 1.0 or a == 2.0:
						food_at[a] = (GS.life_log.get("food_by", {}) as Dictionary).duplicate()
						if a == 1.0:
							sp_log["young_tries"] += int(GS.life_log.get("small_pounce", {}).get("tries", 0))
					for st in ["strength", "skill", "speed", "health_max", "perception"]:
						snap[a][st] = float(snap[a].get(st, 0.0)) + float(GS.wolf.get(st))
					snap[a]["n"] = int(snap[a].get("n", 0)) + 1
			for a in pack_ages:
				if not sampled.has(a) and GS.wolf.age_years >= a:
					sampled[a] = true
					var bp = GS.black_pack
					var leader = GS.pack_leader()
					var st: String = bp.stage
					pack_at[a][st] = int(pack_at[a].get(st, 0)) + 1
					pack_at[a]["n"] += 1
					pack_at[a]["size"] += bp.size(leader != null and leader.alive)
					pack_at[a]["regions"] += bp.regions.size()
			var stage: String = STAGES[GS.wolf.life_stage()]
			var t0 := int(GS.life_log.get("hunt_attempts", 0)); var w0 := int(GS.life_log.get("hunt_successes", 0))
			var prey0: Dictionary = GS.life_log.get("prey_count", {}).duplicate()
			var day0: int = root.get_node("GameTime").day
			var fs0: String = root.get_node("GameTime").current_season()
			var fb0: Dictionary = GS.life_log.get("food_by", {})
			var ft0 := 0.0
			for k in fb0.keys():
				ft0 += float(fb0[k])
			var sal0: float = float(fb0.get("salmon", 0.0))
			ap.step(1)
			var fb1: Dictionary = GS.life_log.get("food_by", {})
			var ft1 := 0.0
			for k in fb1.keys():
				ft1 += float(fb1[k])
			var fden: String = dens[r % dens.size()]
			var fd: Dictionary = food_season.get_or_add(fden, {})
			var fsv: Array = fd.get_or_add(fs0, [0.0, 0.0])
			fsv[0] += ft1 - ft0
			fsv[1] += float(fb1.get("salmon", 0.0)) - sal0
			stuck = stuck + 1 if root.get_node("GameTime").day == day0 and GS.wolf.alive else 0
			same_age = same_age + 1 if absf(GS.wolf.age_years - last_age) < 0.0001 else 0
			last_age = GS.wolf.age_years
			if stuck >= 5 or same_age >= 30:
				var msgs: Array = GS.life_log.get("recent_messages", [])
				print("  ⚠ 卡住（%s）：第 %d 隻、種子 %d、%.2f 歲、季節 %s 第 %d 天、%s %s、飽食 %.0f 體力 %.0f、事件 %s、殘骸 %d、遭遇 %s" % ["同一天" if stuck >= 5 else "年齡 30 天沒變",
					r, GS.rng_seed, GS.wolf.age_years, root.get_node("GameTime").current_season(), root.get_node("GameTime").day, GS.current_region,
					root.get_node("GameTime").current_period(), GS.wolf.hunger, GS.wolf.stamina, GS.pending_events.map(func(e): return str(e.get("type", ""))),
					GS.carcass_index_here(), GS.current_encounter.get("type", "") if GS.get("current_encounter") is Dictionary else "?"])
				print("    最近的選擇：", (GS.life_log.get("decisions", []) as Array).slice(-12), "；睡覺 ", GS.life_log.get("stats", {}).get("option_counts", {}).get("sleep", 0), "；時段 ", root.get_node("GameTime").current_period(), "；pending_season ", root.get_node("GameTime").season_due())
				for m in msgs.slice(maxi(0, msgs.size() - 8)):
					print("    " + str(m).replace("\n", " ").left(160))
				break
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
			var season: String = root.get_node("GameTime").current_season()
			season_days[season] = int(season_days.get(season, 0)) + 1
			if h < hungry_at:
				season_hungry[season] = int(season_hungry.get(season, 0)) + 1
			if stage == "subadult":
				var sk: String = "young" if GS.wolf.age_years < 1.0 else "yearling"
				sub_days[sk] = int(sub_days.get(sk, 0)) + 1
				if h < hungry_at:
					sub_hungry[sk] = int(sub_hungry.get(sk, 0)) + 1
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
		for k in cache_log.keys():
			cache_log[k] += int(GS.life_log.get(k, 0))
		var seen := {}
		var tstats: Dictionary = GS.life_log.get("stats", {})
		for k in tstats.get("tactical_by_stage", {}).keys():
			tac[k] = int(tac.get(k, 0)) + int(tstats["tactical_by_stage"][k])
		for k in tstats.get("tactical_species_cost", {}).keys():
			tac_spx[k] = int(tac_spx.get(k, 0)) + int(tstats["tactical_species_cost"][k])
		for k in tstats.get("tactical_by_species_stage", {}).keys():
			tac_sps[k] = int(tac_sps.get(k, 0)) + int(tstats["tactical_by_species_stage"][k])
		for k in tstats.get("tactical_by_species", {}).keys():
			tac_sp[k] = int(tac_sp.get(k, 0)) + int(tstats["tactical_by_species"][k])
		for k in tstats.get("hunt_entry", {}).keys():
			entry[k] = int(entry.get(k, 0)) + int(tstats["hunt_entry"][k])
		for k in tstats.get("tactical_stamina", {}).keys():
			tac_st[k] = int(tac_st.get(k, 0)) + int(tstats["tactical_stamina"][k])
		var meets: Array = GS.life_log.get("pack_meetings", [])
		if not meets.is_empty():
			meet_lives += 1
		for m in meets:
			var mk: String = "%s.%s" % [m["kind"], m["outcome"]]
			meet_count[mk] = int(meet_count.get(mk, 0)) + 1
		for e in GS.life_log.get("black_pack_events", []):
			var ev: String = str(e["event"])
			event_count[ev] = int(event_count.get(ev, 0)) + 1
			if not seen.has(ev):
				seen[ev] = true
				var l: Array = first_event.get(ev, [])
				l.append(float(e["age"]))
				first_event[ev] = l
		var fb: Dictionary = GS.life_log.get("food_by", {})
		var f1: Dictionary = food_at.get(1.0, fb)
		var f2: Dictionary = food_at.get(2.0, fb)
		for src in fb.keys():
			var cat := _food_cat(str(src))
			food["life"][cat] = float(food["life"].get(cat, 0.0)) + float(fb[src])
			food["young"][cat] = float(food["young"].get(cat, 0.0)) + float(f1.get(src, 0.0))
			food["yearling"][cat] = float(food["yearling"].get(cat, 0.0)) + float(f2.get(src, 0.0)) - float(f1.get(src, 0.0))
		sp_log["tries"] += int(GS.life_log.get("small_pounce", {}).get("tries", 0))
		sp_log["caught"] += int(GS.life_log.get("small_pounce", {}).get("caught", 0))
		for k in GS.life_log.get("salmon", {}).keys():
			salmon_log[k] = int(salmon_log.get(k, 0)) + int(GS.life_log["salmon"][k])
		for k in GS.life_log.get("lynx_choices", {}).keys():
			lynx_log[k] = int(lynx_log.get(k, 0)) + int(GS.life_log["lynx_choices"][k])
		deaths[GS.wolf.death_cause] = int(deaths.get(GS.wolf.death_cause, 0)) + 1
		if str(GS.wolf.death_cause) == "starvation":
			starved.append("%.1f 歲（%s）" % [GS.wolf.age_years, GS.den_region])
		ages.append(GS.wolf.age_years)
	var dpy: float = 4.0 * float(GT._season_day_count()) # 一年幾天
	print("== life_pressure：%d 隻狼（什麼都獵、平均打法，四張地圖輪流），挨餓 = 飽食度 < %d，一年約 %d 天" % [runs, hungry_at, dpy])
	for s in STAGES:
		var yrs: float = max(0.01, days[s] / dpy)
		var k: Dictionary = kills[s]
		print("  %-8s %5.1f 狼年：每年挨餓 %4.1f 天、吃不飽(<60) %5.1f 天；狩獵成功 %3d%%（每天出獵 %.1f 次）；每年獵到 大 %4.1f 中 %4.1f 小 %4.1f" % [
			s, yrs, hungry[s] / yrs, underfed[s] / yrs, roundi(100.0 * wins[s] / max(1, tries[s])), float(tries[s]) / max(1, days[s]),
			k["large"] / yrs, k["medium"] / yrs, k["small"] / yrs])
	for sk in ["young", "yearling"]:
		print("    其中 %s：每年挨餓 %4.1f 天（%d 天）" % ["未滿 1 歲" if sk == "young" else "1～2 歲", float(sub_hungry.get(sk, 0)) / max(0.01, float(sub_days.get(sk, 0)) / dpy), int(sub_days.get(sk, 0))])
	for yk in ["normal", "lean"]:
		print("  %-6s年：每年挨餓 %4.1f 天（共 %d 天）" % [yk, year_hungry[yk] / max(0.01, year_days[yk] / dpy), year_days[yk]])
	print("  老年的荒年：每年挨餓 %4.1f 天（共 %d 天）" % [elder_lean[1] / max(0.01, elder_lean[0] / dpy), elder_lean[0]])
	ages.sort()
	var total := 0.0
	for a in ages: total += a
	var sline := "  各季挨餓（每季 10 天）："
	for se in ["spring", "summer", "autumn", "winter"]:
		sline += " %s %.2f 天" % [se, 10.0 * float(season_hungry.get(se, 0)) / max(1, int(season_days.get(se, 0)))]
	print(sline)
	print("  藏食物（%d 隻合計）：藏 %d 段、吃 %d 段、被挖走／燒掉／壞光 %d 份" % [runs, cache_log["caches_made"], cache_log["caches_eaten"], cache_log["caches_lost"]])
	print("  壽命：平均 %.1f、中位數 %.1f、最短 %.1f、最長 %.1f" % [total / ages.size(), ages[ages.size() / 2], ages[0], ages.back()])
	print("  死因：", deaths, "；餓死：", ", ".join(starved) if not starved.is_empty() else "無")
	for a in duel_ages:
		var sn: float = max(1, int(stat_sum[a].get("n", 0)))
		print("  %.0f 歲單挑黑狼：贏 %d%%（%d 場；黑狼已死的局不算）；這時平均 力量 %.0f 技巧 %.0f 速度 %.0f 血量上限 %.0f" % [a, roundi(100.0 * duel[a][1] / max(1, duel[a][0])), duel[a][0],
			float(stat_sum[a].get("strength", 0)) / sn, float(stat_sum[a].get("skill", 0)) / sn, float(stat_sum[a].get("speed", 0)) / sn, float(stat_sum[a].get("health_max", 0)) / sn])
	for a in SNAP_AGES:
		var nn: float = max(1, int(snap[a].get("n", 0)))
		print("  %.1f 歲平均：力量 %.0f 技巧 %.1f 速度 %.0f 血量上限 %.0f 感知 %.1f" % [a, float(snap[a].get("strength", 0)) / nn, float(snap[a].get("skill", 0)) / nn, float(snap[a].get("speed", 0)) / nn, float(snap[a].get("health_max", 0)) / nn, float(snap[a].get("perception", 0)) / nn])
	for fk in ["young", "yearling", "life"]:
		var tot := 0.0
		for c in food[fk].keys():
			tot += float(food[fk][c])
		var parts: Array = []
		for c in FOOD_CATS:
			if float(food[fk].get(c, 0.0)) > 0.0:
				parts.append("%s %d%%" % [c, roundi(100.0 * float(food[fk][c]) / max(1.0, tot))])
		print("  食物來源 %s（飽食度合計 %d）：%s" % [{"young": "未滿 1 歲", "yearling": "1～2 歲", "life": "一生"}[fk], roundi(tot), "、".join(parts)])
	print("  小撲：%d 次（未滿 1 歲 %d）、撲到 %d；猞猁的雪兔：%s" % [sp_log["tries"], sp_log["young_tries"], sp_log["caught"], lynx_log])
	# 鮭魚（Phase 2h）：各巢穴、各季食物裡鮭魚佔多少（目標 T2：住在有鮭魚區域的狼秋季 25～40%、全年 ≤ 10～15%）
	var sline2 := "  鮭魚佔食物："
	for den in food_season.keys():
		var tot := [0.0, 0.0]
		var parts: Array = []
		for se in ["summer", "autumn"]:
			var v: Array = food_season[den].get(se, [0.0, 0.0])
			parts.append("%s %d%%" % [se, roundi(100.0 * float(v[1]) / max(1.0, float(v[0])))])
		for se in food_season[den].keys():
			tot[0] += float(food_season[den][se][0]); tot[1] += float(food_season[den][se][1])
		sline2 += "%s（%s、全年 %d%%） " % [den, "、".join(parts), roundi(100.0 * tot[1] / max(1.0, tot[0]))]
	print(sline2)
	print("  鮭魚紀錄（合計）：%s" % salmon_log)
	print("  黑狼家族（你在這個年齡時）：")
	for a in pack_ages:
		var pa: Dictionary = pack_at[a]
		var n: float = max(1, int(pa["n"]))
		var stages: Array = []
		for st in ["solo", "pair", "pack", "gone"]:
			stages.append("%s %d%%" % [st, roundi(100.0 * int(pa.get(st, 0)) / n)])
		print("    %.0f 歲：%s；平均 %.1f 隻、%.1f 區（%d 局）" % [a, "、".join(stages), pa["size"] / n, pa["regions"] / n, pa["n"]])
	for ev in first_event.keys():
		var l: Array = first_event[ev]
		l.sort()
		var t := 0.0
		for x in l: t += x
		print("    %-10s %d 局發生（共 %d 次）；第一次 平均 %.1f 歲、中位數 %.1f 歲" % [ev, l.size(), event_count[ev], t / l.size(), l[l.size() / 2]])
	print("    撞上黑狼一家：%d 局有，%s" % [meet_lives, meet_count])
	for st in ["young", "yearling", "adult", "elder"]:
		var n := 0
		var ok := 0
		var gave := 0
		for k in tac.keys():
			if str(k).begins_with(st + "."):
				n += int(tac[k])
				if str(k).ends_with(".caught"):
					ok += int(tac[k])
				elif str(k).ends_with(".gave_up"):
					gave += int(tac[k])
		if n > 0:
			print("  戰術狩獵（鹿類）%-8s %d 場：獵到 %d%%、放棄 %d%%，出手後 %d%%；每場扣體力 %.1f" % [st, n, roundi(100.0 * ok / n), roundi(100.0 * gave / n),
				roundi(100.0 * ok / max(1, n - gave)), float(tac_st.get(st, 0)) / n])
	for sp in ["white_tailed_deer", "elk", "mule_deer", "caribou", "moose", "bison", "beaver", "hare", "snowshoe_hare", "pronghorn", "bighorn_sheep", "marmot"]:
		var n := 0
		var ok := 0
		var gave := 0
		for k in tac_sp.keys():
			if str(k).begins_with(sp + "."):
				n += int(tac_sp[k])
				if str(k).ends_with(".caught"):
					ok += int(tac_sp[k])
				elif str(k).ends_with(".gave_up"):
					gave += int(tac_sp[k])
		if n > 0:
			print("  戰術狩獵 %-18s %d 場：獵到 %d%%、放棄 %d%%，出手後 %d%%；每場扣體力 %.1f、遊戲回合 %.1f" % [sp, n, roundi(100.0 * ok / n), roundi(100.0 * gave / n), roundi(100.0 * ok / max(1, n - gave)),
				float(tac_spx.get(sp + ".stamina", 0)) / n, float(tac_spx.get(sp + ".turns", 0)) / n])
	# 小獵物各年齡的獵到比例（2026-10-22 使用者：未成年的狼抓雪兔約六到七成）
	for sp in ["snowshoe_hare", "hare", "beaver", "marmot"]:
		var line := "  %s 各年齡獵到：" % sp
		for st in ["young", "yearling", "adult", "elder"]:
			var n := 0
			var ok := 0
			for k in tac_sps.keys():
				if str(k).begins_with(sp + "." + st + "."):
					n += int(tac_sps[k])
					if str(k).ends_with(".caught"):
						ok += int(tac_sps[k])
			if n > 0:
				line += " %s %d%%（%d 場）" % [st, roundi(100.0 * ok / n), n]
		print(line)
	# 各入口的狩獵（Phase 2i 第 7 步）：次數、成功率、每場受的傷
	var kinds: Dictionary = {}
	for k in entry.keys():
		var parts: PackedStringArray = str(k).split(".")
		kinds[parts[0] + "." + parts[1]] = true
	var ks: Array = kinds.keys()
	ks.sort()
	for kk in ks:
		var n: int = int(entry.get(kk + ".n", 0))
		print("  入口 %-18s %5d 場：獵到 %3d%%、每場受傷 %.1f" % [kk, n, roundi(100.0 * int(entry.get(kk + ".ok", 0)) / maxf(1.0, n)), float(entry.get(kk + ".hurt", 0)) / maxf(1.0, n)])
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

func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src.keys():
		if dst.has(k) and dst[k] is Dictionary and src[k] is Dictionary:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]
