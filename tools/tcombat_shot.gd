extends SceneTree
# 戰術戰鬥原型的截圖（2026-11-04）：開 prototypes/tactical_combat/，選情境、知識，交給本能跑幾回合，存成 PNG。
# HD=0 用 2D 地圖（預設 HD-2D，2026-11-05）。
# 用法：SC=<情境序號 0～6> KNOW=<0～2> MODE=<0 同步／1 輪流> ROUNDS=<自動幾回合> PLAN=<x,y：最後選好要走的格子> OUT=<路徑> \
#   xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/tcombat_shot.gd
var f := 0
var v

func _env(k: String, d: String) -> String:
	var s := OS.get_environment(k)
	return s if s != "" else d

func _process(_d) -> bool:
	f += 1
	if f == 2:
		v = load("res://prototypes/tactical_combat/TacticalCombat.tscn").instantiate()
		root.add_child(v)
	if f == 5:
		v.scenario_pick.selected = int(_env("SC", "0"))
		v.know_pick.selected = int(_env("KNOW", "1"))
		v.mode_pick.selected = int(_env("MODE", "0"))
		v.seed = 7
		v.hd_on = _env("HD", "1") == "1"
		v._new_game(false)
		for i in int(_env("ROUNDS", "0")):
			if v.tc.done:
				break
			v.tc.plan(0, v.tc.auto_plan(0))
			v._resolve_and_next()
		var p := _env("PLAN", "")
		if p != "":
			var a := p.split(",")
			var c := Vector2i(int(a[0]), int(a[1]))
			if v.tc.reachable(0).has(c):
				v.planned = c
			v._refresh()
	if f == 25:
		root.get_viewport().get_texture().get_image().save_png(_env("OUT", "/tmp/tcombat.png"))
		return true
	return false
