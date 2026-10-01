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

func _ready() -> void:
	balance = _load_json("res://data/balance.json")
	animals = _load_json("res://data/animals.json")
	regions_root = _load_json("res://data/regions.json")
	discovery = _load_json("res://data/discovery.json")
	knowledge = _load_json("res://data/knowledge.json")
	events = _load_json("res://data/events.json")

func regions() -> Dictionary:
	return regions_root.get("regions", {})

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
