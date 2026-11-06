extends SceneTree
# Phase 2k 第 4 步：狼對狼一對一的戰術戰鬥模擬（交給本能 vs 黑狼的 AI）。
# 你的狼用一生模擬（life_pressure）2、3、4 歲時的平均能力；黑狼用 balance.json 的開局能力中間值。
# 看：打贏（牠示弱或被打傷走掉）、你示弱、你被打倒、平均回合。通過標準（SPEC Phase 2k 驗收 4）：2 歲約四成、3 歲八成多、4 歲幾乎都贏，多半以示弱結束。
# 用法：RUNS=200 STAKE=1.0 bash tools/run_sim.sh tactical_wolf_duel
const AGES := {
	"2": { "strength": 75, "skill": 60, "speed": 58, "perception": 55, "stamina": 80, "health": 106, "health_max": 106 },
	"3": { "strength": 87, "skill": 68, "speed": 62, "perception": 61, "stamina": 80, "health": 112, "health_max": 112 },
	"4": { "strength": 92, "skill": 75, "speed": 64, "perception": 65, "stamina": 80, "health": 113, "health_max": 113 },
}
const BLACK := { "strength": 70, "skill": 64, "speed": 68, "perception": 62, "health": 110, "health_max": 110 }

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 200
	var stake := float(OS.get_environment("STAKE")) if OS.get_environment("STAKE") != "" else 1.0
	for age in AGES.keys():
		var res := {"win": 0, "submit_win": 0, "you_submit": 0, "knocked": 0, "other": 0, "rounds": 0}
		for s in runs:
			var tc := TacticalCombat.new()
			tc.setup("wolf_duel", {"seed": 500 + s, "wolf_stats": AGES[age], "opponent_stats": BLACK, "stake": stake, "mode": "sync"})
			var g := 0
			while not tc.done and g < 40:
				g += 1
				tc.begin_round()
				if tc.done:
					break
				tc.plan(0, tc.auto_plan(0))
				tc.resolve()
			res["rounds"] += tc.rounds
			var e := tc.enemy_index()
			match tc.outcome:
				"enemy_submit":
					res["win"] += 1
					res["submit_win"] += 1
				"enemy_left":
					if str(tc.units[e]["out_reason"]) == "hurt":
						res["win"] += 1
					else:
						res["other"] += 1
				"submit":
					res["you_submit"] += 1
				"knocked":
					res["knocked"] += 1
				_:
					res["other"] += 1
			var key: String = tc.outcome + "/" + str(tc.units[e]["out_reason"]) + "/" + str(tc.units[0]["out_reason"])
			res[key] = int(res.get(key, 0)) + 1
		var n := float(runs)
		print("%s 歲 vs 黑狼（stake %.1f）：打贏 %3d%%（其中牠示弱 %3d%%）、你示弱 %3d%%、你被打倒 %3d%%、其他 %3d%%、平均 %.1f 回合" % [age, stake,
			roundi(100.0 * res["win"] / n), roundi(100.0 * res["submit_win"] / n), roundi(100.0 * res["you_submit"] / n), roundi(100.0 * res["knocked"] / n),
			roundi(100.0 * res["other"] / n), float(res["rounds"]) / n])
		print("    ", res.keys().filter(func(k): return str(k).contains("/")).map(func(k): return "%s %d" % [k, res[k]]))
	quit()
