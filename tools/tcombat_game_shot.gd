extends SceneTree
# 主遊戲的戰術戰鬥畫面截圖（Phase 2k，2026-11-06）：新遊戲 → 在殘骸旁被灰熊搶（或其他情境）→ 開戰術戰鬥畫面，存成 PNG。
# COVER=1：狼腳下改成密林（看高草蓋住狼）。
# 用法：SEASON=<季節序號> PERIOD=<時段序號 0 清晨～4 黎明前> ANIMAL=grizzly_bear CONTEXT=carcass LAYOUT=<arrives/on_carcass/encounter/ambush> TERRAIN=<地形> DEN=<巢穴區域> OUT=<路徑> \
#   xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/tcombat_game_shot.gd
var f := 0
var v

func _env(k: String, d: String) -> String:
	var s := OS.get_environment(k)
	return s if s != "" else d

func _process(_d) -> bool:
	f += 1
	if f == 2:
		var gs = root.get_node("GameState")
		gs.new_game(_env("DEN", "forest_east"))
		gs.wolf.age_years = 3.0
		# SEASON=<季節序號>、PERIOD=<時段序號>（看冬天的雪地、時段光線；Phase 2k 第 6 步）
		var gt = root.get_node("GameTime")
		if _env("SEASON", "") != "":
			gt.season_index = int(_env("SEASON", "0"))
		if _env("PERIOD", "") != "":
			gt.period_index = int(_env("PERIOD", "0"))
		var ctx := _env("CONTEXT", "carcass")
		if ctx == "carcass":
			gs.start_feeding("elk", "adult", _env("TERRAIN", "forest_edge"))
		var c = gs.start_combat(_env("ANIMAL", "grizzly_bear"), "adult", ctx)
		c.terrain = _env("TERRAIN", "forest_edge")
		if _env("LAYOUT", "") != "":
			c.set_meta("tc_layout", _env("LAYOUT", ""))
		v = load("res://prototypes/tactical_combat/TacticalCombat.tscn").instantiate()
		root.add_child(v)
		var tc = gs.start_tactical_combat(c)
		# COVER=1：狼所在的格子和左右各一格改成密林 f（看草原的高草蓋住狼，2026-11-08）
		if _env("COVER", "") != "":
			var wp: Vector2i = tc.units[0]["pos"]
			for dx in [-1, 0, 1]:
				var row: String = tc.map.grid[wp.y]
				tc.map.grid[wp.y] = row.substr(0, wp.x + dx) + "f" + row.substr(wp.x + dx + 1)
		v.start_from_game.call_deferred(tc, func(): pass, "")
	if f == 30:
		root.get_viewport().get_texture().get_image().save_png(_env("OUT", "/tmp/tcg.png"))
		return true
	return false
