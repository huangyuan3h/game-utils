extends CharacterBody3D
## Natural 8-direction walk/run — Quaternius Idle/Walk/Run + footstep taps.

const WALK_SPEED := 3.2
const RUN_SPEED := 6.4
const ACCEL := 16.0
const DECEL := 20.0
const TURN_SPEED := 12.0
const MODEL_SCALE := 0.30
const ANIMATED_PATH := "res://assets/models/quaternius/AnimatedHuman.fbx"
const WALKER_PATH := "res://assets/models/walker.glb"
const SETTLER_PATH := "res://assets/models/settler.glb"

## Seconds between footfalls (one foot). Run is quicker da-da.
const WALK_STEP_INTERVAL := 0.42
const RUN_STEP_INTERVAL := 0.26

@onready var _visual_root: Node3D = $VisualRoot
@onready var _label: Label3D = $NameLabel
@onready var _feet: AudioStreamPlayer3D = $Footsteps

var _anim: AnimationPlayer = null
var _clip_idle: String = ""
var _clip_walk: String = ""
var _clip_run: String = ""
var _using_rig: bool = false
var _bob_t: float = 0.0
var _facing_yaw: float = 0.0
var _current_clip: String = ""
var _step_timer: float = 0.0
var _walk_streams: Array[AudioStream] = []
var _run_streams: Array[AudioStream] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_ensure_input_map()
	_load_footsteps()
	_load_model()
	_label.text = "WASD + Shift"


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Vector3(input_dir.x, 0.0, input_dir.y)
	var moving := wish.length_squared() > 0.0001
	var want_run := moving and Input.is_action_pressed("sprint")
	var speed := RUN_SPEED if want_run else WALK_SPEED

	if moving:
		wish = wish.normalized()
		var target_vel := wish * speed
		velocity.x = move_toward(velocity.x, target_vel.x, ACCEL * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, ACCEL * delta)
		var target_yaw := atan2(wish.x, wish.z)
		_facing_yaw = lerp_angle(_facing_yaw, target_yaw, 1.0 - exp(-TURN_SPEED * delta))
		_visual_root.rotation.y = _facing_yaw
	else:
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, DECEL * delta)

	velocity.y = 0.0
	move_and_slide()

	var speed_xz := Vector2(velocity.x, velocity.z).length()
	var running := want_run and speed_xz > WALK_SPEED * 0.85
	_update_anim(speed_xz, running, delta)
	_update_footsteps(speed_xz, running, delta)


func _update_anim(speed_xz: float, running: bool, delta: float) -> void:
	var moving := speed_xz > 0.25
	if _using_rig and _anim != null:
		if moving:
			if running and _clip_run != "":
				_play_clip(_clip_run)
				_anim.speed_scale = clampf(speed_xz / RUN_SPEED, 0.85, 1.2)
			else:
				_play_clip(_clip_walk if _clip_walk != "" else _clip_run)
				_anim.speed_scale = clampf(speed_xz / WALK_SPEED, 0.75, 1.25)
		else:
			_play_clip(_clip_idle)
			_anim.speed_scale = 1.0
		_visual_root.position.y = 0.0
		return

	if moving:
		var bob_rate := 14.0 if running else 8.0
		var bob_amp := 0.06 if running else 0.045
		_bob_t += delta * (bob_rate + speed_xz * 1.5)
		_visual_root.position.y = absf(sin(_bob_t)) * bob_amp
		_visual_root.rotation.z = sin(_bob_t * 0.5) * 0.05
		_visual_root.rotation.x = sin(_bob_t) * 0.035
	else:
		_bob_t = 0.0
		_visual_root.position.y = move_toward(_visual_root.position.y, 0.0, delta * 2.0)
		_visual_root.rotation.x = move_toward(_visual_root.rotation.x, 0.0, delta * 4.0)
		_visual_root.rotation.z = move_toward(_visual_root.rotation.z, 0.0, delta * 4.0)


func _update_footsteps(speed_xz: float, running: bool, delta: float) -> void:
	if speed_xz < 0.4:
		_step_timer = 0.0
		return
	var interval := RUN_STEP_INTERVAL if running else WALK_STEP_INTERVAL
	# Scale interval slightly with actual speed so slow walk is less busy
	interval *= clampf((RUN_SPEED if running else WALK_SPEED) / maxf(speed_xz, 0.1), 0.75, 1.35)
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = interval
	_play_footstep(running)


func _play_footstep(running: bool) -> void:
	if _feet == null:
		return
	var pool := _run_streams if running and not _run_streams.is_empty() else _walk_streams
	if pool.is_empty():
		return
	_feet.stream = pool[_rng.randi_range(0, pool.size() - 1)]
	_feet.pitch_scale = _rng.randf_range(0.92, 1.08)
	_feet.volume_db = (-8.0 if running else -12.0) + _rng.randf_range(-1.0, 1.0)
	_feet.play()


func _load_footsteps() -> void:
	_walk_streams.clear()
	_run_streams.clear()
	for i in 4:
		var wpath := "res://assets/sfx/foot_walk_%d.wav" % i
		var rpath := "res://assets/sfx/foot_run_%d.wav" % i
		if ResourceLoader.exists(wpath):
			_walk_streams.append(load(wpath) as AudioStream)
		if ResourceLoader.exists(rpath):
			_run_streams.append(load(rpath) as AudioStream)
	if _feet != null:
		_feet.bus = &"Master"
		_feet.max_distance = 28.0
		_feet.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE


func _play_clip(clip: String) -> void:
	if _anim == null or clip == "" or clip == _current_clip:
		return
	if not _anim.has_animation(clip):
		return
	_anim.play(clip)
	_current_clip = clip


func _ensure_input_map() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("sprint", [KEY_SHIFT])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _load_model() -> void:
	for child in _visual_root.get_children():
		child.queue_free()
	_anim = null
	_using_rig = false
	_clip_idle = ""
	_clip_walk = ""
	_clip_run = ""
	_current_clip = ""

	if ResourceLoader.exists(ANIMATED_PATH):
		var packed := load(ANIMATED_PATH) as PackedScene
		if packed != null:
			var model := packed.instantiate() as Node3D
			_visual_root.add_child(model)
			model.scale = Vector3.ONE * MODEL_SCALE
			_warm_skin(model)
			_wire_anim(model)
			if _using_rig:
				_label.text = "Walk / Run\nWASD + Shift"
				return

	var fallback: PackedScene = null
	if ResourceLoader.exists(WALKER_PATH):
		fallback = load(WALKER_PATH) as PackedScene
	elif ResourceLoader.exists(SETTLER_PATH):
		fallback = load(SETTLER_PATH) as PackedScene
	if fallback != null:
		var model := fallback.instantiate() as Node3D
		_visual_root.add_child(model)
		_label.text = "Static + bob\nWASD + Shift"
		return

	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.2
	mesh_instance.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.55, 0.35)
	mesh_instance.material_override = mat
	mesh_instance.position.y = 0.6
	_visual_root.add_child(mesh_instance)
	_label.text = "Placeholder"


func _wire_anim(model: Node3D) -> void:
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		return
	_clip_idle = _find_clip("Idle")
	_clip_walk = _find_clip("Walk")
	_clip_run = _find_clip("Run")
	if _clip_idle == "" and _clip_walk == "" and _clip_run == "":
		_anim = null
		return
	for clip in [_clip_idle, _clip_walk, _clip_run]:
		if clip == "":
			continue
		var a: Animation = _anim.get_animation(clip)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
	_using_rig = true
	_play_clip(_clip_idle if _clip_idle != "" else _clip_walk)


func _find_clip(suffix: String) -> String:
	if _anim == null:
		return ""
	for libname in _anim.get_animation_library_list():
		var lib: AnimationLibrary = _anim.get_animation_library(libname)
		if lib == null:
			continue
		for an in lib.get_animation_list():
			if String(an).ends_with(suffix):
				var ln := String(libname)
				if ln == "" or ln == "default":
					if _anim.has_animation(String(an)):
						return String(an)
					return ln + "/" + String(an) if ln != "" else String(an)
				var qualified := ln + "/" + String(an)
				if _anim.has_animation(qualified):
					return qualified
				if _anim.has_animation(String(an)):
					return String(an)
				return qualified
	for an in _anim.get_animation_list():
		if String(an).ends_with(suffix):
			return String(an)
	return ""


func _warm_skin(target: Node3D) -> void:
	var stack: Array = [target]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh := mi.mesh
			if mesh != null:
				for si in range(mesh.get_surface_count()):
					var src: Material = mi.get_surface_override_material(si)
					if src == null:
						src = mesh.surface_get_material(si)
					var sm: StandardMaterial3D
					if src is StandardMaterial3D:
						sm = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					else:
						sm = StandardMaterial3D.new()
					sm.albedo_color = Color(0.52, 0.38, 0.28)
					sm.roughness = 0.92
					sm.metallic = 0.0
					mi.set_surface_override_material(si, sm)
		for ch in n.get_children():
			stack.append(ch)
