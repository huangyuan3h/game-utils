class_name CooldownTracker
extends RefCounted
## Shared cooldown clock for skills, harvesting, and item use.

var _remaining: Dictionary = {}


func try_start(action_id: StringName, seconds: float) -> bool:
	if action_id == &"" or seconds < 0.0:
		return false
	if remaining(action_id) > 0.0:
		return false
	if seconds > 0.0:
		_remaining[action_id] = seconds
	return true


func is_ready(action_id: StringName) -> bool:
	return remaining(action_id) <= 0.0


func remaining(action_id: StringName) -> float:
	return float(_remaining.get(action_id, 0.0))


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var finished: Array[StringName] = []
	for action_id: StringName in _remaining:
		var left := float(_remaining[action_id]) - delta
		if left <= 0.0:
			finished.append(action_id)
		else:
			_remaining[action_id] = left
	for action_id in finished:
		_remaining.erase(action_id)
