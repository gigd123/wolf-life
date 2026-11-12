extends SceneTree
# Phase 2m 第 3 步的規則檢查：體型的經驗——未滿 1 歲對成年的大中型獵物有明確意義的失敗才記（壓倒失敗 2 次、被甩開、被反擊傷到 ≥ 10），
# 只是被發現跑掉、獵到、幼鹿、小獵物、1 歲以上都不記；同一種只記一次、跳學到知識；開場的文字照年齡（未滿 1 歲／1～2 歲／成年只說一次）；
# 知識頁兩行（過去的經驗＋目前的認知）、長大後經驗還在。
# 用法：bash tools/run_sim.sh size_lesson_rules
var f := 0
var fails := 0
var gs
var learned := 0
var logs: Array = []

func _ok(c: bool, msg: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", msg)

# 跑一場假的戰術結果：只設體型經驗會看的欄位
func _fake(animal: String, stage: String, result: String, takedown_fails: int, broke: int, hurt: float):
	var h = gs.start_hunt(animal, stage)
	var th = gs.start_tactical(h)
	th.result = result
	th.takedown_fails = takedown_fails
	th.stats["broke_free"] = broke
	th.damage_by["prey"] = hurt
	gs._maybe_size_lesson(th, h)

func _process(_d) -> bool:
	f += 1
	if f != 3:
		return f > 6
	gs = root.get_node("GameState")
	gs.new_game("forest_east")
	gs.knowledge_learned.connect(func(_e): learned += 1)
	gs.log_message.connect(func(m): logs.append(str(m)))
	var key: String = gs.knowledge_key({"type": "size_lesson", "animal": "white_tailed_deer"})
	_ok(gs.wolf.age_years < 1.0, "開局未滿 1 歲")
	# 不記的情況
	_fake("white_tailed_deer", "adult", "escaped", 0, 0, 0.0)
	_ok(not gs.knowledge.has(key), "只是跑掉不記")
	_fake("white_tailed_deer", "adult", "caught", 3, 0, 20.0)
	_ok(not gs.knowledge.has(key), "獵到不記")
	_fake("hare", "adult", "escaped", 3, 1, 20.0)
	_ok(not gs.knowledge.has(gs.knowledge_key({"type": "size_lesson", "animal": "hare"})), "小獵物不記")
	_fake("white_tailed_deer", "adult", "escaped", 1, 0, 9.0)
	_ok(not gs.knowledge.has(key), "壓倒失敗 1 次、傷 9 不記")
	_ok(str(gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult")).game_mods.get("size_note", "")) == "", "還沒有經驗：開場不提示")
	# 記下
	_fake("white_tailed_deer", "adult", "escaped", 2, 0, 0.0)
	_ok(gs.knowledge.has(key) and str(gs.knowledge[key].get("how", "")) == "takedown", "壓倒失敗 2 次 → 記（takedown）")
	_ok(learned >= 1 and logs.filter(func(m): return m.contains("白尾鹿比你壯太多了")).size() == 1, "跳學到知識、寫一句")
	_fake("white_tailed_deer", "adult", "escaped", 0, 1, 15.0)
	_ok(logs.filter(func(m): return m.contains("白尾鹿比你壯太多了")).size() == 1 and str(gs.knowledge[key]["how"]) == "takedown", "同一種只記一次")
	_fake("elk", "adult", "lost", 0, 1, 0.0)
	_ok(str(gs.knowledge.get(gs.knowledge_key({"type": "size_lesson", "animal": "elk"}), {}).get("how", "")) == "shaken", "被甩開 → 記（shaken）")
	_fake("moose", "adult", "escaped", 0, 0, 12.0)
	_ok(str(gs.knowledge.get(gs.knowledge_key({"type": "size_lesson", "animal": "moose"}), {}).get("how", "")) == "hurt", "被反擊傷到 12 → 記（hurt）")
	# 開場的文字照年齡
	var note: String = str(gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult")).game_mods.get("size_note", ""))
	_ok(note.contains("上次") and note.contains("還是很難"), "未滿 1 歲：記得上次（%s）" % note)
	_ok(str(gs.start_tactical(gs.start_hunt("white_tailed_deer", "juvenile")).game_mods.get("size_note", "")) == "", "盯上幼鹿不說")
	var page: String = load("res://scripts/ui/TextFormat.gd").knowledge_text(gs.knowledge[key])
	_ok(page.contains("個月大") and page.contains("還很難"), "知識頁：過去＋現在還很難（%s）" % page)
	gs.wolf.age_years = 1.5
	_fake("mule_deer", "adult", "escaped", 3, 0, 0.0)
	_ok(not gs.knowledge.has(gs.knowledge_key({"type": "size_lesson", "animal": "mule_deer"})), "1 歲以上不再記新的")
	note = str(gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult")).game_mods.get("size_note", ""))
	_ok(note.contains("小時候") and note.contains("還沒長成"), "1～2 歲（%s）" % note)
	gs.wolf.age_years = 2.5
	note = str(gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult")).game_mods.get("size_note", ""))
	_ok(note.contains("撂得倒"), "成年：撂得倒了（%s）" % note)
	_ok(str(gs.start_tactical(gs.start_hunt("white_tailed_deer", "adult")).game_mods.get("size_note", "")) == "", "成年那句只說一次")
	page = load("res://scripts/ui/TextFormat.gd").knowledge_text(gs.knowledge[key])
	_ok(page.contains("個月大") and page.contains("撂得倒了"), "長大後：經驗還在、現在撂得倒（%s）" % page)
	# 存讀檔
	var data: Dictionary = gs.to_dict() if gs.has_method("to_dict") else {}
	_ok(data.is_empty() or (data.get("knowledge", {}) as Dictionary).has(key), "存檔有這筆")
	print("體型的經驗的規則：%s" % ("全部通過" if fails == 0 else "失敗 %d 個" % fails))
	return true
