class_name WorldSpawner
extends RefCounted
## Spawns and serializes world beacons, harvestable resource nodes, and default quests.

const WorldLocatorScript = preload("res://scripts/map/world_locator.gd")
const WorldBeaconScript = preload("res://scripts/world/world_beacon.gd")

const BEACON_COLORS := [
	Color(0.24, 0.88, 1.0),
	Color(0.32, 0.92, 0.56),
	Color(0.96, 0.78, 0.28),
	Color(0.94, 0.44, 0.36),
	Color(0.84, 0.50, 0.98),
	Color(0.42, 0.72, 1.0),
]


static func spawn_beacons(
	markers_root: Node3D,
	terrain: Node,
	player_pos: Vector3,
	pending_lit_ids: Array[String],
	on_lit_changed: Callable
) -> Array[WorldBeacon]:
	var beacons: Array[WorldBeacon] = []
	if markers_root == null:
		return beacons

	for c in markers_root.get_children():
		if c is WorldBeacon:
			markers_root.remove_child(c)
			c.queue_free()

	var spots: Array[Dictionary] = []
	if terrain != null and terrain.has_method("get_poi_spots"):
		spots = terrain.call("get_poi_spots") as Array[Dictionary]
	elif terrain != null and terrain.has_method("get_map_data"):
		var data: MapData = terrain.call("get_map_data") as MapData
		spots = WorldLocatorScript.find_poi_spots(data, 6, 16.0, player_pos)

	for i in spots.size():
		var spot := spots[i]
		var pos := spot["position"] as Vector3
		var idx := int(spot.get("index", i + 1))
		var bid := str(spot.get("id", "beacon_%d" % idx))
		var bname := str(spot.get("biome_name", "?"))
		var col: Color = BEACON_COLORS[i % BEACON_COLORS.size()] as Color

		var beacon := WorldBeaconScript.new() as WorldBeacon
		beacon.configure(bid, idx, bname, col)
		beacon.position = pos
		beacon.set_lit(pending_lit_ids.has(bid), false)
		if on_lit_changed.is_valid():
			beacon.lit_changed.connect(on_lit_changed)
		markers_root.add_child(beacon)
		beacons.append(beacon)

	return beacons


static func spawn_resource_nodes(
	markers_root: Node3D,
	terrain: Node,
	center: Vector3,
	pending_states: Dictionary,
	prev_nodes: Array[ResourceNode],
	specs: Array[Dictionary] = []
) -> Array[ResourceNode]:
	for rn in prev_nodes:
		if is_instance_valid(rn):
			if rn.get_parent() != null:
				rn.get_parent().remove_child(rn)
			rn.queue_free()

	var spawned: Array[ResourceNode] = []
	if markers_root == null:
		return spawned
	if specs.is_empty():
		specs = GameContent.resource_specs()
	var data: MapData = terrain.call("get_map_data") as MapData if (terrain != null and terrain.has_method("get_map_data")) else null
	var map_half := (data.size * 0.5 - 4.0) if data != null else 52.0

	for sp in specs:
		var off := sp["offset"] as Vector2
		var wx := clampf(center.x + off.x, -map_half, map_half)
		var wz := clampf(center.z + off.y, -map_half, map_half)
		if data != null and data.sample_water_surface(wx, wz) > -1000.0:
			wx = center.x + off.x * 0.35
			wz = center.z + off.y * 0.35
		var wy := float(terrain.call("sample_height", wx, wz)) if (terrain != null and terrain.has_method("sample_height")) else 0.0

		var node := ResourceNode.new()
		var yields_list: Array[Dictionary] = []
		var raw_yields: Variant = sp.get("yields", [])
		if raw_yields is Array:
			for entry in raw_yields as Array:
				if entry is Dictionary:
					yields_list.append((entry as Dictionary).duplicate(true))
		node.configure(
			str(sp["id"]),
			sp["kind"] as StringName,
			sp["action"] as StringName,
			yields_list,
			float(sp.get("max_hp", 30.0)),
			float(sp.get("hit_damage", 10.0)),
			sp["color"] as Color
		)
		node.respawn_time = float(sp.get("respawn_time", 20.0))
		node.position = Vector3(wx, wy, wz)
		if pending_states.has(node.interaction_id):
			node.apply_state(pending_states[node.interaction_id] as Dictionary)
		markers_root.add_child(node)
		spawned.append(node)

	return spawned


static func export_beacons_lit_ids(beacons: Array[WorldBeacon]) -> Array[String]:
	var ids: Array[String] = []
	for b in beacons:
		if is_instance_valid(b) and b.is_lit:
			ids.append(b.interaction_id)
	return ids


static func export_resources_state(nodes: Array[ResourceNode]) -> Dictionary:
	var out: Dictionary = {}
	for rn in nodes:
		if is_instance_valid(rn) and rn.interaction_id != "":
			out[rn.interaction_id] = rn.export_state()
	return out


static func spawn_elder(
	markers_root: Node3D,
	terrain: Node,
	center: Vector3,
	dialogue: DialogueDef = null
) -> DialogueInteractable:
	if markers_root == null:
		return null
	for child in markers_root.get_children():
		if child is DialogueInteractable:
			markers_root.remove_child(child)
			child.queue_free()

	var elder := DialogueInteractable.new()
	elder.name = "Elder"
	elder.display_name = "Elder"
	elder.prompt_text = "Speak with Elder"
	elder.interaction_id = "elder"
	elder.interaction_priority = 5
	elder.interaction_radius = 2.4
	elder.dialogue = dialogue if dialogue != null else GameContent.dialogue(&"elder_intro")

	var offset := Vector2(2.4, 1.6)
	var data: MapData = terrain.call("get_map_data") as MapData if (terrain != null and terrain.has_method("get_map_data")) else null
	var map_half := (data.size * 0.5 - 4.0) if data != null else 52.0
	var wx := clampf(center.x + offset.x, -map_half, map_half)
	var wz := clampf(center.z + offset.y, -map_half, map_half)
	if data != null and data.sample_water_surface(wx, wz) > -1000.0:
		wx = center.x + offset.x * 0.35
		wz = center.z + offset.y * 0.35
	var wy := center.y
	if terrain != null and terrain.has_method("sample_height"):
		wy = float(terrain.call("sample_height", wx, wz))

	markers_root.add_child(elder)
	elder.position = Vector3(wx, wy, wz)
	return elder
