class_name GuEnemy
extends CharacterBody3D
## Navmesh-driven patrol/chase/attack enemy sample.
## Perception and mode transitions come from AiAgent; movement follows NavigationAgent3D.
## When a terrain object is supplied, the body snaps to its height so the same enemy
## works on procedural ground and on flat starter scenes.

signal attack_landed(target: Node, amount: float)
signal defeated(enemy: GuEnemy)
signal respawned(enemy: GuEnemy)

const GROUP_NAME := &"gu_enemies"
const FEET_OFFSET := 0.02

const AiAgentScript = preload("res://addons/gu_gameplay/ai/agent.gd")

@export_group("Movement")
@export var patrol_speed: float = 1.7
@export var chase_speed: float = 3.4
@export var patrol_radius: float = 7.0
@export var sight_range: float = 9.0
@export var sight_angle_deg: float = 65.0
@export var leash_timeout: float = 2.5

@export_group("Combat")
@export var attack_range: float = 1.8
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.3
@export var max_hp: float = 45.0
@export var respawn_seconds: float = 8.0

@export_group("Visual")
@export var display_name: String = "Enemy"
@export_file("*.glb", "*.tscn") var model_path: String = ""
@export var model_scale: float = 1.0
@export var body_color: Color = Color(0.78, 0.3, 0.26)

var terrain: Object = null
var target: Node3D = null
var spawn_position: Vector3 = Vector3.ZERO

var _agent := AiAgentScript.new()
var _nav: NavigationAgent3D = null
var _health: HealthComponent = null
var _hurtbox: Hurtbox = null
var _hitbox: Hitbox = null
var _visual: Node3D = null
var _label: Label3D = null
var _rng := RandomNumberGenerator.new()
var _facing: float = 0.0
var _attack_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _dead: bool = false


func setup(p_terrain: Object, p_target: Node3D, at: Vector3) -> void:
	terrain = p_terrain
	target = p_target
	spawn_position = at
	_wander_target = at
	if is_inside_tree():
		global_position = at
	else:
		position = at


func set_target(p_target: Node3D) -> void:
	target = p_target


func get_health() -> HealthComponent:
	return _health


func get_hurtbox() -> Hurtbox:
	return _hurtbox


func is_dead() -> bool:
	return _dead


func _ready() -> void:
	add_to_group(GROUP_NAME)
	collision_layer = 0
	collision_mask = 0
	_rng.randomize()
	if spawn_position == Vector3.ZERO:
		spawn_position = global_position
		_wander_target = spawn_position
	_ensure_navigation()
	_ensure_combat()
	_ensure_visual()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)

	var present := _target_valid()
	var target_pos := target.global_position if present else global_position
	var target_distance := global_position.distance_to(target_pos) if present else INF
	_agent.sight_range = sight_range
	_agent.sight_angle_deg = sight_angle_deg
	_agent.leash_timeout = leash_timeout
	_agent.move_speed = patrol_speed
	var forward := Vector3(-sin(_facing), 0.0, -cos(_facing))
	_agent.tick(delta, global_position, forward, target_pos, present)

	if present and target_distance <= attack_range:
		_face_toward(target_pos)
	else:
		_move_toward(_pick_destination(delta), delta)

	if present and target_distance <= attack_range:
		_try_attack(target_pos)


func _target_valid() -> bool:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return false
	return true


func _pick_destination(delta: float) -> Vector3:
	if _agent.mode == AiAgentScript.Mode.CHASE and _target_valid():
		return target.global_position
	if _agent.mode == AiAgentScript.Mode.LEASH:
		return spawn_position
	_wander_timer -= delta
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 0.9:
		_wander_timer = _rng.randf_range(3.0, 6.0)
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(2.0, maxf(2.0, patrol_radius))
		_wander_target = spawn_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	return _wander_target


func _move_toward(destination: Vector3, delta: float) -> void:
	var speed := chase_speed if _agent.mode == AiAgentScript.Mode.CHASE else patrol_speed
	var step_target := destination
	if _nav != null:
		_nav.target_position = destination
		var map := _nav.get_navigation_map()
		if map.is_valid() and not _nav.is_navigation_finished():
			var next := _nav.get_next_path_position()
			# A freshly assigned target can resolve to the current position before
			# the map syncs; keep moving straight at the destination in that frame.
			if next.distance_to(global_position) > 0.05 or destination.distance_to(global_position) < 0.05:
				step_target = next

	var direction := step_target - global_position
	direction.y = 0.0
	if direction.length() > 0.08:
		direction = direction.normalized()
		global_position += direction * speed * delta
		_face_toward(global_position + direction)

	if terrain != null and terrain.has_method("sample_height"):
		global_position.y = float(terrain.call("sample_height", global_position.x, global_position.z)) + FEET_OFFSET


func _face_toward(point: Vector3) -> void:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.0001:
		return
	offset = offset.normalized()
	_facing = atan2(-offset.x, -offset.z)
	rotation.y = _facing


func _try_attack(target_pos: Vector3) -> void:
	if _attack_timer > 0.0 or _hitbox == null:
		return
	_attack_timer = maxf(0.2, attack_cooldown)
	var direction := (target_pos - global_position)
	direction.y = 0.0
	direction = direction.normalized()
	var hurtbox := _find_hurtbox(target)
	if hurtbox != null:
		_hitbox.strike(hurtbox, false, direction)
	else:
		attack_landed.emit(target, attack_damage)


func _find_hurtbox(node: Node) -> Hurtbox:
	if node == null:
		return null
	if node.has_method("get_hurtbox"):
		return node.call("get_hurtbox") as Hurtbox
	return node.get_node_or_null("Hurtbox") as Hurtbox


func _ensure_navigation() -> void:
	_nav = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _nav == null:
		_nav = NavigationAgent3D.new()
		_nav.name = "NavigationAgent3D"
		add_child(_nav)
	_nav.path_desired_distance = 0.6
	_nav.target_desired_distance = 0.9
	_nav.avoidance_enabled = false


func _ensure_combat() -> void:
	_health = get_node_or_null("Health") as HealthComponent
	if _health == null:
		_health = HealthComponent.new()
		_health.name = "Health"
		add_child(_health)
	_health.max_hp = max_hp
	if not _health.died.is_connected(_on_died):
		_health.died.connect(_on_died)

	_hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if _hurtbox == null:
		_hurtbox = Hurtbox.new()
		_hurtbox.name = "Hurtbox"
		add_child(_hurtbox)
	_hurtbox.faction = &"enemy"
	_hurtbox.health = _health

	_hitbox = get_node_or_null("Hitbox") as Hitbox
	if _hitbox == null:
		_hitbox = Hitbox.new()
		_hitbox.name = "Hitbox"
		add_child(_hitbox)
	_hitbox.faction = &"enemy"
	_hitbox.damage = attack_damage
	_hitbox.knockback_strength = 1.6


func _ensure_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "VisualRoot"
	add_child(_visual)

	var loaded := false
	if model_path != "" and ResourceLoader.exists(model_path):
		var packed := load(model_path) as PackedScene
		if packed != null:
			var model := packed.instantiate() as Node3D
			if model != null:
				model.scale = Vector3.ONE * model_scale
				_visual.add_child(model)
				loaded = true
	if not loaded:
		var mesh_instance := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.5
		mesh_instance.mesh = capsule
		mesh_instance.position.y = 0.75
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color
		mesh_instance.material_override = mat
		_visual.add_child(mesh_instance)

	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.text = display_name
	_label.position = Vector3(0.0, 1.9, 0.0)
	_label.font_size = 28
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 0.55, 0.5)
	add_child(_label)


func _on_died(_source: Node) -> void:
	if _dead:
		return
	_dead = true
	visible = false
	_hurtbox.health = null
	defeated.emit(self)
	await get_tree().create_timer(maxf(0.1, respawn_seconds)).timeout
	if not is_inside_tree():
		return
	_dead = false
	visible = true
	global_position = spawn_position
	_wander_target = spawn_position
	_wander_timer = 0.0
	_attack_timer = 0.0
	_agent.mode = AiAgentScript.Mode.PATROL
	_hurtbox.health = _health
	_health.revive(true)
	respawned.emit(self)
