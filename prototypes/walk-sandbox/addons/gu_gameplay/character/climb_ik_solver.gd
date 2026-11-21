class_name ClimbIKSolver
extends RefCounted
## Procedural 2-bone IK solver for steep cliff climbing and rock-face clinging.
## Uses contralateral diagonal limb coordination (Right Arm + Left Leg, Left Arm + Right Leg).

const CLIMB_SPINE_TWIST := 0.14
const CLIMB_HIP_YAW := 0.10
const CLIMB_SMOOTH := 16.0

var _skeleton: Skeleton3D = null
var _limb_len: Dictionary = {} ## "Left"/"Right" -> {"arm": Vector2, "leg": Vector2}


func bind_skeleton(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_limb_len = LimbIKUtil.cache_limb_lengths(skeleton)


func has_valid_rig() -> bool:
	return _skeleton != null and not _limb_len.is_empty()


func reset_poses() -> void:
	if _skeleton != null:
		_skeleton.reset_bone_poses()


func apply_climb(
	climb_phase: float,
	climb_move: float,
	climb_t: float,
	climb_lateral: float,
	delta: float
) -> void:
	if _skeleton == null or _limb_len.is_empty():
		return
	var bone_count := _skeleton.get_bone_count()
	var prev_rots: Array[Quaternion] = []
	prev_rots.resize(bone_count)
	for i in range(bone_count):
		prev_rots[i] = _skeleton.get_bone_pose_rotation(i)

	_skeleton.reset_bone_poses()
	# Hips rest pose in AnimatedHuman.fbx has a ~43.5 deg yaw; align Hips to +Z forward.
	var hips := _skeleton.find_bone("Hips")
	var hip_yaw := sin(climb_phase * TAU) * CLIMB_HIP_YAW * climb_move
	if hips >= 0:
		_skeleton.set_bone_pose_rotation(hips, Quaternion(Vector3.UP, hip_yaw))

	var spine_twist := sin(climb_phase * TAU) * CLIMB_SPINE_TWIST * climb_move
	for sname in ["Spine", "Spine1", "Spine2"]:
		var sb := _skeleton.find_bone(sname)
		if sb >= 0:
			var r := _skeleton.get_bone_rest(sb).basis.get_rotation_quaternion()
			var arch := Quaternion(Vector3.RIGHT, 0.05)
			_skeleton.set_bone_pose_rotation(sb, arch * Quaternion(Vector3.UP, spine_twist * 0.4) * r)

	var neck := _skeleton.find_bone("Neck")
	if neck >= 0:
		var nr := _skeleton.get_bone_rest(neck).basis.get_rotation_quaternion()
		var look_up := lerpf(-0.28, -0.40, climb_move)
		var look_side := -spine_twist * 0.9
		_skeleton.set_bone_pose_rotation(
			neck,
			Quaternion(Vector3.RIGHT, look_up) * Quaternion(Vector3.UP, look_side) * nr
		)

	# Contralateral climbing pattern:
	# Right Arm + Left Leg move on `climb_phase`; Left Arm + Right Leg move half a cycle offset.
	var phase_opp := fposmod(climb_phase + 0.5, 1.0)
	_pose_climb_arm("Right", climb_phase, -1.0, climb_move, climb_t, climb_lateral)
	_pose_climb_arm("Left", phase_opp, 1.0, climb_move, climb_t, climb_lateral)
	_pose_climb_leg("Left", climb_phase, 1.0, climb_move, climb_t, climb_lateral)
	_pose_climb_leg("Right", phase_opp, -1.0, climb_move, climb_t, climb_lateral)

	var alpha := 1.0 - exp(-CLIMB_SMOOTH * delta)
	for i in range(bone_count):
		var target_rot := _skeleton.get_bone_pose_rotation(i)
		_skeleton.set_bone_pose_rotation(i, prev_rots[i].slerp(target_rot, alpha))


func _arm_cycle_offset(phase: float, side_sign: float, climb_lateral: float) -> Vector3:
	# Keyframes in shoulder-local direction:
	# +Y = reach overhead, +Z = toward cliff face, +X = character left.
	var lat := climb_lateral * 0.16
	var keys: Array[Vector3] = [
		Vector3(side_sign * 0.24, -0.05, 0.30),             # 0.00: bottom of pull, release hold
		Vector3(side_sign * 0.30 + lat, 0.45, 0.16),        # 0.22: lift hand away from rock, reach up
		Vector3(side_sign * 0.22 + lat, 0.86, 0.28),        # 0.45: grab high handhold on cliff
		Vector3(side_sign * 0.22, 0.52, 0.30),              # 0.72: pull body upward along cliff
		Vector3(side_sign * 0.24, 0.15, 0.30),              # 0.90: finish pull
	]
	var marks: Array[float] = [0.0, 0.22, 0.45, 0.72, 0.90]
	return _eval_cycle(keys, marks, phase)


func _arm_reach_factor(phase: float) -> float:
	var p := fposmod(phase, 1.0)
	# Slightly bent elbow during mid-reach (0.22) and end of pull; fuller extension at high grab (0.45).
	var reach_peak := exp(-pow((p - 0.45) / 0.18, 2.0))
	return lerpf(0.76, 0.94, reach_peak)


func _leg_cycle_offset(phase: float, side_sign: float, climb_lateral: float) -> Vector3:
	# Keyframes in hip-local direction:
	# -Y = down, +Z = forward onto rock footholds, +X = character left (knee flares out).
	var lat := climb_lateral * 0.14
	var keys: Array[Vector3] = [
		Vector3(side_sign * 0.14, -0.92, 0.12),             # 0.00: leg extended after push
		Vector3(side_sign * 0.24 + lat, -0.62, 0.16),       # 0.22: tuck knee, lift foot off rock
		Vector3(side_sign * 0.20 + lat, -0.44, 0.30),       # 0.45: plant foot high on foothold
		Vector3(side_sign * 0.16, -0.72, 0.22),             # 0.72: push body upward
		Vector3(side_sign * 0.14, -0.88, 0.14),             # 0.90: finish leg drive
	]
	var marks: Array[float] = [0.0, 0.22, 0.45, 0.72, 0.90]
	return _eval_cycle(keys, marks, phase)


func _leg_reach_factor(phase: float) -> float:
	var p := fposmod(phase, 1.0)
	# Bend knee sharply when stepping up (p ~ 0.35..0.50), extend when pushing off (p ~ 0.95).
	var tuck := exp(-pow((p - 0.40) / 0.20, 2.0))
	return lerpf(0.95, 0.68, tuck)


func _eval_cycle(keys: Array[Vector3], marks: Array[float], phase: float) -> Vector3:
	var p := fposmod(phase, 1.0)
	var i := 0
	for k in range(marks.size()):
		if marks[k] <= p:
			i = k
	var j := (i + 1) % marks.size()
	var span := fposmod(marks[j] - marks[i], 1.0)
	if span < 0.001:
		span = 1.0
	var u := fposmod(p - marks[i], 1.0) / span
	u = u * u * (3.0 - 2.0 * u)
	return keys[i].lerp(keys[j], u)


func _pose_climb_arm(
	side: String,
	phase: float,
	side_sign: float,
	climb_move: float,
	climb_t: float,
	climb_lateral: float
) -> void:
	if not _limb_len.has(side):
		return
	var upper := _skeleton.find_bone(side + "Arm")
	var fore := _skeleton.find_bone(side + "ForeArm")
	if upper < 0 or fore < 0:
		return
	var lens: Vector2 = _limb_len[side]["arm"]
	var origin: Vector3 = LimbIKUtil.bone_global_pose(_skeleton, upper).origin
	var total := lens.x + lens.y

	var move_dir := _arm_cycle_offset(phase, side_sign, climb_lateral).normalized()
	var move_target := origin + move_dir * (total * _arm_reach_factor(phase))

	# Idle clinging pose: steady asymmetric rock grip with subtle breathing sway
	var idle_y := 0.56 if side_sign > 0.0 else 0.38
	var breathe := sin(climb_t * 1.4 + side_sign * 0.6) * 0.025
	var idle_dir := Vector3(side_sign * 0.28, idle_y + breathe, 0.30).normalized()
	var idle_target := origin + idle_dir * (total * 0.82)

	var target := idle_target.lerp(move_target, climb_move)
	var pole := origin + Vector3(side_sign * 0.85, -0.35, -0.65)
	LimbIKUtil.two_bone(_skeleton, upper, fore, origin, target, pole, lens.x, lens.y)


func _pose_climb_leg(
	side: String,
	phase: float,
	side_sign: float,
	climb_move: float,
	climb_t: float,
	climb_lateral: float
) -> void:
	if not _limb_len.has(side):
		return
	var lens: Vector2 = _limb_len[side]["leg"]
	if lens.x < 0.0001 or lens.y < 0.0001:
		return
	var thigh := _skeleton.find_bone(side + "UpLeg")
	var shin := _skeleton.find_bone(side + "Leg")
	var foot := _skeleton.find_bone(side + "Foot")
	if thigh < 0 or shin < 0:
		return
	var origin: Vector3 = LimbIKUtil.bone_global_pose(_skeleton, thigh).origin
	var total := lens.x + lens.y

	var move_dir := _leg_cycle_offset(phase, side_sign, climb_lateral).normalized()
	var move_target := origin + move_dir * (total * _leg_reach_factor(phase))

	# Idle foothold stance: knees slightly bent, bracing against the rock face
	var idle_y := -0.62 if side_sign < 0.0 else -0.78
	var brace := sin(climb_t * 1.4) * 0.015
	var idle_dir := Vector3(side_sign * 0.18, idle_y + brace, 0.22).normalized()
	var idle_target := origin + idle_dir * (total * 0.80)

	var foot_target := idle_target.lerp(move_target, climb_move)
	var pole := origin + Vector3(side_sign * 0.45, -0.15, 1.0)
	LimbIKUtil.two_bone(_skeleton, thigh, shin, origin, foot_target, pole, lens.x, lens.y)
	if foot >= 0:
		var shin_dir := (foot_target - LimbIKUtil.bone_global_pose(_skeleton, shin).origin).normalized()
		LimbIKUtil.aim_bone_y(_skeleton, foot, (shin_dir + Vector3(0.0, -0.15, 0.28)).normalized())
