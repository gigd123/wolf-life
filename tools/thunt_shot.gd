extends SceneTree
# 戰術狩獵畫面的截圖（2026-11-05，HD-2D 畫面）：開 prototypes/tactical_hunt/，選情境（設定列的序號），存成 PNG。
# ZOOM=<倍數>：拉近到狼附近。
# 用法：SC=<情境序號> HD=0|1 OUT=<路徑> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/thunt_shot.gd
var f := 0
var v

func _env(k: String, d: String) -> String:
	var s := OS.get_environment(k)
	return s if s != "" else d

func _process(_d) -> bool:
	f += 1
	if f == 2:
		v = load("res://prototypes/tactical_hunt/TacticalHunt.tscn").instantiate()
		root.add_child(v)
	if f == 5:
		v.hd_on = _env("HD", "1") == "1"
		v.scenario_pick.selected = int(_env("SC", "0"))
		v.game_seed = 11
		v._new_hunt(false)
		var z := float(_env("ZOOM", "1"))
		if z > 1.0:
			v.hd.zoom = z
			v.hd.focus = Vector2(v.h.wolf_pos) + Vector2(4, 0)
			v.hd._apply_camera()
	if f == 25:
		root.get_viewport().get_texture().get_image().save_png(_env("OUT", "/tmp/thunt.png"))
		return true
	return false
