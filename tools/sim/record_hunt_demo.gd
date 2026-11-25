extends SceneTree
# 錄一場戰術狩獵的示範影片（2026-11-25，給使用者看移動動畫）：本能自動打，每 0.9 秒走一步。
# 用法（要有畫面：xvfb）：xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --fixed-fps 30 --write-movie out.avi -s res://tools/sim/record_hunt_demo.gd
# 環境變數：LARGE=1 用 40×40 地圖；SEED、FAMILY（open／edge／dense／logs）
var hd
var h
var t := 0.0
var next_step := 1.5
var end_at := -1.0
var steps := 0

func _initialize() -> void:
	var HD = load("res://prototypes/tactical_hunt/HuntHD2D.gd")
	h = TacticalHunt.new()
	h.setup_from_game({"family": OS.get_environment("FAMILY") if OS.get_environment("FAMILY") != "" else "edge",
		"seed": int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7, "condition": "average", "season": "summer",
		"large_maps": OS.get_environment("LARGE") != "", "world_map": "forest",
		"wolf": {"speed": 66, "skill": 62, "strength": 62, "perception": 60, "stamina": 80, "health": 100, "health_max": 100}})
	h.game_mods["season"] = "summer"
	TacticalInstinct.pick_target(h)
	hd = HD.new()
	hd.position = Vector2.ZERO
	root.add_child.call_deferred(hd)

var _ready_done := false

func _process(delta: float) -> bool:
	if not _ready_done:
		if hd.is_inside_tree():
			hd.size = root.get_visible_rect().size
			hd.setup(h)
			_ready_done = true
		return false
	t += delta
	if end_at > 0.0:
		return t >= end_at
	if t >= next_step:
		next_step = t + 0.9
		steps += 1
		var p: String = TacticalInstinct.pick_policy(h)
		TacticalInstinct.step(h, "stalk" if (h.held or h.track_pending or h.hidden_unfound()) else p)
		hd.refresh()
		print("step %d round %d wolf %s deer %s state %s done %s %s" % [steps, h.rounds, str(h.wolf_pos), str(h.deer_pos), str(h.deer_state), str(h.done), str(h.result)])
		if h.done or steps > 40:
			end_at = t + 2.0
	return false
