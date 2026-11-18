class_name AiBlackboard
extends RefCounted
## Small key/value board shared by an agent's senses and state.

var _facts: Dictionary = {}


func set_value(key: StringName, value: Variant) -> void:
	_facts[key] = value


func get_value(key: StringName, fallback: Variant = null) -> Variant:
	if not _facts.has(key):
		return fallback
	return _facts[key]


func has_value(key: StringName) -> bool:
	return _facts.has(key)


func erase(key: StringName) -> void:
	_facts.erase(key)
