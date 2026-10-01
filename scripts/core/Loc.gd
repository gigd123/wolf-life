extends Node

func _ready() -> void:
	_load_csv("res://localization/strings_zh_TW.csv")

func _load_csv(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("Missing localization file: %s" % path)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var header: PackedStringArray = file.get_csv_line()
	if header.size() < 2:
		push_error("Malformed localization header in: %s" % path)
		return
	var locale: String = header[1]
	var translation := Translation.new()
	translation.locale = locale
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() < 2 or row[0] == "":
			continue
		translation.add_message(row[0], row[1])
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale(locale)
