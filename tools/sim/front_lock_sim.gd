extends SceneTree
# 特殊招式「前截鎖喉」的模擬（2026-10-16）：快的狼（速度 85、技巧 60）學會與沒學會，各打 RUNS 場。
# 打法：沒察覺時潛近、鹿跑了就耐力追（先小跑、鹿跑 3 回合後衝刺）；學會的狼只要有前截的格子、成功率 ≥ MIN 就出手。
# 鹿群情境（E、G）的目標固定是成鹿。統計成功率、用了幾次招式、受傷、回合數。
# 用法：bash tools/run_sim.sh front_lock_sim 0 300
const TH := preload("res://prototypes/tactical_hunt/TacticalHunt.gd")

var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 300
	var min_chance: float = float(OS.get_environment("MIN")) if OS.get_environment("MIN") != "" else 0.3
	var h = TH.new()
	print("== 前截鎖喉：快的狼（速度 85、技巧 60），每格 %d 場；學會的狼在成功率 ≥ %d%% 時出手" % [runs, roundi(min_chance * 100)])
	for sc in ["A", "C", "D", "E", "G"]:
		var line := "%s %-10s" % [sc, h.t["scenarios"][sc]["name"]]
		for knows in [false, true]:
			var ok := 0; var used := 0; var lock_kills := 0; var hurt := 0; var rounds := 0
			for i in runs:
				h.setup(sc, "fast", i * 7919 + 77)
				h.knows_front_lock = knows
				_target_adult(h)
				var guard := 0
				while not h.done and guard < 80:
					guard += 1
					_step(h, min_chance)
				if h.result == "caught":
					ok += 1
					if h.front_locks > 0 and h.reason.begins_with("你衝到"):
						lock_kills += 1
				used += h.front_locks
				if h.damage_taken > 0.0:
					hurt += 1
				rounds += h.rounds
			line += "  %s：獵到 %3d%%（鎖喉 %3d%%）、每場用 %.1f 次、受傷 %2d%%、%.1f 回合" % ["學會" if knows else "沒學會",
				roundi(100.0 * ok / runs), roundi(100.0 * lock_kills / runs), float(used) / runs, roundi(100.0 * hurt / runs), float(rounds) / runs]
		print(line)
	return true

func _target_adult(h) -> void:
	var best := -1
	var bd := INF
	for i in h.active_deer():
		if not h.is_fawn(i) and h.dist(h.herd[i]["pos"], h.wolf_pos) < bd:
			bd = h.dist(h.herd[i]["pos"], h.wolf_pos)
			best = i
	if best >= 0 and best != h.target:
		h.set_target(best)

func _step(h, min_chance: float) -> void:
	_target_adult(h)
	if h.held:
		var opts: Dictionary = h.hold_options()
		var pick := "release"
		var bc := -1.0
		for k in ["takedown", "throat"]:
			if opts.has(k) and float(opts[k]["chance"]) > bc:
				bc = float(opts[k]["chance"])
				pick = k
		h.hold_action(pick)
		return
	var fl: Dictionary = h.front_lock_targets()
	if not fl.is_empty():
		var best := Vector2i(-1, -1)
		var bc := -1.0
		for c in fl.keys():
			if float(fl[c]["chance"]) > bc:
				bc = float(fl[c]["chance"])
				best = c
		if bc >= min_chance:
			h.front_lock_at(best)
			return
	var targets: Dictionary = h.pounce_targets()
	if not targets.is_empty():
		var best := Vector2i(-1, -1)
		var bs := -1.0
		for c in targets.keys():
			var sc: float = float(targets[c]["chance"]) - float(targets[c]["kick"]) * 0.5
			if sc > bs:
				bs = sc
				best = c
		if h.deer_state == "flee" or float(targets[best]["chance"]) >= 0.6:
			h.pounce_at(best)
			return
	var reach: Dictionary = h.reachable()
	if reach.is_empty():
		h.observe()
		return
	var fleeing: bool = h.deer_state == "flee"
	if fleeing:
		var late: bool = int(h.flee_round) >= 3
		var aim: Vector2i = h.deer_pos
		# 學會的狼：往鹿的前方跑（截頭）
		if h.knows_front_lock and not h.deer_intent().is_empty():
			aim = h.deer_pos + Vector2i(h.deer_intent()[0]) * 2
		_go(h, reach, aim, ["sprint", "trot", "creep"] if late or h.knows_front_lock else ["trot", "creep"])
	elif h.dist(h.wolf_pos, h.deer_pos) > 8.0:
		_go(h, reach, h.deer_pos, ["trot", "creep"])
	else:
		_go(h, reach, h.deer_pos - h.deer_facing, ["creep"])

func _go(h, reach: Dictionary, target: Vector2i, modes: Array) -> void:
	var best := Vector2i(-1, -1)
	var best_score := INF
	for c in reach.keys():
		if not modes.has(reach[c]):
			continue
		var s: float = h.dist(c, target)
		if s < best_score:
			best_score = s
			best = c
	if best == Vector2i(-1, -1) or best_score >= h.dist(h.wolf_pos, target) - 0.01:
		h.observe()
	else:
		h.move_to(best)
