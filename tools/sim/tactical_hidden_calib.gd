extends SceneTree
# Phase 2i 第 6 步：躲在草裡的幼鹿改走戰術地圖的校準。夏季（叉角羚春夏），每種會躲的幼體（discovery.json hidden_young）：
# 選單式（自動玩家的選法，一開始就要搜尋）／戰術地圖（交給本能：走到草叢外觀察，看不出來就潛近去找）。
# 感知 PERC（預設 45,60,80,95；其他能力照一般的成年狼）。另外印出戰術地圖裡：看出來／走近看見／驚起來的比例、平均回合數。
# 通過標準（SPEC Phase 2i）：感知 45 和 80 的成功率差 15～25 個百分點；感知 80 時和選單式差 10 個百分點以內。
# 用法：bash tools/run_sim.sh tactical_hidden_calib 0 100（第三個參數是每格場數）；PERC=45,80；SET='{"hidden": {"observe_div": 100}}' 覆寫 tactical_hunt.json game
var f := 0

const PREY := [["white_tailed_deer", "forest_edge", "forest_east", "summer"], ["elk", "clearing", "forest_east", "summer"],
	["mule_deer", "rolling_hills", "grassland_hills", "summer"], ["pronghorn", "prairie", "grassland_plains", "spring"]]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var gs = root.get_node("GameState")
	var gt = root.get_node("GameTime")
	var AP = load("res://scripts/core/AutoPlayer.gd")
	var HS = load("res://scripts/core/HuntSystem.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 80
	var percs: Array = Array(OS.get_environment("PERC").split(",")) if OS.get_environment("PERC") != "" else ["45", "60", "80", "95"]
	if OS.get_environment("SET") != "":
		gs.tactical_overrides = {"game": JSON.parse_string(OS.get_environment("SET"))}
	# STATS='{"strength": 84, "skill": 77, "speed": 61, "perception": 70, "age_years": 5}'：換成一生模擬裡的狼（Phase 2i 第 7 步）
	var over: Dictionary = JSON.parse_string(OS.get_environment("STATS")) if OS.get_environment("STATS") != "" else {}
	var ap = AP.new("all", "average")
	ap.tactical = false
	print("== 躲在草裡的幼鹿：選單式 vs 戰術地圖（交給本能），一般的成年狼換感知，每格 %d 場" % runs)
	for p in PREY:
		gs.new_game(p[2])
		gs.debug_force_transition("adult")
		gt.season_index = gt.SEASONS.find(p[3])
		for pc in percs:
			var res := {"menu": 0, "tac": 0}
			var st := {"bolt_caught": 0, "look": 0, "walk": 0, "bolt": 0, "rounds": 0, "never": 0}
			for mode in ["menu", "tac"]:
				for i in runs:
					for s in [["speed", 62.0], ["skill", 58.0], ["strength", 65.0], ["perception", float(pc)], ["age_years", 4.0]]:
						gs.debug_set_stat(s[0], float(over.get(s[0], s[1])))
					gs.wolf.stamina = 80.0
					gs.wolf.health = gs.wolf.health_max
					gs.wolf.clear_injury()
					var h = gs.start_hunt(p[0], "juvenile", -1, false, p[1], false, true)
					if mode == "menu":
						var guard := 0
						while h.stage != HS.Stage.DONE and guard < 25:
							guard += 1
							var opt: Dictionary = ap._pick_option(h)
							if opt.is_empty():
								h.give_up()
								break
							h.choose(str(opt["id"]))
						if h.result == HS.Result.SUCCESS:
							res[mode] += 1
					else:
						var th = gs.start_tactical(h)
						TacticalInstinct.play(th)
						st["rounds"] += th.rounds
						var obs: int = int(th.stats.get("hidden_observes", 0))
						if int(th.stats.get("hidden_bolt", 0)) > 0:
							st["bolt"] += 1
							if th.result == "caught":
								st["bolt_caught"] += 1
						elif int(th.stats.get("hidden_found_walk", 0)) > 0:
							st["walk"] += 1
						elif th.hidden_revealed:
							st["look"] += 1
						else:
							st["never"] += 1
							if OS.get_environment("WHY") != "":
								print("    沒找到：", th.result, " ", th.reason, " 回合 ", th.rounds, " 觀察 ", obs)
						if th.result == "caught":
							res[mode] += 1
			print("  %-18s 感知 %-3s 選單 %3d%%  戰術 %3d%%  差 %+3d ｜ 看出 %2d%% 走近看見 %2d%% 驚起 %2d%%（獵到 %d）沒找到 %2d%%（%.1f 回合）" % [p[0], pc,
				roundi(100.0 * res["menu"] / runs), roundi(100.0 * res["tac"] / runs), roundi(100.0 * (res["tac"] - res["menu"]) / runs),
				roundi(100.0 * st["look"] / runs), roundi(100.0 * st["walk"] / runs), roundi(100.0 * st["bolt"] / runs), st["bolt_caught"], roundi(100.0 * st["never"] / runs), float(st["rounds"]) / runs])
	quit()
	return true
