extends Node
## Persistent user preferences backed by ConfigFile (audio, display, locale, controls, debug).

signal setting_changed(key: String, value: Variant)
signal settings_loaded

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "preferences"
const TranslationCatalogScript := preload("res://addons/gu_core/i18n/translation_catalog.gd")
const FontFallbackScript := preload("res://addons/gu_core/i18n/font_fallback.gd")

const DEFAULTS := {
	"master_volume": 1.0,
	"bgm_volume": 0.75,
	"sfx_volume": 0.90,
	"ambience_volume": 0.85,
	"ui_volume": 0.90,
	"camera_zoom_sensitivity": 1.0,
	"camera_look_sensitivity": 1.0,
	"fullscreen": false,
	"show_debug_hud": true,
	"locale": "en",
	"input_bindings": {},
}

var config_path: String = DEFAULT_PATH
var translation_dir: String = "res://data"
var _values: Dictionary = DEFAULTS.duplicate(true)
var _catalog: TranslationCatalog
var _locale_pattern: RegEx


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	load_translations()


func _exit_tree() -> void:
	clear_translations()


func load_settings(path_override: String = "") -> Error:
	var target := path_override if path_override != "" else config_path
	_values = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	var err := cfg.load(target)
	if err == OK:
		for key: String in DEFAULTS:
			if cfg.has_section_key(SECTION, key):
				_values[key] = _sanitize(key, cfg.get_value(SECTION, key, DEFAULTS[key]))
	elif err != ERR_FILE_NOT_FOUND and err != ERR_CANT_OPEN:
		push_warning("SettingsStore failed to load '%s' (err=%d), using defaults." % [target, err])
	_apply_window_mode()
	_apply_locale()
	settings_loaded.emit()
	return err


func save_settings(path_override: String = "") -> Error:
	var target := path_override if path_override != "" else config_path
	var cfg := ConfigFile.new()
	for key: String in DEFAULTS:
		cfg.set_value(SECTION, key, _values.get(key, DEFAULTS[key]))
	return cfg.save(target)


func get_value(key: String, fallback: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return fallback


func set_value(key: String, value: Variant, auto_save: bool = true) -> void:
	var clean: Variant = _sanitize(key, value)
	if _values.has(key) and _values[key] == clean:
		return
	_values[key] = clean
	if key == "fullscreen":
		_apply_window_mode()
	elif key == "locale":
		_apply_locale()
	setting_changed.emit(key, clean)
	if auto_save:
		save_settings()


func reset_defaults(auto_save: bool = true) -> void:
	_values = DEFAULTS.duplicate(true)
	_apply_window_mode()
	_apply_locale()
	for key: String in DEFAULTS:
		setting_changed.emit(key, _values[key])
	if auto_save:
		save_settings()


func load_translations(dir_override: String = "") -> Error:
	var target := dir_override if dir_override != "" else translation_dir
	clear_translations()
	if DirAccess.open(target) == null:
		_apply_locale()
		return ERR_FILE_NOT_FOUND
	_catalog = TranslationCatalogScript.new()
	var err: Error = _catalog.load_dir(target)
	_clamp_locale_to_catalog(true)
	_apply_locale()
	return err


func clear_translations() -> void:
	if _catalog != null:
		_catalog.unload()
		_catalog = null


func get_locales() -> PackedStringArray:
	if _catalog != null:
		var found := _catalog.get_locales()
		if not found.is_empty():
			return found
	return PackedStringArray([str(_values.get("locale", "en"))])


func locale_label(code: String) -> String:
	var canon := _canonical_locale(code)
	if _catalog != null:
		return _catalog.locale_label(canon)
	return canon


func _sanitize(key: String, value: Variant) -> Variant:
	match key:
		"master_volume", "bgm_volume", "sfx_volume", "ambience_volume", "ui_volume":
			return clampf(float(value), 0.0, 1.0)
		"camera_zoom_sensitivity", "camera_look_sensitivity":
			return clampf(float(value), 0.25, 3.0)
		"fullscreen", "show_debug_hud":
			return bool(value)
		"locale":
			var code := _canonical_locale(value)
			if _catalog != null and not _catalog.get_locales().is_empty() and not _catalog.get_locales().has(code):
				return _fallback_locale()
			return code
		"input_bindings":
			return (value as Dictionary).duplicate(true) if value is Dictionary else {}
		_:
			return value


func _canonical_locale(value: Variant) -> String:
	var raw := str(value).strip_edges()
	if _locale_regex().search(raw) == null:
		return _fallback_locale()
	return raw.replace("-", "_")


func _fallback_locale() -> String:
	if _catalog != null and _catalog.default_locale != "":
		var fallback := _catalog.default_locale
		var allowed := _catalog.get_locales()
		if allowed.is_empty() or allowed.has(fallback):
			return fallback
		return String(allowed[0])
	return "en"


func _clamp_locale_to_catalog(auto_save: bool) -> void:
	if _catalog == null or _catalog.get_locales().is_empty():
		return
	var current := str(_values.get("locale", "en"))
	if _catalog.get_locales().has(current):
		return
	var fallback := _fallback_locale()
	if current == fallback:
		return
	_values["locale"] = fallback
	_apply_locale()
	setting_changed.emit("locale", fallback)
	if auto_save:
		save_settings()


func _apply_locale() -> void:
	var code := str(_values.get("locale", "en"))
	ProjectSettings.set_setting("internationalization/locale/fallback", _fallback_locale())
	TranslationServer.set_locale(code)
	FontFallbackScript.apply()


func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fs := bool(_values.get("fullscreen", false))
	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)


func _locale_regex() -> RegEx:
	if _locale_pattern == null:
		_locale_pattern = RegEx.new()
		# Same locale code shape as gu data validation: en, zh, zh_CN, pt-BR.
		_locale_pattern.compile("^[A-Za-z]{2,3}([_-][A-Za-z0-9]+)*$")
	return _locale_pattern
