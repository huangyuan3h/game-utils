extends Control
## Protoss-themed settings panel bound to SettingsStore and InputRouter KeybindList.

@onready var _panel: PanelContainer = %Panel
@onready var _system_tab_btn: Button = get_node_or_null("%SystemTabButton") as Button
@onready var _controls_tab_btn: Button = get_node_or_null("%ControlsTabButton") as Button
@onready var _system_section: Control = get_node_or_null("%SystemSection") as Control
@onready var _controls_section: Control = get_node_or_null("%ControlsSection") as Control
@onready var _keybind_list: KeybindList = get_node_or_null("%KeybindList") as KeybindList
@onready var _reset_keys_btn: Button = get_node_or_null("%ResetKeysButton") as Button

@onready var _audio_label: Label = get_node_or_null("%AudioSectionLabel") as Label
@onready var _master_label: Label = get_node_or_null("%MasterLabel") as Label
@onready var _sfx_label: Label = get_node_or_null("%SfxLabel") as Label
@onready var _amb_label: Label = get_node_or_null("%AmbienceLabel") as Label
@onready var _bgm_label: Label = get_node_or_null("%BgmLabel") as Label
@onready var _system_label: Label = get_node_or_null("%SystemSectionLabel") as Label
@onready var _language_label: Label = get_node_or_null("%LanguageLabel") as Label
@onready var _language_option: OptionButton = get_node_or_null("%LanguageOption") as OptionButton
@onready var _controls_hint: Label = get_node_or_null("%ControlsHint") as Label

@onready var _master_slider: HSlider = %MasterSlider
@onready var _master_val: Label = %MasterValue
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _sfx_val: Label = %SfxValue
@onready var _amb_slider: HSlider = %AmbienceSlider
@onready var _amb_val: Label = %AmbienceValue
@onready var _bgm_slider: HSlider = %BgmSlider
@onready var _bgm_val: Label = %BgmValue
@onready var _debug_check: CheckButton = %DebugHudCheck
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _reset_btn: Button = %ResetButton
@onready var _back_btn: Button = %BackButton

var _syncing: bool = false
var _locale_codes: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_master_slider.value_changed.connect(func(v: float) -> void: _on_slider("master_volume", v, _master_val))
	_sfx_slider.value_changed.connect(func(v: float) -> void: _on_slider("sfx_volume", v, _sfx_val))
	_amb_slider.value_changed.connect(func(v: float) -> void: _on_slider("ambience_volume", v, _amb_val))
	_bgm_slider.value_changed.connect(func(v: float) -> void: _on_slider("bgm_volume", v, _bgm_val))
	_debug_check.toggled.connect(func(on: bool) -> void: _on_toggle("show_debug_hud", on))
	_fullscreen_check.toggled.connect(func(on: bool) -> void: _on_toggle("fullscreen", on))
	if _language_option != null:
		_language_option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_language_option.item_selected.connect(_on_language_selected)
	_reset_btn.pressed.connect(_on_reset)
	_back_btn.pressed.connect(_on_back)
	if _system_tab_btn != null:
		_system_tab_btn.pressed.connect(func() -> void: show_tab("system"))
	if _controls_tab_btn != null:
		_controls_tab_btn.pressed.connect(func() -> void: show_tab("controls"))
	if _reset_keys_btn != null:
		_reset_keys_btn.pressed.connect(_on_reset_keys)
	ProtossUiFx.attach_tree(self, [_back_btn])
	show_tab("system")
	_sync_from_store()
	_refresh_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func on_ui_enter(_params: Dictionary = {}) -> void:
	show_tab("system")
	_sync_from_store()
	_refresh_texts()
	if _keybind_list != null:
		_keybind_list.rebuild()
	ProtossUiFx.animate_panel_enter(_panel, self, true)


func show_tab(tab_name: String) -> void:
	var show_controls := (tab_name == "controls")
	if _system_section != null:
		_system_section.visible = not show_controls
	if _controls_section != null:
		_controls_section.visible = show_controls
	if _system_tab_btn != null:
		_system_tab_btn.disabled = not show_controls
	if _controls_tab_btn != null:
		_controls_tab_btn.disabled = show_controls
	if _reset_btn != null:
		_reset_btn.visible = not show_controls


func _sync_from_store() -> void:
	var store := get_node_or_null("/root/SettingsStore")
	if store == null:
		return
	_syncing = true
	_set_slider(_master_slider, _master_val, float(store.call("get_value", "master_volume", 1.0)))
	_set_slider(_sfx_slider, _sfx_val, float(store.call("get_value", "sfx_volume", 0.9)))
	_set_slider(_amb_slider, _amb_val, float(store.call("get_value", "ambience_volume", 0.85)))
	_set_slider(_bgm_slider, _bgm_val, float(store.call("get_value", "bgm_volume", 0.75)))
	_debug_check.button_pressed = bool(store.call("get_value", "show_debug_hud", true))
	_fullscreen_check.button_pressed = bool(store.call("get_value", "fullscreen", false))
	_fill_language_option(store)
	_syncing = false


func _refresh_texts() -> void:
	_set_tr(get_node_or_null("Center/Panel/VBox/Tag") as Label, "SETTINGS_TAG")
	_set_tr(get_node_or_null("Center/Panel/VBox/Header") as Label, "SETTINGS_HEADER")
	_set_tr(_system_tab_btn, "SETTINGS_TAB_SYSTEM")
	_set_tr(_controls_tab_btn, "SETTINGS_TAB_CONTROLS")
	_set_tr(_audio_label, "SETTINGS_AUDIO")
	_set_tr(_master_label, "SETTINGS_MASTER")
	_set_tr(_sfx_label, "SETTINGS_SFX")
	_set_tr(_amb_label, "SETTINGS_AMBIENCE")
	_set_tr(_bgm_label, "SETTINGS_BGM")
	_set_tr(_system_label, "SETTINGS_SYSTEM")
	_set_tr(_language_label, "SETTINGS_LANGUAGE")
	_set_tr(_debug_check, "SETTINGS_DEBUG_HUD")
	_set_tr(_fullscreen_check, "SETTINGS_FULLSCREEN")
	_set_tr(_controls_hint, "SETTINGS_KEYBINDS")
	_set_tr(_reset_keys_btn, "SETTINGS_RESET_KEYS")
	_set_tr(_reset_btn, "SETTINGS_RESET")
	_set_tr(_back_btn, "SETTINGS_BACK")


func _set_tr(node: Node, key: String) -> void:
	if node == null or not ("text" in node):
		return
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	node.text = tr(key)


func _fill_language_option(store: Node) -> void:
	if _language_option == null:
		return
	_language_option.clear()
	_locale_codes = PackedStringArray()
	var locales: Variant = store.call("get_locales")
	var current := str(store.call("get_value", "locale", "en"))
	var select_idx := 0
	var index := 0
	if locales is Array or locales is PackedStringArray:
		for code_v in locales:
			var code := str(code_v)
			_locale_codes.append(code)
			_language_option.add_item(str(store.call("locale_label", code)))
			if code == current:
				select_idx = index
			index += 1
	if not _locale_codes.is_empty():
		_language_option.select(select_idx)


func _set_slider(slider: HSlider, label: Label, v: float) -> void:
	slider.value = v
	label.text = "%d%%" % roundi(v * 100.0)


func _on_slider(key: String, value: float, label: Label) -> void:
	label.text = "%d%%" % roundi(value * 100.0)
	if _syncing:
		return
	var store := get_node_or_null("/root/SettingsStore")
	if store != null:
		store.call("set_value", key, value)


func _on_toggle(key: String, enabled: bool) -> void:
	if _syncing:
		return
	var store := get_node_or_null("/root/SettingsStore")
	if store != null:
		store.call("set_value", key, enabled)


func _on_language_selected(index: int) -> void:
	if _syncing or index < 0 or index >= _locale_codes.size():
		return
	var store := get_node_or_null("/root/SettingsStore")
	if store != null:
		store.call("set_value", "locale", _locale_codes[index])


func _on_reset() -> void:
	var store := get_node_or_null("/root/SettingsStore")
	if store != null:
		store.call("reset_defaults")
		_sync_from_store()
		_refresh_texts()


func _on_reset_keys() -> void:
	if _keybind_list != null:
		_keybind_list.reset_all()


func _on_back() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("close_top_ui")
