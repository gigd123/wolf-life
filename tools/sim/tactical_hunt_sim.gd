extends SceneTree
# 戰術狩獵原型的模擬（docs/proposals/tactical-hunt-prototype.md 第十節）。
# 固定策略的自動玩家 × 4 個情境 × 3 種狼，各 RUNS 個種子；驗證測試 1～5、7、8、10。
# 用法：bash tools/run_sim.sh tactical_hunt_sim 0 300
const TH := preload("res://prototypes/tactical_hunt/TacticalHunt.gd")
const POLICIES := ["chase", "stalk", "ambush", "dumb_sprint", "dumb_pounce"]
const POLICY_NAMES := {"chase": "猛追", "stalk": "潛近截角", "ambush": "伏擊", "dumb_sprint": "每回合衝刺", "dumb_pounce": "相鄰就撲"}

var f := 0

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 10
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 150
	var h = TH.new()
	print("== 戰術狩獵模擬（每格 %d 場）" % runs)
	var totals := {"stuck": 0, "toward": 0, "games": 0}
	var rounds_all: Array = []
	for profile in ["slow", "normal", "fast"]:
		for stamina in [1.0, 0.5]:
			print("\n-- 狼：%s，體力 %s" % [{"slow": "慢（速度 40）", "normal": "普通（60）", "fast": "快（85）"}[profile], "滿" if stamina == 1.0 else "一半"])
			print("情境        " + "  ".join(POLICIES.map(func(p): return "%-8s" % POLICY_NAMES[p])))
			for sc in ["A", "B", "C", "D"]:
				var row: Array = []
				for pol in POLICIES:
					var ok := 0
					var breath := 0.0
					for i in runs:
						h.setup(sc, profile, i * 7919 + 13, stamina)
						_play(h, pol)
						if h.result == "caught":
							ok += 1
						breath += h.breath_used
						totals["stuck"] += int(h.stats["stuck"])
						totals["toward"] += int(h.stats["toward_wolf"])
						totals["games"] += 1
						if profile == "normal" and stamina == 1.0:
							rounds_all.append(h.rounds)
					row.append("%3d%% 喘%3d" % [roundi(100.0 * ok / runs), roundi(breath / runs)])
				print("%s %-8s " % [sc, h.t["scenarios"][sc]["name"]] + "  ".join(row))
	rounds_all.sort()
	print("\n回合數（普通狼、體力滿、全部策略）：中位數 %d、90%% %d、最多 %d" % [rounds_all[rounds_all.size() / 2], rounds_all[int(rounds_all.size() * 0.9)], rounds_all.back()])
	print("鹿卡住（來回）%d 次、逃跑時往狼的方向 %d 次（共 %d 場）" % [totals["stuck"], totals["toward"], totals["games"]])
	_speed_tiers(h, runs)
	return true

# 測試 10：距離 5 格時被察覺，猛追，幾回合追上
func _speed_tiers(h, runs: int) -> void:
	for pol in ["chase", "pace"]:
		_speed_tier_rows(h, runs, pol)

func _speed_tier_rows(h, runs: int, pol: String) -> void:
	print("\n-- 速度分級：距離 5 格被察覺後%s（開闊地）" % ("猛追（一開始就衝刺）" if pol == "chase" else "耐力追（先小跑跟著，鹿慢下來再衝）"))
	for profile in ["slow", "normal", "fast"]:
		var caught := 0
		var by_round := {}
		for i in runs:
			h.setup("A", profile, i * 104729 + 7)
			h.wolf_pos = h.deer_pos - Vector2i(5, 0)
			h.deer_facing = Vector2i(1, 0)
			h._start_flee("close")
			h._deer_turn() # 察覺的那一回合鹿先跑（和實際流程一樣）
			var start: int = h.rounds
			_play(h, pol)
			if h.result == "caught":
				caught += 1
				var r: int = h.rounds - start
				by_round[r] = int(by_round.get(r, 0)) + 1
		var keys := by_round.keys()
		keys.sort()
		print("%s：追上 %d%%，回合分布 %s" % [profile, roundi(100.0 * caught / runs), ", ".join(keys.map(func(k): return "%d回:%d" % [k, by_round[k]]))])

# --- 策略 ---

func _play(h, pol: String) -> void:
	var guard := 0
	while not h.done and guard < 60:
		guard += 1
		_step(h, pol)

func _step(h, pol: String) -> void:
	var targets: Dictionary = h.pounce_targets()
	if not targets.is_empty():
		# 挑命中率最高（聰明的策略也看被踢的風險）的那一格；聰明的策略在鹿還沒逃、機率不到 60% 時先不撲
		var best := Vector2i(-1, -1)
		var bs := -1.0
		for c in targets.keys():
			var info: Dictionary = targets[c]
			var sc: float = float(info["chance"]) - (0.0 if pol.begins_with("dumb") else float(info["kick"]) * 0.5)
			if sc > bs:
				bs = sc
				best = c
		if pol.begins_with("dumb") or pol == "chase" or h.deer_state == "flee" or float(targets[best]["chance"]) >= 0.6:
			h.pounce_at(best)
			return
	var reach: Dictionary = h.reachable()
	if reach.is_empty():
		h.observe()
		return
	var fleeing: bool = h.deer_state == "flee"
	match pol:
		"dumb_sprint":
			_go(h, reach, h.deer_pos, ["sprint", "trot", "creep"])
		"dumb_pounce":
			_go(h, reach, h.deer_pos, ["trot", "creep"])
		"chase":
			_go(h, reach, h.deer_pos, ["sprint", "trot", "creep"] if fleeing else ["trot", "creep"])
		"pace":
			# 耐力追：鹿跑了 3 回合以上（開始慢下來）才衝刺，之前小跑跟著
			var late: bool = fleeing and int(h.flee_round) >= 3
			_go(h, reach, h.deer_pos, ["sprint", "trot", "creep"] if late else ["trot", "creep"])
		"stalk":
			if fleeing:
				_go(h, reach, _predict(h), ["sprint", "trot", "creep"])
			elif h.dist(h.wolf_pos, h.deer_pos) > 8.0:
				_go(h, reach, h.deer_pos, ["trot", "creep"], true)
			else:
				_go(h, reach, _behind(h), ["creep"], true)
		"ambush":
			if fleeing:
				_go(h, reach, _predict(h), ["sprint", "trot", "creep"])
			else:
				var cover := _cover_near(h)
				if h.wolf_pos == cover or cover == Vector2i(-1, -1):
					if h.dist(h.wolf_pos, h.deer_pos) <= 2.5:
						_go(h, reach, h.deer_pos, ["creep"], true)
					else:
						h.observe()
				else:
					_go(h, reach, cover, ["creep"] if h.dist(h.wolf_pos, h.deer_pos) <= 8.0 else ["trot", "creep"], true)

# 往目標走：在允許的方式裡挑離目標最近的格子；avoid_wind 時避開上風。
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

# 站在上風（氣味吹向鹿）而且在聞得到的距離內：很不利
func _wind_penalty(h, c: Vector2i) -> float:
	var v := Vector2(h.deer_pos - c)
	if v.length() > 9.0:
		return 0.0
	return 12.0 if v.normalized().dot(Vector2(h.wind).normalized()) > 0.5 else 0.0

# 鹿接下來大概在哪：意圖的第一個方向 × 下一回合的格數
func _predict(h) -> Vector2i:
	var intent: Array = h.deer_intent()
	if intent.is_empty():
		return h.deer_pos
	var d: Vector2i = intent[0]
	return h.deer_pos + d * int(h._flee_budget())

# 鹿的側後方（潛近的目標）
func _behind(h) -> Vector2i:
	return h.deer_pos - h.deer_facing

# 伏擊點：鹿的目的地附近、離目的地最近的掩蔽（密林、倒木）
func _cover_near(h) -> Vector2i:
	var goal: Vector2i = h.deer_goal()
	var best := Vector2i(-1, -1)
	var bd := INF
	for y in h.height:
		for x in h.width:
			var c := Vector2i(x, y)
			if h.terrain(c) in ["f", "l"] and c != h.deer_pos:
				var d: float = h.dist(c, goal)
				if d < bd:
					bd = d
					best = c
	return best if bd <= 5.0 else Vector2i(-1, -1)
