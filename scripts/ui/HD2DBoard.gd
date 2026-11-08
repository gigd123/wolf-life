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

# 鏡頭移到某一格、放大到 z 倍（開場拉近到狼附近用）
func focus_on(c: Vector2i, z: float) -> void:
	zoom = clampf(z, 1.0, float(cfg.get("zoom", {}).get("max", 3.0)))
	focus = Vector2(c.x + 0.5, c.y + 0.5)
	if cam != null and sub.size.x > 1:
		_apply_camera()

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
	# 霧、光暈、飽和度（照 HD-2D 測試場景的氣氛；cfg.fog 沒寫就不開）
	var fog: Dictionary = cfg.get("fog", {})
	if not fog.is_empty():
		e.fog_enabled = true
		e.fog_light_color = _col(fog["color"])
		e.fog_density = float(fog["density"])
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_bloom = 0.03
	e.adjustment_enabled = true
	e.adjustment_saturation = float(cfg.get("saturation", 0.92))
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
	# height_var：同一種地形有些格子畫得矮一點（岩坡有高有低，看起來不像一排積木）；只是畫面
	var hv: Dictionary = cfg.get("height_var", {}).get(str(terrain_of.call(c)), {})
	if not hv.is_empty() and _hash01(c.x, c.y, 17) < float(hv.get("chance", 0.0)):
		return float(hv["level"]) * float(cfg["level_height"])
	return float(level_of(c)) * float(cfg["level_height"])

func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, top_y(c), c.y + 0.5)

func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_w and c.y < map_h

# top_override：這一格上面換成別的材質（地面的斑塊，例如草地裡的泥地）
# top_override 以「tint:」開頭時不換材質，只換顏色倍率（例如草地裡偏黃的乾草斑塊）
func _terrain_mat(k: String, top_override: String = "") -> ShaderMaterial:
	var key := k + "|" + top_override
	var tint_override: Array = []
	if top_override.begins_with("tint:"):
		tint_override = Array(top_override.substr(5).split(",")).map(func(v): return float(v))
		top_override = ""
	if mats.has(key):
		return mats[key]
	var m := ShaderMaterial.new()
	m.shader = load(HD_DIR + "terrain.gdshader")
	var top_name: String = top_override if top_override != "" else str(cfg["top"].get(k, "grass"))
	var tt: Texture2D = load(HD_DIR + "assets/tex_%s.png" % top_name)
	var st: Texture2D = load(HD_DIR + "assets/tex_%s.png" % str(cfg["side"].get(k, "dirt")))
	m.set_shader_parameter("top_tex", tt)
	m.set_shader_parameter("side_tex", st)
	m.set_shader_parameter("top_tex_s", tt)
	m.set_shader_parameter("side_tex_s", st)
	m.set_shader_parameter("top_size", float(tt.get_width()))
	m.set_shader_parameter("side_size", float(st.get_width()))
	m.set_shader_parameter("show_grid", true)
	var tint: Array = tint_override if not tint_override.is_empty() else (cfg["tint"].get(k, [1.0, 1.0, 1.0]) if top_override == "" else [1.0, 1.0, 1.0])
	m.set_shader_parameter("tint", Vector3(float(tint[0]), float(tint[1]), float(tint[2])))
	# lip_tops：上面是這些材質時側面畫草皮邊緣（材質 → 往下垂幾個材質像素）
	var lips: Dictionary = cfg.get("lip_tops", {})
	if lips.has(top_name):
		m.set_shader_parameter("lip_texels", float(lips[top_name]))
	mats[key] = m
	return m

# 平滑的值雜訊（0～1）：地面斑塊、樹的種類用，固定不隨重畫改變
func _noise(x: float, y: float, sc: float, salt: int = 0) -> float:
	var fx := x / sc
	var fy := y / sc
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _hash01(ix, iy, salt)
	var b := _hash01(ix + 1, iy, salt)
	var c := _hash01(ix, iy + 1, salt)
	var d := _hash01(ix + 1, iy + 1, salt)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

func _hash01(x: int, y: int, salt: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791) ^ (map_w * 2654435)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 10007) / 10007.0

# 這一格上面的斑塊（cfg.ground_mix：地形字元 → {patch 材質, ratio 佔多少, scale 斑塊大小}）
func _patch_for(k: String, x: int, y: int) -> String:
	var gm: Dictionary = cfg.get("ground_mix", {}).get(k, {})
	if gm.is_empty():
		return ""
	return str(gm["patch"]) if _noise(x, y, float(gm.get("scale", 4.0)), 7) < float(gm.get("ratio", 0.25)) else ""

# 每張地圖自己的設定（cfg.map_sets：主遊戲的地圖 → 要蓋過的設定）：字典的一層一層合併（top、trees、fixed_scale…），其他（tree_mix、near_props…）整個換掉
func apply_map_set(map_id: String) -> void:
	var ms: Dictionary = cfg.get("map_sets", {}).get(map_id, {})
	for k in ms.keys():
		if str(k).begins_with("_"):
			continue
		if cfg.get(k) is Dictionary and ms[k] is Dictionary:
			(cfg[k] as Dictionary).merge((ms[k] as Dictionary).duplicate(true), true)
		else:
			cfg[k] = ms[k].duplicate(true) if (ms[k] is Dictionary or ms[k] is Array) else ms[k]

func _tree_art(x: int, y: int, base: String) -> String:
	var mix: Array = cfg.get("tree_mix", [])
	if mix.is_empty():
		return base
	return str(mix[int(_noise(x, y, 3.0, 11) * mix.size()) % mix.size()])

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
			mi.material_override = _terrain_mat(k, _patch_for(k, x, y))
			world.add_child(mi)
			# near_props：某種地形旁邊的格子放物件（岩坡旁的平地有幾顆滾下來的大石頭）；只是畫面、不擋路
			for np in cfg.get("near_props", []):
				if k != str(np["on"]) or _hash01(x, y, 19) >= float(np.get("chance", 0.2)):
					continue
				var near := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nears: Array = np["near"] if np["near"] is Array else [np["near"]]
					if in_map(c + d) and str(terrain_of.call(c + d)) in nears:
						near = true
				if near:
					var nart: String = str(np.get("winter_art", np["art"])) if bool(cfg.get("winter", false)) else str(np["art"])
					var jn := Vector3((_hash01(x, y, 21) - 0.5) * 0.3, 0, (_hash01(x, y, 23) - 0.5) * 0.2)
					_add_tree(cell_center(c) + jn, nart, float(np.get("scale", 1.0)) * lerpf(0.85, 1.15, _hash01(x, y, 25)))
			if cfg["trees"].has(k):
				# 同一種地形的樹稍微錯開，看起來不像排隊
				var tcfg: Dictionary = cfg["trees"][k]
				if _hash01(x, y, 13) >= float(tcfg.get("chance", 1.0)):
					continue
				var j := Vector3(((x * 37 + y * 11) % 7 - 3) * 0.04, 0, ((x * 13 + y * 29) % 7 - 3) * 0.03)
				# no_mix：固定用這張（大石頭之類，不跟著 tree_mix 換成樹）
				var tart: String = str(tcfg["art"]) if bool(tcfg.get("no_mix", false)) else _tree_art(x, y, str(tcfg["art"]))
				# front：往格子前緣放（草原的高草放在 0.32，蓋住站在同一格的狼）
				_add_tree(cell_center(c) + Vector3(0, 0, float(tcfg.get("front", 0.1))) + j, tart, float(tcfg["scale"]) * lerpf(0.9, 1.1, _hash01(x, y, 3)))
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
				# 水面材質（2026-11-08，ChatGPT）：water_tex 有寫就貼波紋（冬天 winter_water_tex 結冰），照世界座標拼接、一格 32 個材質像素；
				# 顏色改成 tex_tint（乘在材質上，深水暗一點）＋原本的透明度
				var wtex: String = str(cfg.get("winter_water_tex", "")) if bool(cfg.get("winter", false)) and cfg.has("winter_water_tex") else str(cfg.get("water_tex", ""))
				if wtex != "":
					wm.albedo_texture = load(HD_DIR + "assets/tex_%s.png" % wtex)
					wm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					wm.uv1_triplanar = true
					wm.uv1_world_triplanar = true
					wm.uv1_scale = Vector3.ONE * (32.0 / float(wm.albedo_texture.get_width()))
					var tt: Array = water[k].get("tex_tint", [1.0, 1.0, 1.0])
					if bool(cfg.get("winter", false)) and cfg.has("winter_water_tint"):
						tt = cfg["winter_water_tint"]
					var wa: float = float(cfg.get("winter_water_alpha", 0.95)) if bool(cfg.get("winter", false)) and cfg.has("winter_water_tex") else float(water[k]["color"][3])
					wm.albedo_color = Color(float(tt[0]), float(tt[1]), float(tt[2]), wa)
				wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				wm.roughness = 0.2
				wm_i.material_override = wm
				wm_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				world.add_child(wm_i)
	# edge_props：地圖外圍一整排物件（牧場的木柵欄沿著上緣），只是畫面
	var ep: Dictionary = cfg.get("edge_props", {})
	if not ep.is_empty():
		for x in map_w:
			_add_tree(Vector3(x + 0.5, 0, -0.3), str(ep["art"]), float(ep.get("scale", 1.0)))
		# 外圍的其他物件（牧場的小木屋）
		for ex in ep.get("extra", []):
			_add_tree(Vector3(float(ex.get("x", 1.0)), 0, float(ex.get("z", -1.5))), str(ex["art"]), float(ex.get("scale", 1.0)))
	_build_border(bottom)
	overlay = Node3D.new()
	world.add_child(overlay)

func _add_tree(pos: Vector3, art: String, scale: float) -> void:
	# fixed_scale：這張圖固定的縮放（灌木、倒木一格一個，不跟著大樹、小樹的格子放大縮小），稍微隨機 ±10%
	# 秋天換圖（autumn_swap：白樺換成金黃葉子的）
	if str(cfg.get("season", "")) == "autumn":
		art = str(cfg.get("autumn_swap", {}).get(art, art))
	var fs: Dictionary = cfg.get("fixed_scale", {})
	if fs.has(art):
		scale = float(fs[art]) * lerpf(0.9, 1.1, _hash01(int(pos.x * 10.0), int(pos.z * 10.0), 5))
	var s := _make_sprite(false)
	tree_sprites.append({"sprite": s, "art": art, "scale": scale, "cell": Vector2i(int(floor(pos.x)), int(floor(pos.z)))})
	s.position = pos

# 地圖外圍一圈地面與密林（cfg.border：width 幾格、ground 用哪一種地形的材質、tree_chance 每格有樹的機率、tree、scale）
# 只是畫面：點不到、走不到，讓地圖不像浮在空中
func _build_border(bottom: float) -> void:
	var bd: Dictionary = cfg.get("border", {})
	var w: int = int(bd.get("width", 0))
	if w <= 0:
		return
	var gk: String = str(bd.get("ground", "."))
	for y in range(-w, map_h + w):
		for x in range(-w, map_w + w):
			if x >= 0 and y >= 0 and x < map_w and y < map_h:
				continue
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(1, -bottom, 1)
			mi.mesh = box
			mi.position = Vector3(x + 0.5, bottom * 0.5, y + 0.5)
			mi.material_override = _terrain_mat(gk, _patch_for(gk, x, y))
			world.add_child(mi)
			# 離地圖越遠樹越密；最靠近地圖的那一圈稀一點，才看得到邊緣
			var dist: int = maxi(maxi(-x, x - map_w + 1), maxi(-y, y - map_h + 1))
			var ch: float = float(bd.get("tree_chance", 0.7)) * (0.55 if dist == 1 else 1.0)
			# 鏡頭這一側（地圖下方）的樹會擋住最下面幾列：不種樹
			if y >= map_h:
				ch = 0.0
			if _hash01(x, y, 5) < ch:
				var j := Vector3((_hash01(x, y, 6) - 0.5) * 0.3, 0, (_hash01(x, y, 8) - 0.5) * 0.3)
				var sc: Array = bd.get("scale", [0.8, 1.1])
				_add_tree(Vector3(x + 0.5, 0, y + 0.6) + j, _tree_art(x, y, str(bd.get("tree", "pine_dark"))), lerpf(float(sc[0]), float(sc[1]), _hash01(x, y, 9)))

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
		s.texture = load(HD_DIR + "assets/%s_%d.png" % [str(t["art"]), art_px])
		s.pixel_size = float(t["scale"]) / float(art_px)
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
	var occupied: Array = []
	for k in units.keys():
		if not bool(units[k]["used"]):
			(units[k]["sprite"] as Sprite3D).visible = false
			(units[k]["shadow"] as MeshInstance3D).visible = false
			(units[k]["label"] as Label3D).visible = false
		else:
			var sp: Vector3 = (units[k]["sprite"] as Sprite3D).position
			occupied.append(Vector2i(int(floor(sp.x)), int(floor(sp.z))))
	_fade_trees(occupied)

# 擋在角色前面（鏡頭這一側、往下 1～3 格、左右 1 格內）的樹變半透明，看得到後面的動物
func _fade_trees(cells: Array) -> void:
	var keep: Array = cfg.get("no_fade", [])
	for t in tree_sprites:
		var s: Sprite3D = t["sprite"]
		var tc: Vector2i = t["cell"]
		# no_fade：不淡化的物件（草原的高草：就是要蓋住站在裡面的狼，製造潛伏感）
		if str(t["art"]) in keep:
			continue
		var front := false
		for c in cells:
			if absi(tc.x - c.x) <= 1 and tc.y - c.y >= 0 and tc.y - c.y <= 3:
				front = true
				break
		if front:
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			s.modulate = Color(1, 1, 1, 0.35)
		else:
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			s.modulate = Color.WHITE

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
	# 角色不接受別的樹、物件投下的影子（2026-11-08：樹影打在灰熊前半身，看起來像一塊黑色）；光線、時段的顏色照常
	var um: StandardMaterial3D = ent.get("mat", null)
	if um == null:
		um = StandardMaterial3D.new()
		um.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		um.alpha_scissor_threshold = 0.5
		um.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		um.vertex_color_use_as_albedo = true
		um.disable_receive_shadows = true
		um.cull_mode = BaseMaterial3D.CULL_DISABLED
		um.roughness = 1.0
		ent["mat"] = um
		s2.material_override = um
	var tx: Texture2D = art["tex"]
	um.albedo_texture = (tx as AtlasTexture).atlas if tx is AtlasTexture else tx
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
