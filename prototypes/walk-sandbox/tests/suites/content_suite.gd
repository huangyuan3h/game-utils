extends "res://tests/support/test_suite_base.gd"
## Content tables under data/content/ and their localization keys.


func run_all() -> void:
	_test_content_tables()
	_test_content_localization()


func _test_content_tables() -> void:
	GameContent.reload()
	var db := GameContent.database()
	_assert(db.table_names() == ["dialogue", "items", "quests", "resources"], "Content tables load from data/content")
	_assert(db.total_rows() == 10, "Content database indexes every authored row")

	var quests := GameContent.quests()
	_assert(quests.size() == 2, "Quest table yields both quests")
	var quest_ids: Array[String] = []
	for quest_def in quests:
		quest_ids.append(String(quest_def.id))
	_assert(quest_ids == ["activate_beacons", "gather_wood"], "Quest ids come from the table in order")
	_assert(quests[0].auto_start, "activate_beacons starts automatically from data")
	_assert(quests[1].objectives.size() == 1 and int(quests[1].objectives[0].get("target", 0)) == 1, "Nested quest objectives survive JSON loading")

	var elder := GameContent.dialogue(&"elder_intro")
	_assert(elder != null and elder.is_valid(), "Elder dialogue loads and validates")
	_assert(elder.get_node(&"greet").get("choices") is Array, "Dialogue choices load from data")
	_assert(str(elder.get_node(&"greet").get("text", "")) == "The beacon ward needs timber.", "Dialogue text loads as an authored string")

	var specs := GameContent.resource_specs()
	_assert(specs.size() == 4, "Resource table yields four nodes")
	_assert(specs[0]["offset"] is Vector2 and specs[0]["color"] is Color, "Resource vectors and colors convert from JSON")
	_assert((specs[0]["yields"] as Array).size() == 1, "Resource yields load from data")

	var items := GameContent.items()
	_assert(items.size() == 3 and items[0].id == &"wood", "Item table yields typed ItemDefs")
	_assert(items[2].max_stack == 999, "Item stack limits load from data")

	_assert(GameContent.quest(&"missing_id") == null, "Unknown quest ids return null")
	_assert(GameContent.dialogue(&"missing_id") == null, "Unknown dialogue ids return null")


func _test_content_localization() -> void:
	var catalog := TranslationCatalogScript.new()
	var err := catalog.load_dir("res://data")
	_assert(err == OK, "Localization catalog loads for content keys")
	if err == OK:
		_assert(catalog.message("zh", "The beacon ward needs timber.") == "信标的结界需要木料。", "Dialogue text has a zh translation")
		_assert(catalog.message("zh", "Timber for the Ward") == "为结界筹备木料", "Quest title has a zh translation")
		_assert(catalog.message("zh", "Deliver 3 wood") == "交付 3 份木材", "Quest objective has a zh translation")
		_assert(catalog.message("zh", "Speak with Elder") == "与长老交谈", "Interaction prompt has a zh translation")
		var missing: Array[String] = []
		for text in _content_texts():
			if catalog.message("zh", text) == "":
				missing.append(text)
		_assert(missing.is_empty(), "Every content text has a zh translation (missing: %s)" % ", ".join(missing))
	catalog.unload()


func _content_texts() -> Array[String]:
	## Every display string stored in quest and dialogue rows, deduplicated.
	var seen: Dictionary = {}
	for row in GameContent.database().rows("quests"):
		_add_text(seen, row.get("title", ""))
		_add_text(seen, row.get("description", ""))
		for obj in row.get("objectives", []) as Array:
			if obj is Dictionary:
				_add_text(seen, (obj as Dictionary).get("description", ""))
	for row in GameContent.database().rows("dialogue"):
		for node in row.get("nodes", []) as Array:
			if not (node is Dictionary):
				continue
			var nd := node as Dictionary
			_add_text(seen, nd.get("speaker", ""))
			_add_text(seen, nd.get("text", ""))
			for choice in nd.get("choices", []) as Array:
				if choice is Dictionary:
					_add_text(seen, (choice as Dictionary).get("text", ""))
	var out: Array[String] = []
	for key in seen:
		out.append(str(key))
	out.sort()
	return out


func _add_text(seen: Dictionary, raw: Variant) -> void:
	var text := str(raw).strip_edges()
	if text != "":
		seen[text] = true
