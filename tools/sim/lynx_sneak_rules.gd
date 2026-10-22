extends SceneTree
# 悄悄叼走猞猁的雪兔（Phase 2g 第 3 步）的回歸測試：
#   1. 成功率：25% ＋（感知 ＋ 技巧 − 65）÷ 200（約 1 歲 40%、成年 50～60%）
#   2. 成功：雪兔（飽食度 12）歸你、花 1 回合；失敗：牠帶著雪兔走，描述照地形；只有失敗時約 10% 被抓（3～8）
#   3. 試玩紀錄：悄悄叼走、正面搶、離開的次數與叼到幾次；metrics_summary 有這一行
# 用法：bash tools/run_sim.sh lynx_sneak_rules
var gs
var gt
var fails := 0

func _initialize() -> void:
	gs = root.get_node("GameState")
	gt = root.get_node("GameTime")
	_run.call_deferred()

func _lynx(loc: String) -> void:
	gs.current_discovery = {"kind": "lynx", "location": loc, "has_kill": true, "known": true}

func _run() -> void:
	gs.new_game("forest_north")
	gs.pending_events.clear()
	# 1. 成功率
	gs.wolf.perception = 50.0; gs.wolf.skill = 45.0
	var young: float = gs.lynx_sneak_chance()
	var expect: float = 0.25 + (gs.wolf.effective_perception() + gs.wolf.effective_skill() - 65.0) / 200.0
	_check(absf(young - clampf(expect, 0.15, 0.7)) < 0.001 and young >= 0.3 and young <= 0.45, "約 1 歲（感知 50、技巧 45）約 35～45%%（%.2f）" % young)
	gs.wolf.age_years = 3.0
	gs.wolf.perception = 62.0; gs.wolf.skill = 62.0
	var adult: float = gs.lynx_sneak_chance()
	_check(adult >= 0.48 and adult <= 0.62, "成年（62、62）約 50～60%%（%.2f）" % adult)
	gs.wolf.perception = 100.0; gs.wolf.skill = 100.0
	_check(gs.lynx_sneak_chance() <= 0.7, "最多 70%%")
	gs.wolf.perception = 62.0; gs.wolf.skill = 62.0
	# 2. 結果
	var ok := 0
	var fail := 0
	var swiped := 0
	var bad := 0
	var esc_seen := {}
	for i in 400:
		var loc: String = "dense_forest" if i % 2 == 0 else "open_tundra"
		_lynx(loc)
		gs.wolf.hunger = 50.0
		gs.wolf.health = gs.wolf.health_max
		var t0: int = gt.day * 100 + gt.period_index * 10 + gt.turn_in_period
		var r: Dictionary = gs.lynx_sneak()
		var t1: int = gt.day * 100 + gt.period_index * 10 + gt.turn_in_period
		if t1 == t0 or not gs.current_discovery.is_empty():
			bad += 1
		if r["success"]:
			ok += 1
			# 花 1 回合，跨過時段時飽食度會照常消耗（最多 6）
			if float(r["gain"]) != 12.0 or gs.wolf.hunger < 62.0 - 6.01 or gs.wolf.hunger > 62.01 or int(r["damage"]) != 0 or gs.wolf.health < gs.wolf.health_max:
				bad += 1
		else:
			fail += 1
			if gs.wolf.hunger > 50.01 or float(r["gain"]) != 0.0:
				bad += 1
			var allowed: Array = ["thicket", "tree"] if loc == "dense_forest" else ["rocks", "thicket"]
			if not allowed.has(str(r["escape"])):
				bad += 1
			esc_seen[r["escape"]] = true
			if int(r["damage"]) > 0:
				swiped += 1
				if int(r["damage"]) < 3 or int(r["damage"]) > 8 or absf(gs.wolf.health_max - gs.wolf.health - float(r["damage"])) > 0.01:
					bad += 1
	_check(bad == 0, "成功 +12、不受傷；失敗沒食物、描述照地形；每次花時間（不對的 %d 次）" % bad)
	_check(absf(float(ok) / 400.0 - adult) < 0.08, "成功的比例接近成功率（%d／400，%.2f）" % [ok, adult])
	_check(swiped >= 5 and swiped <= fail * 0.2, "只有失敗時偶爾被抓（失敗 %d 次、被抓 %d 次）" % [fail, swiped])
	_check(esc_seen.has("thicket") and esc_seen.has("tree") and esc_seen.has("rocks"), "失敗的描述有密林、樹、岩縫（%s）" % [esc_seen.keys()])
	for k in ["lynx.sneak", "lynx.sneak.got", "lynx.sneak.fail.thicket", "lynx.sneak.fail.tree", "lynx.sneak.fail.rocks", "lynx.sneak.swipe"]:
		_check(TranslationServer.translate(k) != k, "有翻譯：" + k)
	# 3. 試玩紀錄
	_lynx("dense_forest")
	gs.start_lynx_combat()
	_lynx("dense_forest")
	gs.leave_lynx()
	gs.current_discovery = {"kind": "lynx", "location": "dense_forest", "has_kill": false}
	gs.leave_lynx()
	var lc: Dictionary = gs.life_log.get("lynx_choices", {})
	_check(int(lc.get("sneak", 0)) == 400 and int(lc.get("sneak_got", 0)) == ok and int(lc.get("fight", 0)) == 1 and int(lc.get("leave", 0)) == 1, "記下選擇：%s" % lc)
	_check(absf(float(gs.life_log.get("food_by", {}).get("lynx_sneak", 0.0)) - ok * 12.0) < 0.5, "食物來源記在 lynx_sneak")
	_check(str(gs.metrics_summary().get("lynx_choices", "")).contains("sneak"), "metrics_summary 有猞猁的選擇")
	print("成功率 約 1 歲 %.2f、成年 %.2f；成年 400 次：叼到 %d、失敗 %d（被抓 %d）" % [young, adult, ok, fail, swiped])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	quit()

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
