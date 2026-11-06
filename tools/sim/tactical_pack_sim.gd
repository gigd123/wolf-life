extends SceneTree
# Phase 2k 第 5 步：多隻對手與狼群對狼群的戰術戰鬥模擬（你交給本能、同伴自動、對手 AI）。
# 你的狼用 3 歲的平均能力（同 tactical_wolf_duel），同伴照 MATE（成年的伴侶）、對手照 tundra_wolf／pack_wolf 的預設。
# 看：你們贏（牠們都退走）、你撤出、你示弱、你被打倒或死、同伴被打倒或死、平均回合。
# 通過標準（SPEC Phase 2k 驗收 5）：獨狼被 2～3 隻圍時多半撤退、撤得掉（撤出成功約七成以上）；
# 帶著狼群時人數與實力佔優的一方多半贏，和 Phase 3 鄰群衝突（pack_fight_chance）相近。
# 用法：RUNS=200 bash tools/run_sim.sh tactical_pack_sim
const YOU := { "strength": 87, "skill": 68, "speed": 62, "perception": 61, "stamina": 80, "health": 112, "health_max": 112 }
const MATE := { "strength": 72, "skill": 62, "speed": 64, "perception": 60, "stamina": 80, "health": 104, "health_max": 104 }
# 對手：帶頭的和你差不多、其他和伴侶差不多（主遊戲鄰群帶頭的 NPC 約 80～90 力量）
const LEAD := { "strength": 85, "skill": 66, "speed": 64, "perception": 60, "health": 110, "health_max": 110 }
const ALLY_POS := [[3, 3], [3, 7], [2, 5]]
const FOE_POS := [[11, 5], [10, 3], [10, 7]]

func _initialize() -> void:
	_run.call_deferred()

func _scenario(n_you: int, n_foe: int, foe: String) -> Dictionary:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tactical_combat.json"))
	var sc: Dictionary = (cfg["scenarios"]["grizzly_open"] as Dictionary).duplicate(true)
	sc["opponent"] = {"id": foe, "pos": FOE_POS[0], "facing": [-1, 0]}
	var weak := OS.get_environment("WEAK") == "1"
	var extra: Array = []
	for k in range(1, n_foe):
		var x := {"id": foe, "uid": foe + "_%d" % (k + 1), "pos": FOE_POS[k], "facing": [-1, 0]}
		if not weak:
			x["stats"] = MATE
		extra.append(x)
	sc["extra_enemies"] = extra
	var allies: Array = []
	for k in range(1, n_you):
		allies.append({"id": "member_%d" % k, "pos": ALLY_POS[k - 1], "stats": MATE})
	sc["allies"] = allies
	return sc

func _run() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 200
	var foe := OS.get_environment("FOE") if OS.get_environment("FOE") != "" else "pack_wolf"
	for pair in [[1, 2], [1, 3], [2, 2], [2, 3], [3, 3], [3, 2], [2, 1], [3, 1]]:
		var res := {"win": 0, "retreated": 0, "submit": 0, "down": 0, "timeout": 0, "ally_down": 0, "ally_dead": 0, "rounds": 0, "foes_out": 0}
		for s in runs:
			var tc := TacticalCombat.new()
			var opts := {"scenario_data": _scenario(pair[0], pair[1], foe), "seed": 900 + s, "wolf_stats": YOU, "mode": "sync"}
			if OS.get_environment("WEAK") != "1":
				opts["opponent_stats"] = LEAD
			tc.setup("", opts)
			var g := 0
			while not tc.done and g < 40:
				g += 1
				tc.begin_round()
				if tc.done:
					break
				tc.plan(0, tc.auto_plan(0))
				tc.resolve()
			res["rounds"] += tc.rounds
			match tc.outcome:
				"routed", "enemy_submit", "enemy_left":
					res["win"] += 1
				"retreated":
					res["retreated"] += 1
				"submit":
					res["submit"] += 1
				"knocked", "died":
					res["down"] += 1
				_:
					res["timeout"] += 1
			for k in tc.units.size():
				if str(tc.units[k]["side"]) == "ally" and bool(tc.units[k]["out"]):
					if str(tc.units[k]["out_reason"]) in ["knocked", "died"]:
						res["ally_down"] += 1
				if str(tc.units[k]["side"]) == "enemy" and bool(tc.units[k]["out"]):
					res["foes_out"] += 1
		var n := float(runs)
		print("%d 對 %d（%s）：贏 %3d%%、你撤出 %3d%%、你示弱 %3d%%、你被打倒 %3d%%、拖到時間 %3d%%｜同伴被打倒 每場 %.2f 隻、對手退出 每場 %.2f 隻、平均 %.1f 回合" % [pair[0], pair[1], foe,
			roundi(100.0 * res["win"] / n), roundi(100.0 * res["retreated"] / n), roundi(100.0 * res["submit"] / n), roundi(100.0 * res["down"] / n), roundi(100.0 * res["timeout"] / n),
			res["ally_down"] / n, res["foes_out"] / n, float(res["rounds"]) / n])
	quit()
