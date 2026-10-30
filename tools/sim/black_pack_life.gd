extends SceneTree
# Phase 3a 第 6 步「驗證」：黑狼的一生的通過標準（SPEC Phase 3a「目標與驗收」）。
# 自動玩家住在森林（巢穴輪流四區）、每天清晨一半機會換到相鄰區域（AutoPlayer.roam），玩到死，統計：
#   1. 3～6 歲的季節裡，有幾成遇到和黑狼一家有關、要做決定的事（GameState._pack_note：撞上、落單的、殘骸、標記被蓋過、地盤被佔走）
#   2. 壽命、死因（被狼殺死的比例）
#   3. 各種事的次數、成年每年挨餓天數
# 通過標準（初始值）：1 ≥ 70%；壽命 9～11；被狼殺死 ≤ 15%。
# 用法：bash tools/run_sim.sh black_pack_life 0 30；STYLE=assault 換成強攻型（預設 average）；ROAM=0 不四處走動（待在巢穴附近）、SLEEP_HOME=1 四處走動但夜裡回巢穴睡

const DENS := ["forest_east", "forest_north", "forest_south", "forest_west"]

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var runs := _env_int("RUNS", 20)
	# 對照組：NOPACK=1 時黑狼不會成家（看壽命、挨餓的差異是不是黑狼一家造成的）
	if OS.get_environment("NOPACK") != "":
		root.get_node("GameData").balance["black_pack"]["pair_chance"] = 0.0
	var style := OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "average"
	var seasons_total := 0
	var seasons_hit := 0
	var kinds := {}
	var deaths := {}
	var ages: Array = []
	var adult_days := 0
	var adult_hungry := 0
	var stam_sum := 0.0
	var by_age := {} # 歲 -> [季數, 有事的季數]
	for r in runs:
		var ap = AP.new("all", style)
		ap.roam = OS.get_environment("ROAM") != "0"
		ap.roam_sleep_home = OS.get_environment("SLEEP_HOME") != ""
		ap.start(DENS[r % DENS.size()])
		var guard := 0
		var forest_seasons := {} # 季（age × 4）-> true：那一季有待在森林
		while not ap.done() and guard < 2000:
			guard += 1
			ap.step(1)
			if not GS.wolf.alive:
				break
			if GS.current_map() == "forest":
				forest_seasons[int(floor(GS.wolf.age_years * 4.0 + 0.001))] = true
			if GS.wolf.life_stage() == 1:
				adult_days += 1
				stam_sum += GS.wolf.stamina
				if GS.wolf.hunger < 30.0:
					adult_hungry += 1
		ap.finish()
		var hit := {}
		for d in GS.life_log.get("pack_decisions", []):
			hit[int(floor(float(d["age"]) * 4.0 + 0.001))] = true
			kinds[str(d["kind"])] = int(kinds.get(str(d["kind"]), 0)) + 1
		for q in forest_seasons.keys():
			if q >= 12 and q < 24:
				seasons_total += 1
				var y: int = q / 4
				if not by_age.has(y):
					by_age[y] = [0, 0]
				by_age[y][0] += 1
				if hit.has(q):
					seasons_hit += 1
					by_age[y][1] += 1
		var cause: String = str(GS.wolf.death_cause)
		deaths[cause] = int(deaths.get(cause, 0)) + 1
		ages.append(GS.wolf.age_years)
	ages.sort()
	var total := 0.0
	for a in ages:
		total += a
	var wolf_deaths := 0
	for c in deaths.keys():
		if str(c).contains("stranger_wolf") or str(c).contains("challenger") or str(c).contains("pack"):
			wolf_deaths += int(deaths[c])
	print("== black_pack_life：%d 隻（%s，住在森林、四處走動）" % [runs, style])
	print("  3～6 歲的季節：%d 季，有和黑狼一家有關的事 %d 季（%d%%，目標 ≥ 70%%）" % [seasons_total, seasons_hit, roundi(100.0 * seasons_hit / max(1, seasons_total))])
	var ys: Array = by_age.keys()
	ys.sort()
	for y in ys:
		print("    %d 歲：%d／%d 季（%d%%）" % [y, by_age[y][1], by_age[y][0], roundi(100.0 * by_age[y][1] / max(1, by_age[y][0]))])
	print("  事件次數：", kinds)
	print("  壽命：平均 %.1f、中位數 %.1f（目標 9～11）" % [total / max(1, ages.size()), ages[ages.size() / 2] if not ages.is_empty() else 0.0])
	print("  死因：%s；被狼殺死 %d%%（目標 ≤ 15%%）" % [deaths, roundi(100.0 * wolf_deaths / max(1, runs))])
	print("  成年每年挨餓 %.1f 天；成年每天開始時的體力平均 %.0f" % [adult_hungry / max(0.01, adult_days / 40.0), stam_sum / max(1, adult_days)])
	quit()
	return true
