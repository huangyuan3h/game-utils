class_name AiPerception
extends RefCounted
## Vision cone and hearing checks. Callers supply positions; this type does not touch navigation or animation.

static func in_cone(
	origin: Vector3,
	forward: Vector3,
	target: Vector3,
	max_range: float,
	half_angle_deg: float
) -> bool:
	var offset := target - origin
	var distance := offset.length()
	if distance > max_range or distance <= 0.001 or forward.length_squared() <= 0.001:
		return false
	var facing := rad_to_deg(acos(clampf(forward.normalized().dot(offset / distance), -1.0, 1.0)))
	return facing <= half_angle_deg


static func hears(origin: Vector3, noise_at: Vector3, hearing_range: float) -> bool:
	return origin.distance_to(noise_at) <= hearing_range
