class_name ArtLibrary
extends RefCounted

# 美術對應表（data/art.json）的讀取。畫面層只透過這裡拿圖：
# 找不到對應的圖時回傳 false／null，呼叫端退回 PixelArt 程式生成的佔位圖。
# 換正式素材時維持相同檔名與尺寸，或只改 art.json 的路徑即可。

static var _cache: Dictionary = {}

static func _cfg() -> Dictionary:
	return GameData.art

static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_cache[path] = tex
	return tex

static func frame_size() -> Vector2i:
	var fs: Array = _cfg().get("frame_size", [48, 32])
	return Vector2i(int(fs[0]), int(fs[1]))

# 動物：sheet 依動作播動畫，single 顯示單張。stage 找不到時用 adult。
static func setup_animal(icon: AnimatedIcon, animal_id: String, life_stage: String, action: String = "idle") -> bool:
	var table: Dictionary = _cfg().get("animals", {}).get(animal_id, {})
	var entry: Dictionary = table.get(life_stage, table.get("adult", {}))
	if entry.has("sheet"):
		var tex := texture(str(entry["sheet"]))
		if tex == null:
			return false
		var rows: Dictionary = entry.get("rows", {})
		icon.setup(tex, frame_size(), int(rows.get(action, rows.get("idle", 0))), 4, 6.0)
		return true
	if entry.has("single"):
		var single := texture(str(entry["single"]))
		if single == null:
			return false
		icon.show_static(single)
		return true
	return false

# 主角灰狼：idle／walk／howl／down 是 spritesheet 的列。
static func setup_wolf(icon: AnimatedIcon, action: String = "idle", fps: float = 5.0) -> bool:
	var wolf: Dictionary = _cfg().get("wolf", {})
	var tex := texture(str(wolf.get("sheet", "")))
	if tex == null:
		return false
	icon.setup(tex, frame_size(), int(wolf.get("rows", {}).get(action, 0)), 4, fps)
	return true

# 灰狼的單張姿勢：stalk／pounce／eat／sleep。
static func wolf_pose(pose: String) -> Texture2D:
	return texture(str(_cfg().get("wolf", {}).get("poses", {}).get(pose, "")))

static func region_background(region_id: String, season: String) -> Texture2D:
	var table: Dictionary = _cfg().get("region_backgrounds", {})
	return texture(str(table.get(region_id + "@" + season, table.get(region_id, ""))))

static func terrain_background(terrain: String) -> Texture2D:
	return texture(str(_cfg().get("terrain_backgrounds", {}).get(terrain, "")))

static func icon(key: String) -> Texture2D:
	return texture(str(_cfg().get("icons", {}).get(key, "")))

static func period_tint(period: String) -> Color:
	var c: Array = _cfg().get("period_tint", {}).get(period, [1, 1, 1])
	return Color(float(c[0]), float(c[1]), float(c[2]))
