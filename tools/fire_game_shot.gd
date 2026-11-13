extends SceneTree
# 主遊戲裡的森林大火逃生地圖（Phase 2n 第 5 步，2026-11-13）：新遊戲 → 大火燒進狼所在的區域 → Game 開逃生地圖（HD-2D），
# 交給本能走 STEPS 步，存成 PNG；DONE=1 時本能玩到底、按「繼續」回主畫面，檢查紀錄與畫面都回來了（印 FIRE_GAME_OK／FIRE_GAME_FAIL）。
# REGION=<區域> EXTRA=<也在燒的相鄰區,…> STRENGTH=0|1|2 SEASON=<季節序號> PERIOD=<時段序號>
# 用法：OUT=<路徑> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/fire_game_shot.gd
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
		var region := _env("REGION", "forest_north")
		gs.new_game(region)
		gs.debug_force_transition("adult")
		gt.season_index = int(_env("SEASON", "1"))
		if _env("PERIOD", "") != "":
			gt.period_index = int(_env("PERIOD", "0"))
		gs.current_region = region
		gs.start_fire_warning(region)
		gs.fire["phase"] = "burning"
		gs.fire["regions"] = {region: gs._abs_period()}
		for r in _env("EXTRA", "forest_east").split(",", false):
			gs.fire["regions"][r] = gs._abs_period()
		if _env("STRENGTH", "") != "":
			gs.fire["wind_strength"] = int(_env("STRENGTH", "1"))
		game = load("res://scenes/Game.tscn").instantiate()
		root.add_child(game)
	if f == 5:
		game._open_fire_escape({"region": gs.current_region})
	if f == 8:
		var v = game.fire_escape_view
		if _env("DONE", "") != "":
			FireInstinct.play(v.fe, "smart")
		else:
			for i in int(_env("STEPS", "2")):
				if v.fe.done:
					break
				FireInstinct.step(v.fe, "smart")
		v._after()
		print("WOLF ", v.fe.wolf_pos, " den ", v.fe.den_cell, " in_den ", v.fe.in_den, " vis ", v.hd.units.has("wolf"))
	if f == 30:
		root.get_viewport().get_texture().get_image().save_png(_env("OUT", "/tmp/fire_game.png"))
		if _env("DONE", "") != "":
			var v = game.fire_escape_view
			if v == null or not v.fe.done:
				print("FIRE_GAME_FAIL 沒有玩完")
				return true
			# 按「繼續」
			for b in v.buttons.get_children():
				if b is Button:
					(b as Button).pressed.emit()
					break
	if f == 34 and _env("DONE", "") != "":
		var ok: bool = game.fire_escape_view == null
		print("FIRE_GAME_OK" if ok else "FIRE_GAME_FAIL 按了繼續還在逃生地圖")
		return true
	return f > 34
