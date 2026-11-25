extends SceneTree
# 地圖尺寸的對照（2026-11-25，docs/proposals/hunt-escape-edge.md「40×16 是否擴大成 40×40」）：
# 開闊、林緣、密林、倒木四族，地圖換成 tools/make_tactical_maps.py --size 40xH 產生的版本，壯年狼、單隻白尾鹿、交給本能，
# 狼與鹿的起始距離照舊（8～11 格）。印每種尺寸 × 地圖族：
#   成功率、逃掉（跑出邊緣、逃滿 10 回合、跟丟）、牠開始逃之後的回合（平均）、狼與鹿最遠距離（中位數）、撲咬次數（平均）、
#   狼改變移動方向的次數（平均）、逃跑時繞路的比例、從哪一邊跑出去（W／E／N／S）、一場的回合（中位數）。
# 用法：MAPS=檔案.json EXITS=all bash tools/run_sim.sh tactical_size_sim "" 300
#   FLEE_ROUNDS=14 換逃跑回合的上限（預設 10）；MAPS 不給就用 tactical_hunt.json 原本的地圖；EXITS=all 四邊都可以跑出去（預設照舊只有左右）；FAMS=open,dense 只跑一部分
var f := 0
const WOLF := {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}
const WINDS := ["headwind", "crosswind", "tailwind"]

func _cond(i: int) -> String:
	var r := i % 10
	return "weak" if r < 2 else ("healthy" if r >= 7 else "average")

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 300
	var maps: Dictionary = {}
	var mp: String = OS.get_environment("MAPS")
	if mp != "":
		maps = JSON.parse_string(FileAccess.get_file_as_string(mp))
	var all_exits: bool = OS.get_environment("EXITS") == "all"
	var fams: Array = OS.get_environment("FAMS").split(",") if OS.get_environment("FAMS") != "" else ["open", "edge", "dense", "logs"]
	var size_txt := "40x16"
	if not maps.is_empty():
		var any: Dictionary = maps.values()[0]
		size_txt = "%dx%d" % [String(any["map"][0]).length(), (any["map"] as Array).size()]
	print("== tactical_size_sim：%s，%s，逃跑上限 %s 回合，每格 %d 場" % [size_txt, "四邊都可以跑出去" if all_exits else "只有左右可以跑出去", OS.get_environment("FLEE_ROUNDS") if OS.get_environment("FLEE_ROUNDS") != "" else "10", runs])
	print("   成功／逃掉（邊緣／10回合／跟丟）／逃跑回合／最遠距離／撲咬／轉向／繞路／出口 W E N S／回合")
	for fam in fams:
		var ok := 0
		var why := {"edge": 0, "rounds": 0, "lost_edge": 0, "other": 0}
		var chase := 0
		var fled := 0
		var far: Array = []
		var pounces := 0
		var turns := 0
		var moves := 0
		var detour := 0
		var sides := {"W": 0, "E": 0, "N": 0, "S": 0}
		var rounds: Array = []
		for i in runs:
			var h = TH.new()
			if not maps.is_empty():
				h.t["maps"] = maps.duplicate(true)
			if all_exits:
				h.t["deer"]["exit_all_edges"] = true
			if OS.get_environment("FLEE_ROUNDS") != "":
				h.t["deer"]["max_flee_rounds"] = int(OS.get_environment("FLEE_ROUNDS"))
			h.setup_from_game({"family": fam, "seed": i * 7919 + 31, "condition": _cond(i), "wolf": WOLF, "wind_relation": WINDS[i % 3]})
			TacticalInstinct.pick_target(h)
			var p: String = TacticalInstinct.pick_policy(h)
			var guard := 0
			var r0 := -1
			var maxd := 0.0
			var last_dir := Vector2i.ZERO
			var wp: Vector2i = h.wolf_pos
			while not h.done and guard < 90:
				guard += 1
				if h.held or h.track_pending or h.hidden_unfound() or (h.deer_state == "stand" and h.sp().has("stand")):
					TacticalInstinct.step(h, "stalk")
				else:
					TacticalInstinct.step(h, p)
				if r0 < 0 and str(h.deer_state) in ["flee", "stand"]:
					r0 = h.rounds
				if not h.done:
					maxd = maxf(maxd, h.dist(h.wolf_pos, h.deer_pos))
				if h.wolf_pos != wp:
					var dv: Vector2i = h.wolf_pos - wp
					var d1 := Vector2i(signi(dv.x), signi(dv.y))
					if last_dir != Vector2i.ZERO and d1 != last_dir:
						turns += 1
					last_dir = d1
					wp = h.wolf_pos
			if h.result == "caught":
				ok += 1
			elif h.result in ["escaped", "lost"]:
				var w: String = str(h.stats.get("end_why", "other"))
				why[w] = int(why.get(w, 0)) + 1
				if h.stats.has("exit_side"):
					sides[str(h.stats["exit_side"])] += 1
			if r0 >= 0:
				fled += 1
				chase += h.rounds - r0
			far.append(maxd)
			pounces += h.pounce_log.size()
			moves += int(h.stats.get("flee_moves", 0))
			detour += int(h.stats.get("flee_detour", 0))
			rounds.append(h.rounds)
		far.sort()
		rounds.sort()
		var esc: int = int(why["edge"]) + int(why["rounds"]) + int(why["lost_edge"]) + int(why["other"])
		var sd := 0
		for k in sides:
			sd += int(sides[k])
		print("%-6s %2d%%／%2d%%（%2d／%2d／%2d）／%.1f／%.1f／%.2f／%.1f／%2d%%／%s／%d" % [fam, roundi(100.0 * ok / runs), roundi(100.0 * esc / runs),
			roundi(100.0 * why["edge"] / runs), roundi(100.0 * why["rounds"] / runs), roundi(100.0 * why["lost_edge"] / runs),
			float(chase) / maxi(1, fled), float(far[far.size() / 2]), float(pounces) / runs, float(turns) / runs, roundi(100.0 * detour / maxi(1, moves)),
			" ".join(["W", "E", "N", "S"].map(func(k): return "%d%%" % roundi(100.0 * sides[k] / maxi(1, sd)))), rounds[rounds.size() / 2]])
	quit()
	return true
