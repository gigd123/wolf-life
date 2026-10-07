extends SceneTree
# 狩獵成功率依狼的能力（1.7 第 3、4 步）：次成年 40、成年 60、巔峰 78 的狼，對每種獵物各狩獵 RUNS 次。
# 每個階段選成功率最高的選項；追擊階段可用 CHASE 環境變數固定方式（follow／sprint／空白 = 最高成功率）。
# 印出：整體成功率、進入搏鬥的比例、搏鬥第一口的平均成功率、平均受傷。
# 用法：bash tools/run_sim.sh hunt_levels 0 300　　CHASE=follow bash tools/run_sim.sh hunt_levels 0 300

const STAGE_DONE := 5
const STAGE_CHASE := 2
const STAGE_FIGHT := 3
const LEVELS := [["次成年", 40.0], ["成年", 60.0], ["巔峰", 78.0]]
const PREY := [["white_tailed_deer", "juvenile"], ["white_tailed_deer", "adult"], ["white_tailed_deer", "buck"], ["red_fox", "adult"],
	["caribou", "juvenile"], ["caribou", "adult"], ["moose", "juvenile"], ["moose", "adult"]]

func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if v != "" else fallback

func _process(_d):
	var GS = root.get_node("GameState")
	GS.new_game("forest_east")
	GS.auto_playing = true
	var runs := _env_int("RUNS", 300)
	var chase_mode := OS.get_environment("CHASE")
	print("== hunt_levels：每格 %d 次，追擊方式 %s" % [runs, chase_mode if chase_mode != "" else "最高成功率"])
	for lv in LEVELS:
		var line := "[%s %d]" % [lv[0], int(lv[1])]
		print(line)
		for spec in PREY:
			var wins := 0; var fights := 0; var first_bite := 0.0; var dmg := 0.0; var chase_rounds := 0
			for i in runs:
				var v: float = lv[1]
				GS.wolf.stamina = 100; GS.wolf.health_max = 100; GS.wolf.health = 100; GS.wolf.hunger = 80
				GS.wolf.speed = v; GS.wolf.strength = v; GS.wolf.skill = v; GS.wolf.perception = v
				GS.wolf.clear_injury()
				var terrains: Array = ["treeline", "open_tundra", "river_willow", "rocky", "esker"] if spec[0] in ["caribou", "moose"] else ["stream", "dense_forest", "forest_edge", "clearing", "fallen_logs"]
				var h = GS.start_hunt(spec[0], spec[1], -1, false, terrains[i % terrains.size()])
				var g := 0
				var fought := false
				var hp0: float = GS.wolf.health
				while h.stage != STAGE_DONE and g < 30:
					g += 1
					var opts: Array = h.options()
					var best: Dictionary = {}
					for opt in opts:
						if not opt.has("chance"): continue
						if h.stage == STAGE_CHASE and chase_mode != "" and opt["id"] == chase_mode:
							best = opt; break
						if best.is_empty() or float(opt["chance"]) > float(best["chance"]): best = opt
					if best.is_empty(): break
					if h.stage == STAGE_FIGHT and not fought:
						fought = true
						fights += 1
						first_bite += float(best["chance"])
					h.choose(best["id"])
				chase_rounds += h.chase_round
				dmg += hp0 - GS.wolf.health
				if h.result == 1: wins += 1
				GS.finish_hunt(h); GS.clear_discovery(); GS.current_feeding = {}
			print("   %-26s 成功 %3.0f%%  進入搏鬥 %3.0f%%  搏鬥第一口 %3.0f%%  追擊回合 %.2f  受傷 %.1f" % [spec[0] + "/" + spec[1],
				100.0 * wins / runs, 100.0 * fights / runs, (100.0 * first_bite / fights) if fights > 0 else 0.0, float(chase_rounds) / runs, dmg / runs])
	quit()
	return true
