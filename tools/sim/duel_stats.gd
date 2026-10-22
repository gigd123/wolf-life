extends "res://tools/sim/life_pressure.gd"
# 指定能力的狼和黑狼單挑（2026-10-22 使用者問：試玩紀錄裡 2 歲成年時的素質打不打得過黑狼）。
# 黑狼用開局的樣子（2.5～3 歲，能力照 balance.npc_wolves.stranger_wolf.start_stats 擲），每隻黑狼打 DUELS 場，共 RUNS 隻。
# 用法：STATS=strength:74.9,skill:68.5,speed:60.7,perception:52.4,health_max:105.9 bash tools/run_sim.sh duel_stats
func _initialize() -> void:
	pass

func _process(_d) -> bool:
	var GS = root.get_node("GameState")
	var runs: int = _env_int("RUNS", 40)
	var duels: int = _env_int("DUELS", 30)
	var stats := {}
	for pair in OS.get_environment("STATS").split(","):
		if pair.contains(":"):
			stats[pair.get_slice(":", 0)] = float(pair.get_slice(":", 1))
	var total := [0, 0]
	var npc_sum := {}
	for r in runs:
		GS.new_game("forest_east")
		GS.debug_force_transition("adult")
		for k in stats:
			GS.wolf.set(k, stats[k])
		var npc = GS.stranger()
		for k in ["strength", "skill", "speed", "perception", "health_max"]:
			npc_sum[k] = float(npc_sum.get(k, 0.0)) + float(npc.get(k))
		var res: Array = _duel(GS, duels)
		total[0] += res[0]
		total[1] += res[1]
	var avg := {}
	for k in npc_sum:
		avg[k] = roundi(npc_sum[k] / runs)
	print("你的狼 %s 對黑狼（平均 %s）：贏 %d%%（%d 場）" % [stats, avg, roundi(100.0 * total[1] / max(1, total[0])), total[0]])
	return true
