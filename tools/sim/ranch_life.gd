extends SceneTree
# 牧場的一生模擬（Phase 4a 第 5 步，SPEC「目標（模擬的目標區間）」）：
# 自動玩家（什麼都獵、平均打法）照牧場策略玩到死，四個巢穴輪流；每種策略 RUNS 隻：
#   none      沒有牧場（ranch.json enabled false，對照組）
#   never     有牧場、從不去
#   sometimes 有牧場、偶爾去（飽食度 < 60 而且注意 < 40）
#   often     有牧場、常去（注意 < 70）
# 統計：出現比例與年齡、候選位置；成年每年挨餓（牧場開放前／後）、壽命、死因（人類佔多少）；
# 在牧場獵到幾隻、遭遇（巡查、追獵、吃到一半被打斷）、被槍打中、注意的最高值；因為牧場搬巢穴的局；
# 2 歲以後每張地圖的停留（時段比例，牧場開放後 vs 對照組同年齡）、每季探索次數。
# 用法：bash tools/run_sim.sh ranch_life 0 24（RUNS）；POLICIES=never,often 只跑這些；DENS_ONLY=forest_east 只從這些巢穴開始

const DENS := ["forest_east", "grassland_riverwoods", "tundra_south", "mountain_canyon"]
const MAPS := ["forest", "grassland", "tundra", "mountain", "ranch"]

var _GS
var _GT
var _period_map: Dictionary = {} # "open"/"closed" -> map -> 時段數（2 歲以後）

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _on_period(_i: int) -> void:
	if _GS.wolf == null or not _GS.wolf.alive or _GS.wolf.age_years < 2.0:
		return
	var k: String = "open" if _GS.ranch_state() == "open" else "closed"
	var m: Dictionary = _period_map.get_or_add(k, {})
	var mp: String = _GS.current_map()
	m[mp] = int(m.get(mp, 0)) + 1

func _process(_d):
	_GS = root.get_node("GameState")
	_GT = root.get_node("GameTime")
	var GD = root.get_node("GameData")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	_GT.period_changed.connect(_on_period)
	var runs := _env_int("RUNS", 24)
	var policies: Array = Array(OS.get_environment("POLICIES").split(",")) if OS.get_environment("POLICIES") != "" else ["none", "never", "sometimes", "often"]
	var dens: Array = Array(OS.get_environment("DENS_ONLY").split(",")) if OS.get_environment("DENS_ONLY") != "" else DENS
	var dpy: float = 4.0 * float(_GT._season_day_count())
	for pol in policies:
		GD.ranch_def["enabled"] = pol != "none"
		_period_map = {}
		var appeared := 0
		var appear_ages: Array = []
		var cands := {}
		var adult := {"ranch": [0, 0], "no_ranch": [0, 0]} # 成年、老年整段：[天數, 挨餓天數]，照這一局有沒有牧場（開放）分；年齡組成相同才能比
		var elder := {"ranch": [0, 0], "no_ranch": [0, 0]}
		var expl := {"open": [0, 0], "closed": [0, 0]} # 2 歲以後：[天數, 探索次數]
		var deaths := {}
		var ages: Array = []
		var ranch_sum := {}
		var kills_by := {}
		var entry := {} # 家畜.年齡 的狩獵（hunt_entry）
		var moved_lives := 0
		var moves := 0
		var peak: Array = []
		var visited_lives := 0
		var human_dead: Array = []
		for r in runs:
			var ap = AP.new("all", "average")
			if pol != "none":
				ap.ranch_policy = pol
			ap.start(dens[r % dens.size()])
			var guard := 0
			var stuck := 0
			var life := {1: [0, 0], 2: [0, 0]} # 這一局 成年、老年：[天數, 挨餓天數]
			while not ap.done() and guard < 2000:
				guard += 1
				var day0: int = _GT.day
				var k: String = "open" if _GS.ranch_state() == "open" else "closed"
				var ex0: int = ap.explores
				var grown: bool = _GS.wolf.age_years >= 2.0
				ap.step(1)
				stuck = stuck + 1 if _GT.day == day0 and _GS.wolf.alive else 0
				if stuck >= 5:
					print("  ⚠ 卡住：%s 第 %d 隻 %.2f 歲 %s" % [pol, r, _GS.wolf.age_years, _GS.current_region])
					break
				if not _GS.wolf.alive:
					break
				if grown:
					expl[k][0] += 1
					expl[k][1] += ap.explores - ex0
				var ls: int = _GS.wolf.life_stage()
				if life.has(ls):
					life[ls][0] += 1
					if _GS.wolf.hunger < 30.0:
						life[ls][1] += 1
			ap.finish()
			var st: String = _GS.ranch_state()
			var lk: String = "ranch" if st == "open" else "no_ranch"
			for i in 2:
				adult[lk][i] += life[1][i]
				elder[lk][i] += life[2][i]
			if st in ["clues", "open"]:
				appeared += 1
				appear_ages.append(float(_GS.ranch.get("appear_age", 0.0)))
				var c: String = str(_GS.ranch.get("candidate", ""))
				cands[c] = int(cands.get(c, 0)) + 1
			var rl: Dictionary = _GS.life_log.get("ranch", {})
			for key in ["kills", "failed", "patrols", "hunts", "eatings", "shots", "dogs_repelled", "watches", "signs", "clues"]:
				ranch_sum[key] = int(ranch_sum.get(key, 0)) + int(rl.get(key, 0))
			ranch_sum["damage"] = float(ranch_sum.get("damage", 0.0)) + float(rl.get("damage", 0.0))
			for key in rl.get("kills_by", {}).keys():
				kills_by[key] = int(kills_by.get(key, 0)) + int(rl["kills_by"][key])
			if int(rl.get("kills", 0)) > 0:
				visited_lives += 1
			if st == "open":
				peak.append(float(rl.get("peak_attention", 0.0)))
			if ap.ranch_moves > 0:
				moved_lives += 1
				moves += ap.ranch_moves
			var cause: String = str(_GS.wolf.death_cause)
			deaths[cause] = int(deaths.get(cause, 0)) + 1
			if cause == "human":
				human_dead.append("%.1f 歲（%s）" % [_GS.wolf.age_years, dens[r % dens.size()]])
			ages.append(_GS.wolf.age_years)
			var hs: Dictionary = _GS.life_log.get("stats", {})
			for key in hs.get("hunt_entry", {}).keys():
				if str(key).begins_with("cattle_") or str(key).begins_with("sheep_"):
					entry[key] = int(entry.get(key, 0)) + int(hs["hunt_entry"][key])
			for key in hs.get("hunt_entry_how", {}).keys():
				if str(key).begins_with("cattle_") or str(key).begins_with("sheep_"):
					entry["how." + key] = int(entry.get("how." + key, 0)) + int(hs["hunt_entry_how"][key])
		# 家畜的狩獵（Phase 2i 第 7 步）：種類.年齡 的次數、成功率、結局
		var ks: Array = entry.keys().filter(func(k): return str(k).ends_with(".n"))
		ks.sort()
		for k in ks:
			var base: String = str(k).trim_suffix(".n")
			var hows: Array = []
			for hk in entry.keys():
				if str(hk).begins_with("how." + base + "."):
					hows.append("%s %d" % [str(hk).substr(base.length() + 5), int(entry[hk])])
			print("  家畜 %-22s %4d 場：獵到 %3d%%（%s）" % [base, int(entry[k]), roundi(100.0 * int(entry.get(base + ".ok", 0)) / maxf(1.0, int(entry[k]))), "、".join(hows)])
		_report(pol, runs, dpy, appeared, appear_ages, cands, adult, elder, expl, deaths, ages, ranch_sum, kills_by, visited_lives, moved_lives, moves, peak, human_dead)
	quit()
	return true

func _report(pol, runs, dpy, appeared, appear_ages, cands, adult, elder, expl, deaths, ages, ranch_sum, kills_by, visited_lives, moved_lives, moves, peak, human_dead) -> void:
	var total := 0.0
	for a in ages:
		total += a
	ages.sort()
	print("== %s（%d 隻）" % [pol, runs])
	if pol != "none":
		appear_ages.sort()
		var at := 0.0
		for a in appear_ages:
			at += a
		print("  牧場出現 %d%%（%d 局），出現年齡 平均 %.2f、%s；候選 %s" % [roundi(100.0 * appeared / runs), appeared,
			at / max(1, appear_ages.size()), "最早 %.2f 最晚 %.2f" % [appear_ages[0], appear_ages.back()] if not appear_ages.is_empty() else "-", cands])
	for k in ["no_ranch", "ranch"]:
		if adult[k][0] > 0:
			print("  %s的局（%.0f 狼年）：每年挨餓 成年 %.1f、老年 %.1f 天" % ["有牧場" if k == "ranch" else "沒有牧場", (adult[k][0] + elder[k][0]) / dpy,
				adult[k][1] / (adult[k][0] / dpy), elder[k][1] / max(0.01, elder[k][0] / dpy)])
	print("  壽命 平均 %.1f、中位數 %.1f；死因 %s；人類 %d%%%s" % [total / max(1, ages.size()), ages[ages.size() / 2] if not ages.is_empty() else 0.0, deaths,
		roundi(100.0 * int(deaths.get("human", 0)) / runs), "（%s）" % "、".join(human_dead) if not human_dead.is_empty() else ""])
	if pol != "none":
		print("  牧場：獵到 %d（%s，%d 局有）、出手沒獵到 %d；遭遇 巡查 %d、追獵 %d、吃到一半 %d；中槍 %d、人類造成的傷 %.0f、咬退所有狗 %d；觀察 %d、痕跡 %d、出現的線索 %d" % [
			int(ranch_sum.get("kills", 0)), kills_by, visited_lives, int(ranch_sum.get("failed", 0)), int(ranch_sum.get("patrols", 0)), int(ranch_sum.get("hunts", 0)),
			int(ranch_sum.get("eatings", 0)), int(ranch_sum.get("shots", 0)), float(ranch_sum.get("damage", 0.0)), int(ranch_sum.get("dogs_repelled", 0)),
			int(ranch_sum.get("watches", 0)), int(ranch_sum.get("signs", 0)), int(ranch_sum.get("clues", 0))])
		peak.sort()
		print("  注意的最高值（開放的局）：%s；因為牧場搬巢穴 %d 局（%d 次）" % ["中位數 %.0f、最高 %.0f、≥40 的 %d 局、≥70 的 %d 局" % [peak[peak.size() / 2], peak.back(),
			peak.filter(func(x): return x >= 40.0).size(), peak.filter(func(x): return x >= 70.0).size()] if not peak.is_empty() else "-", moved_lives, moves])
	for k in ["closed", "open"]:
		var m: Dictionary = _period_map.get(k, {})
		var tot := 0
		for mp in m.keys():
			tot += int(m[mp])
		if tot == 0:
			continue
		var parts: Array = []
		for mp in MAPS:
			if int(m.get(mp, 0)) > 0:
				parts.append("%s %d%%" % [mp, roundi(100.0 * int(m[mp]) / tot)])
		var ex: Array = expl[k]
		print("  2 歲以後（牧場%s）停留：%s；每季探索 %.1f 次" % ["開放後" if k == "open" else "沒開放", "、".join(parts), 10.0 * ex[1] / max(1, ex[0])])
