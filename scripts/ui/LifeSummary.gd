extends Control

# 一生回顧（SPEC「簡易一生回顧」）：活到幾歲、死因、主要狩獵方式及其變化、野外過夜次數、
# 各獵物捕獲數與最大獵物、被搶食次數、重傷次數、學會的知識，加上一段依模板組成的生平。

const MAX_KNOWLEDGE_LINES := 3

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# 內容比 640×360 長，放在可捲動的區域
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	center.add_child(box)

	var log_data: Dictionary = GameState.life_log
	var wolf: Wolf = GameState.wolf

	var sprite_center := CenterContainer.new()
	box.add_child(sprite_center)
	var sprite := TextureRect.new()
	sprite.custom_minimum_size = Vector2(96, 64)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 灰狼 spritesheet「倒下」那一列的最後一格
	var sheet_path: String = str(GameData.art.get("wolf", {}).get("sheet", ""))
	var down_row: int = int(GameData.art.get("wolf", {}).get("rows", {}).get("down", 3))
	var sheet: Texture2D = ArtLibrary.texture(sheet_path)
	if sheet != null:
		var fs := ArtLibrary.frame_size()
		var frame_atlas := AtlasTexture.new()
		frame_atlas.atlas = sheet
		frame_atlas.region = Rect2(fs.x * 3, fs.y * down_row, fs.x, fs.y)
		sprite.texture = frame_atlas
	else:
		sprite.texture = PixelArt.make_animal_sprite("gray_wolf")
	sprite.modulate = Color(0.8, 0.8, 0.8, 0.9)
	sprite_center.add_child(sprite)

	var title := Label.new()
	title.text = tr("summary.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	var bio := Label.new()
	bio.text = _biography(log_data, wolf)
	bio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.modulate = Color(0.95, 0.9, 0.75)
	box.add_child(bio)

	_add_line(box, tr("summary.days_lived").replace("{days}", str(int(log_data.get("days_lived", 0)))))
	if wolf != null:
		_add_line(box, tr("summary.age").replace("{age}", "%.1f" % wolf.age_years))
	_add_line(box, tr("summary.death_cause").replace("{cause}", tr("death." + str(log_data.get("death_cause", "unknown")))))

	var history: Array = log_data.get("tendency_history", [])
	if not history.is_empty():
		var parts: Array[String] = []
		for h in history:
			parts.append(tr("tendency." + str(h["type"])) + tr("summary.at_age").replace("{age}", "%.1f" % float(h["age"])))
		_add_line(box, tr("summary.tendency").replace("{list}", " → ".join(parts)))
	# 成年時的身體與巔峰上限（1.6 第 2 步）
	var potential: Dictionary = log_data.get("potential", {})
	if not potential.is_empty():
		if str(log_data.get("adult_body", "")) != "":
			_add_line(box, tr("summary.adult_body").replace("{text}", tr(str(log_data["adult_body"]))))
		var caps: Array[String] = []
		for stat in Growth.ALL_STATS:
			caps.append(tr("stat." + stat) + " " + str(int(round(float(potential.get(stat, 0.0))))))
		_add_line(box, tr("summary.potential").replace("{list}", "　".join(caps)))

	var regions_visited: Array = log_data.get("regions_visited", [])
	_add_line(box, tr("summary.regions_visited").replace("{count}", str(regions_visited.size())))
	_add_line(box, tr("summary.wild_nights").replace("{count}", str(int(log_data.get("wild_nights", 0)))))

	var prey_count: Dictionary = log_data.get("prey_count", {})
	var total_prey := 0
	var prey_parts: Array[String] = []
	for animal_id in prey_count.keys():
		total_prey += int(prey_count[animal_id])
		prey_parts.append(tr("animal." + str(animal_id)) + " " + str(prey_count[animal_id]))
	var prey_line: String = tr("summary.prey_total").replace("{count}", str(total_prey))
	if not prey_parts.is_empty():
		prey_line += "（" + "、".join(prey_parts) + "）"
	_add_line(box, prey_line)

	var biggest: String = str(log_data.get("biggest_prey", ""))
	if biggest != "":
		_add_line(box, tr("summary.biggest_prey").replace("{animal}", TextFormat.prey_name(biggest, str(log_data.get("biggest_prey_stage", "adult")))))
	_add_line(box, tr("summary.scavenged").replace("{count}", str(int(log_data.get("scavenged", 0)))))
	if wolf != null:
		_add_line(box, tr("summary.heavy_injuries").replace("{count}", str(wolf.heavy_injury_count)))
		for record in wolf.old_injuries:
			_add_line(box, _old_injury_line(record))

	# 學會的知識：總數，加上幾條「確定」的內容
	var confirmed: Array = []
	for entry in GameState.knowledge.values():
		if GameState.knowledge_level(entry) >= int(GameData.knowledge.get("confirm_count", 3)):
			confirmed.append(entry)
	_add_line(box, tr("summary.knowledge").replace("{count}", str(GameState.knowledge.size())).replace("{confirmed}", str(confirmed.size())))
	for i in min(MAX_KNOWLEDGE_LINES, confirmed.size()):
		_add_line(box, "　" + TextFormat.knowledge_text(confirmed[i]))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)

	var restart_btn := Button.new()
	restart_btn.text = tr("summary.new_life")
	restart_btn.pressed.connect(func():
		SaveSystem.delete_save()
		get_tree().change_scene_to_file("res://scenes/DenSelect.tscn")
	)
	box.add_child(restart_btn)

	var menu_btn := Button.new()
	menu_btn.text = tr("menu.main_menu")
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	box.add_child(menu_btn)

func _add_line(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)

# 死因的敘述；戰死時依對手與情境（例如「為了守住獵物，死在灰熊掌下」）。
func _death_bio(log_data: Dictionary) -> String:
	var cause: String = str(log_data.get("death_cause", "unknown"))
	if cause == "combat":
		var d: Dictionary = log_data.get("death_detail", {})
		var key: String = "death_bio.combat.%s.%s" % [d.get("animal", ""), d.get("context", "")]
		if tr(key) != key:
			return tr(key)
	return tr("death_bio." + cause)

# 舊傷：部位、年齡、來源（例如「左後腿的舊傷，是 2.3 歲那年和灰熊搶食時留下的」）。
func _old_injury_line(record: Dictionary) -> String:
	var source: String = str(record.get("source", ""))
	var key: String = "injury_source." + source
	if tr(key) == key:
		key = "injury_source.hunt"
	return tr("summary.old_injury").replace("{part}", tr(str(record.get("part_key", "")))) \
		.replace("{age}", "%.1f" % float(record.get("age", 0.0))).replace("{source}", tr(key))

# 依模板組成的生平：年輕時的經歷 → 狩獵方式（與變化）→ 死亡。
func _biography(log_data: Dictionary, wolf: Wolf) -> String:
	var parts: Array[String] = []
	var days: int = int(log_data.get("days_lived", 1))
	if int(log_data.get("scavenged_by_bear", 0)) >= 2:
		parts.append(tr("bio.early.scavenged"))
	elif wolf != null and wolf.heavy_injury_count >= 1:
		parts.append(tr("bio.early.injured"))
	elif str(log_data.get("biggest_prey_stage", "")) == "buck":
		parts.append(tr("bio.early.buck"))
	elif int(log_data.get("wild_nights", 0)) * 2 >= days:
		parts.append(tr("bio.early.wanderer"))
	var history: Array = log_data.get("tendency_history", [])
	if history.size() >= 2:
		parts.append(tr("bio.became").replace("{desc}", tr("tendency_desc." + str(history[-1]["type"]))))
	elif history.size() == 1:
		parts.append(tr("bio.was").replace("{desc}", tr("tendency_desc." + str(history[0]["type"]))))
	var age: String = "%.1f" % (wolf.age_years if wolf != null else 0.0)
	parts.append(tr("bio.death").replace("{age}", age).replace("{cause}", _death_bio(log_data)))
	return "，".join(parts) + "。"
