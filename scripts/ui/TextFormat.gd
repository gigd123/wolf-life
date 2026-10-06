class_name TextFormat
extends RefCounted

# 畫面層共用的文字組合（主畫面與一生回顧都會用到）。只讀 GameState，不改任何狀態。

static func t(key: String) -> String:
	return TranslationServer.translate(key)

# 已辨識才顯示真正的名字，否則是「未知的大型掠食者」之類的描述。
static func source_name(source: String) -> String:
	return t("animal." + source) if GameState.is_identified(source) else t("animal_unknown." + source)

static func prey_name(animal_id: String, life_stage: String) -> String:
	var key: String = "prey_name.%s.%s" % [animal_id, life_stage]
	if t(key) != key:
		return t(key)
	if life_stage == "juvenile":
		return t("explore.juvenile") + t("animal." + animal_id)
	return t("animal." + animal_id)

# 傷從哪裡來：有專屬文字就用（「和灰熊搶食」），否則「獵駝鹿」「和狼獾衝突」。
static func injury_source(source: String) -> String:
	var key: String = "injury_source." + source
	if t(key) != key:
		return t(key)
	var parts: PackedStringArray = source.split(".")
	if parts.size() == 2:
		var animal: String = source_name(parts[0])
		return t("injury_source.generic.hunt" if parts[1] == "hunt" else "injury_source.generic.conflict").replace("{animal}", animal)
	return t("injury_source.hunt")

static func knowledge_text(entry: Dictionary) -> String:
	var level: String = t("knowledge.level.%d" % GameState.knowledge_level(entry))
	# 狼嚎的知識本身就分三句寫出把握程度，不再加【似乎】（免得「【似乎】似乎有其他狼」）
	if entry["type"] == "territory":
		level = ""
	var text: String = t("knowledge." + str(entry["type"]))
	if entry["type"] == "territory":
		# 狼嚎的知識逐步成形：似乎有其他狼 → 常從某處傳來 → 這一帶是其他狼的範圍
		text = t("knowledge.territory.%d" % GameState.knowledge_level(entry))
	text = text.replace("{animal}", source_name(str(entry.get("animal", ""))))
	text = text.replace("{region}", t("region." + str(entry.get("region", ""))))
	text = text.replace("{period}", t("period." + str(entry.get("period", ""))))
	text = text.replace("{season}", t("season." + str(entry.get("season", ""))))
	text = text.replace("{prey}", prey_name(str(entry.get("animal", "")), str(entry.get("life_stage", "adult"))))
	text = text.replace("{option}", t("knowledge.option." + str(entry.get("option", ""))))
	return level + text
