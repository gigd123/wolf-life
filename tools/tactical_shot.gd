extends SceneTree
# 戰術地圖截圖（Phase 2c 美術確認）：開原型畫面、選情境、往鹿走幾步，存成 PNG。
# 用法：SC=<情境序號 0～9> MOVES=<步數> OUT=<輸出路徑> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/tactical_shot.gd
var f := 0
var view
func _process(_d) -> bool:
	f += 1
	if f == 2:
		view = load("res://prototypes/tactical_hunt/TacticalHunt.tscn").instantiate()
		root.add_child(view)
	if f == 6:
		view.scenario_pick.selected = int(OS.get_environment("SC")) if OS.get_environment("SC") != "" else 0
		view._new_hunt(true)
		for i in int(OS.get_environment("MOVES") if OS.get_environment("MOVES") != "" else "0"):
			var r: Dictionary = view.h.reachable()
			var best := Vector2i(-1, -1)
			var bd := INF
			for c in r.keys():
				var d: float = view.h.dist(c, view.h.deer_pos)
				if d < bd:
					bd = d
					best = c
			if best.x >= 0:
				view.h.move_to(best)
		view._refresh()
	if f == 12:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OS.get_environment("OUT"))
		return true
	return false
