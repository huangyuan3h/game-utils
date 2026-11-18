class_name AiAgent
extends RefCounted
## Patrol, chase, and leash. Movement is a velocity vector; animation stays with the caller.

const PerceptionScript := preload("res://addons/gu_gameplay/ai/perception.gd")
const BlackboardScript := preload("res://addons/gu_gameplay/ai/blackboard.gd")

enum Mode { PATROL, CHASE, LEASH }

var mode: Mode = Mode.PATROL
var leash_timer: float = 0.0
var leash_timeout: float = 1.0
var sight_range: float = 8.0
var sight_angle_deg: float = 50.0
var hearing_range: float = 4.0
var move_speed: float = 2.0
var aggro: Array[StringName] = []
var blackboard = BlackboardScript.new()


func add_aggro(target_id: StringName) -> void:
	if target_id != &"" and not aggro.has(target_id):
		aggro.append(target_id)


func tick(
	delta: float,
	origin: Vector3,
	forward: Vector3,
	target: Vector3,
	target_present: bool,
	noise_at: Variant = null
) -> Vector3:
	var seen := target_present and PerceptionScript.in_cone(origin, forward, target, sight_range, sight_angle_deg)
	var heard := noise_at is Vector3 and PerceptionScript.hears(origin, noise_at as Vector3, hearing_range)
	if heard:
		blackboard.set_value(&"heard_position", noise_at as Vector3)
	if seen:
		mode = Mode.CHASE
		leash_timer = 0.0
		if not aggro.has(&"target"):
			add_aggro(&"target")
		return (target - origin).normalized() * move_speed
	if mode == Mode.CHASE or mode == Mode.LEASH:
		leash_timer += delta
		if leash_timer >= leash_timeout:
			mode = Mode.PATROL
			leash_timer = 0.0
			aggro.clear()
			return forward.normalized() * move_speed * 0.5
		mode = Mode.LEASH
		return Vector3.ZERO
	mode = Mode.PATROL
	return forward.normalized() * move_speed * 0.5
