extends Node

# Loads every data-driven table once at boot. Nothing here knows about UI or
# about specific animals/regions by name beyond the JSON keys themselves, so
# Phase 2+ content is just more JSON, not new code.

var balance: Dictionary = {}
var animals: Dictionary = {}
var regions_root: Dictionary = {}
var discovery: Dictionary = {}
var knowledge: Dictionary = {}
var events: Dictionary = {}
var tendency: Dictionary = {}
var art: Dictionary = {}
var notices: Dictionary = {}
var ranch_def: Dictionary = {} # Phase 4a 牧場（data/ranch.json）；開放時才把地圖、區域、連接加進世界（set_ranch）
var ranch_links: Array = [] # 牧場開放時的跨地圖連接（同 regions.json links 的格式）

func _ready() -> void:
	balance = _load_json("res://data/balance.json")
	animals = _load_json("res://data/animals.json")
	regions_root = _load_json("res://data/regions.json")
	# maps 裡的 _xxx_comment 是說明文字，不是地圖；拿掉以免逐一走訪地圖時讀到字串。
	var map_table: Dictionary = regions_root.get("maps", {})
	for key in map_table.keys():
		if not map_table[key] is Dictionary:
			map_table.erase(key)
	discovery = _load_json("res://data/discovery.json")
	knowledge = _load_json("res://data/knowledge.json")
	events = _load_json("res://data/events.json")
	tendency = _load_json("res://data/tendency.json")
	art = _load_json("res://data/art.json")
	notices = _load_json("res://data/notices.json")
	ranch_def = _load_json("res://data/ranch.json")

func regions() -> Dictionary:
	return regions_root.get("regions", {})

# 大地圖（森林、苔原…）：{map_id: {name_key, layout, fire, cold}}。
func maps() -> Dictionary:
	return regions_root.get("maps", {})

func map_of(region_id: String) -> String:
	return str(regions().get(region_id, {}).get("map", regions_root.get("start_map", "forest")))

func map_regions(map_id: String) -> Array:
	return maps().get(map_id, {}).get("layout", [])

# 從某個區域出發的跨地圖連接（雙向）：[{to, turns, stamina}]。
func links_from(region_id: String) -> Array:
	var list: Array = []
	for link in regions_root.get("links", []) + ranch_links:
		if str(link["from"]) == region_id:
			list.append({"to": str(link["to"]), "turns": int(link.get("turns", 3)), "stamina": float(link.get("stamina", 0))})
		elif str(link["to"]) == region_id:
			list.append({"to": str(link["from"]), "turns": int(link.get("turns", 3)), "stamina": float(link.get("stamina", 0))})
	return list

# 牧場（Phase 4a）：candidate 是開放的候選位置（"" 表示沒有牧場）。沒有牧場時世界裡完全沒有牧場的地圖、區域、連接；
# 開放時加進 maps、regions，牧場邊緣連到候選的兩個區域。新局、讀檔、開放時呼叫。
func set_ranch(candidate: String) -> void:
	var map_table: Dictionary = maps()
	var region_table: Dictionary = regions()
	for map_id in ranch_def.get("map", {}).keys():
		map_table.erase(map_id)
	for region_id in ranch_def.get("regions", {}).keys():
		region_table.erase(region_id)
	ranch_links = []
	var c: Dictionary = ranch_def.get("candidates", {}).get(candidate, {})
	if c.is_empty():
		return
	for map_id in ranch_def.get("map", {}).keys():
		map_table[map_id] = (ranch_def["map"][map_id] as Dictionary).duplicate(true)
	for region_id in ranch_def.get("regions", {}).keys():
		region_table[region_id] = (ranch_def["regions"][region_id] as Dictionary).duplicate(true)
	for l in c.get("links", []):
		ranch_links.append({"from": str(ranch_def.get("link_region", "ranch_edge")), "to": str(l["region"]), "turns": int(l.get("turns", 2)), "stamina": float(l.get("stamina", 6))})

func ranch_open() -> bool:
	return not ranch_links.is_empty()

func region_features() -> Dictionary:
	return regions_root.get("features", {})

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	var result: Variant = JSON.parse_string(text)
	if typeof(result) != TYPE_DICTIONARY:
		push_error("Invalid JSON in: %s" % path)
		return {}
	return result
