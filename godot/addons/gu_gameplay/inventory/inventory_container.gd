class_name InventoryContainer
extends RefCounted
## Stack-aware item container with optional slot limits, atomic removal, and SaveService serialization.

signal inventory_changed
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)

var max_slots: int = 0 ## 0 = unlimited slots
var default_max_stack: int = 99

var _defs: Dictionary = {} ## StringName -> ItemDef
var _slots: Array[Dictionary] = [] ## [{"id": StringName, "count": int}]


func _init(p_max_slots: int = 0, p_default_max_stack: int = 99) -> void:
	max_slots = maxi(0, p_max_slots)
	default_max_stack = maxi(1, p_default_max_stack)


func register_item(def: ItemDef) -> void:
	if def == null or def.id == &"":
		return
	_defs[def.id] = def


func get_item_def(item_id: StringName) -> ItemDef:
	return _defs.get(item_id, null) as ItemDef


func get_max_stack(item_id: StringName) -> int:
	var def := get_item_def(item_id)
	if def != null:
		return maxi(1, def.max_stack)
	return default_max_stack


func count_item(item_id: StringName) -> int:
	var total := 0
	for slot in _slots:
		if slot["id"] == item_id:
			total += int(slot["count"])
	return total


func has_item(item_id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return count_item(item_id) >= amount


func can_add(item_id: StringName, amount: int) -> bool:
	## Read-only check that `amount` items would fit under the current slot and stack caps.
	if amount <= 0:
		return true
	if item_id == &"":
		return false
	var remaining := amount
	var stack_cap := get_max_stack(item_id)
	for slot in _slots:
		if remaining <= 0:
			break
		if slot["id"] != item_id:
			continue
		var space := stack_cap - int(slot["count"])
		if space > 0:
			remaining -= mini(space, remaining)
	if remaining <= 0:
		return true
	var free_slots := 1 << 30
	if max_slots > 0:
		free_slots = maxi(0, max_slots - _slots.size())
	var needed := int(ceil(float(remaining) / float(stack_cap)))
	return needed <= free_slots


func get_slot_count() -> int:
	return _slots.size()


func get_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _slots:
		out.append({"id": s["id"], "count": int(s["count"])})
	return out


func add_item(item_id: StringName, amount: int) -> int:
	## Adds up to `amount` items and returns leftover count that could not fit.
	if item_id == &"" or amount <= 0:
		return maxi(0, amount)

	var remaining := amount
	var stack_cap := get_max_stack(item_id)

	# 1) Top up existing partial stacks
	for slot in _slots:
		if remaining <= 0:
			break
		if slot["id"] != item_id:
			continue
		var cur := int(slot["count"])
		var space := stack_cap - cur
		if space > 0:
			var take := mini(space, remaining)
			slot["count"] = cur + take
			remaining -= take

	# 2) Allocate new stacks if slots remain
	while remaining > 0 and (max_slots <= 0 or _slots.size() < max_slots):
		var take := mini(stack_cap, remaining)
		_slots.append({"id": item_id, "count": take})
		remaining -= take

	var added := amount - remaining
	if added > 0:
		item_added.emit(item_id, added)
		inventory_changed.emit()
	return remaining


func remove_item(item_id: StringName, amount: int) -> bool:
	## Atomically removes `amount` items; returns false without mutating if insufficient.
	if amount == 0:
		return true
	if item_id == &"" or amount < 0 or count_item(item_id) < amount:
		return false

	var remaining := amount
	for i in range(_slots.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var slot := _slots[i]
		if slot["id"] != item_id:
			continue
		var cur := int(slot["count"])
		if cur <= remaining:
			remaining -= cur
			_slots.remove_at(i)
		else:
			slot["count"] = cur - remaining
			remaining = 0

	item_removed.emit(item_id, amount)
	inventory_changed.emit()
	return true


func clear() -> void:
	if _slots.is_empty():
		return
	_slots.clear()
	inventory_changed.emit()


func export_state() -> Dictionary:
	var serialized: Array[Dictionary] = []
	for s in _slots:
		serialized.append({
			"id": String(s["id"]),
			"count": int(s["count"]),
		})
	return {
		"max_slots": max_slots,
		"slots": serialized,
	}


func apply_state(doc: Dictionary) -> void:
	if doc.has("max_slots"):
		max_slots = maxi(0, int(doc["max_slots"]))
	_slots.clear()
	var raw_slots: Variant = doc.get("slots", [])
	if raw_slots is Array:
		for entry in raw_slots as Array:
			if not (entry is Dictionary):
				continue
			var d := entry as Dictionary
			var item_id := StringName(str(d.get("id", "")))
			var count := int(d.get("count", 0))
			if item_id != &"" and count > 0:
				_slots.append({"id": item_id, "count": count})
	inventory_changed.emit()
