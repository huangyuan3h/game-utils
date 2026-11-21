class_name CharacterLocomotion
extends RefCounted
## Pure 8-direction ground + climb + wade/swim locomotion state machine.
## Depends only on a terrain query interface (sample_height, sample_water_surface, is_open_water).

const WALK_SPEED := 3.2
const RUN_SPEED := 6.4
const CLIMB_SPEED := 1.70
const CLIMB_FAST_SPEED := 2.25
const SWIM_SPEED := 2.45
const ACCEL := 16.0
const DECEL := 20.0
const CLIMB_ACCEL := 12.0
const CLIMB_DECEL := 18.0
const SWIM_ACCEL := 9.0
const SWIM_DECEL := 7.5
const TURN_SPEED := 12.0
const FEET_OFFSET := 0.02

## Steep cliff detection thresholds (slope gradient = dh / horiz_dist).
## Hillsides are walked. Only a near-cliff face, approached uphill, enters climb.
const CLIMB_ENTER_GRADE := 0.88 ## ~41 deg, near the terrain slope limit
const CLIMB_EXIT_GRADE := 0.72  ## ~36 deg hysteresis so a true face does not flicker
const CLIMB_DIR_MIN := 0.45     ## must be heading up the face, not contouring it
const CLIMB_PROBE_DIST := 0.45
const SLOPE_SAMPLE_EPS := 0.35
const CLIMB_BLEND_IN := 7.0
const CLIMB_BLEND_OUT := 6.0
const CLIMB_STRIDE := 0.85

## Sea/lake depth bands (meters). Rivers stay a shallow walkable bed.
const DEPTH_ENTER := 0.15
const DEPTH_WALK := 0.40
const DEPTH_RUN := 0.75
const DEPTH_SWIM := 1.15

const SWIM_FLOAT := 0.72 ## body center depth when actively swimming
const SWIM_IDLE_FLOAT := 0.94 ## deeper float when treading water in place

var facing_yaw: float = 0.0
var water_depth: float = 0.0
var run_amt: float = 0.0
var swim_amt: float = 0.0
var swim_t: float = 0.0
var swim_phase: float = 0.0
var swim_move: float = 0.0 ## smoothed 0=tread/float, 1=active freestyle swim
var climb_amt: float = 0.0
var climb_t: float = 0.0
var climb_phase: float = 0.0
var climb_move: float = 0.0 ## smoothed 0=cling idle, 1=active climbing
var climb_grade: float = 0.0
var climb_lateral: float = 0.0
var climb_vertical: float = 1.0
var speed_xz: float = 0.0
var speed_3d: float = 0.0
var is_moving: bool = false
var is_running: bool = false
var is_climbing: bool = false
var state_label: String = "WALK"


func reset() -> void:
	facing_yaw = 0.0
	water_depth = 0.0
	run_amt = 0.0
	swim_amt = 0.0
	swim_t = 0.0
	swim_phase = 0.0
	swim_move = 0.0
	climb_amt = 0.0
	climb_t = 0.0
	climb_phase = 0.0
	climb_move = 0.0
	climb_grade = 0.0
	climb_lateral = 0.0
	climb_vertical = 1.0
	speed_xz = 0.0
	speed_3d = 0.0
	is_moving = false
	is_running = false
	is_climbing = false
	state_label = "WALK"


func step(
	current_pos: Vector3,
	current_vel: Vector3,
	input_dir: Vector2,
	want_run_mode: bool,
	terrain: Object,
	delta: float,
	speed_scale: float = 1.0,
	facing_override_yaw: float = NAN
) -> Dictionary:
	var wish := Vector3(input_dir.x, 0.0, input_dir.y)
	var clamped_scale := clampf(speed_scale, 0.0, 2.0)
	var moving_input := wish.length_squared() > 0.0001 and clamped_scale > 0.001
	var wish_xz := Vector2(wish.x, wish.z).normalized() if moving_input else Vector2.ZERO

	var probe := current_pos + Vector3(current_vel.x, 0.0, current_vel.z) * delta
	_update_water_stage(_open_water_depth(probe.x, probe.z, terrain))

	# Terrain slope / cliff gradient sampling (central diff + forward probe)
	var grad_here := _sample_slope_vec(current_pos.x, current_pos.z, terrain)
	var here_grade := grad_here.length()
	var grad_ahead := grad_here
	var ahead_grade := here_grade
	var uphill_dir_grade := 0.0
	if moving_input:
		var ahead_x := current_pos.x + wish_xz.x * CLIMB_PROBE_DIST
		var ahead_z := current_pos.z + wish_xz.y * CLIMB_PROBE_DIST
		grad_ahead = _sample_slope_vec(ahead_x, ahead_z, terrain)
		ahead_grade = grad_ahead.length()
		var h_here := _ground_y(current_pos.x, current_pos.z, terrain)
		var h_ahead := _ground_y(ahead_x, ahead_z, terrain)
		var fwd_grade := (h_ahead - h_here) / CLIMB_PROBE_DIST
		uphill_dir_grade = maxf(grad_here.dot(wish_xz), maxf(grad_ahead.dot(wish_xz), fwd_grade))

	var dom_grad := grad_here
	if moving_input and ahead_grade > here_grade and uphill_dir_grade >= CLIMB_ENTER_GRADE:
		dom_grad = grad_ahead

	var can_climb := swim_amt < 0.45 and water_depth < DEPTH_RUN
	var was_climbing := climb_amt >= 0.35
	var want_climb := false
	if can_climb:
		if was_climbing:
			want_climb = here_grade >= CLIMB_EXIT_GRADE or (moving_input and uphill_dir_grade >= CLIMB_ENTER_GRADE)
		elif moving_input:
			var steep_face := maxf(here_grade, ahead_grade) >= CLIMB_ENTER_GRADE and uphill_dir_grade >= CLIMB_DIR_MIN
			want_climb = uphill_dir_grade >= CLIMB_ENTER_GRADE or steep_face

	climb_amt = move_toward(
		climb_amt,
		1.0 if want_climb else 0.0,
		delta * (CLIMB_BLEND_IN if want_climb else CLIMB_BLEND_OUT)
	)
	var target_grade := dom_grad.length() if want_climb else 0.0
	climb_grade = lerpf(climb_grade, target_grade, 1.0 - exp(-10.0 * delta))

	var want_fast := moving_input and want_run_mode
	var land_speed := RUN_SPEED if want_fast else WALK_SPEED
	var mid_speed := lerpf(land_speed, RUN_SPEED * 0.92, run_amt)
	var speed := lerpf(mid_speed, SWIM_SPEED if moving_input else SWIM_SPEED * 0.55, swim_amt)

	# Scramble along the slope at a careful fraction of the normal gait.
	# slope_scale keeps that speed on the surface instead of in the air.
	var dir_g := absf(dom_grad.dot(wish_xz)) if moving_input else dom_grad.length()
	var slope_scale := clampf(1.0 / sqrt(1.0 + dir_g * dir_g), 0.45, 1.0)
	var scramble := land_speed * (0.62 if want_fast else 0.70)
	speed = lerpf(speed, scramble * slope_scale, climb_amt) * clamped_scale

	var accel := lerpf(lerpf(ACCEL, CLIMB_ACCEL, climb_amt), SWIM_ACCEL, swim_amt)
	var decel := lerpf(lerpf(DECEL, CLIMB_DECEL, climb_amt), SWIM_DECEL, swim_amt)

	if swim_amt > 0.55:
		state_label = "SWIM"
	elif climb_amt > 0.45:
		state_label = "CLIMB"
	elif run_amt > 0.35 or (want_fast and water_depth < DEPTH_RUN):
		state_label = "RUN"
	else:
		state_label = "WALK"

	var next_vel := Vector3.ZERO
	if moving_input:
		wish = wish.normalized()
		var target_vel := wish * speed
		next_vel.x = move_toward(current_vel.x, target_vel.x, accel * delta)
		next_vel.z = move_toward(current_vel.z, target_vel.z, accel * delta)
		var move_yaw := atan2(wish.x, wish.z)
		var target_yaw := move_yaw
		# Keep looking where you travel. A small bias uphill stops a diagonal
		# scramble from crabbing straight into the slope.
		if climb_amt > 0.2 and dom_grad.length_squared() > 0.01:
			var wall_dir := dom_grad.normalized()
			var wall_yaw := atan2(wall_dir.x, wall_dir.y)
			target_yaw = lerp_angle(move_yaw, wall_yaw, 0.18 * climb_amt)
		facing_yaw = lerp_angle(facing_yaw, target_yaw, 1.0 - exp(-TURN_SPEED * delta))
	else:
		next_vel.x = move_toward(current_vel.x, 0.0, decel * delta)
		next_vel.z = move_toward(current_vel.z, 0.0, decel * delta)
		if not is_nan(facing_override_yaw):
			facing_yaw = lerp_angle(facing_yaw, facing_override_yaw, 1.0 - exp(-TURN_SPEED * delta))

	var next_pos := current_pos + Vector3(next_vel.x, 0.0, next_vel.z) * delta
	var bed := _ground_y(next_pos.x, next_pos.z, terrain)
	var stand_y := bed + FEET_OFFSET
	next_pos.y = stand_y

	var surf := _water_surface_y(next_pos.x, next_pos.z, terrain)
	if swim_amt > 0.001 and surf > -1000.0:
		var swim_depth := lerpf(SWIM_IDLE_FLOAT, SWIM_FLOAT, swim_move)
		var float_y := surf - lerpf(0.95, swim_depth, swim_amt)
		next_pos.y = lerpf(stand_y, maxf(stand_y, float_y), smoothstep(0.0, 1.0, swim_amt))

	speed_xz = Vector2(next_vel.x, next_vel.z).length()
	speed_3d = (next_pos - current_pos).length() / maxf(delta, 1e-5)
	is_moving = speed_xz > 0.25 or moving_input
	is_climbing = climb_amt > 0.45 and swim_amt < 0.45
	is_running = (want_fast or run_amt > 0.45) and speed_xz > WALK_SPEED * 0.45 and swim_amt < 0.45 and not is_climbing

	swim_t += delta * (2.6 if is_moving else 1.4)
	var move_target := 1.0 if (is_moving and swim_amt > 0.35) else 0.0
	swim_move = move_toward(swim_move, move_target, delta * 3.2)
	if swim_amt > 0.45:
		var stroke_rate := lerpf(0.30, 0.95, clampf(speed_xz / SWIM_SPEED, 0.0, 1.0))
		swim_phase = fposmod(swim_phase + delta * stroke_rate, 1.0)

	climb_t += delta * (2.2 if is_moving else 1.2)
	var climb_move_target := 1.0 if (is_moving and climb_amt > 0.35) else 0.0
	climb_move = move_toward(climb_move, climb_move_target, delta * 5.0)
	if climb_amt > 0.35:
		var vel_2d := Vector2(next_vel.x, next_vel.z)
		var uphill_2d := dom_grad.normalized() if dom_grad.length_squared() > 0.0025 else Vector2(sin(facing_yaw), cos(facing_yaw))
		var left_2d := Vector2(uphill_2d.y, -uphill_2d.x)
		var lat_target := clampf(vel_2d.dot(left_2d) / maxf(CLIMB_SPEED * 0.6, 0.1), -1.0, 1.0)
		climb_lateral = lerpf(climb_lateral, lat_target, 1.0 - exp(-10.0 * delta))
		var vert_sign := 1.0 if (vel_2d.dot(uphill_2d) >= -0.05 or vel_2d.length_squared() < 0.01) else -1.0
		climb_vertical = lerpf(climb_vertical, vert_sign, 1.0 - exp(-10.0 * delta))
		if is_moving:
			climb_phase = fposmod(climb_phase + vert_sign * (speed_3d * delta / CLIMB_STRIDE), 1.0)
	else:
		climb_lateral = lerpf(climb_lateral, 0.0, 1.0 - exp(-8.0 * delta))

	return {
		"position": next_pos,
		"velocity": next_vel,
	}


func _sample_slope_vec(x: float, z: float, terrain: Object) -> Vector2:
	var hx0 := _ground_y(x - SLOPE_SAMPLE_EPS, z, terrain)
	var hx1 := _ground_y(x + SLOPE_SAMPLE_EPS, z, terrain)
	var hz0 := _ground_y(x, z - SLOPE_SAMPLE_EPS, terrain)
	var hz1 := _ground_y(x, z + SLOPE_SAMPLE_EPS, terrain)
	var inv := 1.0 / (2.0 * SLOPE_SAMPLE_EPS)
	return Vector2((hx1 - hx0) * inv, (hz1 - hz0) * inv)


func _open_water_depth(x: float, z: float, terrain: Object) -> float:
	var surface := _water_surface_y(x, z, terrain)
	if surface <= -1000.0:
		return 0.0
	if not _is_open_water(x, z, terrain):
		return 0.0
	return maxf(0.0, surface - _ground_y(x, z, terrain))


func _update_water_stage(depth: float) -> void:
	water_depth = depth
	run_amt = smoothstep(DEPTH_WALK, 0.55, depth) * (1.0 - smoothstep(0.65, DEPTH_RUN, depth))
	swim_amt = smoothstep(DEPTH_RUN, DEPTH_SWIM, depth)


func _ground_y(x: float, z: float, terrain: Object) -> float:
	if terrain != null and terrain.has_method("sample_height"):
		return float(terrain.call("sample_height", x, z))
	return 0.0


func _water_surface_y(x: float, z: float, terrain: Object) -> float:
	if terrain != null and terrain.has_method("sample_water_surface"):
		return float(terrain.call("sample_water_surface", x, z))
	return -INF


func _biome_at(x: float, z: float, terrain: Object) -> int:
	if terrain != null and terrain.has_method("sample_biome"):
		return int(terrain.call("sample_biome", x, z))
	return -1


func _is_open_water(x: float, z: float, terrain: Object) -> bool:
	## Rivers stay wadeable; only sea/lake surfaces count as open water.
	## Terrains that do not distinguish water types treat every surface as open water.
	if terrain != null and terrain.has_method("is_open_water"):
		return bool(terrain.call("is_open_water", x, z))
	return true
