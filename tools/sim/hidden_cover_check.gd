extends SceneTree
# 2026-11-25：躲在草裡的幼鹿那 3×3 格放上樹叢（HuntHD2D._hidden_cover），照地圖換：森林灌木、草原高草、冬天積雪的。
# 用法：bash tools/run_sim.sh hidden_cover_check
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
	var TH = load("res://scripts/core/TacticalHunt.gd")
	var HD = load("res://prototypes/tactical_hunt/HuntHD2D.gd")
	for case in [["", "summer", "shrub"], ["grassland", "summer", "tallgrass"], ["", "winter", "shrub_winter"]]:
		var h = TH.new()
		h.setup_from_game({"family": "open", "seed": 3, "condition": "average", "season": case[1], "world_map": case[0], "hidden": true, "hidden_detection": 30.0,
			"wolf": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}})
		h.game_mods["world_map"] = case[0]
		h.game_mods["season"] = case[1]
		var hd = HD.new()
		hd.size = Vector2(640, 360)
		root.add_child(hd)
		hd.setup(h)
		var n := 0
		var arts := {}
		for t in hd.tree_sprites:
			if h.hidden_area.has_point(t["cell"]):
				n += 1
				arts[str(t["art"])] = true
		_ok(h.hidden_area.size.x == 3 and n >= 9, "%s %s：躲藏的 3×3 格有樹叢（%d 個，%s）" % [case[0] if case[0] != "" else "森林", case[1], n, str(arts.keys())])
		_ok(arts.has(case[2]), "  用到 %s" % case[2])
		hd.queue_free()
	var h2 = TH.new()
	h2.setup_from_game({"family": "open", "seed": 3, "condition": "average", "season": "summer",
		"wolf": {"speed": 62, "skill": 58, "strength": 58, "perception": 55, "stamina": 80, "health": 100, "health_max": 100}})
	var hd2 = HD.new()
	root.add_child(hd2)
	hd2.setup(h2)
	_ok(not hd2.cfg.has("extra_props"), "沒有躲著的幼鹿：不放")
	print("全部通過" if fails == 0 else "有失敗 %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
