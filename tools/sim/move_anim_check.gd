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
	# 逃出邊緣
	h.herd[h.target]["exit_to"] = Vector2i(-3, h.deer_pos.y)
	h.done = true
	h.result = "escaped"
	hd.refresh()
	hd._animate_units(0.6)
	var ds: Sprite3D = hd.units["deer%d" % h.target]["sprite"]
	_ok(ds.visible and ds.position.x < 0.0, "逃出邊緣：鹿滑到地圖外（x %.2f）" % ds.position.x)
	print("全部通過" if fails == 0 else "有失敗 %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
