class_name DialogueRunner
extends RefCounted
## Evaluates a DialogueDef against flags, quests, and inventory.
## Item effects are preflighted and applied as one exchange: all removes, then all adds.
## Signals and quest starts run only after that exchange succeeds.

signal advanced(view: Dictionary)
signal ended(dialogue_id: StringName)
signal blocked(reason: String)

var flags: FlagStore = null
var quests: QuestTracker = null
var inventory: InventoryContainer = null
var event_bus: Object = null

var _def: DialogueDef = null
var _node_id: StringName = &""
var _active: bool = false


func bind(
	p_flags: FlagStore = null,
	p_quests: QuestTracker = null,
	p_inventory: InventoryContainer = null,
	p_event_bus: Object = null
) -> void:
	flags = p_flags
	quests = p_quests
	inventory = p_inventory
	event_bus = p_event_bus


func is_active() -> bool:
	return _active


func start(def: DialogueDef) -> Dictionary:
	if def == null or not def.is_valid():
		_active = false
		_def = def
		_node_id = &""
		return _ended_view("invalid_def", false)
	_def = def
	_node_id = &""
	_active = true
	return _go_to(def.start, true)


func choose(index: int) -> Dictionary:
	if not _active:
		return _ended_view("not_started", false)
	var node := _current_node()
	var raw_choices: Variant = node.get("choices", [])
	if not (raw_choices is Array):
		return _fail("bad_choice")
	var choices := raw_choices as Array
	if index < 0 or index >= choices.size() or not (choices[index] is Dictionary):
		return _fail("bad_choice")
	var choice := choices[index] as Dictionary
	if not _conditions_pass(choice.get("conditions", [])):
		return _fail("choice_unavailable")
	var err := _apply_effects(choice.get("effects", []))
	if err != "":
		return _fail(err)
	return _go_to(StringName(str(choice.get("next", ""))), false)


func continue_line() -> Dictionary:
	if not _active:
		return _ended_view("not_started", false)
	var node := _current_node()
	if not _visible_choices(node).is_empty():
		return _fail("choice_required")
	if not _has_advance(node):
		return _finish()
	return _go_to(_resolve_next(node), false)


func close() -> Dictionary:
	if not _active:
		return _ended_view("", true)
	return _finish()


func _go_to(next_id: StringName, from_start: bool) -> Dictionary:
	if next_id == &"":
		if from_start:
			_active = false
			return _ended_view("missing_node", false)
		return _finish()
	var node := _def.get_node(next_id) if _def != null else {}
	if node.is_empty():
		if from_start:
			_active = false
			return _ended_view("missing_node", false)
		return _fail("missing_node")
	var err := _apply_effects(node.get("effects", []))
	if err != "":
		if from_start:
			_active = false
			return _ended_view(err, false)
		return _fail(err)
	_node_id = next_id
	var view := _make_view("")
	advanced.emit(view)
	return view


func _finish() -> Dictionary:
	var dialogue_id := _def.id if _def != null else &""
	_active = false
	_node_id = &""
	var view := _ended_view("", true)
	ended.emit(dialogue_id)
	return view


func _fail(reason: String) -> Dictionary:
	blocked.emit(reason)
	return _make_view(reason)


func _current_node() -> Dictionary:
	if _def == null:
		return {}
	return _def.get_node(_node_id)


func _make_view(error: String) -> Dictionary:
	var node := _current_node()
	var visible := _visible_choices(node)
	var can_continue := visible.is_empty() and _has_advance(node)
	var terminal := visible.is_empty() and not can_continue
	return {
		"ok": error == "",
		"ended": false,
		"error": error,
		"node_id": _node_id,
		"speaker": str(node.get("speaker", "")),
		"text": str(node.get("text", "")),
		"choices": visible,
		"can_continue": can_continue,
		"terminal": terminal,
		"dialogue_id": _def.id if _def != null else &"",
	}


func _ended_view(error: String, ok: bool) -> Dictionary:
	return {
		"ok": ok and error == "",
		"ended": true,
		"error": error,
		"node_id": &"",
		"speaker": "",
		"text": "",
		"choices": [] as Array[Dictionary],
		"can_continue": false,
		"terminal": false,
		"dialogue_id": _def.id if _def != null else &"",
	}


func _visible_choices(node: Dictionary) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	var raw_choices: Variant = node.get("choices", [])
	if not (raw_choices is Array):
		return visible
	var index := 0
	for raw in raw_choices as Array:
		if raw is Dictionary:
			var choice := raw as Dictionary
			if _conditions_pass(choice.get("conditions", [])):
				visible.append({
					"index": index,
					"text": str(choice.get("text", "")),
				})
		index += 1
	return visible


func _has_advance(node: Dictionary) -> bool:
	var branches: Variant = node.get("branches", [])
	if branches is Array and not (branches as Array).is_empty():
		return true
	return StringName(str(node.get("next", ""))) != &""


func _resolve_next(node: Dictionary) -> StringName:
	var branches: Variant = node.get("branches", [])
	if branches is Array:
		for raw in branches as Array:
			if not (raw is Dictionary):
				continue
			var branch := raw as Dictionary
			if _conditions_pass(branch.get("conditions", [])):
				return StringName(str(branch.get("next", "")))
	return StringName(str(node.get("next", "")))


func _conditions_pass(raw_conditions: Variant) -> bool:
	if not (raw_conditions is Array):
		return false
	for raw in raw_conditions as Array:
		if not (raw is Dictionary) or not _condition_pass(raw as Dictionary):
			return false
	return true


func _condition_pass(entry: Dictionary) -> bool:
	match str(entry.get("type", "")):
		"flag":
			return _flag_pass(entry)
		"quest":
			return _quest_pass(entry)
		"item":
			return _item_pass(entry)
		_:
			return false


func _flag_pass(entry: Dictionary) -> bool:
	if flags == null:
		return false
	var flag_id := StringName(str(entry.get("id", "")))
	var op := str(entry.get("op", "eq"))
	if op == "exists":
		return flags.has_flag(flag_id)
	if not flags.has_flag(flag_id) and op != "neq":
		return false
	var actual: Variant = flags.get_flag(flag_id, null)
	var expected: Variant = entry.get("value", null)
	match op:
		"eq":
			return _values_equal(actual, expected)
		"neq":
			return not _values_equal(actual, expected)
		"gt", "gte", "lt", "lte":
			return _numbers_compare(actual, expected, op)
		_:
			return false


func _quest_pass(entry: Dictionary) -> bool:
	if quests == null:
		return false
	var quest_id := StringName(str(entry.get("id", "")))
	var state := str(entry.get("state", ""))
	match state:
		"active":
			return quests.is_active(quest_id)
		"completed":
			return quests.is_completed(quest_id)
		"inactive":
			return not quests.is_active(quest_id) and not quests.is_completed(quest_id)
		"not_completed":
			return not quests.is_completed(quest_id)
		_:
			return false


func _item_pass(entry: Dictionary) -> bool:
	if inventory == null:
		return false
	var item_id := StringName(str(entry.get("id", "")))
	var amount := int(entry.get("amount", 1))
	return inventory.has_item(item_id, amount)


func _values_equal(actual: Variant, expected: Variant) -> bool:
	if _is_number(actual) and _is_number(expected):
		return is_equal_approx(_as_number(actual), _as_number(expected))
	return actual == expected


func _numbers_compare(actual: Variant, expected: Variant, op: String) -> bool:
	if not _is_number(actual) or not _is_number(expected):
		return false
	var a := _as_number(actual)
	var b := _as_number(expected)
	match op:
		"gt":
			return a > b
		"gte":
			return a >= b or is_equal_approx(a, b)
		"lt":
			return a < b
		"lte":
			return a <= b or is_equal_approx(a, b)
		_:
			return false


func _is_number(value: Variant) -> bool:
	return value is int or value is float or value is bool


func _as_number(value: Variant) -> float:
	if value is bool:
		return 1.0 if value else 0.0
	return float(value)


func _apply_effects(raw_effects: Variant) -> String:
	if not (raw_effects is Array):
		return "unknown_effect"
	var effects := raw_effects as Array
	var err := _preflight(effects)
	if err != "":
		return err
	err = _apply_items(effects)
	if err != "":
		return err
	for raw in effects:
		if not (raw is Dictionary):
			continue
		var effect := raw as Dictionary
		match str(effect.get("type", "")):
			"set_flag":
				flags.set_flag(StringName(str(effect.get("id", ""))), effect.get("value", true))
			"inc_flag":
				flags.inc_counter(StringName(str(effect.get("id", ""))), int(effect.get("delta", 1)))
			"start_quest":
				var quest_id := StringName(str(effect.get("id", "")))
				if not quests.is_active(quest_id) and not quests.is_completed(quest_id):
					quests.start_quest(quest_id)
	if event_bus != null:
		for raw in effects:
			if not (raw is Dictionary):
				continue
			var effect := raw as Dictionary
			if str(effect.get("type", "")) != "emit_event":
				continue
			var payload: Variant = effect.get("payload", {})
			var data: Dictionary = payload as Dictionary if payload is Dictionary else {}
			event_bus.call("emit_event", StringName(str(effect.get("event", ""))), data)
	return ""


func _preflight(effects: Array) -> String:
	var removes: Dictionary = {}
	var adds: Dictionary = {}
	for raw in effects:
		if not (raw is Dictionary):
			return "unknown_effect"
		var effect := raw as Dictionary
		var kind := str(effect.get("type", ""))
		match kind:
			"set_flag", "inc_flag":
				if flags == null:
					return "no_flags"
				if StringName(str(effect.get("id", ""))) == &"":
					return "bad_flag"
			"start_quest":
				if quests == null:
					return "no_quests"
				var quest_id := StringName(str(effect.get("id", "")))
				if str(quests.get_quest_status(quest_id).get("state", "")) == "unknown":
					return "unknown_quest"
			"add_item", "remove_item":
				if inventory == null:
					return "no_inventory"
				var item_id := StringName(str(effect.get("id", "")))
				var amount := int(effect.get("amount", 1))
				if item_id == &"" or amount <= 0:
					return "bad_amount"
				var bucket := adds if kind == "add_item" else removes
				bucket[item_id] = int(bucket.get(item_id, 0)) + amount
			"emit_event":
				if event_bus == null or not is_instance_valid(event_bus) or not event_bus.has_method("emit_event"):
					return "no_event_bus"
				if StringName(str(effect.get("event", ""))) == &"":
					return "bad_event"
			_:
				return "unknown_effect"
	if removes.is_empty() and adds.is_empty():
		return ""
	for item_id in removes:
		if not inventory.has_item(item_id, int(removes[item_id])):
			return "missing_item"
	var sim := _simulation(adds.keys())
	for item_id in removes:
		if not sim.remove_item(item_id, int(removes[item_id])):
			return "missing_item"
	for item_id in adds:
		var amount := int(adds[item_id])
		if not sim.can_add(item_id, amount) or sim.add_item(item_id, amount) != 0:
			return "inventory_full"
	return ""


func _apply_items(effects: Array) -> String:
	var removes: Dictionary = {}
	var adds: Dictionary = {}
	for raw in effects:
		var effect := raw as Dictionary
		var kind := str(effect.get("type", ""))
		if kind != "add_item" and kind != "remove_item":
			continue
		var item_id := StringName(str(effect.get("id", "")))
		var amount := int(effect.get("amount", 1))
		var bucket := adds if kind == "add_item" else removes
		bucket[item_id] = int(bucket.get(item_id, 0)) + amount
	if removes.is_empty() and adds.is_empty():
		return ""
	var snapshot := inventory.export_state()
	for item_id in removes:
		if not inventory.remove_item(item_id, int(removes[item_id])):
			inventory.apply_state(snapshot)
			return "missing_item"
	for item_id in adds:
		if inventory.add_item(item_id, int(adds[item_id])) != 0:
			inventory.apply_state(snapshot)
			return "inventory_full"
	return ""


func _simulation(extra_ids: Array) -> InventoryContainer:
	var sim := InventoryContainer.new(inventory.max_slots, inventory.default_max_stack)
	var seen: Dictionary = {}
	for slot in inventory.get_slots():
		_copy_item_def(sim, slot["id"], seen)
	for raw_id in extra_ids:
		_copy_item_def(sim, raw_id, seen)
	sim.apply_state(inventory.export_state())
	return sim


func _copy_item_def(sim: InventoryContainer, raw_id: Variant, seen: Dictionary) -> void:
	var item_id := StringName(raw_id)
	if item_id == &"" or seen.has(item_id):
		return
	seen[item_id] = true
	var def := inventory.get_item_def(item_id)
	if def != null:
		sim.register_item(def)
