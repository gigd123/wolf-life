extends SceneTree
# 文字檢查（文案一致性 A）的回歸測試：主畫面掃描、紀錄（含自動遊玩時）都抓得到原始翻譯鍵與沒替換的佔位，
# 記進試玩紀錄、同一個片段只記一次；正常的文字（含檔名、數字）不誤報。
# 用法：bash tools/run_sim.sh text_watch
var f := 0
var fails := 0

func _process(_d) -> bool:
	f += 1
	if f == 3:
		var gs = root.get_node("GameState")
		gs.new_game("forest_east")
		change_scene_to_file("res://scenes/Game.tscn")
	if f != 12:
		return f > 16
	var gs = root.get_node("GameState")
	var game = current_scene
	_check(game.text_watch.enabled, "讀得到翻譯表")
	game.text_watch.scan(game, game.debug_overlay)
	var base: int = gs.metrics().get("text_issues", {}).size()
	_check(base == 0, "一開局的主畫面沒有文字問題（實際 %d）" % base)
	# 正常文字不誤報
	game._log("你在 0.5 天內走到 res://a.png，速度 ▲0.3。")
	_check(gs.metrics().get("text_issues", {}).size() == base, "正常文字不誤報")
	# 紀錄裡的原始鍵與佔位
	game._log("challenger.not_a_key 出現在紀錄裡")
	game._log("你在{region}休息")
	game._log("challenger.not_a_key 又出現一次")
	var issues: Dictionary = gs.metrics().get("text_issues", {})
	_check(issues.has("challenger.not_a_key") and issues["challenger.not_a_key"]["kind"] == "RAWKEY", "紀錄裡的原始鍵")
	_check(issues.has("{region}") and issues["{region}"]["kind"] == "PLACEHOLDER", "紀錄裡的佔位")
	_check(issues.size() == base + 2, "同一個片段只記一次")
	# 自動遊玩時 GameState 送出的紀錄
	gs.auto_playing = true
	gs.log_message.emit("routine.missing_line 在照常過日子時")
	gs.auto_playing = false
	_check(gs.metrics()["text_issues"].has("routine.missing_line") and bool(gs.metrics()["text_issues"]["routine.missing_line"]["auto"]), "自動遊玩時的紀錄")
	# 畫面上的元件
	var lab := Label.new()
	lab.text = "season_card.fake.key"
	game.add_child(lab)
	game.text_watch.scan(game, game.debug_overlay)
	_check(gs.metrics()["text_issues"].has("season_card.fake.key"), "畫面掃描")
	print("試玩紀錄摘要：", gs.metrics_summary()["text_issues"])
	print("失敗 %d 項" % fails if fails > 0 else "全部通過")
	return true

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  ✗ " + what)
