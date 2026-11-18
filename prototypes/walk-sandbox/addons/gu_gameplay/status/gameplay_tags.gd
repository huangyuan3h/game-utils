class_name GameplayTags
extends RefCounted
## Hierarchical tags. `State.Stunned` satisfies a query for `State` and for itself.

var _tags: Dictionary = {}


func add(tag: StringName) -> void:
	if tag != &"":
		_tags[tag] = true


func remove(tag: StringName) -> void:
	_tags.erase(tag)


func has_exact(tag: StringName) -> bool:
	return _tags.has(tag)


func has(query: StringName) -> bool:
	var wanted := String(query)
	if wanted == "":
		return false
	for raw_tag: StringName in _tags:
		var text := String(raw_tag)
		if text == wanted or text.begins_with(wanted + "."):
			return true
	return false


func clear() -> void:
	_tags.clear()
