class_name CameraRig
extends Node3D
## Smooth follow + zoom camera rig decoupled from world/main scene logic.

const DEFAULT_OFFSET := Vector3(0.0, 7.5, 9.5)
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.12
const FOLLOW_SPEED := 6.0

@export var cam_offset: Vector3 = DEFAULT_OFFSET
@export var look_height: float = 0.9

@onready var _camera: Camera3D = $Camera3D

var _target: Node3D = null
var _zoom: float = 1.0


func _ready() -> void:
	_bind_zoom_keys()


func set_target(target: Node3D) -> void:
	_target = target
	if _target != null:
		global_position = _target.global_position + cam_offset * _zoom
		if _camera != null:
			_camera.look_at(_target.global_position + Vector3(0.0, look_height, 0.0), Vector3.UP)


func get_zoom() -> float:
	return _zoom


func set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_gameplay_input_allowed():
		return
	var sens := _zoom_sensitivity()
	if event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		set_zoom(_zoom + pan.delta.y * 0.045 * sens)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		var factor := lerpf(1.0, mag.factor, sens)
		set_zoom(_zoom / maxf(factor, 0.01))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(_zoom - ZOOM_STEP * sens)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(_zoom + ZOOM_STEP * sens)
			get_viewport().set_input_as_handled()
		return
	if InputMap.has_action("zoom_in") and event.is_action_pressed("zoom_in"):
		set_zoom(_zoom - ZOOM_STEP * sens)
	elif InputMap.has_action("zoom_out") and event.is_action_pressed("zoom_out"):
		set_zoom(_zoom + ZOOM_STEP * sens)


func _is_gameplay_input_allowed() -> bool:
	var router := get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("is_gameplay_active"):
		return bool(router.call("is_gameplay_active"))
	return true


func _zoom_sensitivity() -> float:
	var store := get_node_or_null("/root/SettingsStore")
	if store != null and store.has_method("get_value"):
		return float(store.call("get_value", "camera_zoom_sensitivity", 1.0))
	return 1.0


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var desired := _target.global_position + cam_offset * _zoom
	global_position = global_position.lerp(desired, 1.0 - exp(-FOLLOW_SPEED * delta))
	if _camera != null:
		_camera.look_at(_target.global_position + Vector3(0.0, look_height, 0.0), Vector3.UP)


func _bind_zoom_keys() -> void:
	_bind("zoom_in", [KEY_EQUAL, KEY_KP_ADD])
	_bind("zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)
