extends SceneTree
# Phase 2n 第 1 步的規則檢查（火場原型）：
# 水、岩石不會燒；火往下風燒得比上風快；強風比微風快；燃燒 → 剛燒過 → 冷卻的焦土；這一回合才燒起來的草地下一回合還在燒；
# 煙往下風飄、微風時在水邊積聚；火星先落下、之後才燒，不會落在狼身上；
# 站在燃燒的格子受燒傷、深水裡的熱比較少；燃燒的格子走不過去；只有站在邊上才能離開、往在燒的那一邊是 into_fire；
# 煙越濃看得越近；起點照察覺的早晚離火遠近不同。
# 用法：bash tools/run_sim.sh fire_escape_rules
var f := 0
var fails := 0

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

func _fe(rows: Array, st: int, wind := Vector2(1, 0), extra := {}):
	var FE = load("res://scripts/core/FireEscape.gd")
	var fe = FE.new()
	var ctx := {"map": rows, "seed": 7, "wind": wind, "strength": st, "flank": false, "wolf": {"perception": 50, "health": 999, "health_max": 999}}
	ctx.merge(extra, true)
	fe.setup(ctx)
	return fe

func _rows(w: int, h: int, ch: String) -> Array:
	var out: Array = []
	for y in h:
		out.append(ch.repeat(w))
	return out

func _front(fe) -> int:
	var m := -1
	for p in fe.burning_cells():
		m = maxi(m, p.x)
	return m

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	# 延燒：下風快、強風快
	var fronts := []
	for st in 3:
		var fe = _fe(_rows(40, 20, "."), st, Vector2(1, 0), {"wolf_pos": Vector2i(39, 0)})
		for r in 6:
			fe.wait()
		fronts.append(_front(fe))
	_ok(fronts[0] < fronts[1] and fronts[1] < fronts[2], "風越強火走得越遠（%s）" % str(fronts))
	var fe2 = _fe(_rows(40, 20, "."), 1, Vector2(1, 0), {"wolf_pos": Vector2i(0, 19)})
	for r in 5:
		fe2.wait()
	var mx := -1
	var my := 0
	for p in fe2.burning_cells():
		mx = maxi(mx, p.x)
	_ok(mx >= 6, "中風往下風（東）燒了 6 格以上（%d）" % mx)
	# 不會燒的地形
	var rows := _rows(30, 10, ".")
	rows[5] = "...........wwwwwddrrggx......."
	var fe3 = _fe(rows, 2, Vector2(1, 0), {"wolf_pos": Vector2i(29, 0)})
	for r in 12:
		fe3.wait()
	var bad := false
	for x in range(11, 23):
		if fe3.fire.has(Vector2i(x, 5)):
			bad = true
	_ok(not bad, "水、深水、岩坡、碎石、焦土不會燒")
	# 狀態：燃燒 → 剛燒過 → 冷卻
	var fe4 = _fe(_rows(20, 6, "."), 0, Vector2(1, 0), {"wolf_pos": Vector2i(19, 0)})
	var p0 := Vector2i(0, 3)
	_ok(fe4.state(p0) == "burning", "開場上風邊在燒")
	var seen := {}
	for r in 6:
		seen[fe4.state(p0)] = true
		fe4.wait()
	_ok(seen.has("hot") and fe4.state(p0) == "ash", "燃燒 → 剛燒過 → 冷卻（%s，現在 %s）" % [str(seen.keys()), fe4.state(p0)])
	# 這一回合才燒起來的草地下一回合還在燒
	var fe5 = _fe(_rows(20, 6, "."), 1, Vector2(1, 0), {"wolf_pos": Vector2i(19, 0)})
	fe5.wait()
	var newborn: Array = fe5.burning_cells().filter(func(p): return int(fe5.fire[p]["born"]) == fe5.rounds)
	_ok(not newborn.is_empty(), "這一回合有新燒起來的格子")
	# 煙往下風飄
	var fe6 = _fe(_rows(40, 20, "f"), 1, Vector2(1, 0), {"wolf_pos": Vector2i(39, 0)})
	var down := 0
	var up := 0
	for p in fe6.smoke:
		if p.x > 4:
			down += 1
	_ok(down > 20, "中風的煙往下風飄（%d 格）" % down)
	# 微風時煙在水邊積聚
	var rows7 := _rows(20, 10, ".")
	rows7[5] = "....wwww............"
	var fe7 = _fe(rows7, 0, Vector2(1, 0), {"wolf_pos": Vector2i(19, 0)})
	_ok(fe7.smoke_at(Vector2i(4, 5)) >= fe7.smoke_at(Vector2i(4, 4)), "微風的煙在水邊積聚（水 %d、旁邊 %d）" % [fe7.smoke_at(Vector2i(4, 5)), fe7.smoke_at(Vector2i(4, 4))])
	# 火星：先落下、之後才燒、不落在狼身上
	var fe8 = _fe(_rows(40, 20, "f"), 2, Vector2(1, 0), {"wolf_pos": Vector2i(20, 10)})
	var ember_then_fire := false
	var on_wolf := false
	var marks := {}
	for r in 10:
		for e in fe8.embers:
			marks[e] = true
			if e == fe8.wolf_pos:
				on_wolf = true
		fe8.wolf["health"] = 999
		fe8.wait()
		for e in marks:
			if fe8.fire.has(e):
				ember_then_fire = true
	_ok(not marks.is_empty() and ember_then_fire, "強風的針葉林有火星，之後燒起來（%d 處）" % marks.size())
	_ok(not on_wolf, "火星不落在狼身上")
	# 傷：站在燃燒的格子、深水
	var fe9 = _fe(_rows(10, 5, "f"), 0, Vector2(1, 0), {"wolf_pos": Vector2i(9, 0)})
	var hb: float = float(fe9.wolf["health"])
	fe9.wolf_pos = Vector2i(0, 2)
	fe9.wait()
	_ok(float(fe9.dmg["burn"]) > 0.0, "站在燃燒的格子受燒傷")
	var rows10 := _rows(10, 5, "f")
	for y in 5:
		rows10[y] = "f" + "a".repeat(9)
	rows10[2] = "fd" + "a".repeat(8)
	var rows11 := _rows(10, 5, "f")
	for y in 5:
		rows11[y] = "f" + "a".repeat(9)
	rows11[2] = "fg" + "a".repeat(8)
	var fea = _fe(rows10, 0, Vector2(1, 0), {"wolf_pos": Vector2i(1, 2)})
	var feb = _fe(rows11, 0, Vector2(1, 0), {"wolf_pos": Vector2i(1, 2)})
	fea.wait()
	feb.wait()
	_ok(float(fea.dmg["heat"]) < float(feb.dmg["heat"]), "深水裡的熱比碎石少（%.1f < %.1f）" % [fea.dmg["heat"], feb.dmg["heat"]])
	# 燃燒的格子走不過去
	var fec = _fe(_rows(10, 5, "."), 0, Vector2(1, 0), {"wolf_pos": Vector2i(3, 2)})
	_ok(not fec.reachable().has(Vector2i(0, 2)), "燃燒的格子走不過去")
	# 離開：只有站在邊上；往在燒的那一邊是 into_fire
	var fed = _fe(_rows(10, 6, "."), 0, Vector2(1, 0), {"wolf_pos": Vector2i(5, 3), "edges_burning": ["n"]})
	fed.exit_to("e")
	_ok(not fed.done, "不在邊上不能離開")
	fed.wolf_pos = Vector2i(5, 0)
	fed.exit_to("n")
	_ok(fed.done and fed.result == "into_fire", "往在燒的那一邊是 into_fire")
	var fee = _fe(_rows(10, 6, "."), 0, Vector2(1, 0), {"wolf_pos": Vector2i(9, 3)})
	fee.exit_to("e")
	_ok(fee.done and fee.result == "escaped" and fee.exit_side == "e", "往沒在燒的那一邊逃出去")
	# 煙越濃看得越近
	var fef = _fe(_rows(40, 20, "f"), 2, Vector2(1, 0), {"wolf_pos": Vector2i(30, 10)})
	var clear_r: int = fef.sight_radius()
	fef.wolf_pos = Vector2i(3, 10)
	_ok(fef.sight_radius() < clear_r, "煙濃時看得近（%d < %d）" % [fef.sight_radius(), clear_r])
	# 起點：察覺得早離火遠
	var de := 0.0
	var dl := 0.0
	for s in 10:
		var FE = load("res://scripts/core/FireEscape.gd")
		var a = FE.new()
		a.setup({"hunt_map": "edge_1", "seed": s, "wind": Vector2(1, 0), "strength": 1, "warning": "early", "flank": false})
		var b = FE.new()
		b.setup({"hunt_map": "edge_1", "seed": s, "wind": Vector2(1, 0), "strength": 1, "warning": "late", "flank": false})
		de += a.wolf_pos.x
		dl += b.wolf_pos.x
	_ok(de > dl, "察覺得早離火遠（%.1f > %.1f）" % [de / 10.0, dl / 10.0])
	# --- 第 2 步：避難地形 ---
	# 巢穴：擋得住火和熱；火靠近時濃煙終究會灌進來，之後每回合扣血；在裡面不能移動、不能離開地圖；看不到外面
	var rowsd := _rows(16, 8, "f")
	rowsd[4] = "ffn" + "f".repeat(13)
	var fd = _fe(rowsd, 1, Vector2(1, 0), {"wolf_pos": Vector2i(2, 4)})
	fd.den_cell = Vector2i(2, 4)
	_ok(fd.can_enter_den(), "站在洞口可以鑽進去")
	fd.enter_den()
	_ok(fd.in_den and fd.sight_radius() == 0, "在巢穴裡、看不到外面")
	# 洞口在火的路上（地圖中間）：幾個種子裡濃煙都會灌進來
	var rows_mid := _rows(24, 9, "f")
	rows_mid[4] = "f".repeat(10) + "n" + "f".repeat(13)
	var flooded := 0
	var no_fire := true
	var smoked := true
	for sd in 6:
		var fdm = _fe(rows_mid, 1, Vector2(1, 0), {"wolf_pos": Vector2i(10, 4), "seed": sd + 1})
		fdm.den_cell = Vector2i(10, 4)
		fdm.enter_den()
		for r in 40:
			fdm.wait()
			if fdm.done:
				break
		if fdm.den_smoke:
			flooded += 1
			smoked = smoked and float(fdm.dmg["smoke"]) > 0.0
		no_fire = no_fire and float(fdm.dmg["burn"]) == 0.0 and float(fdm.dmg["heat"]) == 0.0
	_ok(no_fire, "巢穴裡不受火和熱的傷")
	_ok(flooded >= 3, "火從旁邊燒過時，濃煙多半會灌進巢穴（6 次裡 %d 次）" % flooded)
	_ok(smoked, "濃煙灌進來之後扣血")
	var fd2 = _fe(rowsd, 1, Vector2(1, 0), {"wolf_pos": Vector2i(2, 4)})
	fd2.den_cell = Vector2i(2, 4)
	fd2.enter_den()
	var before: Vector2i = fd2.wolf_pos
	fd2.move_to(Vector2i(3, 4))
	_ok(fd2.wolf_pos == before and fd2.in_den, "在巢穴裡不能移動")
	fd2.leave_den()
	_ok(not fd2.in_den and fd2.wolf_pos == Vector2i(2, 4), "衝出來回到洞口那一格")
	# 本能 den：躲到濃煙灌進來才出來
	var fd3 = _fe(rowsd, 1, Vector2(1, 0), {"wolf_pos": Vector2i(2, 4)})
	fd3.den_cell = Vector2i(2, 4)
	var FI = load("res://scripts/core/FireInstinct.gd")
	FI.step(fd3, "den")
	_ok(fd3.in_den, "本能 den：先鑽進去")
	var left_after_smoke := true
	for r in 30:
		var was_smoke: bool = fd3.den_smoke
		var was_in: bool = fd3.in_den
		FI.step(fd3, "den")
		if was_in and not fd3.in_den and not was_smoke:
			left_after_smoke = false
		if not fd3.in_den or fd3.done:
			break
	_ok(left_after_smoke, "本能 den：濃煙灌進來才出來")
	# 地圖放巢穴、早先燒過的焦土
	var FE = load("res://scripts/core/FireEscape.gd")
	var fm = FE.new()
	fm.setup({"hunt_map": "edge_1", "seed": 3, "wind": Vector2(1, 0), "strength": 1, "den": true, "ash_patch": true, "flank": false})
	_ok(fm.den_cell.x >= 0 and fm.terrain(fm.den_cell) == "n", "巢穴所在的區域地圖上有洞口")
	var ash := 0
	for y in fm.height:
		for x in fm.width:
			if fm.terrain(Vector2i(x, y)) == "x":
				ash += 1
	_ok(ash >= 5, "早先燒過的一塊焦土（%d 格）" % ash)
	# 岩坡：火不會燒進來，但熱照算（和旁邊有一樣多火的碎石一樣）
	var rr := _rows(10, 5, "f")
	for y in 5:
		rr[y] = "f" + "a".repeat(9)
	rr[2] = "fr" + "a".repeat(8)
	var fr = _fe(rr, 0, Vector2(1, 0), {"wolf_pos": Vector2i(1, 2)})
	fr.wait()
	_ok(float(fr.dmg["heat"]) > 0.0 and not fr.fire.has(Vector2i(1, 2)), "岩坡不會燒、熱照算（%.1f）" % fr.dmg["heat"])
	print("火場原型的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
