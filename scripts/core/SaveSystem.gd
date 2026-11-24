extends Node

# Single save slot, JSON at user://save.json, per DESIGN.md "存檔" rules.
# 存檔前把上一份複製成 save.json.bak；save.json 壞掉（不是完整的 JSON）時讀上一份。
# 用腳本跑的測試（godot -s …，模擬、規則測試、截圖）改用 save_test.json，不碰玩家的存檔（2026-11-24 被規則測試蓋掉過）。

const SAVE_PATH := "user://save.json"
const TEST_SAVE_PATH := "user://save_test.json"

var save_path: String = SAVE_PATH
var keep_backup: bool = true

func _ready() -> void:
	if get_tree().get_script() != null:
		save_path = TEST_SAVE_PATH
		keep_backup = false

func backup_path() -> String:
	return save_path + ".bak"

func has_save() -> bool:
	return FileAccess.file_exists(save_path)

func save_game() -> void:
	var data := GameState.to_dict()
	if keep_backup and has_save():
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup_path()))
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func load_game() -> bool:
	if not has_save():
		return false
	var result: Variant = _read(save_path)
	if typeof(result) != TYPE_DICTIONARY:
		result = _read(backup_path())
	if typeof(result) != TYPE_DICTIONARY:
		return false
	GameState.load_from_dict(result)
	return true

func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
