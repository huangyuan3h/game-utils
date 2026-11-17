class_name Interactor
extends Area3D
## Detects nearest valid Interactable in range and triggers interaction on gameplay input.

signal focus_changed(interactable: Interactable)

const INTERACT_MASK := Interactable.INTERACT_LAYER

@export var interact_action: StringName = &"interact"
@export var interact_range: float = 2.6
@export var actor_path: NodePath
@export var auto_bind_input: bool = true

var input_router: Node = null

var _focused: Interactable = null
var _actor_override: Node = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = INTERACT_MASK
	monitoring = true
	monitorable = false
	_ensure_collision_shape()
	if auto_bind_input:
		_ensure_interact_action()


func set_actor(actor: Node) -> void:
	_actor_override = actor


func get_actor() -> Node:
	if _actor_override != null and is_instance_valid(_actor_override):
		return _actor_override
	if not actor_path.is_empty():
		var target := get_node_or_null(actor_path)
		if target != null:
			return target
	return get_parent()


func get_focused() -> Interactable:
	if _focused != null and is_instance_valid(_focused):
		return _focused
	return null


func refresh_focus() -> Interactable:
	if not is_inside_tree():
		_set_focused(null)
		return null

	var actor := get_actor()
	var origin := global_position
	var candidates: Dictionary = {}

	for area in get_overlapping_areas():
		if area is Interactable:
			candidates[area.get_instance_id()] = area

	var tree := get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group(Interactable.GROUP_NAME):
			if node is Interactable:
				var inter := node as Interactable
				if not is_instance_valid(inter) or not inter.is_inside_tree():
					continue
				var max_d := maxf(interact_range, inter.interaction_radius)
				if origin.distance_to(inter.global_position) <= max_d:
					candidates[inter.get_instance_id()] = inter

	var best: Interactable = null
	var best_priority := -2147483648
	var best_dist_sq := INF

	for key in candidates:
		var cand := candidates[key] as Interactable
		if cand == null or not is_instance_valid(cand) or not cand.can_interact(actor):
			continue
		var d2 := origin.distance_squared_to(cand.global_position)
		if cand.interaction_priority > best_priority or (
			cand.interaction_priority == best_priority and d2 < best_dist_sq
		):
			best = cand
			best_priority = cand.interaction_priority
			best_dist_sq = d2

	_set_focused(best)
	return _focused


func try_interact() -> bool:
	if not _is_gameplay_active():
		return false
	var target := refresh_focus()
	if target == null:
		return false
	return target.interact(get_actor())


func _physics_process(_delta: float) -> void:
	refresh_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(interact_action):
		return
	if not event.is_action_pressed(interact_action):
		return
	if not _is_gameplay_active():
		return
	if try_interact():
		get_viewport().set_input_as_handled()


func _set_focused(next_target: Interactable) -> void:
	var prev_valid := _focused if (_focused != null and is_instance_valid(_focused)) else null
	if prev_valid == next_target:
		return
	_focused = next_target
	focus_changed.emit(_focused)


func _is_gameplay_active() -> bool:
	var router := input_router
	if router == null or not is_instance_valid(router):
		router = get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("is_gameplay_active"):
		return bool(router.call("is_gameplay_active"))
	return true


func _ensure_collision_shape() -> void:
	for ch in get_children():
		if ch is CollisionShape3D:
			return
	var cs := CollisionShape3D.new()
	cs.name = "DetectorShape"
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(interact_range, 0.5)
	cs.shape = sphere
	add_child(cs)


func _ensure_interact_action() -> void:
	var ir := get_node_or_null("/root/InputRouter")
	if ir != null and ir.has_method("register_action"):
		ir.call("register_action", interact_action, [KEY_E], "Interact")
		return
	var action_name := String(interact_action)
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	if not InputMap.action_has_event(action_name, ev):
		InputMap.action_add_event(action_name, ev)
