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

var _frame: int = 0
var _timer: float = 0.0

func setup(p_sheet: Texture2D, p_frame_size: Vector2i, p_row: int, p_frame_count: int, p_fps: float = 6.0) -> void:
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
	texture = tex

func _process(delta: float) -> void:
	if sheet == null or frame_count <= 1:
		return
	_timer += delta
	var frame_time: float = 1.0 / max(0.001, fps)
	if _timer >= frame_time:
		_timer -= frame_time
		_frame = (_frame + 1) % frame_count
		_update_frame()

func _update_frame() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(frame_size.x * _frame, frame_size.y * row, frame_size.x, frame_size.y)
	texture = atlas
