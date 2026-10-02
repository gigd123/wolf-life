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
	# 單張姿勢（例如陌生灰狼的威嚇、撲咬、示弱）優先於 spritesheet 的列
	if entry.get("poses", {}).has(action):
		var pose := texture(str(entry["poses"][action]))
		if pose != null:
			icon.show_static(pose)
			return true
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

# 主角灰狼：idle／walk／howl／down 是 spritesheet 的列。stage：""（次成年）、"adult"、"elder"。
static func setup_wolf(icon: AnimatedIcon, action: String = "idle", fps: float = 5.0, stage: String = "") -> bool:
	var wolf: Dictionary = _cfg().get("wolf", {})
	var tex := texture(str(_wolf_stage(stage).get("sheet", "")))
	if tex == null:
		tex = texture(str(wolf.get("sheet", "")))
	if tex == null:
		return false
	icon.setup(tex, frame_size(), int(wolf.get("rows", {}).get(action, 0)), 4, fps)
	return true

# 灰狼的單張姿勢：stalk／pounce／eat／sleep。
static func wolf_pose(pose: String, stage: String = "") -> Texture2D:
	var tex := texture(str(_wolf_stage(stage).get("poses", {}).get(pose, "")))
	if tex != null:
		return tex
	return texture(str(_cfg().get("wolf", {}).get("poses", {}).get(pose, "")))

static func _wolf_stage(stage: String) -> Dictionary:
	return _cfg().get("wolf", {}).get("stages", {}).get(stage, {})

static func region_background(region_id: String, season: String) -> Texture2D:
	var table: Dictionary = _cfg().get("region_backgrounds", {})
	return texture(str(table.get(region_id + "@" + season, table.get(region_id, ""))))

# 地形背景；有 terrain@season（例如苔原的冬季版）就用季節版。
static func terrain_background(terrain: String, season: String = "") -> Texture2D:
	var table: Dictionary = _cfg().get("terrain_backgrounds", {})
	return texture(str(table.get(terrain + "@" + season, table.get(terrain, ""))))

static func icon(key: String) -> Texture2D:
	return texture(str(_cfg().get("icons", {}).get(key, "")))

# 圖示的路徑（給 RichTextLabel 的 [img] 用）；檔案不存在時回傳空字串。
static func icon_path(key: String) -> String:
	var path: String = str(_cfg().get("icons", {}).get(key, ""))
	return path if path != "" and ResourceLoader.exists(path) else ""

static func season_background(season: String) -> Texture2D:
	return texture(str(_cfg().get("season_backgrounds", {}).get(season, "")))

static func period_tint(period: String) -> Color:
	var c: Array = _cfg().get("period_tint", {}).get(period, [1, 1, 1])
	return Color(float(c[0]), float(c[1]), float(c[2]))
