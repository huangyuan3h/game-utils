class_name CharacterActionSpec
extends RefCounted
## Immutable-style specification describing a character action's timing,
## movement rules, environment constraints, tool visual, and IK/animation driver.

enum MovePolicy {
	LOCK,           ## Zero movement while active; movement input does not cancel
	SLOW,           ## Move at scaled speed while active
	CANCEL_ON_MOVE, ## Movement input immediately cancels the action
}

enum ToolType {
	NONE,
	PICKAXE,
	AXE,
	HAMMER,
}

var id: StringName = &""
var display_name: String = ""
var category: StringName = &"work"
var duration: float = 1.0
var windup_ratio: float = 0.25
var recover_ratio: float = 0.15
var hit_phases: Array[float] = []
var looping: bool = true
var move_policy: int = MovePolicy.CANCEL_ON_MOVE
var move_speed_scale: float = 0.0
var allow_in_water: bool = false
var allow_while_climbing: bool = false
var max_water_depth: float = 0.45
var tool_type: int = ToolType.NONE
var ik_profile: StringName = &""
var clip_hint: String = ""
var blend_in_speed: float = 12.0
var blend_out_speed: float = 14.0


func _init(cfg: Dictionary = {}) -> void:
	if cfg.is_empty():
		return
	id = StringName(str(cfg.get("id", "")))
	display_name = str(cfg.get("display_name", String(id).to_upper()))
	category = StringName(str(cfg.get("category", "work")))
	duration = maxf(float(cfg.get("duration", 1.0)), 0.05)
	windup_ratio = clampf(float(cfg.get("windup_ratio", 0.25)), 0.0, 0.85)
	recover_ratio = clampf(float(cfg.get("recover_ratio", 0.15)), 0.0, 0.85)
	if windup_ratio + recover_ratio > 0.95:
		recover_ratio = maxf(0.0, 0.95 - windup_ratio)

	hit_phases.clear()
	var raw_hits: Variant = cfg.get("hit_phases", [])
	if raw_hits is Array:
		for hp in raw_hits:
			hit_phases.append(clampf(float(hp), 0.01, 0.99))
		hit_phases.sort()

	looping = bool(cfg.get("looping", true))
	move_policy = int(cfg.get("move_policy", MovePolicy.CANCEL_ON_MOVE))
	move_speed_scale = clampf(float(cfg.get("move_speed_scale", 0.0)), 0.0, 1.0)
	allow_in_water = bool(cfg.get("allow_in_water", false))
	allow_while_climbing = bool(cfg.get("allow_while_climbing", false))
	max_water_depth = maxf(float(cfg.get("max_water_depth", 0.45)), 0.0)
	tool_type = int(cfg.get("tool_type", ToolType.NONE))
	ik_profile = StringName(str(cfg.get("ik_profile", String(id))))
	clip_hint = str(cfg.get("clip_hint", ""))
	blend_in_speed = maxf(float(cfg.get("blend_in_speed", 12.0)), 1.0)
	blend_out_speed = maxf(float(cfg.get("blend_out_speed", 14.0)), 1.0)


func is_valid() -> bool:
	return id != &"" and duration >= 0.05


func effective_move_scale() -> float:
	match move_policy:
		MovePolicy.LOCK:
			return 0.0
		MovePolicy.SLOW:
			return move_speed_scale
		MovePolicy.CANCEL_ON_MOVE:
			return 0.0
		_:
			return 0.0
