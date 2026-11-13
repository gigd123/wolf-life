class_name HuntHD2D
extends HD2DBoard
# 戰術狩獵的 HD-2D 畫面（2026-11-05，使用者：戰鬥原型的 HD-2D 可以，戰術場景也改看看）。
# 共用的地形、鏡頭、點格子在 HD2DBoard；這裡照 TacticalHuntView._draw_map 畫同樣的東西：
# 能走的格子、可以撲的格子（紅框）、前截鎖喉（紫框）、鹿的目的地、躲在草裡的範圍、母子線、逃跑的意圖、目標（黃框）、最弱的一隻（橘點）、狼與同伴。
# 地形的高低只是畫面（岩坡、峭壁高一點，水低一點），規則照 data/tactical_hunt.json。

const CFG_PATH := "res://prototypes/tactical_hunt/hunt_hd2d.json"

var view # TacticalHuntView（讀 h、hover、lock_armed、wolf_facing、ally_last）
var h

func _init() -> void:
	_init_board(CFG_PATH)

var _base_cfg: Dictionary = {}

func setup(th) -> void:
	h = th
	_last_wolf_pos = Vector2i(-999, -999)
	# 每一場從設定檔的原樣開始（地圖、季節的覆蓋不會留到下一場）
	if _base_cfg.is_empty():
		_base_cfg = cfg.duplicate(true)
	cfg = _base_cfg.duplicate(true)
	var winter: bool = str(h.game_mods.get("season", "")) == "winter"
	# 每張地圖自己的樹、地面（map_sets，2026-11-08）：先蓋，再套冬天
	apply_map_set(str(h.game_mods.get("world_map", "")))
	cfg["winter"] = winter
	cfg["season"] = str(h.game_mods.get("season", ""))
	if winter:
		# 地面換成雪、樹換積雪的那組、顏色倍率與斑塊用冬天的（密林原本調深調綠，疊在雪上會變成綠色色塊）
		(cfg["top"] as Dictionary).merge(cfg.get("winter_top", {}), true)
		cfg["tree_mix"] = cfg.get("winter_tree_mix", ["pine_snow"])
		(cfg["tint"] as Dictionary).merge(cfg.get("winter_tint", {}), true)
		(cfg["tint"] as Dictionary).erase("_comment")
		(cfg["ground_mix"] as Dictionary).merge(cfg.get("winter_ground_mix", {}), true)
		# 固定圖的物件（大石頭、倒木）：冬天換 winter_art
		for tk in (cfg["trees"] as Dictionary).keys():
			var te: Dictionary = cfg["trees"][tk]
			if te.has("winter_art"):
				te["art"] = te["winter_art"]
	build(h.width, h.height, func(c: Vector2i) -> String: return h.terrain(c))
	focus_on(h.wolf_pos, float(cfg.get("start_zoom", 1.0)))
	refresh()

# 狼的姿勢（2026-11-08）：咬住獵物（或獵到了）咬住不放、潛行、小跑或衝刺時走路兩格輪流、沒動站著
func _wolf_pose() -> String:
	var wp: Dictionary = cfg.get("wolf_poses", {})
	var pose := "stand"
	if h.held or (h.done and str(h.result) == "caught"):
		pose = "hold"
	else:
		match str(h.last_mode):
			"creep":
				pose = "stalk"
			"trot", "sprint":
				pose = "walk_b" if h.rounds % 2 == 1 else "walk"
	return str(wp.get(pose, wp.get("stand", "hdwolf_stand")))

# 同伴的姿勢：咬住獵物 hold（苔原狼沒有咬住的圖 → 撲咬）、潛行、小跑或衝刺走路兩張輪流（苔原狼只有一張走路）、沒動站著
func _ally_pose(k: int, own: bool) -> String:
	var w: Dictionary = h.wolves[k]
	var pose := "stand"
	if not h.done and h._ally_holding() == k:
		pose = "hold"
	else:
		match str(w.get("mode", "still")):
			"creep":
				pose = "stalk"
			"trot", "sprint":
				pose = "walk_b" if (h.rounds + k) % 2 == 1 else "walk"
	if own:
		var wp: Dictionary = cfg.get("wolf_poses", {})
		return str(wp.get(pose, wp.get("stand", "hdwolf_stand")))
	var tp: Dictionary = cfg.get("tundra_poses", {})
	return str(tp.get(pose, tp.get("stand", "tundrawolf_stand")))

func _species_key(i: int) -> String:
	var sp: String = str(h.herd[i].get("species", "deer"))
	if h.is_fawn(i) and sp == "deer":
		return "fawn"
	# 同一群的成鹿混用兩種圖（馴鹿：公鹿、母鹿）：序號 % every == keep 的用原本的，其他用 mixed.key
	# random：每一隻開場時擲一次（記在牠身上，只給畫面用；駝鹿多半單獨出現，照序號會永遠是同一種）
	var mx: Dictionary = cfg.get("hd_art", {}).get(sp, {}).get("mixed", {})
	# 遊戲記下了公母（game.male_share）：公的用原本的圖、母的用 mixed.key
	if not mx.is_empty() and not h.is_fawn(i) and h.herd[i].has("male"):
		return sp if bool(h.herd[i]["male"]) else str(mx["key"])
	if not mx.is_empty() and not h.is_fawn(i):
		var every: int = int(mx.get("every", 2))
		var v: int = i % every
		if bool(mx.get("random", false)):
			if not h.herd[i].has("_hd_variant"):
				h.herd[i]["_hd_variant"] = randi() % every
			v = int(h.herd[i]["_hd_variant"])
		if v != int(mx.get("keep", 0)):
			return str(mx["key"])
	# 公鹿（主遊戲）：沒有自己的戰術物種的（白尾鹿、騾鹿）用 <物種>_buck 的圖
	if str(h.game_mods.get("life_stage", "")) == "buck" and not h.is_fawn(i) and cfg.get("hd_art", {}).has(sp + "_buck"):
		return sp + "_buck"
	return sp

func _art_for(key: String, state: String = "", idx: int = 0) -> Dictionary:
	var e: Array = cfg["species"].get(key, cfg["species"]["deer"])
	var winter: bool = str(h.game_mods.get("season", "")) == "winter"
	# 有 HD-2D 圖的獵物（hd_art）用那張
	var hd: Dictionary = cfg.get("hd_art", {}).get(key, {})
	if not hd.is_empty():
		if winter and hd.has("winter"):
			return hd_wolf_texture(str(hd["winter"]))
		# 跑的第二張（2026-11-12）：逃跑時每回合和「跑」輪流；鹿群裡每一隻錯開一格，不會整群同一個步伐
		if state == "flee" and hd.has("flee_b") and (h.rounds + idx) % 2 == 1:
			return hd_wolf_texture(str(hd["flee_b"]))
		return hd_wolf_texture(str(hd.get(state, hd["name"])))
	var a := HD2DBoard.animal_texture(str(e[0]), str(e[1]), float(e[2]), winter)
	if a.is_empty():
		e = cfg["species"]["deer"]
		a = HD2DBoard.animal_texture(str(e[0]), str(e[1]), float(e[2]))
	return a

var _last_wolf_pos := Vector2i(-999, -999)
var _wolf_face := Vector2i(1, 0)

func _flip(f: Vector2i):
	return (f.x < 0) if f.x != 0 else null

func paint() -> void:
	if h == null:
		return
	var col: Dictionary = cfg["colors"]
	var hid: bool = h.hidden_unfound() or h.track_pending # 密林裡不見了（Phase 2m）：不畫出牠在哪
	if h.deer_state == "unaware" and not hid:
		frame(h.deer_goal(), _col(col["goal"]), 0.02, 0.05)
	if hid:
		var ar: Rect2i = h.hidden_area
		for y in range(ar.position.y, ar.end.y):
			for x in range(ar.position.x, ar.end.x):
				if in_map(Vector2i(x, y)):
					quad(Vector2i(x, y), _col(col["hidden"]), 0.96, 0.015)
	# 能走的格子：點自己的狼才顯示（2026-11-08）
	if not h.done and (view == null or bool(view.range_shown)):
		var reach: Dictionary = h.reachable()
		for c in reach.keys():
			quad(c, _col(col.get(str(reach[c]), col["trot"])), 0.86, 0.01)
		for c in h.pounce_targets().keys():
			frame(c, _col(col["target"]), 0.03)
		if view != null and view.lock_armed:
			for c in h.front_lock_targets().keys():
				frame(c, _col(col["lock"]), 0.035)
	# 鹿群
	for i in h.active_deer():
		var m: int = int(h.herd[i]["mother"])
		if m >= 0 and not bool(h.herd[m]["gone"]) and not bool(h.herd[i]["separated"]):
			line(cell_center(h.herd[i]["pos"]) + Vector3(0, 0.15, 0), cell_center(h.herd[m]["pos"]) + Vector3(0, 0.15, 0), _col(col["bond"]))
		if i == h.target:
			continue
		var wk: bool = bool(h.herd[i].get("weakest", false))
		unit("deer%d" % i, _art_for(_species_key(i), str(h.herd[i].get("state", "")), i), h.herd[i]["pos"], _flip(h.herd[i]["facing"]), Color.WHITE, tr("tactical.hd.weakest") if wk else "", _col(col["weakest"]))
		if wk:
			frame(h.herd[i]["pos"], _col(col["weakest"]), 0.05, 0.05)
	if not hid:
		if not h.done and not h.held:
			var dc := cell_center(h.deer_pos) + Vector3(0, 0.1, 0)
			for d in h.deer_intent():
				var v := Vector2(d).normalized() * float(h._flee_budget())
				line(dc, dc + Vector3(v.x, 0, v.y), _col(col["intent"]))
		var tint: Color = _col(col["held"]) if h.held else Color.WHITE
		# 觀察後看出的最弱的那一隻（2026-11-08：原本只在腳下畫一小塊，被圖蓋住看不到）→ 頭上寫「最弱」、橘色框
		var wkt: bool = bool(h.herd[h.target].get("weakest", false))
		unit("deer%d" % h.target, _art_for(_species_key(h.target), str(h.herd[h.target].get("state", "")), h.target), h.deer_pos, _flip(h.deer_facing), tint, tr("tactical.hd.weakest") if wkt else "", _col(col["weakest"]))
		if wkt:
			frame(h.deer_pos, _col(col["weakest"]), 0.05, 0.06)
		elif h.herd.size() > 1:
			frame(h.deer_pos, _col(col["picked"]), 0.04, 0.05)
	# 狼與同伴
	# 狼的面向（2026-11-08：原本只有 2D 畫面在算，HD-2D 一直面向右）：上一步移動的方向；沒動過時朝向獵物
	if h.wolf_pos != _last_wolf_pos:
		var mv: Vector2i = h.wolf_pos - _last_wolf_pos
		_wolf_face = mv if _last_wolf_pos.x > -99 else h.deer_pos - h.wolf_pos
		_last_wolf_pos = h.wolf_pos
	var wf: Vector2i = _wolf_face
	var wart := hd_wolf_texture(_wolf_pose())
	wart["ps"] = float(wart["ps"]) * float(h.game_mods.get("wolf_scale", 1.0))
	unit("wolf", wart, h.wolf_pos, _flip(wf))
	for k in range(1, h.wolves.size()):
		var w: Dictionary = h.wolves[k]
		var pos: Vector2i = w["pos"]
		var role: String = str(w["role"])
		var rc: Color = _col(col.get(role, col["chase"]))
		var last: Array = view.ally_last.get(k, [pos, h.deer_pos - pos]) if view != null else [pos, h.deer_pos - pos]
		# 同伴也跟著動作換姿勢（2026-11-11）：你的狼群用灰狼的圖（調一點藍），苔原狼用苔原狼的圖
		var own: bool = bool(w.get("own", false))
		unit("ally%d" % k, hd_wolf_texture(_ally_pose(k, own)), pos, _flip(last[1]), Color(0.82, 0.88, 0.98) if own else Color.WHITE)
		quad(pos, rc, 0.24, 0.05)
		if not h.done:
			var aim0: Vector2i = w.get("aim", pos)
			var aim := Vector2i(clampi(aim0.x, 0, h.width - 1), clampi(aim0.y, 0, h.height - 1))
			if aim != pos:
				line(cell_center(pos) + Vector3(0, 0.12, 0), cell_center(aim) + Vector3(0, 0.12, 0), rc)
		if str(w.get("intent", "")) == "holding":
			frame(h.deer_pos, Color(1.0, 0.38, 0.31, 0.95), 0.045)
	if view != null:
		var hv: Vector2i = view.hover
		if hv.x >= 0 and in_map(hv):
			quad(hv, _col(col["hover"]), 0.94, 0.04)
