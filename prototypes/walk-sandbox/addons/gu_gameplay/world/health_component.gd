class_name HealthComponent
extends Node
## Reusable health & invulnerability component backed by StatSet.

signal damaged(amount: float, source: Node, remaining_hp: float)
signal healed(amount: float, remaining_hp: float)
signal died(source: Node)
signal revived

@export var max_hp: float = 100.0:
	set(v):
		max_hp = maxf(1.0, v)
		if not _externally_bound and _stats != null:
			_stats.define_stat(stat_id, max_hp, max_hp, 0.0)
			_dead = false
@export var stat_id: StringName = &"hp"
@export var invuln_time: float = 0.0

var _stats: StatSet = null
var _externally_bound: bool = false
var _dead: bool = false
var _invuln_remaining: float = 0.0


func _init() -> void:
	_ensure_stats()


func _ready() -> void:
	_ensure_stats()


func _process(delta: float) -> void:
	if _invuln_remaining > 0.0:
		_invuln_remaining = maxf(0.0, _invuln_remaining - delta)


func bind_stat_set(p_stats: StatSet, define_if_missing: bool = true) -> void:
	if p_stats == null:
		return
	_stats = p_stats
	_externally_bound = true
	if define_if_missing and not _stats.has_stat(stat_id):
		_stats.define_stat(stat_id, maxf(1.0, max_hp))
	_dead = _stats.get_value(stat_id) <= 0.0001


func get_stats() -> StatSet:
	_ensure_stats()
	return _stats


func set_max_hp(new_max: float, reset_current: bool = false) -> void:
	var clean_max := maxf(1.0, new_max)
	_ensure_stats()
	var prev_cur := get_hp()
	max_hp = clean_max
	if not reset_current:
		var cur := minf(prev_cur, clean_max)
		_stats.define_stat(stat_id, clean_max, cur, 0.0)
		_dead = cur <= 0.0001


func get_hp() -> float:
	_ensure_stats()
	return _stats.get_value(stat_id)


func get_max_hp() -> float:
	_ensure_stats()
	return _stats.get_max(stat_id)


func get_ratio() -> float:
	_ensure_stats()
	return _stats.get_ratio(stat_id)


func is_dead() -> bool:
	return _dead


func is_invulnerable() -> bool:
	return _invuln_remaining > 0.0


func apply_damage(amount: float, source: Node = null) -> float:
	_ensure_stats()
	if amount <= 0.0 or _dead or _invuln_remaining > 0.0:
		return 0.0
	var applied := -_stats.modify_value(stat_id, -amount)
	if applied <= 0.0:
		return 0.0
	if invuln_time > 0.0:
		_invuln_remaining = invuln_time
	var rem := _stats.get_value(stat_id)
	damaged.emit(applied, source, rem)
	if rem <= 0.0001 and not _dead:
		_dead = true
		died.emit(source)
	return applied


func heal(amount: float) -> float:
	_ensure_stats()
	if amount <= 0.0 or _dead:
		return 0.0
	var gained := _stats.modify_value(stat_id, amount)
	if gained > 0.0:
		healed.emit(gained, _stats.get_value(stat_id))
	return gained


func revive(full_hp: bool = true, hp_amount: float = -1.0) -> void:
	_ensure_stats()
	_dead = false
	_invuln_remaining = 0.0
	var target := get_max_hp() if full_hp else clampf(hp_amount, 1.0, get_max_hp())
	_stats.set_value(stat_id, target)
	revived.emit()


func export_state() -> Dictionary:
	_ensure_stats()
	return {
		"hp": get_hp(),
		"max_hp": get_max_hp(),
		"dead": _dead,
	}


func apply_state(doc: Dictionary) -> void:
	_ensure_stats()
	if doc.has("max_hp"):
		max_hp = maxf(1.0, float(doc["max_hp"]))
	var hp_val := float(doc.get("hp", max_hp))
	_stats.define_stat(stat_id, max_hp, hp_val, 0.0)
	_dead = bool(doc.get("dead", hp_val <= 0.0001))
	_invuln_remaining = 0.0


func _ensure_stats() -> void:
	if _stats == null:
		_stats = StatSet.new()
	if not _stats.has_stat(stat_id):
		_stats.define_stat(stat_id, maxf(1.0, max_hp))
