extends SceneTree
# 字卡分級（2026-10-16）的回歸測試：
# 1. 受傷與痊癒：輕傷→重傷、重傷→輕傷、還沒好、完全好、恢復期間又受傷，換日摘要的痊癒句要和實際傷勢一致。
# 2. 睡醒摘要：一般成長不出卡片；挨餓長不起來只在連續挨餓的第一晚出卡片。
# 用法：bash tools/run_sim.sh notice_triage
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var W = load("res://scripts/core/Wolf.gd")
	# --- 1. 受傷 ---
	var cases := {
		"輕傷→重傷": [[W.Injury.LIGHT, 2], [W.Injury.HEAVY, 6]],
		"重傷→輕傷": [[W.Injury.HEAVY, 6], [W.Injury.LIGHT, 2]],
		"輕傷恢復中又輕傷": [[W.Injury.LIGHT, 2], [W.Injury.LIGHT, 3]],
		"重傷恢復中又重傷": [[W.Injury.HEAVY, 2], [W.Injury.HEAVY, 6]],
	}
	for name in cases.keys():
		gs.new_game("forest_east")
		gs.pending_events.clear()
		var steps: Array = cases[name]
		gs.wolf.apply_injury(steps[0][0], steps[0][1], "speed", "leg", "test")
		gs._sleep_heal = 1
		gs._on_day_changed(0)
		gs.wolf.apply_injury(steps[1][0], steps[1][1], "speed", "leg", "test")
		var expect_heavy: bool = steps[0][0] == W.Injury.HEAVY or steps[1][0] == W.Injury.HEAVY
		_check(gs.wolf.injury == (W.Injury.HEAVY if expect_heavy else W.Injury.LIGHT), name + "：受傷後的程度")
		var healed_day := -1
		var healed_key := ""
		for day in 20:
			gs.pending_events.clear()
			var before: int = gs.wolf.injury
			gs.wolf.hunger = 80.0
			gs._sleep_heal = 1 # 這一天睡過（傷勢只在睡覺時好轉）
			gs._on_day_changed(day + 1)
			var heal_lines: Array = []
			for e in gs.pending_events:
				if e.get("type", "") == "day_summary":
					for line in e.get("lines", []):
						var k: String = str(line.get("key", ""))
						if k.contains("healed") and not k.contains("poison") or k == "day_summary.old_injury_new":
							heal_lines.append(k)
			if not heal_lines.is_empty():
				_check(gs.wolf.injury == W.Injury.NONE, name + "：第 %d 天顯示痊癒時傷已經全好" % day)
				_check(heal_lines.size() == 1, name + "：痊癒只有一句")
				var k0: String = heal_lines[0]
				_check(before == W.Injury.HEAVY == (k0.contains("heavy") or k0 == "day_summary.old_injury_new"), name + "：痊癒句的程度和好之前一致（%s）" % k0)
				healed_day = day
				healed_key = k0
			elif before != W.Injury.NONE and gs.wolf.injury == W.Injury.NONE:
				_check(false, name + "：傷好了卻沒有痊癒句")
		_check(healed_day >= 0, name + "：最後有痊癒")
		print("%s：第 %d 天痊癒（%s）" % [name, healed_day, healed_key])
	# --- 2. 睡醒摘要 ---
	gs.new_game("forest_east")
	var settle_ok := {"points": 20.0, "hunger_mult": 1.0}
	var settle_starved := {"points": 20.0, "hunger_mult": 0.1}
	var cards: Array = []
	for settle in [settle_ok, settle_starved, settle_starved, settle_starved, settle_ok, settle_starved]:
		cards.append(bool(gs.sleep_summary(settle).get("card", false)))
	print("睡醒摘要（一般、挨餓×3、一般、挨餓）出卡片：", cards)
	_check(cards == [false, true, false, false, false, true], "挨餓卡片只在連續挨餓的第一晚")
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
