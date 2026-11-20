extends SceneTree
# 戰術狩獵的手感量測（2026-11-16，2026-10-30 試玩回饋第 2、3 項）：
# A. 地形有沒有差別：每種地圖族（白尾鹿，體況照遊戲的比例、風向輪流），比較
#    instinct 本能（看風、繞到後方）、stalk 潛近截角、straight 直直潛行過去（不管風、不找掩蔽）、rush 小跑直衝，
#    成功率、出手時牠還沒察覺的比例、牠察覺時的距離、接近途中站在掩蔽（密林、倒木）裡的比例、回合數。
#    如果 straight 和本能差不多，表示地形、掩蔽幾乎沒有影響（「潛近到最近再出擊」就好）。
# B. 咬住之後的招式：同樣的種子先照本能打到第一次咬住（之前完全一樣），再換成各種咬住後的打法打完：
#    takedown 一直壓倒、throat 一直咬喉、best 本能（挑機率高的）、ham 先咬後腿再壓倒（從後方咬住才有）、hang2 先死咬拖住 2 回合再壓倒、hang_throat 拖住 2 回合再咬喉；
#    看獵到、掙脫、被踢的比例與回合。物種：白尾鹿（健康、普通、虛弱）、母馬鹿。
# 指標（2026-11-17 使用者：不只看成功率）：成功率、回合數（中位數）、狼受傷的場次比例、喘的消耗（平均）、獵物逃脫（逃走或不見）的比例。
# A2. 狼的狀態：年輕（1～2 歲）、壯年、老年、體力低的壯年，在開闊、林緣、密林各比較本能與直直潛行。
# D.（Phase 2o 第 3 步）地形與逃跑路線：每種地圖族，本能打法下「牠開始逃之後」逃掉（逃走、不見、你放棄）的比例；
#    同一張地圖、同一個起點的鹿，狼從西、東、北、南四個方向（離鹿約 10 格的平地）接近的成功率，差最多幾點。
# 用法：bash tools/run_sim.sh tactical_feel_sim "" 1000（第三個參數是每格的場數，預設 1000；探索用 120）；PART=A／A2／B 只跑一部分
var f := 0
var TH
var alert_set: Dictionary = {}
var tune_set: Dictionary = {}

static func _merge(a: Dictionary, b: Dictionary) -> void:
	for k in b:
		if a.has(k) and a[k] is Dictionary and b[k] is Dictionary:
			_merge(a[k], b[k])
		else:
			a[k] = b[k]

const FAMILIES := ["open", "edge", "dense", "logs", "stream", "river", "slope", "tundra"]
const WINDS := ["headwind", "crosswind", "tailwind"]
const WOLF := {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}
const PROFILES := {
	"年輕": {"speed": 64, "skill": 44, "strength": 44, "perception": 50, "stamina": 80, "health": 100, "health_max": 100},
	"壯年": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100},
	"老年": {"speed": 50, "skill": 62, "strength": 50, "perception": 55, "stamina": 60, "health": 90, "health_max": 90},
	"體力低": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 35, "health": 100, "health_max": 100},
}

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	TH = load("res://scripts/core/TacticalHunt.gd")
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 1000
	var part: String = OS.get_environment("PART")
	# 調參（Phase 2o）：ALERT_SET='{"exposed": {"mult": 2.5}}' 合併進 tactical_hunt.json 的 alert；FAMS=open,edge、POLS=instinct,straight 只跑這些
	if OS.get_environment("ALERT_SET") != "":
		alert_set = JSON.parse_string(OS.get_environment("ALERT_SET"))
	# TUNE_SET='{"herd": {"vigilance": {...}}}'：合併進整個 tactical_hunt.json
	if OS.get_environment("TUNE_SET") != "":
		tune_set = JSON.parse_string(OS.get_environment("TUNE_SET"))
	var fams: Array = OS.get_environment("FAMS").split(",") if OS.get_environment("FAMS") != "" else FAMILIES
	var pols: Array = OS.get_environment("POLS").split(",") if OS.get_environment("POLS") != "" else ["instinct", "stalk", "straight", "rush"]
	if part in ["", "A"]:
		_part_a(runs, fams, {"壯年": WOLF}, pols)
	if part in ["", "A2"]:
		_part_a(runs, ["open", "edge", "dense"], PROFILES, ["instinct", "straight"])
	if part == "H":
		_part_h(runs, fams if OS.get_environment("FAMS") != "" else ["open", "edge", "dense"])
	if part in ["", "B"]:
		_part_b(runs)
	if part == "D":
		_part_d(runs, fams if OS.get_environment("FAMS") != "" else ["open", "edge", "dense", "logs", "stream"])
	return true

func _cond(i: int) -> String:
	# 遊戲的體況比例：健康 5、普通 3、虛弱 2
	var k: int = i % 10
	return "healthy" if k < 5 else ("average" if k < 8 else "weak")

func _cover(h, c: Vector2i) -> bool:
	return str(h.terrain(c)) in ["f", "l", "T"]

# --- A ---
func _part_a(runs: int, fams: Array, profiles: Dictionary, pols: Array) -> void:
	print("== A. 地形（白尾鹿單隻、體況照遊戲比例、風向輪流；每格 %d 場）" % runs)
	print("   打法：成功率／出手時牠還沒察覺／察覺時的距離（中位數）／接近時在掩蔽裡／回合（中位數）／受傷／喘的消耗／逃脫")
	for pk in profiles:
		for fam in fams:
			var line := "%-4s %-7s" % [pk, fam]
			for pol in pols:
				var ok := 0
				var unaware_first := 0
				var first_n := 0
				var det_dist: Array = []
				var cover_r := 0
				var approach_r := 0
				var rounds: Array = []
				var hurt := 0
				var breath := 0.0
				var esc := 0
				for i in runs:
					var h = TH.new()
					if not alert_set.is_empty():
						_merge(h.t["alert"], alert_set.duplicate(true))
					if not tune_set.is_empty():
						_merge(h.t, tune_set.duplicate(true))
					h.setup_from_game({"family": fam, "seed": i * 7919 + 31, "condition": _cond(i), "wolf": profiles[pk], "wind_relation": WINDS[i % 3]})
					var p: String = pol
					if pol == "instinct":
						TacticalInstinct.pick_target(h)
						p = TacticalInstinct.pick_policy(h)
					var guard := 0
					var seen := false
					var first := true
					while not h.done and guard < 70:
						guard += 1
						var was: String = str(h.deer_state)
						var pl: int = h.pounce_log.size()
						if not h.held and was != "flee":
							approach_r += 1
							if _cover(h, h.wolf_pos):
								cover_r += 1
						_step(h, p)
						if first and h.pounce_log.size() > pl:
							first = false
							first_n += 1
							if was != "flee":
								unaware_first += 1
						if not seen and str(h.deer_state) == "flee" and was != "flee":
							seen = true
							det_dist.append(h.dist(h.wolf_pos, h.deer_pos))
					if h.result == "caught":
						ok += 1
					elif h.result in ["escaped", "lost"]:
						esc += 1
					if float(h.damage_taken) > 0.0:
						hurt += 1
					breath += float(h.breath_used)
					rounds.append(h.rounds)
				det_dist.sort()
				rounds.sort()
				line += "  %s %2d%%／%2d%%／%.1f／%2d%%／%d／%2d%%／%.0f／%2d%%" % [pol, roundi(100.0 * ok / runs), roundi(100.0 * unaware_first / maxi(1, first_n)),
					float(det_dist[det_dist.size() / 2]) if not det_dist.is_empty() else -1.0, roundi(100.0 * cover_r / maxi(1, approach_r)), rounds[rounds.size() / 2],
					roundi(100.0 * hurt / runs), breath / runs, roundi(100.0 * esc / runs)]
			print(line)

# 一步：咬住、追足跡、躲著、站定交給本能；接近照打法
func _step(h, pol: String) -> void:
	if h.held or h.track_pending or h.hidden_unfound() or (h.deer_state == "stand" and h.sp().has("stand")):
		TacticalInstinct.step(h, "stalk")
		return
	if pol in ["chase", "pace", "stalk", "ambush", "hold", "cutoff"]:
		TacticalInstinct.step(h, pol)
		return
	var targets: Dictionary = h.pounce_targets()
	if not targets.is_empty():
		var best := Vector2i(-1, -1)
		var bs := -1.0
		for c in targets:
			if float(targets[c]["chance"]) > bs:
				bs = float(targets[c]["chance"])
				best = c
		if h.deer_state == "flee" or bs >= 0.6 or pol == "rush":
			h.pounce_at(best)
			return
	var reach: Dictionary = h.reachable()
	if reach.is_empty():
		h.observe()
		return
	var modes: Array = ["creep"]
	if h.deer_state == "flee":
		modes = ["sprint", "trot", "creep"]
	elif pol == "rush":
		modes = ["trot", "creep"]
	var pick := Vector2i(-1, -1)
	var bd := 1e9
	for c in reach:
		if not str(reach[c]) in modes:
			continue
		var d: float = h.dist(c, h.deer_pos)
		if d < bd:
			bd = d
			pick = c
	if pick.x < 0 or bd >= h.dist(h.wolf_pos, h.deer_pos):
		h.observe()
		return
	h.move_to(pick)

# --- B ---
func _part_b(runs: int) -> void:
	print("== B. 咬住之後的招式（同一個種子照本能打到第一次咬住，之後換打法；每格最多 %d 場，只算有咬住的）" % runs)
	print("   打法：獵到／掙脫或鬆口後逃走／被踢的場次比例／咬住後幾回合（平均）／咬住後的喘消耗（平均）")
	# 第三個欄位 low：咬住時喘只剩 7（不夠壓倒；Phase 2o 第 2 步）
	var cases := [["deer", "healthy", ""], ["deer", "average", ""], ["deer", "weak", ""], ["elk", "healthy", ""], ["elk", "weak", ""], ["deer", "healthy", "low"], ["elk", "healthy", "low"]]
	for cs in cases:
		var line := "%-5s %-8s %-3s" % [cs[0], cs[1], cs[2]]
		var n_held := 0
		var sides := {}
		var res := {}
		for strat in ["takedown", "throat", "best", "ham1", "ham", "hang2", "hang_throat"]:
			var ok := 0
			var lost := 0
			var kicked := 0
			var hr := 0
			var nh := 0
			var hb := 0.0
			for i in runs:
				var h = TH.new()
				if not tune_set.is_empty():
					_merge(h.t, tune_set.duplicate(true))
				var ctx := {"family": "edge", "seed": i * 4421 + 7, "wolf": WOLF, "wind_relation": WINDS[i % 3]}
				if cs[0] == "elk":
					ctx["species"] = "elk"
					ctx["family"] = "edge"
				if str(cs[1]) != "":
					ctx["condition"] = cs[1]
				h.setup_from_game(ctx)
				TacticalInstinct.pick_target(h)
				var p: String = TacticalInstinct.pick_policy(h)
				var guard := 0
				while not h.done and not h.held and guard < 70:
					guard += 1
					TacticalInstinct.step(h, p)
				if not h.held:
					continue
				if str(cs[2]) == "low":
					h.breath = 7.0 # 夠咬喉（5）、不夠壓倒（8）：只剩咬喉、死咬拖住或鬆口
				nh += 1
				if strat == "takedown":
					sides[h.hold_side] = int(sides.get(h.hold_side, 0)) + 1
				var r0: int = h.rounds
				var k0: int = h.kicks
				var b0: float = float(h.breath_used)
				var n := 0
				while h.held and not h.done and guard < 90:
					guard += 1
					n += 1
					var opts: Dictionary = h.hold_options()
					var pick := "release"
					match strat:
						"takedown":
							pick = "takedown"
						"throat":
							pick = "throat"
						"best":
							TacticalInstinct.step(h, p)
							continue
						"ham1":
							pick = "hamstring" if opts.has("hamstring") and int(h.herd[h.di].get("hamstrung", 0)) < 1 and n <= 2 else "takedown"
						"ham":
							pick = "hamstring" if opts.has("hamstring") else "takedown"
						"hang2":
							pick = "hang" if n <= 2 else "takedown"
						"hang_throat":
							pick = "hang" if n <= 2 else "throat"
					if not opts.has(pick):
						pick = "release"
					h.hold_action(pick)
				# 鬆口或掙脫後照本能打完（可能再咬住）
				while not h.done and guard < 120:
					guard += 1
					TacticalInstinct.step(h, p)
				if h.result == "caught":
					ok += 1
				else:
					lost += 1
				if h.kicks > k0:
					kicked += 1
				hr += h.rounds - r0
				hb += float(h.breath_used) - b0
			n_held = nh
			line += "  %s %2d%%／%2d%%／%2d%%／%.1f／%.0f" % [strat, roundi(100.0 * ok / maxi(1, nh)), roundi(100.0 * lost / maxi(1, nh)), roundi(100.0 * kicked / maxi(1, nh)), float(hr) / maxi(1, nh), hb / maxi(1, nh)]
		print(line + "  （咬住 %d 場，位置 %s）" % [n_held, str(sides)])

# --- H. 鹿群（一生模擬裡多半是鹿群，2026-11-17）：白尾鹿 4 隻＋1 隻小鹿、母馬鹿 6 隻；狼三種年齡；本能
func _part_h(runs: int, fams: Array) -> void:
	print("== H. 鹿群（本能；每格 %d 場）：成功率／回合／受傷／逃脫" % runs)
	for sp in [["deer", 4, 1], ["elk", 6, 0]]:
		for pk in ["年輕", "壯年", "老年"]:
			var line := "%-4s %-4s" % [sp[0], pk]
			for fam in fams:
				var ok := 0
				var hurt := 0
				var esc := 0
				var rounds: Array = []
				for i in runs:
					var h = TH.new()
					if not alert_set.is_empty():
						_merge(h.t["alert"], alert_set.duplicate(true))
					if not tune_set.is_empty():
						_merge(h.t, tune_set.duplicate(true))
					var conds: Array = []
					for k in int(sp[1]):
						conds.append(_cond(i * 3 + k))
					var ctx := {"family": fam, "seed": i * 6151 + 13, "wolf": PROFILES[pk], "wind_relation": WINDS[i % 3], "herd": {"conditions": conds, "calves": int(sp[2])}}
					if sp[0] == "elk":
						ctx["species"] = "elk"
						ctx["family"] = fam
					h.setup_from_game(ctx)
					TacticalInstinct.play(h, "")
					if h.result == "caught":
						ok += 1
					elif h.result in ["escaped", "lost"]:
						esc += 1
					if float(h.damage_taken) > 0.0:
						hurt += 1
					rounds.append(h.rounds)
				rounds.sort()
				line += "  %s %2d%%／%d／%2d%%／%2d%%" % [fam, roundi(100.0 * ok / runs), rounds[rounds.size() / 2], roundi(100.0 * hurt / runs), roundi(100.0 * esc / runs)]
			print(line)


# D. 地形與逃跑路線（Phase 2o 第 3 步）：MAP=stream_3 只用這一張地圖；POLS 預設 instinct,straight
# 每個方向用同一組種子（獵物位置、體況、亂數一樣），只差狼從哪一側開始
func _part_d(runs: int, fams: Array) -> void:
	var only_map: String = OS.get_environment("MAP")
	var pols: Array = OS.get_environment("POLS").split(",") if OS.get_environment("POLS") != "" else ["instinct", "straight"]
	print("== D. 地形與逃跑路線（白尾鹿單隻、體況照遊戲比例、側風；每格 %d 場%s）" % [runs, ("，地圖 " + only_map) if only_map != "" else ""])
	print("   每個方向：獵到／追逐後逃掉（逃走、不見、放棄）／站定（被逼到）／逃跑時繞路／穿過難走地形／追逐回合／喘的消耗")
	var dirs := {"西": Vector2i(-1, 0), "東": Vector2i(1, 0), "北": Vector2i(0, -1), "南": Vector2i(0, 1)}
	if only_map != "":
		fams = [TH.new().t["maps"][only_map]["family"]]
	for fam in fams:
		for pol in pols:
			var by_dir := {}
			var lines: Array = []
			for dk in dirs:
				var ok := 0
				var fled := 0
				var fled_esc := 0
				var corner := 0
				var moves := 0
				var detour := 0
				var rough := 0
				var chase_r := 0
				var breath := 0.0
				for i in runs:
					var h = TH.new()
					if not tune_set.is_empty():
						_merge(h.t, tune_set.duplicate(true))
					if only_map != "":
						h.t["maps"] = {only_map: h.t["maps"][only_map]}
					h.setup_from_game({"family": fam, "seed": i * 7919 + 31, "condition": _cond(i), "wolf": WOLF, "wind_relation": "crosswind"})
					# 把狼放在鹿的那個方向約 10 格、最近的平地（同一張圖、同一隻鹿）
					var want: Vector2i = h.deer_pos + dirs[dk] * 10
					want = Vector2i(clampi(want.x, 1, h.width - 2), clampi(want.y, 1, h.height - 2))
					var best: Vector2i = h.wolf_pos
					var bd := INF
					for y in h.height:
						for x in h.width:
							var c := Vector2i(x, y)
							if h.terrain(c) == "." and h.dist(c, h.deer_pos) >= 6.0 and h.dist(c, want) < bd:
								bd = h.dist(c, want)
								best = c
					h.wolf_pos = best
					h.wind = h.wind_for("crosswind")
					var p: String = pol
					if pol == "instinct":
						TacticalInstinct.pick_target(h)
						p = TacticalInstinct.pick_policy(h)
					var guard := 0
					var was_flee := false
					var r0 := -1
					while not h.done and guard < 70:
						guard += 1
						_step(h, p)
						if str(h.deer_state) in ["flee", "stand"] and not was_flee:
							was_flee = true
							r0 = h.rounds
					if h.result == "caught":
						ok += 1
					if was_flee:
						fled += 1
						chase_r += h.rounds - r0
						if h.result in ["escaped", "lost", "gave_up"]:
							fled_esc += 1
						if int(h.stats.get("cornered", 0)) > 0:
							corner += 1
					moves += int(h.stats.get("flee_moves", 0))
					detour += int(h.stats.get("flee_detour", 0))
					rough += int(h.stats.get("flee_rough", 0))
					breath += float(h.breath_used)
				by_dir[dk] = roundi(100.0 * ok / runs)
				lines.append("    %s %2d%%／%2d%%／%2d%%／%2d%%／%2d%%／%.1f／%.0f" % [dk, by_dir[dk], roundi(100.0 * fled_esc / maxi(1, fled)), roundi(100.0 * corner / maxi(1, fled)),
					roundi(100.0 * detour / maxi(1, moves)), roundi(100.0 * rough / maxi(1, moves)), float(chase_r) / maxi(1, fled), breath / runs])
			var vals: Array = by_dir.values()
			vals.sort()
			print("%-7s %-9s 方向差 %d" % [fam, pol, int(vals[-1]) - int(vals[0])])
			for l in lines:
				print(l)
