class_name AnimatedIcon
extends TextureRect

# A TextureRect that cycles through one row of a fixed-frame-size sprite
# sheet, for use anywhere a plain TextureRect was showing a static PixelArt
# texture. Real sheets (see assets/art/sprites/) replace the procedural ones
# without any other UI code changing.

var sheet: Texture2D
var frame_size: Vector2i
var row: int = 0
var frame_count: int = 4
var fps: float = 6.0
var loop: bool = true # false：播一次停在最後一格（戰鬥的撲咬、被打飛等動作）
# 固定像素倍率（> 0 時）：圖不縮放塞滿框，而是照原始像素大小 × zoom 畫在框的底部中央，
# 讓不同動物照比例顯示（狩獵、戰鬥畫面；2026-10-13）。框外的部分照樣畫出來。
var zoom: float = 0.0:
	set(v):
		zoom = v
		if zoom > 0.0 and texture != null:
			_shown = texture
			texture = null
		queue_redraw()
var _shown: Texture2D

var _frame: int = 0
var _timer: float = 0.0

func setup(p_sheet: Texture2D, p_frame_size: Vector2i, p_row: int, p_frame_count: int, p_fps: float = 6.0, p_loop: bool = true) -> void:
	loop = p_loop
	sheet = p_sheet
	frame_size = p_frame_size
	row = p_row
	frame_count = p_frame_count
	fps = p_fps
	_frame = 0
	_timer = 0.0
	_update_frame()
	set_process(frame_count > 1)

# 顯示單張圖（不播動畫）。
func show_static(tex: Texture2D) -> void:
	sheet = null
	frame_count = 1
	set_process(false)
	_set_tex(tex)

func _process(delta: float) -> void:
	if sheet == null or frame_count <= 1:
		return
	_timer += delta
	var frame_time: float = 1.0 / max(0.001, fps)
	if _timer >= frame_time:
		_timer -= frame_time
		if not loop and _frame >= frame_count - 1:
			set_process(false)
			return
		_frame = (_frame + 1) % frame_count
		_update_frame()

func _update_frame() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(frame_size.x * _frame, frame_size.y * row, frame_size.x, frame_size.y)
	_set_tex(atlas)

func _set_tex(t: Texture2D) -> void:
	if zoom > 0.0:
		_shown = t
		texture = null
		queue_redraw()
	else:
		texture = t

func _draw() -> void:
	if zoom <= 0.0 or _shown == null:
		return
	var s: Vector2 = _shown.get_size() * zoom
	var pos := Vector2((size.x - s.x) * 0.5, size.y - s.y)
	if flip_h:
		# 水平翻轉：以圖的右緣為原點、x 反向（負寬度的矩形不會翻轉）
		draw_set_transform(Vector2(pos.x + s.x, pos.y), 0.0, Vector2(-1, 1))
		draw_texture_rect(_shown, Rect2(Vector2.ZERO, s), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(_shown, Rect2(pos, s), false)
