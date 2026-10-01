extends SceneTree
# 狩獵結果統計（SPEC「獵物反應」「狩獵深度分級」）：固定能力 40 的狼對每種獵物各狩獵 400 次，
# 每個階段選成功率最高的選項；印出反應分布、成功／逃走次數、平均追擊回合、受傷與事件，
# 並檢查所有選項、因素、結果文字是否都有翻譯（MISSING 應該是空的）。
# 用法：bash tools/run_sim.sh hunt_outcomes

const STAGE_DONE := 5

func _check(k: String, missing: Dictionary) -> void:
	if k != "" and tr(k) == k: missing[k] = true
func _process(_d):
	var GS = root.get_node("GameState")
	GS.new_game("forest_east")
	var missing := {}
	for spec in [["hare","adult",false],["white_tailed_deer","juvenile",false],["white_tailed_deer","adult",false],["white_tailed_deer","buck",false],["white_tailed_deer","adult",true],["red_fox","adult",false]]:
		var reactions := {}; var res := {}; var rounds := 0; var dmg := 0.0; var notes := {}
		for i in 400:
			GS.wolf.stamina = 100; GS.wolf.health = 100; GS.wolf.hunger = 60; GS.wolf.speed = 40; GS.wolf.strength = 40; GS.wolf.skill = 40; GS.wolf.perception = 40
			var h = GS.start_hunt(spec[0], spec[1], -1, false, ["stream","dense_forest","forest_edge","clearing","fallen_logs"][i % 5], spec[2])
			reactions[h.reaction] = reactions.get(h.reaction, 0) + 1
			var g := 0
			while h.stage != STAGE_DONE and g < 30:
				g += 1
				var best: Dictionary = {}
				for opt in h.options():
					_check(opt["label_key"], missing)
					for f in opt.get("factors", []): _check(f["key"], missing)
					if opt.has("chance") and (best.is_empty() or float(opt["chance"]) > float(best["chance"])): best = opt
				var sr: Dictionary = h.choose(best["id"])
				_check(sr.get("text_key", ""), missing); _check(sr.get("reason_key", ""), missing)
				for n in sr.get("notes", []):
					notes[n] = notes.get(n, 0) + 1; _check(n, missing)
				dmg += float(sr.get("damage", 0.0))
				if h.stage == 2: _check(h.wolf_stamina_key(), missing); _check(h.prey_stamina_key(), missing)
			if g >= 30: res["stuck"] = res.get("stuck", 0) + 1
			rounds += h.chase_round
			res[h.result] = res.get(h.result, 0) + 1
			for k in h.prey_state_keys(): _check(k, missing)
			GS.finish_hunt(h); GS.clear_discovery()
		print("%s/%s%s reactions=%s results(1=win,2=fled)=%s avg_chase_rounds=%.2f avg_dmg=%.1f notes=%s" % [spec[0], spec[1], " injured" if spec[2] else "", reactions, res, float(rounds)/400, dmg/400, notes])
	print("MISSING ", missing.keys())
	print("life_log ", GS.life_log.get("hunt_attempts"), " ", GS.life_log.get("hunt_successes"))
	quit(); return true
