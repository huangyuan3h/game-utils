extends CharacterBody3D
## Player coordinator: reads input, steps CharacterActionController & CharacterLocomotion,
## and drives Visual / Audio / Headlight.

const ACTION_BINDINGS := {
	"action_gather": &"gather",
	"action_mine": &"mine",
	"action_chop": &"chop",
	"action_build": &"build",
}

@onready var _visual_root: Node3D = $VisualRoot
@onready var _label: Label3D = $NameLabel
@onready var _feet: AudioStreamPlayer3D = $Footsteps

## External context — injected by main (keeps public vars for backwards compatibility).
var terrain: Node = null
var sky_time: Node = null

var _run_mode: bool = false
var _locomotion := CharacterLocomotion.new()
var _actions := CharacterActionController.new()
var _visual: CharacterVisual
var _audio: CharacterAudio
var _head_light: NightHeadlight
var _interactor: Interactor


func _ready() -> void:
	_ensure_input_map()
	collision_mask = 0
	collision_layer = 0

	_visual = CharacterVisual.new()
	_visual.name = "VisualController"
	add_child(_visual)
	_visual.setup(_visual_root)

	_audio = CharacterAudio.new()
	_audio.name = "AudioController"
	add_child(_audio)
	_audio.setup(_feet)

	_head_light = NightHeadlight.new()
	add_child(_head_light)

	_interactor = get_node_or_null("Interactor") as Interactor
	if _interactor == null:
		_interactor = Interactor.new()
		_interactor.name = "Interactor"
		_interactor.position = Vector3(0.0, 0.75, 0.0)
		add_child(_interactor)
	_interactor.set_actor(self)

	_actions.action_beat.connect(_on_action_beat)
	_label.text = _visual.model_status_text


func set_context(p_terrain: Node, p_sky_time: Node) -> void:
	terrain = p_terrain
	sky_time = p_sky_time


func get_interactor() -> Interactor:
	return _interactor


func get_locomotion() -> CharacterLocomotion:
	return _locomotion


func get_action_controller() -> CharacterActionController:
	return _actions


func perform_action(action_id: StringName, context: Dictionary = {}) -> bool:
	var ctx := context.duplicate()
	if not ctx.has("origin_pos"):
		ctx["origin_pos"] = global_position
	return _actions.try_start(action_id, _locomotion, ctx)


func cancel_action(reason: StringName = &"manual") -> void:
	_actions.cancel(reason)


func get_run_mode() -> bool:
	return _run_mode


func set_run_mode(enabled: bool) -> void:
	_run_mode = enabled


func get_facing_yaw() -> float:
	return _locomotion.facing_yaw


func set_facing_yaw(yaw: float) -> void:
	_locomotion.facing_yaw = yaw


func _physics_process(delta: float) -> void:
	var allow_input := _is_gameplay_input_allowed()
	if allow_input and Input.is_action_just_pressed("sprint"):
		_run_mode = not _run_mode

	var input_dir := Vector2.ZERO
	if allow_input:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		_process_action_inputs()

	var hold_active := allow_input and _is_any_action_held()
	var action_frame := _actions.step(delta, _locomotion, input_dir, hold_active)
	var move_scale := float(action_frame.get("move_scale", 1.0))
	var facing_override := float(action_frame.get("facing_override_yaw", 0.0)) if bool(action_frame.get("has_facing_override", false)) else NAN

	var result := _locomotion.step(global_position, velocity, input_dir, _run_mode, terrain, delta, move_scale, facing_override)
	velocity = result["velocity"] as Vector3
	global_position = result["position"] as Vector3

	var action_label := str(action_frame.get("state_label", ""))
	_label.text = action_label if action_label != "" else _locomotion.state_label

	var snow_cover := 0.0
	if sky_time != null and sky_time.has_method("get_weather_params"):
		var wp: Dictionary = sky_time.call("get_weather_params") as Dictionary
		snow_cover = float(wp.get("snow_cover", 0.0))

	_visual.update_visual(_locomotion, delta, action_frame)
	_audio.update_audio(_locomotion, terrain, global_position, delta, snow_cover)
	_head_light.update_from_sky(sky_time, delta)


func _process_action_inputs() -> void:
	if Input.is_action_just_pressed("action_cancel"):
		_actions.cancel(&"input_cancel")
		return
	for input_name: String in ACTION_BINDINGS.keys():
		if Input.is_action_just_pressed(input_name):
			perform_action(ACTION_BINDINGS[input_name] as StringName)
			return
	if Input.is_action_just_pressed("action_repeat"):
		perform_action(_actions.last_used_id)


func _is_any_action_held() -> bool:
	if Input.is_action_pressed("action_repeat"):
		return true
	for input_name: String in ACTION_BINDINGS.keys():
		if Input.is_action_pressed(input_name):
			return true
	return false


func _on_action_beat(action_id: StringName, beat_index: int, cycle_count: int) -> void:
	if _visual != null:
		_visual.trigger_action_beat(action_id)
	if _audio != null:
		_audio.play_action_beat(action_id)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method("emit_event"):
		bus.call("emit_event", &"character_action_beat", {
			"action_id": action_id,
			"beat_index": beat_index,
			"cycle_count": cycle_count,
		})


func _is_gameplay_input_allowed() -> bool:
	var router := get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("is_gameplay_active"):
		return bool(router.call("is_gameplay_active"))
	return true


func _ensure_input_map() -> void:
	var router := get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("register_action"):
		router.call("register_action", &"move_left", [KEY_A, KEY_LEFT], "Move Left")
		router.call("register_action", &"move_right", [KEY_D, KEY_RIGHT], "Move Right")
		router.call("register_action", &"move_forward", [KEY_W, KEY_UP], "Move Forward")
		router.call("register_action", &"move_back", [KEY_S, KEY_DOWN], "Move Back")
		router.call("register_action", &"sprint", [KEY_SHIFT], "Toggle Run")
	else:
		_bind("move_left", [KEY_A, KEY_LEFT])
		_bind("move_right", [KEY_D, KEY_RIGHT])
		_bind("move_forward", [KEY_W, KEY_UP])
		_bind("move_back", [KEY_S, KEY_DOWN])
		_bind("sprint", [KEY_SHIFT])
	_bind("action_gather", [KEY_1])
	_bind("action_mine", [KEY_2])
	_bind("action_chop", [KEY_3])
	_bind("action_build", [KEY_4])
	_bind("action_repeat", [KEY_F])
	_bind("action_cancel", [KEY_X])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)
