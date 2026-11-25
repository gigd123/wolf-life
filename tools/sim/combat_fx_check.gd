extends SceneTree
# 戰術戰鬥的事件動畫（2026-11-25）：hit 事件 → 出手的衝一下、被打中的閃紅；動畫播完回到原位、顏色恢復
# 用法：bash tools/run_sim.sh combat_fx_check
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
	var tc := TacticalCombat.new()
	tc.setup("grizzly_open", {"seed": 3})
	var hd = load("res://prototypes/tactical_combat/CombatHD2D.gd").new()
	hd.size = Vector2(900, 420)
	root.add_child(hd)
	hd.setup(tc)
	var e: int = tc.enemy_index()
	var ws: Sprite3D = hd.units["u0"]["sprite"]
	var es: Sprite3D = hd.units["u%d" % e]["sprite"]
	var w0: Vector3 = ws.position
	tc.events.append({"kind": "hit", "who": 0, "target": e, "round": tc.rounds})
	hd.refresh()
	hd._animate_units(0.14)
	_ok(ws.position.distance_to(w0) > 0.05, "出手的狼往對手衝出去（%.2f）" % ws.position.distance_to(w0))
	hd._animate_units(0.05)
	_ok(es.modulate.g < 0.95, "被打中的對手閃紅（%s）" % str(es.modulate))
	hd._animate_units(1.0)
	_ok(ws.position.distance_to(w0) < 0.02 and es.modulate.g > 0.99, "播完回到原位、顏色恢復")
	print("全部通過" if fails == 0 else "有失敗 %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
