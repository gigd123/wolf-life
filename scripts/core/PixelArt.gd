class_name PixelArt
extends RefCounted

# Procedural placeholder art per DESIGN.md "Phase 1 美術、音效、音樂" — plain
# geometric silhouettes, not real sprites, so they can be swapped for real
# art later without touching any code that calls these functions.

static func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var xa: int = max(0, x0)
	var xb: int = min(img.get_width(), x1)
	var ya: int = max(0, y0)
	var yb: int = min(img.get_height(), y1)
	for x in range(xa, xb):
		for y in range(ya, yb):
			img.set_pixel(x, y, color)

static func _fill_ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, color: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var x0: int = int(max(0, cx - rx))
	var x1: int = int(min(img.get_width(), cx + rx + 1))
	var y0: int = int(max(0, cy - ry))
	var y1: int = int(min(img.get_height(), cy + ry + 1))
	for x in range(x0, x1):
		for y in range(y0, y1):
			var nx: float = (x - cx) / rx
			var ny: float = (y - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, color)

static func _fill_triangle(img: Image, ax: float, ay: float, bx: float, by: float, cx: float, cy: float, color: Color) -> void:
	var min_x: int = int(max(0, min(ax, min(bx, cx))))
	var max_x: int = int(min(img.get_width(), max(ax, max(bx, cx)) + 1))
	var min_y: int = int(max(0, min(ay, min(by, cy))))
	var max_y: int = int(min(img.get_height(), max(ay, max(by, cy)) + 1))
	var area: float = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
	if absf(area) < 0.001:
		return
	for x in range(min_x, max_x):
		for y in range(min_y, max_y):
			var w1: float = ((bx - x) * (cy - y) - (cx - x) * (by - y)) / area
			var w2: float = ((cx - x) * (ay - y) - (ax - x) * (cy - y)) / area
			var w3: float = 1.0 - w1 - w2
			if w1 >= 0.0 and w2 >= 0.0 and w3 >= 0.0:
				img.set_pixel(x, y, color)

static func make_flat_texture(size: Vector2i, base_color: Color, seed_value: int = 0) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in range(size.y):
		for x in range(size.x):
			var jitter: float = rng.randf_range(-0.06, 0.06)
			var c := Color(
				clamp(base_color.r + jitter, 0.0, 1.0),
				clamp(base_color.g + jitter, 0.0, 1.0),
				clamp(base_color.b + jitter, 0.0, 1.0),
				1.0
			)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# --- Region map tiles ---
# A flat terrain colour plus a few simple "tree" blobs, lighter/whiter in
# winter to hint at snow, so the four forest regions read as distinct places.

const REGION_BASE_COLOR := {
	"forest_east": Color(0.30, 0.45, 0.28),
	"forest_north": Color(0.42, 0.52, 0.58),
	"forest_south": Color(0.55, 0.60, 0.34),
	"forest_west": Color(0.16, 0.28, 0.14),
}

static func make_region_tile(region_id: String, season: String, size: Vector2i = Vector2i(40, 40)) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var base: Color = REGION_BASE_COLOR.get(region_id, Color(0.3, 0.4, 0.3))
	if season == "winter":
		base = base.lerp(Color(0.85, 0.88, 0.92), 0.45)
	img.fill(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = region_id.hash()
	var trunk_color := Color(0.22, 0.16, 0.1)
	var leaf_color := Color(0.14, 0.26, 0.13).lerp(Color(0.9, 0.93, 0.95), 0.5 if season == "winter" else 0.0)
	var tree_count: int = 3
	for i in range(tree_count):
		var tx: float = rng.randf_range(size.x * 0.15, size.x * 0.85)
		var ty: float = rng.randf_range(size.y * 0.5, size.y * 0.85)
		_fill_rect(img, int(tx) - 1, int(ty) - int(size.y * 0.18), int(tx) + 1, int(ty), trunk_color)
		_fill_ellipse(img, tx, ty - size.y * 0.22, size.x * 0.11, size.y * 0.14, leaf_color)
	return ImageTexture.create_from_image(img)

# --- Animal silhouettes ---
# Same simple side-view quadruped shape for every species, distinguished by
# colour, ear/tail style and proportions. `scale` shrinks it for a juvenile
# or subadult wolf; `muzzle_grey` adds a pale muzzle patch for an elder wolf.

static func make_animal_sprite(species_id: String, size: Vector2i = Vector2i(48, 32), scale: float = 1.0, muzzle_grey: bool = false) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = size.x * 0.5
	var ground_y: float = size.y * 0.92
	match species_id:
		"gray_wolf":
			_draw_quadruped(img, cx, ground_y, scale, Color(0.42, 0.40, 0.37), "pointed", "bushy_up", 1.0, false, muzzle_grey)
		"white_tailed_deer":
			_draw_quadruped(img, cx, ground_y, scale, Color(0.55, 0.42, 0.28), "small", "thin_down", 1.15, true, false)
		"hare":
			_draw_quadruped(img, cx, ground_y, scale, Color(0.62, 0.56, 0.48), "long", "stub", 0.6, false, false)
		"red_fox":
			_draw_quadruped(img, cx, ground_y, scale, Color(0.72, 0.36, 0.18), "pointed", "bushy_low", 0.75, false, false)
		"grizzly_bear":
			_draw_quadruped(img, cx, ground_y, scale, Color(0.35, 0.27, 0.18), "round", "stub", 1.6, false, false)
		_:
			_draw_quadruped(img, cx, ground_y, scale, Color(0.5, 0.5, 0.5), "pointed", "stub", 1.0, false, false)
	return ImageTexture.create_from_image(img)

static func _draw_quadruped(
	img: Image, cx: float, ground_y: float, scale: float, body_color: Color,
	ear_style: String, tail_style: String, bulk: float, has_antlers: bool, muzzle_grey: bool
) -> void:
	var body_len: float = img.get_width() * 0.42 * scale * clamp(bulk, 0.6, 1.4)
	var body_h: float = img.get_height() * 0.22 * scale * clamp(bulk, 0.7, 1.3)
	var body_cy: float = ground_y - body_h * 1.1
	var head_r: float = body_h * 0.75
	var head_cx: float = cx + body_len * 0.55
	var head_cy: float = body_cy - body_h * 0.3

	# legs (drawn first so the body overlaps their tops)
	var leg_w: float = max(1.0, img.get_width() * 0.03 * scale)
	var leg_h: float = ground_y - body_cy
	for lx in [cx - body_len * 0.55, cx - body_len * 0.1, cx + body_len * 0.15, cx + body_len * 0.5]:
		_fill_rect(img, int(lx - leg_w * 0.5), int(body_cy), int(lx + leg_w * 0.5), int(ground_y), body_color)

	# body + head
	_fill_ellipse(img, cx, body_cy, body_len * 0.55, body_h, body_color)
	_fill_ellipse(img, head_cx, head_cy, head_r, head_r * 0.85, body_color)

	# snout
	var snout_len: float = head_r * 0.9
	_fill_ellipse(img, head_cx + snout_len * 0.7, head_cy + head_r * 0.15, snout_len * 0.6, head_r * 0.35, body_color)

	if muzzle_grey:
		_fill_ellipse(img, head_cx + snout_len * 0.9, head_cy + head_r * 0.15, snout_len * 0.35, head_r * 0.22, Color(0.75, 0.75, 0.72))

	# ears
	match ear_style:
		"pointed":
			_fill_triangle(img, head_cx - head_r * 0.2, head_cy - head_r * 0.4, head_cx + head_r * 0.15, head_cy - head_r * 1.5, head_cx + head_r * 0.5, head_cy - head_r * 0.5, body_color)
		"round":
			_fill_ellipse(img, head_cx, head_cy - head_r * 0.9, head_r * 0.32, head_r * 0.32, body_color)
		"long":
			_fill_rect(img, int(head_cx - head_r * 0.3), int(head_cy - head_r * 2.2), int(head_cx - head_r * 0.05), int(head_cy - head_r * 0.6), body_color)
			_fill_rect(img, int(head_cx + head_r * 0.05), int(head_cy - head_r * 2.4), int(head_cx + head_r * 0.3), int(head_cy - head_r * 0.6), body_color)
		"small":
			_fill_triangle(img, head_cx - head_r * 0.1, head_cy - head_r * 0.5, head_cx + head_r * 0.05, head_cy - head_r * 1.1, head_cx + head_r * 0.3, head_cy - head_r * 0.5, body_color)

	if has_antlers:
		var antler_color := Color(0.5, 0.42, 0.32)
		_fill_rect(img, int(head_cx - head_r * 0.1), int(head_cy - head_r * 2.3), int(head_cx + head_r * 0.05), int(head_cy - head_r * 0.9), antler_color)
		_fill_rect(img, int(head_cx - head_r * 0.5), int(head_cy - head_r * 2.1), int(head_cx - head_r * 0.1), int(head_cy - head_r * 1.9), antler_color)
		_fill_rect(img, int(head_cx + head_r * 0.05), int(head_cy - head_r * 2.5), int(head_cx + head_r * 0.45), int(head_cy - head_r * 2.3), antler_color)

	# tail
	match tail_style:
		"bushy_up":
			_fill_ellipse(img, cx - body_len * 0.65, body_cy - body_h * 0.7, body_h * 0.5, body_h * 0.7, body_color)
		"bushy_low":
			_fill_ellipse(img, cx - body_len * 0.7, body_cy + body_h * 0.2, body_h * 0.6, body_h * 0.35, body_color)
		"thin_down":
			_fill_rect(img, int(cx - body_len * 0.62), int(body_cy - body_h * 0.1), int(cx - body_len * 0.5), int(body_cy + body_h * 0.6), body_color)
		"stub":
			_fill_ellipse(img, cx - body_len * 0.55, body_cy - body_h * 0.1, body_h * 0.25, body_h * 0.22, body_color)

# --- Status icons ---

static func make_status_icon(kind: String, size: Vector2i = Vector2i(16, 16)) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	match kind:
		"injury":
			_fill_ellipse(img, cx, cy, size.x * 0.42, size.y * 0.42, Color(0.75, 0.15, 0.12))
			var bar_w: float = size.x * 0.55
			var bar_h: float = max(1.0, size.y * 0.14)
			_fill_rect(img, int(cx - bar_w * 0.5), int(cy - bar_h * 0.5), int(cx + bar_w * 0.5), int(cy + bar_h * 0.5), Color(1, 1, 1))
			_fill_rect(img, int(cx - bar_h * 0.5), int(cy - bar_w * 0.5), int(cx + bar_h * 0.5), int(cy + bar_w * 0.5), Color(1, 1, 1))
		"poison":
			_fill_ellipse(img, cx, cy + size.y * 0.05, size.x * 0.4, size.y * 0.38, Color(0.42, 0.65, 0.2))
			_fill_ellipse(img, cx - size.x * 0.18, cy - size.y * 0.28, size.x * 0.12, size.y * 0.12, Color(0.42, 0.65, 0.2))
			_fill_ellipse(img, cx + size.x * 0.2, cy - size.y * 0.32, size.x * 0.1, size.y * 0.1, Color(0.42, 0.65, 0.2))
		"hunger":
			_fill_ellipse(img, cx, cy + size.y * 0.1, size.x * 0.42, size.y * 0.3, Color(0.85, 0.55, 0.15))
			_fill_ellipse(img, cx, cy, size.x * 0.32, size.y * 0.2, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
