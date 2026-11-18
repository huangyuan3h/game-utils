class_name TranslationCatalog
extends RefCounted
## Loads Godot translations from `gu data` localization CSVs (`keys,<locale>,...`).

const MANIFEST_NAME := "i18n_manifest.json"

var default_locale: String = "en"

var _locales: PackedStringArray = PackedStringArray()
var _translations: Array[Translation] = []
var _by_locale: Dictionary = {}
static var _locale_pattern: RegEx


func load_dir(dir_path: String) -> Error:
	unload()
	var err := OK
	var had_manifest := false
	var files: PackedStringArray = PackedStringArray()
	var manifest_path := dir_path.path_join(MANIFEST_NAME)
	if FileAccess.file_exists(manifest_path):
		had_manifest = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if parsed is Dictionary:
			var doc := parsed as Dictionary
			var fallback := str(doc.get("default_locale", "")).strip_edges()
			if fallback != "":
				default_locale = fallback.replace("-", "_")
			var listed: Variant = doc.get("files", [])
			if listed is Array:
				for item in listed:
					var rel := str(item).strip_edges()
					if rel != "":
						files.append(dir_path.path_join(rel))
			var listed_locales: Variant = doc.get("locales", [])
			if listed_locales is Array:
				for item in listed_locales:
					var code := str(item).strip_edges().replace("-", "_")
					if code != "" and not _locales.has(code):
						_locales.append(code)
		else:
			err = ERR_INVALID_DATA
			had_manifest = false
	if files.is_empty():
		files = _scan_csv(dir_path)
	for path in files:
		var file_err := _load_csv(path)
		if err == OK and file_err != OK:
			err = file_err
	if not had_manifest:
		_choose_default_locale()
	_add_locale_aliases()
	for tr in _translations:
		TranslationServer.add_translation(tr)
	return err


func unload() -> void:
	for tr in _translations:
		TranslationServer.remove_translation(tr)
	_translations.clear()
	_by_locale.clear()
	_locales = PackedStringArray()
	default_locale = "en"


func get_locales() -> PackedStringArray:
	return _locales.duplicate()


func message(locale: String, key: String) -> String:
	var tr: Translation = _by_locale.get(locale) as Translation
	if tr == null:
		return ""
	return String(tr.get_message(StringName(key)))


func locale_label(code: String) -> String:
	var text := message(code, "LOCALE_%s" % code)
	if text == "":
		return code
	return text


## Godot may rewrite "zh" to zh_CN / zh_Hans. Those aliases are not listed in the menu.
func _add_locale_aliases() -> void:
	var extras := {
		"zh": ["zh_CN", "zh_Hans", "zh_Hans_CN"],
		"en": ["en_US"],
	}
	for code in _locales.duplicate():
		var src: Translation = _by_locale.get(String(code)) as Translation
		if src == null or not extras.has(String(code)):
			continue
		for alias_v in extras[String(code)]:
			var alias := String(alias_v)
			if _by_locale.has(alias):
				continue
			var copy := Translation.new()
			copy.locale = alias
			for key in src.get_message_list():
				copy.add_message(key, src.get_message(key))
			_by_locale[alias] = copy
			_translations.append(copy)


func _choose_default_locale() -> void:
	if _locales.has("en"):
		default_locale = "en"
	elif not _locales.is_empty():
		var ordered := _locales.duplicate()
		ordered.sort()
		default_locale = String(ordered[0])


func _scan_csv(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for name in DirAccess.get_files_at(dir_path):
		var lower := String(name).to_lower()
		if not lower.ends_with(".csv"):
			continue
		var stem := lower.trim_suffix(".csv")
		if stem.ends_with("_i18n") or stem.begins_with("translations"):
			out.append(dir_path.path_join(String(name)))
	out.sort()
	return out


func _load_csv(path: String) -> Error:
	if not FileAccess.file_exists(path):
		push_warning("TranslationCatalog missing file '%s'." % path)
		return ERR_FILE_NOT_FOUND
	var text := FileAccess.get_file_as_string(path)
	var rows := parse_csv(text)
	if rows.is_empty():
		push_warning("TranslationCatalog empty CSV '%s'." % path)
		return ERR_INVALID_DATA
	var header: PackedStringArray = rows[0]
	if header.is_empty() or header[0].strip_edges() != "keys":
		push_warning("TranslationCatalog '%s' first column must be 'keys'." % path)
		return ERR_INVALID_DATA
	var columns: PackedStringArray = PackedStringArray()
	for i in range(1, header.size()):
		columns.append(_canonical_locale(header[i]))
	for r in range(1, rows.size()):
		var row: PackedStringArray = rows[r]
		if row.is_empty():
			continue
		var key := row[0].strip_edges()
		if key == "":
			continue
		for c in range(columns.size()):
			var locale := columns[c]
			if locale == "":
				continue
			var msg := row[c + 1] if c + 1 < row.size() else ""
			_translation_for(locale).add_message(key, msg)
	return OK


func _translation_for(locale: String) -> Translation:
	if _by_locale.has(locale):
		return _by_locale[locale] as Translation
	var tr := Translation.new()
	tr.locale = locale
	_by_locale[locale] = tr
	_translations.append(tr)
	if not _locales.has(locale):
		_locales.append(locale)
	return tr


func _canonical_locale(raw: String) -> String:
	var code := raw.strip_edges()
	if code == "":
		return ""
	var pattern := _locale_regex()
	if pattern.search(code) == null:
		return ""
	return code.replace("-", "_")


func _locale_regex() -> RegEx:
	return _shared_locale_regex()


static func _shared_locale_regex() -> RegEx:
	# Godot locale code: en, zh, zh_CN, pt-BR. Hyphens are stored as underscores.
	if _locale_pattern == null:
		_locale_pattern = RegEx.new()
		_locale_pattern.compile("^[A-Za-z]{2,3}([_-][A-Za-z0-9]+)*$")
	return _locale_pattern


## Parse CSV text the same way Python's csv module does, including quoted commas.
static func parse_csv(text: String) -> Array:
	var rows: Array = []
	if text.begins_with("\uFEFF"):
		text = text.substr(1)
	var row := PackedStringArray()
	var field := ""
	var in_quotes := false
	var i := 0
	var n := text.length()
	while i < n:
		var ch := text[i]
		if in_quotes:
			if ch == '"':
				if i + 1 < n and text[i + 1] == '"':
					field += '"'
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			field += ch
			i += 1
			continue
		if ch == '"':
			in_quotes = true
			i += 1
			continue
		if ch == ",":
			row.append(field)
			field = ""
			i += 1
			continue
		if ch == "\n" or ch == "\r":
			if ch == "\r" and i + 1 < n and text[i + 1] == "\n":
				i += 1
			row.append(field)
			rows.append(row.duplicate())
			row = PackedStringArray()
			field = ""
			i += 1
			continue
		field += ch
		i += 1
	if field != "" or not row.is_empty():
		row.append(field)
		rows.append(row.duplicate())
	return rows
