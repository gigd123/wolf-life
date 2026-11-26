extends SceneTree
# 黑狼示弱後追擊的風險（2026-11-26 使用者問）：選單式戰鬥，你一直咬到牠示弱，接著一直「追擊」。
# 你的能力照 2026-11-25 試玩紀錄（3 歲稍弱、4.4 歲），示弱之前照自動玩家的強攻打法，示弱之後一直追擊；× 黑狼的年齡，各 RUNS 場；印：打到示弱的比例、追擊後 咬死牠／你戰死／牠逃掉，追擊後你受的傷、重傷的比例。
# 用法：bash tools/run_sim.sh pursue_sim；RUNS=200
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var ap = load("res://scripts/core/AutoPlayer.gd").new("all", "assault")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 200
	if OS.get_environment("RUNS") == "" and OS.get_environment("DAYS") != "":
		runs = 200
	print("== 黑狼示弱後追擊（選單式），每格 %d 場" % runs)
	# 你的能力值：照 2026-11-25 試玩紀錄（4.4 歲：力量 99、技巧 84、速度 64、感知 54、血量 117），3 歲稍弱
	var profiles := {3.0: [85.0, 72.0, 62.0, 52.0, 108.0], 4.4: [99.0, 84.0, 64.0, 54.0, 117.0]}
	for age in [3.0, 4.4]:
		for black_age in [4.0, 6.0, 8.0]:
			var submitted := 0
			var pre := {}
			var res := {}
			var dmg_sum := 0.0
			var heavy := 0
			for i in runs:
				gs.new_game("forest_east")
				gs.debug_force_transition("adult")
				var pf: Array = profiles[age]
				gs.wolf.age_years = age
				gs.wolf.strength = pf[0]
				gs.wolf.skill = pf[1]
				gs.wolf.speed = pf[2]
				gs.wolf.perception = pf[3]
				gs.wolf.health_max = pf[4]
				gs.wolf.health = gs.wolf.health_max
				gs.wolf.clear_injury()
				var npc = gs.stranger()
				if npc == null:
					continue
				npc.age_years = black_age
				npc.alive = true
				npc.health = npc.health_max
				var c = gs.start_stranger_combat("territory")
				var g := 0
				# 示弱之前照自動玩家（平均打法）的判斷：會閃、會撤
				while c.phase != c.Phase.DONE and not c.opp_submitted and g < 40:
					g += 1
					c.choose(ap._combat_choice(c))
				if not c.opp_submitted or c.phase == c.Phase.DONE:
					var o0: String = "died" if gs.wolf.health <= 0.0 else str(c.outcome)
					pre[o0] = int(pre.get(o0, 0)) + 1
					continue
				submitted += 1
				var hp0: float = gs.wolf.health
				var heavy0: bool = gs.wolf.is_heavily_injured() if gs.wolf.has_method("is_heavily_injured") else false
				g = 0
				while c.phase != c.Phase.DONE and g < 30:
					g += 1
					var ids2: Array = c.options().map(func(o): return str(o["id"]))
					c.choose("pursue" if ids2.has("pursue") else ("bite" if ids2.has("bite") else str(ids2[0])))
				var out: String = "died" if gs.wolf.health <= 0.0 else str(c.outcome)
				res[out] = int(res.get(out, 0)) + 1
				dmg_sum += maxf(0.0, hp0 - gs.wolf.health)
				if gs.wolf.has_method("is_heavily_injured") and gs.wolf.is_heavily_injured() and not heavy0:
					heavy += 1
			var n: int = maxi(1, submitted)
			print("  你 %.0f 歲 vs 黑狼 %.0f 歲：打到示弱 %d%%；追擊後 %s；追擊時受傷平均 %.0f；沒示弱就結束 %s" % [age, black_age, roundi(100.0 * submitted / runs),
				str(res.keys().map(func(k): return "%s %d%%" % [k, roundi(100.0 * int(res[k]) / n)])), dmg_sum / n, str(pre)])
	quit()
	return true
