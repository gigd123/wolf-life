extends SceneTree
# HD-2D 戰術場景測試的截圖（2026-11-04）：開 prototypes/hd2d_tactical/，照環境變數切模式，存成 PNG。
# 用法：TILE=32|48 SMOOTH=0|1 LEVEL=0|1|2 ZOOM=<無段時螢幕上一格的像素> VIEW=normal|far|map WALK=<x,y> OUT=<路徑> \
#   xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/hd2d_shot.gd
var f := 0
var v

func _env(k: String, d: String) -> String:
	var s := OS.get_environment(k)
	return s if s != "" else d

func _process(_d) -> bool:
	f += 1
	if f == 2:
		v = load("res://prototypes/hd2d_tactical/HD2DTactical.tscn").instantiate()
		root.add_child(v)
	if f == 5:
		v.tile_px = int(_env("TILE", "32"))
		v.smooth = _env("SMOOTH", "0") == "1"
		v.level = int(_env("LEVEL", "0"))
		v.smooth_tile = float(_env("ZOOM", "96"))
		v._apply_tile()
		var w := _env("WALK", "")
		if w != "":
			var p := w.split(",")
			v.wolf_cell = Vector2i(int(p[0]), int(p[1]))
			v.wolf.position = v.cell_center(v.wolf_cell)
		v._focus_wolf()
		match _env("VIEW", "normal"):
			"far":
				v.far_view = true
				v._update_camera()
			"map":
				v._toggle_overview()
	if f == 30:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(_env("OUT", "/tmp/hd2d.png"))
		return true
	return false
