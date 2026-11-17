class_name StatSet
extends RefCounted
## Pure-data attribute/resource set supporting base bounds, additive/multiplicative
## modifiers, atomic spending, change signals, and JSON-safe serialization.

signal stat_changed(stat_id: StringName, current: float, max_val: float)

var _stats: Dictionary = {} ## StringName -> Dictionary


func define_stat(
	stat_id: StringName,
	base_max: float,
	initial: float = -INF,
	min_val: float = 0.0
) -> void:
	if stat_id == &"":
		return
	var clean_min := min_val
	var clean_max := maxf(clean_min, base_max)
	var start_val := clean_max if is_inf(initial) else clampf(initial, clean_min, clean_max)
	_stats[stat_id] = {
		"base_max": clean_max,
		"min": clean_min,
		"effective_max": clean_max,
		"current": start_val,
		"modifiers": {},
	}
	stat_changed.emit(stat_id, start_val, clean_max)


func has_stat(stat_id: StringName) -> bool:
	return _stats.has(stat_id)


func get_value(stat_id: StringName, fallback: float = 0.0) -> float:
	if not _stats.has(stat_id):
		return fallback
	return float((_stats[stat_id] as Dictionary)["current"])


func get_max(stat_id: StringName, fallback: float = 0.0) -> float:
	if not _stats.has(stat_id):
		return fallback
	return float((_stats[stat_id] as Dictionary)["effective_max"])


func get_min(stat_id: StringName, fallback: float = 0.0) -> float:
	if not _stats.has(stat_id):
		return fallback
	return float((_stats[stat_id] as Dictionary)["min"])


func get_ratio(stat_id: StringName) -> float:
	if not _stats.has(stat_id):
		return 0.0
	var s := _stats[stat_id] as Dictionary
	var lo := float(s["min"])
	var hi := float(s["effective_max"])
	var span := hi - lo
	if span <= 0.0001:
		return 0.0
	return clampf((float(s["current"]) - lo) / span, 0.0, 1.0)


func set_value(stat_id: StringName, value: float) -> void:
	if not _stats.has(stat_id):
		return
	var s := _stats[stat_id] as Dictionary
	var lo := float(s["min"])
	var hi := float(s["effective_max"])
	var next := clampf(value, lo, hi)
	if is_equal_approx(float(s["current"]), next):
		return
	s["current"] = next
	stat_changed.emit(stat_id, next, hi)


func modify_value(stat_id: StringName, delta: float) -> float:
	if not _stats.has(stat_id):
		return 0.0
	var prev := get_value(stat_id)
	set_value(stat_id, prev + delta)
	return get_value(stat_id) - prev


func spend(stat_id: StringName, cost: float) -> bool:
	if cost < 0.0 or not _stats.has(stat_id):
		return false
	var cur := get_value(stat_id)
	if cur + 0.0001 < cost:
		return false
	set_value(stat_id, cur - cost)
	return true


func add_modifier(
	stat_id: StringName,
	mod_id: StringName,
	flat_add: float = 0.0,
	mult: float = 1.0
) -> void:
	if not _stats.has(stat_id) or mod_id == &"":
		return
	var s := _stats[stat_id] as Dictionary
	var mods := s["modifiers"] as Dictionary
	mods[mod_id] = {"flat": flat_add, "mult": maxf(0.0, mult)}
	_recompute_max(stat_id)


func remove_modifier(stat_id: StringName, mod_id: StringName) -> void:
	if not _stats.has(stat_id):
		return
	var s := _stats[stat_id] as Dictionary
	var mods := s["modifiers"] as Dictionary
	if mods.erase(mod_id):
		_recompute_max(stat_id)


func export_state() -> Dictionary:
	var out: Dictionary = {}
	for stat_id: StringName in _stats:
		var s := _stats[stat_id] as Dictionary
		var mods_out: Dictionary = {}
		var mods := s["modifiers"] as Dictionary
		for mid: StringName in mods:
			var m := mods[mid] as Dictionary
			mods_out[String(mid)] = {"flat": float(m["flat"]), "mult": float(m["mult"])}
		out[String(stat_id)] = {
			"base_max": float(s["base_max"]),
			"min": float(s["min"]),
			"current": float(s["current"]),
			"modifiers": mods_out,
		}
	return out


func apply_state(doc: Dictionary) -> void:
	for raw_id in doc:
		var stat_id := StringName(str(raw_id))
		var entry: Variant = doc[raw_id]
		if not (entry is Dictionary):
			continue
		var d := entry as Dictionary
		var bmax := float(d.get("base_max", 100.0))
		var lo := float(d.get("min", 0.0))
		var cur := float(d.get("current", bmax))
		define_stat(stat_id, bmax, cur, lo)
		var raw_mods: Variant = d.get("modifiers", {})
		if raw_mods is Dictionary:
			for raw_mid in raw_mods as Dictionary:
				var m: Variant = (raw_mods as Dictionary)[raw_mid]
				if m is Dictionary:
					var md := m as Dictionary
					add_modifier(stat_id, StringName(str(raw_mid)), float(md.get("flat", 0.0)), float(md.get("mult", 1.0)))
		set_value(stat_id, cur)


func _recompute_max(stat_id: StringName) -> void:
	var s := _stats[stat_id] as Dictionary
	var base_max := float(s["base_max"])
	var lo := float(s["min"])
	var mods := s["modifiers"] as Dictionary
	var sum_flat := 0.0
	var prod_mult := 1.0
	for mid: StringName in mods:
		var m := mods[mid] as Dictionary
		sum_flat += float(m["flat"])
		prod_mult *= float(m["mult"])
	var eff_max := maxf(lo, (base_max + sum_flat) * prod_mult)
	var prev_max := float(s["effective_max"])
	var prev_cur := float(s["current"])
	s["effective_max"] = eff_max
	s["current"] = clampf(prev_cur, lo, eff_max)
	if not is_equal_approx(prev_max, eff_max) or not is_equal_approx(prev_cur, float(s["current"])):
		stat_changed.emit(stat_id, float(s["current"]), eff_max)
