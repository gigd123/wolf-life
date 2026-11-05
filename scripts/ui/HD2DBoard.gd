class_name HD2DBoard
extends Control
# HD-2D 戰術地圖的共用畫面（2026-11-05；戰鬥原型 CombatHD2D、戰術狩獵 HuntHD2D 共用）。
# 只負責畫：3D 地形方塊（高度、材質依地形字元）＋樹＋像素角色（Sprite3D）＋地面上的標示，
# 畫在 SubViewport，再放到這個 Control 的範圍（用螢幕的實際像素畫）。整張地圖固定放進畫面。
# 子類別覆寫 paint()：每次畫面更新時呼叫 unit()、quad()、line()、label() 畫這一刻的狀態。
# 點格子、滑鼠移動用訊號交回原本的畫面處理；邏輯完全不在這裡。
# 滾輪縮放（cfg.zoom：max 最多放大幾倍、step 每格倍率）、右鍵或中鍵拖曳捲動。
# cfg（JSON）：level_height、camera_pitch、margin、swap_px、heights／top／side／tint／trees（依地形字元）、ambient、light、tilt_shift、background。

signal cell_hovered(c: Vector2i)
signal cell_clicked(c: Vector2i)

const HD_DIR := "res://prototypes/hd2d_tactical/"

var cfg: Dictionary = {}
var map_w := 0
var map_h := 0
var terrain_of: Callable # (Vector2i) -> String
var sub: SubViewport
var screen: TextureRect
var post: ShaderMaterial
var cam: Camera3D
var world: Node3D
var overlay: Node3D
var tree_sprites: Array = [] # [{sprite, kind}]
var units := {} # 鍵 -> {sprite, shadow, label, used}
var mats := {}
var art_px := 32
var _blob: ImageTexture
var _last_hover := Vector2i(-1, -1)
# 縮放與捲動（滾輪縮放、右鍵或中鍵拖曳捲動；1 = 整張地圖放進畫面）
var zoom := 1.0
var focus := Vector2.ZERO # 鏡頭看的地面位置（x, z）
var _fit_size := 1.0
var _dragging := false

func _init_board(cfg_path: String) -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(cfg_path))
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	sub = SubViewport.new()
	sub.own_world_3d = true
	sub.msaa_3d = Viewport.MSAA_DISABLED
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	screen = TextureRect.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.texture = sub.get_texture()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = ShaderMaterial.new()
	post.shader = load(HD_DIR + "tilt_shift.gdshader")
	var ts: Dictionary = cfg["tilt_shift"]
	post.set_shader_parameter("focus", float(ts["focus"]))
	post.set_shader_parameter("band", float(ts["band"]))
	post.set_shader_parameter("max_blur", float(ts["max_blur"]))
	screen.material = post
	add_child(screen)
	gui_input.connect(_on_input)
	mouse_exited.connect(func(): _last_hover = Vector2i(-1, -1); cell_hovered.emit(Vector2i(-1, -1)))
	resized.connect(_on_resized)

# --- 建地圖（每局一次） ---
func build(w: int, h: int, terrain_fn: Callable) -> void:
	map_w = w
	map_h = h
	terrain_of = terrain_fn
	if world != null:
		world.queue_free()
	units.clear()
	tree_sprites.clear()
	world = Node3D.new()
	sub.add_child(world)
	_build_env()
	_build_terrain()
	art_px = 0
	zoom = 1.0
	focus = Vector2(map_w * 0.5, map_h * 0.5)
	_on_resized()

func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = _col(cfg.get("background", [0.1, 0.11, 0.1]))
	var amb: Dictionary = cfg["ambient"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _col(amb["color"])
	e.ambient_light_energy = float(amb["energy"])
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var lc: Dictionary = cfg["light"]
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(float(lc["pitch"]), float(lc["yaw"]), 0)
	sun.light_energy = float(lc["energy"])
	sun.light_color = _col(lc["color"])
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	world.add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = Vector3(float(cfg["camera_pitch"]), 0, 0)
	cam.near = 0.1
	cam.far = 200.0
	world.add_child(cam)

func level_of(c: Vector2i) -> int:
	return int(cfg["heights"].get(str(terrain_of.call(c)), 0))

func top_y(c: Vector2i) -> float:
	return float(level_of(c)) * float(cfg["level_height"])

func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, top_y(c), c.y + 0.5)

func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_w and c.y < map_h

func _terrain_mat(k: String) -> ShaderMaterial:
	if mats.has(k):
		return mats[k]
	var m := ShaderMaterial.new()
	m.shader = load(HD_DIR + "terrain.gdshader")
	var tt: Texture2D = load(HD_DIR + "assets/tex_%s.png" % str(cfg["top"].get(k, "grass")))
	var st: Texture2D = load(HD_DIR + "assets/tex_%s.png" % str(cfg["side"].get(k, "dirt")))
	m.set_shader_parameter("top_tex", tt)
	m.set_shader_parameter("side_tex", st)
	m.set_shader_parameter("top_tex_s", tt)
	m.set_shader_parameter("side_tex_s", st)
	m.set_shader_parameter("top_size", float(tt.get_width()))
	m.set_shader_parameter("side_size", float(st.get_width()))
	m.set_shader_parameter("show_grid", true)
	var tint: Array = cfg["tint"].get(k, [1.0, 1.0, 1.0])
	m.set_shader_parameter("tint", Vector3(float(tint[0]), float(tint[1]), float(tint[2])))
	mats[k] = m
	return m

func _build_terrain() -> void:
	mats.clear()
	var lh: float = float(cfg["level_height"])
	var bottom := -2.0 * lh
	var water: Dictionary = cfg.get("water", {})
	for y in map_h:
		for x in map_w:
			var c := Vector2i(x, y)
			var k: String = str(terrain_of.call(c))
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			var top := top_y(c)
			box.size = Vector3(1, top - bottom, 1)
			mi.mesh = box
			mi.position = Vector3(x + 0.5, (top + bottom) * 0.5, y + 0.5)
			mi.material_override = _terrain_mat(k)
			world.add_child(mi)
			if cfg["trees"].has(k):
				# 同一種地形的樹稍微錯開，看起來不像排隊
				var s := _make_sprite(false)
				var j := Vector3(((x * 37 + y * 11) % 7 - 3) * 0.04, 0, ((x * 13 + y * 29) % 7 - 3) * 0.03)
				tree_sprites.append({"sprite": s, "kind": k})
				s.position = cell_center(c) + Vector3(0, 0, 0.1) + j
			if k in cfg.get("logs", []):
				var lg := MeshInstance3D.new()
				var cy := CylinderMesh.new()
				cy.top_radius = 0.16
				cy.bottom_radius = 0.18
				cy.height = 0.9
				lg.mesh = cy
				lg.rotation_degrees = Vector3(0, 30 if (x + y) % 2 == 0 else -30, 90)
				lg.position = cell_center(c) + Vector3(0, 0.17, 0)
				var lm := StandardMaterial3D.new()
				lm.albedo_color = Color(0.36, 0.26, 0.18)
				lg.material_override = lm
				world.add_child(lg)
			if water.has(k):
				var wm_i := MeshInstance3D.new()
				var pl := PlaneMesh.new()
				pl.size = Vector2(1, 1)
				wm_i.mesh = pl
				wm_i.position = cell_center(c) + Vector3(0, float(water[k].get("lift", 0.12)), 0)
				var wm := StandardMaterial3D.new()
				wm.albedo_color = _col(water[k]["color"])
				wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				wm.roughness = 0.2
				wm_i.material_override = wm
				wm_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				world.add_child(wm_i)
	overlay = Node3D.new()
	world.add_child(overlay)

func _make_sprite(blob: bool) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if blob else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	world.add_child(s)
	return s

func _blob_texture() -> ImageTexture:
	if _blob != null:
		return _blob
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 32:
			var d := Vector2((x - 15.5) / 16.0, (y - 7.5) / 8.0).length()
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if d < 0.8 else (0.5 if d < 1.0 else 0.0)))
	_blob = ImageTexture.create_from_image(img)
	return _blob

# 樹：螢幕上一格夠大就用 48 那套（HD-2D 測試的「兩套自動切換」）
func _load_trees() -> void:
	for t in tree_sprites:
		var s: Sprite3D = t["sprite"]
		var tcfg: Dictionary = cfg["trees"][t["kind"]]
		s.texture = load(HD_DIR + "assets/%s_%d.png" % [str(tcfg["art"]), art_px])
		s.pixel_size = float(tcfg["scale"]) / float(art_px)
		s.offset = Vector2(0, s.texture.get_height() * 0.5 - 2)

# HD-2D 測試的狼（目前這一套的像素）
func hd_wolf_texture(pose: String = "wolf_stand") -> Dictionary:
	var px: int = art_px if art_px > 0 else 32
	return {"tex": load(HD_DIR + "assets/%s_%d.png" % [pose, px]), "ps": 1.0 / float(px)}

# 遊戲的動物圖（data/art.json 的 animals）：single 一張圖、sheet 取第一格（沒寫 frame 用 frame_size）、strips.walk 取第一格；winter 時有 @winter 的用冬季的圖。
# 寬度縮放到 width_cells 格。找不到時回傳空的字典。
static func animal_texture(species: String, stage: String, width_cells: float, winter: bool = false) -> Dictionary:
	var a: Dictionary = GameData.art.get("animals", {}).get(species, {})
	var st: Dictionary = a.get(stage, a.get("adult", {}))
	# 冬季換毛的動物（雪兔）有 @winter 的圖
	if winter and a.has(stage + "@winter"):
		st = a[stage + "@winter"]
	var tex: Texture2D = null
	if st.has("single"):
		tex = ArtLibrary.texture(str(st["single"]))
	elif st.has("sheet"):
		# 沒寫 frame 的是預設的格子大小（art.json 的 frame_size）
		var fr: Array = st.get("frame", GameData.art.get("frame_size", [48, 32]))
		var at := AtlasTexture.new()
		at.atlas = ArtLibrary.texture(str(st["sheet"]))
		at.region = Rect2(0, 0, float(fr[0]), float(fr[1]))
		tex = at
	elif st.has("strips") and st["strips"].has("walk"):
		var wk: Dictionary = st["strips"]["walk"]
		var at2 := AtlasTexture.new()
		at2.atlas = ArtLibrary.texture(str(wk["sheet"]))
		at2.region = Rect2(0, 0, float(wk["frame"][0]), float(wk["frame"][1]))
		tex = at2
	if tex == null:
		return {}
	return {"tex": tex, "ps": width_cells / float(maxi(1, tex.get_width()))}

# --- 每次畫面更新 ---
func refresh() -> void:
	if world == null:
		return
	for k in units.keys():
		units[k]["used"] = false
	for ch in overlay.get_children():
		ch.queue_free()
	paint()
	for k in units.keys():
		if not bool(units[k]["used"]):
			(units[k]["sprite"] as Sprite3D).visible = false
			(units[k]["shadow"] as MeshInstance3D).visible = false
			(units[k]["label"] as Label3D).visible = false

func paint() -> void:
	pass

# 角色：key 固定的話同一個 Sprite3D 重複用。art：{tex, ps}；flip 為 null 時維持上一次的方向（素材都面向右）
func unit(key: String, art: Dictionary, c: Vector2i, flip, modulate: Color = Color.WHITE, tag: String = "", tag_color: Color = Color(1, 0.75, 0.45)) -> void:
	if art.is_empty():
		return
	if not units.has(key):
		var s := _make_sprite(true)
		var sh := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(1.0, 0.5)
		sh.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _blob_texture()
		m.albedo_color = Color(0, 0, 0, 0.45)
		sh.material_override = m
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(sh)
		var lb := Label3D.new()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.pixel_size = 0.012
		lb.font_size = 32
		lb.outline_size = 8
		lb.no_depth_test = true
		world.add_child(lb)
		units[key] = {"sprite": s, "shadow": sh, "label": lb}
	var ent: Dictionary = units[key]
	ent["used"] = true
	var s2: Sprite3D = ent["sprite"]
	s2.visible = true
	s2.texture = art["tex"]
	s2.pixel_size = float(art["ps"])
	s2.modulate = modulate
	s2.offset = Vector2(0, s2.texture.get_height() * 0.5 - 1)
	if flip != null:
		s2.flip_h = bool(flip)
	var p := cell_center(c)
	s2.position = p + Vector3(0, 0, 0.05)
	var sh2: MeshInstance3D = ent["shadow"]
	sh2.visible = true
	sh2.position = p + Vector3(0, 0.02, 0)
	var w: float = s2.texture.get_width() * s2.pixel_size
	sh2.scale = Vector3(clampf(w, 0.4, 2.2), 1, clampf(w, 0.4, 2.2))
	var lb2: Label3D = ent["label"]
	lb2.visible = tag != ""
	lb2.text = tag
	lb2.modulate = tag_color
	lb2.position = p + Vector3(0, s2.texture.get_height() * s2.pixel_size + 0.25, 0)

func quad(c: Vector2i, color: Color, size: float, lift: float) -> void:
	var mi := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(size, size)
	mi.mesh = pl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = cell_center(c) + Vector3(0, lift, 0)
	overlay.add_child(mi)

# 格子的外框（四條細長的方塊）
func frame(c: Vector2i, color: Color, lift: float, thick: float = 0.08) -> void:
	var p := cell_center(c) + Vector3(0, lift, 0)
	for side in [[Vector3(0, 0, -0.45), Vector2(0.98, thick)], [Vector3(0, 0, 0.45), Vector2(0.98, thick)], [Vector3(-0.45, 0, 0), Vector2(thick, 0.98)], [Vector3(0.45, 0, 0), Vector2(thick, 0.98)]]:
		var mi := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = side[1]
		mi.mesh = pl
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = color
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = p + side[0]
		overlay.add_child(mi)

func line(a: Vector3, b: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.no_depth_test = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.add_child(mi)

func label(p: Vector3, text: String, color: Color) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = 0.012
	lb.font_size = 32
	lb.outline_size = 8
	lb.modulate = color
	lb.no_depth_test = true
	lb.position = p
	overlay.add_child(lb)

func sprite_at(tex: Texture2D, ps: float, c: Vector2i) -> void:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = ps
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.position = cell_center(c) + Vector3(0, tex.get_height() * 0.5 * ps, 0)
	overlay.add_child(s)

# --- 鏡頭：整張地圖放進這個範圍 ---
func _screen_scale() -> float:
	var vr: Vector2 = get_viewport_rect().size
	var ws: Vector2 = Vector2(DisplayServer.window_get_size()) if DisplayServer.get_name() != "headless" else vr
	return max(1.0, min(ws.x / vr.x, ws.y / vr.y))

func _on_resized() -> void:
	if cam == null or map_w == 0:
		return
	var px := Vector2i(maxi(1, int(size.x * _screen_scale())), maxi(1, int(size.y * _screen_scale())))
	if sub.size != px:
		sub.size = px
	post.set_shader_parameter("canvas_size", Vector2(px))
	var pitch := deg_to_rad(-float(cfg["camera_pitch"]))
	var max_lv := 0
	for v in cfg["heights"].values():
		max_lv = maxi(max_lv, int(v))
	var m: float = float(cfg["margin"])
	var need_h: float = map_h * sin(pitch) + max_lv * float(cfg["level_height"]) * cos(pitch) + m
	var aspect := float(px.x) / float(px.y)
	_fit_size = max(need_h, (map_w + m) / aspect)
	_apply_camera()

func _apply_camera() -> void:
	cam.size = _fit_size / zoom
	# 拉近時不讓鏡頭跑出地圖：看得到的範圍的一半
	var aspect := float(sub.size.x) / float(maxi(1, sub.size.y))
	var pitch := deg_to_rad(-float(cfg["camera_pitch"]))
	var half_w: float = cam.size * aspect * 0.5
	var half_d: float = cam.size * 0.5 / sin(pitch)
	focus.x = clampf(focus.x, min(half_w, map_w * 0.5), max(map_w - half_w, map_w * 0.5))
	focus.y = clampf(focus.y, min(half_d, map_h * 0.5), max(map_h - half_d, map_h * 0.5))
	var fwd := -Basis.from_euler(cam.rotation).z
	cam.position = Vector3(focus.x, 0.3, focus.y) - fwd * 30.0
	var tile_px: float = float(sub.size.y) / cam.size
	var want: int = 48 if tile_px >= float(cfg["swap_px"]) else 32
	if want != art_px:
		art_px = want
		_load_trees()
		refresh()

# 畫面上的一點對到地面（高度 0）的位置 (x, z)
func _ground_at(p: Vector2) -> Vector2:
	var cp := p / size * Vector2(sub.size)
	var o := cam.project_ray_origin(cp)
	var n := cam.project_ray_normal(cp)
	if absf(n.y) < 0.0001:
		return Vector2(o.x, o.z)
	var t := -o.y / n.y
	return Vector2(o.x + n.x * t, o.z + n.z * t)

# --- 輸入：滑鼠所在的格子 ---
func _pick_cell(p: Vector2) -> Vector2i:
	if cam == null or map_w == 0:
		return Vector2i(-1, -1)
	var cp := p / size * Vector2(sub.size)
	var o := cam.project_ray_origin(cp)
	var n := cam.project_ray_normal(cp)
	var t := 0.0
	while t < 160.0:
		var q := o + n * t
		var c := Vector2i(int(floor(q.x)), int(floor(q.z)))
		if in_map(c) and q.y <= top_y(c) + 0.001:
			return c
		t += 0.02
	return Vector2i(-1, -1)

func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var zc: Dictionary = cfg.get("zoom", {"max": 3.0, "step": 1.15})
		var before := _ground_at(ev.position)
		zoom = clampf(zoom * (float(zc["step"]) if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / float(zc["step"])), 1.0, float(zc["max"]))
		_apply_camera()
		# 以滑鼠所在的位置為中心縮放
		var after := _ground_at(ev.position)
		focus += before - after
		_apply_camera()
		accept_event()
		return
	if ev is InputEventMouseButton and ev.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_dragging = ev.pressed
		accept_event()
		return
	if ev is InputEventMouseMotion and _dragging:
		var a := _ground_at(ev.position - ev.relative)
		var b := _ground_at(ev.position)
		focus += a - b
		_apply_camera()
		return
	if ev is InputEventMouseMotion:
		var c := _pick_cell(ev.position)
		if c != _last_hover:
			_last_hover = c
			cell_hovered.emit(c)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var c2 := _pick_cell(ev.position)
		if c2.x >= 0:
			cell_clicked.emit(c2)
