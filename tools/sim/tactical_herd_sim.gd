extends SceneTree
# 戰術狩獵原型・鹿群版的模擬（docs/proposals/tactical-hunt-herd.md 第六節）。
# 五種打法 × 情境 E～H × 三種狼，各 RUNS 場；統計成功率、獵到幼鹿／成鹿、期望肉量、生母護幼、受傷、回合數，並對照通過標準。
# 用法：bash tools/run_sim.sh tactical_herd_sim 0 150
const TH := preload("res://prototypes/tactical_hunt/TacticalHunt.gd")
const POLICIES := ["fawn", "fawn_back", "adult", "scatter", "pace"]
const NAMES := {"fawn": "專挑幼鹿", "fawn_back": "幼鹿・母鹿來就退", "adult": "挑成鹿", "scatter": "衝散再挑", "pace": "耐力追"}
const SCEN := ["E", "F", "G", "H"]
const PROFILES := ["slow", "normal", "fast"]

var f := 0
var scatter_phase := {}

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 150
	var h = TH.new()
	print("== 鹿群版模擬（每格 %d 場）" % runs)
	var rounds_all: Array = []
	var fawn_tries := 0; var fawn_defended := 0
	var hurt := {"fawn": [0, 0], "adult": [0, 0]} # 撲幼鹿／撲成鹿策略：[受傷場數, 場數]
	var verdict: Array = []
	for sc in SCEN:
		print("\n-- 情境 %s %s" % [sc, h.t["scenarios"][sc]["name"]])
		print("  狼     " + "  ".join(POLICIES.map(func(p): return "%-16s" % NAMES[p])))
		var best_by_profile := {}
		for profile in PROFILES:
			var row: Array = []
			var meats := {}
			for pol in POLICIES:
				var ok := 0; var fawns := 0; var meat := 0; var defs := 0; var dmg := 0.0; var injured := 0
				for i in runs:
					h.setup(sc, profile, i * 7919 + 31)
					scatter_phase[0] = false
					_play(h, pol)
					if h.result == "caught":
						ok += 1
						if h.caught_kind == "fawn":
							fawns += 1
					meat += h.meat
					defs += h.defends
					dmg += h.damage_taken
					if h.damage_taken > 0.0:
						injured += 1
					if profile == "normal":
						rounds_all.append(h.rounds)
					if pol in ["fawn", "fawn_back"]:
						fawn_tries += 1
						if h.defends > 0:
							fawn_defended += 1
					var hk: String = "fawn" if pol == "fawn" else ("adult" if pol == "adult" else "")
					if hk != "":
						hurt[hk][1] += 1
						if h.damage_taken > 0.0:
							hurt[hk][0] += 1
				meats[pol] = float(meat) / runs
				row.append("%3d%%(幼%2d) 肉%.2f 傷%2d%%" % [roundi(100.0 * ok / runs), roundi(100.0 * fawns / max(1, ok)), float(meat) / runs, roundi(100.0 * injured / runs)])
			print("  %-6s " % profile + "  ".join(row))
			var ranked: Array = POLICIES.duplicate()
			ranked.sort_custom(func(a, b): return float(meats[a]) > float(meats[b]))
			best_by_profile[profile] = ranked[0]
			var top: float = float(meats[ranked[0]]); var second: float = float(meats[ranked[1]])
			verdict.append("%s/%s：最好 %s（肉 %.2f）、第二 %s（%.2f，差 %d%%）" % [sc, profile, NAMES[ranked[0]], top, NAMES[ranked[1]], second, roundi(100.0 * (top - second) / max(0.01, top))])
		var uniq := {}
		for p in best_by_profile.values():
			uniq[p] = true
		verdict.append("  %s：三種狼的最好打法 %s" % [sc, "不同（通過）" if uniq.size() > 1 else "都是「%s」（不通過）" % NAMES[best_by_profile.values()[0]]])
	rounds_all.sort()
	print("\n== 對照通過標準")
	for v in verdict:
		print("  " + v)
	print("  專挑幼鹿時生母護幼的比例：%d%%（標準 ≥ 50%%）" % roundi(100.0 * fawn_defended / max(1, fawn_tries)))
	print("  受傷比例：專挑幼鹿 %d%%、挑成鹿 %d%%（標準：幼鹿 ≥ 2 倍）" % [roundi(100.0 * hurt["fawn"][0] / max(1, hurt["fawn"][1])), roundi(100.0 * hurt["adult"][0] / max(1, hurt["adult"][1]))])
	print("  回合數（普通狼）：中位數 %d、90%% %d（標準中位數 8～15）" % [rounds_all[rounds_all.size() / 2], rounds_all[int(rounds_all.size() * 0.9)]])
	return true

# --- 打法 ---

func _play(h, pol: String) -> void:
	var guard := 0
	while not h.done and guard < 80:
		guard += 1
		_step(h, pol)

func _nearest(h, want_fawn: bool) -> int:
	var best := -1
	var bd := INF
	for i in h.active_deer():
		if h.is_fawn(i) != want_fawn:
			continue
		var d: float = h.dist(h.herd[i]["pos"], h.wolf_pos)
		if d < bd:
			bd = d
			best = i
	return best

func _pick_target(h, pol: String) -> void:
	if h.held:
		return
	var t := -1
	match pol:
		"fawn", "fawn_back", "pace":
			t = _nearest(h, true)
		"adult":
			t = _nearest(h, false)
		"scatter":
			# 散開後挑落單的幼鹿，其次最近的幼鹿、成鹿
			for i in h.active_deer():
				if h.is_fawn(i) and bool(h.herd[i]["separated"]):
					t = i
			if t < 0:
				t = _nearest(h, true)
	if t < 0:
		t = _nearest(h, false) if pol != "adult" else _nearest(h, true)
	if t >= 0 and t != h.target:
		h.set_target(t)

func _step(h, pol: String) -> void:
	_pick_target(h, pol)
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
	var reach: Dictionary = h.reachable()
	# 幼鹿・母鹿來就退：護幼的母鹿在旁邊時先退開
	if pol == "fawn_back":
		for i in h.active_deer():
			if not h.is_fawn(i) and int(h.herd[i]["defend_rounds"]) > 0 and h._cheb(h.herd[i]["pos"], h.wolf_pos) <= 1:
				_away(h, reach, h.herd[i]["pos"])
				return
	var targets: Dictionary = h.pounce_targets()
	if not targets.is_empty():
		var best := Vector2i(-1, -1)
		var bs := -1.0
		for c in targets.keys():
			var info: Dictionary = targets[c]
			var sc: float = float(info["chance"]) - float(info["kick"]) * 0.5
			if sc > bs:
				bs = sc
				best = c
		if h.deer_state == "flee" or float(targets[best]["chance"]) >= 0.55 or pol in ["fawn", "scatter"]:
			h.pounce_at(best)
			return
	if reach.is_empty():
		h.observe()
		return
	var fleeing: bool = h.deer_state == "flee"
	match pol:
		"fawn", "fawn_back":
			if fleeing:
				_go(h, reach, _predict(h), ["sprint", "trot", "creep"])
			elif h.dist(h.wolf_pos, h.deer_pos) > 6.0:
				_go(h, reach, h.deer_pos, ["trot", "creep"], true)
			else:
				_go(h, reach, h.deer_pos, ["creep"], true)
		"adult":
			if fleeing:
				_go(h, reach, _predict(h), ["sprint", "trot", "creep"])
			elif h.dist(h.wolf_pos, h.deer_pos) > 8.0:
				_go(h, reach, h.deer_pos, ["trot", "creep"], true)
			else:
				_go(h, reach, h.deer_pos - h.deer_facing, ["creep"], true)
		"scatter":
			if not scatter_phase[0]:
				# 先潛近到 5 格內，再衝進鹿群中心
				var center := Vector2.ZERO
				var n := 0
				for i in h.active_deer():
					center += Vector2(h.herd[i]["pos"])
					n += 1
				var c := Vector2i((center / max(1, n)).round())
				if h.dist(h.wolf_pos, c) > 5.0 and not fleeing:
					_go(h, reach, c, ["trot", "creep"], true)
				else:
					scatter_phase[0] = true
					_go(h, reach, c, ["sprint", "trot"])
			else:
				_go(h, reach, _predict(h) if fleeing else h.deer_pos, ["sprint", "trot", "creep"])
		"pace":
			var late: bool = fleeing and int(h.flee_round) >= 3
			_go(h, reach, h.deer_pos, ["sprint", "trot", "creep"] if late else ["trot", "creep"])

func _go(h, reach: Dictionary, target: Vector2i, modes: Array, avoid_wind: bool = false) -> void:
	var best := Vector2i(-1, -1)
	var best_score := INF
	for c in reach.keys():
		if not modes.has(reach[c]):
			continue
		var s: float = h.dist(c, target)
		if avoid_wind:
			s += _wind_penalty(h, c)
		if s < best_score:
			best_score = s
			best = c
	var here: float = h.dist(h.wolf_pos, target) + (_wind_penalty(h, h.wolf_pos) if avoid_wind else 0.0)
	if best == Vector2i(-1, -1) or best_score >= here - 0.01:
		h.observe()
	else:
		h.move_to(best)

# 退開：離 from 最遠的潛行／小跑格
func _away(h, reach: Dictionary, from: Vector2i) -> void:
	var best := Vector2i(-1, -1)
	var bd := -1.0
	for c in reach.keys():
		if reach[c] == "sprint":
			continue
		var d: float = h.dist(c, from)
		if d > bd:
			bd = d
			best = c
	if best == Vector2i(-1, -1):
		h.observe()
	else:
		h.move_to(best)

func _wind_penalty(h, c: Vector2i) -> float:
	var v := Vector2(h.deer_pos - c)
	if v.length() > 9.0:
		return 0.0
	return 12.0 if v.normalized().dot(Vector2(h.wind).normalized()) > 0.5 else 0.0

func _predict(h) -> Vector2i:
	var intent: Array = h.deer_intent()
	if intent.is_empty():
		return h.deer_pos
	var d: Vector2i = intent[0]
	return h.deer_pos + d * int(h._flee_budget())
