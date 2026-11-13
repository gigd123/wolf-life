extends SceneTree
# 森林大火逃生地圖的截圖（Phase 2n 第 5 步，2026-11-13，HD-2D 畫面）：開 prototypes/fire_escape/，照設定產生火場，交給本能走 STEPS 步，存成 PNG。
# POLICY=smart|stay|water…（FireInstinct 的打法）
# MAP=<地圖序號>（FireEscapeView.MAPS）WIND=0|1|2 WARN=0|1|2 SEED=<種子> STEPS=<本能走幾步> NIGHT=1 DEN=1 HD=0|1 ZOOM=<倍數>
# 用法：OUT=<路徑> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/fire_shot.gd
var f := 0
var v

func _env(k: String, d: String) -> String:
	var s := OS.get_environment(k)
	return s if s != "" else d

func _process(_d) -> bool:
	f += 1
	if f == 2:
		v = load("res://prototypes/fire_escape/FireEscape.tscn").instantiate()
		root.add_child(v)
	if f == 5:
		v.hd_on = _env("HD", "1") == "1"
		v.map_pick.selected = int(_env("MAP", "0"))
		v.wind_pick.selected = int(_env("WIND", "2"))
		v.warn_pick.selected = int(_env("WARN", "1"))
		v.den_check.button_pressed = _env("DEN", "0") == "1"
		v.seed = int(_env("SEED", "3"))
		v._new()
		v.fe.night = _env("NIGHT", "0") == "1"
		for i in int(_env("STEPS", "4")):
			if v.fe.done:
				break
			FireInstinct.step(v.fe, _env("POLICY", "smart"))
		v._after()
		var z := float(_env("ZOOM", "1"))
		if z > 0.0:
			v.hd.zoom = z
			v.hd.focus = Vector2(v.fe.wolf_pos)
			v.hd._apply_camera()
		v._refresh()
	if f == 30:
		root.get_viewport().get_texture().get_image().save_png(_env("OUT", "/tmp/fire.png"))
		return true
	return false
