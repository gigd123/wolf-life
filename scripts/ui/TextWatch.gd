class_name TextWatch
extends RefCounted
# 文字檢查（文案一致性 A，2026-10-16）：遊玩時找畫面與紀錄裡的原始翻譯鍵（RAWKEY）與沒替換的 {佔位}（PLACEHOLDER）。
# 規則和 tools/ui_check.gd 相同，但在真正遊玩時執行（含照常過日子、自動遊玩時 GameState 送出的紀錄），
# 找到的問題記進試玩紀錄（GameState.metric_text_issue），同一個問題只回報一次。
# 前綴表讀自 localization 的 CSV；匯出版沒有 CSV 時不檢查。

var enabled := false
var prefixes := {}
var key_re := RegEx.new()
var ph_re := RegEx.new()
var seen := {}

func _init() -> void:
	var f := FileAccess.open("res://localization/strings_zh_TW.csv", FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() > 0 and line[0].contains("."):
			prefixes[line[0].split(".")[0]] = true
	key_re.compile("(?<![\\w/:])([a-z][a-z0-9_]*)(\\.[a-z0-9_]+)+")
	ph_re.compile("\\{[a-z_]+\\}")
	enabled = not prefixes.is_empty()

# 回傳這次新找到的問題（[種類, 片段]），已回報過的不再回傳。
func check(text: String, where: String) -> Array:
	var found: Array = []
	if not enabled or text == "":
		return found
	for m in key_re.search_all(text):
		var s := m.get_string()
		if prefixes.has(m.get_string(1)) and not s.ends_with(".png") and not s.ends_with(".json"):
			found.append(["RAWKEY", s])
	for m in ph_re.search_all(text):
		found.append(["PLACEHOLDER", m.get_string()])
	var fresh: Array = []
	for item in found:
		if seen.has(item[1]):
			continue
		seen[item[1]] = true
		fresh.append(item)
		GameState.metric_text_issue(item[0], item[1], where, text.substr(0, 80).replace("\n", " "))
		push_warning("文字問題 %s %s @ %s：%s" % [item[0], item[1], where, text.substr(0, 80)])
	return fresh

# 掃描畫面上看得到的文字元件（略過 skip 底下的節點，例如除錯選單）。
func scan(root: Node, skip: Node) -> Array:
	var fresh: Array = []
	if not enabled:
		return fresh
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or (skip != null and skip.is_ancestor_of(c)):
			continue
		var t := ""
		if c is RichTextLabel:
			t = c.get_parsed_text()
		elif c is Label or c is Button:
			t = c.text
		if c.tooltip_text != "":
			t += "\n" + c.tooltip_text
		if t != "":
			fresh.append_array(check(t, str(c.name)))
	return fresh
