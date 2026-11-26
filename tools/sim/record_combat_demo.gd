extends SceneTree
# 錄一場戰術戰鬥的示範影片（2026-11-25）：山地鄰群（BLACK=1 換成黑狼一家）（帶頭的狼＋伴侶＋年輕的狼），本能自動打，每 1.1 秒一回合。
# 用法：xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --fixed-fps 30 --write-movie out.avi -s res://tools/sim/record_combat_demo.gd
var hd
var tc
var t := 0.0
var next_step := 1.5
var end_at := -1.0
var steps := 0
var _ready_done := false

func _initialize() -> void:
	pass

func _setup_game() -> void:
	var gs = root.get_node("GameState")
	gs.new_game("mountain_canyon")
	gs.wolf.age_years = 4.0
	gs.wolf.health_max = 115.0
	gs.wolf.health = 115.0
	gs.wolf.strength = 78.0
	gs.wolf.skill = 70.0
	gs.debug_force_transition("adult")
	if OS.get_environment("BLACK") != "":
		# 黑狼一家（BLACK=1）：森林，帶頭的黑狼＋伴侶＋年輕的
		gs.new_game("forest_east")
		gs.wolf.age_years = 4.0
		gs.debug_force_transition("adult")
		var bp = gs.black_pack
		bp.stage = "pack"
		bp.regions = [gs.current_region]
		bp.young = [1.5, 2.0]
		gs.meet_pack_id = "black"
	else:
		gs.current_region = "mountain_canyon"
		gs.meet_pack_id = "mountain"
		var mp = gs.pack_by_id("mountain")
		mp.young = [1.5, 2.0]
	tc = gs.start_pack_tactical()
	# 示範用：你這隻血量多一點，不會一開打就判斷太危險而撤退
	tc.units[0]["hp_max"] = 260.0
	tc.units[0]["hp"] = 260.0
	# 示範用：被包圍時不自動撤（只影響這支錄影）
	tc.cfg["ai"]["wolf"]["auto_retreat_pr"] = 0.0
	hd = load("res://prototypes/tactical_combat/CombatHD2D.gd").new()
	root.add_child.call_deferred(hd)

var _f := 0

func _process(delta: float) -> bool:
	_f += 1
	if _f == 2:
		_setup_game()
	if hd == null:
		return false
	if not _ready_done:
		if hd.is_inside_tree():
			hd.size = root.get_visible_rect().size
			hd.setup(tc)
			_ready_done = true
		return false
	t += delta
	if end_at > 0.0:
		return t >= end_at
	if t >= next_step:
		next_step = t + 1.1
		steps += 1
		# 示範用：一直正面對打（交給本能會因為對方多而先撤）
		tc.units[0]["command"] = "duel"
		tc.plan(0, tc.ally_plan(0))
		tc.resolve()
		if not tc.done:
			tc.begin_round() # 對手決定下一回合（同戰鬥畫面的 _resolve_and_next）
		hd.refresh()
		print("step %d done %s %s" % [steps, str(tc.done), str(tc.outcome)])
		if tc.done or steps > 14:
			end_at = t + 2.0
	return false
