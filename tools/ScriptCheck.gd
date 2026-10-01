extends Node
## 由 tools/godot_check.sh 以 headless 模式執行。
## 在 autoload 都已載入的情況下逐一載入所有 GDScript，編譯錯誤會印成 SCRIPT ERROR。

func _ready() -> void:
	var failed := 0
	var paths := _collect("res://")
	for path in paths:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			print("SCRIPT_CHECK_FAIL ", path)
			failed += 1
	print("SCRIPT_CHECK_DONE %d scripts, %d failed" % [paths.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)

func _collect(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir_path):
		if sub.begins_with("."):
			continue
		out.append_array(_collect(dir_path.path_join(sub)))
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension() == "gd":
			out.append(dir_path.path_join(file))
	return out
