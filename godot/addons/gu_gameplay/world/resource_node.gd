class_name ResourceNode
extends Interactable
## Harvestable world entity combining HealthComponent, drop tables, WorldPickup spawning,
## optional PoolService recycling, hit feedback, and SaveService state serialization.

signal harvested(actor: Node, damage: float, remaining_hp: float)
signal depleted(actor: Node)
signal respawned

const HIT_SFX_PATH := "res://addons/gu_core/audio/sfx/protoss_hover.wav"
const DEPLETE_SFX_PATH := "res://addons/gu_core/audio/sfx/protoss_back.wav"

@export var resource_kind: StringName = &"ore"
@export var preferred_action: StringName = &"mine"
@export var max_hp: float = 30.0
@export var hit_damage: float = 10.0
@export var respawn_time: float = 0.0
@export var drop_table: Array[Dictionary] = []
@export var pickup_scene: PackedScene = null
@export var shake_intensity: float = 0.08
@export var accent_color: Color = Color(0.42, 0.80, 0.96)

var pool_service: Node = null
var event_bus: Object = null
var audio_manager: Node = null
var camera_rig: Node = null

var _health := HealthComponent.new()
var _depleted: bool = false
var _respawn_remaining: float = 0.0
var _hit_jiggle: float = 0.0
var _visuals_ready: bool = false
var _active_visual: Node3D = null
var _stump_visual: Node3D = null
var _label: Label3D = null
var _rng := RandomNumberGenerator.new()

static var _default_pickup_scene: PackedScene = null


func _init() -> void:
	_rng.randomize()
	_health.name = "HealthComponent"
	_health.max_hp = max_hp


func _ready() -> void:
	interaction_radius = 2.0
	super._ready()
	if _health.get_parent() != self:
		add_child(_health)
	_health.set_max_hp(max_hp, true)
	if not _health.died.is_connected(_on_health_died):
		_health.died.connect(_on_health_died)
	_ensure_visuals()
	_refresh_visuals()


func _process(delta: float) -> void:
	if _hit_jiggle > 0.0:
		_hit_jiggle = maxf(0.0, _hit_jiggle - delta * 6.0)
		if _active_visual != null:
			var s := 1.0 + sin(_hit_jiggle * PI) * 0.14
			_active_visual.scale = Vector3(s, 2.0 - s, s)
	elif _active_visual != null and _active_visual.scale != Vector3.ONE:
		_active_visual.scale = Vector3.ONE

	if _depleted and respawn_time > 0.0 and _respawn_remaining > 0.0:
		_respawn_remaining = maxf(0.0, _respawn_remaining - delta)
		if _respawn_remaining <= 0.0:
			respawn()


func configure(
	p_id: String,
	p_kind: StringName,
	p_action: StringName,
	p_drops: Array[Dictionary],
	p_max_hp: float = 30.0,
	p_hit_damage: float = 10.0,
	p_color: Color = Color(0.42, 0.80, 0.96)
) -> void:
	interaction_id = p_id
	resource_kind = p_kind
	preferred_action = p_action
	drop_table = p_drops.duplicate(true)
	max_hp = maxf(1.0, p_max_hp)
	hit_damage = maxf(1.0, p_hit_damage)
	accent_color = p_color
	_health.set_max_hp(max_hp, true)
	_depleted = false
	enabled = true
	_ensure_visuals()
	_refresh_visuals()


func get_health() -> HealthComponent:
	return _health


func is_depleted() -> bool:
	return _depleted


func apply_harvest_hit(actor: Node = null, damage: float = -1.0) -> float:
	if _depleted:
		return 0.0
	var dmg := damage if damage > 0.0 else hit_damage
	var dealt := _health.apply_damage(dmg, actor)
	if dealt <= 0.0:
		return 0.0

	_hit_jiggle = 1.0
	_play_sfx(HIT_SFX_PATH, -7.0, 0.95, 1.1)
	_trigger_camera_shake()
	_refresh_visuals()
	harvested.emit(actor, dealt, _health.get_hp())
	return dealt


func respawn() -> void:
	_depleted = false
	_respawn_remaining = 0.0
	enabled = true
	_health.revive(true)
	_refresh_visuals()
	respawned.emit()


func export_state() -> Dictionary:
	return {
		"depleted": _depleted,
		"hp": _health.get_hp(),
		"respawn_remaining": _respawn_remaining,
	}


func apply_state(doc: Dictionary) -> void:
	_depleted = bool(doc.get("depleted", false))
	_respawn_remaining = maxf(0.0, float(doc.get("respawn_remaining", 0.0)))
	if _depleted:
		_health.apply_state({"hp": 0.0, "max_hp": max_hp, "dead": true})
		enabled = false
	else:
		var hp_val := float(doc.get("hp", max_hp))
		_health.apply_state({"hp": hp_val, "max_hp": max_hp, "dead": false})
		enabled = true
	_ensure_visuals()
	_refresh_visuals()


func _can_interact(_actor: Node) -> bool:
	return not _depleted


func _on_interact(actor: Node) -> void:
	if actor != null and actor.has_method("perform_action"):
		actor.call("perform_action", preferred_action, {"target_pos": global_position})
	apply_harvest_hit(actor, hit_damage)


func _on_health_died(source: Node) -> void:
	_depleted = true
	enabled = false
	_respawn_remaining = respawn_time
	_play_sfx(DEPLETE_SFX_PATH, -4.0, 0.92, 1.02)
	_spawn_drops()
	_refresh_visuals()

	var bus: Object = event_bus
	if bus == null or not is_instance_valid(bus):
		bus = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method("emit_event"):
		bus.call("emit_event", &"resource_depleted", {
			"id": interaction_id,
			"kind": String(resource_kind),
		})
	depleted.emit(source)


func _spawn_drops() -> Array[WorldPickup]:
	var spawned: Array[WorldPickup] = []
	var parent_node := get_parent()
	if parent_node == null:
		return spawned

	var pool: Node = pool_service
	if pool == null or not is_instance_valid(pool):
		pool = get_node_or_null("/root/PoolService")

	var drop_idx := 0
	for entry in drop_table:
		var chance := clampf(float(entry.get("chance", 1.0)), 0.0, 1.0)
		if chance < 1.0 and _rng.randf() > chance:
			continue
		var lo := maxi(1, int(entry.get("min", entry.get("amount", 1))))
		var hi := maxi(lo, int(entry.get("max", lo)))
		var qty := _rng.randi_range(lo, hi)
		var drop_id := StringName(str(entry.get("item_id", resource_kind)))

		var pickup: WorldPickup = null
		var scene_to_use := pickup_scene
		if scene_to_use == null and pool != null:
			scene_to_use = _get_default_pickup_scene()
		if scene_to_use != null and pool != null and pool.has_method("acquire"):
			pickup = pool.call("acquire", scene_to_use, parent_node) as WorldPickup
		elif scene_to_use != null:
			pickup = scene_to_use.instantiate() as WorldPickup
			if pickup != null:
				parent_node.add_child(pickup)
		else:
			pickup = WorldPickup.new()
			parent_node.add_child(pickup)

		if pickup == null:
			continue
		var ang := float(drop_idx) * 2.1 + _rng.randf_range(-0.3, 0.3)
		var dist := _rng.randf_range(0.7, 1.3)
		pickup.global_position = global_position + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		pickup.configure(drop_id, qty, accent_color)
		spawned.append(pickup)
		drop_idx += 1

	return spawned


static func _get_default_pickup_scene() -> PackedScene:
	if _default_pickup_scene == null:
		var packed := PackedScene.new()
		var tpl := WorldPickup.new()
		packed.pack(tpl)
		tpl.free()
		_default_pickup_scene = packed
	return _default_pickup_scene


func _trigger_camera_shake() -> void:
	if shake_intensity <= 0.0:
		return
	var rig: Node = camera_rig
	if (rig == null or not is_instance_valid(rig)) and is_inside_tree():
		var tree := get_tree()
		if tree != null:
			var cams := tree.get_nodes_in_group(&"gu_camera_rigs")
			if not cams.is_empty():
				rig = cams[0]
	if rig != null and rig.has_method("add_shake"):
		rig.call("add_shake", shake_intensity, 0.14)


func _play_sfx(path: String, vol_db: float, pmin: float, pmax: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var am: Node = audio_manager
	if am == null or not is_instance_valid(am):
		am = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx_at"):
		am.call("play_sfx_at", global_position, stream, vol_db, pmin, pmax)


func _ensure_visuals() -> void:
	if _visuals_ready:
		return
	_visuals_ready = true

	_active_visual = Node3D.new()
	_active_visual.name = "ActiveMesh"
	add_child(_active_visual)

	var body := MeshInstance3D.new()
	if resource_kind == &"wood":
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.18
		trunk.bottom_radius = 0.26
		trunk.height = 1.4
		trunk.radial_segments = 7
		body.mesh = trunk
		body.position = Vector3(0.0, 0.7, 0.0)
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.42, 0.28, 0.16)
		body.material_override = tmat
		_active_visual.add_child(body)

		var crown := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.75
		cone.height = 1.4
		cone.radial_segments = 7
		crown.mesh = cone
		crown.position = Vector3(0.0, 1.65, 0.0)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = accent_color
		crown.material_override = cmat
		_active_visual.add_child(crown)
	else:
		var ore_mesh := SphereMesh.new()
		ore_mesh.radius = 0.52
		ore_mesh.height = 0.85
		ore_mesh.radial_segments = 6
		ore_mesh.rings = 2
		body.mesh = ore_mesh
		body.position = Vector3(0.0, 0.42, 0.0)
		var omat := StandardMaterial3D.new()
		omat.albedo_color = accent_color
		omat.roughness = 0.5
		omat.metallic = 0.25
		omat.emission_enabled = true
		omat.emission = accent_color * 0.28
		body.material_override = omat
		_active_visual.add_child(body)

	_stump_visual = Node3D.new()
	_stump_visual.name = "DepletedVisual"
	var stump := MeshInstance3D.new()
	var smesh := CylinderMesh.new()
	smesh.top_radius = 0.28
	smesh.bottom_radius = 0.36
	smesh.height = 0.22
	smesh.radial_segments = 7
	stump.mesh = smesh
	stump.position = Vector3(0.0, 0.11, 0.0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.28, 0.28, 0.30)
	stump.material_override = smat
	_stump_visual.add_child(stump)
	add_child(_stump_visual)

	_label = Label3D.new()
	_label.name = "ResourceLabel"
	_label.position = Vector3(0.0, 1.55, 0.0)
	_label.font_size = 34
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _refresh_visuals() -> void:
	var action_title := String(preferred_action).capitalize()
	var kind_title := String(resource_kind).capitalize()
	prompt_text = "%s %s" % [action_title, kind_title]
	if _active_visual != null:
		_active_visual.visible = not _depleted
	if _stump_visual != null:
		_stump_visual.visible = _depleted
	if _label != null:
		if _depleted:
			_label.text = "%s [DEPLETED]" % kind_title
			_label.modulate = Color(0.65, 0.68, 0.72)
		else:
			_label.text = "%s (%.0f/%.0f)" % [kind_title, _health.get_hp(), _health.get_max_hp()]
			_label.modulate = accent_color.lightened(0.35)
