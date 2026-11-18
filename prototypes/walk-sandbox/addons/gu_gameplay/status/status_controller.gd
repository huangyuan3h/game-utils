class_name StatusController
extends Node
## Timed buffs and damage-over-time. Stat changes go through StatSet modifiers and expire with the effect.

const GameplayTagsScript := preload("res://addons/gu_gameplay/status/gameplay_tags.gd")

var stats: StatSet = null
var health: HealthComponent = null
var tags = GameplayTagsScript.new()

var _effects: Dictionary = {}


func apply_status(effect_id: StringName, spec: Dictionary) -> void:
	if effect_id == &"":
		return
	var duration := maxf(0.0, float(spec.get("duration", 0.0)))
	var max_stacks := maxi(1, int(spec.get("max_stacks", 1)))
	var stacks := 1
	if _effects.has(effect_id):
		stacks = mini(max_stacks, int((_effects[effect_id] as Dictionary)["stacks"]) + 1)
		_clear_modifier(effect_id)
	else:
		_grant_tags(spec)
	_effects[effect_id] = {
		"remaining": duration,
		"stacks": stacks,
		"max_stacks": max_stacks,
		"tick_interval": maxf(0.0, float(spec.get("tick_interval", 0.0))),
		"tick_wait": float(spec.get("tick_interval", 0.0)),
		"damage_per_tick": float(spec.get("damage_per_tick", 0.0)),
		"stat_id": StringName(spec.get("stat_id", &"")),
		"flat": float(spec.get("flat", 0.0)),
		"mult": float(spec.get("mult", 1.0)),
		"tags": spec.get("tags", []),
	}
	_apply_modifier(effect_id)


func has_status(effect_id: StringName) -> bool:
	return _effects.has(effect_id)


func get_stacks(effect_id: StringName) -> int:
	if not _effects.has(effect_id):
		return 0
	return int((_effects[effect_id] as Dictionary)["stacks"])


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var expired: Array[StringName] = []
	for effect_id: StringName in _effects:
		var effect := _effects[effect_id] as Dictionary
		effect["remaining"] = float(effect["remaining"]) - delta
		var interval := float(effect["tick_interval"])
		var damage := float(effect["damage_per_tick"])
		if interval > 0.0 and damage > 0.0 and health != null:
			effect["tick_wait"] = float(effect["tick_wait"]) - delta
			while float(effect["tick_wait"]) <= 0.0 and float(effect["remaining"]) + interval > 0.0:
				health.apply_damage(damage * int(effect["stacks"]), self)
				effect["tick_wait"] = float(effect["tick_wait"]) + interval
		if float(effect["remaining"]) <= 0.0:
			expired.append(effect_id)
	for effect_id in expired:
		_expire(effect_id)


func _apply_modifier(effect_id: StringName) -> void:
	if stats == null or not _effects.has(effect_id):
		return
	var effect := _effects[effect_id] as Dictionary
	var stat_id := effect["stat_id"] as StringName
	if stat_id == &"":
		return
	var stacks := int(effect["stacks"])
	var mult := pow(float(effect["mult"]), stacks)
	var flat := float(effect["flat"]) * float(stacks)
	stats.add_modifier(stat_id, _mod_id(effect_id), flat, mult)


func _clear_modifier(effect_id: StringName) -> void:
	if stats == null or not _effects.has(effect_id):
		return
	var stat_id := (_effects[effect_id] as Dictionary)["stat_id"] as StringName
	if stat_id != &"":
		stats.remove_modifier(stat_id, _mod_id(effect_id))


func _grant_tags(spec: Dictionary) -> void:
	var listed: Variant = spec.get("tags", [])
	if listed is Array:
		for item in listed:
			tags.add(StringName(str(item)))


func _revoke_tags(effect: Dictionary) -> void:
	var listed: Variant = effect.get("tags", [])
	if listed is Array:
		for item in listed:
			tags.remove(StringName(str(item)))


func _expire(effect_id: StringName) -> void:
	if not _effects.has(effect_id):
		return
	var effect := _effects[effect_id] as Dictionary
	_clear_modifier(effect_id)
	_revoke_tags(effect)
	_effects.erase(effect_id)


func _mod_id(effect_id: StringName) -> StringName:
	return StringName("status:%s" % String(effect_id))
