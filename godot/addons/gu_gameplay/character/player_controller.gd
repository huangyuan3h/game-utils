extends CharacterBody3D
class_name GuPlayer
## Shared player coordinator: reads input, steps CharacterActionController & CharacterLocomotion,
## and drives Visual / Audio / Headlight. Art and audio paths are supplied by the owning scene.

signal player_died
signal player_respawned

const ACTION_BINDINGS := {
	"action_gather": &"gather",
	"action_mine": &"mine",
	"action_chop": &"chop",
	"action_build": &"build",
	"action_strike": &"strike",
}
const STAMINA_MAX := 100.0
const STAMINA_REGEN := 15.0
const STRIKE_RANGE := 2.4
const STRIKE_DOT := 0.35

@export_group("Combat")
@export var max_hp: float = 100.0
@export var strike_damage: float = 18.0
@export var respawn_delay: float = 2.0

@export_group("Character Assets")
## Rigged model with Idle/Walk/Run/Working clips (FBX or glTF scene).
@export_file("*.fbx", "*.glb", "*.tscn") var animated_model_path: String = ""
## Static model used when no rigged model is configured.
@export_file("*.glb", "*.tscn") var walker_model_path: String = ""
## Second static model option, tried after `walker_model_path`.
@export_file("*.glb", "*.tscn") var settler_model_path: String = ""
## Looping water ambience played near open water. Leave empty to disable.
@export_file("*.wav", "*.ogg") var water_loop_path: String = ""

@onready var _visual_root: Node3D = $VisualRoot
@onready var _label: Label3D = $NameLabel
@onready var _feet: AudioStreamPlayer3D = $Footsteps

## External context — injected by main (keeps public vars for backwards compatibility).
var terrain: Node = null
var sky_time: Node = null

var _run_mode: bool = false
var _locomotion := CharacterLocomotion.new()
var _actions := CharacterActionController.new()
var _inventory := InventoryContainer.new(16, 99)
var _stats := StatSet.new()
var _visual: CharacterVisual
var _audio: CharacterAudio
var _head_light: NightHeadlight
var _interactor: Interactor
var _health: HealthComponent = null
var _hurtbox: Hurtbox = null
var _hitbox: Hitbox = null
var _spawn_position := Vector3.ZERO
var _dead := false


func _ready() -> void:
	_stats.define_stat(&"stamina", STAMINA_MAX)
	_spawn_position = global_position
	_ensure_combat()
	_ensure_input_map()
	collision_mask = 0
	collision_layer = 0
	add_to_group(WorldPickup.COLLECTOR_GROUP)
	var save_svc := get_node_or_null("/root/SaveService")
	if save_svc != null and save_svc.has_method("register_saveable"):
		save_svc.call("register_saveable", "inventory", _inventory)
		save_svc.call("register_saveable", "player_stats", _stats)

	_visual = CharacterVisual.new()
	_visual.name = "VisualController"
	add_child(_visual)
	_visual.setup(_visual_root, {
		"animated": animated_model_path,
		"walker": walker_model_path,
		"settler": settler_model_path,
	})

	_audio = CharacterAudio.new()
	_audio.name = "AudioController"
	add_child(_audio)
	_audio.setup(_feet, water_loop_path)

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


func _exit_tree() -> void:
	var save_svc := get_node_or_null("/root/SaveService")
	if save_svc != null and save_svc.has_method("unregister_saveable"):
		save_svc.call("unregister_saveable", "inventory")
		save_svc.call("unregister_saveable", "player_stats")


func set_context(p_terrain: Node, p_sky_time: Node) -> void:
	terrain = p_terrain
	sky_time = p_sky_time


func get_interactor() -> Interactor:
	return _interactor


func get_inventory() -> InventoryContainer:
	return _inventory


func get_stats() -> StatSet:
	return _stats


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


func is_alive() -> bool:
	return _health == null or not _health.is_dead()


func set_spawn_point(point: Vector3) -> void:
	_spawn_position = point


func get_health() -> HealthComponent:
	return _health


func get_hurtbox() -> Hurtbox:
	return _hurtbox


func get_facing_yaw() -> float:
	return _locomotion.facing_yaw


func set_facing_yaw(yaw: float) -> void:
	_locomotion.facing_yaw = yaw


func _physics_process(delta: float) -> void:
	var step := _gameplay_delta(delta)
	var allow_input := _is_gameplay_input_allowed()
	if allow_input and Input.is_action_just_pressed("sprint"):
		_run_mode = not _run_mode

	var input_dir := Vector2.ZERO
	if allow_input:
		input_dir = _aim_move(Input.get_vector("move_left", "move_right", "move_forward", "move_back"))
		_process_action_inputs()

	var hold_active := allow_input and _is_any_action_held()
	var action_frame := _actions.step(step, _locomotion, input_dir, hold_active)
	var move_scale := float(action_frame.get("move_scale", 1.0))
	var facing_override := float(action_frame.get("facing_override_yaw", 0.0)) if bool(action_frame.get("has_facing_override", false)) else NAN

	_tick_stamina(step)
	var result := _locomotion.step(global_position, velocity, input_dir, _run_mode, terrain, step, move_scale, facing_override)
	velocity = result["velocity"] as Vector3
	global_position = result["position"] as Vector3

	var action_label := str(action_frame.get("state_label", ""))
	_label.text = action_label if action_label != "" else _locomotion.state_label

	var snow_cover := 0.0
	if sky_time != null and sky_time.has_method("get_weather_params"):
		var wp: Dictionary = sky_time.call("get_weather_params") as Dictionary
		snow_cover = float(wp.get("snow_cover", 0.0))

	_visual.update_visual(_locomotion, step, action_frame)
	_audio.update_audio(_locomotion, terrain, global_position, step, snow_cover)
	_head_light.update_from_sky(sky_time, step)


func _aim_move(input_dir: Vector2) -> Vector2:
	var tree := get_tree()
	if tree == null:
		return input_dir
	var rigs := tree.get_nodes_in_group(&"gu_camera_rigs")
	if rigs.is_empty():
		return input_dir
	var rig: Node = rigs[0]
	if rig.has_method("world_move"):
		return rig.call("world_move", input_dir)
	return input_dir


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
	if action_id == &"strike":
		_apply_strike_beat()
	else:
		_apply_action_beat_to_nearby_resource(action_id)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method("emit_event"):
		bus.call("emit_event", &"character_action_beat", {
			"action_id": action_id,
			"beat_index": beat_index,
			"cycle_count": cycle_count,
		})


func _apply_action_beat_to_nearby_resource(action_id: StringName) -> void:
	if not is_inside_tree():
		return
	var focused := _interactor.get_focused() if _interactor != null else null
	if focused is ResourceNode:
		var rfocus := focused as ResourceNode
		if not rfocus.is_depleted():
			rfocus.apply_harvest_hit(self)
			return
	var tree := get_tree()
	if tree == null:
		return
	var best: ResourceNode = null
	var best_d2 := 2.8 * 2.8
	for node in tree.get_nodes_in_group(Interactable.GROUP_NAME):
		if node is ResourceNode:
			var rn := node as ResourceNode
			if rn.is_depleted() or rn.preferred_action != action_id:
				continue
			var d2 := global_position.distance_squared_to(rn.global_position)
			if d2 <= best_d2:
				best_d2 = d2
				best = rn
	if best != null:
		best.apply_harvest_hit(self)


func _apply_strike_beat() -> void:
	if not is_inside_tree() or _hitbox == null:
		return
	var forward := Vector3(-sin(_locomotion.facing_yaw), 0.0, -cos(_locomotion.facing_yaw))
	var best: Hurtbox = null
	var best_d2 := STRIKE_RANGE * STRIKE_RANGE
	for node in get_tree().get_nodes_in_group(GuEnemy.GROUP_NAME):
		if not (node is GuEnemy) or (node as GuEnemy).is_dead():
			continue
		var hurtbox := (node as GuEnemy).get_hurtbox()
		if hurtbox == null:
			continue
		var offset := hurtbox.global_position - global_position
		offset.y = 0.0
		var d2 := offset.length_squared()
		if d2 > best_d2:
			continue
		if d2 > 0.01 and forward.dot(offset.normalized()) < STRIKE_DOT:
			continue
		best_d2 = d2
		best = hurtbox
	if best != null:
		_hitbox.strike(best, false, forward)


func _ensure_combat() -> void:
	_health = get_node_or_null("Health") as HealthComponent
	if _health != null:
		_health.bind_stat_set(_stats, true)
		_health.max_hp = max_hp
		if not _health.died.is_connected(_on_player_died):
			_health.died.connect(_on_player_died)
	_hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if _hurtbox != null:
		_hurtbox.faction = &"player"
		_hurtbox.health = _health
	_hitbox = get_node_or_null("Hitbox") as Hitbox
	if _hitbox != null:
		_hitbox.faction = &"player"
		_hitbox.damage = strike_damage


func _on_player_died(_source: Node) -> void:
	if _dead:
		return
	_dead = true
	player_died.emit()
	set_physics_process(false)
	if _visual_root != null:
		_visual_root.visible = false
	await get_tree().create_timer(maxf(0.2, respawn_delay)).timeout
	if not is_inside_tree():
		return
	_dead = false
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_locomotion.reset()
	if _visual_root != null:
		_visual_root.visible = true
	if _health != null:
		_health.revive(true)
	player_respawned.emit()
	set_physics_process(true)


func _tick_stamina(delta: float) -> void:
	# Shift toggles run and keeps it. An empty stamina bar must not force a walk.
	_stats.modify_value(&"stamina", STAMINA_REGEN * delta)


func _gameplay_delta(frame_delta: float) -> float:
	var clock := get_node_or_null("/root/GameClock")
	if clock != null and clock.has_method("gameplay_delta"):
		return float(clock.call("gameplay_delta", frame_delta))
	return frame_delta


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
		router.call("register_action", &"action_gather", [KEY_1], "Action: Gather")
		router.call("register_action", &"action_mine", [KEY_2], "Action: Mine")
		router.call("register_action", &"action_chop", [KEY_3], "Action: Chop")
		router.call("register_action", &"action_build", [KEY_4], "Action: Build")
		router.call("register_action", &"action_strike", [KEY_SPACE], "Strike")
		router.call("register_action", &"action_repeat", [KEY_F], "Repeat Action")
		router.call("register_action", &"action_cancel", [KEY_X], "Cancel Action")
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
		_bind("action_strike", [KEY_SPACE])
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
