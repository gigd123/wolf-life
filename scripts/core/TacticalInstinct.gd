class_name TacticalInstinct
extends RefCounted

# 戰術狩獵的自動打法（Phase 2c 第 3 步「交給本能」）：從 tools/sim/tactical_hunt_sim.gd 搬來，
# 主遊戲的「交給本能」按鈕、自動玩家與照常過日子、模擬共用。
# 策略：chase 猛追、pace 耐力追（鹿跑 3 回合後才衝）、stalk 潛近截角、ambush 伏擊；dumb_sprint／dumb_pounce 是模擬用的對照。
# 本能（pick_policy）依風向挑：上風 → 耐力追；其他 → 潛近截角（模擬裡下風、林緣、倒木旁都是潛近最好）。
# hold 等同伴趕（苔原狼的群體狩獵實驗）：潛到 6 格內就停下等，獵物被趕過來時截住。
# cutoff 截斷退路（旱獺，Phase 2g）：逃向一格洞口的獵物（species.refuge_pounce），先繞到牠和洞口之間、站上洞口，再潛近；本能在牠就在洞口邊時用它，離洞遠時潛近。
# 本能比自己打差一些（SPEC 2c：約低一成）：交給本能之後，撲咬、壓倒、咬喉扣 game.instinct_penalty（出手比較莽撞）。

const POLICIES := ["chase", "pace", "stalk", "ambush"]

# 依局面挑一種打法（本能）。
static func pick_policy(h) -> String:
	# 有苔原狼同伴（Phase 2i；含還沒跟上來的）：獵物已經在逃或沒有驅趕的 → 一起猛追；會站定的大型獵物（駝鹿）猛追、看出虛弱潛近；
	# 其他（鹿群）等驅趕（tactical_ally_sim，每格 30 場：馴鹿群 等著趕 80%／猛追 73%，白尾鹿群 63／67%，馬鹿群 57／60%，健康駝鹿 猛追 20%，虛弱駝鹿 潛近 60%）
	var roles: Array = []
	for w in h.wolves:
		if bool(w.get("ally", false)):
			roles.append(str(w["role"]))
	for pa in h.pending_allies:
		roles.append(str(pa["role"]))
	# 同伴都是你的狼群（伴侶、子女，Phase 3 第 3、7 步）：照單狼的打法，伴侶自己照角色行動（mate_hunt_sim：一隻同伴時「等驅趕」「猛追」都不如單狼的潛近、跟著）
	if not roles.is_empty() and h.own_ally_count() == roles.size():
		roles = [] # 同伴都是你的狼群（第 7 步：好幾隻也一樣）
	if not roles.is_empty():
		if h.deer_state == "flee" or not roles.has("drive"):
			return "chase"
		if h.sp().has("stand"):
			return "stalk" if h.condition_known and h.condition == "weak" else "chase"
		return "hold"
	# 逃向一格洞口的獵物（旱獺）：牠就在洞口邊才先截斷退路；離洞遠的直接潛近（模擬：遠的時候繞去洞口太慢，Phase 2g）
	var rp: Dictionary = h.sp().get("refuge_pounce", {})
	if not rp.is_empty():
		var hole: Vector2i = h._open_hole(h.deer_pos)
		return "cutoff" if hole.x >= 0 and h.dist(hole, h.deer_pos) <= float(rp["dist"]) else "stalk"
	if h.wind_side() == "upwind":
		return "pace"
	return "stalk"

# 鹿群裡挑目標（Phase 2d 第 2 步）：觀察後標出最弱的那一隻就挑牠；沒有的話挑小鹿；都沒有就照原本的。
static func pick_target(h) -> void:
	if h.held or h.herd.size() <= 1:
		return
	for i in h.active_deer():
		if bool(h.herd[i].get("weakest", false)):
			h.set_target(i)
			return
	if h.is_fawn(h.target):
		return
	var best := -1
	for i in h.active_deer():
		if h.is_fawn(i) and (best < 0 or h.dist(h.herd[i]["pos"], h.wolf_pos) < h.dist(h.herd[best]["pos"], h.wolf_pos)):
			best = i
	if best >= 0:
		h.set_target(best)

# 從現在的局面打到結束（中途按「交給本能」也可以）。pol 空字串時由本能挑。
static func play(h, pol: String = "") -> void:
	pick_target(h)
	if pol == "":
		pol = pick_policy(h)
		h.game_mods["instinct_penalty"] = float(h.t.get("game", {}).get("instinct_penalty", 0.0))
	var guard := 0
	while not h.done and guard < 60:
		guard += 1
		step(h, pol)

static func step(h, pol: String) -> void:
	# 目標在密林裡不見了（Phase 2m）：追上的機率夠、喘也夠才追
	if h.track_pending:
		var tc: Dictionary = h._track_cfg()
		if float(h.track_chance()["chance"]) >= float(tc.get("instinct_min_chance", 0.4)) and h.breath >= h.breath_max * float(tc.get("instinct_min_breath", 0.3)):
			h.follow_track()
		else:
			h.give_up_track()
		return
	# 咬住了（Phase 2o 第 2 步：照情況挑招）：
	#   累了、受傷的 → 壓倒、咬喉挑機率高的（咬喉這時最有效）；健康的大型獵物 → 先咬後腿削弱；喘不夠 → 死咬拖住撐著；都做不到就鬆口
	if h.held:
		var opts: Dictionary = h.hold_options()
		var pick := "release"
		var bc := -1.0
		for k in ["takedown", "throat"]:
			if opts.has(k) and float(opts[k]["chance"]) > bc:
				bc = float(opts[k]["chance"])
				pick = k
		var hams: int = int(h.herd[h.di].get("hamstrung", 0))
		var tired: bool = h.deer_fatigue_any() >= 0.5 or h.wounds >= 2
		if not tired and h._large_healthy() and opts.has("hamstring") and hams < 1:
			pick = "hamstring"
		elif h.sp().has("hold") and bc < float(h.t["game"].get("instinct_wear_down", 0.3)):
			# 大型獵物（物種有咬住後的加減）機會太小：先咬後腿、再不行就死咬拖住，把牠拖垮
			if opts.has("hamstring"):
				pick = "hamstring"
			elif opts.has("hang"):
				pick = "hang"
		# 喘不夠壓倒（Phase 2o 第 2 步）：咬喉的機會夠就咬喉，不然死咬拖住（回一點喘、牠踢不太到你、越掙扎越累），撐到喘夠再壓倒
		if not opts.has("takedown") and h.hold_short.has("takedown") and opts.has("hang"):
			pick = "throat" if opts.has("throat") and float(opts["throat"]["chance"]) >= 0.35 else "hang"
		# 苔原狼在旁邊（群體狩獵實驗）：牠們一起拖倒的機會比自己出手好，就死咬拖住
		if opts.has("hang") and float(opts["hang"].get("ally_takedown_any", 0.0)) > bc:
			pick = "hang"
		h.hold_action(pick)
		return
	# 躲在草裡、還沒看出牠在哪（Phase 2i 第 6 步）：走到草叢外 HIDDEN_WATCH 格左右觀察；看不出來就潛近去找（可能把牠驚起來）。躲著的幼鹿不會聞到你，不用避開上風
	if h.hidden_unfound():
		_hidden_step(h)
		return
	# 站定的大型獵物（Phase 2f）：看出是健康的就放棄（照生態幾乎打不下來）；否則繞到側面、後方再撲，站太久就放棄
	if h.deer_state == "stand" and h.sp().has("stand"):
		_stand_step(h)
		return
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
		# 出手的門檻：物種可以覆寫（趴著不動的兔子撲咬機率本來就不高，等下去只會讓牠發現，2026-10-22）
		# 等同伴趕（hold）：被逼到角落站定的獵物也撲（不然會一直等下去）
		if pol.begins_with("dumb") or pol == "chase" or h.deer_state == "flee" or (pol == "hold" and h.deer_state == "stand") \
				or float(targets[best]["chance"]) >= float(h.sp().get("instinct_pounce_at", 0.6)):
			h.pounce_at(best)
			return
	var reach: Dictionary = h.reachable()
	if reach.is_empty():
		h.observe()
		return
	var fleeing: bool = h.deer_state == "flee"
	# 苔原狼咬住、拖住了獵物（群體狩獵實驗）：不管哪種打法都衝過去一起咬
	if h.wolves.size() > 1 and h._ally_holding() > 0:
		_go(h, reach, h.deer_pos, ["sprint", "trot", "creep"])
		return
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
		"hold":
			# 等同伴趕（群體狩獵實驗）：沒察覺時潛到 hold_dist 格內就停下等（同伴繞到另一側把獵物趕過來）；
			# 被趕過來時只潛行迎上去（衝出去就沒有埋伏的加成；撲出去那一下可以衝），其他時候截住
			if fleeing and h._driven():
				_go(h, reach, _predict(h), ["creep"])
			elif fleeing:
				_go(h, reach, _predict(h), ["sprint", "trot", "creep"])
			elif h.dist(h.wolf_pos, h.deer_pos) > 6.0:
				_go(h, reach, h.deer_pos, ["creep"], true)
			elif int(h.rounds) >= 12:
				# 等太久同伴還沒趕過來：自己潛近
				_go(h, reach, _behind(h), ["creep"], true)
			else:
				h.observe()
		"cutoff":
			var hole := _refuge_cell(h)
			if fleeing:
				_go(h, reach, _predict(h), ["sprint", "trot", "creep"])
			elif hole == Vector2i(-1, -1) or h.wolf_pos == hole:
				_go(h, reach, h.deer_pos, ["creep"], true)
			else:
				_go(h, reach, hole, ["trot", "creep"] if h.dist(h.wolf_pos, h.deer_pos) > 6.0 else ["creep"], true)
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

const HIDDEN_WATCH := 3.5 # 離草叢中心幾格就停下來觀察
const HIDDEN_TRIES := 1 # 觀察幾次看不出來就走進去找（再看的機會越來越小）

static func _hidden_step(h) -> void:
	var center: Vector2 = Vector2(h.hidden_area.position) + Vector2(h.hidden_area.size) * 0.5 - Vector2(0.5, 0.5)
	var d: float = Vector2(h.wolf_pos).distance_to(center)
	var tries: int = int(h.stats.get("hidden_observes", 0))
	if d > HIDDEN_WATCH + 0.5:
		var reach: Dictionary = h.reachable()
		if reach.is_empty():
			h.observe()
			return
		_go(h, reach, Vector2i(center.round()), ["trot", "creep"] if d > 8.0 else ["creep"])
		return
	if tries < HIDDEN_TRIES:
		h.observe()
		return
	var reach2: Dictionary = h.reachable()
	if reach2.is_empty():
		h.observe()
		return
	_go(h, reach2, Vector2i(center.round()), ["creep"])

# 往目標走：在允許的方式裡挑離目標最近的格子；avoid_wind 時避開上風。
const STAND_GIVE_UP := 6 # 站定幾回合還繞不到好角度就放棄
const STAND_WALL := 3 # 鹿群裡幾隻站定就算站成一道牆

static func _stand_step(h) -> void:
	if (h.condition_known and h.condition == "healthy") or int(h.herd[h.target].get("stand_rounds", 0)) > STAND_GIVE_UP:
		h.give_up()
		return
	# 整群站成一道牆（3 隻以上站定，野牛，Phase 2f 第 3 步）、或已經被撞或踢了兩下：不硬上
	var standing := 0
	for i in h.active_deer():
		if not h.is_fawn(i) and str(h.herd[i]["state"]) == "stand":
			standing += 1
	if standing >= STAND_WALL or h.kicks >= 2:
		h.give_up()
		return
	# 側面、後方而且機會夠的撲；正面不撲
	var targets: Dictionary = h.pounce_targets()
	var best := Vector2i(-1, -1)
	var bs := -1.0
	for c in targets.keys():
		var info: Dictionary = targets[c]
		if str(info["side"]) == "front":
			continue
		var sc: float = float(info["chance"]) - float(info["kick"]) * 0.5
		if sc > bs:
			bs = sc
			best = c
	if best.x >= 0 and float(targets[best]["chance"]) >= 0.35:
		h.pounce_at(best)
		return
	# 往牠身後兩格繞（小跑、潛行；牠每回合只轉 45°）
	var rear: Vector2i = h.deer_pos - h.deer_facing * 2
	_go(h, h.reachable(), rear, ["trot", "creep"])

static func _go(h, reach: Dictionary, target: Vector2i, modes: Array, avoid_wind: bool = false) -> void:
	var best := Vector2i(-1, -1)
	var best_score := INF
	for c in reach.keys():
		if not modes.has(reach[c]):
			continue
		var s: float = h.dist(c, target)
		if avoid_wind:
			s += _wind_penalty(h, c) + _cover_penalty(h, c)
			# 掩蔽路線（Phase 2o 第 1 步）：目標是牠本身時，改用「經過暴露的格子比較貴」的路線距離
			if target == h.deer_pos and _stealth_on(h):
				s = float(_stealth_map(h).get(c, 999.0)) + _wind_penalty(h, c)
		if s < best_score:
			best_score = s
			best = c
	var here: float = h.dist(h.wolf_pos, target) + ((_wind_penalty(h, h.wolf_pos) + _cover_penalty(h, h.wolf_pos)) if avoid_wind else 0.0)
	if avoid_wind and target == h.deer_pos and _stealth_on(h):
		here = float(_stealth_map(h).get(h.wolf_pos, 999.0)) + _wind_penalty(h, h.wolf_pos)
	if best == Vector2i(-1, -1) or best_score >= here - 0.01:
		h.observe()
		return
	# 等時機（Phase 2o 第 1 步）：接近時下一步會暴露在開闊地、牠就在附近又沒在吃草 → 先等牠低頭（最多連等 PATIENCE 回合）
	var waits: int = int(h.game_mods.get("_instinct_waits", 0))
	if avoid_wind and h.deer_state in ["unaware", "suspicious"] and (h.cover_state(best) == "exposed" or h.cover_state(h.wolf_pos) == "exposed") and not _watcher_grazing(h) \
			and h.dist(best, h.deer_pos) <= PATIENT_DIST and waits < PATIENCE:
		h.game_mods["_instinct_waits"] = waits + 1
		h.observe()
		return
	h.game_mods["_instinct_waits"] = 0
	h.move_to(best)

const PATIENCE := 4 # 在開闊地最多連等幾回合牠低頭

# 等時機看的是離你最近、還沒在逃的那一隻（鹿群裡最可能看到你的；單隻就是目標）有沒有低頭吃草
static func _watcher_grazing(h) -> bool:
	var best := -1
	var bd := INF
	for i in h.active_deer():
		var d: float = h.dist(h.herd[i]["pos"], h.wolf_pos)
		if d < bd:
			bd = d
			best = i
	return h.grazing(best if best >= 0 else -1)
const EXPOSED_COST := 3.0 # 掩蔽路線：經過暴露的格子一格算幾格

# 有沒有掩蔽的設定（沒有就照原本的找路）；牠還沒在逃
static func _stealth_on(h) -> bool:
	return not (h.t["alert"].get("cover", {}) as Dictionary).is_empty() and h.deer_state in ["unaware", "suspicious"]

# 從牠的位置往外的路線距離：暴露的格子 × EXPOSED_COST、掩蔽 × 0.8，地形照走路的代價；每回合、牠的位置不變時用算好的
static func _stealth_map(h) -> Dictionary:
	var key: String = "%d|%s" % [h.rounds, str(h.deer_pos)]
	if str(h.game_mods.get("_stealth_key", "")) == key:
		return h.game_mods["_stealth_map"]
	# Dial 式的桶子（代價 × 4 取整當桶子的序號），比每次掃一遍找最小的快很多（40×16 格、每回合算一次）
	# 每一格的掩蔽倍率先算好
	var mults := {}
	for y in h.height:
		for x in h.width:
			var c := Vector2i(x, y)
			var cs0: String = h.cover_state(c)
			mults[c] = EXPOSED_COST if cs0 == "exposed" else (0.8 if cs0 == "in" else 1.0)
	var dist := {h.deer_pos: 0.0}
	var buckets: Array = [[h.deer_pos]]
	var bi := 0
	while bi < buckets.size():
		var bucket: Array = buckets[bi]
		var k := 0
		while k < bucket.size():
			var cur: Vector2i = bucket[k]
			k += 1
			if roundi(float(dist[cur]) * 4.0) != bi:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var n: Vector2i = cur + d
				if not h.in_bounds(n):
					continue
				var nd: float = float(dist[cur]) + h.step_cost(cur, n) * float(mults[n])
				if nd < float(dist.get(n, 1e9)):
					dist[n] = nd
					var nb: int = maxi(bi, roundi(nd * 4.0))
					while buckets.size() <= nb:
						buckets.append([])
					(buckets[nb] as Array).append(n)
		bi += 1
	h.game_mods["_stealth_key"] = key
	h.game_mods["_stealth_map"] = dist
	return dist

const PATIENT_DIST := 12.0 # 離牠幾格內才等

# 接近時的掩蔽（Phase 2o 第 1 步）：在聞得到、看得到的距離內，暴露的格子不利、掩蔽裡有利。
# 兩者的差（0.9）要小於潛行前進一格（1），不然站在掩蔽裡就永遠不出來
static func _cover_penalty(h, c: Vector2i) -> float:
	if h.dist(c, h.deer_pos) > 9.0:
		return 0.0
	match h.cover_state(c):
		"exposed":
			return 0.6
		"in":
			return -0.3
	return 0.0

# 站在上風（氣味吹向鹿）而且在聞得到的距離內：很不利
static func _wind_penalty(h, c: Vector2i) -> float:
	var v := Vector2(h.deer_pos - c)
	if v.length() > 9.0:
		return 0.0
	return 12.0 if v.normalized().dot(Vector2(h.wind).normalized()) > 0.5 else 0.0

# 鹿接下來大概在哪：意圖的第一個方向 × 下一回合的格數
static func _predict(h) -> Vector2i:
	var intent: Array = h.deer_intent()
	if intent.is_empty():
		return h.deer_pos
	var d: Vector2i = intent[0]
	return h.deer_pos + d * int(h._flee_budget())

# 鹿的側後方（潛近的目標）
static func _behind(h) -> Vector2i:
	return h.deer_pos - h.deer_facing

# 獵物會逃進去的那一格（離牠最近的 seek 地形：旱獺的洞口）；沒有就 (-1, -1)
static func _refuge_cell(h) -> Vector2i:
	var ter: String = str(h.sp().get("seek", {}).get("terrain", ""))
	var best := Vector2i(-1, -1)
	var bd := INF
	if ter == "":
		return best
	for y in h.height:
		for x in h.width:
			var c := Vector2i(x, y)
			if h.terrain(c) == ter and h.dist(c, h.deer_pos) < bd:
				bd = h.dist(c, h.deer_pos)
				best = c
	return best

# 伏擊點：鹿的目的地附近、離目的地最近的掩蔽（密林、倒木）
static func _cover_near(h) -> Vector2i:
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
