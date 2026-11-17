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
	prev_nodes: Array[ResourceNode]
) -> Array[ResourceNode]:
	for rn in prev_nodes:
		if is_instance_valid(rn):
			if rn.get_parent() != null:
				rn.get_parent().remove_child(rn)
			rn.queue_free()

	var spawned: Array[ResourceNode] = []
	if markers_root == null:
		return spawned

	var specs := [
		{"id": "res_ore_1", "kind": &"ore", "action": &"mine", "offset": Vector2(4.2, 2.4), "color": Color(0.35, 0.78, 0.98)},
		{"id": "res_ore_2", "kind": &"ore", "action": &"mine", "offset": Vector2(-4.5, 2.8), "color": Color(0.95, 0.74, 0.30)},
		{"id": "res_wood_1", "kind": &"wood", "action": &"chop", "offset": Vector2(3.6, -4.4), "color": Color(0.28, 0.72, 0.34)},
		{"id": "res_wood_2", "kind": &"wood", "action": &"chop", "offset": Vector2(-3.8, -4.2), "color": Color(0.34, 0.78, 0.42)},
	]
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
		var rkind := sp["kind"] as StringName
		node.configure(
			str(sp["id"]),
			rkind,
			sp["action"] as StringName,
			[{"item_id": String(rkind), "min": 1, "max": 2, "chance": 1.0}],
			30.0,
			10.0,
			sp["color"] as Color
		)
		node.respawn_time = 20.0
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


static func create_gather_wood_quest() -> QuestDef:
	return QuestDef.from_dict({
		"id": "gather_wood",
		"title": "Timber for the Ward",
		"description": "Bring 3 wood to the elder.",
		"objectives": [
			{
				"id": "deliver",
				"description": "Deliver 3 wood",
				"type": "event",
				"event": "wood_delivered",
				"target": 1,
			},
		],
		"rewards": [
			{"type": "item", "id": "coin", "amount": 8},
			{"type": "flag", "id": "elder_paid", "value": true},
		],
	})


static func create_elder_dialogue() -> DialogueDef:
	return DialogueDef.from_dict({
		"id": "elder_intro",
		"start": "greet",
		"nodes": [
			{
				"id": "greet",
				"speaker": "Elder",
				"text": "The beacon ward needs timber.",
				"branches": [
					{
						"conditions": [
							{"type": "quest", "id": "gather_wood", "state": "completed"},
						],
						"next": "done",
					},
				],
				"choices": [
					{
						"text": "I will bring three wood.",
						"next": "accepted",
						"conditions": [
							{"type": "quest", "id": "gather_wood", "state": "inactive"},
						],
						"effects": [
							{"type": "start_quest", "id": "gather_wood"},
							{"type": "set_flag", "id": "met_elder", "value": true},
						],
					},
					{
						"text": "Here is the wood.",
						"next": "paid",
						"conditions": [
							{"type": "quest", "id": "gather_wood", "state": "active"},
							{"type": "item", "id": "wood", "amount": 3},
						],
						"effects": [
							{"type": "remove_item", "id": "wood", "amount": 3},
							{"type": "emit_event", "event": "wood_delivered"},
						],
					},
					{
						"text": "I will return later.",
						"next": "later",
						"conditions": [
							{"type": "quest", "id": "gather_wood", "state": "not_completed"},
						],
					},
				],
			},
			{
				"id": "accepted",
				"speaker": "Elder",
				"text": "Three timber beams will do. Fell the trees nearby.",
			},
			{
				"id": "paid",
				"speaker": "Elder",
				"text": "The ward is steadier. Take this for your trouble.",
			},
			{
				"id": "done",
				"speaker": "Elder",
				"text": "You already helped the ward.",
			},
			{
				"id": "later",
				"speaker": "Elder",
				"text": "I will keep the watch.",
			},
		],
	})


static func spawn_elder(markers_root: Node3D, terrain: Node, center: Vector3) -> DialogueInteractable:
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
	elder.dialogue = create_elder_dialogue()

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


static func create_beacon_quest() -> QuestDef:
	return QuestDef.from_dict({
		"id": "activate_beacons",
		"title": "Activate Sector Beacons",
		"description": "Light 3 world beacons to stabilize the sector.",
		"objectives": [
			{
				"id": "light_3",
				"description": "Light 3 beacons",
				"type": "event",
				"event": "beacon_lit_changed",
				"filter": {"lit": true},
				"target": 3,
			},
		],
		"rewards": [
			{"type": "flag", "id": "sector_linked", "value": true},
		],
	})
