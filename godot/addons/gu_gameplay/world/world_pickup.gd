class_name WorldPickup
extends Area3D
## Collectible 3D item drop with magnet attraction, InventoryContainer integration,
## AudioManager/EventBus feedback, and PoolService lifecycle hooks.

signal picked_up(collector: Node, item_id: StringName, amount: int)

const COLLECTOR_GROUP := &"gu_collectors"
const PICKUP_SFX_PATH := "res://addons/gu_core/audio/sfx/protoss_click.wav"

@export var item_id: StringName = &"ore"
@export var amount: int = 1
@export var pickup_radius: float = 1.4
@export var magnet_radius: float = 3.2
@export var magnet_speed: float = 7.5
@export var collector_group: StringName = COLLECTOR_GROUP
@export var accent_color: Color = Color(0.95, 0.81, 0.35)

var event_bus: Object = null
var pool_service: Node = null
var audio_manager: Node = null

var _collected: bool = false
var _bob_t: float = 0.0
var _visuals_ready: bool = false
var _mesh: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _label: Label3D = null


func _ready() -> void:
	monitoring = false
	monitorable = false
	_ensure_visuals()
	_refresh_visuals()


func _physics_process(delta: float) -> void:
	if not _collected:
		step_pickup(delta)


func configure(
	p_item_id: StringName,
	p_amount: int = 1,
	p_color: Color = Color(0.95, 0.81, 0.35)
) -> void:
	item_id = p_item_id
	amount = maxi(1, p_amount)
	accent_color = p_color
	_collected = false
	_ensure_visuals()
	_refresh_visuals()


func on_pool_acquire() -> void:
	_collected = false
	_bob_t = 0.0
	visible = true
	_ensure_visuals()
	_refresh_visuals()


func on_pool_release() -> void:
	_collected = true


func is_collected() -> bool:
	return _collected


func step_pickup(delta: float) -> bool:
	if _collected:
		return false
	_bob_t += delta
	if _mesh != null:
		_mesh.position.y = 0.34 + sin(_bob_t * 3.4) * 0.07
		_mesh.rotation.y += delta * 2.1

	var collector := _find_nearest_collector()
	if collector == null:
		return false

	var target_pos := collector.global_position
	var delta_vec := Vector3(target_pos.x - global_position.x, 0.0, target_pos.z - global_position.z)
	var dist := delta_vec.length()

	if dist <= pickup_radius:
		return try_collect(collector)

	if dist <= magnet_radius and dist > 0.001:
		var step_dist := minf(dist, magnet_speed * delta)
		global_position += delta_vec.normalized() * step_dist
		if global_position.distance_to(Vector3(target_pos.x, global_position.y, target_pos.z)) <= pickup_radius:
			return try_collect(collector)

	return false


func try_collect(collector: Node) -> bool:
	if _collected or amount <= 0 or collector == null or not is_instance_valid(collector):
		return false
	var inv := _resolve_inventory(collector)
	if inv == null:
		return false

	var leftover: int = inv.add_item(item_id, amount)
	var added: int = amount - leftover
	if added <= 0:
		return false

	picked_up.emit(collector, item_id, added)
	_emit_pickup_event(added)
	_play_pickup_sfx()

	if leftover > 0:
		amount = leftover
		_refresh_visuals()
		return false

	_collected = true
	_recycle_or_free()
	return true


func _find_nearest_collector() -> Node3D:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_d2 := magnet_radius * magnet_radius
	for node in tree.get_nodes_in_group(collector_group):
		if node is Node3D and is_instance_valid(node):
			var n3 := node as Node3D
			var dx := n3.global_position.x - global_position.x
			var dz := n3.global_position.z - global_position.z
			var d2 := dx * dx + dz * dz
			if d2 <= best_d2:
				best_d2 = d2
				best = n3
	return best


func _resolve_inventory(collector: Node) -> InventoryContainer:
	if collector.has_method("get_inventory"):
		return collector.call("get_inventory") as InventoryContainer
	var prop: Variant = collector.get("inventory")
	if prop is InventoryContainer:
		return prop as InventoryContainer
	return null


func _emit_pickup_event(added: int) -> void:
	var bus: Object = event_bus
	if bus == null or not is_instance_valid(bus):
		bus = get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method("emit_event"):
		bus.call("emit_event", &"item_picked_up", {
			"item_id": String(item_id),
			"amount": added,
		})


func _play_pickup_sfx() -> void:
	if not ResourceLoader.exists(PICKUP_SFX_PATH):
		return
	var stream := load(PICKUP_SFX_PATH) as AudioStream
	if stream == null:
		return
	var am: Node = audio_manager
	if am == null or not is_instance_valid(am):
		am = get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx_at"):
		am.call("play_sfx_at", global_position, stream, -6.0, 1.05, 1.18)


func _recycle_or_free() -> void:
	var pool: Node = pool_service
	if pool == null or not is_instance_valid(pool):
		pool = get_node_or_null("/root/PoolService")
	if pool != null and pool.has_method("release"):
		pool.call("release", self)
	else:
		queue_free()


func _ensure_visuals() -> void:
	if _visuals_ready:
		return
	_visuals_ready = true

	_mesh = MeshInstance3D.new()
	_mesh.name = "PickupCore"
	var sphere := SphereMesh.new()
	sphere.radius = 0.19
	sphere.height = 0.36
	sphere.radial_segments = 6
	sphere.rings = 2
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.34, 0.0)
	_mat = StandardMaterial3D.new()
	_mat.roughness = 0.3
	_mat.metallic = 0.2
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 1.4
	_mesh.material_override = _mat
	add_child(_mesh)

	_label = Label3D.new()
	_label.name = "PickupLabel"
	_label.position = Vector3(0.0, 0.82, 0.0)
	_label.font_size = 32
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)


func _refresh_visuals() -> void:
	if _mat != null:
		_mat.albedo_color = accent_color
		_mat.emission = accent_color * 0.65
	if _label != null:
		_label.text = "%s x%d" % [String(item_id).capitalize(), amount]
		_label.modulate = accent_color.lightened(0.35)
