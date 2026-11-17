extends Control
## Protoss-themed settings panel bound directly to SettingsStore.

@onready var _panel: PanelContainer = %Panel
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


func _ready() -> void:
	_master_slider.value_changed.connect(func(v: float) -> void: _on_slider("master_volume", v, _master_val))
	_sfx_slider.value_changed.connect(func(v: float) -> void: _on_slider("sfx_volume", v, _sfx_val))
	_amb_slider.value_changed.connect(func(v: float) -> void: _on_slider("ambience_volume", v, _amb_val))
	_bgm_slider.value_changed.connect(func(v: float) -> void: _on_slider("bgm_volume", v, _bgm_val))
	_debug_check.toggled.connect(func(on: bool) -> void: _on_toggle("show_debug_hud", on))
	_fullscreen_check.toggled.connect(func(on: bool) -> void: _on_toggle("fullscreen", on))
	_reset_btn.pressed.connect(_on_reset)
	_back_btn.pressed.connect(_on_back)
	ProtossUiFx.attach_tree(self, [_back_btn])
	_sync_from_store()


func on_ui_enter(_params: Dictionary = {}) -> void:
	_sync_from_store()
	ProtossUiFx.animate_panel_enter(_panel, self, true)


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
	_syncing = false


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


func _on_reset() -> void:
	var store := get_node_or_null("/root/SettingsStore")
	if store != null:
		store.call("reset_defaults")
		_sync_from_store()


func _on_back() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("close_top_ui")
