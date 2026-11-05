class_name CombatHD2D
extends Control
# 戰鬥原型的 HD-2D 畫面（2026-11-05，使用者：HD-2D 測試滿意，先套到戰鬥原型）。
# 只換畫面：讀 TacticalCombatView 的 tc（TacticalCombat）與畫面狀態（計畫要走的格子、滑鼠所在、被打中的格子），
# 3D 地形＋像素角色畫在 SubViewport，再放到這個 Control 的範圍。點格子、滑鼠移動用訊號交回原本的畫面處理。
# 地形的高低只是畫面（大石頭、峭壁畫成高台），規則照 data/tactical_combat.json。

signal cell_hovered(c: Vector2i)
signal cell_clicked(c: Vector2i)

const HD_DIR := "res://prototypes/hd2d_tactical/"
const CFG_PATH := "res://prototypes/tactical_combat/combat_hd2d.json"

var view # TacticalCombatView（讀 tc、planned、hover、hit_cells）
var cfg: Dictionary = {}
var tc: TacticalCombat
var sub: SubViewport
var screen: TextureRect
var post: ShaderMaterial
var cam: Camera3D
var world: Node3D # 每局重建
var overlay: Node3D # 每次 refresh 重建
var unit_sprites := {} # 單位索引 -> {sprite, shadow, label}
var tree_sprites: Array = [] # [{sprite, kind}]
var mats := {}
var art_px := 32
var _blob: ImageTexture
var _last_hover := Vector2i(-1, -1)

func _init() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CFG_PATH))
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

# --- 一局開始：地形、樹、單位 ---
func setup(combat: TacticalCombat) -> void:
	tc = combat
	if world != null:
		world.queue_free()
	unit_sprites.clear()
	tree_sprites.clear()
	world = Node3D.new()
	sub.add_child(world)
	_build_env()
	_build_terrain()
	_on_resized()
	refresh()

func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.1)
	var amb: Dictionary = cfg["ambient"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _col(amb["color"])
	e.ambient_light_energy = float(amb["energy"])
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.25
	env.environment = e
	world.add_child(env)
	var lc: Dictionary = cfg["light"]
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(float(lc["pitch"]), float(lc["yaw"]), 0)
	sun.light_energy = float(lc["energy"])
	sun.light_color = _col(lc["color"])
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = Vector3(float(cfg["camera_pitch"]), 0, 0)
	cam.near = 0.1
	cam.far = 200.0
	world.add_child(cam)

func level_of(c: Vector2i) -> int:
	return int(cfg["heights"].get(tc.map.terrain(c), 0))

func top_y(c: Vector2i) -> float:
	return float(level_of(c)) * float(cfg["level_height"])

func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, top_y(c), c.y + 0.5)

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
	for y in tc.map.height:
		for x in tc.map.width:
			var c := Vector2i(x, y)
			var k: String = tc.map.terrain(c)
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			var top := top_y(c)
			box.size = Vector3(1, top - bottom, 1)
			mi.mesh = box
			mi.position = Vector3(x + 0.5, (top + bottom) * 0.5, y + 0.5)
			mi.material_override = _terrain_mat(k)
			world.add_child(mi)
			if cfg["trees"].has(k):
				var s := _make_sprite(false)
				tree_sprites.append({"sprite": s, "kind": k})
				s.position = cell_center(c) + Vector3(0, 0, 0.1)
			if k == "l":
				# 倒木：橫躺的圓木
				var log := MeshInstance3D.new()
				var cy := CylinderMesh.new()
				cy.top_radius = 0.16
				cy.bottom_radius = 0.18
				cy.height = 0.9
				log.mesh = cy
				log.rotation_degrees = Vector3(0, 30 if (x + y) % 2 == 0 else -30, 90)
				log.position = cell_center(c) + Vector3(0, 0.17, 0)
				var lm := StandardMaterial3D.new()
				lm.albedo_color = Color(0.36, 0.26, 0.18)
				log.material_override = lm
				world.add_child(log)
			if k == "s":
				var w := MeshInstance3D.new()
				var pl := PlaneMesh.new()
				pl.size = Vector2(1, 1)
				w.mesh = pl
				w.position = cell_center(c) + Vector3(0, 0.12, 0)
				var wm := StandardMaterial3D.new()
				wm.albedo_color = Color(0.32, 0.52, 0.62, 0.62)
				wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				w.material_override = wm
				world.add_child(w)
	overlay = Node3D.new()
	world.add_child(overlay)

func _make_sprite(blob := true) -> Sprite3D:
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

# 狼與樹的素材：螢幕上一格夠大就用 48 那套（HD-2D 測試的「兩套自動切換」）
func _load_art() -> void:
	for t in tree_sprites:
		var s: Sprite3D = t["sprite"]
		var tc_cfg: Dictionary = cfg["trees"][t["kind"]]
		s.texture = load(HD_DIR + "assets/%s_%d.png" % [str(tc_cfg["art"]), art_px])
		s.pixel_size = float(tc_cfg["scale"]) / float(art_px)
		s.offset = Vector2(0, s.texture.get_height() * 0.5 - 2)

func _unit_texture(i: int) -> Dictionary:
	var u: Dictionary = tc.units[i]
	var key: String = str(u["id"]) if str(u["species"]) == "wolf" else str(u["species"])
	var uc: Dictionary = cfg["units"].get(key, cfg["units"]["wolf"])
	if str(uc.get("art", "")) == "hd2d_wolf":
		var name := "wolf_stand"
		if str(u.get("last_mode", "")) == "creep":
			name = "wolf_stalk"
		return {"tex": load(HD_DIR + "assets/%s_%d.png" % [name, art_px]), "ps": 1.0 / float(art_px), "mod": _col(uc["modulate"])}
	var at := AtlasTexture.new()
	at.atlas = load(str(uc["sheet"]))
	var fr: Array = uc["frame"]
	at.region = Rect2(0, 0, float(fr[0]), float(fr[1]))
	return {"tex": at, "ps": 1.0 / float(uc["px_per_cell"]), "mod": Color.WHITE}

# --- 每次畫面更新：單位的位置、面向，地面上的範圍與標記 ---
func refresh() -> void:
	if tc == null or world == null:
		return
	for i in tc.units.size():
		_update_unit(i)
	for ch in overlay.get_children():
		ch.queue_free()
	var col: Dictionary = cfg["colors"]
	if not tc.done:
		var reach: Dictionary = tc.reachable(0)
		for c in reach.keys():
			_quad(c, _col(col.get(str(reach[c]), col["trot"])), 0.86, 0.01)
	for e in tc.intents.keys():
		var seen: Dictionary = tc.intents[e].get("seen", {})
		var clear: bool = int(seen.get("level", 0)) >= 2
		for c in seen.get("zone", []):
			_quad(c, _col(col["zone_clear" if clear else "zone_partial"]), 0.98, 0.02)
	if view != null:
		var planned: Vector2i = view.planned
		if planned.x >= 0:
			_quad(planned, _col(col["planned"]), 0.7, 0.03)
			_line(cell_center(tc.units[0]["pos"]) + Vector3(0, 0.05, 0), cell_center(planned) + Vector3(0, 0.05, 0), _col(col["path"]))
		var hv: Vector2i = view.hover
		if hv.x >= 0 and tc.map.in_bounds(hv):
			_quad(hv, _col(col["hover"]), 0.94, 0.035)
		for c in view.hit_cells:
			_quad(c, _col(col["hit"]), 0.5, 0.04)
	# 殘骸、放下的肉
	if not tc.carcass.is_empty() and int(tc.carcass["segments"]) > 0:
		var cc: Dictionary = cfg["carcass"]
		var s := Sprite3D.new()
		s.texture = load(str(cc.get(str(tc.carcass.get("animal", "")), cc["_default"])))
		s.pixel_size = 1.0 / float(cc["px_per_cell"])
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.position = cell_center(tc.carcass["pos"]) + Vector3(0, s.texture.get_height() * 0.5 * s.pixel_size, 0)
		overlay.add_child(s)
		_label(cell_center(tc.carcass["pos"]) + Vector3(0.3, 0.7, 0), str(tc.carcass["segments"]), Color(1, 0.85, 0.75))
	for d in tc.drops:
		_quad(d["pos"], Color(0.45, 0.18, 0.12, 0.9), 0.35, 0.05)
	# 對手盯著誰
	for i in tc.units.size():
		if tc.active(i) and not tc.player_side(i):
			var a: int = int(tc.units[i].get("attention", -1))
			if a >= 0 and tc.active(a):
				_line(cell_center(tc.units[i]["pos"]) + Vector3(0, 0.6, 0), cell_center(tc.units[a]["pos"]) + Vector3(0, 0.4, 0), _col(col["attention"]))

func _update_unit(i: int) -> void:
	var u: Dictionary = tc.units[i]
	if not unit_sprites.has(i):
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
		unit_sprites[i] = {"sprite": s, "shadow": sh, "label": lb}
	var ent: Dictionary = unit_sprites[i]
	var s2: Sprite3D = ent["sprite"]
	var on: bool = tc.active(i)
	s2.visible = on
	(ent["shadow"] as MeshInstance3D).visible = on
	(ent["label"] as Label3D).visible = on
	if not on:
		return
	var t := _unit_texture(i)
	s2.texture = t["tex"]
	s2.pixel_size = t["ps"]
	s2.modulate = t["mod"]
	s2.offset = Vector2(0, s2.texture.get_height() * 0.5 - 1)
	# 素材都面向右：面向左邊的翻過來（正上、正下維持上一次的方向）
	var f: Vector2i = u["facing"]
	if f.x != 0:
		s2.flip_h = f.x < 0
	var p := cell_center(u["pos"])
	s2.position = p + Vector3(0, 0, 0.05)
	(ent["shadow"] as MeshInstance3D).position = p + Vector3(0, 0.02, 0)
	# 狀態：在吃、叼著肉
	var tags: Array = []
	if bool(u.get("eating", false)):
		tags.append(tr("tcombat.hd.eating"))
	if str(u["carrying"]) != "":
		tags.append(tr("tcombat.hd.carrying"))
	var lb2: Label3D = ent["label"]
	lb2.text = " ".join(tags)
	lb2.modulate = Color(1, 0.75, 0.45)
	lb2.position = p + Vector3(0, s2.texture.get_height() * s2.pixel_size + 0.25, 0)

func _quad(c: Vector2i, color: Color, size: float, lift: float) -> void:
	var mi := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(size, size)
	mi.mesh = pl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = cell_center(c) + Vector3(0, lift, 0)
	overlay.add_child(mi)

func _line(a: Vector3, b: Vector3, color: Color) -> void:
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

func _label(p: Vector3, text: String, color: Color) -> void:
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

# --- 鏡頭：整張地圖放進這個範圍；SubViewport 用螢幕的實際像素畫 ---
func _screen_scale() -> float:
	var vr: Vector2 = get_viewport_rect().size
	var ws: Vector2 = Vector2(DisplayServer.window_get_size()) if DisplayServer.get_name() != "headless" else vr
	return max(1.0, min(ws.x / vr.x, ws.y / vr.y))

func _on_resized() -> void:
	if tc == null or cam == null:
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
	var need_h: float = tc.map.height * sin(pitch) + max_lv * float(cfg["level_height"]) * cos(pitch) + m
	var aspect := float(px.x) / float(px.y)
	cam.size = max(need_h, (tc.map.width + m) / aspect)
	var center := Vector3(tc.map.width * 0.5, 0.3, tc.map.height * 0.5)
	var fwd := -cam.global_transform.basis.z if cam.is_inside_tree() else -Basis.from_euler(cam.rotation).z
	cam.position = center - fwd * 30.0
	# 螢幕上一格幾像素 → 狼與樹用哪一套
	var tile_px: float = float(px.y) / cam.size
	var want: int = 48 if tile_px >= float(cfg["swap_px"]) else 32
	if want != art_px or tree_sprites.size() > 0 and (tree_sprites[0]["sprite"] as Sprite3D).texture == null:
		art_px = want
		_load_art()
		refresh()

# --- 輸入：滑鼠所在的格子 ---
func _pick_cell(p: Vector2) -> Vector2i:
	if cam == null or tc == null:
		return Vector2i(-1, -1)
	var cp := p / size * Vector2(sub.size)
	var o := cam.project_ray_origin(cp)
	var n := cam.project_ray_normal(cp)
	var t := 0.0
	while t < 120.0:
		var q := o + n * t
		var c := Vector2i(int(floor(q.x)), int(floor(q.z)))
		if tc.map.in_bounds(c) and q.y <= top_y(c) + 0.001:
			return c
		t += 0.02
	return Vector2i(-1, -1)

func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := _pick_cell(ev.position)
		if c != _last_hover:
			_last_hover = c
			cell_hovered.emit(c)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var c2 := _pick_cell(ev.position)
		if c2.x >= 0:
			cell_clicked.emit(c2)
