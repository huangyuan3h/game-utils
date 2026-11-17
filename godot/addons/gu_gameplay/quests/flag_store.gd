class_name FlagStore
extends RefCounted
## Pure-data world flag and counter store with change signals and SaveService serialization.

signal flag_changed(flag_id: StringName, old_value: Variant, new_value: Variant)

var _flags: Dictionary = {} ## StringName -> Variant


func set_flag(flag_id: StringName, value: Variant) -> void:
	if flag_id == &"":
		return
	var had := _flags.has(flag_id)
	var old_val: Variant = _flags.get(flag_id, null)
	if had and old_val == value:
		return
	_flags[flag_id] = value
	flag_changed.emit(flag_id, old_val, value)


func get_flag(flag_id: StringName, fallback: Variant = null) -> Variant:
	if _flags.has(flag_id):
		return _flags[flag_id]
	return fallback


func get_bool(flag_id: StringName, fallback: bool = false) -> bool:
	if not _flags.has(flag_id):
		return fallback
	return bool(_flags[flag_id])


func get_int(flag_id: StringName, fallback: int = 0) -> int:
	if not _flags.has(flag_id):
		return fallback
	var v: Variant = _flags[flag_id]
	if v is int or v is float or v is bool:
		return int(v)
	return fallback


func inc_counter(flag_id: StringName, delta: int = 1) -> int:
	if flag_id == &"":
		return 0
	var next := get_int(flag_id, 0) + delta
	set_flag(flag_id, next)
	return next


func has_flag(flag_id: StringName) -> bool:
	return _flags.has(flag_id)


func erase_flag(flag_id: StringName) -> void:
	if not _flags.has(flag_id):
		return
	var old_val: Variant = _flags[flag_id]
	_flags.erase(flag_id)
	flag_changed.emit(flag_id, old_val, null)


func clear() -> void:
	if _flags.is_empty():
		return
	_flags.clear()


func list_flags() -> Dictionary:
	return _flags.duplicate(true)


func export_state() -> Dictionary:
	var out: Dictionary = {}
	for k: StringName in _flags:
		out[String(k)] = _flags[k]
	return {"flags": out}


func apply_state(doc: Dictionary) -> void:
	_flags.clear()
	var raw: Variant = doc.get("flags", {})
	if raw is Dictionary:
		for k in raw as Dictionary:
			var fid := StringName(str(k))
			if fid != &"":
				_flags[fid] = (raw as Dictionary)[k]
