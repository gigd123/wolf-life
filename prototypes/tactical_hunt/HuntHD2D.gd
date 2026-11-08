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

func setup(th) -> void:
	h = th
	# 冬季地面換成雪（winter_top：地形字元 → 材質）
	var top: Dictionary = cfg.get("summer_top", {}).duplicate()
	if top.is_empty():
		cfg["summer_top"] = (cfg["top"] as Dictionary).duplicate()
		top = cfg["summer_top"].duplicate()
	var winter: bool = str(h.game_mods.get("season", "")) == "winter"
	if winter:
		top.merge(cfg.get("winter_top", {}), true)
	cfg["top"] = top
	# 冬季的樹都積雪；外圍的地面跟著換
	if not cfg.has("summer_tree_mix"):
		cfg["summer_tree_mix"] = cfg.get("tree_mix", [])
	cfg["tree_mix"] = cfg.get("winter_tree_mix", ["pine_snow"]) if winter else cfg["summer_tree_mix"]
	# 固定圖的物件（大石頭）：冬天換 winter_art、其他季節換回 summer_art
	for tk in (cfg["trees"] as Dictionary).keys():
		var te: Dictionary = cfg["trees"][tk]
		if te.has("winter_art"):
			if not te.has("summer_art"):
				te["summer_art"] = te["art"]
			te["art"] = te["winter_art"] if winter else te["summer_art"]
	build(h.width, h.height, func(c: Vector2i) -> String: return h.terrain(c))
	focus_on(h.wolf_pos, float(cfg.get("start_zoom", 1.0)))
	refresh()

func _species_key(i: int) -> String:
	var sp: String = str(h.herd[i].get("species", "deer"))
	if h.is_fawn(i) and sp == "deer":
		return "fawn"
	# 同一群的成鹿混用兩種圖（馴鹿：公鹿、母鹿）：序號 % every == keep 的用原本的，其他用 mixed.key
	# random：每一隻開場時擲一次（記在牠身上，只給畫面用；駝鹿多半單獨出現，照序號會永遠是同一種）
	var mx: Dictionary = cfg.get("hd_art", {}).get(sp, {}).get("mixed", {})
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

func _art_for(key: String, state: String = "") -> Dictionary:
	var e: Array = cfg["species"].get(key, cfg["species"]["deer"])
	var winter: bool = str(h.game_mods.get("season", "")) == "winter"
	# 有 HD-2D 圖的獵物（hd_art）用那張
	var hd: Dictionary = cfg.get("hd_art", {}).get(key, {})
	if not hd.is_empty():
		if winter and hd.has("winter"):
			return hd_wolf_texture(str(hd["winter"]))
		return hd_wolf_texture(str(hd.get(state, hd["name"])))
	var a := HD2DBoard.animal_texture(str(e[0]), str(e[1]), float(e[2]), winter)
	if a.is_empty():
		e = cfg["species"]["deer"]
		a = HD2DBoard.animal_texture(str(e[0]), str(e[1]), float(e[2]))
	return a

func _flip(f: Vector2i):
	return (f.x < 0) if f.x != 0 else null

func paint() -> void:
	if h == null:
		return
	var col: Dictionary = cfg["colors"]
	var hid: bool = h.hidden_unfound()
	if h.deer_state == "unaware" and not hid:
		frame(h.deer_goal(), _col(col["goal"]), 0.02, 0.05)
	if hid:
		var ar: Rect2i = h.hidden_area
		for y in range(ar.position.y, ar.end.y):
			for x in range(ar.position.x, ar.end.x):
				if in_map(Vector2i(x, y)):
					quad(Vector2i(x, y), _col(col["hidden"]), 0.96, 0.015)
	if not h.done:
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
		unit("deer%d" % i, _art_for(_species_key(i), str(h.herd[i].get("state", ""))), h.herd[i]["pos"], _flip(h.herd[i]["facing"]))
		if bool(h.herd[i].get("weakest", false)):
			quad(h.herd[i]["pos"], _col(col["weakest"]), 0.22, 0.06)
	if not hid:
		if not h.done and not h.held:
			var dc := cell_center(h.deer_pos) + Vector3(0, 0.1, 0)
			for d in h.deer_intent():
				var v := Vector2(d).normalized() * float(h._flee_budget())
				line(dc, dc + Vector3(v.x, 0, v.y), _col(col["intent"]))
		var tint: Color = _col(col["held"]) if h.held else Color.WHITE
		unit("deer%d" % h.target, _art_for(_species_key(h.target), str(h.herd[h.target].get("state", ""))), h.deer_pos, _flip(h.deer_facing), tint)
		if h.herd.size() > 1:
			frame(h.deer_pos, _col(col["picked"]), 0.04, 0.05)
		if bool(h.herd[h.target].get("weakest", false)):
			quad(h.deer_pos, _col(col["weakest"]), 0.22, 0.06)
	# 狼與同伴
	var wf: Vector2i = view.wolf_facing if view != null else Vector2i(1, 0)
	unit("wolf", hd_wolf_texture("hdwolf_stand"), h.wolf_pos, _flip(wf))
	for k in range(1, h.wolves.size()):
		var w: Dictionary = h.wolves[k]
		var pos: Vector2i = w["pos"]
		var role: String = str(w["role"])
		var rc: Color = _col(col.get(role, col["chase"]))
		var last: Array = view.ally_last.get(k, [pos, h.deer_pos - pos]) if view != null else [pos, h.deer_pos - pos]
		unit("ally%d" % k, hd_wolf_texture("hdwolf_stand"), pos, _flip(last[1]), Color(0.82, 0.88, 0.98))
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
