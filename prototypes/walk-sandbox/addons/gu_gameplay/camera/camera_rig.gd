class_name CameraRig
extends Node3D
## Smooth follow, zoom, and impulse screen-shake camera rig decoupled from world logic.

const DEFAULT_OFFSET := Vector3(0.0, 7.5, 9.5)
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.12
const FOLLOW_SPEED := 6.0
const LOOK_KEY_SPEED := 1.7
const LOOK_MOUSE_RAD := 0.004

@export var cam_offset: Vector3 = DEFAULT_OFFSET
@export var look_height: float = 0.9
@export var camera_path: NodePath = ^"Camera3D"

var _camera: Camera3D = null
var _target: Node3D = null
var _zoom: float = 1.0
var _yaw: float = 0.0
var _dragging_look: bool = false
var _mouse_mode_before_drag: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_remaining: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	add_to_group(&"gu_camera_rigs")
	_resolve_camera()
	_bind_zoom_keys()
	_bind_look_keys()


func set_target(target: Node3D) -> void:
	_target = target
	_resolve_camera()
	if _target != null and is_instance_valid(_target):
		global_position = _target.global_position + _orbit_offset()
		if _camera != null and is_inside_tree():
			_camera.look_at(_target.global_position + Vector3(0.0, look_height, 0.0), Vector3.UP)


func clear_target() -> void:
	_target = null


func get_zoom() -> float:
	return _zoom


func set_zoom(value: float) -> void:
	_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)


func get_yaw() -> float:
	return _yaw


func set_yaw(yaw: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)


func add_yaw(delta_yaw: float) -> void:
	set_yaw(_yaw + delta_yaw)


## Rotate a camera-local stick (x right, y forward as negative Z) into world XZ.
func world_move(input_dir: Vector2) -> Vector2:
	var world := Basis(Vector3.UP, _yaw) * Vector3(input_dir.x, 0.0, input_dir.y)
	return Vector2(world.x, world.z)


func add_shake(intensity: float, duration: float = 0.25) -> void:
	if intensity <= 0.0 or duration <= 0.0:
		return
	_shake_intensity = maxf(_shake_intensity, intensity)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_remaining = maxf(_shake_remaining, duration)


func get_shake_remaining() -> float:
	return _shake_remaining


func _unhandled_input(event: InputEvent) -> void:
	if not _is_gameplay_input_allowed():
		_end_look_drag()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_begin_look_drag()
		else:
			_end_look_drag()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _dragging_look:
		var motion := event as InputEventMouseMotion
		add_yaw(-motion.relative.x * LOOK_MOUSE_RAD * _look_sensitivity())
		get_viewport().set_input_as_handled()
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


func _process(delta: float) -> void:
	_resolve_camera()
	if _dragging_look and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_end_look_drag()
	if _is_gameplay_input_allowed():
		var look := 0.0
		if InputMap.has_action("camera_left") and Input.is_action_pressed("camera_left"):
			look += 1.0
		if InputMap.has_action("camera_right") and Input.is_action_pressed("camera_right"):
			look -= 1.0
		if look != 0.0:
			add_yaw(look * LOOK_KEY_SPEED * _look_sensitivity() * delta)
	if _target != null and is_instance_valid(_target):
		var desired := _target.global_position + _orbit_offset()
		global_position = global_position.lerp(desired, 1.0 - exp(-FOLLOW_SPEED * delta))
		if _camera != null:
			_camera.look_at(_target.global_position + Vector3(0.0, look_height, 0.0), Vector3.UP)

	_step_shake(delta)


func _step_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_remaining <= 0.0:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_shake_intensity = 0.0
		_shake_duration = 0.0
		return
	_shake_remaining = maxf(0.0, _shake_remaining - delta)
	var ratio := _shake_remaining / maxf(_shake_duration, 0.001)
	var amp := _shake_intensity * ratio * ratio
	_camera.h_offset = _rng.randf_range(-amp, amp)
	_camera.v_offset = _rng.randf_range(-amp, amp)


func _resolve_camera() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		_camera = get_node_or_null("Camera3D") as Camera3D


func _is_gameplay_input_allowed() -> bool:
	var router := get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("is_gameplay_active"):
		return bool(router.call("is_gameplay_active"))
	return true


func _orbit_offset() -> Vector3:
	return Basis(Vector3.UP, _yaw) * (cam_offset * _zoom)


func _begin_look_drag() -> void:
	if _dragging_look:
		return
	_dragging_look = true
	_mouse_mode_before_drag = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_look_drag() -> void:
	if not _dragging_look:
		return
	_dragging_look = false
	Input.mouse_mode = _mouse_mode_before_drag


func _look_sensitivity() -> float:
	var store := get_node_or_null("/root/SettingsStore")
	if store != null and store.has_method("get_value"):
		return float(store.call("get_value", "camera_look_sensitivity", 1.0))
	return 1.0


func _zoom_sensitivity() -> float:
	var store := get_node_or_null("/root/SettingsStore")
	if store != null and store.has_method("get_value"):
		return float(store.call("get_value", "camera_zoom_sensitivity", 1.0))
	return 1.0


func _bind_zoom_keys() -> void:
	var ir := get_node_or_null("/root/InputRouter")
	if ir != null and ir.has_method("register_action"):
		ir.call("register_action", &"zoom_in", [KEY_EQUAL, KEY_KP_ADD], "Zoom In")
		ir.call("register_action", &"zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT], "Zoom Out")
		return
	_bind("zoom_in", [KEY_EQUAL, KEY_KP_ADD])
	_bind("zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT])


func _bind_look_keys() -> void:
	var ir := get_node_or_null("/root/InputRouter")
	if ir != null and ir.has_method("register_action"):
		ir.call("register_action", &"camera_left", [KEY_Q], "Look Left")
		ir.call("register_action", &"camera_right", [KEY_R], "Look Right")
		return
	_bind("camera_left", [KEY_Q])
	_bind("camera_right", [KEY_R])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)
