class_name Interactable
extends Area3D
## Base 3D interactable volume. Subclasses override _can_interact / _on_interact.

signal interacted(actor: Node)

const GROUP_NAME := &"gu_interactables"
const INTERACT_LAYER := 1 << 3

@export var interaction_id: String = ""
@export var prompt_text: String = "Interact"
@export var enabled: bool = true
@export var interaction_radius: float = 1.8
@export var interaction_priority: int = 0


func _enter_tree() -> void:
	if not is_in_group(GROUP_NAME):
		add_to_group(GROUP_NAME)


func _ready() -> void:
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	_ensure_collision_shape()


func can_interact(actor: Node) -> bool:
	if not enabled or not is_inside_tree():
		return false
	if actor != null and not is_instance_valid(actor):
		return false
	return _can_interact(actor)


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	_on_interact(actor)
	interacted.emit(actor)
	return true


func get_prompt_text() -> String:
	return prompt_text


func _can_interact(_actor: Node) -> bool:
	return true


func _on_interact(_actor: Node) -> void:
	pass


func _ensure_collision_shape() -> void:
	for ch in get_children():
		if ch is CollisionShape3D:
			return
	var cs := CollisionShape3D.new()
	cs.name = "InteractShape"
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(interaction_radius, 0.25)
	cs.shape = sphere
	add_child(cs)
