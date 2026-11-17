class_name QuestTracker
extends RefCounted
## Event-driven and state-synced quest progression tracker with SaveService serialization.

signal quest_started(quest_id: StringName)
signal objective_progressed(quest_id: StringName, objective_id: StringName, current: int, target: int)
signal quest_completed(quest_id: StringName)

var event_bus: Object = null
var flag_store: FlagStore = null
var inventory: InventoryContainer = null
var stats: StatSet = null

var _defs: Dictionary = {} ## StringName -> QuestDef
var _order: Array[StringName] = []
var _active: Dictionary = {} ## StringName -> Dictionary (obj_id: String -> int)
var _completed: Dictionary = {} ## StringName -> bool
var _event_callbacks: Dictionary = {} ## StringName -> Callable
var _bound_inv_cb: Callable = Callable()
var _bound_flag_cb: Callable = Callable()


func bind(
	p_event_bus: Object = null,
	p_flag_store: FlagStore = null,
	p_inventory: InventoryContainer = null,
	p_stats: StatSet = null
) -> void:
	unbind()
	event_bus = p_event_bus
	flag_store = p_flag_store
	inventory = p_inventory
	stats = p_stats

	if inventory != null:
		_bound_inv_cb = func(_item_id: StringName = &"", _amount: int = 0) -> void:
			sync_stateful_objectives()
		if not inventory.inventory_changed.is_connected(sync_stateful_objectives):
			inventory.inventory_changed.connect(sync_stateful_objectives)

	if flag_store != null:
		_bound_flag_cb = func(_fid: StringName, _old_v: Variant, _new_v: Variant) -> void:
			sync_stateful_objectives()
		if not flag_store.flag_changed.is_connected(_bound_flag_cb):
			flag_store.flag_changed.connect(_bound_flag_cb)

	_subscribe_all_registered_events()
	sync_stateful_objectives()


func unbind() -> void:
	if event_bus != null and is_instance_valid(event_bus) and event_bus.has_method("unsubscribe"):
		for ev_name: StringName in _event_callbacks:
			var cb: Callable = _event_callbacks[ev_name] as Callable
			event_bus.call("unsubscribe", ev_name, cb)
	_event_callbacks.clear()

	if inventory != null and inventory.inventory_changed.is_connected(sync_stateful_objectives):
		inventory.inventory_changed.disconnect(sync_stateful_objectives)

	if flag_store != null and _bound_flag_cb.is_valid() and flag_store.flag_changed.is_connected(_bound_flag_cb):
		flag_store.flag_changed.disconnect(_bound_flag_cb)

	_bound_inv_cb = Callable()
	_bound_flag_cb = Callable()


func register_quest(def: QuestDef) -> bool:
	if def == null or not def.is_valid():
		return false
	if not _defs.has(def.id):
		_order.append(def.id)
	_defs[def.id] = def
	_subscribe_quest_events(def)
	if def.auto_start and not is_active(def.id) and not is_completed(def.id):
		start_quest(def.id)
	return true


func register_from_rows(rows: Array[Dictionary]) -> int:
	var count := 0
	for row in rows:
		var def := QuestDef.from_dict(row)
		if register_quest(def):
			count += 1
	return count


func start_quest(quest_id: StringName) -> bool:
	if not _defs.has(quest_id) or is_active(quest_id) or is_completed(quest_id):
		return false
	var def := _defs[quest_id] as QuestDef
	var progress: Dictionary = {}
	for i in def.objectives.size():
		var obj := def.objectives[i]
		var oid := _objective_id(obj, i)
		progress[oid] = 0
	_active[quest_id] = progress
	quest_started.emit(quest_id)
	_sync_quest_stateful_objectives(quest_id)
	_try_complete_quest(quest_id)
	return true


func is_active(quest_id: StringName) -> bool:
	return _active.has(quest_id)


func is_completed(quest_id: StringName) -> bool:
	return bool(_completed.get(quest_id, false))


func get_quest_status(quest_id: StringName) -> Dictionary:
	if not _defs.has(quest_id):
		return {"state": "unknown", "objectives": [], "done": 0, "total": 0}
	var def := _defs[quest_id] as QuestDef
	var state_str := "completed" if is_completed(quest_id) else ("active" if is_active(quest_id) else "inactive")
	var progress: Dictionary = _active.get(quest_id, {}) as Dictionary
	var objs_out: Array[Dictionary] = []
	var done_count := 0

	for i in def.objectives.size():
		var obj := def.objectives[i]
		var oid := _objective_id(obj, i)
		var target := maxi(1, int(obj.get("target", 1)))
		var cur := target if state_str == "completed" else mini(target, int(progress.get(oid, 0)))
		if cur >= target:
			done_count += 1
		objs_out.append({
			"id": oid,
			"description": str(obj.get("description", oid)),
			"current": cur,
			"target": target,
			"completed": cur >= target,
		})

	return {
		"id": quest_id,
		"title": def.title,
		"state": state_str,
		"objectives": objs_out,
		"done": done_count,
		"total": def.objectives.size(),
	}


func list_active_quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for qid: StringName in _order:
		if is_active(qid):
			out.append(get_quest_status(qid))
	return out


func handle_event(event_name: StringName, payload: Dictionary = {}) -> void:
	if event_name == &"" or _active.is_empty():
		return
	var active_ids: Array = _active.keys()
	for raw_qid in active_ids:
		var qid := raw_qid as StringName
		if not _active.has(qid) or not _defs.has(qid):
			continue
		var def := _defs[qid] as QuestDef
		var progress := _active[qid] as Dictionary
		var changed := false

		for i in def.objectives.size():
			var obj := def.objectives[i]
			var otype := str(obj.get("type", "event"))
			if otype != "event":
				continue
			var expected_ev := StringName(str(obj.get("event", "")))
			if expected_ev != event_name:
				continue
			var filter: Variant = obj.get("filter", {})
			if filter is Dictionary and not _payload_matches(payload, filter as Dictionary):
				continue

			var oid := _objective_id(obj, i)
			var target := maxi(1, int(obj.get("target", 1)))
			var cur := int(progress.get(oid, 0))
			if cur >= target:
				continue
			var inc := maxi(1, int(obj.get("increment", 1)))
			var next := mini(target, cur + inc)
			if next != cur:
				progress[oid] = next
				changed = true
				objective_progressed.emit(qid, StringName(oid), next, target)

		if changed:
			_try_complete_quest(qid)


func sync_stateful_objectives() -> void:
	if _active.is_empty():
		return
	var active_ids: Array = _active.keys()
	for raw_qid in active_ids:
		var qid := raw_qid as StringName
		if _sync_quest_stateful_objectives(qid):
			_try_complete_quest(qid)


func export_state() -> Dictionary:
	var active_out: Dictionary = {}
	for qid: StringName in _active:
		var prog := _active[qid] as Dictionary
		var p_out: Dictionary = {}
		for oid in prog:
			p_out[str(oid)] = int(prog[oid])
		active_out[String(qid)] = p_out

	var comp_out: Array[String] = []
	for qid: StringName in _completed:
		if bool(_completed[qid]):
			comp_out.append(String(qid))
	comp_out.sort()

	return {
		"active": active_out,
		"completed": comp_out,
	}


func apply_state(doc: Dictionary) -> void:
	_active.clear()
	_completed.clear()

	var raw_comp: Variant = doc.get("completed", [])
	if raw_comp is Array:
		for raw_id in raw_comp as Array:
			var qid := StringName(str(raw_id))
			if qid != &"":
				_completed[qid] = true

	var raw_act: Variant = doc.get("active", {})
	if raw_act is Dictionary:
		for raw_id in raw_act as Dictionary:
			var qid := StringName(str(raw_id))
			if qid == &"" or is_completed(qid):
				continue
			var prog_raw: Variant = (raw_act as Dictionary)[raw_id]
			var prog_clean: Dictionary = {}
			if prog_raw is Dictionary:
				for oid in prog_raw as Dictionary:
					prog_clean[str(oid)] = int((prog_raw as Dictionary)[oid])
			_active[qid] = prog_clean

	sync_stateful_objectives()


func _sync_quest_stateful_objectives(qid: StringName) -> bool:
	if not _active.has(qid) or not _defs.has(qid):
		return false
	var def := _defs[qid] as QuestDef
	var progress := _active[qid] as Dictionary
	var any_changed := false

	for i in def.objectives.size():
		var obj := def.objectives[i]
		var otype := str(obj.get("type", "event"))
		var oid := _objective_id(obj, i)
		var target := maxi(1, int(obj.get("target", 1)))
		var cur := int(progress.get(oid, 0))
		var next := cur

		if otype == "inventory_count" and inventory != null:
			var item_id := StringName(str(obj.get("item_id", "")))
			next = mini(target, inventory.count_item(item_id))
		elif otype == "flag" and flag_store != null:
			var flag_id := StringName(str(obj.get("flag_id", "")))
			if obj.has("flag_value"):
				var expected: Variant = obj["flag_value"]
				next = target if flag_store.get_flag(flag_id, null) == expected else 0
			else:
				next = mini(target, flag_store.get_int(flag_id, 0))
		else:
			continue

		if next != cur:
			progress[oid] = next
			any_changed = true
			objective_progressed.emit(qid, StringName(oid), next, target)

	return any_changed


func _try_complete_quest(qid: StringName) -> void:
	if not _active.has(qid) or not _defs.has(qid):
		return
	var def := _defs[qid] as QuestDef
	var progress := _active[qid] as Dictionary

	for i in def.objectives.size():
		var obj := def.objectives[i]
		var oid := _objective_id(obj, i)
		var target := maxi(1, int(obj.get("target", 1)))
		if int(progress.get(oid, 0)) < target:
			return

	_active.erase(qid)
	_completed[qid] = true
	_grant_rewards(def)
	quest_completed.emit(qid)


func _grant_rewards(def: QuestDef) -> void:
	for rew in def.rewards:
		var rtype := str(rew.get("type", ""))
		match rtype:
			"item":
				if inventory != null:
					var item_id := StringName(str(rew.get("id", "")))
					var amt := maxi(1, int(rew.get("amount", 1)))
					inventory.add_item(item_id, amt)
			"stat":
				if stats != null:
					var stat_id := StringName(str(rew.get("id", "")))
					var delta := float(rew.get("delta", 0.0))
					stats.modify_value(stat_id, delta)
			"flag":
				if flag_store != null:
					var flag_id := StringName(str(rew.get("id", "")))
					flag_store.set_flag(flag_id, rew.get("value", true))


func _subscribe_all_registered_events() -> void:
	for qid: StringName in _order:
		_subscribe_quest_events(_defs[qid] as QuestDef)


func _subscribe_quest_events(def: QuestDef) -> void:
	if event_bus == null or not is_instance_valid(event_bus) or not event_bus.has_method("subscribe"):
		return
	for obj in def.objectives:
		if str(obj.get("type", "event")) != "event":
			continue
		var ev_name := StringName(str(obj.get("event", "")))
		if ev_name == &"" or _event_callbacks.has(ev_name):
			continue
		var cb := func(payload: Dictionary = {}) -> void:
			handle_event(ev_name, payload)
		_event_callbacks[ev_name] = cb
		event_bus.call("subscribe", ev_name, cb)


func _payload_matches(payload: Dictionary, filter: Dictionary) -> bool:
	for k in filter:
		if not payload.has(k) or payload[k] != filter[k]:
			return false
	return true


func _objective_id(obj: Dictionary, idx: int) -> String:
	var oid := str(obj.get("id", ""))
	return oid if oid != "" else "obj_%d" % idx
