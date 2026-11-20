extends SceneTree
# 躲在草裡的幼體被驚起之後追不追得上（2026-11-20 試玩回報 Bug #6）：物種 × 地圖族 × 狼，本能打法，每格 RUNS 場。
# 印：獵到、被驚起的比例、驚起後獵到、驚起後第一回合幼體跑幾格與狼能衝幾格。
# TUNE_SET='{"special": {...}}' 合併進 tactical_hunt.json（試驚起的加成、幼體的逃跑格數）。
# 用法：RUNS=300 bash tools/run_sim.sh tactical_young_bolt（SPECIES=mule_deer FAMS=slope,edge 只跑一部分）
# 叉角羚的幼體在主遊戲是 pronghorn_kid、沒有母親（game.no_mother），這裡照主遊戲開
var f := 0

static func _merge(a: Dictionary, b: Dictionary) -> void:
	for k in b:
		if a.has(k) and a[k] is Dictionary and b[k] is Dictionary:
			_merge(a[k], b[k])
		else:
			a[k] = b[k]

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 300
	var tune: Dictionary = JSON.parse_string(OS.get_environment("TUNE_SET")) if OS.get_environment("TUNE_SET") != "" else {}
	var wolves := {
		"1歲": {"speed": 58, "skill": 42, "strength": 42, "perception": 48, "stamina": 70, "health": 90, "health_max": 90},
		"1歲累": {"speed": 58, "skill": 42, "strength": 42, "perception": 48, "stamina": 30, "health": 90, "health_max": 90},
		"成年": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}}
	var sps: Array = OS.get_environment("SPECIES").split(",") if OS.get_environment("SPECIES") != "" else ["deer", "elk", "mule_deer", "pronghorn_kid"]
	var fams: Array = OS.get_environment("FAMS").split(",") if OS.get_environment("FAMS") != "" else ["open", "edge", "dense", "slope"]
	for sp in sps:
		for fam in fams:
			var line := "%-10s %-6s" % [sp, fam]
			for wk in wolves:
				var ok := 0
				var bolted := 0
				var ok_b := 0
				var run1 := 0.0
				var dash := 0.0
				for i in runs:
					var h = TH.new()
					if not tune.is_empty():
						_merge(h.t, tune.duplicate(true))
					var ctx := {"family": fam, "seed": i * 331 + 9, "wolf": wolves[wk], "wind_relation": "crosswind", "fawn": sp != "pronghorn_kid",
						"herd": {"calf_alone": true}, "hidden": true, "hidden_detection": 30}
					if sp != "deer":
						ctx["species"] = sp
					h.setup_from_game(ctx)
					# 和 TacticalInstinct.play 一樣先挑目標與打法（2026-11-20：原本傳空字串，狼追得很差，驚起後的成功率被低估）
					TacticalInstinct.pick_target(h)
					var pol: String = TacticalInstinct.pick_policy(h)
					h.game_mods["instinct_penalty"] = float(h.t.get("game", {}).get("instinct_penalty", 0.0))
					var was_b := false
					var guard := 0
					while not h.done and guard < 60:
						guard += 1
						var before: bool = bool(h.herd[h.target].get("bolted", false))
						var p0: Vector2i = h.deer_pos
						TacticalInstinct.step(h, pol)
						if not before and bool(h.herd[h.target].get("bolted", false)):
							was_b = true
							run1 += h.dist(p0, h.deer_pos)
							dash += float(h.move_budget("sprint")) if h.has_method("move_budget") else 0.0
					if was_b:
						bolted += 1
					if h.result == "caught":
						ok += 1
						if was_b:
							ok_b += 1
				line += "  %s 獵到%2d%% 驚起%2d%% 驚起後%2d%%（幼體跑%.1f）" % [wk, roundi(100.0 * ok / runs), roundi(100.0 * bolted / runs), roundi(100.0 * ok_b / maxi(1, bolted)), run1 / maxi(1, bolted)]
			print(line)
	return true
