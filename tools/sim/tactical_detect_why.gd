extends SceneTree
# 戰術狩獵：鹿是被什麼驚動的（Phase 2o 第 1 步的診斷）。每種地圖族 × 打法，記 detect_cause（scent 聞到、noise 看到或聽到、close 太近、missed 撲空…）、
# 驚動前警覺的來源合計（看見、聞到、聽到），以及開始逃時的距離。
# 用法：RUNS=300 bash tools/run_sim.sh tactical_detect_why
var f := 0
func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var FS = load("res://tools/sim/tactical_feel_sim.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 300
	var wolf := {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}
	var winds := ["headwind", "crosswind", "tailwind"]
	for fam in ["open", "edge", "dense"]:
		for pol in ["instinct", "straight"]:
			var causes := {}
			var src := {"sight": 0.0, "scent": 0.0, "hear": 0.0}
			for i in runs:
				var h = TH.new()
				h.setup_from_game({"family": fam, "seed": i * 7919 + 31, "condition": "average", "wolf": wolf, "wind_relation": winds[i % 3]})
				var p: String = pol
				if pol == "instinct":
					TacticalInstinct.pick_target(h)
					p = TacticalInstinct.pick_policy(h)
				var guard := 0
				while not h.done and guard < 70 and h.deer_state != "flee" and not h.held:
					guard += 1
					var m: String = str(h.last_mode)
					var g: Dictionary = h.alert_gain(m if m in ["creep", "trot", "sprint", "still"] else "still")
					src["scent"] += float(g["scent"])
					src["sight"] += float(g["noise"]) - _hear(h, m)
					src["hear"] += _hear(h, m)
					if p == "straight":
						_straight(h)
					else:
						TacticalInstinct.step(h, p)
				var c: String = str(h.detect_cause) if h.detect_cause != "" else ("held" if h.held else "none")
				causes[c] = int(causes.get(c, 0)) + 1
			print("%-6s %-9s 驚動：%s  警覺來源合計：看見 %.0f、聞到 %.0f、聽到 %.0f" % [fam, pol, str(causes), src["sight"] / runs, src["scent"] / runs, src["hear"] / runs])
	return true

func _hear(h, m: String) -> float:
	return h._band(h.t["alert"].get("hearing", {}).get(m, []), h.dist(h.wolf_pos, h.deer_pos))

func _straight(h) -> void:
	var targets: Dictionary = h.pounce_targets()
	if not targets.is_empty():
		var best := Vector2i(-1, -1)
		var bs := -1.0
		for c in targets:
			if float(targets[c]["chance"]) > bs:
				bs = float(targets[c]["chance"])
				best = c
		if bs >= 0.6:
			h.pounce_at(best)
			return
	var reach: Dictionary = h.reachable()
	var pick := Vector2i(-1, -1)
	var bd := 1e9
	for c in reach:
		if str(reach[c]) != "creep":
			continue
		var d: float = h.dist(c, h.deer_pos)
		if d < bd:
			bd = d
			pick = c
	if pick.x < 0 or bd >= h.dist(h.wolf_pos, h.deer_pos):
		h.observe()
		return
	h.move_to(pick)
