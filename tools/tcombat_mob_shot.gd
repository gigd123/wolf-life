extends SceneTree
# 幫苔原狼對付狼獾的戰術戰鬥（2026-11-19 試玩回報 Bug #9）：苔原狼要一起上場。印出你方的單位（MOB_ALLIES=…），存成 PNG。
# 用法：OUT=<路徑> xvfb-run -a -s "-screen 0 1920x1080x24" $GODOT --path . --rendering-driver opengl3 -s tools/tcombat_mob_shot.gd
var f := 0
var v
func _process(_d) -> bool:
	f += 1
	if f == 2:
		var gs = root.get_node("GameState")
		gs.new_game("tundra_south")
		gs.wolf.age_years = 3.0
		root.get_node("GameTime").season_index = 2
		gs.debug_tundra_mob()
		var c = gs.start_mob_combat()
		var tc = gs.start_tactical_combat(c)
		var ally := []
		for u in tc.units:
			if str(u["side"]) in ["player", "ally"]:
				ally.append("%s(%s)" % [str(u["id"]), str(u.get("art_key", ""))])
		print("MOB_ALLIES=", ally, " 狼獾血 ", tc.units[tc.enemy_index()]["hp"], "/", tc.units[tc.enemy_index()]["hp_max"])
		v = load("res://prototypes/tactical_combat/TacticalCombat.tscn").instantiate()
		root.add_child(v)
		v.start_from_game.call_deferred(tc, func(): pass, "")
	if f == 30:
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/mob.png")
		return true
	return false
