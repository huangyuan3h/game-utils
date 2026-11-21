class_name CharacterActionRegistry
extends RefCounted
## Central registry mapping action IDs to CharacterActionSpec definitions.
## Allows adding or overriding character actions without touching the state machine.

var _specs: Dictionary = {} ## StringName -> CharacterActionSpec
var _order: Array[StringName] = []


static func create_default() -> CharacterActionRegistry:
	var reg := CharacterActionRegistry.new()
	reg.register(CharacterActionSpec.new({
		"id": "gather",
		"display_name": "GATHER",
		"category": "work",
		"duration": 1.08,
		"windup_ratio": 0.24,
		"recover_ratio": 0.16,
		"hit_phases": [0.56],
		"looping": true,
		"move_policy": CharacterActionSpec.MovePolicy.CANCEL_ON_MOVE,
		"allow_in_water": false,
		"max_water_depth": 0.35,
		"tool_type": CharacterActionSpec.ToolType.NONE,
		"ik_profile": "gather",
		"clip_hint": "Working",
	}))
	reg.register(CharacterActionSpec.new({
		"id": "mine",
		"display_name": "MINE",
		"category": "work",
		"duration": 0.96,
		"windup_ratio": 0.36,
		"recover_ratio": 0.16,
		"hit_phases": [0.58],
		"looping": true,
		"move_policy": CharacterActionSpec.MovePolicy.CANCEL_ON_MOVE,
		"allow_in_water": false,
		"max_water_depth": 0.45,
		"tool_type": CharacterActionSpec.ToolType.PICKAXE,
		"ik_profile": "mine",
		"clip_hint": "Working",
	}))
	reg.register(CharacterActionSpec.new({
		"id": "chop",
		"display_name": "CHOP",
		"category": "work",
		"duration": 0.88,
		"windup_ratio": 0.34,
		"recover_ratio": 0.16,
		"hit_phases": [0.55],
		"looping": true,
		"move_policy": CharacterActionSpec.MovePolicy.CANCEL_ON_MOVE,
		"allow_in_water": false,
		"max_water_depth": 0.45,
		"tool_type": CharacterActionSpec.ToolType.AXE,
		"ik_profile": "chop",
		"clip_hint": "Working",
	}))
	reg.register(CharacterActionSpec.new({
		"id": "build",
		"display_name": "BUILD",
		"category": "work",
		"duration": 0.94,
		"windup_ratio": 0.20,
		"recover_ratio": 0.14,
		"hit_phases": [0.42, 0.80],
		"looping": true,
		"move_policy": CharacterActionSpec.MovePolicy.CANCEL_ON_MOVE,
		"allow_in_water": false,
		"max_water_depth": 0.40,
		"tool_type": CharacterActionSpec.ToolType.HAMMER,
		"ik_profile": "build",
		"clip_hint": "Working",
	}))
	reg.register(CharacterActionSpec.new({
		"id": "strike",
		"display_name": "STRIKE",
		"category": "combat",
		"duration": 0.55,
		"windup_ratio": 0.34,
		"recover_ratio": 0.30,
		"hit_phases": [0.50],
		"looping": false,
		"move_policy": CharacterActionSpec.MovePolicy.LOCK,
		"allow_in_water": true,
		"tool_type": CharacterActionSpec.ToolType.NONE,
		"ik_profile": "strike",
		"clip_hint": "Working",
	}))
	return reg


func register(spec: CharacterActionSpec) -> bool:
	if spec == null or not spec.is_valid():
		return false
	if not _specs.has(spec.id):
		_order.append(spec.id)
	_specs[spec.id] = spec
	return true


func unregister(action_id: StringName) -> void:
	if _specs.erase(action_id):
		_order.erase(action_id)


func has_action(action_id: StringName) -> bool:
	return _specs.has(action_id)


func get_spec(action_id: StringName) -> CharacterActionSpec:
	return _specs.get(action_id, null) as CharacterActionSpec


func list_ids() -> Array[StringName]:
	return _order.duplicate()
