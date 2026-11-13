class_name FireHD2D
extends HD2DBoard
# 森林大火逃生地圖的 HD-2D 畫面（Phase 2n 第 5 步，2026-11-13）。共用的地形、鏡頭、點格子在 HD2DBoard；邏輯全在 FireEscape。
# 設定：戰術狩獵的 hunt_hd2d.json 為底，fire_hd2d.json 蓋過去（火場多的地形字元、火的演出）。
# 畫的東西：
#   地面：地形 shader 的 state_tex（一格一個像素）——燒焦的程度、餘燼的火光、看不看得到（沒看過的很暗、看過但被煙遮住的灰暗）
#   樹：燃燒中偏橘、剛燒過與焦土換成燒焦的圖（burnt_*）、沒看過的不畫
#   火焰（三格輪流，有風時往下風倒）、剛點燃的小火、煙團（照程度的透明度，往下風偏、慢慢飄）、火星、火光（幾盞 OmniLight，照燃燒的格子分群）
#   光線：站的地方煙越濃，太陽越暗越橘、霧越濃；夜裡環境光變暗（火更顯眼）
#   右上角的風向箭頭與文字（風力越強箭頭越長）
#   能走的格子、巢穴洞口、地圖四邊連到的區域（在燒的那一邊畫紅線）、狼

const BASE_CFG := "res://prototypes/tactical_hunt/hunt_hd2d.json"
const FIRE_CFG := "res://prototypes/fire_escape/fire_hd2d.json"

var fe # FireEscape
var view # FireEscapeView（hover、_side_label、_wind_text）
var fx_root: Node3D
var flames := {} # 格子 → {sprite, phase, small}
var smokes := {} # 格子 → {sprite, base: Vector3, phase}
var ember_sprites := {} # 格子 → Sprite3D
var lights: Array = [] # OmniLight3D
var light_base: Array = [] # 每盞的基本亮度
var state_img: Image
var state_tex: ImageTexture
var water_planes := {} # 格子 → [StandardMaterial3D, 原本的顏色]
var env: Environment
var sun: DirectionalLight3D
var env_base := {}
var wind_box: Control
var wind_label: Label
var _base_cfg := {}
var _t := 0.0
var _frame := 0
var _last_wolf := Vector2i(-999, -999)
var _face := Vector2i(1, 0)
var _moved_round := -1 # 這一回合有移動（走路的姿勢）

func _init() -> void:
	_init_board(BASE_CFG)
	_merge(cfg, JSON.parse_string(FileAccess.get_file_as_string(FIRE_CFG)))
	_base_cfg = cfg.duplicate(true)
	# 風向（右上角）：箭頭 + 文字
	wind_box = Control.new()
	wind_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_box.custom_minimum_size = Vector2(34, 34)
	wind_box.size = Vector2(34, 34)
	wind_box.draw.connect(_draw_wind)
	add_child(wind_box)
	wind_label = Label.new()
	wind_label.theme_type_variation = &"SmallLabel"
	wind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wind_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	wind_label.add_theme_constant_override("outline_size", 4)
	add_child(wind_label)
	resized.connect(_place_wind)

static func _merge(a: Dictionary, b: Dictionary) -> void:
	for k in b:
		if a.has(k) and a[k] is Dictionary and b[k] is Dictionary:
			_merge(a[k], b[k])
		else:
			a[k] = b[k].duplicate(true) if (b[k] is Dictionary or b[k] is Array) else b[k]

func _place_wind() -> void:
	wind_box.position = Vector2(size.x - 38, 4)
	wind_label.position = Vector2(0, 38)
	wind_label.size = Vector2(size.x - 4, 14)

# 每一場：照火場建地圖
func setup(p_fe, season: String = "") -> void:
	fe = p_fe
	cfg = _base_cfg.duplicate(true)
	cfg["season"] = season
	flames.clear()
	smokes.clear()
	ember_sprites.clear()
	lights.clear()
	light_base.clear()
	water_planes.clear()
	_last_wolf = Vector2i(-999, -999)
	_moved_round = -1
	_animal_last.clear()
	# 舊的地圖會被釋放：建好新的之前不要畫火（build 裡鏡頭換素材大小時會呼叫 refresh）
	state_img = null
	fx_root = null
	build(fe.width, fe.height, func(c: Vector2i) -> String: return fe.terrain(c))
	_hook_world()
	focus_on(fe.wolf_pos, float(cfg.get("start_zoom", 1.0)))
	_place_wind()
	refresh()

# 建好地圖之後：地形材質接上 state_tex、找出水面、環境與太陽、放火光
func _hook_world() -> void:
	state_img = Image.create(map_w, map_h, false, Image.FORMAT_RGBA8)
	state_img.fill(Color(0, 0, 1, 1))
	state_tex = ImageTexture.create_from_image(state_img)
	for m in mats.values():
		var sm: ShaderMaterial = m
		sm.set_shader_parameter("use_state", true)
		sm.set_shader_parameter("state_tex", state_tex)
		sm.set_shader_parameter("state_size", Vector2(map_w, map_h))
	for ch in world.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is PlaneMesh and (ch as MeshInstance3D).material_override is StandardMaterial3D:
			var p: Vector3 = (ch as MeshInstance3D).position
			var c := Vector2i(int(floor(p.x)), int(floor(p.z)))
			if in_map(c):
				var wm: StandardMaterial3D = (ch as MeshInstance3D).material_override
				water_planes[c] = [wm, wm.albedo_color]
		elif ch is WorldEnvironment:
			env = (ch as WorldEnvironment).environment
		elif ch is DirectionalLight3D:
			sun = ch
	if env != null:
		env_base = {"fog": env.fog_light_color, "density": env.fog_density, "ambient": env.ambient_light_color, "ambient_e": env.ambient_light_energy, "bg": env.background_color}
	if sun != null:
		env_base["sun"] = sun.light_color
		env_base["sun_e"] = sun.light_energy
	fx_root = Node3D.new()
	world.add_child(fx_root)
	var fx: Dictionary = cfg["fx"]
	for i in int(fx.get("light_max", 8)):
		var l := OmniLight3D.new()
		l.light_color = _col(fx["light_color"])
		l.omni_range = float(fx.get("light_range", 5.0))
		l.shadow_enabled = false
		l.visible = false
		fx_root.add_child(l)
		lights.append(l)
		light_base.append(0.0)

# 一格看不看得到：2 看得到、1 看過（被煙遮住）、0 沒看過
func _vis(p: Vector2i) -> int:
	if fe.visible(p):
		return 2
	return 1 if fe.known.has(p) else 0

# 沒看過但火光照得到（燃燒的格子在兩倍視線內）
func _glow_seen(p: Vector2i) -> bool:
	return fe.burning(p) and fe._cheb(p, fe.wolf_pos) <= fe.sight_radius() * 2

func _fire_state(p: Vector2i) -> String:
	var s: String = fe.state(p)
	if s == "" and fe.terrain(p) == "x":
		return "ash"
	return s

func refresh() -> void:
	super.refresh()
	if fe == null or world == null or state_img == null or fx_root == null:
		return
	_update_state()
	_update_trees()
	_update_fx()
	_update_mood()
	_update_wind()

func _load_trees() -> void:
	super._load_trees()
	if fe != null and state_img != null:
		_update_trees()
		for c in flames.keys():
			_size_flame(c)

# --- 地面 ---
func _update_state() -> void:
	for y in map_h:
		for x in map_w:
			var p := Vector2i(x, y)
			var v: int = _vis(p)
			var st: String = _fire_state(p)
			var r := 0.0
			var g := 0.0
			match st:
				"burning":
					r = 0.5
					g = 0.6 if bool(fe.fire[p].get("small", false)) else 1.0
				"hot":
					r = 0.85
					g = 0.45
				"ash":
					r = 1.0
			if v == 0 and not _glow_seen(p):
				g = 0.0
			state_img.set_pixel(x, y, Color(r, g, [0.0, 0.45, 1.0][v], 1.0))
			if water_planes.has(p):
				var wm: StandardMaterial3D = water_planes[p][0]
				var base: Color = water_planes[p][1]
				var k: float = [0.12, 0.45, 1.0][v]
				wm.albedo_color = Color(base.r * k, base.g * k, base.b * k, base.a)
	state_tex.update(state_img)

# --- 樹 ---
func _update_trees() -> void:
	var fx: Dictionary = cfg["fx"]
	var burnt_map: Dictionary = fx.get("burnt", {})
	for t in tree_sprites:
		var c: Vector2i = t["cell"]
		if not in_map(c):
			continue
		var s: Sprite3D = t["sprite"]
		var v: int = _vis(c)
		if v == 0:
			s.visible = false
			continue
		var st: String = _fire_state(c)
		var art: String = str(t["art"])
		if st in ["hot", "ash"]:
			art = str(burnt_map.get(art, "burnt_" + art))
			if art == "" or not ResourceLoader.exists(HD_DIR + "assets/%s_%d.png" % [art, art_px]):
				s.visible = false
				continue
		s.visible = true
		var tex: Texture2D = load(HD_DIR + "assets/%s_%d.png" % [art, art_px])
		if s.texture != tex:
			s.texture = tex
			s.offset = Vector2(0, tex.get_height() * 0.5 - 2)
		var tint := Color.WHITE
		if st == "burning":
			tint = _col(fx["burning_tint"])
		elif st == "hot":
			tint = _col(fx["hot_tint"])
		if v == 1:
			var rt: Color = _col(fx["remembered_tint"])
			tint = Color(tint.r * rt.r, tint.g * rt.g, tint.b * rt.b)
		s.modulate = Color(tint.r, tint.g, tint.b, s.modulate.a)

func _has_tree(c: Vector2i) -> bool:
	for t in tree_sprites:
		if t["cell"] == c and not str(t["art"]) in ["stones", "stones_winter", "boulder", "cave", "reeds"]:
			return true
	return false

# --- 火焰、煙、火星、火光 ---
func _fx_sprite(shaded: bool = false) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = shaded
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(s)
	return s

func _update_fx() -> void:
	var fx: Dictionary = cfg["fx"]
	# 火焰：看得到的燃燒格子（看不到但火光照得到的也畫）
	var want := {}
	for p in fe.burning_cells():
		if _vis(p) > 0 or _glow_seen(p):
			want[p] = true
	for c in flames.keys():
		if not want.has(c):
			(flames[c]["sprite"] as Sprite3D).queue_free()
			flames.erase(c)
	for c in want:
		var small: bool = bool(fe.fire[c].get("small", false))
		if not flames.has(c):
			var s := _fx_sprite()
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			flames[c] = {"sprite": s, "phase": (c.x * 7 + c.y * 3) % 3, "crown": _has_tree(c) and fe.terrain(c) in ["f", "a", "l"]}
		flames[c]["small"] = small
		_size_flame(c)
	# 煙團：看過的格子（輕煙隔一格畫一團，太多會糊成一片）
	var swant := {}
	for y in map_h:
		for x in map_w:
			var p := Vector2i(x, y)
			var lv: int = fe.smoke_at(p)
			if lv <= 0 or _vis(p) == 0:
				continue
			if lv == 1 and (x + y) % 2 == 1:
				continue
			swant[p] = lv
	for c in smokes.keys():
		if not swant.has(c):
			(smokes[c]["sprite"] as Sprite3D).queue_free()
			smokes.erase(c)
	var drift: float = float(fx["smoke_drift"]) * (fe.strength + 0.5)
	for c in swant:
		var lv: int = swant[c]
		if not smokes.has(c):
			var s := _fx_sprite()
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			s.texture = load(HD_DIR + "assets/smoke_puff_%s_%d.png" % ["a" if (c.x + c.y * 3) % 2 == 0 else "b", 32])
			smokes[c] = {"sprite": s, "phase": float((c.x * 13 + c.y * 7) % 10) / 10.0}
		var sp: Sprite3D = smokes[c]["sprite"]
		# 每一團大小、位置稍微錯開（不然排成整齊的一列一列）
		sp.pixel_size = float(fx["smoke_scale"][lv]) * lerpf(0.75, 1.2, _hash01(c.x, c.y, 41)) / 32.0
		sp.flip_h = _hash01(c.x, c.y, 47) < 0.5
		var a: float = float(fx["smoke_alpha"][lv])
		# 燃燒中的格子：煙往上冒，貼地的少（看得到火）
		if fe.burning(c):
			a *= 0.45
		if fe._cheb(c, fe.wolf_pos) <= 1:
			a *= float(fx["smoke_near_wolf"])
		if _vis(c) == 1:
			a *= 0.7
		# 煙不受光（unshaded）：夜裡調暗；火旁邊的煙被火光照成橘色
		var tint: Color = _col(fx["smoke_night"]) if fe.night else Color.WHITE
		if _near_fire(c, 2):
			var wt: Color = _col(fx["smoke_firelit"])
			tint = Color(tint.r * wt.r, tint.g * wt.g, tint.b * wt.b) if not fe.night else wt
		sp.modulate = Color(tint.r, tint.g, tint.b, a)
		var jit := Vector3((_hash01(c.x, c.y, 43) - 0.5) * 0.8, (_hash01(c.x, c.y, 49) - 0.5) * 0.3, (_hash01(c.x, c.y, 45) - 0.5) * 0.8)
		smokes[c]["base"] = cell_center(c) + jit + Vector3(fe.wind.x * drift, float(fx["smoke_lift"][lv]) + (0.5 if fe.burning(c) else 0.0), fe.wind.y * drift)
		sp.position = smokes[c]["base"]
	# 火星
	for c in ember_sprites.keys():
		if not fe.embers.has(c) or _vis(c) < 2:
			(ember_sprites[c] as Sprite3D).queue_free()
			ember_sprites.erase(c)
	for c in fe.embers:
		if _vis(c) < 2 or ember_sprites.has(c):
			continue
		var es := _fx_sprite()
		es.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		es.texture = load(HD_DIR + "assets/fire_ember_32.png")
		es.pixel_size = 1.0 / 32.0
		es.position = cell_center(c) + Vector3(0, 0.35, 0.1)
		ember_sprites[c] = es
	_update_lights()
	_animate()

func _near_fire(c: Vector2i, r: int) -> bool:
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if fe.burning(Vector2i(x, y)):
				return true
	return false

# 地圖上的邊的名字：短（主遊戲寫連到的區域，在燒的加「在燒」；完整的說明在右欄）
func _edge_text(s: String) -> String:
	var t: String = tr("fire.side." + s)
	if view != null and bool(view.game_mode):
		var r: String = str((fe.get_meta("sides", {}) as Dictionary).get(s, {}).get("region", ""))
		if r != "":
			t = tr("region." + r)
	if fe.edges_burning.has(s):
		t += "・" + tr("fire.ui.burning")
	return t

# 地圖四邊的區域名稱：比 HD2DBoard.label 大（整張地圖放進畫面時也看得到）
func _edge_label(p: Vector3, text: String, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var lb := Label3D.new()
	lb.horizontal_alignment = align
	lb.text = text
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = float(cfg["fx"].get("edge_label_px", 0.03))
	lb.font_size = 32
	lb.outline_size = 10
	lb.modulate = color
	lb.no_depth_test = true
	lb.position = p
	overlay.add_child(lb)

func _size_flame(c: Vector2i) -> void:
	var fx: Dictionary = cfg["fx"]
	var f: Dictionary = flames[c]
	var s: Sprite3D = f["sprite"]
	var sc: float = float(fx["small"]) if bool(f["small"]) else float(fx["flame_scale"].get(fe.terrain(c), 0.8)) * (float(fx["crown"]) if bool(f["crown"]) else 1.0)
	s.pixel_size = sc / float(art_px)
	var j := Vector3(((c.x * 37 + c.y * 11) % 7 - 3) * 0.03, 0, 0.18)
	s.position = cell_center(c) + j
	if s.texture != null:
		s.offset = Vector2(0, s.texture.get_height() * 0.5 - 1)

# 火光：把看得到的燃燒格子照 light_block 格分群，最大的幾群各放一盞
func _update_lights() -> void:
	var fx: Dictionary = cfg["fx"]
	var blk: int = int(fx.get("light_block", 6))
	var groups := {}
	for c in flames.keys():
		var k := Vector2i(c.x / blk, c.y / blk)
		if not groups.has(k):
			groups[k] = [0, Vector2.ZERO]
		groups[k][0] += 1
		groups[k][1] += Vector2(c) + Vector2(0.5, 0.5)
	var keys: Array = groups.keys()
	keys.sort_custom(func(a, b): return int(groups[a][0]) > int(groups[b][0]))
	var le: Array = fx["light_energy"]
	for i in lights.size():
		var l: OmniLight3D = lights[i]
		if i >= keys.size():
			l.visible = false
			continue
		var g: Array = groups[keys[i]]
		var ctr: Vector2 = g[1] / float(g[0])
		l.visible = true
		l.position = Vector3(ctr.x, 1.2, ctr.y)
		light_base[i] = minf(float(le[2]), float(le[0]) + float(le[1]) * float(g[0]))
		l.light_energy = light_base[i]

# 每 frame_sec 秒：火焰換格、煙慢慢飄、火星閃、火光跳動、地上的餘燼明暗
func _animate() -> void:
	var lean: bool = fe.strength >= 1 and absf(fe.wind.x) > 0.3
	var frames := "abc"
	for c in flames:
		var f: Dictionary = flames[c]
		var s: Sprite3D = f["sprite"]
		var i: int = (_frame + int(f["phase"])) % 3
		var name: String
		if bool(f["small"]):
			name = "fire_small_%s" % ["a", "b"][i % 2]
		else:
			name = ("fire_flame_lean_%s" if lean else "fire_flame_%s") % frames[i]
		var tex: Texture2D = load(HD_DIR + "assets/%s_%d.png" % [name, art_px])
		if s.texture != tex:
			s.texture = tex
			s.offset = Vector2(0, tex.get_height() * 0.5 - 1)
		s.flip_h = lean and fe.wind.x < 0
	var drift: float = 0.12 * (fe.strength + 1)
	for c in smokes:
		var sm: Dictionary = smokes[c]
		var ph: float = fmod(float(sm["phase"]) + _frame * 0.04 * (fe.strength + 1), 1.0)
		(sm["sprite"] as Sprite3D).position = (sm["base"] as Vector3) + Vector3(fe.wind.x * drift * ph, ph * 0.25, fe.wind.y * drift * ph)
	for c in ember_sprites:
		(ember_sprites[c] as Sprite3D).visible = (_frame + c.x + c.y) % 3 != 0
	for i in lights.size():
		if (lights[i] as OmniLight3D).visible:
			(lights[i] as OmniLight3D).light_energy = float(light_base[i]) * (0.85 + 0.3 * _hash01(_frame, i, 31))
	var pulse: float = 0.8 + 0.3 * _hash01(_frame, 0, 33)
	for m in mats.values():
		(m as ShaderMaterial).set_shader_parameter("glow_pulse", pulse)

func _process(delta: float) -> void:
	super._process(delta)
	if fe == null or fx_root == null:
		return
	_t += delta
	if _t >= float(cfg["fx"].get("frame_sec", 0.14)):
		_t = 0.0
		_frame += 1
		_animate()

# --- 光線：煙越濃越暗越橘；夜裡 ---
func _update_mood() -> void:
	if env == null or sun == null:
		return
	var md: Dictionary = cfg["fx"]["mood"]
	var lv: int = fe.smoke_at(fe.wolf_pos)
	var k: float = lv / 3.0
	sun.light_color = (env_base["sun"] as Color).lerp(_col(md["smoke_sun"]), k)
	env.fog_light_color = (env_base["fog"] as Color).lerp(_col(md["smoke_fog"]), k)
	env.fog_density = float(md["smoke_fog_density"][lv])
	sun.light_energy = float(md["smoke_sun_energy"][lv])
	if fe.night:
		# 夜裡的霧是暗的（不然煙濃時整個畫面被霧染亮）
		env.fog_light_color = _col(md["night_background"]).lerp(_col(md["smoke_fog"]) * 0.45, k)
		env.ambient_light_color = _col(md["night_ambient"])
		env.ambient_light_energy = float(md["night_ambient_energy"])
		env.background_color = _col(md["night_background"])
		sun.light_energy = float(md["night_sun_energy"])
	else:
		env.ambient_light_color = env_base["ambient"]
		env.ambient_light_energy = env_base["ambient_e"]
		env.background_color = env_base["bg"]

# --- 風向 ---
func _update_wind() -> void:
	wind_label.text = view._wind_text() if view != null else ""
	wind_box.queue_redraw()

func _draw_wind() -> void:
	if fe == null:
		return
	var ctr := Vector2(17, 17)
	wind_box.draw_circle(ctr, 16, Color(0, 0, 0, 0.45))
	# 鏡頭朝北看：地圖的 x 是畫面的右、y（往南）是畫面的下
	var d: Vector2 = (fe.wind as Vector2).normalized()
	var ln: float = 6.0 + 4.0 * fe.strength
	var tip: Vector2 = ctr + d * ln
	var tail: Vector2 = ctr - d * ln
	var col := Color(0.92, 0.95, 1.0)
	wind_box.draw_line(tail, tip, col, 2.0)
	var perp := Vector2(-d.y, d.x)
	wind_box.draw_colored_polygon(PackedVector2Array([tip + d * 3, tip - d * 4 + perp * 4, tip - d * 4 - perp * 4]), col)
	# 風力：箭尾的短線（微風 0、中風 1、強風 2）
	for i in fe.strength:
		var b: Vector2 = tail + d * (3.0 + i * 3.0)
		wind_box.draw_line(b + perp * 3, b - perp * 3, col, 1.5)

# 其他動物（第 6 步）：看得到的才畫；逃跑時用跑的圖（鹿兩張輪流），渡鴉飛在空中
var _animal_last := {} # id -> [上一次的位置, 面向]
func _paint_animals() -> void:
	var arts: Dictionary = cfg["fx"].get("animal_art", {})
	for a in fe.fauna.visible_animals(fe):
		var k: String = str(a["kind"])
		var ac: Dictionary = arts.get(k, {})
		var id: int = int(a["id"])
		var pos: Vector2i = a["pos"]
		var last: Array = _animal_last.get(id, [pos, Vector2i(1, 0)])
		var face: Vector2i = last[1]
		if pos != last[0]:
			face = pos - (last[0] as Vector2i)
		_animal_last[id] = [pos, face]
		var pose: String = str(ac.get("stand", ""))
		if bool(a["fleeing"]):
			pose = str(ac.get("run_b", ac.get("run", pose))) if (fe.rounds + id) % 2 == 1 else str(ac.get("run", pose))
		if pose == "":
			continue
		var art := hd_wolf_texture(pose)
		art["ps"] = float(art["ps"]) * float(ac.get("scale", 1.0))
		var key := "an%d" % id
		unit(key, art, pos, (face.x < 0) if face.x != 0 else null)
		if bool(fe.fauna.kcfg(k).get("fly", false)) and bool(a["fleeing"]):
			var ent: Dictionary = units[key]
			(ent["sprite"] as Sprite3D).position.y += float(ac.get("lift", 1.4))
			(ent["shadow"] as MeshInstance3D).visible = false

# --- 每次重畫：能走的格子、巢穴、四邊、狼 ---
func paint() -> void:
	if fe == null:
		return
	var col: Dictionary = cfg["fire_colors"]
	if not fe.done and not fe.in_den:
		var reach: Dictionary = fe.reachable()
		for c in reach:
			quad(c, _col(col.get(str(reach[c]), col["trot"])), 0.86, 0.01)
	if fe.den_cell.x >= 0 and fe.known.has(fe.den_cell):
		frame(fe.den_cell, _col(col["den"]), 0.04, 0.06)
	# 四邊：連到的區域；在燒的那一邊畫紅線
	for s in ["n", "e", "s", "w"]:
		var burning_edge: bool = fe.edges_burning.has(s)
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		var mid := Vector3.ZERO
		match s:
			"n":
				a = Vector3(0, 0.15, 0.02)
				b = Vector3(map_w, 0.15, 0.02)
				mid = Vector3(map_w * 0.5, 0.6, -0.6)
			"s":
				a = Vector3(0, 0.15, map_h - 0.02)
				b = Vector3(map_w, 0.15, map_h - 0.02)
				mid = Vector3(map_w * 0.5, 0.4, map_h - 0.6)
			"w":
				a = Vector3(0.02, 0.15, 0)
				b = Vector3(0.02, 0.15, map_h)
				mid = Vector3(0.3, 0.6, map_h * 0.5)
			_:
				a = Vector3(map_w - 0.02, 0.15, 0)
				b = Vector3(map_w - 0.02, 0.15, map_h)
				mid = Vector3(map_w - 0.3, 0.6, map_h * 0.5)
		if burning_edge:
			line(a, b, _col(col["edge_burning"]))
		if view != null:
			var al: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT if s == "w" else (HORIZONTAL_ALIGNMENT_RIGHT if s == "e" else HORIZONTAL_ALIGNMENT_CENTER)
			_edge_label(mid, _edge_text(s), _col(col["edge_burning"] if burning_edge else col["edge_label"]), al)
	# 站在邊上可以離開：那一邊的格子外框
	if not fe.done and not fe.in_den and not fe.can_exit().is_empty():
		frame(fe.wolf_pos, _col(col["exit"]), 0.05, 0.06)
	# 狼：躲在洞裡時不畫，洞口寫一句
	if fe.wolf_pos != _last_wolf:
		if _last_wolf.x > -99:
			_face = fe.wolf_pos - _last_wolf
			_moved_round = fe.rounds
		_last_wolf = fe.wolf_pos
	_paint_animals()
	if fe.in_den:
		label(cell_center(fe.den_cell) + Vector3(0, 1.0, 0), tr("fire.ui.in_den"), _col(col["den"]))
	elif not (fe.done and fe.result == "escaped"):
		var wp: Dictionary = cfg.get("wolf_poses", {})
		var pose: String = str(wp.get("stand", "hdwolf_stand"))
		if fe.done and fe.result == "dead":
			pose = "hdwolf_down"
		elif float(fe.wolf["health"]) < float(fe.wolf.get("health_max", 100)) * 0.4:
			pose = "hdwolf_hurt"
		elif _moved_round == fe.rounds:
			pose = str(wp.get("walk_b" if fe.rounds % 2 == 1 else "walk", "hdwolf_walk"))
		unit("wolf", hd_wolf_texture(pose), fe.wolf_pos, (_face.x < 0) if _face.x != 0 else null)
	if view != null:
		var hv: Vector2i = view.hover
		if hv.x >= 0 and in_map(hv):
			quad(hv, _col(col["hover"]), 0.94, 0.04)
