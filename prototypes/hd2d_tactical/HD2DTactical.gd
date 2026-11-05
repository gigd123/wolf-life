extends Control
# HD-2D 戰術場景測試（2026-11-04，和遊戲進度無關）
# 目的：看「3D 地形＋像素角色」的戰術地圖好不好看、看不看得清楚，比較：
#   - 分段縮放（畫布整數倍放大，像素乾淨）vs 無段縮放（滑順，像素可能不整齊）
#   - 全貌：簡化的俯視圖 vs 拉很遠的 HD-2D 畫面
#   - 一格 32 vs 48 像素
#   - （2026-11-05）平常 32、拉近想看 48 的兩種做法：兩套素材依縮放自動切換 vs 只畫 48 一套、拉遠時縮小顯示
# 素材是從使用者給的概念圖裁出來的（prep_assets.py），只用在這裡。
# 專案用 Compatibility 渲染器（沒有內建景深），景深用 tilt_shift.gdshader 在 2D 畫面上做。

const DIR := "res://prototypes/hd2d_tactical/"
const SNOW := "snow"
const DIRT := "dirt"
const GRASS := "grass"
const ROCK := "rock"
const WATER := "water"

var cfg: Dictionary = {}
var map_w := 32
var map_h := 16
var level_h := 0.5
var terrain: Array = [] # [y][x] 地面種類
var height: Array = [] # [y][x] 高度（階）
var side: Array = [] # [y][x] 側面材質
var blocked := {} # 樹佔的格子（不能走）

var tile_px := 32
# 素材的做法（2026-11-05）："fixed" 照「每格」按鈕；"swap" 兩套素材，螢幕上一格夠大就換 48；"down48" 只用 48，拉遠時縮小
const ART_MODES := ["fixed", "swap", "down48"]
var art_mode := "fixed"
var loaded_px := 0 # 目前載入的素材是幾像素的那套
var smooth_min := false # 只用 48 時，縮小用平滑濾鏡（mipmap）還是最近點
var smooth := false
var level := 0 # 分段縮放：0 近、1 中、2 遠
var smooth_tile := 96.0 # 無段縮放：螢幕上一格的像素
var far_view := false
var cam_target := Vector3.ZERO
var mouse_moved := false
var dragging := false

var sub: SubViewport
var world_root: Node3D
var cam: Camera3D
var screen: TextureRect
var post: ShaderMaterial
var terrain_mats := {}
var hover: MeshInstance3D
var wolf: Sprite3D
var moose: Sprite3D
var trees: Array = [] # [{sprite, cell, kind}]
var shadows: Array = []
var wolf_cell := Vector2i(5, 10)
var moose_cell := Vector2i(24, 7)
var path: Array = []
var step_t := 0.0
var step_from := Vector3.ZERO
var step_to := Vector3.ZERO
var step_jump := false
var walk_frame := 0
var info: Label
var overview: Control
var grid_on := true
var dof_on := true
var buttons := {}

func _ready() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(DIR + "hd2d_tactical.json"))
	map_w = int(cfg["map_w"])
	map_h = int(cfg["map_h"])
	level_h = float(cfg["level_height"])
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_map()
	_build_view()
	_build_world()
	_build_ui()
	_apply_tile()
	_focus_wolf()

# --- 地圖（固定的配置：雪地、岩石台、石牆矮坎、碎石坡、峭壁、小溪、草地）---
func _build_map() -> void:
	terrain.clear()
	height.clear()
	side.clear()
	for y in map_h:
		var tr_row: Array = []
		var h_row: Array = []
		var s_row: Array = []
		for x in map_w:
			var t := SNOW if x < 11 else (DIRT if x < 18 else GRASS)
			if x >= 20 and x <= 27 and y >= 5 and y <= 10:
				t = DIRT
			if x >= 9 and x <= 12 and (y + x) % 3 == 0:
				t = DIRT
			tr_row.append(t)
			h_row.append(0)
			s_row.append(DIRT)
		terrain.append(tr_row)
		height.append(h_row)
		side.append(s_row)
	# 岩石台（狼可以跳上去：高 2 階）
	_fill(Rect2i(3, 3, 5, 4), SNOW, 2, ROCK)
	# 石牆矮坎（高 1 階，走得上去）
	_fill(Rect2i(1, 8, 9, 1), SNOW, 1, "wall")
	# 碎石坡：往右一階一階升高，接到峭壁上面
	for x in range(12, 17):
		_fill(Rect2i(x, 1, 1, 5), ROCK, x - 11, ROCK)
	# 峭壁（高 6 階，只能從碎石坡上去）
	_fill(Rect2i(17, 0, 6, 4), GRASS, 6, ROCK)
	# 岩柱（高 4 階，上不去）
	_fill(Rect2i(24, 11, 3, 2), SNOW, 4, ROCK)
	# 右邊：草地上的矮岩坎（高 1 階）與一塊高台（高 3 階，要從矮岩坎一階一階上去）
	_fill(Rect2i(32, 5, 5, 3), GRASS, 1, ROCK)
	_fill(Rect2i(34, 2, 4, 3), GRASS, 2, ROCK)
	_fill(Rect2i(36, 2, 2, 2), SNOW, 3, ROCK)
	# 小溪（低一階，有水）
	for x in range(14, map_w):
		for y in [13, 14]:
			terrain[y][x] = WATER
			height[y][x] = -1
			side[y][x] = DIRT

func _fill(r: Rect2i, t: String, h: int, s: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			terrain[y][x] = t
			height[y][x] = h
			side[y][x] = s

func top_y(c: Vector2i) -> float:
	return float(height[c.y][c.x]) * level_h

func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x + 0.5, top_y(c), c.y + 0.5)

func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_w and c.y < map_h

# --- 畫面：3D 畫在 SubViewport，再用 TextureRect（加 tilt-shift）放大到螢幕 ---
func _build_view() -> void:
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
	post.shader = load(DIR + "tilt_shift.gdshader")
	var ts: Dictionary = cfg["tilt_shift"]
	post.set_shader_parameter("focus", float(ts["focus"]))
	post.set_shader_parameter("band", float(ts["band"]))
	post.set_shader_parameter("max_blur", float(ts["max_blur"]))
	screen.material = post
	add_child(screen)

func _build_world() -> void:
	world_root = Node3D.new()
	sub.add_child(world_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.76)
	var amb: Dictionary = cfg["ambient"]
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _col(amb["color"])
	e.ambient_light_energy = float(amb["energy"])
	var fog: Dictionary = cfg["fog"]
	e.fog_enabled = true
	e.fog_light_color = _col(fog["color"])
	e.fog_density = float(fog["density"])
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_bloom = 0.03
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.92
	env.environment = e
	world_root.add_child(env)
	var lc: Dictionary = cfg["light"]
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(float(lc["pitch"]), float(lc["yaw"]), 0)
	sun.light_energy = float(lc["energy"])
	sun.light_color = _col(lc["color"])
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	world_root.add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = Vector3(float(cfg["camera_pitch"]), 0, 0)
	cam.near = 0.1
	cam.far = 300.0
	world_root.add_child(cam)
	# 地形方塊
	var bottom := -2.0 * level_h
	for y in map_h:
		for x in map_w:
			var c := Vector2i(x, y)
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			var top := top_y(c)
			box.size = Vector3(1, top - bottom, 1)
			mi.mesh = box
			mi.position = Vector3(x + 0.5, (top + bottom) * 0.5, y + 0.5)
			var t: String = terrain[y][x]
			mi.material_override = _terrain_mat(DIRT if t == WATER else t, side[y][x])
			world_root.add_child(mi)
	# 水面
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(map_w - 14, 2)
	water.mesh = plane
	water.position = Vector3(14 + (map_w - 14) * 0.5, -level_h * 0.3, 14.0)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.32, 0.52, 0.62, 0.62)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.2
	wm.metallic_specular = 0.8
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(water)
	# 滑鼠所在的格子
	hover = MeshInstance3D.new()
	var hp := PlaneMesh.new()
	hp.size = Vector2(0.94, 0.94)
	hover.mesh = hp
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1.0, 0.9, 0.4, 0.35)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover.material_override = hm
	hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover.visible = false
	world_root.add_child(hover)
	# 樹、狼、駝鹿
	_place_trees()
	wolf = _make_sprite()
	moose = _make_sprite()
	wolf.position = cell_center(wolf_cell)
	moose.position = cell_center(moose_cell)

func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))

func _terrain_mat(top: String, side_kind: String) -> ShaderMaterial:
	var key := top + "/" + side_kind
	if terrain_mats.has(key):
		return terrain_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load(DIR + "terrain.gdshader")
	var tt: Texture2D = load(DIR + "assets/tex_%s.png" % top)
	var st: Texture2D = load(DIR + "assets/tex_%s.png" % side_kind)
	m.set_shader_parameter("top_tex", tt)
	m.set_shader_parameter("side_tex", st)
	m.set_shader_parameter("top_tex_s", tt)
	m.set_shader_parameter("side_tex_s", st)
	m.set_shader_parameter("top_size", float(tt.get_width()))
	m.set_shader_parameter("side_size", float(st.get_width()))
	terrain_mats[key] = m
	return m

func _place_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261104
	var spots: Array = []
	for x in map_w:
		spots.append(Vector2i(x, 0))
		if x % 2 == 0 or x < 12:
			spots.append(Vector2i(x, map_h - 1))
	for y in range(1, map_h - 1):
		spots.append(Vector2i(0, y))
		spots.append(Vector2i(map_w - 1, y))
	for c in [Vector2i(9, 2), Vector2i(10, 4), Vector2i(2, 12), Vector2i(8, 12), Vector2i(9, 13), Vector2i(12, 9), Vector2i(13, 11),
			Vector2i(19, 9), Vector2i(18, 11), Vector2i(29, 4), Vector2i(28, 2), Vector2i(29, 9), Vector2i(30, 11), Vector2i(23, 4),
			Vector2i(17, 6), Vector2i(26, 3), Vector2i(21, 1), Vector2i(19, 2),
			Vector2i(31, 3), Vector2i(33, 9), Vector2i(35, 11), Vector2i(38, 8), Vector2i(31, 10), Vector2i(36, 6)]:
		spots.append(c)
	for c in spots:
		if not in_map(c) or blocked.has(c) or terrain[c.y][c.x] == WATER or c == wolf_cell or c == moose_cell:
			continue
		# 碎石坡、岩石台上不種
		if (c.x >= 12 and c.x <= 16 and c.y >= 1 and c.y <= 5) or (c.x >= 3 and c.x <= 7 and c.y >= 3 and c.y <= 6):
			continue
		if rng.randf() < 0.18 and c.x > 0 and c.x < map_w - 1 and c.y > 0 and c.y < map_h - 1:
			continue
		var kind := "pine_snow" if (c.x < 14 or rng.randf() < 0.3) else "pine_dark"
		var s := _make_sprite(false)
		var jitter := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.1, 0.1))
		s.position = cell_center(c) + jitter
		trees.append({"sprite": s, "cell": c, "kind": kind})
		blocked[c] = true

func _make_sprite(blob := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	# 樹投影子；動物用腳下的圓影（像素圖投出來的影子是一整個黑色剪影，不好看）
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if blob else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	world_root.add_child(s)
	if blob:
		var sh := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(1.1, 0.55)
		sh.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _blob_texture()
		m.albedo_color = Color(0, 0, 0, 0.45)
		sh.material_override = m
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(sh)
		shadows.append({"mesh": sh, "owner": s})
	return s

var _blob: ImageTexture
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

# 換一格幾像素：素材換成那個密度的版本，地形材質的像素密度跟著換
func _apply_tile() -> void:
	_load_assets(_art_px())
	_update_camera()

# 這個縮放下該用哪一套素材
func _art_px() -> int:
	match art_mode:
		"down48":
			return 48
		"swap":
			if far_view:
				return 32
			var sw: Dictionary = cfg.get("swap", {"up": 44.0, "down": 40.0})
			# 有一點落差（往上 up 才換 48、往下 down 才換回 32），停在門檻附近時不會一直跳
			if loaded_px == 48:
				return 48 if smooth_tile >= float(sw["down"]) else 32
			return 48 if smooth_tile >= float(sw["up"]) else 32
	return tile_px

func _filter() -> int:
	return BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if art_mode == "down48" and smooth_min else BaseMaterial3D.TEXTURE_FILTER_NEAREST

func _load_assets(px: int) -> void:
	loaded_px = px
	var ps := 1.0 / float(px)
	for t in trees:
		var s: Sprite3D = t["sprite"]
		s.texture = load(DIR + "assets/%s_%d.png" % [t["kind"], px])
		s.pixel_size = ps
		s.texture_filter = _filter()
		s.offset = Vector2(0, s.texture.get_height() * 0.5 - 2)
	_set_wolf_frame("wolf_stand")
	moose.texture = load(DIR + "assets/moose_stand_%d.png" % px)
	moose.pixel_size = ps
	moose.texture_filter = _filter()
	moose.offset = Vector2(0, moose.texture.get_height() * 0.5 - 1)
	for m in terrain_mats.values():
		(m as ShaderMaterial).set_shader_parameter("texels_per_unit", float(px))
		(m as ShaderMaterial).set_shader_parameter("smooth_min", art_mode == "down48" and smooth_min)

func _set_wolf_frame(name: String) -> void:
	var px: int = loaded_px if loaded_px > 0 else tile_px
	wolf.texture = load(DIR + "assets/%s_%d.png" % [name, px])
	wolf.pixel_size = 1.0 / float(px)
	wolf.texture_filter = _filter()
	wolf.offset = Vector2(0, wolf.texture.get_height() * 0.5 - 1)

func _cycle_art_mode() -> void:
	art_mode = ART_MODES[(ART_MODES.find(art_mode) + 1) % ART_MODES.size()]
	# 兩種新做法都是看「滑順地拉近拉遠」時的樣子：切到無段縮放
	if art_mode != "fixed" and not smooth:
		smooth = true
		far_view = false
	_apply_tile()

# --- 鏡頭 ---
func _window_px() -> Vector2i:
	return get_window().size

func _canvas_size() -> Vector2i:
	var w := _window_px()
	if smooth or far_view:
		return w
	var s := int(cfg["step_scales"][level])
	return Vector2i(max(1, w.x / s), max(1, w.y / s))

func _update_camera() -> void:
	if loaded_px > 0 and _art_px() != loaded_px:
		_load_assets(_art_px())
	var canvas := _canvas_size()
	if sub.size != canvas:
		sub.size = canvas
	post.set_shader_parameter("canvas_size", Vector2(canvas))
	post.set_shader_parameter("enabled", dof_on)
	if far_view:
		# 整張地圖放進畫面：直的看斜過去的深度，橫的看寬度
		var pitch := deg_to_rad(-float(cfg["camera_pitch"]))
		var need_h := map_h * sin(pitch) + 6.0 * level_h * cos(pitch) + 3.0
		var aspect := float(canvas.x) / float(canvas.y)
		cam.size = max(need_h, (map_w + 1.0) / aspect)
		cam_target = Vector3(map_w * 0.5, 0, map_h * 0.5)
	elif smooth:
		cam.size = float(canvas.y) / smooth_tile
	else:
		cam.size = float(canvas.y) / float(loaded_px if loaded_px > 0 else tile_px)
	_clamp_target()
	var fwd := -cam.global_transform.basis.z
	var pos := cam_target - fwd * 30.0
	if not smooth and not far_view:
		pos = _snap(pos, cam.size / float(canvas.y))
	cam.position = pos
	_update_info()

# 分段縮放時鏡頭對齊畫布像素，捲動時材質不會閃
func _snap(p: Vector3, px: float) -> Vector3:
	var b := cam.global_transform.basis
	var r := snappedf(p.dot(b.x), px)
	var u := snappedf(p.dot(b.y), px)
	var f := p.dot(b.z)
	return b.x * r + b.y * u + b.z * f

func _clamp_target() -> void:
	cam_target.x = clamp(cam_target.x, 0.0, float(map_w))
	cam_target.z = clamp(cam_target.z, 0.0, float(map_h))
	cam_target.y = 0.0

func _focus_wolf() -> void:
	far_view = false
	cam_target = Vector3(wolf.position.x, 0, wolf.position.z)
	_update_camera()

func _visible_tiles() -> Vector2:
	var canvas := _canvas_size()
	var w := float(canvas.x) / float(canvas.y) * cam.size
	var pitch := deg_to_rad(-float(cfg["camera_pitch"]))
	return Vector2(w, cam.size / sin(pitch))

func _zoom(dir: int) -> void:
	far_view = false
	if smooth:
		var sm: Dictionary = cfg["smooth"]
		var mult := float(sm["wheel_mult"])
		smooth_tile = clamp(smooth_tile * (mult if dir > 0 else 1.0 / mult), float(sm["min_tile"]), float(sm["max_tile"]))
	else:
		level = clamp(level - dir, 0, (cfg["step_scales"] as Array).size() - 1)
	_update_camera()

func _pan(delta_world: Vector2) -> void:
	far_view = false
	cam_target.x += delta_world.x
	cam_target.z += delta_world.y
	_update_camera()

# 螢幕（邏輯座標）→ 畫布座標
func _to_canvas(p: Vector2) -> Vector2:
	var vr := get_viewport_rect().size
	return p / vr * Vector2(sub.size)

func _pick_cell(p: Vector2) -> Vector2i:
	var cp := _to_canvas(p)
	var o := cam.project_ray_origin(cp)
	var n := cam.project_ray_normal(cp)
	var t := 0.0
	while t < 160.0:
		var q := o + n * t
		var c := Vector2i(int(floor(q.x)), int(floor(q.z)))
		if in_map(c) and q.y <= top_y(c) + 0.001:
			return c
		t += 0.03
	return Vector2i(-1, -1)

# --- 移動：一格一格走，高 1 階走上去、高 2 階跳上去，往下最多 3 階；樹、峭壁擋路 ---
func _can_step(a: Vector2i, b: Vector2i) -> bool:
	if not in_map(b) or blocked.has(b) or b == moose_cell:
		return false
	var dh: int = int(height[b.y][b.x]) - int(height[a.y][a.x])
	if dh > 0:
		return dh <= int(cfg["jump_up_levels"])
	return -dh <= int(cfg["drop_levels"])

func _find_path(from: Vector2i, to: Vector2i) -> Array:
	var prev := {from: from}
	var q: Array = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == to:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not prev.has(n) and _can_step(c, n):
				prev[n] = c
				q.append(n)
	if not prev.has(to):
		return []
	var out: Array = []
	var c2 := to
	while c2 != from:
		out.push_front(c2)
		c2 = prev[c2]
	return out

func _start_next_step() -> void:
	if path.is_empty():
		_set_wolf_frame("wolf_stand")
		return
	var next: Vector2i = path.pop_front()
	step_from = cell_center(wolf_cell)
	step_to = cell_center(next)
	step_jump = int(height[next.y][next.x]) - int(height[wolf_cell.y][wolf_cell.x]) >= int(cfg["climb_levels"]) + 1
	if next.x != wolf_cell.x:
		wolf.flip_h = next.x < wolf_cell.x
	wolf_cell = next
	step_t = 0.0
	walk_frame = 1 - walk_frame
	_set_wolf_frame("wolf_stalk" if step_jump else ("wolf_walk" if walk_frame == 0 else "wolf_walk2"))

func _process(delta: float) -> void:
	if step_from != step_to:
		var dur := float(cfg["move_step_sec"]) * (1.8 if step_jump else 1.0)
		step_t = min(1.0, step_t + delta / dur)
		var p := step_from.lerp(step_to, step_t)
		if step_jump or abs(step_to.y - step_from.y) > 0.01:
			p.y += sin(step_t * PI) * (0.6 if step_jump else 0.15)
		wolf.position = p
		if step_t >= 1.0:
			step_from = step_to
			_start_next_step()
	# 鍵盤、畫面邊緣捲動
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1
	if mouse_moved and not overview.visible:
		var mp := get_viewport().get_mouse_position()
		var vr := get_viewport_rect().size
		var e := float(cfg["edge_scroll_px"]) * vr.y / 360.0
		if mp.x < e: pan.x -= 1
		if mp.x > vr.x - e: pan.x += 1
		if mp.y < e: pan.y -= 1
		if mp.y > vr.y - e: pan.y += 1
	if pan != Vector2.ZERO:
		_pan(pan * float(cfg["pan_speed"]) * delta * cam.size / 11.0)
	_update_occlusion()
	_update_shadows()
	_face_moose()

# 擋住狼的樹變半透明（在狼前面、畫面上重疊）
func _update_occlusion() -> void:
	for t in trees:
		var s: Sprite3D = t["sprite"]
		var dz := s.position.z - wolf.position.z
		var tree_h := s.texture.get_height() * s.pixel_size if s.texture != null else 3.0
		var hide: bool = dz > 0.05 and dz < tree_h * 1.2 + 0.5 and abs(s.position.x - wolf.position.x) < 0.9 \
			and s.position.y >= wolf.position.y - 1.0
		if hide:
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			s.transparent = true
			s.modulate.a = 0.35
		else:
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			s.modulate.a = 1.0

func _update_shadows() -> void:
	for sh in shadows:
		var o: Sprite3D = sh["owner"]
		var m: MeshInstance3D = sh["mesh"]
		var c := Vector2i(int(floor(o.position.x)), int(floor(o.position.z)))
		var y := top_y(c) if in_map(c) else 0.0
		m.position = Vector3(o.position.x, y + 0.02, o.position.z)
		var w := (o.texture.get_width() * o.pixel_size) if o.texture != null else 1.0
		m.scale = Vector3(w * 0.8, 1, 1)

func _face_moose() -> void:
	moose.flip_h = wolf.position.x < moose.position.x

# --- 輸入 ---
func _unhandled_input(ev: InputEvent) -> void:
	if overview.visible:
		if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_TAB or ev.keycode == KEY_ESCAPE):
			_toggle_overview()
		return
	if ev is InputEventMouseMotion:
		mouse_moved = true
		if dragging:
			var px_world := cam.size / get_viewport_rect().size.y
			var pitch := deg_to_rad(-float(cfg["camera_pitch"]))
			_pan(Vector2(-ev.relative.x * px_world, -ev.relative.y * px_world / sin(pitch)))
		else:
			var c := _pick_cell(ev.position)
			hover.visible = in_map(c)
			if hover.visible:
				hover.position = cell_center(c) + Vector3(0, 0.015, 0)
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_zoom(1)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_zoom(-1)
		elif ev.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			dragging = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			var c := _pick_cell(ev.position)
			if in_map(c) and step_from == step_to:
				path = _find_path(wolf_cell, c)
				_start_next_step()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_TAB: _toggle_overview()
			KEY_F: _focus_wolf()
			KEY_G: _toggle_grid()
			KEY_EQUAL, KEY_KP_ADD: _zoom(1)
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom(-1)

# --- 介面 ---
func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(4, 4)
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 1)
	panel.add_child(outer)
	var title := Label.new()
	title.text = tr("hd2d.title")
	title.add_theme_font_size_override("font_size", 8)
	outer.add_child(title)
	var box := GridContainer.new()
	box.columns = 2
	box.add_theme_constant_override("h_separation", 1)
	box.add_theme_constant_override("v_separation", 1)
	outer.add_child(box)
	buttons["mode"] = _btn(box, "", func(): smooth = not smooth; far_view = false; _update_camera())
	buttons["tile"] = _btn(box, "", func(): tile_px = 48 if tile_px == 32 else 32; _apply_tile())
	buttons["art"] = _btn(box, "", func(): _cycle_art_mode())
	buttons["minf"] = _btn(box, "", func(): smooth_min = not smooth_min; _apply_tile())
	_btn(box, tr("hd2d.zoom_in"), func(): _zoom(1))
	_btn(box, tr("hd2d.zoom_out"), func(): _zoom(-1))
	_btn(box, tr("hd2d.overview.map"), func(): _toggle_overview())
	_btn(box, tr("hd2d.overview.far"), func(): far_view = not far_view; _update_camera())
	_btn(box, tr("hd2d.focus"), func(): _focus_wolf())
	_btn(box, tr("hd2d.grid"), func(): _toggle_grid())
	_btn(box, tr("hd2d.dof"), func(): dof_on = not dof_on; _update_camera())
	_btn(box, tr("hd2d.back"), func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	info = Label.new()
	info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info.position.y -= 26
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 8)
	info.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	info.add_theme_constant_override("outline_size", 3)
	add_child(info)
	overview = OverviewMap.new()
	overview.owner_view = self
	overview.set_anchors_preset(Control.PRESET_FULL_RECT)
	overview.visible = false
	add_child(overview)

func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 7)
	b.custom_minimum_size = Vector2(0, 0)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _toggle_grid() -> void:
	grid_on = not grid_on
	for m in terrain_mats.values():
		(m as ShaderMaterial).set_shader_parameter("show_grid", grid_on)

func _toggle_overview() -> void:
	overview.visible = not overview.visible
	overview.queue_redraw()

func _update_info() -> void:
	if info == null:
		return
	(buttons["mode"] as Button).text = tr("hd2d.zoom_mode.smooth" if smooth else "hd2d.zoom_mode.step")
	(buttons["tile"] as Button).text = tr("hd2d.tile").format({"n": tile_px})
	(buttons["tile"] as Button).disabled = art_mode != "fixed"
	(buttons["art"] as Button).text = tr("hd2d.art." + art_mode)
	(buttons["minf"] as Button).text = tr("hd2d.minify.smooth" if smooth_min else "hd2d.minify.nearest")
	(buttons["minf"] as Button).disabled = art_mode != "down48"
	var vt := _visible_tiles()
	var line: String
	if far_view:
		line = tr("hd2d.info.far")
	elif smooth:
		line = tr("hd2d.info.smooth").format({"t": int(round(smooth_tile)), "n": loaded_px, "w": int(vt.x), "h": int(vt.y)})
	else:
		line = tr("hd2d.info.step").format({"level": tr("hd2d.level.%d" % level), "s": int(cfg["step_scales"][level]), "n": tile_px, "w": int(vt.x), "h": int(vt.y)})
	if art_mode != "fixed":
		line += "・" + tr("hd2d.info.art." + art_mode).format({"n": loaded_px})
	info.text = line + "\n" + tr("hd2d.help")

# 給俯視圖用：點一格把鏡頭移過去
func center_on(c: Vector2i) -> void:
	far_view = false
	cam_target = Vector3(c.x + 0.5, 0, c.y + 0.5)
	overview.visible = false
	_update_camera()


# 全貌：簡化的俯視圖（地形色塊、高度深淺、峭壁的邊、樹、狼與駝鹿的圖示）
class OverviewMap extends Control:
	var owner_view
	const COLORS := {"snow": Color(0.86, 0.9, 0.94), "dirt": Color(0.47, 0.36, 0.26), "grass": Color(0.33, 0.48, 0.28),
		"rock": Color(0.5, 0.5, 0.52), "water": Color(0.3, 0.48, 0.62)}

	func _layout() -> Array:
		var v = owner_view
		var r := get_rect().size
		var cell: float = floor(min((r.x - 40.0) / v.map_w, (r.y - 60.0) / v.map_h))
		var origin := Vector2((r.x - cell * v.map_w) * 0.5, 30.0)
		return [cell, origin]

	func _draw() -> void:
		var v = owner_view
		draw_rect(Rect2(Vector2.ZERO, get_rect().size), Color(0.08, 0.09, 0.11, 0.92))
		var l := _layout()
		var cell: float = l[0]
		var o: Vector2 = l[1]
		for y in v.map_h:
			for x in v.map_w:
				var h: int = v.height[y][x]
				var col: Color = COLORS.get(v.terrain[y][x], Color.MAGENTA)
				col = col.darkened(0.12) if h <= 0 else col.lightened(min(0.25, h * 0.04))
				draw_rect(Rect2(o + Vector2(x, y) * cell, Vector2(cell, cell)), col)
				# 高低差 2 階以上畫邊（跳不上去或要跳）
				for d in [Vector2i(1, 0), Vector2i(0, 1)]:
					var n: Vector2i = Vector2i(x, y) + d
					if n.x < v.map_w and n.y < v.map_h and abs(int(v.height[n.y][n.x]) - h) >= 2:
						var a := o + Vector2(n.x, n.y) * cell
						var b := a + (Vector2(0, cell) if d.x == 1 else Vector2(cell, 0))
						draw_line(a, b, Color(0.1, 0.08, 0.06), 2.0)
		for x in v.map_w + 1:
			draw_line(o + Vector2(x * cell, 0), o + Vector2(x * cell, v.map_h * cell), Color(0, 0, 0, 0.15))
		for y in v.map_h + 1:
			draw_line(o + Vector2(0, y * cell), o + Vector2(v.map_w * cell, y * cell), Color(0, 0, 0, 0.15))
		for t in v.trees:
			var c: Vector2i = t["cell"]
			var p := o + (Vector2(c) + Vector2(0.5, 0.5)) * cell
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -cell * 0.38), p + Vector2(cell * 0.3, cell * 0.3), p + Vector2(-cell * 0.3, cell * 0.3)]), Color(0.1, 0.25, 0.17))
		var mp := o + (Vector2(v.moose_cell) + Vector2(0.5, 0.5)) * cell
		draw_circle(mp, cell * 0.4, Color(0.15, 0.08, 0.04))
		draw_circle(mp, cell * 0.32, Color(0.6, 0.4, 0.25))
		var wp := o + Vector2(v.wolf.position.x, v.wolf.position.z) * cell
		draw_circle(wp, cell * 0.4, Color(0.05, 0.05, 0.08))
		draw_circle(wp, cell * 0.32, Color(0.85, 0.87, 0.9))
		# 目前鏡頭看到的範圍
		var vt: Vector2 = v._visible_tiles()
		var ct: Vector3 = v.cam_target
		draw_rect(Rect2(o + (Vector2(ct.x, ct.z) - vt * 0.5) * cell, vt * cell), Color(1, 0.9, 0.4, 0.8), false, 1.0)
		var font := get_theme_default_font()
		draw_string(font, Vector2(o.x, 20), tr("hd2d.overview.help"), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.9, 0.9))

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var l := _layout()
			var cell: float = l[0]
			var c := Vector2i(((ev.position - l[1]) / cell).floor())
			if owner_view.in_map(c):
				owner_view.center_on(c)
			accept_event()
