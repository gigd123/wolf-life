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
	# 去過的大地圖（1.6 第 6 步：苔原）
	var maps_visited: Array = log_data.get("maps_visited", [])
	if maps_visited.size() > 1:
		var map_names: Array[String] = []
		for m in maps_visited:
			map_names.append(tr(str(GameData.maps().get(str(m), {}).get("name_key", ""))))
		_add_line(box, tr("summary.maps").replace("{list}", "、".join(map_names)))
	# 經歷過的森林大火（1.6 第 5 步）
	for f in log_data.get("fires", []):
		_add_line(box, _fire_line(f))
	# 和陌生灰狼的每次相遇（1.6 第 4 步）
	var meetings: Array = log_data.get("stranger_meetings", [])
	if not meetings.is_empty():
		var entries: Array[String] = []
		for m in meetings:
			entries.append(tr("summary.stranger_entry").replace("{age}", "%.1f" % float(m.get("age", 0.0))) \
				.replace("{outcome}", tr("summary.stranger_outcome." + str(m.get("outcome", "")))))
		_add_line(box, tr("summary.stranger").replace("{n}", str(meetings.size())).replace("{list}", "、".join(entries)))
	# 苔原的經歷（1.6 第 6d 步）：困在暴風雪裡、和狼獾交手、在河谷落水
	for b in log_data.get("blizzards", []):
		if bool(b.get("in_tundra", false)):
			var choice: String = str(b.get("choice", ""))
			_add_line(box, tr("summary.blizzard").replace("{age}", "%.1f" % float(b.get("age", 0.0))).replace("{days}", str(int(b.get("days", 2)))) \
				.replace("{choice}", tr("summary.blizzard.choice." + (choice if choice != "" else "none"))) \
				.replace("{result}", tr("summary.blizzard.result." + (str(b.get("result", "")) if choice != "" else "safe"))))
	var wolverine_meetings: Array = log_data.get("wolverine_meetings", [])
	if not wolverine_meetings.is_empty():
		var w_entries: Array[String] = []
		for m in wolverine_meetings:
			w_entries.append(tr("summary.stranger_entry").replace("{age}", "%.1f" % float(m.get("age", 0.0))) \
				.replace("{outcome}", tr("summary.wolverine_outcome." + str(m.get("outcome", "")))))
		var w_line: String = tr("summary.wolverine").replace("{n}", str(wolverine_meetings.size())).replace("{list}", "、".join(w_entries))
		if int(log_data.get("wolverine_gen", 1)) > 1:
			w_line += tr("summary.wolverine_gen").replace("{n}", str(int(log_data["wolverine_gen"])))
		_add_line(box, w_line)
	# 和苔原狼的相遇（1.6 第 6e 步）：嚎叫的回應不列入，只列見面的經過
	var tundra_meetings: Array = log_data.get("tundra_meetings", []).filter(func(m): return str(m.get("kind", "")) != "howl")
	if not tundra_meetings.is_empty():
		var t_entries: Array[String] = []
		for m in tundra_meetings:
			t_entries.append(tr("summary.stranger_entry").replace("{age}", "%.1f" % float(m.get("age", 0.0))) \
				.replace("{outcome}", tr("summary.tundra_outcome." + str(m.get("outcome", "")))))
		_add_line(box, tr("summary.tundra").replace("{n}", str(tundra_meetings.size())).replace("{list}", "、".join(t_entries)) \
			.replace("{relation}", tr("summary.tundra.relation." + _tundra_relation_key(int(log_data.get("tundra_relation", 0))))))
	if log_data.has("bear_first_win"):
		_add_line(box, tr("summary.bear_first_win").replace("{age}", str(log_data["bear_first_win"])))
	if int(log_data.get("fell_through_ice", 0)) > 0:
		_add_line(box, tr("summary.fell_through_ice").replace("{n}", str(int(log_data["fell_through_ice"]))))

	# 學會的知識：確定的件數，另外列出還不確定的（通常、似乎），加上幾條「確定」的內容
	var confirmed: Array = []
	var by_level: Dictionary = {1: 0, 2: 0}
	for entry in GameState.knowledge.values():
		var level: int = GameState.knowledge_level(entry)
		if level >= int(GameData.knowledge.get("confirm_count", 3)):
			confirmed.append(entry)
		elif by_level.has(level):
			by_level[level] += 1
	_add_line(box, tr("summary.knowledge").replace("{confirmed}", str(confirmed.size())) \
		.replace("{usual}", str(by_level[2])).replace("{maybe}", str(by_level[1])))
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

func _tundra_relation_key(r: int) -> String:
	var levels: Dictionary = NpcWolf.cfg("tundra_wolf").get("interaction", {}).get("relation", {}).get("levels", {})
	if r <= int(levels.get("hostile", -3)):
		return "hostile"
	if r >= int(levels.get("friendly", 6)):
		return "friendly"
	if r >= int(levels.get("familiar", 3)):
		return "familiar"
	return "wary"

func _region_names(list: Array) -> String:
	var names: Array[String] = []
	for r in list:
		names.append(tr("region." + str(r)))
	return "、".join(names)

func _fire_line(f: Dictionary) -> String:
	var escape: String = str(f.get("escape", ""))
	var result: String = str(f.get("result", "safe"))
	if escape == "":
		escape = "none"
		result = "safe"
	return tr("summary.fire").replace("{age}", "%.1f" % float(f.get("age", 0.0))) \
		.replace("{season}", tr("season." + str(f.get("season", "summer")))) \
		.replace("{origin}", tr("region." + str(f.get("origin", "")))).replace("{list}", _region_names(f.get("burned", []))) \
		.replace("{escape}", tr("summary.fire.escape." + escape).replace("{region}", tr("region." + str(f.get("escape_region", ""))))) \
		.replace("{result}", tr("summary.fire.result." + result))

# 一生中第一場大火的生平句（死在火裡時由死因那一句交代）。
func _fire_bio(f: Dictionary) -> String:
	var escape: String = str(f.get("escape", ""))
	if escape == "":
		escape = "none"
	var text: String = tr("bio.fire." + escape).replace("{age}", str(int(float(f.get("age", 0.0))))) \
		.replace("{region}", tr("region." + str(f.get("escape_region", ""))))
	if str(f.get("result", "")) in ["light", "heavy"]:
		text += tr("bio.fire.burned")
	return text

# 和那隻黑狼之間最重要的一次：咬死牠 > 趕走牠 > 向牠示弱。
func _stranger_bio(log_data: Dictionary) -> String:
	for outcome in ["killed", "drove_off", "submit"]:
		for m in log_data.get("stranger_meetings", []):
			if str(m.get("outcome", "")) == outcome:
				return tr("bio.stranger." + outcome).replace("{age}", str(int(float(m.get("age", 0.0))))) \
					.replace("{region}", tr("region." + str(m.get("region", ""))))
	return ""

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
	var fires: Array = log_data.get("fires", [])
	if not fires.is_empty():
		parts.append(_fire_bio(fires[0]))
	var stranger_line := _stranger_bio(log_data)
	if stranger_line != "":
		parts.append(stranger_line)
	var age: String = "%.1f" % (wolf.age_years if wolf != null else 0.0)
	parts.append(tr("bio.death").replace("{age}", age).replace("{cause}", _death_bio(log_data)))
	return "，".join(parts) + "。"
