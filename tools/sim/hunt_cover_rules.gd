extends SceneTree
# Phase 2o 第 1 步：掩蔽與接近路線的規則。
# 站在掩蔽裡潛行，被看見的警覺比較少；暴露在開闊地比較多；牠低頭吃草時比較少；小跑不受掩蔽影響；
# 開闊、林緣、溪流的地圖有掩蔽帶；本能在開闊地會等牠低頭（不會一直等）。
# 用法：bash tools/run_sim.sh hunt_cover_rules
var f := 0
var fails := 0

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _set_ter(h, c: Vector2i, ch: String) -> void:
	if not h.in_bounds(c):
		return
	var row: String = h.grid[c.y]
	h.grid[c.y] = row.substr(0, c.x) + ch + row.substr(c.x + 1)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var h = TH.new()
	h.setup_from_game({"family": "open", "seed": 11, "condition": "average",
		"wolf": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}, "wind_relation": "crosswind"})
	var al: Dictionary = h.t["alert"]
	_ok(not al.get("cover", {}).is_empty(), "tactical_hunt.json 的 alert 有 cover 設定")
	# 把狼放在離鹿 4 格、側風；地圖周圍清空成開闊
	h.deer_state = "unaware"
	h.herd[h.di]["grazing"] = false
	var dp: Vector2i = h.deer_pos
	var wp := Vector2i(clampi(dp.x - 4, 1, h.width - 2), dp.y)
	if wp == dp:
		wp = Vector2i(clampi(dp.x + 4, 1, h.width - 2), dp.y)
	h.wolf_pos = wp
	# 這一格與周圍：先全部改成開闊，量暴露；再把狼那一格改成密林，量掩蔽
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			_set_ter(h, wp + Vector2i(dx, dy), ".")
	_ok(h.cover_state() == "exposed", "四周都是開闊地：暴露（%s）" % h.cover_state())
	var exposed: float = float(h.alert_gain("creep")["noise"])
	_set_ter(h, wp + Vector2i(1, 1), "f")
	var plain: float = float(h.alert_gain("creep")["noise"])
	_ok(h.cover_state() == "", "旁邊有一叢灌木：不算暴露也不算掩蔽")
	_set_ter(h, wp, "f")
	_ok(h.cover_state() == "in", "站在密林裡：在掩蔽裡")
	var covered: float = float(h.alert_gain("creep")["noise"])
	_ok(covered < plain and plain < exposed, "潛行被看見：掩蔽 %.1f < 一般 %.1f < 暴露 %.1f" % [covered, plain, exposed])
	var trot_c: float = float(h.alert_gain("trot")["noise"])
	_set_ter(h, wp, ".")
	var trot_p: float = float(h.alert_gain("trot")["noise"])
	_ok(absf(trot_c - trot_p) < 0.01, "小跑不受掩蔽影響（%.1f／%.1f）" % [trot_c, trot_p])
	h.herd[h.di]["grazing"] = true
	var graze: float = float(h.alert_gain("creep")["noise"])
	_ok(graze < plain * 0.75, "牠低頭吃草時比較不會看到（%.1f < %.1f）" % [graze, plain])
	h.herd[h.di]["grazing"] = false
	# 吃草的旗標：沒察覺時有時停下吃草
	var grazed := 0
	for i in 40:
		h.deer_state = "unaware"
		h._deer_wander()
		if h.grazing():
			grazed += 1
	_ok(grazed > 5 and grazed < 35, "沒察覺的鹿有時低頭吃草（40 回合 %d 次）" % grazed)
	# 地圖有掩蔽帶
	for fam in ["open", "edge", "stream"]:
		for id in h.t["maps"]:
			var m: Dictionary = h.t["maps"][id]
			if str(m["family"]) != fam:
				continue
			var cov := 0
			for row in m["map"]:
				cov += String(row).count("f") + String(row).count("l")
			_ok(cov >= 40, "%s 有掩蔽（%d 格）" % [id, cov])
	# 本能在開闊地等牠低頭，但不會一直等
	var waited := 0
	var stalled := 0
	for sd in 30:
		var h2 = TH.new()
		h2.setup_from_game({"family": "open", "seed": sd * 31 + 5, "condition": "average",
			"wolf": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}, "wind_relation": "crosswind"})
		var run := 0
		var maxrun := 0
		var guard := 0
		while not h2.done and guard < 70:
			guard += 1
			var r0: Vector2i = h2.wolf_pos
			var was: String = str(h2.deer_state)
			TacticalInstinct.step(h2, "stalk")
			if h2.wolf_pos == r0 and was in ["unaware", "suspicious"] and not h2.held and not h2.done:
				run += 1
				maxrun = maxi(maxrun, run)
			else:
				run = 0
		if int(h2.game_mods.get("_instinct_waits", 0)) > 0 or maxrun > 0:
			waited += 1
		if maxrun > 6:
			stalled += 1
	_ok(waited > 0, "本能有時在開闊地停下來等（%d／30 場）" % waited)
	_ok(stalled <= 2, "本能不會一直等（連等超過 6 回合 %d 場）" % stalled)
	print("掩蔽與接近路線的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
