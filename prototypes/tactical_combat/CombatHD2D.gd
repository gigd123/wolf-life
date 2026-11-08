class_name CombatHD2D
extends HD2DBoard
# 戰鬥原型的 HD-2D 畫面（2026-11-05，使用者：HD-2D 測試滿意，先套到戰鬥原型）。
# 共用的地形、鏡頭、點格子在 HD2DBoard；這裡只畫這一刻的戰鬥：單位、能走的格子、預告範圍、計畫、殘骸、注意力。
# 讀 TacticalCombatView 的 tc 與畫面狀態（planned、hover、hit_cells）。地形的高低只是畫面，規則照 data/tactical_combat.json。

const CFG_PATH := "res://prototypes/tactical_combat/combat_hd2d.json"

var view # TacticalCombatView
var tc: TacticalCombat

func _init() -> void:
	_init_board(CFG_PATH)

func setup(combat: TacticalCombat) -> void:
	tc = combat
	_out_seen.clear()
	_apply_season_period()
	build(tc.map.width, tc.map.height, func(c: Vector2i) -> String: return tc.map.terrain(c))
	refresh()

func _unit_art(i: int) -> Dictionary:
	var u: Dictionary = tc.units[i]
	var key: String = str(u["id"]) if str(u["species"]) == "wolf" else str(u["species"])
	var uc: Dictionary = cfg["units"].get(key, cfg["units"]["wolf"])
	if str(uc.get("art", "")) == "hd2d_wolf":
		var wp := _wolf_pose(i)
		# 有專屬圖的狼（黑狼，2026-11-08）：poses 有這個姿勢就用專屬圖、不調色；沒有的姿勢用灰狼的圖調色（modulate）
		var own: Dictionary = uc.get("poses", {})
		if own.has(wp):
			var t := hd_wolf_texture(str(own[wp]))
			t["mod"] = uc.get("poses_modulate", [1, 1, 1])
			return t
		return hd_wolf_texture(str(cfg["wolf_poses"].get(wp, cfg["wolf_poses"]["stand"])))
	# HD-2D 的新圖（Gemini，2026-11-06）：依姿勢挑一張——在吃 eat、預告看起來是揮掌或咬 swipe、撲擊 crouch、衝撞 charge、守食物 rear、上一回合有移動 walk／walk_b 輪流、沒動 stand
	var poses: Dictionary = uc.get("hd2d_poses", {})
	if not poses.is_empty():
		# 上一回合有移動：走路（兩格輪流）；沒動：站著
		var moved: bool = str(u.get("prev_mode", u.get("last_mode", ""))) != ""
		var pose := "stand" if poses.has("stand") and not moved else "walk"
		if pose == "walk" and poses.has("walk_b") and tc.rounds % 2 == 1:
			pose = "walk_b"
		if bool(u.get("eating", false)) and poses.has("eat"):
			pose = "eat"
		elif tc.intents.has(i) and str(tc.intents[i].get("looks", "")) in ["swipe", "bite"] and poses.has("swipe"):
			pose = "swipe"
		elif tc.intents.has(i) and str(tc.intents[i].get("looks", "")) == "pounce" and poses.has("crouch"):
			pose = "crouch" # 準備撲：伏低
		elif tc.intents.has(i) and str(tc.intents[i].get("looks", "")) == "charge" and poses.has("charge"):
			pose = "charge" # 衝撞（假衝看起來一樣）
		elif tc.intents.has(i) and str(tc.intents[i].get("looks", "")) == "guard" and poses.has("rear"):
			pose = "rear" # 守食物：用後腳站起來
		return hd_wolf_texture(str(poses.get(pose, poses.get("walk", ""))))
	return HD2DBoard.animal_texture(str(u["species"]), "adult", float(uc.get("width_cells", 1.8)))

# 主遊戲（Phase 2k 第 6 步）：冬天地面換雪、樹都積雪、不畫地面的草色斑塊；清晨、黃昏、夜裡、黎明前換光線
var _base_cfg: Dictionary = {}

func _apply_season_period() -> void:
	if _base_cfg.is_empty():
		_base_cfg = cfg.duplicate(true)
	cfg = _base_cfg.duplicate(true)
	if tc.season == "winter":
		(cfg["top"] as Dictionary).merge(cfg.get("winter_top", {}), true)
		cfg["tree_mix"] = cfg.get("winter_tree_mix", ["pine_snow"])
		cfg["ground_mix"] = {}
		var tr2: Dictionary = cfg["trees"]
		for k in tr2.keys():
			tr2[k]["art"] = "pine_snow"
		cfg["border"]["tree"] = "pine_snow"
		(cfg["tint"] as Dictionary).merge(cfg.get("winter_tint", {}), true)
		(cfg["colors"] as Dictionary).merge(cfg.get("winter_colors", {}), true)
		(cfg["colors"] as Dictionary).erase("_comment")
	var pd: Dictionary = cfg.get("periods", {}).get(tc.period, {})
	for k in pd.keys():
		cfg[k] = pd[k]

# 狼的姿勢（2026-11-06 Gemini 的灰狼）：退出的那一回合照退出的原因；你方照上一回合做了什麼；對手的狼照牠這一回合的預告
func _wolf_pose(i: int) -> String:
	var u: Dictionary = tc.units[i]
	if bool(u["out"]):
		match str(u["out_reason"]):
			"submit": return "submit"
			"knocked", "died": return "down"
		return "retreat"
	if str(u["carrying"]) != "":
		return "carry"
	var moved: bool
	if tc.player_side(i):
		var act: String = str(tc.plans.get(i, {}).get("action", ""))
		if act in ["bite", "pounce", "harass", "pin"]:
			return "lunge"
		if act == "threaten":
			return "threaten"
		if float(u["hp"]) <= float(u["hp_max"]) * float(cfg.get("hurt_ratio", 0.25)):
			return "hurt"
		var mode: String = str(u.get("last_mode", u.get("prev_mode", "")))
		if mode == "creep":
			return "stalk"
		moved = mode != ""
	else:
		var looks: String = str(tc.intents.get(i, {}).get("looks", ""))
		if looks in ["bite", "pin"]:
			return "ready"
		if looks == "threaten":
			return "threaten"
		if looks == "back_off":
			return "retreat"
		if float(u["hp"]) <= float(u["hp_max"]) * float(cfg.get("hurt_ratio", 0.25)):
			return "hurt"
		moved = looks == "move"
	if moved:
		return "walk" if tc.rounds % 2 == 0 else ("walk_b" if cfg["wolf_poses"].has("walk_b") else "stand")
	return "stand"

# 退出的單位留在原地一回合（看得到牠是示弱、被打倒還是撤走）：第一次看到牠退出的回合
var _out_seen := {}

func _show_unit(i: int) -> bool:
	if tc.active(i):
		_out_seen.erase(i)
		return true
	var u: Dictionary = tc.units[i]
	if str(u["species"]) != "wolf" and not bool(_opp_cfg_wolf(i)):
		return false # 熊、美洲獅走了就不畫（上樹、離開）
	if not _out_seen.has(i):
		_out_seen[i] = tc.rounds
	return int(_out_seen[i]) == tc.rounds

func _opp_cfg_wolf(i: int) -> bool:
	return bool(tc.cfg["opponents"].get(str(tc.units[i]["species"]), {}).get("wolf", false))

func paint() -> void:
	if tc == null:
		return
	var col: Dictionary = cfg["colors"]
	for i in tc.units.size():
		if not _show_unit(i):
			continue
		var u: Dictionary = tc.units[i]
		var key: String = str(u["id"]) if str(u["species"]) == "wolf" else str(u["species"])
		var uc: Dictionary = cfg["units"].get(key, cfg["units"]["wolf"])
		var tags: Array = []
		if bool(u.get("eating", false)):
			tags.append(tr("tcombat.hd.eating"))
		if str(u["carrying"]) != "":
			tags.append(tr("tcombat.hd.carrying"))
		var f: Vector2i = u["facing"]
		var art := _unit_art(i)
		unit("u%d" % i, art, u["pos"], (f.x < 0) if f.x != 0 else null, _col(art.get("mod", uc.get("modulate", [1, 1, 1]))), " ".join(tags))
	if not tc.done:
		var reach: Dictionary = tc.reachable(0)
		for c in reach.keys():
			quad(c, _col(col.get(str(reach[c]), col["trot"])), 0.86, 0.01)
	for e in tc.intents.keys():
		var seen: Dictionary = tc.intents[e].get("seen", {})
		var clear: bool = int(seen.get("level", 0)) >= 2
		for c in seen.get("zone", []):
			quad(c, _col(col["zone_clear" if clear else "zone_partial"]), 0.98, 0.02)
	if view != null:
		var planned: Vector2i = view.planned
		if planned.x >= 0:
			quad(planned, _col(col["planned"]), 0.7, 0.03)
			line(cell_center(tc.units[0]["pos"]) + Vector3(0, 0.05, 0), cell_center(planned) + Vector3(0, 0.05, 0), _col(col["path"]))
		var hv: Vector2i = view.hover
		if hv.x >= 0 and tc.map.in_bounds(hv):
			quad(hv, _col(col["hover"]), 0.94, 0.035)
		for c in view.hit_cells:
			quad(c, _col(col["hit"]), 0.5, 0.04)
	if not tc.carcass.is_empty() and int(tc.carcass["segments"]) > 0:
		var cc: Dictionary = cfg["carcass"]
		var hdc: Dictionary = cc.get("hd", {})
		if not hdc.is_empty():
			var art: Dictionary = hd_wolf_texture(str(hdc.get(str(tc.carcass.get("animal", "")), hdc["_default"])))
			sprite_at(art["tex"], float(art["ps"]), tc.carcass["pos"])
		else:
			var tex: Texture2D = load(str(cc.get(str(tc.carcass.get("animal", "")), cc["_default"])))
			sprite_at(tex, 1.0 / float(cc["px_per_cell"]), tc.carcass["pos"])
		label(cell_center(tc.carcass["pos"]) + Vector3(0.3, 0.7, 0), str(tc.carcass["segments"]), Color(1, 0.85, 0.75))
	for d in tc.drops:
		quad(d["pos"], Color(0.45, 0.18, 0.12, 0.9), 0.35, 0.05)
	for i in tc.units.size():
		if tc.active(i) and not tc.player_side(i):
			var a: int = int(tc.units[i].get("attention", -1))
			if a >= 0 and tc.active(a):
				line(cell_center(tc.units[i]["pos"]) + Vector3(0, 0.6, 0), cell_center(tc.units[a]["pos"]) + Vector3(0, 0.4, 0), _col(col["attention"]))
