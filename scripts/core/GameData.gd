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

func _ready() -> void:
	balance = _load_json("res://data/balance.json")
	animals = _load_json("res://data/animals.json")
	regions_root = _load_json("res://data/regions.json")
	discovery = _load_json("res://data/discovery.json")
	knowledge = _load_json("res://data/knowledge.json")
	events = _load_json("res://data/events.json")
	tendency = _load_json("res://data/tendency.json")
	art = _load_json("res://data/art.json")
	notices = _load_json("res://data/notices.json")

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
	for link in regions_root.get("links", []):
		if str(link["from"]) == region_id:
			list.append({"to": str(link["to"]), "turns": int(link.get("turns", 3)), "stamina": float(link.get("stamina", 0)), "ice": link.get("ice", {})})
		elif str(link["to"]) == region_id:
			list.append({"to": str(link["from"]), "turns": int(link.get("turns", 3)), "stamina": float(link.get("stamina", 0)), "ice": link.get("ice", {})})
	return list

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
