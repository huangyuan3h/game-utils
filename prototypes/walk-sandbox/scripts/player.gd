extends CharacterBody3D
## 8-direction walk controller (WASD / arrow keys).

const SPEED := 4.5
const MODEL_PATH := "res://assets/models/walker.glb"
const FALLBACK_MODEL := "res://assets/models/settler.glb"

@onready var _visual_root: Node3D = $VisualRoot
@onready var _label: Label3D = $NameLabel


func _ready() -> void:
	_ensure_input_map()
	_load_model()
	_label.text = "Player\nWASD / Arrows"


func _physics_process(_delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# XZ plane: forward is -Z in Godot
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		# Face movement direction (keep upright)
		var look_at_pos := global_position + Vector3(direction.x, 0.0, direction.z)
		if look_at_pos.distance_squared_to(global_position) > 0.0001:
			look_at(look_at_pos, Vector3.UP)
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	velocity.y = 0.0
	move_and_slide()


func _ensure_input_map() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _load_model() -> void:
	for child in _visual_root.get_children():
		child.queue_free()

	var packed: PackedScene = null
	if ResourceLoader.exists(MODEL_PATH):
		packed = load(MODEL_PATH) as PackedScene
	elif ResourceLoader.exists(FALLBACK_MODEL):
		packed = load(FALLBACK_MODEL) as PackedScene

	if packed == null:
		# Capsule placeholder if GLB not imported yet
		var mesh_instance := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.25
		capsule.height = 1.2
		mesh_instance.mesh = capsule
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.55, 0.35)
		mesh_instance.material_override = mat
		mesh_instance.position.y = 0.6
		_visual_root.add_child(mesh_instance)
		_label.text = "Placeholder\n(open once in editor to import GLB)"
		return

	var model := packed.instantiate() as Node3D
	_visual_root.add_child(model)
	# Typical Kenney/civ-scale models may need a small lift
	model.position = Vector3(0, 0, 0)
