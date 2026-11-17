extends Node3D
## World scene coordinator: wires terrain, sky/weather, player, camera rig, UI screens, beacons, and save snapshots.

@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig: CameraRig = $CameraPivot
@onready var _debug_overlay: DebugOverlay = $CanvasLayer
@onready var _markers_root: Node3D = $Markers
@onready var _sky_time: Node3D = $SkyTime
@onready var _terrain: Node3D = $TerrainMap
@onready var _prompt_panel: PanelContainer = get_node_or_null("%InteractionPromptPanel") as PanelContainer
@onready var _prompt_label: Label = get_node_or_null("%InteractionPromptLabel") as Label

const TITLE_SCENE := preload("res://scenes/ui/title_screen.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/settings_panel.tscn")
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

var _landform_mode: int = -1 ## -1 = auto by seed, 0..3 = specific MapGenerator.Landform
var _pending_spawn_override: Dictionary = {}
var _pending_lit_beacon_ids: Array[String] = []
var _beacons: Array[WorldBeacon] = []
var _focused_interactable: Interactable = null


func _ready() -> void:
	_register_ui_screens()
	# Wait one frame so TerrainMap._ready has built the initial landscape
	await get_tree().process_frame
	if _player.has_method("set_context"):
		_player.call("set_context", _terrain, _sky_time)
	if _player.has_method("get_interactor"):
		var interactor := _player.call("get_interactor") as Interactor
		if interactor != null and not interactor.focus_changed.is_connected(_on_interactor_focus_changed):
			interactor.focus_changed.connect(_on_interactor_focus_changed)
	if _sky_time != null and _sky_time.has_method("set_context"):
		_sky_time.call("set_context", _terrain, _player)
	if _camera_rig != null:
		_camera_rig.set_target(_player)
	if _debug_overlay != null:
		_debug_overlay.set_context(_terrain, _player, _sky_time, _camera_rig)
		_debug_overlay.set_landform_mode(_landform_mode)
		_debug_overlay.regen_requested.connect(_regen_terrain)
		_debug_overlay.landform_cycle_requested.connect(_cycle_landform)
	if _terrain != null and _terrain.has_signal("generation_finished"):
		_terrain.connect("generation_finished", Callable(self, "_on_terrain_generation_finished"))

	_place_player_on_terrain()
	_spawn_beacons()
	_refresh_interaction_prompt()
	_refresh_overlay()

	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("register_world", self)
		flow.call("enter_title")


func _process(_delta: float) -> void:
	_clamp_player_to_map()
	if _sky_time != null and _sky_time.has_method("get_weather_params") and _terrain != null and _terrain.has_method("apply_weather"):
		_terrain.call("apply_weather", _sky_time.call("get_weather_params"))
	_refresh_interaction_prompt()
	_refresh_overlay()


func start_new_world(opts: Dictionary = {}) -> void:
	_pending_spawn_override.clear()
	_pending_lit_beacon_ids.clear()
	if opts.has("landform"):
		_landform_mode = int(opts["landform"])
		if _debug_overlay != null:
			_debug_overlay.set_landform_mode(_landform_mode)
	var gen_opts := {"relief": float(opts.get("relief", 1.0))}
	if _landform_mode >= 0:
		gen_opts["landform"] = _landform_mode
	var p_seed := int(opts.get("seed", -1))
	if _terrain != null and _terrain.has_method("generate_random"):
		_terrain.call("generate_random", p_seed, gen_opts)


func export_save_state() -> Dictionary:
	var data: MapData = _terrain.call("get_map_data") as MapData if (_terrain != null and _terrain.has_method("get_map_data")) else null
	var sky_state: Dictionary = _sky_time.call("export_state") as Dictionary if (_sky_time != null and _sky_time.has_method("export_state")) else {}
	var p := _player.global_position
	var yaw := float(_player.call("get_facing_yaw")) if _player.has_method("get_facing_yaw") else 0.0
	var run_mode := bool(_player.call("get_run_mode")) if _player.has_method("get_run_mode") else false
	return {
		"world": {
			"seed": data.seed_value if data != null else 42,
			"landform": data.landform if data != null else 0,
			"landform_mode": _landform_mode,
			"relief": 1.0,
		},
		"sky": sky_state,
		"player": {
			"position": [p.x, p.y, p.z],
			"facing_yaw": yaw,
			"run_mode": run_mode,
		},
		"beacons": {
			"lit_ids": _get_lit_beacon_ids(),
		},
	}


func apply_save_state(doc: Dictionary) -> void:
	var world_cfg: Dictionary = doc.get("world", {}) as Dictionary
	var p_seed := int(world_cfg.get("seed", 42))
	_landform_mode = int(world_cfg.get("landform_mode", -1))
	if _debug_overlay != null:
		_debug_overlay.set_landform_mode(_landform_mode)
	var opts := {
		"relief": float(world_cfg.get("relief", 1.0)),
		"landform": int(world_cfg.get("landform", 0)),
	}
	_pending_spawn_override = doc.get("player", {}) as Dictionary
	_pending_lit_beacon_ids.clear()
	var beacons_cfg: Dictionary = doc.get("beacons", {}) as Dictionary
	for raw_id in beacons_cfg.get("lit_ids", []) as Array:
		_pending_lit_beacon_ids.append(str(raw_id))

	if _terrain != null and _terrain.has_method("generate_random"):
		_terrain.call("generate_random", p_seed, opts)
	if _sky_time != null and _sky_time.has_method("apply_state") and doc.get("sky") is Dictionary:
		_sky_time.call("apply_state", doc["sky"] as Dictionary)


func get_beacons() -> Array[WorldBeacon]:
	return _beacons.duplicate()


func _register_ui_screens() -> void:
	var ui := get_node_or_null("/root/UIRouter")
	if ui == null:
		return
	ui.call("register_screen", &"title", TITLE_SCENE)
	ui.call("register_screen", &"pause", PAUSE_SCENE)
	ui.call("register_screen", &"settings", SETTINGS_SCENE)


func _terrain_height(x: float, z: float) -> float:
	if _terrain != null and _terrain.has_method("sample_height"):
		return float(_terrain.call("sample_height", x, z))
	return 0.0


func _place_player_on_terrain() -> void:
	if not _pending_spawn_override.is_empty():
		var arr: Array = _pending_spawn_override.get("position", []) as Array
		if arr.size() == 3:
			_player.global_position = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
			_player.velocity = Vector3.ZERO
			if _player.has_method("set_facing_yaw"):
				_player.call("set_facing_yaw", float(_pending_spawn_override.get("facing_yaw", 0.0)))
			if _player.has_method("set_run_mode"):
				_player.call("set_run_mode", bool(_pending_spawn_override.get("run_mode", false)))
			_pending_spawn_override.clear()
			return

	var spawn := Vector3.ZERO
	if _terrain != null and _terrain.has_method("get_spawn_point"):
		spawn = _terrain.call("get_spawn_point") as Vector3
	else:
		var data: MapData = _terrain.call("get_map_data") as MapData if (_terrain != null and _terrain.has_method("get_map_data")) else null
		spawn = WorldLocatorScript.find_spawn_point(data)
	_player.global_position = spawn
	_player.velocity = Vector3.ZERO


func _spawn_beacons() -> void:
	_beacons.clear()
	_focused_interactable = null
	for c in _markers_root.get_children():
		_markers_root.remove_child(c)
		c.queue_free()

	var spots: Array[Dictionary] = []
	if _terrain != null and _terrain.has_method("get_poi_spots"):
		spots = _terrain.call("get_poi_spots") as Array[Dictionary]
	elif _terrain != null and _terrain.has_method("get_map_data"):
		var data: MapData = _terrain.call("get_map_data") as MapData
		spots = WorldLocatorScript.find_poi_spots(data, 6, 16.0, _player.global_position)

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
		beacon.set_lit(_pending_lit_beacon_ids.has(bid), false)
		beacon.lit_changed.connect(_on_beacon_lit_changed)
		_markers_root.add_child(beacon)
		_beacons.append(beacon)
	_pending_lit_beacon_ids.clear()


func _get_lit_beacon_ids() -> Array[String]:
	var ids: Array[String] = []
	for b in _beacons:
		if is_instance_valid(b) and b.is_lit:
			ids.append(b.interaction_id)
	return ids


func _on_beacon_lit_changed(beacon: WorldBeacon, lit: bool) -> void:
	_refresh_interaction_prompt()
	_refresh_overlay()
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method("emit_event"):
		bus.call("emit_event", &"beacon_lit_changed", {
			"id": beacon.interaction_id,
			"index": beacon.beacon_index,
			"lit": lit,
		})
	var flow := get_node_or_null("/root/GameFlow")
	var ui := get_node_or_null("/root/UIRouter")
	if flow != null and int(flow.call("get_state")) == 3 and ui != null and ui.has_method("show_toast"):
		var msg := "Beacon %d Activated" % beacon.beacon_index if lit else "Beacon %d Extinguished" % beacon.beacon_index
		var tone := &"success" if lit else &"info"
		ui.call("show_toast", msg, 2.2, tone)


func _on_interactor_focus_changed(target: Interactable) -> void:
	_focused_interactable = target
	_refresh_interaction_prompt()


func _refresh_interaction_prompt() -> void:
	if _prompt_panel == null or _prompt_label == null:
		return
	var router := get_node_or_null("/root/InputRouter")
	var gameplay_ok := router == null or bool(router.call("is_gameplay_active"))
	var target := _focused_interactable
	if target == null or not is_instance_valid(target) or not gameplay_ok:
		_prompt_panel.visible = false
		return
	_prompt_label.text = "[E] %s" % target.get_prompt_text()
	_prompt_panel.visible = true


func _cycle_landform() -> void:
	_landform_mode += 1
	if _landform_mode > 3:
		_landform_mode = -1
	if _debug_overlay != null:
		_debug_overlay.set_landform_mode(_landform_mode)
	_regen_terrain()


func _regen_terrain() -> void:
	if _terrain == null:
		return
	var opts := {"relief": 1.0}
	if _landform_mode >= 0:
		opts["landform"] = _landform_mode
	if _terrain.has_method("generate_random_async"):
		_terrain.call("generate_random_async", -1, opts)
	elif _terrain.has_method("generate_random"):
		_terrain.call("generate_random", -1, opts)


func _on_terrain_generation_finished(data: MapData) -> void:
	if data != null:
		print("Generated map seed=", data.seed_value, " landform=", data.landform, " h=[", data.h_min, ",", data.h_max, "]")
	_place_player_on_terrain()
	_spawn_beacons()


func _clamp_player_to_map() -> void:
	var map_size := 120.0
	if _terrain != null and _terrain.has_method("get_map_size"):
		map_size = float(_terrain.call("get_map_size"))
	var half := map_size * 0.5 - 1.0
	var p := _player.global_position
	p.x = clampf(p.x, -half, half)
	p.z = clampf(p.z, -half, half)
	_player.global_position = p


func _refresh_overlay() -> void:
	if _debug_overlay == null:
		return
	var lit_spots: Array[String] = []
	for b in _beacons:
		if is_instance_valid(b) and b.is_lit:
			lit_spots.append("Spot %d" % b.beacon_index)
	_debug_overlay.set_reached_spots(lit_spots)
	_debug_overlay.refresh()
