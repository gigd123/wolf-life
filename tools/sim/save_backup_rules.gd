extends SceneTree
# 存檔的保護（2026-11-24）：腳本跑的測試不碰 save.json；存檔前留下上一份 .bak；save.json 壞掉時讀上一份。
# 用法：bash tools/run_sim.sh save_backup_rules
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("  ✗ " + msg)

func _run() -> void:
	await process_frame
	var ss = root.get_node("SaveSystem")
	var gs = root.get_node("GameState")
	var real_before: String = FileAccess.get_md5("user://save.json") if FileAccess.file_exists("user://save.json") else ""
	_ok(ss.save_path == "user://save_test.json" and not ss.keep_backup, "腳本跑的測試用 save_test.json（%s）" % ss.save_path)
	gs.new_game("forest_east")
	_ok(FileAccess.file_exists("user://save_test.json"), "開新局寫在 save_test.json")
	_ok((FileAccess.get_md5("user://save.json") if FileAccess.file_exists("user://save.json") else "") == real_before, "開新局沒有碰 save.json")
	# 備份：用另一個檔名試
	ss.save_path = "user://save_backup_rules.json"
	ss.keep_backup = true
	gs.wolf.hunger = 50.0
	ss.save_game()
	_ok(not FileAccess.file_exists(ss.backup_path()), "第一次存檔沒有上一份")
	gs.wolf.hunger = 33.0
	ss.save_game()
	_ok(FileAccess.file_exists(ss.backup_path()), "第二次存檔留下上一份")
	_ok(ss.load_game() and is_equal_approx(gs.wolf.hunger, 33.0), "平常讀最新的一份（%s）" % gs.wolf.hunger)
	var f := FileAccess.open(ss.save_path, FileAccess.WRITE)
	f.store_string("{\"wolf\": {")
	f.close()
	_ok(ss.load_game() and is_equal_approx(gs.wolf.hunger, 50.0), "壞掉時讀上一份（%s）" % gs.wolf.hunger)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ss.backup_path()))
	_ok(not ss.load_game(), "兩份都不能用：讀檔失敗")
	ss.delete_save()
	_ok(not ss.has_save(), "刪除存檔")
	print("存檔的保護：%s（%s）" % ["全部通過" if fails == 0 else "失敗 %d 項" % fails, OS.get_user_data_dir()])
	quit()
