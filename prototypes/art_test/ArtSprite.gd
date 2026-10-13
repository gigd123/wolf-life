extends Node2D

# 美術測試場景用的角色圖（和遊戲程式無關，見 ArtTest.gd）。
# 讀 assets/art/art_test/manifest.json 的一隻動物：每個動作一張橫向 spritesheet，
# 以腳底中心為原點畫出來，依目標高度縮放；插畫版平滑縮放，像素版用整數倍率、最近鄰。
# 該風格沒有這隻動物時，改用遊戲現有的像素圖（ArtLibrary）頂替，fallback_id 是遊戲裡的動物 ID。

signal finished(action: String)

var entry: Dictionary = {}
var pixel: bool = false
var target_h: float = 46.0
var flip: bool = false:
	set(v):
		flip = v
		queue_redraw()
		if _fallback != null:
			_fallback.flip_h = v
var action: String = ""
var speed: float = 1.0

var _sheets: Dictionary = {}
var _frame: int = 0
var _timer: float = 0.0
var _fallback: AnimatedIcon
var _fallback_id: String = ""
var _fallback_wolf: bool = false
var _fallback_timer: float = -1.0

# 遊戲動作名稱對應（頂替用的舊圖）
const FALLBACK_ACTION := {"idle": "idle", "walk": "move", "hop": "move", "bite": "attack", "hurt": "hurt"}


func setup(p_entry: Dictionary, p_pixel: bool, p_target_h: float, fallback_id: String = "", fallback_wolf: bool = false) -> void:
	entry = p_entry
	pixel = p_pixel
	target_h = p_target_h
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel else CanvasItem.TEXTURE_FILTER_LINEAR
	_sheets.clear()
	if _fallback != null:
		_fallback.queue_free()
		_fallback = null
	_fallback_id = fallback_id
	_fallback_wolf = fallback_wolf
	if entry.is_empty() and fallback_id != "":
		_fallback = AnimatedIcon.new()
		_fallback.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fallback)
	play("idle")


func has_action(a: String) -> bool:
	return entry.get("actions", {}).has(a) or (_fallback != null and FALLBACK_ACTION.has(a))


func play(a: String, p_speed: float = 1.0) -> void:
	speed = p_speed
	if not entry.is_empty() and not entry.get("actions", {}).has(a):
		a = "walk" if a == "hop" and entry["actions"].has("walk") else "idle"
	action = a
	_frame = 0
	_timer = 0.0
	if _fallback != null:
		_setup_fallback(a)
	queue_redraw()


func _setup_fallback(a: String) -> void:
	var game_action: String = FALLBACK_ACTION.get(a, "idle")
	if _fallback_wolf:
		if game_action == "attack":
			ArtLibrary.setup_wolf_strip(_fallback, "bite")
		elif game_action == "hurt":
			ArtLibrary.setup_wolf_strip(_fallback, "hurt")
		else:
			ArtLibrary.setup_wolf(_fallback, "walk" if game_action == "move" else "idle", 8.0)
	else:
		ArtLibrary.setup_animal(_fallback, _fallback_id, "adult", game_action)
	# 舊圖的成年灰狼約 30 像素高；照比例放大到目標高度（取 0.5 的倍數，避免像素忽大忽小）
	var zoom: float = maxf(0.5, round(target_h / 30.0 * 2.0) / 2.0)
	_fallback.zoom = zoom
	var fs: Vector2 = Vector2(_fallback.frame_size) if _fallback.frame_size != Vector2i.ZERO else Vector2(48, 32)
	_fallback.size = fs * zoom
	_fallback.position = Vector2(-fs.x * zoom / 2.0, -fs.y * zoom)
	_fallback.flip_h = flip
	_fallback_timer = 0.6 if game_action in ["attack", "hurt"] else -1.0


func _act() -> Dictionary:
	return entry.get("actions", {}).get(action, {})


func _sheet() -> Texture2D:
	var path: String = str(_act().get("sheet", ""))
	if path == "":
		return null
	if not _sheets.has(path):
		_sheets[path] = load(path)
	return _sheets[path]


func duration(a: String) -> float:
	var info: Dictionary = entry.get("actions", {}).get(a, {})
	if info.is_empty():
		return 0.6
	return float(info["frames"]) / float(info["fps"])


func _process(delta: float) -> void:
	if _fallback != null:
		if _fallback_timer > 0.0:
			_fallback_timer -= delta
			if _fallback_timer <= 0.0:
				finished.emit(action)
		return
	var info := _act()
	if info.is_empty():
		return
	var n: int = int(info["frames"])
	_timer += delta * speed
	var step: float = 1.0 / float(info["fps"])
	while _timer >= step:
		_timer -= step
		if _frame < n - 1:
			_frame += 1
		elif bool(info["loop"]):
			_frame = 0
		else:
			_timer = 0.0
			finished.emit(action)
			break
		queue_redraw()


func scale_factor() -> float:
	var body_h: float = float(entry.get("body_h", 1))
	var s: float = target_h / body_h
	if pixel:
		s = maxf(1.0, round(s))
	return s


func _draw() -> void:
	var tex := _sheet()
	if tex == null:
		return
	var fw: float = float(entry["frame"][0])
	var fh: float = float(entry["frame"][1])
	var s: float = scale_factor()
	var src := Rect2(_frame * fw, 0, fw, fh)
	var dst := Rect2(-float(entry["center_x"]) * s, -float(entry["foot"]) * s, fw * s, fh * s)
	if flip:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	draw_texture_rect_region(tex, dst, src)
