class_name RiverHD2D
extends HD2DBoard
# 鮭魚洄流的河岸畫面（HD-2D，2026-11-21，試玩回報 #7）。
# 共用的地形、鏡頭、點格子在 HD2DBoard，地形的樣子沿用戰術狩獵（prototypes/tactical_hunt/hunt_hd2d.json）；
# 這裡照 RiverView._draw_map 畫同樣的東西：魚量（淺灘上的鮭魚與粉紅色的點）、灰熊與牠的威嚇範圍、熊吃剩的魚、能走的格子、狼。
# 只管畫面，規則照 scripts/core/RiverFishing.gd。

const CFG_PATH := "res://prototypes/tactical_hunt/hunt_hd2d.json"
const RIVER_CFG := "res://data/river_hd2d.json"

var view # RiverView（讀 hover）
var rf
var rcfg: Dictionary = {}
var _base_cfg: Dictionary = {}
var _last_wolf_pos := Vector2i(-999, -999)
var _wolf_face := Vector2i(1, 0)
var _last_attempts := 0
var _last_caught := 0
var _pose := "stand"
var _salmon: Dictionary = {}

func _init() -> void:
	_init_board(CFG_PATH)
	rcfg = JSON.parse_string(FileAccess.get_file_as_string(RIVER_CFG))

func setup(p_rf, season: String = "", world_map: String = "") -> void:
	rf = p_rf
	_last_wolf_pos = Vector2i(-999, -999)
	_last_round = -1
	_last_attempts = rf.attempts
	_last_caught = rf.caught
	_pose = "stand"
	if _base_cfg.is_empty():
		_base_cfg = cfg.duplicate(true)
	cfg = _base_cfg.duplicate(true)
	apply_map_set(world_map)
	cfg["season"] = season
	_salmon = HD2DBoard.animal_texture("salmon", "adult", float(rcfg.get("salmon_width", 0.7)))
	build(rf.width, rf.height, func(c: Vector2i) -> String: return rf.terrain(c))
	focus_on(rf.wolf_pos, float(cfg.get("start_zoom", 1.0)))
	refresh()

# 水的格子上，疊上去的標記要高過水面（hunt_hd2d.json 的 water.<地形>.lift），不然被水蓋住
func _wl(c: Vector2i) -> float:
	var w: Dictionary = cfg.get("water", {}).get(rf.terrain(c), {})
	return float(w.get("lift", 0.0)) + 0.01 if not w.is_empty() else 0.0

func _flip(f: Vector2i):
	return (f.x < 0) if f.x != 0 else null

# 狼的姿勢：這一回合撲魚撲到了在吃、撲空撲出去、移動走路（兩張輪流）、原地等站著；滑鼠移動造成的重畫不換姿勢
var _last_round := -1

func _update_pose() -> void:
	if rf.rounds == _last_round and _last_wolf_pos.x > -999:
		return
	_last_round = rf.rounds
	if rf.caught > _last_caught:
		_pose = "eat"
	elif rf.attempts > _last_attempts:
		_pose = "lunge"
	elif rf.wolf_pos != _last_wolf_pos and _last_wolf_pos.x > -999:
		_pose = "walk_b" if rf.rounds % 2 == 1 else "walk"
	else:
		_pose = "stand"
	_last_attempts = rf.attempts
	_last_caught = rf.caught
	if rf.wolf_pos != _last_wolf_pos:
		var mv: Vector2i = rf.wolf_pos - _last_wolf_pos
		if _last_wolf_pos.x > -999 and mv != Vector2i.ZERO:
			_wolf_face = mv
		_last_wolf_pos = rf.wolf_pos

func paint() -> void:
	if rf == null:
		return
	var col: Dictionary = rcfg.get("colors", {})
	# 魚量：淺灘上一格的點（1～3 個點的大小），魚最多的地方畫一條鮭魚
	for y in rf.height:
		for x in rf.width:
			var c := Vector2i(x, y)
			var q: int = rf.fish_at(c)
			if q <= 0:
				continue
			quad(c, _col(col.get("fish", [0.95, 0.55, 0.45, 0.45])), 0.18 + 0.14 * q, 0.012 + _wl(c))
			if q >= int(rcfg.get("salmon_at", 3)) and not _salmon.is_empty() and (x * 7 + y * 3) % 2 == 0:
				_fish_sprite(c)
	# 灰熊的威嚇範圍（警告過你的那頭畫深一點）
	for i in rf.bears.size():
		var bp: Vector2i = rf.bears[i]["pos"]
		var r: int = rf.radius(i)
		var tc: Color = _col(col.get("threat_on" if bool(rf.bears[i]["warned"]) else "threat", [0.9, 0.25, 0.2, 0.2]))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = bp + Vector2i(dx, dy)
				if rf.in_bounds(c) and c != bp:
					quad(c, tc, 0.9, 0.02 + _wl(c))
	# 能走的格子
	if not rf.done:
		for c in rf.reachable().keys():
			quad(c, _col(col.get("move", [0.95, 0.85, 0.3, 0.32])), 0.86, 0.03 + _wl(c))
	# 熊吃剩的魚
	for c in rf.leftovers:
		frame(c, _col(col.get("leftover", [0.91, 0.63, 0.44, 0.95])), 0.04 + _wl(c))
		_fish_sprite(c)
	# 灰熊：朝向牠要去的地方（在捕魚時朝向你）；捕魚時用吃的圖，走路兩張輪流；小的那頭縮小
	var poses: Dictionary = rcfg.get("bear_poses", {})
	for i in rf.bears.size():
		var b: Dictionary = rf.bears[i]
		var bpos: Vector2i = b["pos"]
		var face: Vector2i = (Vector2i(b["target"]) - bpos) if not bool(b["fishing"]) else (rf.wolf_pos - bpos)
		var pose := "eat" if bool(b["fishing"]) else ("walk_b" if (rf.rounds + i) % 2 == 1 else "walk")
		if bool(b["warned"]):
			pose = "swipe"
		var art := hd_wolf_texture(str(poses.get(pose, "grizzly_stand")))
		if not bool(b["big"]):
			art["ps"] = float(art["ps"]) * float(rcfg.get("young_bear_scale", 0.75))
		unit("bear%d" % i, art, bpos, _flip(face))
	# 狼
	_update_pose()
	var wp: Dictionary = rcfg.get("wolf_poses", {})
	var wart := hd_wolf_texture(str(wp.get(_pose, wp.get("stand", "hdwolf_stand"))))
	# 次成年、老年的體型（主遊戲的縮放，同戰術狩獵）
	wart["ps"] = float(wart["ps"]) * float(GameState.wolf_display_scale())
	unit("wolf", wart, rf.wolf_pos, _flip(_wolf_face))
	if view != null:
		var hv: Vector2i = view.hover
		if hv.x >= 0 and in_map(hv):
			quad(hv, _col(col.get("hover", [1.0, 0.92, 0.45, 0.35])), 0.94, 0.05 + _wl(hv))

# 一條鮭魚（浮在水面上，一半在水裡）
func _fish_sprite(c: Vector2i) -> void:
	if _salmon.is_empty():
		return
	var tex: Texture2D = _salmon["tex"]
	var ps: float = float(_salmon["ps"])
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = ps
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.position = cell_center(c) + Vector3(0, _wl(c) + tex.get_height() * 0.25 * ps, 0)
	overlay.add_child(sp)
