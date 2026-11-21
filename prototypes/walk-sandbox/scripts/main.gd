extends Node3D
## World scene coordinator: wires terrain, sky/weather, player, camera rig, UI screens, quests, and saves.

@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig: CameraRig = $CameraPivot
@onready var _debug_overlay: DebugOverlay = $CanvasLayer
@onready var _markers_root: Node3D = $Markers
@onready var _sky_time: Node3D = $SkyTime
@onready var _terrain: Node3D = $TerrainMap
@onready var _nav_region: NavigationRegion3D = $NavRegion
@onready var _prompt_panel: PanelContainer = get_node_or_null("%InteractionPromptPanel") as PanelContainer
@onready var _prompt_label: Label = get_node_or_null("%InteractionPromptLabel") as Label

const TITLE_SCENE := preload("res://scenes/ui/title_screen.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const WorldLocatorScript = preload("res://scripts/map/world_locator.gd")
const ShaderWarmupScript = preload("res://addons/gu_core/flow/shader_warmup.gd")

var _landform_mode: int = -1 ## -1 = auto by seed, 0..3 = specific MapGenerator.Landform
var _pending_spawn_override: Dictionary = {}
var _pending_lit_beacon_ids: Array[String] = []
var _pending_resource_states: Dictionary = {}
var _beacons: Array[WorldBeacon] = []
var _resource_nodes: Array[ResourceNode] = []
var _enemies: Array[GuEnemy] = []
var _focused_interactable: Interactable = null
var _flags := FlagStore.new()
var _quests := QuestTracker.new()
var _dialogue_box: DialogueBox = null


func _ready() -> void:
	_register_ui_screens()
	_setup_quests()
	_setup_dialogue()
	var warmup := ShaderWarmupScript.new()
	var terrain_shader := load("res://shaders/terrain_ground.gdshader") as Shader
	if terrain_shader != null:
		warmup.add_shader(terrain_shader)
	add_child(warmup)
	# Wait one frame so TerrainMap._ready has built the initial landscape and shaders can compile.
	await get_tree().process_frame
	if _player.has_method("set_context"):
		_player.call("set_context", _terrain, _sky_time)
	if _player.has_method("get_interactor"):
		var interactor := _player.call("get_interactor") as Interactor
		if interactor != null and not interactor.focus_changed.is_connected(_on_interactor_focus_changed):
			interactor.focus_changed.connect(_on_interactor_focus_changed)
	if _player.has_signal("player_died"):
		_player.connect("player_died", _on_player_died)
	_setup_gameplay_hud()
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
	_register_content()
	_rebuild_world_entities()
	_refresh_interaction_prompt()
	_refresh_overlay()

	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("register_world", self)
		flow.call("enter_title")

	WorldCommands.register(
		get_node_or_null("/root/DevConsole"),
		func() -> void:
			_pending_spawn_override.clear()
			_place_player_on_terrain(),
		func() -> Array[WorldBeacon]: return _beacons,
		_refresh_overlay,
		_sky_time,
		_player
	)


func _exit_tree() -> void:
	_quests.unbind()
	var save_svc := get_node_or_null("/root/SaveService")
	if save_svc != null and save_svc.has_method("unregister_saveable"):
		save_svc.call("unregister_saveable", "flags")
		save_svc.call("unregister_saveable", "quests")


func _process(_delta: float) -> void:
	_clamp_player_to_map()
	if _sky_time != null and _sky_time.has_method("get_weather_params") and _terrain != null and _terrain.has_method("apply_weather"):
		_terrain.call("apply_weather", _sky_time.call("get_weather_params"))
	_refresh_interaction_prompt()
	_refresh_overlay()
	_refresh_enemy_targets()


func _refresh_enemy_targets() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	var playing := flow != null and int(flow.call("get_state")) == 3
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.set_target(_player if playing else null)


func start_new_world(opts: Dictionary = {}) -> void:
	_pending_spawn_override.clear()
	_pending_lit_beacon_ids.clear()
	_pending_resource_states.clear()
	_flags.clear()
	if _player.has_method("get_inventory"):
		var inv := _player.call("get_inventory") as InventoryContainer
		if inv != null:
			inv.clear()
	if _dialogue_box != null and _dialogue_box.is_open():
		_dialogue_box.close()
	_quests.apply_state({"active": {}, "completed": []})
	_quests.start_quest(&"activate_beacons")
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
			"lit_ids": WorldSpawner.export_beacons_lit_ids(_beacons),
		},
		"resources": WorldSpawner.export_resources_state(_resource_nodes),
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
	_pending_resource_states = (doc.get("resources", {}) as Dictionary).duplicate(true)

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


func _setup_quests() -> void:
	var quest_defs := GameContent.quests()
	for quest_def in quest_defs:
		_quests.register_quest(quest_def)
	_quests.bind(get_node_or_null("/root/EventBus"), _flags, _player_inventory())
	for quest_def in quest_defs:
		if quest_def.auto_start:
			_quests.start_quest(quest_def.id)
	_quests.quest_completed.connect(func(qid: StringName) -> void:
		GuLog.info("Quests", "Completed quest: %s" % String(qid))
		var ui := get_node_or_null("/root/UIRouter")
		var flow := get_node_or_null("/root/GameFlow")
		if flow != null and int(flow.call("get_state")) == 3 and ui != null and ui.has_method("show_toast"):
			var title := tr(str(_quests.get_quest_status(qid).get("title", String(qid))))
			if title == "":
				title = String(qid)
			ui.call("show_toast", "QUEST COMPLETE: %s" % title, 3.0, &"success")
		_refresh_overlay()
	)
	var save_svc := get_node_or_null("/root/SaveService")
	if save_svc != null and save_svc.has_method("register_saveable"):
		save_svc.call("register_saveable", "flags", _flags)
		save_svc.call("register_saveable", "quests", _quests)


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
			if _player.has_method("set_spawn_point"):
				_player.call("set_spawn_point", _player.global_position)
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
	if _player.has_method("set_spawn_point"):
		_player.call("set_spawn_point", spawn)


func _rebuild_world_entities() -> void:
	_focused_interactable = null
	_rebuild_navigation()
	_beacons = WorldSpawner.spawn_beacons(
		_markers_root,
		_terrain,
		_player.global_position,
		_pending_lit_beacon_ids,
		_on_beacon_lit_changed
	)
	_pending_lit_beacon_ids.clear()
	_resource_nodes = WorldSpawner.spawn_resource_nodes(
		_markers_root,
		_terrain,
		_player.global_position,
		_pending_resource_states,
		_resource_nodes,
		GameContent.resource_specs()
	)
	_pending_resource_states.clear()
	WorldSpawner.spawn_elder(_markers_root, _terrain, _player.global_position, GameContent.dialogue(&"elder_intro"))
	_enemies = WorldSpawner.spawn_enemies(_markers_root, _terrain, _player, _enemies)


func _rebuild_navigation() -> void:
	if _nav_region == null or _terrain == null:
		return
	var ground := _terrain.get_node_or_null("Mesh") as MeshInstance3D
	if ground == null or ground.mesh == null:
		return
	var started := Time.get_ticks_msec()
	var baked := NavMeshBaker.bake(_nav_region, ground)
	GuLog.info("Nav", "navmesh bake=%s elapsed=%dms polygons=%d" % [
		str(baked),
		Time.get_ticks_msec() - started,
		_nav_region.navigation_mesh.get_polygon_count() if _nav_region.navigation_mesh != null else 0,
	])


func _register_content() -> void:
	var inv := _player_inventory()
	if inv == null:
		return
	for item_def in GameContent.items():
		inv.register_item(item_def)


func _setup_dialogue() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DialogueLayer"
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_dialogue_box = DialogueBox.new()
	_dialogue_box.name = "DialogueBox"
	layer.add_child(_dialogue_box)
	_dialogue_box.bind(_flags, _quests, _player_inventory(), get_node_or_null("/root/EventBus"))


func _player_inventory() -> InventoryContainer:
	if _player != null and _player.has_method("get_inventory"):
		return _player.call("get_inventory") as InventoryContainer
	return null


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
	_prompt_label.text = "[E] %s" % tr(target.get_prompt_text())
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
		var msg := "Generated map seed=%d landform=%d h=[%.2f,%.2f]" % [data.seed_value, data.landform, data.h_min, data.h_max]
		print(msg)
		GuLog.info("Main", msg)
	_place_player_on_terrain()
	_rebuild_world_entities()


func _clamp_player_to_map() -> void:
	var map_size := 120.0
	if _terrain != null and _terrain.has_method("get_map_size"):
		map_size = float(_terrain.call("get_map_size"))
	var half := map_size * 0.5 - 1.0
	var p := _player.global_position
	p.x = clampf(p.x, -half, half)
	p.z = clampf(p.z, -half, half)
	_player.global_position = p


func _quest_line(quest_id: StringName, label: String) -> String:
	var status := _quests.get_quest_status(quest_id)
	var state := str(status.get("state", "inactive"))
	if state == "completed":
		return "%s: COMPLETE" % label
	if state == "active":
		var objectives: Array = status.get("objectives", []) as Array
		if not objectives.is_empty() and objectives[0] is Dictionary:
			var objective := objectives[0] as Dictionary
			return "%s: %d/%d" % [label, int(objective.get("current", 0)), int(objective.get("target", 1))]
		return "%s: ACTIVE" % label
	return "%s: READY" % label


func _setup_gameplay_hud() -> void:
	if _player == null or not _player.has_method("get_stats") or not _player.has_method("get_inventory"):
		return
	var stats := _player.call("get_stats") as StatSet
	var inv := _player.call("get_inventory") as InventoryContainer
	if stats == null or inv == null:
		return
	var hud := GameplayHud.new()
	hud.name = "GameplayHud"
	add_child(hud)
	hud.bind_player_hud(stats, &"hp", inv, _quests, tr("Health"))
	hud.add_stat_bar(stats, &"stamina", tr("Stamina"))


func _on_player_died() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	var ui := get_node_or_null("/root/UIRouter")
	if flow != null and int(flow.call("get_state")) == 3 and ui != null and ui.has_method("show_toast"):
		ui.call("show_toast", tr("You were defeated."), 2.4, &"warning")


func _refresh_overlay() -> void:
	if _debug_overlay == null:
		return
	var lit_spots: Array[String] = []
	for b in _beacons:
		if is_instance_valid(b) and b.is_lit:
			lit_spots.append("Spot %d" % b.beacon_index)
	_debug_overlay.set_reached_spots(lit_spots)
	if _debug_overlay.has_method("set_quest_summary"):
		_debug_overlay.set_quest_summary("%s  |  %s" % [
			_quest_line(&"activate_beacons", "LINK"),
			_quest_line(&"gather_wood", "TIMBER"),
		])
	_debug_overlay.refresh()
