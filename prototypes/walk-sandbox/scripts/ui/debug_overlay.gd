class_name DebugOverlay
extends CanvasLayer
## Protoss-themed tactical HUD & quick hotkeys (F3 toggle, G random map, V cycle landform).

signal regen_requested
signal landform_cycle_requested

@onready var _hud_root: Control = get_node_or_null("%HudRoot") as Control
@onready var _status_badge: Label = get_node_or_null("%StatusBadge") as Label
@onready var _telemetry_label: Label = get_node_or_null("%TelemetryLabel") as Label
@onready var _beacons_label: Label = get_node_or_null("%BeaconsLabel") as Label

var _terrain: Node = null
var _player: Node3D = null
var _sky_time: Node = null
var _camera_rig: CameraRig = null
var _landform_mode: int = -1
var _reached_spots: Array[String] = []
var _hud_enabled: bool = true


func _ready() -> void:
	_bind_debug_keys()
	_sync_with_settings()


func set_context(p_terrain: Node, p_player: Node3D, p_sky_time: Node, p_camera_rig: CameraRig) -> void:
	_terrain = p_terrain
	_player = p_player
	_sky_time = p_sky_time
	_camera_rig = p_camera_rig


func set_landform_mode(mode: int) -> void:
	_landform_mode = mode


func set_reached_spots(spots: Array[String]) -> void:
	_reached_spots = spots


func _unhandled_input(event: InputEvent) -> void:
	if not _allow_debug():
		return
	if InputMap.has_action("toggle_debug_hud") and event.is_action_pressed("toggle_debug_hud"):
		_hud_enabled = not _hud_enabled
		var store := get_node_or_null("/root/SettingsStore")
		if store != null and store.has_method("set_value"):
			store.call("set_value", "show_debug_hud", _hud_enabled)
		_apply_visibility()
		get_viewport().set_input_as_handled()
		return
	if not _is_gameplay_active():
		return
	if InputMap.has_action("regen_terrain") and event.is_action_pressed("regen_terrain"):
		regen_requested.emit()
		get_viewport().set_input_as_handled()
	elif InputMap.has_action("cycle_landform") and event.is_action_pressed("cycle_landform"):
		landform_cycle_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	_apply_visibility()
	if _hud_root == null or not _hud_root.visible:
		return

	var biome := "?"
	if _terrain != null and _player != null and _terrain.has_method("biome_name_at"):
		biome = str(_terrain.call("biome_name_at", _player.global_position.x, _player.global_position.z))
	var landform := "?"
	if _terrain != null and _terrain.has_method("landform_name"):
		landform = str(_terrain.call("landform_name"))
	var lf_tag := "Auto" if _landform_mode < 0 else "Locked"
	var zoom_pct := roundf((_camera_rig.get_zoom() if _camera_rig != null else 1.0) * 100.0)
	var sky_line := ""
	if _sky_time != null and _sky_time.has_method("get_hud_line"):
		sky_line = str(_sky_time.call("get_hud_line"))
	var async_tag := " [WARPING...]" if (_terrain != null and _terrain.has_method("is_generating_async") and bool(_terrain.call("is_generating_async"))) else ""

	var stance := "IDLE"
	if _player != null:
		var lbl := _player.get_node_or_null("NameLabel") as Label3D
		if lbl != null and lbl.text != "":
			stance = lbl.text

	if _status_badge != null:
		_status_badge.text = "%s · ZOOM %.0f%%" % [stance, zoom_pct]

	if _telemetry_label != null:
		_telemetry_label.text = (
			"Landform: %s (%s)%s · Biome: %s\n%s" % [landform, lf_tag, async_tag, biome, sky_line]
		)

	if _beacons_label != null:
		var tokens: Array[String] = []
		for i in range(1, 7):
			var name_str := "Spot %d" % i
			if _reached_spots.has(name_str):
				tokens.append("◆%d" % i)
			else:
				tokens.append("◇%d" % i)
		_beacons_label.text = "  ".join(tokens)


func _sync_with_settings() -> void:
	var store := get_node_or_null("/root/SettingsStore")
	if store != null:
		_hud_enabled = bool(store.call("get_value", "show_debug_hud", true))
		if store.has_signal("setting_changed") and not store.is_connected("setting_changed", Callable(self, "_on_setting_changed")):
			store.connect("setting_changed", Callable(self, "_on_setting_changed"))
	_apply_visibility()


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "show_debug_hud":
		_hud_enabled = bool(value)
		_apply_visibility()


func _apply_visibility() -> void:
	if _hud_root == null:
		return
	var flow := get_node_or_null("/root/GameFlow")
	var on_title := flow != null and int(flow.call("get_state")) == 1 # GameFlow.State.TITLE
	_hud_root.visible = _hud_enabled and not on_title


func _allow_debug() -> bool:
	var router := get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("allow_debug"):
		return bool(router.call("allow_debug"))
	return true


func _is_gameplay_active() -> bool:
	var router := get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("is_gameplay_active"):
		return bool(router.call("is_gameplay_active"))
	return true


func _bind_debug_keys() -> void:
	_bind("regen_terrain", [KEY_G])
	_bind("cycle_landform", [KEY_V])
	_bind("toggle_debug_hud", [KEY_F3])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)
