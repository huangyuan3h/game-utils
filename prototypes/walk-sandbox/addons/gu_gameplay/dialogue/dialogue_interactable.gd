class_name DialogueInteractable
extends Interactable
## NPC or object that opens the scene DialogueBox with a bound DialogueDef.

@export var dialogue: DialogueDef
@export var display_name: String = ""

var _label: Label3D


func _ready() -> void:
	if prompt_text == "Interact" or prompt_text == "":
		prompt_text = "Talk"
	super._ready()
	_ensure_visual()


func _can_interact(_actor: Node) -> bool:
	return dialogue != null


func _on_interact(_actor: Node) -> void:
	var box := _find_box()
	if box == null or dialogue == null:
		return
	box.start(dialogue)


func _find_box() -> DialogueBox:
	var tree := get_tree()
	if tree == null:
		return null
	var found := tree.get_nodes_in_group(DialogueBox.GROUP_NAME)
	for node in found:
		if node is DialogueBox:
			return node as DialogueBox
	return null


func _ensure_visual() -> void:
	if get_node_or_null("Visual") != null:
		return
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.32
	mesh.height = 1.5
	visual.mesh = mesh
	visual.position = Vector3(0.0, 0.75, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.81, 0.40)
	visual.material_override = mat
	add_child(visual)

	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.text = display_name if display_name != "" else "NPC"
	_label.position = Vector3(0.0, 1.7, 0.0)
	_label.font_size = 28
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(0.95, 0.86, 0.55)
	add_child(_label)
