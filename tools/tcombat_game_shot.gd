extends SceneTree
# 主遊戲的戰術戰鬥畫面截圖（Phase 2k，2026-11-06）：新遊戲 → 在殘骸旁被灰熊搶（或其他情境）→ 開戰術戰鬥畫面，存成 PNG。
# 用法：ANIMAL=grizzly_bear CONTEXT=carcass LAYOUT=<arrives/on_carcass/encounter/ambush> TERRAIN=<地形> DEN=<巢穴區域> OUT=<路徑> \
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
		v.start_from_game.call_deferred(tc, func(): pass, "")
	if f == 30:
		root.get_viewport().get_texture().get_image().save_png(_env("OUT", "/tmp/tcg.png"))
		return true
	return false
