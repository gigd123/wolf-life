extends SceneTree
# 次成年灰狼的圖（2026-11-25）：未滿 2 歲時你這隻狼用 hdwolf_sub_*，沒有的姿勢（咬住、走路第二格）用成狼的；2 歲以上用成狼的
# 用法：bash tools/run_sim.sh sub_wolf_art_check
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
	var gs = root.get_node("GameState")
	gs.new_game("forest_east")
	var hd = load("res://prototypes/tactical_hunt/HuntHD2D.gd").new()
	root.add_child(hd)
	gs.wolf.age_years = 1.5
	for pose in ["hdwolf_stand", "hdwolf_walk", "hdwolf_stalk", "hdwolf_lunge", "hdwolf_hurt", "hdwolf_submit"]:
		var t: Texture2D = hd.player_wolf_texture(pose)["tex"]
		_ok(t.resource_path.contains("hdwolf_sub_"), "1.5 歲 %s → %s" % [pose, t.resource_path.get_file()])
	var tb: Texture2D = hd.player_wolf_texture("hdwolf_walk_b")["tex"]
	_ok(tb.resource_path.contains("hdwolf_sub_walk_"), "走路第二張還沒有：用年輕的狼第一張，不和成狼交錯（%s）" % tb.resource_path.get_file())
	var th: Texture2D = hd.player_wolf_texture("hdwolf_hold")["tex"]
	_ok(not th.resource_path.contains("_sub_"), "還沒有的姿勢用成狼的（%s）" % th.resource_path.get_file())
	gs.wolf.age_years = 3.0
	var ta: Texture2D = hd.player_wolf_texture("hdwolf_stand")["tex"]
	_ok(not ta.resource_path.contains("_sub_"), "3 歲用成狼的（%s）" % ta.resource_path.get_file())
	print("全部通過" if fails == 0 else "有失敗 %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
