extends Node
## Persistent user preferences backed by ConfigFile (audio, display, controls, debug).

signal setting_changed(key: String, value: Variant)
signal settings_loaded

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "preferences"

const DEFAULTS := {
	"master_volume": 1.0,
	"bgm_volume": 0.75,
	"sfx_volume": 0.90,
	"ambience_volume": 0.85,
	"ui_volume": 0.90,
	"camera_zoom_sensitivity": 1.0,
	"fullscreen": false,
	"show_debug_hud": true,
}

var config_path: String = DEFAULT_PATH
var _values: Dictionary = DEFAULTS.duplicate(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


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
	setting_changed.emit(key, clean)
	if auto_save:
		save_settings()


func reset_defaults(auto_save: bool = true) -> void:
	_values = DEFAULTS.duplicate(true)
	_apply_window_mode()
	for key: String in DEFAULTS:
		setting_changed.emit(key, _values[key])
	if auto_save:
		save_settings()


func _sanitize(key: String, value: Variant) -> Variant:
	match key:
		"master_volume", "bgm_volume", "sfx_volume", "ambience_volume", "ui_volume":
			return clampf(float(value), 0.0, 1.0)
		"camera_zoom_sensitivity":
			return clampf(float(value), 0.25, 3.0)
		"fullscreen", "show_debug_hud":
			return bool(value)
		_:
			return value


func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var fs := bool(_values.get("fullscreen", false))
	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
