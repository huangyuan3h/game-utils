class_name WorkIKSolver
extends RefCounted
## Procedural 2-bone IK solver for character work actions:
##   - gather: kneeling/squatting reach & scoop
##   - mine: two-handed overhead pickaxe swing
##   - chop: side-twisting horizontal/diagonal axe chop
##   - build: crouched artisan hammer double-tap

const WORK_SMOOTH := 18.0

var _skeleton: Skeleton3D = null
var _limb_len: Dictionary = {} ## "Left"/"Right" -> {"arm": Vector2, "leg": Vector2}
var _hips_idx: int = -1
var _hips_rest_pos: Vector3 = Vector3.ZERO
var _foot_rest_y: float = 0.0


func bind_skeleton(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_limb_len = LimbIKUtil.cache_limb_lengths(skeleton)
	_hips_idx = -1
	_hips_rest_pos = Vector3.ZERO
	_foot_rest_y = 0.0
	if _skeleton != null:
		_hips_idx = _skeleton.find_bone("Hips")
		if _hips_idx >= 0:
			_hips_rest_pos = _skeleton.get_bone_rest(_hips_idx).origin
		var l_foot := _skeleton.find_bone("LeftFoot")
		if l_foot >= 0:
			_foot_rest_y = _skeleton.get_bone_global_rest(l_foot).origin.y


func has_valid_rig() -> bool:
	return _skeleton != null and not _limb_len.is_empty()


func reset_poses() -> void:
	if _skeleton != null:
		_skeleton.reset_bone_poses()


func apply_work(profile: StringName, cycle_phase: float, blend_weight: float, delta: float) -> void:
	if _skeleton == null or _limb_len.is_empty():
		return
	var w := clampf(blend_weight, 0.0, 1.0)
	if w <= 0.001:
		return

	var bone_count := _skeleton.get_bone_count()
	var prev_rots: Array[Quaternion] = []
	prev_rots.resize(bone_count)
	for i in range(bone_count):
		prev_rots[i] = _skeleton.get_bone_pose_rotation(i)
	var prev_hips_pos := _skeleton.get_bone_pose_position(_hips_idx) if _hips_idx >= 0 else Vector3.ZERO

	_skeleton.reset_bone_poses()

	var p := fposmod(cycle_phase, 1.0)
	var leg_total := _avg_leg_total()

	match profile:
		&"gather":
			_pose_gather(p, leg_total)
		&"mine":
			_pose_mine(p, leg_total)
		&"chop":
			_pose_chop(p, leg_total)
		&"build":
			_pose_build(p, leg_total)
		_:
			_pose_gather(p, leg_total)

	var alpha := clampf((1.0 - exp(-WORK_SMOOTH * maxf(delta, 0.001))) * w, 0.0, 1.0)
	if delta <= 0.0:
		alpha = w
	for i in range(bone_count):
		var target_rot := _skeleton.get_bone_pose_rotation(i)
		_skeleton.set_bone_pose_rotation(i, prev_rots[i].slerp(target_rot, alpha))
	if _hips_idx >= 0:
		var target_hips_pos := _skeleton.get_bone_pose_position(_hips_idx)
		_skeleton.set_bone_pose_position(_hips_idx, prev_hips_pos.lerp(target_hips_pos, alpha))


func _pose_gather(p: float, leg_total: float) -> void:
	var scoop := sin(clampf((p - 0.20) / 0.50, 0.0, 1.0) * PI)
	var hips_yaw := lerpf(0.05, -0.14, scoop)
	var hips_drop := (0.24 + 0.06 * scoop) * leg_total
	_set_hips(hips_yaw, 0.0, -hips_drop)

	_set_spine(0.20 + 0.14 * scoop, -0.10 * scoop, 0.0)
	_set_neck(0.24 + 0.12 * scoop, 0.0)

	_pose_planted_leg("Left", 1.0, 0.14, 0.18, leg_total)
	_pose_planted_leg("Right", -1.0, 0.18, -0.16, leg_total)

	# Right arm reaches down to ground, scoops (hit ~0.56), lifts toward pouch
	var r_keys: Array[Vector3] = [
		Vector3(-0.22, -0.35, 0.48),
		Vector3(-0.14, -0.78, 0.62),
		Vector3(-0.04, -0.84, 0.72),
		Vector3(-0.08, -0.30, 0.44),
		Vector3(-0.20, -0.34, 0.46),
	]
	var r_marks: Array[float] = [0.0, 0.28, 0.56, 0.78, 0.96]
	var r_dir := _eval_cycle(r_keys, r_marks, p).normalized()
	var r_reach := lerpf(0.78, 0.94, scoop)
	_pose_arm_dir("Right", -1.0, r_dir, r_reach, Vector3(-0.85, 0.15, -0.45))

	# Left arm braces lightly near knee/pouch
	var l_dir := Vector3(0.28, -0.58 - 0.08 * scoop, 0.52).normalized()
	_pose_arm_dir("Left", 1.0, l_dir, 0.76, Vector3(0.85, 0.10, -0.40))


func _pose_mine(p: float, leg_total: float) -> void:
	# Windup (0..0.36) -> Strike (0.36..0.58) -> Follow-through & recover
	var windup := _smooth_window(p, 0.0, 0.36)
	var strike := _smooth_window(p, 0.36, 0.58)
	var spine_pitch := lerpf(-0.26, 0.34, strike) * windup + lerpf(0.34, 0.04, _smooth_window(p, 0.58, 1.0)) * (1.0 - (1.0 - strike) * (1.0 - _smooth_window(p, 0.58, 1.0)))
	# Simpler crisp keyframed spine pitch
	var pitch_val := _eval_scalar([0.04, -0.24, 0.32, 0.20, 0.05], [0.0, 0.34, 0.58, 0.74, 0.96], p)
	var twist_val := _eval_scalar([-0.06, -0.22, 0.14, 0.08, -0.05], [0.0, 0.34, 0.58, 0.74, 0.96], p)

	_set_hips(-0.12 + twist_val * 0.35, 0.0, -(0.09 + 0.05 * maxf(0.0, pitch_val)) * leg_total)
	_set_spine(pitch_val, twist_val, 0.0)
	_set_neck(clampf(-pitch_val * 0.45 + 0.14, -0.25, 0.32), -twist_val * 0.4)

	_pose_planted_leg("Left", 1.0, 0.16, 0.18, leg_total)
	_pose_planted_leg("Right", -1.0, 0.18, -0.20, leg_total)

	# Both hands move in unison holding the pickaxe handle
	var r_keys: Array[Vector3] = [
		Vector3(-0.16, -0.05, 0.62),  # ready
		Vector3(-0.20, 0.88, -0.10),  # overhead windup
		Vector3(-0.08, -0.44, 0.82),  # impact at 0.58
		Vector3(-0.10, -0.28, 0.74),  # rebound
		Vector3(-0.16, -0.06, 0.64),  # recover
	]
	var marks: Array[float] = [0.0, 0.36, 0.58, 0.72, 0.96]
	var r_dir := _eval_cycle(r_keys, marks, p).normalized()
	var reach := _eval_scalar([0.78, 0.86, 0.95, 0.88, 0.78], marks, p)
	var r_hand := _pose_arm_dir("Right", -1.0, r_dir, reach, Vector3(-0.75, 0.20, -0.60))

	# Left hand grips slightly below/left of right hand
	var l_target := r_hand + Vector3(0.0025, -0.0022, -0.0018)
	_pose_arm_target("Left", 1.0, l_target, Vector3(0.75, 0.10, -0.55))


func _pose_chop(p: float, leg_total: float) -> void:
	var marks: Array[float] = [0.0, 0.34, 0.55, 0.74, 0.96]
	var twist_val := _eval_scalar([-0.14, -0.42, 0.34, 0.22, -0.12], marks, p)
	var pitch_val := _eval_scalar([0.08, 0.04, 0.18, 0.12, 0.08], marks, p)

	_set_hips(twist_val * 0.38, 0.0, -0.09 * leg_total)
	_set_spine(pitch_val, twist_val, 0.0)
	_set_neck(0.10, -twist_val * 0.55)

	_pose_planted_leg("Left", 1.0, 0.18, 0.15, leg_total)
	_pose_planted_leg("Right", -1.0, 0.20, -0.18, leg_total)

	# Horizontal-diagonal axe swing from right-back across front-center to left
	var r_keys: Array[Vector3] = [
		Vector3(-0.28, 0.08, 0.56),   # ready
		Vector3(-0.78, 0.34, -0.18),  # cocked back right
		Vector3(0.18, 0.06, 0.88),    # chop impact at 0.55
		Vector3(0.52, -0.02, 0.56),   # follow through left
		Vector3(-0.24, 0.06, 0.56),   # reset
	]
	var r_dir := _eval_cycle(r_keys, marks, p).normalized()
	var reach := _eval_scalar([0.80, 0.86, 0.95, 0.88, 0.80], marks, p)
	var r_hand := _pose_arm_dir("Right", -1.0, r_dir, reach, Vector3(-0.85, -0.10, -0.45))

	var l_target := r_hand + Vector3(0.0022, -0.0018, -0.0020)
	_pose_arm_target("Left", 1.0, l_target, Vector3(0.85, -0.15, -0.40))


func _pose_build(p: float, leg_total: float) -> void:
	# Double hammer strike aligned with hit_phases = [0.42, 0.80]
	var marks: Array[float] = [0.0, 0.22, 0.42, 0.54, 0.66, 0.80, 0.94]
	var tap_dip := _eval_scalar([0.0, -0.06, 0.14, 0.02, -0.05, 0.14, 0.0], marks, p)

	_set_hips(0.10, 0.0, -0.17 * leg_total)
	_set_spine(0.20 + tap_dip * 0.45, -0.08, 0.0)
	_set_neck(0.22 + tap_dip * 0.40, 0.04)

	_pose_planted_leg("Left", 1.0, 0.16, 0.14, leg_total)
	_pose_planted_leg("Right", -1.0, 0.18, -0.15, leg_total)

	# Right hand hammers twice cleanly
	var r_keys: Array[Vector3] = [
		Vector3(-0.14, 0.08, 0.66),
		Vector3(-0.18, 0.46, 0.52),   # raise 1
		Vector3(-0.08, -0.22, 0.82),  # hit 1 (0.42)
		Vector3(-0.12, 0.06, 0.72),   # rebound
		Vector3(-0.18, 0.42, 0.54),   # raise 2
		Vector3(-0.08, -0.24, 0.82),  # hit 2 (0.80)
		Vector3(-0.14, 0.08, 0.68),   # reset
	]
	var r_dir := _eval_cycle(r_keys, marks, p).normalized()
	var reach := _eval_scalar([0.80, 0.76, 0.92, 0.82, 0.76, 0.92, 0.80], marks, p)
	_pose_arm_dir("Right", -1.0, r_dir, reach, Vector3(-0.75, 0.15, -0.60))

	# Left hand holds workpiece steady in front
	var l_dir := Vector3(0.18, -0.14, 0.76).normalized()
	_pose_arm_dir("Left", 1.0, l_dir, 0.80, Vector3(0.85, 0.05, -0.45))


func _set_hips(yaw: float, pitch: float, y_offset: float) -> void:
	if _hips_idx < 0:
		return
	var rot := Quaternion(Vector3.UP, yaw) * Quaternion(Vector3.RIGHT, pitch)
	_skeleton.set_bone_pose_rotation(_hips_idx, rot)
	_skeleton.set_bone_pose_position(_hips_idx, _hips_rest_pos + Vector3(0.0, y_offset, 0.0))


func _set_spine(pitch: float, yaw: float, roll: float) -> void:
	var segs := ["Spine", "Spine1", "Spine2"]
	var weights := [0.28, 0.36, 0.36]
	for i in segs.size():
		var sb := _skeleton.find_bone(segs[i])
		if sb < 0:
			continue
		var r := _skeleton.get_bone_rest(sb).basis.get_rotation_quaternion()
		var w: float = weights[i]
		var q := Quaternion(Vector3.RIGHT, pitch * w) * Quaternion(Vector3.UP, yaw * w) * Quaternion(Vector3.FORWARD, roll * w)
		_skeleton.set_bone_pose_rotation(sb, q * r)


func _set_neck(pitch: float, yaw: float) -> void:
	var neck := _skeleton.find_bone("Neck")
	if neck < 0:
		return
	var nr := _skeleton.get_bone_rest(neck).basis.get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(
		neck,
		Quaternion(Vector3.RIGHT, pitch) * Quaternion(Vector3.UP, yaw) * nr
	)


func _pose_arm_dir(side: String, side_sign: float, dir: Vector3, reach_ratio: float, pole_off: Vector3) -> Vector3:
	if not _limb_len.has(side):
		return Vector3.ZERO
	var upper := _skeleton.find_bone(side + "Arm")
	var fore := _skeleton.find_bone(side + "ForeArm")
	if upper < 0 or fore < 0:
		return Vector3.ZERO
	var lens: Vector2 = _limb_len[side]["arm"]
	var origin := LimbIKUtil.bone_global_pose(_skeleton, upper).origin
	var total := lens.x + lens.y
	var target := origin + dir.normalized() * (total * clampf(reach_ratio, 0.35, 0.98))
	var pole := origin + pole_off * total
	LimbIKUtil.two_bone(_skeleton, upper, fore, origin, target, pole, lens.x, lens.y)
	_pose_hand(side, side_sign, target, fore)
	return target


func _pose_arm_target(side: String, side_sign: float, target: Vector3, pole_off: Vector3) -> void:
	if not _limb_len.has(side):
		return
	var upper := _skeleton.find_bone(side + "Arm")
	var fore := _skeleton.find_bone(side + "ForeArm")
	if upper < 0 or fore < 0:
		return
	var lens: Vector2 = _limb_len[side]["arm"]
	var origin := LimbIKUtil.bone_global_pose(_skeleton, upper).origin
	var total := lens.x + lens.y
	var pole := origin + pole_off * total
	LimbIKUtil.two_bone(_skeleton, upper, fore, origin, target, pole, lens.x, lens.y)
	_pose_hand(side, side_sign, target, fore)


func _pose_hand(side: String, _side_sign: float, target: Vector3, fore: int) -> void:
	var hand := _skeleton.find_bone(side + "Hand")
	if hand < 0:
		return
	var fore_origin := LimbIKUtil.bone_global_pose(_skeleton, fore).origin
	var aim := (target - fore_origin).normalized()
	if aim.length_squared() > 0.001:
		LimbIKUtil.aim_bone_y(_skeleton, hand, aim)


func _pose_planted_leg(side: String, side_sign: float, x_spread: float, z_offset: float, leg_total: float) -> void:
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
	var origin := LimbIKUtil.bone_global_pose(_skeleton, thigh).origin
	var foot_target := Vector3(
		origin.x + side_sign * x_spread * leg_total,
		_foot_rest_y + 0.04 * leg_total,
		z_offset * leg_total
	)
	var pole := origin + Vector3(side_sign * 0.25 * leg_total, -0.10 * leg_total, 0.90 * leg_total)
	LimbIKUtil.two_bone(_skeleton, thigh, shin, origin, foot_target, pole, lens.x, lens.y)
	if foot >= 0:
		LimbIKUtil.aim_bone_y(_skeleton, foot, Vector3(side_sign * 0.06, -0.25, 0.96).normalized())


func _avg_leg_total() -> float:
	for side in ["Left", "Right"]:
		if _limb_len.has(side):
			var leg: Vector2 = _limb_len[side]["leg"]
			if leg.x + leg.y > 0.0001:
				return leg.x + leg.y
	return 0.036


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


func _eval_scalar(vals: Array[float], marks: Array[float], phase: float) -> float:
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
	return lerpf(vals[i], vals[j], u)


func _smooth_window(p: float, start_p: float, end_p: float) -> float:
	if end_p <= start_p:
		return 0.0
	var u := clampf((p - start_p) / (end_p - start_p), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)
