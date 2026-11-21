class_name LimbIKUtil
extends RefCounted
## Shared 2-bone analytical IK and skeleton pose utilities for procedural rig solvers.


static func cache_limb_lengths(skeleton: Skeleton3D) -> Dictionary:
	var result: Dictionary = {}
	if skeleton == null:
		return result
	for side in ["Left", "Right"]:
		var upper := skeleton.find_bone(side + "Arm")
		var fore := skeleton.find_bone(side + "ForeArm")
		var hand := skeleton.find_bone(side + "Hand")
		var thigh := skeleton.find_bone(side + "UpLeg")
		var shin := skeleton.find_bone(side + "Leg")
		var foot := skeleton.find_bone(side + "Foot")
		if upper < 0 or fore < 0 or hand < 0:
			continue
		var l1 := skeleton.get_bone_global_rest(upper).origin.distance_to(skeleton.get_bone_global_rest(fore).origin)
		var l2 := skeleton.get_bone_global_rest(fore).origin.distance_to(skeleton.get_bone_global_rest(hand).origin)
		var t1 := 0.0
		var t2 := 0.0
		if thigh >= 0 and shin >= 0 and foot >= 0:
			t1 = skeleton.get_bone_global_rest(thigh).origin.distance_to(skeleton.get_bone_global_rest(shin).origin)
			t2 = skeleton.get_bone_global_rest(shin).origin.distance_to(skeleton.get_bone_global_rest(foot).origin)
		result[side] = {"arm": Vector2(l1, l2), "leg": Vector2(t1, t2)}
	return result


static func bone_global_pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var cur := bone
	while cur >= 0:
		xform = skeleton.get_bone_pose(cur) * xform
		cur = skeleton.get_bone_parent(cur)
	return xform


static func two_bone(
	skeleton: Skeleton3D,
	bone_a: int,
	bone_b: int,
	root: Vector3,
	target: Vector3,
	pole: Vector3,
	l1: float,
	l2: float
) -> void:
	var to_t := target - root
	var raw_len := to_t.length()
	if raw_len < 1e-6:
		return
	var dist := clampf(raw_len, absf(l1 - l2) + 0.0001, l1 + l2 - 0.0001)
	var axis := to_t / raw_len
	var hyp := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var height := sqrt(maxf(l1 * l1 - hyp * hyp, 0.0))
	var pole_dir := pole - root
	pole_dir = pole_dir - axis * pole_dir.dot(axis)
	if pole_dir.length_squared() < 1e-8:
		pole_dir = axis.cross(Vector3.UP)
		if pole_dir.length_squared() < 1e-8:
			pole_dir = axis.cross(Vector3.RIGHT)
	pole_dir = pole_dir.normalized()
	var elbow := root + axis * hyp + pole_dir * height
	aim_bone_y(skeleton, bone_a, elbow - root)
	aim_bone_y(skeleton, bone_b, target - elbow)


static func aim_bone_y(skeleton: Skeleton3D, bone: int, direction: Vector3) -> void:
	if direction.length_squared() < 1e-10:
		return
	var parent := skeleton.get_bone_parent(bone)
	var parent_global := Transform3D.IDENTITY
	if parent >= 0:
		parent_global = bone_global_pose(skeleton, parent)
	var rest_local := skeleton.get_bone_rest(bone)
	var rest_global := parent_global * rest_local
	var swing := quat_from_to(rest_global.basis.y, direction)
	var desired_basis := Basis(swing) * rest_global.basis
	var local_basis := parent_global.basis.inverse() * desired_basis
	skeleton.set_bone_pose_rotation(bone, local_basis.get_rotation_quaternion())


static func quat_from_to(a: Vector3, b: Vector3) -> Quaternion:
	var an := a.normalized()
	var bn := b.normalized()
	var d := an.dot(bn)
	if d > 0.9995:
		return Quaternion.IDENTITY
	if d < -0.9995:
		var axis := an.cross(Vector3.FORWARD)
		if axis.length_squared() < 1e-6:
			axis = an.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(an, bn)
