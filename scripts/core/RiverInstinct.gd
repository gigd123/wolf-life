class_name RiverInstinct
extends RefCounted

# 河岸模式的自動打法（Phase 2h 第 4 步）：模擬校準用，第 5 步的自動玩家與照常過日子用 adaptive。
# camp     死守魚最多的淺灘：被趕開就走回去（被威嚇也不讓）
# far      躲最遠：挑離熊最遠、有魚的淺灘，一直撲
# adaptive 照局勢換位：挑熊的威嚇範圍外（多留 1 格）魚最多的淺灘；被威嚇就馬上換；附近安全的吃剩的魚順手撿
# 每個 step 做一個戰術回合的行動（移動或撲魚）；吃到 stop_at 就離開。

static func step(rf, policy: String, stop_at: float = 150.0) -> void:
	if rf.done:
		return
	if rf.hunger >= stop_at or rf.hunger >= rf.hunger_max:
		rf.leave()
		return
	var goal := _goal(rf, policy)
	if goal.x < 0:
		rf.leave()
		return
	if rf.wolf_pos == goal and rf.can_fish():
		rf.fish_once()
		return
	if rf.wolf_pos == goal:
		# 站在目標上卻不能撲（被威嚇）：camp 硬待著（等著被趕開），其他換位
		if policy == "camp":
			rf.wait()
		else:
			_walk(rf, _goal(rf, policy, true), true)
		return
	_walk(rf, goal, policy != "camp")

static func _goal(rf, policy: String, avoid_current: bool = false) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -INF
	# adaptive：安全的吃剩的魚在 6 格內，先去撿
	if policy == "adaptive":
		for c in rf.leftovers:
			if rf._bear_threat_dist(c) > 1 and Vector2(c - rf.wolf_pos).length() <= 6.0:
				return c
	for y in rf.height:
		for x in rf.width:
			var c := Vector2i(x, y)
			var q: int = rf.fish_at(c)
			if q <= 0 or rf.bear_at(c) >= 0:
				continue
			if avoid_current and c == rf.wolf_pos:
				continue
			var dist: float = Vector2(c - rf.wolf_pos).length()
			var score := 0.0
			match policy:
				"camp":
					score = q * 100.0 - dist
				"far":
					score = float(mini(rf._bear_threat_dist(c), 30)) * 10.0 + q - dist * 0.01
				_:
					if rf._bear_threat_dist(c) <= 1:
						continue
					score = q * 100.0 - dist * 2.0
			if score > best_score:
				best_score = score
				best = c
	return best

# 往目標走一步：在走得到的格子裡挑離目標最近的；careful 時避開熊的威嚇範圍
static func _walk(rf, goal: Vector2i, careful: bool) -> void:
	if goal.x < 0:
		rf.leave()
		return
	var reach: Dictionary = rf.reachable()
	var best := Vector2i(-1, -1)
	var bd := INF
	for c in reach.keys():
		if careful and rf._bear_threat_dist(c) <= 0:
			continue
		var d: float = Vector2(c - goal).length()
		if d < bd:
			bd = d
			best = c
	if best.x < 0:
		rf.wait()
		return
	rf.move_to(best)
