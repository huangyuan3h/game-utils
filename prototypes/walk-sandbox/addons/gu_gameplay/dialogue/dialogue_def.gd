class_name DialogueDef
extends Resource
## Declarative branching dialogue. Nodes are dictionaries so the same graph
## can be authored in the Inspector or loaded from DataTableLoader rows.

const CONDITION_TYPES: Array[String] = ["flag", "quest", "item"]
const EFFECT_TYPES: Array[String] = ["set_flag", "inc_flag", "start_quest", "add_item", "remove_item", "emit_event"]
const FLAG_OPS: Array[String] = ["eq", "neq", "gt", "gte", "lt", "lte", "exists"]
const QUEST_STATES: Array[String] = ["inactive", "active", "completed", "not_completed"]

@export var id: StringName = &""
@export var start: StringName = &""
@export var nodes: Array[Dictionary] = []


static func from_dict(d: Dictionary) -> DialogueDef:
	var def := DialogueDef.new()
	def.id = StringName(str(d.get("id", "")))
	def.start = StringName(str(d.get("start", "")))
	var raw_nodes: Variant = d.get("nodes", [])
	if raw_nodes is Array:
		for raw in raw_nodes as Array:
			if raw is Dictionary:
				def.nodes.append((raw as Dictionary).duplicate(true))
	return def


func get_node(node_id: StringName) -> Dictionary:
	if node_id == &"":
		return {}
	for node in nodes:
		if StringName(str(node.get("id", ""))) == node_id:
			return node
	return {}


func is_valid() -> bool:
	if id == &"" or start == &"" or nodes.is_empty():
		return false
	var ids: Dictionary = {}
	for node in nodes:
		var node_id := StringName(str(node.get("id", "")))
		if node_id == &"" or ids.has(node_id):
			return false
		if not _node_shape_ok(node):
			return false
		ids[node_id] = true
	if not ids.has(start):
		return false
	for node in nodes:
		if not _refs_ok(node, ids):
			return false
	return true


func _node_shape_ok(node: Dictionary) -> bool:
	if not _list_ok(node.get("effects", []), true):
		return false
	if not _choice_list_ok(node.get("choices", [])):
		return false
	var branches: Variant = node.get("branches", [])
	if not (branches is Array):
		return false
	for raw in branches as Array:
		if not (raw is Dictionary):
			return false
		var branch := raw as Dictionary
		if not _list_ok(branch.get("conditions", []), false):
			return false
	return true


func _choice_list_ok(raw_choices: Variant) -> bool:
	if not (raw_choices is Array):
		return false
	for raw in raw_choices as Array:
		if not (raw is Dictionary):
			return false
		var choice := raw as Dictionary
		if not _list_ok(choice.get("conditions", []), false):
			return false
		if not _list_ok(choice.get("effects", []), true):
			return false
	return true


func _list_ok(raw_list: Variant, is_effect: bool) -> bool:
	if not (raw_list is Array):
		return false
	for raw in raw_list as Array:
		if not (raw is Dictionary):
			return false
		var entry := raw as Dictionary
		var kind := str(entry.get("type", ""))
		if is_effect:
			if not EFFECT_TYPES.has(kind) or not _effect_fields_ok(entry, kind):
				return false
		elif not CONDITION_TYPES.has(kind) or not _condition_fields_ok(entry, kind):
			return false
	return true


func _condition_fields_ok(entry: Dictionary, kind: String) -> bool:
	match kind:
		"flag":
			if StringName(str(entry.get("id", ""))) == &"":
				return false
			var op := str(entry.get("op", "eq"))
			return FLAG_OPS.has(op)
		"quest":
			if StringName(str(entry.get("id", ""))) == &"":
				return false
			return QUEST_STATES.has(str(entry.get("state", "")))
		"item":
			return StringName(str(entry.get("id", ""))) != &""
		_:
			return false


func _effect_fields_ok(entry: Dictionary, kind: String) -> bool:
	match kind:
		"set_flag", "inc_flag", "start_quest", "add_item", "remove_item":
			return StringName(str(entry.get("id", ""))) != &""
		"emit_event":
			return StringName(str(entry.get("event", ""))) != &""
		_:
			return false


func _refs_ok(node: Dictionary, ids: Dictionary) -> bool:
	if not _target_ok(node.get("next", ""), ids):
		return false
	for raw in node.get("choices", []) as Array:
		if not _target_ok((raw as Dictionary).get("next", ""), ids):
			return false
	for raw in node.get("branches", []) as Array:
		if not _target_ok((raw as Dictionary).get("next", ""), ids):
			return false
	return true


func _target_ok(raw_next: Variant, ids: Dictionary) -> bool:
	var next_id := StringName(str(raw_next))
	return next_id == &"" or ids.has(next_id)
