extends SceneTree
# 鮭魚洄流河岸的 HD-2D 畫面（2026-11-21，試玩回報 #7）：新遊戲 → 洄流的區域與季節 → Game 開河岸畫面，
# 狼往魚最多的淺灘走 STEPS 步、站上去撲一次，存成 PNG（印 RIVER_SHOT 狼的位置、灰熊數、HD-2D 有沒有畫出狼與熊）。
# HD=0 時看 2D 地圖。STAGE_IDX=<data 的 stages 序號，預設 1 盛期>
# 用法：OUT=<路徑> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/river_shot.gd
var f := 0
var game
var gs

func _env(k: String, d: String) -> String:
	var s := OS.get_environment(k)
	return s if s != "" else d

func _process(_d) -> bool:
	f += 1
	if f == 2:
		gs = root.get_node("GameState")
		var gt = root.get_node("GameTime")
		gs.new_game("forest_east")
		gs.debug_force_transition("adult")
		var cfg: Dictionary = gs._salmon_cfg()
		gs.current_region = str(cfg["regions"][0])
		var st: Dictionary = cfg["stages"][int(_env("STAGE_IDX", "1"))]
		gt.season_index = ["spring", "summer", "autumn", "winter"].find(str(st["season"]))
		gt.day = int(st["from"])
		load("res://prototypes/tactical_hunt/TacticalHuntView.gd").hd_on = _env("HD", "1") != "0"
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 5:
		game._open_river()
	if f == 8:
		var v = null
		for ch in game.get_children():
			if ch.get_script() == load("res://scripts/ui/RiverView.gd"):
				v = ch
		if v == null:
			print("RIVER_SHOT_FAIL 沒有河岸畫面")
			return true
		var rf = v.rf
		for i in int(_env("STEPS", "3")):
			if rf.done:
				break
			# 往魚最多、沒被熊威嚇的淺灘走
			var best := Vector2i(-1, -1)
			var bs := -INF
			for c in rf.reachable().keys():
				var sc: float = float(rf.fish_at(c)) * 3.0 - Vector2(c - rf.wolf_pos).length() * 0.1
				if sc > bs:
					bs = sc
					best = c
			if best.x >= 0:
				v._on_click(best)
		if rf.can_fish():
			rf.fish_once()
			v._after_action()
		print("RIVER_SHOT wolf ", rf.wolf_pos, " bears ", rf.bears.size(), " hd_wolf ", v.hd.units.has("wolf"), " hd_bear ", v.hd.units.has("bear0"), " caught ", rf.caught, " attempts ", rf.attempts)
	if f == 30:
		root.get_viewport().get_texture().get_image().save_png(_env("OUT", "/tmp/river.png"))
		return true
	return false
