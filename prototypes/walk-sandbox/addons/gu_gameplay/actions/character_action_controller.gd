class_name CharacterActionController
extends RefCounted
## Pure-logic character action state machine (no SceneTree or locomotion class dependency).
## Coordinates action validation, lifecycle phases, hit-beat callbacks,
## locomotion overrides, and clean cancellation/completion.

signal action_started(action_id: StringName, spec: CharacterActionSpec)
signal action_beat(action_id: StringName, beat_index: int, cycle_count: int)
signal action_completed(action_id: StringName, cycle_count: int)
signal action_cancelled(action_id: StringName, reason: StringName)

enum Phase { IDLE, WINDUP, ACTIVE, RECOVER }

var _registry: CharacterActionRegistry
var _spec: CharacterActionSpec = null
var _last_ik_profile: StringName = &""
var _last_tool_type: int = CharacterActionSpec.ToolType.NONE

var current_id: StringName = &""
var last_used_id: StringName = &"gather"
var phase_state: int = Phase.IDLE
var elapsed: float = 0.0
var cycle_phase: float = 0.0
var cycle_count: int = 0
var blend_weight: float = 0.0
var has_target_yaw: bool = false
var target_yaw: float = 0.0
var last_cancel_reason: StringName = &""

var _min_cycles: int = 1
var _continuous: bool = false
var _stop_requested: bool = false


func _init(registry: CharacterActionRegistry = null) -> void:
	_registry = registry if registry != null else CharacterActionRegistry.create_default()


func set_registry(registry: CharacterActionRegistry) -> void:
	if registry != null:
		_registry = registry


func get_registry() -> CharacterActionRegistry:
	return _registry


func is_acting() -> bool:
	return _spec != null and phase_state != Phase.IDLE


func get_current_spec() -> CharacterActionSpec:
	return _spec


func can_start(action_id: StringName, loco: Variant = null) -> Dictionary:
	if _registry == null or not _registry.has_action(action_id):
		return {"ok": false, "reason": &"unknown_action"}
	var spec := _registry.get_spec(action_id)
	if spec == null or not spec.is_valid():
		return {"ok": false, "reason": &"invalid_spec"}
	if loco != null:
		var swim_amt := _loco_float(loco, &"swim_amt", 0.0)
		var is_climbing := _loco_bool(loco, &"is_climbing", false)
		var climb_amt := _loco_float(loco, &"climb_amt", 0.0)
		var water_depth := _loco_float(loco, &"water_depth", 0.0)
		if not spec.allow_in_water and swim_amt > 0.35:
			return {"ok": false, "reason": &"swimming"}
		if not spec.allow_while_climbing and (is_climbing or climb_amt > 0.45):
			return {"ok": false, "reason": &"climbing"}
		if water_depth > spec.max_water_depth:
			return {"ok": false, "reason": &"water_too_deep"}
	return {"ok": true, "reason": &""}


func try_start(action_id: StringName, loco: Variant = null, context: Dictionary = {}) -> bool:
	var check := can_start(action_id, loco)
	if not bool(check.get("ok", false)):
		last_cancel_reason = check.get("reason", &"blocked") as StringName
		return false

	var spec := _registry.get_spec(action_id)
	if _spec != null:
		if _spec.id == action_id and phase_state != Phase.IDLE:
			_stop_requested = false
			if context.has("continuous"):
				_continuous = bool(context["continuous"])
			if context.has("min_cycles"):
				_min_cycles = maxi(1, int(context["min_cycles"]))
			return true
		cancel(&"replaced")

	_spec = spec
	current_id = spec.id
	last_used_id = spec.id
	_last_ik_profile = spec.ik_profile
	_last_tool_type = spec.tool_type
	phase_state = Phase.WINDUP if spec.windup_ratio > 0.0 else Phase.ACTIVE
	elapsed = 0.0
	cycle_phase = 0.0
	cycle_count = 0
	last_cancel_reason = &""
	_stop_requested = false
	_continuous = bool(context.get("continuous", false))
	_min_cycles = maxi(1, int(context.get("min_cycles", 1)))

	if context.has("target_yaw"):
		has_target_yaw = true
		target_yaw = float(context["target_yaw"])
	elif context.has("target_pos") and context.has("origin_pos"):
		var delta_pos: Vector3 = (context["target_pos"] as Vector3) - (context["origin_pos"] as Vector3)
		if Vector2(delta_pos.x, delta_pos.z).length_squared() > 0.0004:
			has_target_yaw = true
			target_yaw = atan2(delta_pos.x, delta_pos.z)
		else:
			has_target_yaw = false
	else:
		has_target_yaw = false

	action_started.emit(current_id, _spec)
	return true


func request_stop(graceful: bool = true) -> void:
	if _spec == null:
		return
	if not graceful:
		cancel(&"stopped")
		return
	_continuous = false
	_stop_requested = true


func cancel(reason: StringName = &"manual") -> void:
	if _spec == null:
		return
	var cancelled_id := current_id
	last_cancel_reason = reason
	_clear_active_state()
	action_cancelled.emit(cancelled_id, reason)


func reset() -> void:
	_clear_active_state()
	blend_weight = 0.0
	_last_ik_profile = &""
	_last_tool_type = CharacterActionSpec.ToolType.NONE
	last_cancel_reason = &""


func step(
	delta: float,
	loco: Variant = null,
	move_input: Vector2 = Vector2.ZERO,
	hold_active: bool = false
) -> Dictionary:
	var dt := maxf(delta, 0.0)

	if _spec == null:
		blend_weight = move_toward(blend_weight, 0.0, 14.0 * dt)
		return _build_frame(false)

	# 1) Environment guard while acting (e.g. pushed/drifted into deep water or cliff climb)
	if loco != null:
		var swim_amt := _loco_float(loco, &"swim_amt", 0.0)
		var water_depth := _loco_float(loco, &"water_depth", 0.0)
		var is_climbing := _loco_bool(loco, &"is_climbing", false)
		var climb_amt := _loco_float(loco, &"climb_amt", 0.0)
		if (not _spec.allow_in_water and swim_amt > 0.45) or water_depth > _spec.max_water_depth:
			cancel(&"water_depth")
			blend_weight = move_toward(blend_weight, 0.0, 14.0 * dt)
			return _build_frame(false)
		if not _spec.allow_while_climbing and (is_climbing or climb_amt > 0.45):
			cancel(&"climbing")
			blend_weight = move_toward(blend_weight, 0.0, 14.0 * dt)
			return _build_frame(false)

	# 2) Movement interrupt policy
	if move_input.length_squared() > 0.04 and _spec.move_policy == CharacterActionSpec.MovePolicy.CANCEL_ON_MOVE:
		cancel(&"moved")
		blend_weight = move_toward(blend_weight, 0.0, 14.0 * dt)
		return _build_frame(false)

	# 3) Advance action clock and emit hit beats accurately across cycle boundaries
	blend_weight = move_toward(blend_weight, 1.0, _spec.blend_in_speed * dt)
	elapsed += dt

	var prev_phase := cycle_phase
	var next_raw := prev_phase + (dt / maxf(_spec.duration, 0.05))
	var completed_now := false

	while next_raw >= 1.0:
		_emit_beats_in_range(prev_phase, 1.0)
		cycle_count += 1
		var should_continue := _spec.looping and not _stop_requested and (hold_active or _continuous or cycle_count < _min_cycles)
		if should_continue:
			next_raw -= 1.0
			prev_phase = 0.0
		else:
			completed_now = true
			break

	if completed_now:
		var done_id := current_id
		var done_cycles := cycle_count
		_clear_active_state()
		action_completed.emit(done_id, done_cycles)
		return _build_frame(false)

	_emit_beats_in_range(prev_phase, next_raw)
	cycle_phase = clampf(next_raw, 0.0, 0.9999)
	_update_phase_state()
	return _build_frame(true)


func _loco_float(loco: Variant, prop: StringName, fallback: float) -> float:
	if loco is Dictionary:
		var d := loco as Dictionary
		if d.has(prop):
			return float(d[prop])
		var s := String(prop)
		return float(d.get(s, fallback))
	if loco is Object and is_instance_valid(loco):
		var v: Variant = (loco as Object).get(prop)
		if v != null:
			return float(v)
	return fallback


func _loco_bool(loco: Variant, prop: StringName, fallback: bool) -> bool:
	if loco is Dictionary:
		var d := loco as Dictionary
		if d.has(prop):
			return bool(d[prop])
		var s := String(prop)
		return bool(d.get(s, fallback))
	if loco is Object and is_instance_valid(loco):
		var v: Variant = (loco as Object).get(prop)
		if v != null:
			return bool(v)
	return fallback


func _emit_beats_in_range(start_p: float, end_p: float) -> void:
	if _spec == null or _spec.hit_phases.is_empty():
		return
	for i in _spec.hit_phases.size():
		var hp := _spec.hit_phases[i]
		if hp > start_p and hp <= end_p:
			action_beat.emit(current_id, i, cycle_count)


func _update_phase_state() -> void:
	if _spec == null:
		phase_state = Phase.IDLE
		return
	if cycle_phase < _spec.windup_ratio:
		phase_state = Phase.WINDUP
	elif _spec.recover_ratio > 0.0 and cycle_phase >= (1.0 - _spec.recover_ratio):
		phase_state = Phase.RECOVER
	else:
		phase_state = Phase.ACTIVE


func _clear_active_state() -> void:
	_spec = null
	current_id = &""
	phase_state = Phase.IDLE
	elapsed = 0.0
	cycle_phase = 0.0
	cycle_count = 0
	has_target_yaw = false
	_stop_requested = false
	_continuous = false


func _build_frame(acting: bool) -> Dictionary:
	var label := ""
	var move_scale := 1.0
	var tool := _last_tool_type
	var profile := _last_ik_profile
	var clip := ""
	if acting and _spec != null:
		label = _spec.display_name
		if cycle_count > 0:
			label = "%s x%d" % [_spec.display_name, cycle_count + 1]
		move_scale = _spec.effective_move_scale()
		tool = _spec.tool_type
		profile = _spec.ik_profile
		clip = _spec.clip_hint
	return {
		"is_acting": acting,
		"action_id": current_id if acting else &"",
		"state_label": label,
		"move_scale": move_scale,
		"has_facing_override": acting and has_target_yaw,
		"facing_override_yaw": target_yaw,
		"ik_profile": profile,
		"tool_type": tool,
		"clip_hint": clip,
		"cycle_phase": cycle_phase if acting else 0.0,
		"cycle_count": cycle_count,
		"phase_state": phase_state,
		"blend_weight": blend_weight,
	}
