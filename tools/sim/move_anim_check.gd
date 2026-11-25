extends SceneTree
# 戰術畫面的移動動畫（2026-11-25，pre-2.0-plan 六之三第 5 項第一步）：
#   1. 狼換格子：refresh 後還在原地附近，播一半在中間，0.5 秒後到新的格子
#   2. 一次跳太遠（> snap_dist）直接到位
#   3. 逃出邊緣的鹿：結束後滑到地圖外
# 用法：bash tools/run_sim.sh move_anim_check
var f := 0
var fails := 0

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
	print(("  ✓ " if c else "  ✗ ") + msg)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 8
	var HD = load("res://prototypes/tactical_hunt/HuntHD2D.gd")
	var h = TacticalHunt.new()
	h.setup_from_game({"family": "open", "seed": 5, "condition": "average", "season": "summer",
		"wolf": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}})
	var hd = HD.new()
	hd.size = Vector2(900, 420)
	root.add_child(hd)
	hd.setup(h)
	hd.refresh()
	var s: Sprite3D = hd.units["wolf"]["sprite"]
	var p0: Vector3 = s.position
	var c0: Vector2i = h.wolf_pos
	h.wolf_pos = c0 + Vector2i(3, 0)
	hd.refresh()
	var target: Vector3 = hd.cell_center(h.wolf_pos) + Vector3(0, 0, 0.05)
	_ok(s.position.distance_to(p0) < 0.05, "剛換格子：還在原地（%s）" % str(s.position))
	hd._animate_units(0.25)
	var mid: float = s.position.x
	_ok(mid > p0.x + 0.5 and mid < target.x - 0.5, "播到一半：在中間（x %.2f，%.2f → %.2f）" % [mid, p0.x, target.x])
	hd._animate_units(0.3)
	_ok(s.position.distance_to(target) < 0.01, "0.5 秒後到新的格子")
	h.wolf_pos = c0 + Vector2i(14, 0) if c0.x < 20 else c0 - Vector2i(14, 0)
	hd.refresh()
	_ok(s.position.distance_to(hd.cell_center(h.wolf_pos) + Vector3(0, 0, 0.05)) < 0.01, "跳太遠：直接到位")
	# 撲咬（第二步）：狼往獵物衝一下、咬到時獵物閃紅；撲空的回合獵物等撲完才動
	var dkey := "deer%d" % h.target
	var dsp: Sprite3D = hd.units[dkey]["sprite"]
	h.anim_events.append({"kind": "pounce", "to": h.deer_pos, "hit": true, "kicked": false, "who": h.target})
	var d_before: Vector3 = dsp.position
	h.deer_pos = h.deer_pos + Vector2i(0, 2)
	h.herd[h.target]["pos"] = h.deer_pos
	var w_before: Vector3 = s.position
	hd.refresh()
	hd._animate_units(0.15)
	_ok(dsp.position.distance_to(d_before) < 0.05, "撲咬的回合：獵物先不動（等撲完）")
	_ok(s.position.distance_to(w_before) > 0.1, "狼往獵物衝出去（%.2f）" % s.position.distance_to(w_before))
	_ok(dsp.modulate.g < 0.95, "咬到：獵物閃紅（%s）" % str(dsp.modulate))
	hd._animate_units(0.4)
	_ok(s.position.distance_to(w_before) < 0.02, "衝完回到原位")
	hd._animate_units(0.6)
	_ok(dsp.position.distance_to(hd.cell_center(h.deer_pos) + Vector3(0, 0, 0.05)) < 0.02 and dsp.modulate == Color.WHITE, "撲完獵物才移動到新位置、顏色恢復")
	# 略過：播放中點一下直接到結果
	h.wolf_pos = h.wolf_pos + Vector2i(0, 2)
	hd.refresh()
	_ok(hd.is_animating(), "換格子後在播動畫")
	hd.finish_anims()
	_ok(not hd.is_animating() and s.position.distance_to(hd.cell_center(h.wolf_pos) + Vector3(0, 0, 0.05)) < 0.01, "略過：直接到新的格子")
	# 逃出邊緣
	h.herd[h.target]["exit_to"] = Vector2i(-3, h.deer_pos.y)
	h.done = true
	h.result = "escaped"
	hd.refresh()
	hd._animate_units(0.6)
	var ds: Sprite3D = hd.units["deer%d" % h.target]["sprite"]
	_ok(ds.visible and ds.position.x < 0.0, "逃出邊緣：鹿滑到地圖外（x %.2f）" % ds.position.x)
	# 撲空後馬上跑出邊緣：獵物要等撲完才開始滑，滑出去的時間要把等的時間也算進去（不會還沒動就消失）
	var h2 = TacticalHunt.new()
	h2.setup_from_game({"family": "open", "seed": 5, "condition": "average", "season": "summer",
		"wolf": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}})
	hd.setup(h2)
	hd.refresh()
	var k2 := "deer%d" % h2.target
	h2.wolf_pos += Vector2i(1, 0)
	h2.anim_events.append({"kind": "pounce", "to": h2.deer_pos, "hit": false, "kicked": false, "who": h2.target})
	h2.herd[h2.target]["exit_to"] = Vector2i(h2.deer_pos) + Vector2i(3, 0)
	h2.done = true
	h2.result = "escaped"
	var now: int = Time.get_ticks_msec()
	hd.refresh()
	var left: int = int(hd._exit_until[h2.target]) - now
	_ok(left >= 1300, "撲空後跑出邊緣：等撲完（0.8 秒）再滑 0.5 秒才消失（%d 毫秒）" % left)
	# 移動、事件動畫播到一半時角色被藏起來（2026-11-25 試玩回報：_unit_pos 找不到 to 而當掉）
	var ent: Dictionary = hd.units[k2]
	hd.add_fx(k2, {"type": "flash", "color": Color.RED, "start": 0.0, "dur": 0.35})
	_ok(float(ent["t"]) < 1.0, "藏起來之前還在等著移動（t %.2f）" % float(ent["t"]))
	hd._exit_until[h2.target] = 0
	hd.refresh()
	hd.add_fx(k2, {"type": "flash", "color": Color.RED, "start": 0.0, "dur": 0.35}) # 藏著的時候來的事件不播
	hd._animate_units(0.1)
	var stopped: bool = float(ent["t"]) >= 1.0 and (ent.get("fx", []) as Array).is_empty()
	_ok(not (ent["sprite"] as Sprite3D).visible and stopped, "播到一半被藏起來：動畫停掉、不會當掉")
	print("全部通過" if fails == 0 else "有失敗 %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
