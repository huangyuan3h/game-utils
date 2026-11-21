class_name CharacterVisual
extends Node
## Manages character rig/fallback loading, animation clips, body tilt/bob,
## SwimIKSolver, ClimbIKSolver, WorkIKSolver, and HandToolVisual.

const MODEL_SCALE := 0.30
## Model paths come from the owning scene; the addon ships no art assets.
var animated_path: String = ""
var walker_path: String = ""
var settler_path: String = ""

const SWIM_PITCH := 1.38
const SWIM_IDLE_PITCH := 0.74
const SWIM_PIVOT_Y := 0.70
const SWIM_ROLL := 0.10

enum IKMode { NONE, SWIM, CLIMB, WORK }

var _visual_root: Node3D
var _anim: AnimationPlayer = null
var _clip_idle: String = ""
var _clip_walk: String = ""
var _clip_run: String = ""
var _clip_work: String = ""
var _current_clip: String = ""
var _using_rig: bool = false
var _bob_t: float = 0.0
var _ik_mode: int = IKMode.NONE
var _swim_ik := SwimIKSolver.new()
var _climb_ik := ClimbIKSolver.new()
var _work_ik := WorkIKSolver.new()
var _tool_visual := HandToolVisual.new()
var model_status_text: String = "Placeholder"


func setup(visual_root: Node3D, model_paths: Dictionary = {}) -> void:
	_visual_root = visual_root
	animated_path = str(model_paths.get("animated", ""))
	walker_path = str(model_paths.get("walker", ""))
	settler_path = str(model_paths.get("settler", ""))
	if _tool_visual.get_parent() != self:
		_tool_visual.name = "HandToolVisual"
		add_child(_tool_visual)
	_load_model()


func trigger_action_beat(action_id: StringName) -> void:
	_tool_visual.spawn_impact_burst(action_id, _visual_root)


func update_visual(loco: CharacterLocomotion, delta: float, action_frame: Dictionary = {}) -> void:
	if _visual_root == null or loco == null:
		return

	var is_acting := bool(action_frame.get("is_acting", false))
	var action_blend := float(action_frame.get("blend_weight", 0.0))
	var ik_profile: StringName = action_frame.get("ik_profile", &"") as StringName
	var tool_type := int(action_frame.get("tool_type", CharacterActionSpec.ToolType.NONE))

	var lean := -0.14 * loco.run_amt * (1.0 if loco.is_moving else 0.35)
	if is_acting:
		lean = 0.0
	var target_swim_pitch := lerpf(SWIM_IDLE_PITCH, SWIM_PITCH, loco.swim_move)
	# Lean into the slope like a steep hike. The model is small, so a fraction
	# of the slope angle reads as a scramble without planting the chest in the hill.
	var slope_pitch := clampf(atan(maxf(loco.climb_grade, 0.0)) * 0.55, 0.0, 0.32)
	var target_climb_pitch := slope_pitch
	var pitch := lean * (1.0 - loco.climb_amt) + target_swim_pitch * loco.swim_amt + target_climb_pitch * loco.climb_amt
	var body_roll := sin(loco.swim_phase * TAU) * SWIM_ROLL * loco.swim_amt * loco.swim_move
	var basis := Basis(Vector3.UP, loco.facing_yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, body_roll)
	_visual_root.basis = _visual_root.basis.slerp(basis, 1.0 - exp(-10.0 * delta))

	var bob := 0.0
	if loco.swim_amt > 0.05:
		var swim_bob := lerpf(sin(loco.swim_t * 0.9) * 0.010, sin(loco.swim_phase * TAU * 2.0) * 0.014, loco.swim_move)
		bob = swim_bob * loco.swim_amt
	elif loco.is_moving and not is_acting:
		_bob_t += delta * ((14.0 if loco.is_running else 8.0) + loco.speed_xz * 1.5)
		bob = absf(sin(_bob_t)) * (0.06 if loco.is_running else 0.045)
	else:
		_bob_t = 0.0

	# Keep feet anchored on steep slopes during climb; pivot around chest for run/swim.
	var pivot_y := SWIM_PIVOT_Y * maxf(loco.swim_amt, 1.0 - loco.climb_amt)
	var chest := Vector3(0.0, pivot_y, 0.0)
	var target_pos := chest - _visual_root.basis * chest
	if loco.climb_amt > 0.01:
		# A few centimetres of clearance. A large standoff reads as floating off the hill.
		var climb_offset := Vector3(0.0, 0.015, -0.04) * loco.climb_amt
		target_pos += Basis(Vector3.UP, loco.facing_yaw) * climb_offset
	target_pos.y += bob
	_visual_root.position = _visual_root.position.lerp(target_pos, 1.0 - exp(-8.0 * delta))

	var show_tool := is_acting and loco.swim_amt <= 0.45 and loco.climb_amt <= 0.35
	_tool_visual.set_active_tool(tool_type if show_tool else CharacterActionSpec.ToolType.NONE)

	if _using_rig and _anim != null:
		var desired_mode := IKMode.NONE
		if loco.swim_amt > 0.45:
			desired_mode = IKMode.SWIM
		elif is_acting and _work_ik.has_valid_rig() and ik_profile != &"":
			desired_mode = IKMode.WORK

		if desired_mode != _ik_mode:
			if _ik_mode == IKMode.SWIM:
				_swim_ik.reset_poses()
			elif _ik_mode == IKMode.CLIMB:
				_climb_ik.reset_poses()
			elif _ik_mode == IKMode.WORK:
				_work_ik.reset_poses()
			_ik_mode = desired_mode

		if _ik_mode == IKMode.SWIM:
			if _anim.is_playing():
				_anim.stop()
			_current_clip = ""
			_swim_ik.apply_freestyle(loco.swim_phase, loco.swim_move, loco.swim_t, delta)
		elif _ik_mode == IKMode.CLIMB:
			if _anim.is_playing():
				_anim.stop()
			_current_clip = ""
			_climb_ik.apply_climb(loco.climb_phase, loco.climb_move, loco.climb_t, loco.climb_lateral, delta)
		elif _ik_mode == IKMode.WORK:
			if _anim.is_playing():
				_anim.stop()
			_current_clip = ""
			var cycle_phase := float(action_frame.get("cycle_phase", 0.0))
			_work_ik.apply_work(ik_profile, cycle_phase, maxf(action_blend, 0.15), delta)
		elif is_acting and _clip_work != "":
			_play_clip(_clip_work)
			_anim.speed_scale = 1.1
		else:
			if loco.is_moving:
				if loco.is_running and _clip_run != "":
					_play_clip(_clip_run)
					_anim.speed_scale = clampf(loco.speed_xz / CharacterLocomotion.RUN_SPEED, 0.85, 1.2)
				else:
					_play_clip(_clip_walk if _clip_walk != "" else _clip_run)
					_anim.speed_scale = clampf(loco.speed_xz / CharacterLocomotion.WALK_SPEED, 0.75, 1.25)
			else:
				_play_clip(_clip_idle)
				_anim.speed_scale = 1.0


func _load_model() -> void:
	if _visual_root == null:
		return
	for child in _visual_root.get_children():
		child.queue_free()
	_anim = null
	_using_rig = false
	_ik_mode = IKMode.NONE
	_clip_idle = ""
	_clip_walk = ""
	_clip_run = ""
	_clip_work = ""
	_current_clip = ""
	_tool_visual.cleanup()

	if animated_path != "" and ResourceLoader.exists(animated_path):
		var packed := load(animated_path) as PackedScene
		if packed != null:
			var model := packed.instantiate() as Node3D
			_visual_root.add_child(model)
			model.scale = Vector3.ONE * MODEL_SCALE
			var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
			_swim_ik.bind_skeleton(skel)
			_climb_ik.bind_skeleton(skel)
			_work_ik.bind_skeleton(skel)
			_tool_visual.bind_skeleton(skel)
			_warm_skin(model)
			_wire_anim(model)
			if _using_rig:
				model_status_text = "Walk / Run / Climb / Swim / Actions\nWASD + Shift + 1..4"
				return

	var fallback: PackedScene = null
	if walker_path != "" and ResourceLoader.exists(walker_path):
		fallback = load(walker_path) as PackedScene
	elif settler_path != "" and ResourceLoader.exists(settler_path):
		fallback = load(settler_path) as PackedScene
	if fallback != null:
		var model := fallback.instantiate() as Node3D
		_visual_root.add_child(model)
		model_status_text = "Static + bob\nWASD + Shift"
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
	model_status_text = "Placeholder"


func _wire_anim(model: Node3D) -> void:
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		return
	_clip_idle = _find_clip("Idle")
	_clip_walk = _find_clip("Walk")
	_clip_run = _find_clip("Run")
	_clip_work = _find_clip("Working")
	if _clip_idle == "" and _clip_walk == "" and _clip_run == "":
		_anim = null
		return
	for clip in [_clip_idle, _clip_walk, _clip_run, _clip_work]:
		if clip == "":
			continue
		var a: Animation = _anim.get_animation(clip)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
	_using_rig = true
	_play_clip(_clip_idle if _clip_idle != "" else _clip_walk)


func _play_clip(clip: String) -> void:
	if _anim == null or clip == "" or clip == _current_clip:
		return
	if not _anim.has_animation(clip):
		return
	_anim.play(clip)
	_current_clip = clip


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
