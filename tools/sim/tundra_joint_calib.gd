extends SceneTree
# Phase 2i 第 3 步：苔原狼一起狩獵的主遊戲開法校準（GameState.start_hunt + start_tactical，體況照季節擲）。
# 同一隻成年狼（一般、快）在苔原（SEASON，預設 autumn），比較：
#   單狼（觀察、挑最弱的再交給本能，同自動玩家）／單狼本能／跟上來（本能）／加入（本能）／加入（選單式，改版前的對照）
# 獵物：馴鹿（主遊戲照季節成群）、駝鹿。每格 RUNS 場（預設 60）。
# 用法：bash tools/run_sim.sh tundra_joint_calib；RUNS=100；SET='{"join_dist": 3}' 覆寫 tactical_hunt.json allies.game（校準用）
var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var HS = load("res://scripts/core/HuntSystem.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 60
	gs.new_game("tundra_south")
	gs.debug_force_transition("adult")
	var season: String = OS.get_environment("SEASON") if OS.get_environment("SEASON") != "" else "autumn"
	gt.season_index = gt.SEASONS.find(season)
	var wolves := {"一般": {"speed": 62.0, "skill": 58.0, "strength": 65.0, "perception": 65.0}, "快": {"speed": 80.0, "skill": 68.0, "strength": 72.0, "perception": 72.0}}
	var ap = AP.new("all", "average")
	ap.tactical = false
	print("== 苔原狼一起狩獵（主遊戲開法，%s 的苔原，每格 %d 場；本能的打法；苔原狼 2 隻）" % [season, runs])
	for wk in wolves.keys():
		for animal in ["caribou", "moose"]:
			var line := "  %-4s %-8s" % [wk, animal]
			for mode in ["solo_best", "solo", "follow", "join", "join_menu"]:
				var ok := 0
				var rounds := 0
				for i in runs:
					for st in wolves[wk].keys():
						gs.debug_set_stat(st, float(wolves[wk][st]))
					gs.debug_set_stat("age_years", 4.0)
					gs.wolf.stamina = 80.0
					gs.wolf.health = gs.wolf.health_max
					gs.wolf.clear_injury()
					var h = gs.start_hunt(animal, "adult", -1, false, "open_tundra")
					if mode in ["follow", "join", "join_menu"]:
						h.apply_tundra_help(2, mode != "follow")
					if mode == "join_menu":
						var guard := 0
						while h.stage != HS.Stage.DONE and guard < 25:
							guard += 1
							var opt: Dictionary = ap._pick_option(h)
							if opt.is_empty():
								h.give_up()
								break
							h.choose(str(opt["id"]))
						if h.result == HS.Result.SUCCESS:
							ok += 1
						continue
					var th = gs.start_tactical(h)
					if mode == "solo_best":
						th.observe()
					TacticalInstinct.play(th)
					rounds += th.rounds
					if th.result == "caught":
						ok += 1
				line += "  %s %3d%%" % [{"solo_best": "單狼觀察", "solo": "單狼本能", "follow": "跟上來", "join": "加入", "join_menu": "加入(選單)"}[mode], roundi(100.0 * ok / runs)]
				if mode != "join_menu":
					line += "（%.1f）" % (float(rounds) / runs)
			print(line)
	quit()
	return true
