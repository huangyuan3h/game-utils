class_name SwimIKSolver
extends RefCounted
## Procedural 2-bone IK solver for front-crawl swimming and treading water.

const SWIM_SPINE_ROLL := 0.12
const SWIM_STROKE_SMOOTH := 14.0

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


func apply_freestyle(swim_phase: float, swim_move: float, swim_t: float, delta: float) -> void:
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
	if hips >= 0:
		_skeleton.set_bone_pose_rotation(hips, Quaternion.IDENTITY)

	var spine_roll := sin(swim_phase * TAU) * SWIM_SPINE_ROLL * swim_move
	for sname in ["Spine1", "Spine2"]:
		var sb := _skeleton.find_bone(sname)
		if sb >= 0:
			var r := _skeleton.get_bone_rest(sb).basis.get_rotation_quaternion()
			_skeleton.set_bone_pose_rotation(sb, Quaternion(Vector3.UP, spine_roll * 0.5) * r)

	var neck := _skeleton.find_bone("Neck")
	if neck >= 0:
		var nr := _skeleton.get_bone_rest(neck).basis.get_rotation_quaternion()
		var look_up := lerpf(-0.34, -0.26, swim_move)
		_skeleton.set_bone_pose_rotation(
			neck,
			Quaternion(Vector3.RIGHT, look_up) * Quaternion(Vector3.UP, -spine_roll * 1.4) * nr
		)

	_pose_crawl_arm("Right", swim_phase, -1.0, swim_move, swim_t)
	_pose_crawl_arm("Left", fposmod(swim_phase + 0.5, 1.0), 1.0, swim_move, swim_t)
	var flutter := lerpf(sin(swim_t * 1.4), sin(swim_phase * TAU * 2.0), swim_move)
	_pose_flutter_leg("Right", -flutter, -1.0, swim_move)
	_pose_flutter_leg("Left", flutter, 1.0, swim_move)

	var alpha := 1.0 - exp(-SWIM_STROKE_SMOOTH * delta)
	for i in range(bone_count):
		var target_rot := _skeleton.get_bone_pose_rotation(i)
		_skeleton.set_bone_pose_rotation(i, prev_rots[i].slerp(target_rot, alpha))


func _crawl_hand_offset(phase: float, side: float) -> Vector3:
	var keys: Array[Vector3] = [
		Vector3(side * 0.14, 0.94, 0.04),
		Vector3(side * 0.12, 0.62, 0.42),
		Vector3(side * 0.08, -0.28, 0.56),
		Vector3(side * 0.22, -0.88, 0.12),
		Vector3(side * 0.44, 0.02, -0.24),
		Vector3(side * 0.22, 0.72, -0.14),
	]
	var marks: Array[float] = [0.0, 0.16, 0.36, 0.52, 0.72, 0.88]
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


func _crawl_arm_reach(phase: float) -> float:
	var p := fposmod(phase, 1.0)
	var rec := sin(clampf((p - 0.52) / 0.36, 0.0, 1.0) * PI)
	return lerpf(0.95, 0.72, rec)


func _pose_crawl_arm(side: String, phase: float, side_sign: float, swim_move: float, swim_t: float) -> void:
	if not _limb_len.has(side):
		return
	var upper := _skeleton.find_bone(side + "Arm")
	var fore := _skeleton.find_bone(side + "ForeArm")
	if upper < 0 or fore < 0:
		return
	var lens: Vector2 = _limb_len[side]["arm"]
	var origin: Vector3 = LimbIKUtil.bone_global_pose(_skeleton, upper).origin
	var total := lens.x + lens.y
	var crawl_dir := _crawl_hand_offset(phase, side_sign).normalized()
	var crawl_target := origin + crawl_dir * (total * _crawl_arm_reach(phase))
	var scull := Vector3(
		side_sign * (0.56 + 0.16 * sin(swim_t * 1.1)),
		-0.08 + 0.12 * cos(swim_t * 1.1),
		0.45 + 0.10 * sin(swim_t * 1.1)
	).normalized()
	var tread_target := origin + scull * (total * 0.78)
	var target := tread_target.lerp(crawl_target, swim_move)
	var pole := origin + Vector3(side_sign * 0.85, 0.15, -0.95)
	LimbIKUtil.two_bone(_skeleton, upper, fore, origin, target, pole, lens.x, lens.y)


func _pose_flutter_leg(side: String, flutter: float, side_sign: float, swim_move: float) -> void:
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
	var amp := lerpf(0.14, 0.22, swim_move)
	var leg_dir := Vector3(side_sign * 0.04, -1.0, amp * flutter - 0.03).normalized()
	var upbeat := maxf(0.0, -flutter)
	var straight := lerpf(0.997, 0.986, upbeat * swim_move)
	var foot_target := origin + leg_dir * ((lens.x + lens.y) * straight)
	var pole := origin + Vector3(side_sign * 0.04, -0.35, 1.0)
	LimbIKUtil.two_bone(_skeleton, thigh, shin, origin, foot_target, pole, lens.x, lens.y)
	if foot >= 0:
		var shin_dir := (foot_target - LimbIKUtil.bone_global_pose(_skeleton, shin).origin).normalized()
		LimbIKUtil.aim_bone_y(_skeleton, foot, (shin_dir + Vector3(0.0, 0.0, 0.28)).normalized())
