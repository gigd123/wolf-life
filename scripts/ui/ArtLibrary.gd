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

# --- 選單畫面的新圖（art.json 的 hd_menu，2026-11-11） ---
const SETTINGS_PATH := "user://settings.cfg"
static var _hd_on := -1 # -1 還沒讀設定

static func _hd() -> Dictionary:
	return _cfg().get("hd_menu", {})

static func hd_menu_on() -> bool:
	if _hd_on < 0:
		var cfg := ConfigFile.new()
		var v: String = str(_hd().get("default", "hd"))
		if cfg.load(SETTINGS_PATH) == OK:
			v = str(cfg.get_value("art", "menu", v))
		_hd_on = 1 if v == "hd" else 0
	return _hd_on == 1 and not _hd().is_empty()

static func set_hd_menu(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("art", "menu", "hd" if on else "old")
	cfg.save(SETTINGS_PATH)
	_hd_on = 1 if on else 0

static func _hd_tex(name: String) -> Texture2D:
	if name == "":
		return null
	return texture(str(_hd().get("dir", "")) + name + "_32.png")

const HD_SUFFIX := {"idle": [""], "move": ["_run"], "walk": [""], "attack": ["_fight", "_alert"], "threaten": ["_alert"], "hurt": ["_alert"], "eat": ["_graze"]}

# 這隻動物、這個階段、這個動作的新圖；沒有回傳 null（照舊圖）
static func hd_animal(animal_id: String, life_stage: String, action: String) -> Texture2D:
	if not hd_menu_on():
		return null
	var table: Dictionary = _hd().get("animals", {}).get(animal_id, {})
	var seasonal: String = life_stage + "@" + GameTime.current_season()
	var entry = table.get(seasonal, table.get(life_stage, null))
	if entry == null:
		return null
	if action == "":
		action = "idle"
	if entry is Dictionary:
		return _hd_tex(str(entry.get(action, entry.get("_", "") if not (action in ["herd", "distant", "pair", "circling"]) else "")))
	for suf in HD_SUFFIX.get(action, []):
		var t := _hd_tex(str(entry) + str(suf))
		if t != null:
			return t
	return null

# 兩張新圖拼成兩格的長條（移動時輪流；大小不同時補成一樣大、底部置中對齊）
static func _pair_strip(a: Texture2D, b: Texture2D) -> Texture2D:
	var key := "pair|" + a.resource_path + "|" + b.resource_path
	if _cache.has(key):
		return _cache[key]
	var ia: Image = a.get_image()
	var ib: Image = b.get_image()
	if ia == null or ib == null:
		return null
	ia.convert(Image.FORMAT_RGBA8)
	ib.convert(Image.FORMAT_RGBA8)
	var w: int = maxi(ia.get_width(), ib.get_width())
	var h: int = maxi(ia.get_height(), ib.get_height())
	var out := Image.create(w * 2, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(ia, Rect2i(Vector2i.ZERO, ia.get_size()), Vector2i((w - ia.get_width()) / 2, h - ia.get_height()))
	out.blit_rect(ib, Rect2i(Vector2i.ZERO, ib.get_size()), Vector2i(w + (w - ib.get_width()) / 2, h - ib.get_height()))
	var tex := ImageTexture.create_from_image(out)
	_cache[key] = tex
	return tex

# 有第二張走路圖（hd_menu.walk_b）就播兩格，回傳 true；沒有回傳 false
static func _hd_walk(icon: AnimatedIcon, first: Texture2D, who: String) -> bool:
	var wb: Dictionary = _hd().get("walk_b", {})
	var second := _hd_tex(str(wb.get(who, "")))
	if first == null or second == null:
		return false
	var strip := _pair_strip(first, second)
	if strip == null:
		return false
	icon.setup(strip, Vector2i(strip.get_width() / 2, strip.get_height()), 0, 2, float(wb.get("fps", 3.0)))
	return true

static func hd_wolf(pose: String) -> Texture2D:
	if not hd_menu_on():
		return null
	return _hd_tex(str(_hd().get("wolf", {}).get(pose, "")))

static func frame_size() -> Vector2i:
	var fs: Array = _cfg().get("frame_size", [48, 32])
	return Vector2i(int(fs[0]), int(fs[1]))

# 動物：sheet 依動作播動畫，single 顯示單張。stage 找不到時用 adult。
# animate = false：回合之間的靜止畫面，略過只播一次的多格動畫（loop false），用單張姿勢或 spritesheet。
static func setup_animal(icon: AnimatedIcon, animal_id: String, life_stage: String, action: String = "idle", animate: bool = true) -> bool:
	var hd := hd_animal(animal_id, life_stage, action)
	if hd != null:
		if not (animate and action in ["move", "walk"] and life_stage == "adult" and _hd_walk(icon, hd, animal_id)):
			icon.show_static(hd)
		return true
	var table: Dictionary = _cfg().get("animals", {}).get(animal_id, {})
	var entry: Dictionary = table.get(life_stage, table.get("adult", {}))
	# 季節外觀（例如雪兔冬季變白）：有 life_stage@season 就用那一版
	var seasonal: String = life_stage + "@" + GameTime.current_season()
	if table.has(seasonal):
		entry = table[seasonal]
	# 1.9 第 4 步：正式的多格動畫（strips 裡有這個動作）優先於單張姿勢，換圖不用改程式
	var one_shot: bool = not bool(entry.get("strips", {}).get(action, {}).get("loop", true))
	if entry.get("strips", {}).has(action) and action != "walk" and (animate or not one_shot) and _setup_strip(icon, entry["strips"][action]):
		return true
	# 單張姿勢（例如陌生灰狼的威嚇、撲咬、示弱）優先於 spritesheet 的列
	if entry.get("poses", {}).has(action):
		var pose := texture(str(entry["poses"][action]))
		if pose != null:
			icon.show_static(pose)
			return true
	# 動作的橫向長條動畫（自訂格子大小）；move 沒有對應時用 walk
	var strips: Dictionary = entry.get("strips", {})
	var strip_key: String = action if strips.has(action) and (animate or not one_shot) else ("walk" if action == "move" and strips.has("walk") else "")
	if strip_key != "" and _setup_strip(icon, strips[strip_key]):
		return true
	if entry.has("sheet"):
		var tex := texture(str(entry["sheet"]))
		if tex == null:
			return false
		var rows: Dictionary = entry.get("rows", {})
		icon.setup(tex, _entry_frame(entry), int(rows.get(action, rows.get("idle", 0))), int(entry.get("frames", 4)), 6.0)
		return true
	if entry.has("single"):
		var single := texture(str(entry["single"]))
		if single == null:
			return false
		icon.show_static(single)
		return true
	return false

static func _entry_frame(entry: Dictionary) -> Vector2i:
	if entry.has("frame"):
		return Vector2i(int(entry["frame"][0]), int(entry["frame"][1]))
	return frame_size()

static func _setup_strip(icon: AnimatedIcon, strip: Dictionary) -> bool:
	var tex := texture(str(strip.get("sheet", "")))
	if tex == null:
		return false
	icon.setup(tex, _entry_frame(strip), 0, int(strip.get("frames", 4)), float(strip.get("fps", 5.0)), bool(strip.get("loop", true)))
	return true

# 相對灰狼的顯示倍率（art.json 動物的 display_scale；沒寫的幼獸用成體 × 0.7，其他階段例如雄鹿用成體）。狩獵與戰鬥畫面照比例顯示用。
static func display_scale(animal_id: String, life_stage: String) -> float:
	# 新圖彼此的比例已經對了（一格 32 像素）
	if hd_animal(animal_id, life_stage, "idle") != null:
		return 1.0
	var table: Dictionary = _cfg().get("animals", {}).get(animal_id, {})
	var ds: Dictionary = table.get("display_scale", {})
	if ds.has(life_stage):
		return float(ds[life_stage])
	var adult: float = float(ds.get("adult", 1.0))
	return adult * 0.7 if life_stage == "juvenile" else adult

# 動物待機時一格的大小（spritesheet 的格子，或單張圖的大小）；決定狩獵畫面要留多大的位置。
static func idle_frame_size(animal_id: String, life_stage: String) -> Vector2:
	var hd := hd_animal(animal_id, life_stage, "idle")
	if hd != null:
		return hd.get_size()
	var table: Dictionary = _cfg().get("animals", {}).get(animal_id, {})
	var entry: Dictionary = table.get(life_stage, table.get("adult", {}))
	if entry.has("sheet"):
		return Vector2(_entry_frame(entry))
	var single := texture(str(entry.get("single", "")))
	return single.get_size() if single != null else Vector2(frame_size())

# 事件圖（art.json 的 events）；沒有對應的圖回傳 null。
static func event_image(key: String) -> Texture2D:
	return texture(str(_cfg().get("events", {}).get(key, "")))

# 主角灰狼：idle／walk／howl／down 是 spritesheet 的列。stage：""（次成年）、"adult"、"elder"。
static func setup_wolf(icon: AnimatedIcon, action: String = "idle", fps: float = 5.0, stage: String = "") -> bool:
	var hw := hd_wolf(action)
	if hw != null:
		if not (action == "walk" and _hd_walk(icon, hw, "wolf")):
			icon.show_static(hw)
		return true
	var wolf: Dictionary = _cfg().get("wolf", {})
	var tex := texture(str(_wolf_stage(stage).get("sheet", "")))
	if tex == null:
		tex = texture(str(wolf.get("sheet", "")))
	if tex == null:
		return false
	icon.setup(tex, frame_size(), int(wolf.get("rows", {}).get(action, 0)), 4, fps)
	return true

# 灰狼的單張姿勢：stalk／pounce／eat／sleep。
# 灰狼姿勢的多格動畫（1.9 第 4 步）：art.json 的 wolf.stages.<階段>.strips 或 wolf.strips 有這個姿勢就用，沒有回傳 false
static func setup_wolf_strip(icon: AnimatedIcon, pose: String, stage: String = "") -> bool:
	# 新圖是單張：有新圖的姿勢不播舊的多格動畫（交給 wolf_pose）
	if hd_wolf(pose) != null:
		return false
	var strips: Dictionary = _wolf_stage(stage).get("strips", {})
	if not strips.has(pose):
		strips = _cfg().get("wolf", {}).get("strips", {})
	if not strips.has(pose):
		return false
	return _setup_strip(icon, strips[pose])

static func wolf_pose(pose: String, stage: String = "") -> Texture2D:
	var hw := hd_wolf(pose)
	if hw != null:
		return hw
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
# burned：區域剛燒過（燃燒中或焦黑期），有「地形@burned」的圖就用（QA-72），沒有就用一般的。
static func terrain_background(terrain: String, season: String = "", burned: bool = false) -> Texture2D:
	var table: Dictionary = _cfg().get("terrain_backgrounds", {})
	if burned:
		var tex := texture(str(table.get(terrain + "@burned", "")))
		if tex != null:
			return tex
	return texture(str(table.get(terrain + "@" + season, table.get(terrain, ""))))

# 屍體（art.json 的 carcasses）；沒有對應的圖回傳 null。
static func carcass(animal_id: String) -> Texture2D:
	return texture(str(_cfg().get("carcasses", {}).get(animal_id, "")))

static func icon(key: String) -> Texture2D:
	return texture(str(_cfg().get("icons", {}).get(key, "")))

# 牧場（Phase 4a 第 6 步，art.json ranch）：group 是 clues／signs／watch／encounters，key 是種類。
# 值 "event:xxx" 用 events 的圖、"file:xxx" 用 assets/art/icons/xxx.png、"icon:xxx" 用 icons 的鍵（encounters 的值直接是 events 的鍵）。
static func ranch_image(group: String, key: String) -> Texture2D:
	var v: String = str(_cfg().get("ranch", {}).get(group, {}).get(key, ""))
	if v == "":
		return null
	if group == "encounters":
		return event_image(v)
	if v.begins_with("event:"):
		return event_image(v.substr(6))
	if v.begins_with("file:"):
		return texture("res://assets/art/icons/%s.png" % v.substr(5))
	return icon(v.trim_prefix("icon:"))

# 圖示的路徑（給 RichTextLabel 的 [img] 用）；檔案不存在時回傳空字串。
static func icon_path(key: String) -> String:
	var path: String = str(_cfg().get("icons", {}).get(key, ""))
	return path if path != "" and ResourceLoader.exists(path) else ""

static func season_background(season: String) -> Texture2D:
	return texture(str(_cfg().get("season_backgrounds", {}).get(season, "")))

static func period_tint(period: String) -> Color:
	var c: Array = _cfg().get("period_tint", {}).get(period, [1, 1, 1])
	return Color(float(c[0]), float(c[1]), float(c[2]))
