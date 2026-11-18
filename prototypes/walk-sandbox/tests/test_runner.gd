extends SceneTree
## Headless unit test runner for Phase 1 + Phase 2 skeleton modules:
##   - MapGenerator + MapData validation & spatial queries
##   - TerrainBuildContext + SeaMesh / LakeMesh / RiverMesh decoupling
##   - CharacterLocomotion dry / shallow / swim / river transitions
##   - addons/gu_core: InputRouter, SettingsStore, AudioManager, SaveService, UIRouter, GameFlow
##
## Run with:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path prototypes/walk-sandbox --script res://tests/test_runner.gd

const MapGen = preload("res://scripts/map_generator.gd")
const MapTypes = preload("res://scripts/map/map_types.gd")
const WorldLocatorScript = preload("res://scripts/map/world_locator.gd")
const SeaMesh = preload("res://scripts/terrain/sea_mesh.gd")
const LakeMesh = preload("res://scripts/terrain/lake_mesh.gd")
const RiverMesh = preload("res://scripts/terrain/river_mesh.gd")
const MapRivers = preload("res://scripts/map/map_rivers.gd")
const LandPropsMesh = preload("res://scripts/terrain/land_props_mesh.gd")
const WorldBeaconScript = preload("res://scripts/world/world_beacon.gd")
const SkyTimeScript = preload("res://scripts/sky_time.gd")

const InputRouterScript = preload("res://addons/gu_core/input/input_router.gd")
const SettingsStoreScript = preload("res://addons/gu_core/settings/settings_store.gd")
const TranslationCatalogScript = preload("res://addons/gu_core/i18n/translation_catalog.gd")
const FontFallbackScript = preload("res://addons/gu_core/i18n/font_fallback.gd")
const ShaderWarmupScript = preload("res://addons/gu_core/flow/shader_warmup.gd")
const TooltipFrameScript = preload("res://addons/gu_core/ui/tooltip_frame.gd")
const GameplayTagsScript = preload("res://addons/gu_gameplay/status/gameplay_tags.gd")
const StatusControllerScript = preload("res://addons/gu_gameplay/status/status_controller.gd")
const CooldownTrackerScript = preload("res://addons/gu_gameplay/status/cooldown_tracker.gd")
const HurtboxScript = preload("res://addons/gu_gameplay/combat/hurtbox.gd")
const HitboxScript = preload("res://addons/gu_gameplay/combat/hitbox.gd")
const JuiceBusScript = preload("res://addons/gu_gameplay/combat/juice_bus.gd")
const CoachMarksScript = preload("res://addons/gu_gameplay/ui/coach_marks.gd")
const AiAgentScript = preload("res://addons/gu_gameplay/ai/agent.gd")
const AiPerceptionScript = preload("res://addons/gu_gameplay/ai/perception.gd")
const AudioManagerScript = preload("res://addons/gu_core/audio/audio_manager.gd")
const SaveServiceScript = preload("res://addons/gu_core/save/save_service.gd")
const UIRouterScript = preload("res://addons/gu_core/ui/ui_router.gd")
const GameFlowScript = preload("res://addons/gu_core/flow/game_flow.gd")
const EventBusScript = preload("res://addons/gu_core/events/event_bus.gd")
const PoolServiceScript = preload("res://addons/gu_core/pool/pool_service.gd")
const DevConsoleScript = preload("res://addons/gu_core/debug/dev_console.gd")

const InteractableScript = preload("res://addons/gu_gameplay/interaction/interactable.gd")
const InteractorScript = preload("res://addons/gu_gameplay/interaction/interactor.gd")
const SurfaceResolverScript = preload("res://addons/gu_gameplay/audio/surface_resolver.gd")
const SurfaceAudioBankScript = preload("res://addons/gu_gameplay/audio/surface_audio_bank.gd")

var _failures: Array[String] = []
var _passed: int = 0


class MockTerrain extends RefCounted:
	var ground_y: float = 1.0
	var water_y: float = -INF
	var biome: int = MapTypes.Biome.GRASS
	var height_fn: Callable = Callable()

	func sample_height(x: float, z: float) -> float:
		if height_fn.is_valid():
			return float(height_fn.call(x, z))
		return ground_y

	func sample_water_surface(_x: float, _z: float) -> float:
		return water_y

	func sample_biome(_x: float, _z: float) -> int:
		return biome


class MockWorld extends Node:
	var started_count: int = 0
	var last_opts: Dictionary = {}
	var applied_doc: Dictionary = {}

	func start_new_world(opts: Dictionary = {}) -> void:
		started_count += 1
		last_opts = opts.duplicate(true)

	func export_save_state() -> Dictionary:
		return {
			"world": {"seed": 777, "landform": 1, "relief": 1.0},
			"sky": {"hour": 12.5, "weather": 2, "speed_index": 1},
			"player": {"position": [3.0, 4.0, -5.0], "facing_yaw": 1.2, "run_mode": true},
		}

	func apply_save_state(doc: Dictionary) -> void:
		applied_doc = doc.duplicate(true)


var _ran: bool = false
var _quit_through_flow: bool = false
var _clock_timer_fired: bool = false


func _on_game_clock_timer() -> void:
	_clock_timer_fired = true


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_all()
	if _failures.is_empty():
		print("[PASS] All %d Phase 1 + Phase 2 + Phase 3 assertions passed." % _passed)
		if _quit_through_flow:
			var flow := get_root().get_node_or_null("GameFlow")
			if flow != null and flow.has_method("quit_game"):
				flow.call("quit_game")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + f)
		print("[FAIL] %d assertion(s) failed (%d passed)." % [_failures.size(), _passed])
		quit(1)
	return true


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(msg)


func _run_all() -> void:
	_test_map_data_and_generator()
	_test_terrain_build_context_and_meshes()
	_test_river_channel_and_confluence()
	_test_character_locomotion()
	_test_character_climbing()
	_test_input_router()
	_test_settings_store()
	_test_settings_locale()
	_test_audio_manager()
	_test_save_service()
	_test_game_flow_and_ui_router()
	_test_protoss_ui_skin()
	_test_world_locator()
	_test_interaction_system()
	_test_surface_resolver_and_audio_bank()
	_test_beacon_save_roundtrip()
	_test_character_action_architecture()
	_test_work_ik_and_tool_visual()
	_test_event_bus()
	_test_camera_rig_shake()
	_test_stat_set_and_inventory()
	_test_data_table_loader()
	_test_save_migrations_and_backup()
	_test_pool_service_and_scene_loader()
	_test_input_rebinding_and_dev_console()
	_test_flags_and_quest_tracker()
	_test_dialogue()
	_test_save_slots_panel_and_keybind_list()
	_test_world_entity_primitives()
	_test_gameplay_hud()
	_test_loading_and_shader_warmup()
	_test_status_cooldown_and_tags()
	_test_hitbox_and_juice()
	_test_game_clock()
	_test_input_glyphs_focus_tooltip_coach()
	_test_bug_report_and_platform()
	_test_ai_perception()
	_test_summit_star_clarity()
	_test_play_smoke()


func _test_map_data_and_generator() -> void:
	var d1: MapData = MapGen.generate(42, {"relief": 1.0})
	var d2: MapData = MapGen.generate(42, {"relief": 1.0})
	_assert(d1 != null, "MapGenerator.generate returns non-null MapData")
	_assert(d1.is_valid(), "Generated MapData passes is_valid()")
	_assert(d1.seed_value == 42, "MapData keeps seed_value")
	_assert(d1.heights.size() == d1.grid * d1.grid, "Heights array matches grid*grid")
	_assert(d1.h_min <= d1.h_max, "h_min <= h_max")

	var all_finite := true
	for h in d1.heights:
		if is_nan(h) or is_inf(h):
			all_finite = false
			break
	_assert(all_finite, "All terrain heights are finite")
	_assert(is_equal_approx(d1.sample_height(0.0, 0.0), d2.sample_height(0.0, 0.0)), "Generation is deterministic per seed")

	var h_edge := d1.sample_height(9999.0, -9999.0)
	_assert(not is_nan(h_edge) and not is_inf(h_edge), "Out-of-bounds height query clamps safely")
	var b_edge := d1.sample_biome(9999.0, -9999.0)
	_assert(b_edge >= 0, "Out-of-bounds biome query clamps safely")


func _test_terrain_build_context_and_meshes() -> void:
	var data: MapData = MapGen.generate(108, {"relief": 1.0})
	var ctx := TerrainBuildContext.new(data)

	var rb := RiverMesh.new()
	var r_res: Dictionary = rb.build(ctx)
	ctx.mouths = r_res.get("mouths", []) as Array[Dictionary]
	data.refresh_height_range()

	var img := Image.create(data.grid, data.grid, false, Image.FORMAT_RF)
	ctx.height_tex = ImageTexture.create_from_image(img)

	var s_res: Dictionary = SeaMesh.new().build(ctx)
	_assert(s_res.get("mesh") is Mesh, "SeaMesh builds a Mesh via TerrainBuildContext")
	_assert(s_res.get("material") is ShaderMaterial, "SeaMesh builds a ShaderMaterial")

	var l_res: Dictionary = LakeMesh.new().build(ctx)
	if not data.lakes.is_empty():
		_assert(l_res.get("mesh") is Mesh, "LakeMesh builds a Mesh when lakes exist")

	var packed: Dictionary = ctx.pack_mouth_uniforms("sea")
	_assert(int(packed.get("count", -1)) <= 8, "pack_mouth_uniforms caps count at MAX_MOUTHS (8)")
	_assert((packed.get("pos_dir", []) as Array).size() == 8, "pack_mouth_uniforms pads pos_dir to 8")

	var spawn := WorldLocatorScript.find_spawn_point(data)
	var pois := WorldLocatorScript.find_poi_spots(data, 6, 16.0, spawn)
	ctx.clear_spots.append(Vector2(spawn.x, spawn.z))
	for spot: Dictionary in pois:
		var sp := spot["position"] as Vector3
		ctx.clear_spots.append(Vector2(sp.x, sp.z))
	var props_root := Node3D.new()
	var lpm := LandPropsMesh.new()
	lpm.build(ctx, props_root)
	_assert(props_root.get_child_count() > 0, "LandPropsMesh builds foliage/prop batches from TerrainBuildContext")
	var trees_in_river := 0
	for tree_name in ["PineTrees", "BroadleafTrees"]:
		var batch := props_root.get_node_or_null(tree_name) as MultiMeshInstance3D
		if batch == null or batch.multimesh == null:
			continue
		for ti in batch.multimesh.instance_count:
			var origin := batch.multimesh.get_instance_transform(ti).origin
			if lpm._too_close_to_river(origin.x, origin.z):
				trees_in_river += 1
	_assert(trees_in_river == 0, "Trees stay off the river bank")
	_assert(lpm._near_clear_spot(spawn.x, spawn.z, 2.8), "LandPropsMesh respects dynamic clear_spots for spawn")
	if not pois.is_empty():
		var p0 := pois[0]["position"] as Vector3
		_assert(lpm._near_clear_spot(p0.x, p0.z, 2.8), "LandPropsMesh respects dynamic clear_spots for POIs")
	props_root.free()


func _test_river_channel_and_confluence() -> void:
	var found_trib := false
	for seed in [108, 42, 7, 19, 64, 3]:
		var data: MapData = MapGen.generate(seed, {"relief": 1.0})
		if data.rivers.size() < 2:
			continue
		var main: PackedVector2Array = data.rivers[0]
		var gap := INF
		for ri in range(1, data.rivers.size()):
			var trib: PackedVector2Array = data.rivers[ri]
			if trib.is_empty():
				continue
			var tip: Vector2 = trib[trib.size() - 1]
			var d := MapRivers._dist_to_polyline(tip, main)
			if d < gap:
				gap = d
		if gap > 6.0:
			continue
		_assert(
			gap > 0.2 and gap < 3.4,
			"Tributary meets the main bank without crossing it (seed %d)" % seed
		)
		var ctx := TerrainBuildContext.new(data)
		var mesh := RiverMesh.new().build(ctx).get("mesh") as ArrayMesh
		_assert(mesh != null, "River mesh builds for a joined watershed")
		if mesh == null:
			return
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var floating := 0
		var buried := 0
		var checked := 0
		for i in range(0, verts.size() - 1, 2):
			var col := colors[i]
			if col.g > 0.45 or col.b > 0.45:
				continue
			var mid := (verts[i] + verts[i + 1]) * 0.5
			var bed := ctx.sample_height(mid.x, mid.z)
			checked += 1
			if mid.y - bed > 1.35:
				floating += 1
			elif bed > mid.y + 0.55:
				buried += 1
		_assert(checked > 8, "Inland river stations are checked")
		_assert(floating == 0 and buried == 0, "River sheet stays in the carved channel (seed %d)" % seed)
		found_trib = true
		break
	_assert(found_trib, "A generated map includes a tributary confluence")


func _test_character_locomotion() -> void:
	var loco := CharacterLocomotion.new()
	var terrain := MockTerrain.new()

	terrain.ground_y = 2.5
	terrain.water_y = -INF
	terrain.biome = MapTypes.Biome.GRASS
	var pos := Vector3(0.0, 2.5, 0.0)
	var vel := Vector3.ZERO
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "WALK", "Dry walk reports WALK state")
	_assert(is_equal_approx(pos.y, 2.5 + CharacterLocomotion.FEET_OFFSET), "Dry walk snaps feet to ground_y + FEET_OFFSET")
	_assert(loco.swim_amt < 0.01, "Dry walk has near-zero swim_amt")

	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), true, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "RUN", "Sprint on dry land reports RUN state")
	_assert(loco.speed_xz > CharacterLocomotion.WALK_SPEED, "Sprint exceeds WALK_SPEED")

	terrain.ground_y = -1.5
	terrain.water_y = 0.95
	terrain.biome = MapTypes.Biome.SEA
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(0.0, 1.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "SWIM", "Deep sea triggers SWIM state")
	_assert(loco.swim_amt > 0.9, "Deep sea sets swim_amt near 1.0")
	_assert(pos.y > terrain.ground_y + 0.5, "Swimmer floats above deep seabed")

	loco.reset()
	terrain.ground_y = 1.0
	terrain.water_y = 3.0
	terrain.biome = MapTypes.Biome.RIVER
	var river_res := loco.step(Vector3(0.0, 1.0, 0.0), Vector3.ZERO, Vector2(1.0, 0.0), false, terrain, 0.05)
	var river_pos := river_res["position"] as Vector3
	_assert(loco.swim_amt == 0.0, "River biome does not trigger swim blend")
	_assert(is_equal_approx(river_pos.y, 1.0 + CharacterLocomotion.FEET_OFFSET), "River keeps character grounded on riverbed")


func _test_character_climbing() -> void:
	var loco := CharacterLocomotion.new()
	var terrain := MockTerrain.new()

	# 1) Gentle slope (grade = 0.25) should stay in WALK, not CLIMB
	terrain.height_fn = func(x: float, _z: float) -> float:
		return 1.0 + maxf(0.0, x) * 0.25
	var pos := Vector3(0.0, 1.0, 0.0)
	var vel := Vector3.ZERO
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "WALK", "Gentle 0.25 slope stays in WALK state")
	_assert(loco.climb_amt < 0.05, "Gentle slope does not activate climb_amt")

	# 1b) A walkable hillside (grade 0.65, ~33 deg) stays on foot.
	loco.reset()
	terrain.height_fn = func(x: float, _z: float) -> float:
		return 1.0 + maxf(0.0, x) * 0.65
	pos = Vector3(0.0, 1.0, 0.0)
	vel = Vector3.ZERO
	for _i in 24:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "WALK", "Hillside grade 0.65 is walked, not climbed")
	_assert(loco.climb_amt < 0.05, "Hillside does not activate climb_amt")

	# 2) Steep cliff (flat -> 1.0 grade cliff from x=1.5..6.5 -> flat plateau at x>=6.5)
	loco.reset()
	terrain.height_fn = func(x: float, _z: float) -> float:
		if x < 1.5:
			return 1.0
		if x > 6.5:
			return 6.0
		return 1.0 + (x - 1.5) * 1.0
	pos = Vector3(0.5, 1.0, 0.0)
	vel = Vector3.ZERO
	var entered_climb := false
	for _i in 40:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
		if loco.state_label == "CLIMB":
			entered_climb = true
	_assert(entered_climb, "Steep 1.0-grade cliff triggers CLIMB state")
	_assert(loco.climb_amt > 0.8, "Climb blend reaches >0.8 on steep cliff")
	_assert(loco.facing_yaw > 1.2 and loco.facing_yaw < 1.9, "Climber faces uphill (+X) into the cliff")
	_assert(loco.speed_3d < CharacterLocomotion.WALK_SPEED * 0.92, "Steep scramble is slower than a flat walk")
	_assert(loco.speed_3d > 1.1, "Steep scramble still makes progress")

	# 3) Stopping mid-cliff keeps CLIMB state (clinging instead of flickering to WALK)
	for _i in 15:
		var res := loco.step(pos, vel, Vector2.ZERO, false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "CLIMB", "Stopping mid-cliff preserves CLIMB clinging state")
	_assert(loco.climb_move < 0.1, "Clinging idle drops climb_move toward 0")

	# 4) Continuing uphill onto flat plateau exits CLIMB back to WALK
	for _i in 100:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
		if pos.x > 7.5:
			break
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(pos.x > 6.8 and loco.state_label == "WALK", "Reaching flat plateau exits CLIMB back to WALK")

	# 5) Walking downhill from flat ground onto moderate slope does not spuriously climb
	loco.reset()
	terrain.height_fn = func(x: float, _z: float) -> float:
		return 5.0 - maxf(0.0, x - 1.0) * 0.7
	pos = Vector3(0.0, 5.0, 0.0)
	vel = Vector3.ZERO
	for _i in 25:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "WALK", "Walking downhill does not trigger upward CLIMB")

	# 6) Deep sea prioritizes SWIM even over a steep seabed
	loco.reset()
	terrain.height_fn = func(x: float, _z: float) -> float:
		return -2.5 + x * 1.1
	terrain.water_y = 0.95
	terrain.biome = MapTypes.Biome.SEA
	pos = Vector3(0.0, -2.5, 0.0)
	vel = Vector3.ZERO
	for _i in 20:
		var res := loco.step(pos, vel, Vector2(1.0, 0.0), false, terrain, 0.05)
		pos = res["position"] as Vector3
		vel = res["velocity"] as Vector3
	_assert(loco.state_label == "SWIM", "Deep water prioritizes SWIM over steep seabed")

	# 7) Real MapData steep cliff cell triggers CLIMB when walked uphill
	var real_map: MapData = MapGen.generate(42, {"landform": MapTypes.Landform.TERRACED_HIGHLANDS, "relief": 1.0})
	var best_pos := Vector2.ZERO
	var best_grad := Vector2.ZERO
	for z in range(10, real_map.grid - 10):
		for x in range(10, real_map.grid - 10):
			var wx := (float(x) / float(real_map.grid - 1) - 0.5) * real_map.size
			var wz := (float(z) / float(real_map.grid - 1) - 0.5) * real_map.size
			if real_map.sample_height(wx, wz) < real_map.water_y + 1.0:
				continue
			var gx := (real_map.sample_height(wx + 0.35, wz) - real_map.sample_height(wx - 0.35, wz)) / 0.70
			var gz := (real_map.sample_height(wx, wz + 0.35) - real_map.sample_height(wx, wz - 0.35)) / 0.70
			var g := Vector2(gx, gz)
			if g.length() > best_grad.length():
				best_grad = g
				best_pos = Vector2(wx, wz)
	_assert(best_grad.length() > CharacterLocomotion.CLIMB_ENTER_GRADE, "Generated Terraced Highlands has steep climbable cliff")
	loco.reset()
	var up_dir := best_grad.normalized()
	var start_xz := best_pos - up_dir * 0.4
	var rpos := Vector3(start_xz.x, real_map.sample_height(start_xz.x, start_xz.y), start_xz.y)
	var rvel := Vector3.ZERO
	var real_climbed := false
	for _i in 20:
		var res := loco.step(rpos, rvel, up_dir, false, real_map, 0.05)
		rpos = res["position"] as Vector3
		rvel = res["velocity"] as Vector3
		if loco.state_label == "CLIMB":
			real_climbed = true
	_assert(real_climbed, "Real MapData steep cliff triggers CLIMB when moving uphill")


func _test_input_router() -> void:
	var router := InputRouterScript.new()
	_assert(router.is_gameplay_active(), "InputRouter defaults to GAMEPLAY active")
	_assert(router.allow_debug(), "InputRouter allows debug by default")

	router.push_context(InputRouterScript.Context.UI, &"pause")
	_assert(not router.is_gameplay_active(), "UI context blocks gameplay input")
	_assert(router.is_ui_active(), "UI context reports is_ui_active()")
	_assert(router.allow_debug(), "UI context still allows debug")

	router.push_context(InputRouterScript.Context.MODAL, &"confirm")
	_assert(not router.allow_debug(), "MODAL context blocks debug hotkeys")
	_assert(router.get_stack_size() == 2, "Stack size tracks distinct owners")

	# Re-pushing same owner updates in place without leaking entries
	router.push_context(InputRouterScript.Context.MODAL, &"confirm")
	_assert(router.get_stack_size() == 2, "Re-pushing same owner does not duplicate stack entries")

	router.pop_context(&"confirm")
	_assert(router.is_ui_active() and router.allow_debug(), "Popping MODAL restores UI context")

	router.pop_context(&"pause")
	_assert(router.is_gameplay_active(), "Popping UI restores GAMEPLAY context")
	router.free()


func _test_settings_store() -> void:
	var tmp_path := "user://test_settings_phase2.cfg"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)

	var store := SettingsStoreScript.new()
	store.config_path = tmp_path
	store.load_settings()

	_assert(is_equal_approx(float(store.get_value("master_volume")), 1.0), "SettingsStore default master_volume is 1.0")
	var emitted := []
	store.setting_changed.connect(func(k: String, v: Variant) -> void: emitted.append([k, v]))

	store.set_value("sfx_volume", 1.8) # should clamp to 1.0 (was 0.90)
	_assert(is_equal_approx(float(store.get_value("sfx_volume")), 1.0), "SettingsStore clamps sfx_volume <= 1.0")
	store.set_value("bgm_volume", -0.5) # should clamp to 0.0
	_assert(is_equal_approx(float(store.get_value("bgm_volume")), 0.0), "SettingsStore clamps bgm_volume >= 0.0")
	store.set_value("show_debug_hud", false)
	_assert(emitted.size() == 3, "setting_changed fires for each unique change")

	var reloaded := SettingsStoreScript.new()
	reloaded.config_path = tmp_path
	var err := reloaded.load_settings()
	_assert(err == OK, "SettingsStore loads saved ConfigFile cleanly")
	_assert(is_equal_approx(float(reloaded.get_value("bgm_volume")), 0.0), "Persisted bgm_volume survives reload")
	_assert(bool(reloaded.get_value("show_debug_hud")) == false, "Persisted show_debug_hud survives reload")

	reloaded.reset_defaults()
	_assert(bool(reloaded.get_value("show_debug_hud")) == true, "reset_defaults restores show_debug_hud")

	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)
	store.free()
	reloaded.free()


func _test_settings_locale() -> void:
	var prev_locale := TranslationServer.get_locale()
	var shipped = TranslationCatalogScript.new()
	var shipped_err: Error = shipped.load_dir("res://data")
	_assert(shipped_err == OK, "res://data localization catalog loads")
	var shipped_locales: PackedStringArray = shipped.get_locales()
	_assert(shipped_locales.has("en") and shipped_locales.has("zh"), "Shipped ui_i18n.csv exposes en and zh")
	_assert(shipped.message("zh", "SETTINGS_LANGUAGE") == "语言", "Shipped zh translation for SETTINGS_LANGUAGE")
	_assert(shipped.message("zh", "TITLE_CONTINUE") == "继续", "Title screen has a Chinese string")
	_assert(shipped.get_locales().size() == 2, "Locale aliases stay out of the language list")
	_assert(shipped.locale_label("zh") == "中文", "Locale autonym is read from that locale")
	shipped.unload()

	var tmp_cfg := "user://test_settings_locale.cfg"
	var tmp_dir := "user://test_i18n_catalog"
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)
	_wipe_user_dir(tmp_dir)
	DirAccess.make_dir_absolute(tmp_dir)

	var csv_file := FileAccess.open(tmp_dir.path_join("ui_i18n.csv"), FileAccess.WRITE)
	_assert(csv_file != null, "Locale fixture CSV opens")
	if csv_file != null:
		csv_file.store_string("keys,en,zh\nTEST_HELLO,\"Hello, world\",你好\nLOCALE_en,English,英语\nLOCALE_zh,Chinese,中文\n")
		csv_file.close()
	var manifest_file := FileAccess.open(tmp_dir.path_join("i18n_manifest.json"), FileAccess.WRITE)
	_assert(manifest_file != null, "Locale fixture manifest opens")
	if manifest_file != null:
		manifest_file.store_string("{\n  \"version\": 1,\n  \"default_locale\": \"en\",\n  \"locales\": [\"en\", \"zh\"],\n  \"files\": [\"ui_i18n.csv\"]\n}\n")
		manifest_file.close()

	var store := SettingsStoreScript.new()
	store.config_path = tmp_cfg
	store.translation_dir = tmp_dir
	store.load_settings()
	var err: Error = store.load_translations()
	_assert(err == OK, "SettingsStore loads localization CSV into TranslationServer")
	_assert(FontFallbackScript.is_applied(), "CJK font fallback is attached to ThemeDB")
	_assert(store.get_locales().size() == 2, "SettingsStore locales come from the catalog")
	store.set_value("locale", "zh")
	_assert(str(store.get_value("locale")) == "zh", "SettingsStore accepts catalog locale zh")
	_assert(TranslationServer.get_locale() == "zh", "SettingsStore applies locale through TranslationServer")
	_assert(tr("TEST_HELLO") == "你好", "Quoted CSV cell reaches TranslationServer for zh")
	_assert(store.locale_label("zh") == "中文", "SettingsStore locale_label uses the locale autonym")
	store.set_value("locale", "nope")
	_assert(str(store.get_value("locale")) == "en", "Unknown locale falls back to default_locale")
	_assert(TranslationServer.get_locale() == "en", "Fallback locale is applied to TranslationServer")

	store.set_value("locale", "zh")
	var reloaded := SettingsStoreScript.new()
	reloaded.config_path = tmp_cfg
	reloaded.translation_dir = tmp_dir
	var load_err := reloaded.load_settings()
	_assert(load_err == OK and str(reloaded.get_value("locale")) == "zh", "Persisted locale survives SettingsStore reload")
	_assert(reloaded.load_translations() == OK, "Reloaded SettingsStore loads the same catalog")
	_assert(TranslationServer.get_locale() == "zh" and tr("TEST_HELLO") == "你好", "Reloaded locale is applied to TranslationServer")
	reloaded.reset_defaults()
	_assert(str(reloaded.get_value("locale")) == "en" and TranslationServer.get_locale() == "en", "reset_defaults restores locale en")
	_assert(tr("TEST_HELLO") == "Hello, world", "Quoted comma in the en column survives CSV parsing")

	store.clear_translations()
	reloaded.clear_translations()
	TranslationServer.set_locale(prev_locale)
	store.free()
	reloaded.free()
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)
	_wipe_user_dir(tmp_dir)


func _wipe_user_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in DirAccess.get_files_at(path):
		dir.remove(String(name))
	DirAccess.remove_absolute(path)


func _test_audio_manager() -> void:
	var am := AudioManagerScript.new()
	am.ensure_buses()
	for bus_name: StringName in AudioManagerScript.REQUIRED_BUSES:
		_assert(AudioServer.get_bus_index(bus_name) >= 0, "AudioServer has bus '%s'" % String(bus_name))

	am.set_bus_volume(AudioManagerScript.BUS_SFX, 1.5)
	_assert(is_equal_approx(am.get_bus_volume(AudioManagerScript.BUS_SFX), 1.0), "AudioManager clamps bus volume <= 1.0")

	am.set_bus_volume(AudioManagerScript.BUS_BGM, 0.0)
	var bgm_idx := AudioServer.get_bus_index(AudioManagerScript.BUS_BGM)
	_assert(AudioServer.is_bus_mute(bgm_idx), "AudioManager mutes bus when linear volume is 0.0")

	am.set_bus_volume(AudioManagerScript.BUS_BGM, 0.5)
	_assert(not AudioServer.is_bus_mute(bgm_idx), "AudioManager unmutes bus when linear volume > 0")
	_assert(not am.is_shutting_down(), "AudioManager is not shutting down initially")

	get_root().add_child(am)
	var sfx_stream := AudioStreamWAV.new()
	var p3d := am.play_sfx_at(Vector3(4.0, 1.5, -2.0), sfx_stream, -6.0)
	_assert(am.get_sfx3d_pool_size() == AudioManagerScript.SFX3D_POOL_SIZE, "AudioManager creates 3D SFX pool")
	_assert(p3d != null and p3d.stream == sfx_stream, "AudioManager.play_sfx_at assigns stream")
	_assert(p3d.global_position.is_equal_approx(Vector3(4.0, 1.5, -2.0)), "AudioManager.play_sfx_at sets 3D position")
	_assert(p3d.bus == AudioManagerScript.BUS_SFX, "AudioManager.play_sfx_at routes through SFX bus")

	var dummy_player := AudioStreamPlayer.new()
	dummy_player.stream = AudioStreamWAV.new()
	get_root().add_child(dummy_player)
	am.prepare_shutdown()
	_assert(am.is_shutting_down(), "AudioManager marks shutting down on prepare_shutdown()")
	_assert(dummy_player.stream == null, "AudioManager.prepare_shutdown() clears scene AudioStreamPlayer streams")
	get_root().remove_child(dummy_player)
	dummy_player.free()
	get_root().remove_child(am)
	am.free()


func _test_save_service() -> void:
	var tmp_dir := "user://test_saves_phase2"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir

	_assert(svc.sanitize_slot("../bad/slot!@#") == "badslot", "sanitize_slot strips path traversal & symbols")

	var sample_payload := {
		"world": {"seed": 9876, "landform": 2, "relief": 1.0},
		"sky": {"hour": 14.25, "weather": 3, "speed_index": 1},
		"player": {"position": [1.5, 2.0, -3.5], "facing_yaw": 0.5, "run_mode": true},
	}
	var save_err := svc.save_slot("test_slot", sample_payload)
	_assert(save_err == OK, "SaveService writes slot cleanly")
	_assert(svc.has_slot("test_slot"), "SaveService reports slot exists")

	var loaded := svc.load_slot("test_slot")
	_assert(bool(loaded.get("ok", false)), "SaveService loads valid slot")
	var ldata: Dictionary = loaded["data"] as Dictionary
	_assert(int((ldata["world"] as Dictionary)["seed"]) == 9876, "SaveService preserves world seed")

	# Deterministic regeneration check from saved seed + landform
	var w: Dictionary = ldata["world"] as Dictionary
	var m1: MapData = MapGen.generate(int(w["seed"]), {"landform": int(w["landform"]), "relief": float(w["relief"])})
	var m2: MapData = MapGen.generate(int(w["seed"]), {"landform": int(w["landform"]), "relief": float(w["relief"])})
	_assert(is_equal_approx(m1.sample_height(5.0, -5.0), m2.sample_height(5.0, -5.0)), "Saved seed reproduces exact heightfield")

	# Corrupt JSON & unsupported schema validation
	var bad_path := svc.get_slot_path("corrupt")
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string("{not valid json")
	f.close()
	var bad_res := svc.load_slot("corrupt")
	_assert(not bool(bad_res.get("ok", true)), "SaveService rejects corrupt JSON cleanly")

	var old_ver_path := svc.get_slot_path("bad_ver")
	var f2 := FileAccess.open(old_ver_path, FileAccess.WRITE)
	f2.store_string('{"schema_version": 999, "world": {"seed": 1}}')
	f2.close()
	var ver_res := svc.load_slot("bad_ver")
	_assert(not bool(ver_res.get("ok", true)), "SaveService rejects unsupported schema_version")

	svc.delete_slot("test_slot")
	svc.delete_slot("corrupt")
	svc.delete_slot("bad_ver")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()


func _test_game_flow_and_ui_router() -> void:
	# Verify autoloads registered in project.godot work inside SceneTree
	var flow := get_root().get_node_or_null("GameFlow")
	var ui := get_root().get_node_or_null("UIRouter")
	var input_router := get_root().get_node_or_null("InputRouter")
	_assert(flow != null and ui != null and input_router != null, "Autoloads GameFlow, UIRouter, InputRouter exist on SceneTree root")
	if flow == null or ui == null or input_router == null:
		return

	var mock_world := MockWorld.new()
	get_root().add_child(mock_world)
	flow.call("register_world", mock_world)

	var dummy_scene := PackedScene.new()
	var dummy_ctrl := Control.new()
	dummy_scene.pack(dummy_ctrl)
	dummy_ctrl.free()

	ui.call("register_screen", &"title", dummy_scene)
	ui.call("register_screen", &"pause", dummy_scene)
	ui.call("register_screen", &"settings", dummy_scene)

	flow.call("enter_title")
	_assert(int(flow.call("get_state")) == GameFlowScript.State.TITLE, "GameFlow transitions to TITLE")
	_assert(ui.call("top_screen_id") == &"title", "UIRouter shows title screen on enter_title()")
	_assert(not bool(input_router.call("is_gameplay_active")), "TITLE blocks gameplay input via UIRouter")

	flow.call("start_new_game", {"seed": 123})
	_assert(int(flow.call("get_state")) == GameFlowScript.State.PLAYING, "GameFlow transitions to PLAYING on start_new_game()")
	_assert(mock_world.started_count == 1, "start_new_game invokes world.start_new_world()")
	_assert(bool(input_router.call("is_gameplay_active")), "PLAYING restores GAMEPLAY input context")

	flow.call("set_paused", true)
	_assert(int(flow.call("get_state")) == GameFlowScript.State.PAUSED, "GameFlow transitions to PAUSED")
	_assert(paused, "SceneTree.paused becomes true when PAUSED")
	_assert(ui.call("top_screen_id") == &"pause", "UIRouter shows pause screen when PAUSED")

	flow.call("open_settings")
	_assert(ui.call("top_screen_id") == &"settings", "open_settings pushes settings over pause")
	flow.call("close_top_ui")
	_assert(ui.call("top_screen_id") == &"pause", "close_top_ui returns from settings to pause")
	flow.call("close_top_ui")
	_assert(int(flow.call("get_state")) == GameFlowScript.State.PLAYING, "Closing pause screen resumes PLAYING")
	_assert(not paused, "SceneTree.paused becomes false after resume")

	flow.call("return_to_title")
	_assert(int(flow.call("get_state")) == GameFlowScript.State.TITLE, "return_to_title transitions back to TITLE")
	ui.call("clear_screens")

	# Toast queue + modal confirm + transition curtain checks
	ui.call("clear_toasts")
	ui.call("show_toast", "Toast 1", 1.0, &"info")
	ui.call("show_toast", "Toast 2", 1.0, &"success")
	ui.call("show_toast", "Toast 3", 1.0, &"warning")
	ui.call("show_toast", "Toast 4", 1.0, &"error")
	_assert(int(ui.call("get_active_toast_count")) == 3, "UIRouter caps active toasts at MAX_ACTIVE_TOASTS")
	_assert(int(ui.call("get_queued_toast_count")) == 1, "UIRouter queues excess toasts")
	ui.call("clear_toasts")

	var confirm_hits := [0]
	var dlg := ui.call("show_confirm", "Confirm", "Test body", func() -> void: confirm_hits[0] += 1) as Control
	_assert(dlg != null, "UIRouter.show_confirm returns dialog node")
	_assert(ui.call("top_screen_id") == UIRouterScript.CONFIRM_SCREEN_ID, "show_confirm pushes modal onto UIRouter")
	_assert(not bool(input_router.call("allow_debug")), "show_confirm activates InputRouter.Context.MODAL")
	dlg.call("confirm")
	_assert(confirm_hits[0] == 1, "ConfirmDialog.confirm invokes callback")
	_assert(bool(input_router.call("allow_debug")), "ConfirmDialog.confirm restores InputRouter context")

	ui.call("fade_out", 0.0)
	_assert(is_equal_approx(float(ui.call("get_transition_alpha")), 1.0), "UIRouter.fade_out reaches opaque")
	ui.call("fade_in", 0.0)
	_assert(is_equal_approx(float(ui.call("get_transition_alpha")), 0.0), "UIRouter.fade_in returns transparent")

	mock_world.queue_free()


func _test_protoss_ui_skin() -> void:
	var theme_path := "res://addons/gu_core/ui/protoss/protoss_theme.tres"
	var theme := load(theme_path) as Theme
	_assert(theme != null, "Protoss theme loads cleanly")
	if theme != null:
		_assert(theme.get_stylebox("panel", "PanelContainer") is StyleBoxTexture, "Protoss theme defines StyleBoxTexture for PanelContainer")
		_assert(theme.get_stylebox("normal", "Button") is StyleBoxTexture, "Protoss theme defines StyleBoxTexture for Button normal")
		_assert(theme.get_stylebox("hover", "Button") is StyleBoxTexture, "Protoss theme defines StyleBoxTexture for Button hover")
		_assert(theme.get_icon("grabber", "HSlider") is Texture2D, "Protoss theme defines HSlider grabber icon")
		_assert(theme.get_icon("checked", "CheckButton") is Texture2D, "Protoss theme defines CheckButton checked icon")

	var sfx_paths := [
		"res://addons/gu_core/audio/sfx/protoss_hover.wav",
		"res://addons/gu_core/audio/sfx/protoss_click.wav",
		"res://addons/gu_core/audio/sfx/protoss_back.wav",
		"res://addons/gu_core/audio/sfx/protoss_open.wav",
	]
	for p: String in sfx_paths:
		_assert(load(p) is AudioStream, "Protoss UI SFX loads cleanly: %s" % p)

	var plain := load("res://addons/gu_core/ui/default_theme.tres") as Theme
	_assert(plain != null, "Gray theme loads cleanly")
	if plain != null:
		_assert(plain.get_stylebox("panel", "PanelContainer") is StyleBoxFlat, "Gray theme uses a flat panel")
		_assert(plain.get_stylebox("normal", "Button") is StyleBoxFlat, "Gray theme uses a flat button")
	var ui := get_root().get_node_or_null("UIRouter")
	_assert(ui != null, "UIRouter autoload available for theme check")
	if ui != null:
		var stack_root := ui.get_node_or_null("UIRouterLayer/ScreenStack") as Control
		_assert(stack_root != null and stack_root.theme == plain, "UIRouter uses the gray theme")

	var screen_paths := [
		"res://scenes/ui/title_screen.tscn",
		"res://scenes/ui/pause_menu.tscn",
		"res://scenes/ui/settings_panel.tscn",
		"res://addons/gu_core/ui/save_slots_panel.tscn",
	]
	for sp: String in screen_paths:
		var packed := load(sp) as PackedScene
		_assert(packed != null, "UI scene loads cleanly: %s" % sp)
		if packed != null:
			var inst := packed.instantiate() as Control
			_assert(inst != null, "UI scene instantiates as Control: %s" % sp)
			if inst != null:
				get_root().add_child(inst)
				if inst.has_method("on_ui_enter"):
					inst.call("on_ui_enter", {})
				var panel := inst.get_node_or_null("%Panel") as PanelContainer
				_assert(panel != null, "UI scene exposes %%Panel container: %s" % sp)
				get_root().remove_child(inst)
				inst.free()


func _test_world_locator() -> void:
	var seeds := [17, 42, 108, 256, 999]
	var min_spacing := 16.0
	for s: int in seeds:
		var data: MapData = MapGen.generate(s, {"relief": 1.0})
		var spawn: Vector3 = WorldLocatorScript.find_spawn_point(data)
		var spawn_biome := data.sample_biome(spawn.x, spawn.z)
		_assert(
			spawn_biome != MapTypes.Biome.SEA
			and spawn_biome != MapTypes.Biome.LAKE
			and spawn_biome != MapTypes.Biome.RIVER
			and spawn_biome != MapTypes.Biome.CLIFF,
			"Seed %d spawn biome (%s) avoids water and cliff" % [s, MapTypes.biome_name(spawn_biome)]
		)
		_assert(
			data.sample_water_surface(spawn.x, spawn.z) <= -1000.0,
			"Seed %d spawn is not in swimmable water" % s
		)
		_assert(spawn.y >= data.water_y, "Seed %d spawn sits at or above water_y" % s)

		var pois: Array[Dictionary] = WorldLocatorScript.find_poi_spots(data, 6, min_spacing, spawn)
		_assert(pois.size() >= 3, "Seed %d locates at least 3 POI spots (got %d)" % [s, pois.size()])
		for i in pois.size():
			var p: Vector3 = pois[i]["position"] as Vector3
			var b: int = int(pois[i]["biome"])
			_assert(
				b != MapTypes.Biome.SEA
				and b != MapTypes.Biome.LAKE
				and b != MapTypes.Biome.RIVER
				and b != MapTypes.Biome.CLIFF,
				"Seed %d POI %d avoids water and cliff" % [s, i]
			)
			_assert(data.sample_water_surface(p.x, p.z) <= -1000.0, "Seed %d POI %d is dry" % [s, i])
			for j in range(i + 1, pois.size()):
				var q: Vector3 = pois[j]["position"] as Vector3
				var d := Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z))
				_assert(d >= min_spacing - 0.01, "Seed %d POIs %d-%d respect min_spacing (%.2f)" % [s, i, j, d])


func _test_interaction_system() -> void:
	var host := Node3D.new()
	get_root().add_child(host)

	var actor := Node3D.new()
	actor.position = Vector3.ZERO
	host.add_child(actor)

	var router := InputRouterScript.new()
	host.add_child(router)

	var interactor := InteractorScript.new()
	interactor.interact_range = 3.0
	interactor.auto_bind_input = false
	interactor.input_router = router
	actor.add_child(interactor)
	interactor.set_actor(actor)

	var near_item := InteractableScript.new()
	near_item.interaction_id = "near"
	near_item.prompt_text = "Open Crate"
	near_item.position = Vector3(1.0, 0.0, 0.0)
	host.add_child(near_item)

	var far_item := InteractableScript.new()
	far_item.interaction_id = "far"
	far_item.prompt_text = "Pull Lever"
	far_item.position = Vector3(2.1, 0.0, 0.0)
	host.add_child(far_item)

	var focus_events: Array[Interactable] = []
	interactor.focus_changed.connect(func(t: Interactable) -> void: focus_events.append(t))

	var triggered := [0]
	near_item.interacted.connect(func(_a: Node) -> void: triggered[0] += 1)
	var far_triggered := [0]
	far_item.interacted.connect(func(_a: Node) -> void: far_triggered[0] += 1)

	var focused := interactor.refresh_focus()
	_assert(focused == near_item, "Interactor focuses nearest interactable")
	_assert(focus_events.size() == 1 and focus_events[0] == near_item, "focus_changed emits on initial focus")

	# InputRouter blocking check
	router.push_context(InputRouterScript.Context.UI, &"modal_test")
	_assert(not interactor.try_interact(), "Interactor blocks try_interact when InputRouter is in UI context")
	_assert(triggered[0] == 0, "Blocked interaction does not fire interacted signal")

	router.pop_context(&"modal_test")
	_assert(interactor.try_interact(), "Interactor succeeds when InputRouter returns to GAMEPLAY")
	_assert(triggered[0] == 1, "Unblocked interaction fires interacted signal")

	# Disabling closer target switches focus to second target
	near_item.enabled = false
	var next_focus := interactor.refresh_focus()
	_assert(next_focus == far_item, "Disabling focused target shifts focus to next valid interactable")
	_assert(interactor.try_interact() and far_triggered[0] == 1, "Interactor triggers newly focused target")

	host.free()


func _test_surface_resolver_and_audio_bank() -> void:
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.GRASS, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.GRASS,
		"Grass biome resolves to GRASS surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.SAND, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.SAND,
		"Sand biome resolves to SAND surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.DIRT, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.DIRT,
		"Dirt biome resolves to DIRT surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.CLIFF, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.ROCK,
		"Cliff biome resolves to ROCK surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.GRASS, 0.0, 0.6) == SurfaceResolverScript.SurfaceType.SNOW,
		"High snow_cover overrides Grass to SNOW surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.ALPINE, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.SNOW,
		"Alpine biome resolves to SNOW surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.RIVER, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.SHALLOW_WATER,
		"River biome resolves to SHALLOW_WATER surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.SAND, 0.15, 0.0) == SurfaceResolverScript.SurfaceType.SHALLOW_WATER,
		"Shallow water_depth overrides Sand to SHALLOW_WATER surface"
	)
	_assert(
		SurfaceResolverScript.resolve_by_name("Alpine", 0.0, 0.0) == SurfaceResolverScript.SurfaceType.SNOW,
		"SurfaceResolver.resolve_by_name maps Alpine to SNOW without MapTypes dependency"
	)

	var bank := SurfaceAudioBankScript.new()
	bank.load_default_fallbacks()
	_assert(not bank.fallback_walk.is_empty(), "SurfaceAudioBank loads default walk fallback streams")
	_assert(not bank.fallback_run.is_empty(), "SurfaceAudioBank loads default run fallback streams")

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var fb_stream := bank.get_stream(SurfaceResolverScript.SurfaceType.SAND, false, rng)
	_assert(fb_stream != null and bank.fallback_walk.has(fb_stream), "Empty surface pool falls back to foot_walk_*.wav")

	var custom_stream := AudioStreamWAV.new()
	bank.sand_walk = [custom_stream]
	_assert(
		bank.get_stream(SurfaceResolverScript.SurfaceType.SAND, false, rng) == custom_stream,
		"Populated surface pool overrides fallback stream"
	)


func _test_beacon_save_roundtrip() -> void:
	var host := Node3D.new()
	get_root().add_child(host)

	var b1 := WorldBeaconScript.new()
	b1.configure("beacon_1", 1, "Grass", Color(0.24, 0.88, 1.0))
	host.add_child(b1)

	var b2 := WorldBeaconScript.new()
	b2.configure("beacon_2", 2, "Sand", Color(0.96, 0.78, 0.28))
	host.add_child(b2)

	_assert(not b1.is_lit and not b2.is_lit, "Beacons initialize unlit")
	_assert(b1.interact(host), "Interacting with WorldBeacon toggles it")
	_assert(b1.is_lit, "Beacon_1 becomes lit after interact")

	var lit_ids: Array[String] = []
	for b in [b1, b2]:
		if b.is_lit:
			lit_ids.append(b.interaction_id)

	var tmp_dir := "user://test_saves_phase3"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	var err := svc.save_slot("beacon_slot", {
		"world": {"seed": 42, "landform": 0, "relief": 1.0},
		"beacons": {"lit_ids": lit_ids},
	})
	_assert(err == OK, "SaveService persists beacon lit_ids")

	var loaded := svc.load_slot("beacon_slot")
	_assert(bool(loaded.get("ok", false)), "SaveService reloads beacon slot cleanly")
	var restored_ids: Array = ((loaded["data"] as Dictionary).get("beacons", {}) as Dictionary).get("lit_ids", []) as Array

	var b1_reloaded := WorldBeaconScript.new()
	b1_reloaded.configure("beacon_1", 1, "Grass", Color(0.24, 0.88, 1.0))
	host.add_child(b1_reloaded)
	b1_reloaded.set_lit(restored_ids.has(b1_reloaded.interaction_id), false)

	var b2_reloaded := WorldBeaconScript.new()
	b2_reloaded.configure("beacon_2", 2, "Sand", Color(0.96, 0.78, 0.28))
	host.add_child(b2_reloaded)
	b2_reloaded.set_lit(restored_ids.has(b2_reloaded.interaction_id), false)

	_assert(b1_reloaded.is_lit, "Reloaded Beacon_1 restores lit state from SaveService")
	_assert(not b2_reloaded.is_lit, "Reloaded Beacon_2 remains unlit from SaveService")

	svc.delete_slot("beacon_slot")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()
	host.free()


func _test_character_action_architecture() -> void:
	var reg := CharacterActionRegistry.create_default()
	for id: StringName in [&"gather", &"mine", &"chop", &"build"]:
		_assert(reg.has_action(id), "Default registry includes action '%s'" % String(id))
		var spec := reg.get_spec(id)
		_assert(spec != null and spec.is_valid(), "Action spec '%s' is valid" % String(id))

	var bad_spec := CharacterActionSpec.new({"id": "", "duration": 0.0})
	_assert(not reg.register(bad_spec), "Registry rejects invalid CharacterActionSpec")

	var custom := CharacterActionSpec.new({
		"id": "fish",
		"display_name": "FISH",
		"duration": 0.8,
		"hit_phases": [0.5],
		"move_policy": CharacterActionSpec.MovePolicy.LOCK,
		"allow_in_water": true,
		"max_water_depth": 1.0,
	})
	_assert(reg.register(custom) and reg.has_action(&"fish"), "Registry supports dynamic custom action registration")
	reg.unregister(&"fish")
	_assert(not reg.has_action(&"fish"), "Registry supports unregistering actions")

	var ctrl := CharacterActionController.new()
	var loco := CharacterLocomotion.new()
	var terrain := MockTerrain.new()
	terrain.ground_y = 2.0
	terrain.water_y = -INF
	terrain.biome = MapTypes.Biome.GRASS
	loco.step(Vector3.ZERO, Vector3.ZERO, Vector2.ZERO, false, terrain, 0.05)

	var started_log: Array[StringName] = []
	var beat_log: Array[Array] = []
	var done_log: Array[Array] = []
	var cancel_log: Array[Array] = []
	ctrl.action_started.connect(func(id: StringName, _s: CharacterActionSpec) -> void: started_log.append(id))
	ctrl.action_beat.connect(func(id: StringName, b: int, c: int) -> void: beat_log.append([id, b, c]))
	ctrl.action_completed.connect(func(id: StringName, c: int) -> void: done_log.append([id, c]))
	ctrl.action_cancelled.connect(func(id: StringName, r: StringName) -> void: cancel_log.append([id, r]))

	# Single-cycle tap completion + double-beat build action
	_assert(ctrl.try_start(&"build", loco, {
		"origin_pos": Vector3.ZERO,
		"target_pos": Vector3(2.0, 0.0, 0.0),
	}), "Build action starts on dry ground")
	_assert(ctrl.is_acting(), "ActionController reports is_acting() after start")
	_assert(ctrl.has_target_yaw and is_equal_approx(ctrl.target_yaw, PI * 0.5), "ActionController computes target_yaw toward target_pos")
	_assert(started_log.size() == 1 and started_log[0] == &"build", "action_started signal fires once")

	for _i in 30:
		var frame := ctrl.step(0.05, loco, Vector2.ZERO, false)
		var lres := loco.step(
			Vector3.ZERO,
			Vector3(1.0, 0.0, 0.0),
			Vector2.ZERO,
			false,
			terrain,
			0.05,
			float(frame.get("move_scale", 1.0)),
			float(frame.get("facing_override_yaw", 0.0)) if bool(frame.get("has_facing_override", false)) else NAN
		)
		if not ctrl.is_acting():
			_assert((lres["velocity"] as Vector3).length() < 1.0, "Locomotion decelerates while action locks movement")
			break
	_assert(not ctrl.is_acting(), "Single tap action finishes cleanly after 1 cycle")
	_assert(beat_log.size() == 2, "Build action emits 2 hit beats per cycle")
	_assert(done_log.size() == 1 and int(done_log[0][1]) == 1, "action_completed reports 1 finished cycle")

	# Continuous hold looping (mine) + movement interrupt
	beat_log.clear()
	_assert(ctrl.try_start(&"mine", loco), "Mine action starts")
	for _i in 30:
		ctrl.step(0.05, loco, Vector2.ZERO, true)
	_assert(ctrl.is_acting() and ctrl.cycle_count >= 1, "Holding input loops mine action past cycle 1")
	_assert(beat_log.size() >= 1, "Looped mine action emits hit beats")

	var moved_frame := ctrl.step(0.016, loco, Vector2(1.0, 0.0), false)
	_assert(not bool(moved_frame.get("is_acting", true)), "Movement cancels CANCEL_ON_MOVE action immediately")
	_assert(cancel_log.size() == 1 and cancel_log[0][1] == &"moved", "Cancel reason is 'moved'")

	# Environment guards: deep water & climbing
	loco.swim_amt = 0.8
	loco.water_depth = 1.3
	_assert(not ctrl.try_start(&"chop", loco), "Cannot start chop while swimming in deep water")
	_assert(ctrl.last_cancel_reason == &"swimming", "Blocked reason is 'swimming'")

	loco.swim_amt = 0.0
	loco.water_depth = 0.0
	loco.is_climbing = true
	loco.climb_amt = 0.8
	_assert(not ctrl.try_start(&"gather", loco), "Cannot start gather while climbing steep cliff")
	_assert(ctrl.last_cancel_reason == &"climbing", "Blocked reason is 'climbing'")


func _test_work_ik_and_tool_visual() -> void:
	var packed := load("res://assets/models/quaternius/AnimatedHuman.fbx") as PackedScene
	_assert(packed != null, "AnimatedHuman.fbx loads for WorkIKSolver test")
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_assert(skel != null, "AnimatedHuman.fbx exposes Skeleton3D")
	if skel == null:
		model.free()
		return

	var ik := WorkIKSolver.new()
	ik.bind_skeleton(skel)
	_assert(ik.has_valid_rig(), "WorkIKSolver binds to AnimatedHuman Skeleton3D")

	for profile: StringName in [&"gather", &"mine", &"chop", &"build"]:
		for phase in [0.1, 0.45, 0.75]:
			ik.apply_work(profile, phase, 1.0, 0.05)
	var hips_idx := skel.find_bone("Hips")
	var hips_q := skel.get_bone_pose_rotation(hips_idx)
	_assert(hips_q.is_normalized() and is_finite(hips_q.x), "WorkIKSolver produces valid normalized bone rotations")

	var tool_vis := HandToolVisual.new()
	tool_vis.bind_skeleton(skel)
	var attach := skel.find_child("RightHandToolAttachment", false, false) as BoneAttachment3D
	_assert(attach != null and attach.bone_name == "RightHand", "HandToolVisual attaches BoneAttachment3D to RightHand")
	tool_vis.set_active_tool(CharacterActionSpec.ToolType.AXE)
	var axe_node := attach.find_child("Axe", true, false) as Node3D
	var pick_node := attach.find_child("Pickaxe", true, false) as Node3D
	_assert(axe_node != null and axe_node.visible, "Axe tool becomes visible when active")
	_assert(pick_node != null and not pick_node.visible, "Pickaxe tool stays hidden when Axe is active")
	tool_vis.cleanup()
	tool_vis.free()
	model.free()


func _test_event_bus() -> void:
	var bus_autoload := get_root().get_node_or_null("EventBus")
	_assert(bus_autoload != null, "Autoload EventBus exists on SceneTree root")

	var bus := EventBusScript.new()
	var received: Array[Dictionary] = []
	var cb := func(payload: Dictionary) -> void: received.append(payload)

	bus.subscribe(&"quest_step", cb)
	bus.subscribe(&"quest_step", cb) # idempotent duplicate check
	_assert(bus.get_subscriber_count(&"quest_step") == 1, "EventBus avoids duplicate callback subscriptions")

	bus.emit_event(&"quest_step", {"step": 2})
	_assert(received.size() == 1 and int(received[0]["step"]) == 2, "EventBus delivers payload to subscribers")

	bus.unsubscribe(&"quest_step", cb)
	bus.emit_event(&"quest_step", {"step": 3})
	_assert(received.size() == 1, "EventBus stops delivering after unsubscribe")

	var target := Node.new()
	var obj_cb := Callable(target, "set_name")
	bus.subscribe(&"rename_evt", obj_cb)
	bus.unsubscribe_all(target)
	_assert(bus.get_subscriber_count(&"rename_evt") == 0, "EventBus.unsubscribe_all removes target callbacks")
	target.free()
	bus.free()


func _test_camera_rig_shake() -> void:
	var host := Node3D.new()
	get_root().add_child(host)

	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	host.add_child(rig)

	var target := Node3D.new()
	target.position = Vector3(5.0, 1.0, -3.0)
	host.add_child(target)

	rig.set_target(target)
	_assert(rig.global_position.is_equal_approx(Vector3(5.0, 1.0, -3.0) + CameraRig.DEFAULT_OFFSET), "CameraRig snaps to target on set_target")

	rig.set_zoom(0.2)
	_assert(is_equal_approx(rig.get_zoom(), CameraRig.ZOOM_MIN), "CameraRig clamps zoom min")
	rig.set_zoom(1.0)

	rig.set_yaw(PI * 0.5)
	_assert(is_equal_approx(rig.get_yaw(), PI * 0.5), "CameraRig stores yaw")
	rig._process(2.0)
	var orbited := target.global_position + Basis(Vector3.UP, PI * 0.5) * CameraRig.DEFAULT_OFFSET
	_assert(rig.global_position.distance_to(orbited) < 0.05, "CameraRig orbits around the target")
	var ahead := rig.world_move(Vector2(0.0, -1.0))
	_assert(ahead.distance_to(Vector2(-1.0, 0.0)) < 0.02, "Forward follows the camera yaw")
	rig.set_yaw(0.0)

	rig.add_shake(0.5, 0.4)
	_assert(rig.get_shake_remaining() > 0.35, "CameraRig.add_shake schedules impulse")
	rig._process(0.1)
	_assert(rig.get_shake_remaining() < 0.35, "CameraRig decays shake over time")
	rig._process(0.5)
	_assert(is_equal_approx(cam.h_offset, 0.0) and is_equal_approx(cam.v_offset, 0.0), "CameraRig resets offsets after shake ends")

	rig.clear_target()
	host.free()


func _test_stat_set_and_inventory() -> void:
	# Decoupled Dictionary loco check for CharacterActionController
	var ctrl := CharacterActionController.new()
	_assert(ctrl.try_start(&"gather", {"swim_amt": 0.0, "is_climbing": false, "water_depth": 0.0}), "ActionController accepts Dictionary loco state")
	_assert(not ctrl.try_start(&"chop", {"swim_amt": 0.9, "water_depth": 1.2}), "ActionController blocks swimming via Dictionary state")

	var stats := StatSet.new()
	stats.define_stat(&"hp", 100.0, 80.0)
	stats.define_stat(&"stamina", 50.0)
	_assert(is_equal_approx(stats.get_value(&"hp"), 80.0), "StatSet initializes custom initial value")
	_assert(stats.spend(&"stamina", 20.0) and is_equal_approx(stats.get_value(&"stamina"), 30.0), "StatSet.spend deducts atomically")
	_assert(not stats.spend(&"stamina", 40.0) and is_equal_approx(stats.get_value(&"stamina"), 30.0), "StatSet.spend fails safely on insufficient resource")

	stats.add_modifier(&"hp", &"armor_buff", 50.0, 1.0)
	_assert(is_equal_approx(stats.get_max(&"hp"), 150.0), "StatSet additive modifier scales max")
	stats.set_value(&"hp", 150.0)
	stats.remove_modifier(&"hp", &"armor_buff")
	_assert(is_equal_approx(stats.get_value(&"hp"), 100.0), "Removing modifier clamps current value to new max")

	var inv := InventoryContainer.new(2, 10)
	var wood := ItemDef.new()
	wood.id = &"wood"
	wood.display_name = "Wood"
	wood.max_stack = 5
	inv.register_item(wood)

	var leftover := inv.add_item(&"wood", 12)
	_assert(leftover == 2, "InventoryContainer respects max_slots=2 and max_stack=5 (10 stored, 2 leftover)")
	_assert(inv.count_item(&"wood") == 10 and inv.has_item(&"wood", 10), "InventoryContainer sums stacks accurately")
	_assert(not inv.remove_item(&"wood", 11) and inv.count_item(&"wood") == 10, "Atomic remove_item leaves inventory intact when short")
	_assert(inv.remove_item(&"wood", 7) and inv.count_item(&"wood") == 3, "remove_item drains across stacks accurately")
	_assert(inv.can_add(&"wood", 7) and not inv.can_add(&"wood", 8), "InventoryContainer.can_add respects leftover stack space and free slots")
	_assert(inv.can_add(&"ore", 10) and not inv.can_add(&"ore", 11), "InventoryContainer.can_add uses default max stack for unregistered items")
	_assert(inv.count_item(&"wood") == 3, "InventoryContainer.can_add does not mutate slots")

	# SaveService round-trip for StatSet + InventoryContainer
	var tmp_dir := "user://test_saves_p1"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	var err := svc.save_slot("p1_slot", {
		"world": {"seed": 11},
		"stats": stats.export_state(),
		"inventory": inv.export_state(),
	})
	_assert(err == OK, "SaveService writes StatSet + InventoryContainer state")
	var loaded := svc.load_slot("p1_slot")
	_assert(bool(loaded.get("ok", false)), "SaveService reloads P1 slot")

	var stats2 := StatSet.new()
	stats2.apply_state((loaded["data"] as Dictionary).get("stats", {}) as Dictionary)
	_assert(is_equal_approx(stats2.get_value(&"stamina"), 30.0), "StatSet restores stamina value across SaveService")

	var inv2 := InventoryContainer.new()
	inv2.apply_state((loaded["data"] as Dictionary).get("inventory", {}) as Dictionary)
	_assert(inv2.count_item(&"wood") == 3 and inv2.max_slots == 2, "InventoryContainer restores items and max_slots across SaveService")

	svc.delete_slot("p1_slot")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()


func _test_data_table_loader() -> void:
	var table_path := "user://test_items_p2.json"
	var f := FileAccess.open(table_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 1,
		"table": "items",
		"rows": [
			{"id": "herb", "heal": 15},
			{"id": "crystal", "heal": 50},
		],
	}))
	f.close()

	var rows := DataTableLoader.load_table(table_path)
	_assert(rows.size() == 2, "DataTableLoader loads compiled JSON table rows")
	var by_id := DataTableLoader.index_by_id(rows)
	_assert(by_id.has("crystal") and int((by_id["crystal"] as Dictionary)["heal"]) == 50, "DataTableLoader.index_by_id indexes rows")
	var herb := DataTableLoader.find_by_id(rows, "herb")
	_assert(int(herb.get("heal", 0)) == 15, "DataTableLoader.find_by_id finds row by id")

	if FileAccess.file_exists(table_path):
		DirAccess.remove_absolute(table_path)


class MockPoolItem extends Node3D:
	var acquired_count: int = 0
	var released_count: int = 0

	func on_pool_acquire() -> void:
		acquired_count += 1

	func on_pool_release() -> void:
		released_count += 1


func _test_save_migrations_and_backup() -> void:
	var tmp_dir := "user://test_saves_arch"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	svc.delete_slot("mig_slot")

	# 1) Saveable registry integration
	var inv := InventoryContainer.new()
	inv.add_item(&"ore", 5)
	svc.register_saveable("inventory", inv)
	var save_err := svc.save_slot("mig_slot", {"world": {"seed": 55}})
	_assert(save_err == OK, "SaveService writes slot with registered Saveable")

	# Mutate and verify backup creation on second save
	inv.add_item(&"ore", 3)
	var save_err2 := svc.save_slot("mig_slot", {"world": {"seed": 56}})
	_assert(save_err2 == OK, "SaveService overwrites slot atomically and writes .bak")
	_assert(FileAccess.file_exists(svc.get_backup_path("mig_slot")), "SaveService creates .bak on overwrite")

	# Corrupt primary JSON -> automatic recovery from .bak (seed 55, ore 5)
	var cf := FileAccess.open(svc.get_slot_path("mig_slot"), FileAccess.WRITE)
	cf.store_string("{corrupt_primary")
	cf.close()
	var rec := svc.load_slot("mig_slot")
	_assert(bool(rec.get("ok", false)) and bool(rec.get("recovered_from_backup", false)), "SaveService recovers from .bak when primary JSON is corrupt")
	var rec_data := rec["data"] as Dictionary
	_assert(int((rec_data["world"] as Dictionary)["seed"]) == 55, "Backup recovery restores previous valid world seed")
	var inv_reloaded := InventoryContainer.new()
	svc.register_saveable("inventory", inv_reloaded)
	svc.apply_saveables(rec_data)
	_assert(inv_reloaded.count_item(&"ore") == 5, "SaveService.apply_saveables restores InventoryContainer from backup")

	# 2) Schema migration chain v1 -> v2 -> v3
	svc.current_schema_version = 3
	svc.register_migration(1, func(d: Dictionary) -> Dictionary:
		var next := d.duplicate(true)
		next["migrated_v2"] = true
		return next
	)
	svc.register_migration(2, func(d: Dictionary) -> Dictionary:
		var next := d.duplicate(true)
		next["migrated_v3"] = "done"
		return next
	)
	var mig := svc.load_slot("mig_slot")
	_assert(bool(mig.get("ok", false)), "SaveService runs v1->v2->v3 migration chain")
	var mig_data := mig["data"] as Dictionary
	_assert(int(mig_data.get("schema_version", 0)) == 3, "Migrated save reaches target schema_version 3")
	_assert(bool(mig_data.get("migrated_v2", false)) and str(mig_data.get("migrated_v3", "")) == "done", "Migrations apply in order")

	svc.delete_slot("mig_slot")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()


func _test_pool_service_and_scene_loader() -> void:
	var pool_autoload := get_root().get_node_or_null("PoolService")
	_assert(pool_autoload != null, "Autoload PoolService exists on SceneTree root")

	var pool := PoolServiceScript.new()
	get_root().add_child(pool)

	var packed := PackedScene.new()
	var tpl := MockPoolItem.new()
	packed.pack(tpl)
	tpl.free()

	pool.prewarm(packed, 2)
	var s1 := pool.get_pool_stats(packed)
	_assert(int(s1["available"]) == 2 and int(s1["active"]) == 0, "PoolService.prewarm populates available pool")

	var parent_node := Node3D.new()
	get_root().add_child(parent_node)
	var inst := pool.acquire(packed, parent_node) as MockPoolItem
	_assert(inst != null and inst.get_parent() == parent_node and inst.visible, "PoolService.acquire activates and parents node")
	_assert(inst.acquired_count == 1, "PoolService.acquire invokes on_pool_acquire()")

	pool.release(inst)
	_assert(inst.released_count == 1 and not inst.visible and inst.get_parent() == pool, "PoolService.release parks node and invokes on_pool_release()")
	var s2 := pool.get_pool_stats(packed)
	_assert(int(s2["available"]) == 2 and int(s2["active"]) == 0, "PoolService stats restore after release")

	pool.clear_pool(packed)
	parent_node.queue_free()
	pool.queue_free()

	var loader := SceneLoader.new()
	get_root().add_child(loader)
	_assert(loader.request_load("res://does_not_exist.tscn") == ERR_FILE_NOT_FOUND, "SceneLoader rejects missing scene paths")
	_assert(loader.request_load("res://scenes/ui/title_screen.tscn") == OK, "SceneLoader starts threaded request on valid scene")
	for _i in 100:
		if not loader.is_loading():
			break
		OS.delay_msec(10)
		loader._poll_once()
	_assert(not loader.is_loading() and is_equal_approx(loader.get_progress(), 1.0), "SceneLoader completes loading title_screen.tscn")
	loader.queue_free()


func _test_input_rebinding_and_dev_console() -> void:
	var tmp_cfg := "user://test_bindings_arch.cfg"
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)

	var store := SettingsStoreScript.new()
	store.config_path = tmp_cfg
	store.load_settings()

	var ir := InputRouterScript.new()
	ir.settings_store = store
	ir.register_action(&"test_jump", [KEY_SPACE], "Jump")
	ir.register_action(&"test_dash", [KEY_Q], "Dash")

	_assert(ir.get_action_keycode(&"test_jump") == KEY_SPACE, "InputRouter registers default keycode")
	var rebind_res := ir.rebind_action_key(&"test_jump", KEY_Q, true)
	_assert(bool(rebind_res.get("ok", false)) and rebind_res.get("swapped_with") == &"test_dash", "InputRouter swaps conflicting key binding")
	_assert(ir.get_action_keycode(&"test_jump") == KEY_Q and ir.get_action_keycode(&"test_dash") == KEY_SPACE, "Swapped actions update both keycodes")

	# Reload SettingsStore + InputRouter to verify persistence
	var store2 := SettingsStoreScript.new()
	store2.config_path = tmp_cfg
	store2.load_settings()
	var ir2 := InputRouterScript.new()
	ir2.settings_store = store2
	ir2.register_action(&"test_jump", [KEY_SPACE], "Jump")
	ir2.register_action(&"test_dash", [KEY_Q], "Dash")
	_assert(ir2.get_action_keycode(&"test_jump") == KEY_Q, "Persisted input_bindings survive SettingsStore reload")

	ir2.reset_bindings()
	_assert(ir2.get_action_keycode(&"test_jump") == KEY_SPACE, "InputRouter.reset_bindings restores defaults")

	# GuLog + DevConsole checks
	GuLog.clear()
	GuLog.info("Test", "Structured info entry")
	GuLog.error("Test", "Structured error entry")
	_assert(GuLog.get_entries(GuLog.Level.ERROR).size() == 1, "GuLog filters entries by minimum level")

	var console_autoload := get_root().get_node_or_null("DevConsole")
	_assert(console_autoload != null, "Autoload DevConsole exists on SceneTree root")

	var console := DevConsoleScript.new()
	console.input_router = ir2
	get_root().add_child(console)
	console.register_command("sum", "Add two ints", func(args: Array[String]) -> String:
		return str(int(args[0]) + int(args[1]))
	)
	_assert(console.execute("sum 3 4") == "7", "DevConsole executes custom command")
	console.set_open(true)
	_assert(console.is_open() and not ir2.allow_debug(), "Opening DevConsole pushes MODAL context")
	console.set_open(false)
	_assert(not console.is_open() and ir2.allow_debug(), "Closing DevConsole restores gameplay context")

	console.queue_free()
	ir.free()
	ir2.free()
	store.free()
	store2.free()
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)


func _test_flags_and_quest_tracker() -> void:
	var flags := FlagStore.new()
	var flag_events := [0]
	flags.flag_changed.connect(func(_id: StringName, _old_v: Variant, _new_v: Variant) -> void: flag_events[0] += 1)

	flags.set_flag(&"met_elder", true)
	_assert(flags.get_bool(&"met_elder"), "FlagStore stores boolean flags")
	_assert(flags.inc_counter(&"beacons_lit", 2) == 2, "FlagStore.inc_counter increments integer counters")
	_assert(flag_events[0] == 2, "FlagStore emits flag_changed on mutations")

	var bus := EventBusScript.new()
	var inv := InventoryContainer.new()
	var stats := StatSet.new()
	stats.define_stat(&"xp", 1000.0, 0.0)

	var tracker := QuestTracker.new()
	tracker.bind(bus, flags, inv, stats)

	var loaded_count := tracker.register_from_rows([
		{
			"id": "sector_trial",
			"title": "Sector Trial",
			"objectives": [
				{"id": "beacons", "type": "event", "event": "beacon_lit_changed", "filter": {"lit": true}, "target": 2},
				{"id": "gather_wood", "type": "inventory_count", "item_id": "wood", "target": 3},
				{"id": "flag_ready", "type": "flag", "flag_id": "met_elder", "flag_value": true, "target": 1},
			],
			"rewards": [
				{"type": "item", "id": "coin", "amount": 10},
				{"type": "stat", "id": "xp", "delta": 50.0},
				{"type": "flag", "id": "trial_done", "value": true},
			],
		},
	])
	_assert(loaded_count == 1, "QuestTracker.register_from_rows registers DataTableLoader-style rows")
	_assert(tracker.start_quest(&"sector_trial"), "QuestTracker starts registered quest")

	# Non-matching filter should not advance beacon objective
	bus.emit_event(&"beacon_lit_changed", {"lit": false})
	var st1 := tracker.get_quest_status(&"sector_trial")
	_assert(int((st1["objectives"][0] as Dictionary)["current"]) == 0, "QuestTracker ignores events failing filter")

	# Matching event advances objective
	bus.emit_event(&"beacon_lit_changed", {"lit": true})
	var st2 := tracker.get_quest_status(&"sector_trial")
	_assert(int((st2["objectives"][0] as Dictionary)["current"]) == 1, "QuestTracker advances event objective via EventBus")

	# SaveService round-trip while quest is in progress
	var tmp_dir := "user://test_saves_quests"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	svc.register_saveable("flags", flags)
	svc.register_saveable("quests", tracker)
	var err := svc.save_slot("quest_slot", {"world": {"seed": 77}})
	_assert(err == OK, "SaveService persists FlagStore + QuestTracker saveables")

	var loaded := svc.load_slot("quest_slot")
	_assert(bool(loaded.get("ok", false)), "SaveService loads quest save slot")

	var flags2 := FlagStore.new()
	var inv2 := InventoryContainer.new()
	var stats2 := StatSet.new()
	stats2.define_stat(&"xp", 1000.0, 0.0)
	var tracker2 := QuestTracker.new()
	tracker2.register_from_rows([
		{
			"id": "sector_trial",
			"title": "Sector Trial",
			"objectives": [
				{"id": "beacons", "type": "event", "event": "beacon_lit_changed", "filter": {"lit": true}, "target": 2},
				{"id": "gather_wood", "type": "inventory_count", "item_id": "wood", "target": 3},
				{"id": "flag_ready", "type": "flag", "flag_id": "met_elder", "flag_value": true, "target": 1},
			],
			"rewards": [
				{"type": "item", "id": "coin", "amount": 10},
				{"type": "stat", "id": "xp", "delta": 50.0},
				{"type": "flag", "id": "trial_done", "value": true},
			],
		},
	])
	tracker2.bind(bus, flags2, inv2, stats2)
	flags2.apply_state((loaded["data"] as Dictionary).get("flags", {}) as Dictionary)
	tracker2.apply_state((loaded["data"] as Dictionary).get("quests", {}) as Dictionary)
	var st_restored := tracker2.get_quest_status(&"sector_trial")
	_assert(tracker2.is_active(&"sector_trial") and int((st_restored["objectives"][0] as Dictionary)["current"]) == 1, "Restored QuestTracker keeps partial progress")

	# Finish remaining objectives -> verify completion + rewards
	inv2.add_item(&"wood", 3)
	bus.emit_event(&"beacon_lit_changed", {"lit": true})
	_assert(tracker2.is_completed(&"sector_trial"), "Quest completes once all event + inventory + flag objectives meet target")
	_assert(inv2.count_item(&"coin") == 10, "Quest completion grants item reward to InventoryContainer")
	_assert(is_equal_approx(stats2.get_value(&"xp"), 50.0), "Quest completion grants stat reward to StatSet")
	_assert(flags2.get_bool(&"trial_done"), "Quest completion sets reward flag in FlagStore")

	tracker.unbind()
	tracker2.unbind()
	svc.delete_slot("quest_slot")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()
	bus.free()


func _dialogue_choice_index(view: Dictionary, text: String) -> int:
	var choices: Variant = view.get("choices", [])
	if choices is Array:
		for raw in choices as Array:
			if raw is Dictionary and str((raw as Dictionary).get("text", "")) == text:
				return int((raw as Dictionary).get("index", -1))
	return -1


func _test_dialogue() -> void:
	var broken := DialogueDef.from_dict({
		"id": "bad",
		"start": "a",
		"nodes": [{"id": "a", "next": "missing"}],
	})
	_assert(not broken.is_valid(), "DialogueDef rejects a next target that does not exist")
	var runner := DialogueRunner.new()
	var rejected := runner.start(broken)
	_assert(not bool(rejected.get("ok", true)) and bool(rejected.get("ended", false)), "DialogueRunner refuses an invalid graph")

	var flags := FlagStore.new()
	runner.bind(flags, null, null, null)
	var gated := DialogueDef.from_dict({
		"id": "gate",
		"start": "greet",
		"nodes": [
			{
				"id": "greet",
				"speaker": "Elder",
				"text": "Well?",
				"choices": [
					{
						"text": "You know me.",
						"next": "known",
						"conditions": [{"type": "flag", "id": "met_elder", "op": "eq", "value": true}],
						"effects": [{"type": "inc_flag", "id": "talks", "delta": 1}],
					},
				],
			},
			{"id": "known", "text": "Welcome back."},
		],
	})
	var view := runner.start(gated)
	_assert((view.get("choices", []) as Array).is_empty() and bool(view.get("terminal", false)), "Flag condition hides the only choice")
	flags.set_flag(&"met_elder", true)
	view = runner.start(gated)
	_assert((view.get("choices", []) as Array).size() == 1, "Flag condition reveals the choice")
	view = runner.choose(0)
	_assert(flags.get_int(&"talks") == 1 and String(view.get("node_id", "")) == "known", "Choice effect writes a flag and advances")

	var quests := QuestTracker.new()
	quests.register_quest(QuestDef.from_dict({
		"id": "errand",
		"objectives": [{"id": "wait", "type": "event", "event": "never_happens", "target": 1}],
	}))
	var hire := DialogueRunner.new()
	hire.bind(flags, quests, null, null)
	var hire_def := DialogueDef.from_dict({
		"id": "hire",
		"start": "ask",
		"nodes": [{
			"id": "ask",
			"text": "Help?",
			"choices": [{
				"text": "Yes",
				"effects": [{"type": "start_quest", "id": "errand"}],
			}],
		}],
	})
	view = hire.start(hire_def)
	view = hire.choose(0)
	_assert(bool(view.get("ended", false)) and quests.is_active(&"errand"), "Dialogue start_quest accepts a quest")
	view = hire.start(hire_def)
	view = hire.choose(0)
	_assert(bool(view.get("ok", false)) and bool(view.get("ended", false)) and quests.is_active(&"errand"), "start_quest is a no-op when the quest is already active")

	var short_inv := InventoryContainer.new()
	short_inv.add_item(&"wood", 1)
	var trade := DialogueRunner.new()
	trade.bind(null, null, short_inv, null)
	var trade_def := DialogueDef.from_dict({
		"id": "trade",
		"start": "offer",
		"nodes": [
			{
				"id": "offer",
				"text": "Three wood.",
				"choices": [{
					"text": "Hand them over.",
					"next": "thanks",
					"effects": [{"type": "remove_item", "id": "wood", "amount": 3}],
				}],
			},
			{"id": "thanks", "text": "Good."},
		],
	})
	view = trade.start(trade_def)
	view = trade.choose(0)
	_assert(str(view.get("error", "")) == "missing_item" and String(view.get("node_id", "")) == "offer", "Short inventory keeps the line in place")
	_assert(short_inv.count_item(&"wood") == 1, "Failed remove_item does not change the inventory")

	var tight := InventoryContainer.new(1, 1)
	tight.add_item(&"wood", 1)
	var pack := DialogueRunner.new()
	pack.bind(null, null, tight, null)
	var pack_def := DialogueDef.from_dict({
		"id": "pack",
		"start": "offer",
		"nodes": [
			{
				"id": "offer",
				"text": "Swap?",
				"choices": [{
					"text": "Deal",
					"next": "thanks",
					"effects": [
						{"type": "remove_item", "id": "wood", "amount": 1},
						{"type": "add_item", "id": "ore", "amount": 2},
					],
				}],
			},
			{"id": "thanks", "text": "Done."},
		],
	})
	view = pack.start(pack_def)
	view = pack.choose(0)
	_assert(str(view.get("error", "")) == "inventory_full" and String(view.get("node_id", "")) == "offer", "Full pack keeps the line in place")
	_assert(tight.count_item(&"wood") == 1 and tight.count_item(&"ore") == 0, "Failed exchange rolls back both sides")

	var bus := EventBusScript.new()
	var bag := InventoryContainer.new()
	var story_flags := FlagStore.new()
	var story := QuestTracker.new()
	story.register_quest(WorldSpawner.create_gather_wood_quest())
	story.bind(bus, story_flags, bag)
	var elder := DialogueRunner.new()
	elder.bind(story_flags, story, bag, bus)
	var elder_def := WorldSpawner.create_elder_dialogue()
	_assert(elder_def.is_valid(), "Elder dialogue graph is valid")
	view = elder.start(elder_def)
	var accept := _dialogue_choice_index(view, "I will bring three wood.")
	_assert(accept >= 0 and _dialogue_choice_index(view, "Here is the wood.") == -1, "Delivery stays hidden until the quest is active and stocked")
	view = elder.choose(accept)
	_assert(story.is_active(&"gather_wood") and story_flags.get_bool(&"met_elder"), "Accept choice starts the quest and sets a flag")
	_assert(String(view.get("node_id", "")) == "accepted", "Accept choice advances to the accepted line")

	bag.add_item(&"wood", 2)
	view = elder.start(elder_def)
	_assert(_dialogue_choice_index(view, "Here is the wood.") == -1, "Delivery stays hidden until the player holds 3 wood")
	bag.add_item(&"wood", 1)
	view = elder.start(elder_def)
	var deliver := _dialogue_choice_index(view, "Here is the wood.")
	_assert(deliver >= 0, "Delivery appears once the quest is active and the wood is in hand")
	view = elder.choose(deliver)
	_assert(bag.count_item(&"wood") == 0, "Delivery removes the promised wood")
	_assert(story.is_completed(&"gather_wood"), "Delivery event completes the quest")
	_assert(bag.count_item(&"coin") == 8, "Quest reward grants coins after delivery")
	_assert(story_flags.get_bool(&"elder_paid"), "Quest reward sets the paid flag")
	_assert(String(view.get("node_id", "")) == "paid", "Delivery advances to the paid line")

	view = elder.start(elder_def)
	_assert((view.get("choices", []) as Array).is_empty() and bool(view.get("can_continue", false)), "Completed quest hides choices and offers Continue")
	view = elder.continue_line()
	_assert(String(view.get("node_id", "")) == "done" and bool(view.get("terminal", false)) and not bool(view.get("ended", true)), "Completed branch lands on the closing line")

	var router := get_root().get_node("InputRouter")
	var was_gameplay := bool(router.call("is_gameplay_active"))
	var stack_before := int(router.call("get_stack_size"))
	var host := Node3D.new()
	get_root().add_child(host)
	var box := DialogueBox.new()
	host.add_child(box)
	var box_flags := FlagStore.new()
	box.bind(box_flags, null, null, null)
	var npc := DialogueInteractable.new()
	npc.dialogue = DialogueDef.from_dict({
		"id": "hi",
		"start": "a",
		"nodes": [{
			"id": "a",
			"speaker": "Elder",
			"text": "Hello",
			"effects": [{"type": "set_flag", "id": "spoke", "value": true}],
		}],
	})
	host.add_child(npc)
	_assert(npc.interact(host), "DialogueInteractable accepts an actor")
	_assert(box.is_open() and box_flags.get_bool(&"spoke"), "DialogueInteractable opens DialogueBox and applies the line")
	_assert(not bool(router.call("is_gameplay_active")), "DialogueBox pushes the UI input context")
	var close_btn := box.find_child("CloseButton", true, false) as Button
	_assert(close_btn != null, "Terminal line shows Close")
	if close_btn != null:
		close_btn.pressed.emit()
	_assert(not box.is_open(), "Close dismisses DialogueBox")
	_assert(bool(router.call("is_gameplay_active")) == was_gameplay, "Closing DialogueBox restores the previous gameplay input state")
	_assert(int(router.call("get_stack_size")) == stack_before, "Closing DialogueBox pops its input context")

	story.unbind()
	host.free()
	bus.free()


func _test_save_slots_panel_and_keybind_list() -> void:
	# 1) SaveService slot metadata & SaveSlotsPanel
	var tmp_dir := "user://test_saves_slots_ui"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	svc.delete_slot("alpha")
	svc.delete_slot("beta")
	svc.save_slot("alpha", {"world": {"seed": 1}})
	svc.save_slot("beta", {"world": {"seed": 2}})
	var metas := svc.list_slot_metadata()
	_assert(metas.size() == 2, "SaveService.list_slot_metadata returns all saved slots")
	_assert(bool((metas[0] as Dictionary).get("exists", false)), "Slot metadata marks existing slot")
	_assert(str((metas[0] as Dictionary).get("saved_at_text", "")) != "", "Slot metadata formats timestamp text")

	var mock_world := MockWorld.new()
	get_root().add_child(mock_world)

	var flow := GameFlowScript.new()
	get_root().add_child(flow)
	flow.register_world(mock_world)

	var slots_scene := load("res://addons/gu_core/ui/save_slots_panel.tscn") as PackedScene
	_assert(slots_scene != null, "save_slots_panel.tscn loads cleanly")
	var slots_inst := slots_scene.instantiate() as SaveSlotsPanel
	slots_inst.save_service = svc
	slots_inst.game_flow = flow
	get_root().add_child(slots_inst)
	slots_inst.on_ui_enter({"mode": "load", "allow_save": false})
	_assert(slots_inst.get_mode() == "load" and slots_inst.get_slot_count() == 2, "SaveSlotsPanel populates existing slots in load mode")
	slots_inst.set_mode("save")
	_assert(slots_inst.get_mode() == "load", "SaveSlotsPanel blocks save mode when allow_save=false")

	slots_inst.on_ui_enter({"mode": "save", "allow_save": true})
	_assert(slots_inst.get_mode() == "save", "SaveSlotsPanel enables save mode when allow_save=true")
	_assert(slots_inst.delete_slot_confirmed("alpha") == OK and slots_inst.get_slot_count() == 1, "SaveSlotsPanel.delete_slot_confirmed deletes slot and refreshes list")
	slots_inst.free()

	# Verify GameFlow.open_save_slots auto-registers & opens screen on UIRouter
	var gf_aut := get_root().get_node_or_null("GameFlow")
	var ui_aut := get_root().get_node_or_null("UIRouter")
	if gf_aut != null and ui_aut != null:
		gf_aut.call("open_save_slots", "load")
		_assert(ui_aut.call("top_screen_id") == &"save_slots", "GameFlow.open_save_slots pushes save_slots onto UIRouter")
		ui_aut.call("clear_screens")

	svc.delete_slot("alpha")
	svc.delete_slot("beta")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	flow.queue_free()
	mock_world.queue_free()
	svc.free()

	# 2) KeybindList dynamic rows + capture/cancel/swap + SettingsPanel tabs
	var tmp_cfg := "user://test_keybind_ui.cfg"
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)
	var store := SettingsStoreScript.new()
	store.config_path = tmp_cfg
	store.load_settings()

	var ir := InputRouterScript.new()
	ir.settings_store = store
	ir.register_action(&"ui_act_a", [KEY_J], "Action A")
	ir.register_action(&"ui_act_b", [KEY_K], "Action B")

	var kb := KeybindList.new()
	kb.input_router = ir
	get_root().add_child(kb)
	_assert(kb.get_action_count() == 2, "KeybindList builds one row per registered action")
	_assert(kb.get_button_text(&"ui_act_a") == "J", "KeybindList renders current key label")

	kb.begin_listen(&"ui_act_a")
	_assert(kb.is_listening() and not ir.allow_debug(), "KeybindList.begin_listen pushes MODAL context")
	var esc_res := kb.capture_key_event(&"ui_act_a", KEY_ESCAPE)
	_assert(bool(esc_res.get("cancelled", false)) and not kb.is_listening() and ir.allow_debug(), "KEY_ESCAPE cancels key capture and restores context")
	_assert(kb.get_button_text(&"ui_act_a") == "J", "Cancelled capture preserves previous key label")

	var swap_res := kb.capture_key_event(&"ui_act_a", KEY_K)
	_assert(bool(swap_res.get("ok", false)), "KeybindList.capture_key_event rebinds and swaps conflicts")
	_assert(kb.get_button_text(&"ui_act_a") == "K" and kb.get_button_text(&"ui_act_b") == "J", "KeybindList refreshes both swapped button labels")

	kb.reset_all()
	_assert(kb.get_button_text(&"ui_act_a") == "J" and kb.get_button_text(&"ui_act_b") == "K", "KeybindList.reset_all restores default labels")

	kb.free()
	ir.free()
	store.free()
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)

	# Verify SettingsPanel tab toggle and locale options from the shared catalog.
	var lang_store := get_root().get_node_or_null("SettingsStore")
	var spawned_store: Node = null
	if lang_store == null:
		spawned_store = SettingsStoreScript.new()
		spawned_store.name = "SettingsStore"
		spawned_store.config_path = "user://test_settings_panel_locale.cfg"
		spawned_store.translation_dir = "res://data"
		get_root().add_child(spawned_store)
		lang_store = spawned_store
	var sp_packed := load("res://scenes/ui/settings_panel.tscn") as PackedScene
	var sp_inst := sp_packed.instantiate() as Control
	get_root().add_child(sp_inst)
	sp_inst.call("show_tab", "controls")
	var sys_sec := sp_inst.get_node_or_null("%SystemSection") as Control
	var ctrl_sec := sp_inst.get_node_or_null("%ControlsSection") as Control
	_assert(sys_sec != null and not sys_sec.visible and ctrl_sec != null and ctrl_sec.visible, "SettingsPanel switches between System and Controls tabs")
	var lang := sp_inst.get_node_or_null("%LanguageOption") as OptionButton
	var locale_count := 0
	if lang_store != null:
		var locales: Variant = lang_store.call("get_locales")
		if locales is PackedStringArray or locales is Array:
			locale_count = locales.size()
	_assert(lang != null and locale_count > 0 and lang.item_count == locale_count, "SettingsPanel language options match SettingsStore locales")
	var zh_index := -1
	for i in lang.item_count:
		if lang.get_item_text(i) == "中文":
			zh_index = i
	_assert(zh_index >= 0, "SettingsPanel lists 中文")
	var prev_ui_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	var title := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate()
	get_root().add_child(title)
	_assert((title.get_node("%ContinueButton") as Button).text == "继续", "Title screen switches to Chinese")
	get_root().remove_child(title)
	title.free()
	TranslationServer.set_locale(prev_ui_locale)
	get_root().remove_child(sp_inst)
	sp_inst.free()
	if spawned_store != null:
		get_root().remove_child(spawned_store)
		spawned_store.free()
		if FileAccess.file_exists("user://test_settings_panel_locale.cfg"):
			DirAccess.remove_absolute("user://test_settings_panel_locale.cfg")


class MockCollector extends Node3D:
	var inventory: InventoryContainer = null

	func get_inventory() -> InventoryContainer:
		return inventory


func _test_world_entity_primitives() -> void:
	# 1) HealthComponent damage, invuln window, heal, death, revive
	var hc := HealthComponent.new()
	hc.max_hp = 50.0
	hc.invuln_time = 0.25
	get_root().add_child(hc)
	var died_hits := [0]
	hc.died.connect(func(_src: Node) -> void: died_hits[0] += 1)

	_assert(is_equal_approx(hc.apply_damage(20.0), 20.0), "HealthComponent applies initial damage")
	_assert(is_equal_approx(hc.apply_damage(10.0), 0.0), "HealthComponent blocks damage during invuln window")
	hc._process(0.30)
	_assert(is_equal_approx(hc.heal(10.0), 10.0) and is_equal_approx(hc.get_hp(), 40.0), "HealthComponent heals after invuln expires")
	hc.apply_damage(99.0)
	_assert(hc.is_dead() and died_hits[0] == 1, "HealthComponent emits died once when HP hits zero")
	_assert(is_equal_approx(hc.heal(10.0), 0.0), "HealthComponent ignores heal while dead")
	hc.revive(true)
	_assert(not hc.is_dead() and is_equal_approx(hc.get_hp(), 50.0), "HealthComponent.revive restores alive state and max HP")
	get_root().remove_child(hc)
	hc.free()

	# 2) WorldPickup magnet, InventoryContainer overflow, EventBus, PoolService
	var host := Node3D.new()
	get_root().add_child(host)

	var bus := EventBusScript.new()
	var picked_events: Array[Dictionary] = []
	bus.subscribe(&"item_picked_up", func(p: Dictionary) -> void: picked_events.append(p))

	var pool := PoolServiceScript.new()
	get_root().add_child(pool)

	var pickup_packed := PackedScene.new()
	var tpl_pickup := WorldPickup.new()
	pickup_packed.pack(tpl_pickup)
	tpl_pickup.free()
	pool.prewarm(pickup_packed, 2)

	var collector := MockCollector.new()
	collector.inventory = InventoryContainer.new(1, 3) # max 3 items total
	collector.add_to_group(WorldPickup.COLLECTOR_GROUP)
	collector.position = Vector3.ZERO
	host.add_child(collector)

	var drop := pool.acquire(pickup_packed, host) as WorldPickup
	drop.event_bus = bus
	drop.pool_service = pool
	drop.position = Vector3(2.2, 0.0, 0.0)
	drop.configure(&"ore", 5, Color(0.4, 0.8, 1.0))

	# Magnet slides pickup closer, collects 3, leaves 2 behind because inventory is full
	for _i in 6:
		drop.step_pickup(0.1)
	_assert(collector.inventory.count_item(&"ore") == 3, "WorldPickup collects up to InventoryContainer capacity")
	_assert(drop.amount == 2 and not drop.is_collected(), "WorldPickup retains uncollected leftover when inventory full")
	_assert(picked_events.size() == 1 and int(picked_events[0]["amount"]) == 3, "WorldPickup emits EventBus item_picked_up")

	# Expand inventory slots and finish collecting -> recycles back into PoolService
	collector.inventory.max_slots = 2
	drop.step_pickup(0.1)
	_assert(collector.inventory.count_item(&"ore") == 5, "WorldPickup delivers remaining items once space opens")
	_assert(drop.is_collected() and drop.get_parent() == pool, "WorldPickup recycles into PoolService after full collection")
	var pstats := pool.get_pool_stats(pickup_packed)
	_assert(int(pstats["available"]) == 2 and int(pstats["active"]) == 0, "PoolService restores available count after pickup release")

	# 3) ResourceNode harvest -> deplete -> drop -> respawn -> SaveService round-trip
	var rnode := ResourceNode.new()
	rnode.event_bus = bus
	rnode.pool_service = pool
	rnode.pickup_scene = pickup_packed
	rnode.respawn_time = 2.0
	host.add_child(rnode)
	rnode.configure("ore_test", &"ore", &"mine", [{"item_id": "ore", "min": 2, "max": 2, "chance": 1.0}], 20.0, 10.0)

	_assert(is_equal_approx(rnode.apply_harvest_hit(collector), 10.0), "ResourceNode takes first harvest hit")
	_assert(not rnode.is_depleted(), "ResourceNode stays active while HP > 0")
	rnode.apply_harvest_hit(collector)
	_assert(rnode.is_depleted() and not rnode.can_interact(collector), "ResourceNode depletes and disables interaction at 0 HP")

	var spawned_pickups := 0
	for ch in host.get_children():
		if ch is WorldPickup:
			spawned_pickups += 1
	_assert(spawned_pickups >= 1, "Depleted ResourceNode spawns WorldPickup drop(s)")

	var saved_state := rnode.export_state()
	_assert(bool(saved_state.get("depleted", false)), "ResourceNode.export_state captures depleted state")

	rnode._process(2.5)
	_assert(not rnode.is_depleted() and is_equal_approx(rnode.get_health().get_hp(), 20.0), "ResourceNode respawns after respawn_time elapses")

	rnode.apply_state(saved_state)
	_assert(rnode.is_depleted() and not rnode.can_interact(collector), "ResourceNode.apply_state restores depleted state")

	pool.clear_pool(pickup_packed)
	pool.queue_free()
	bus.free()
	host.free()


func _test_gameplay_hud() -> void:
	var stats := StatSet.new()
	stats.define_stat(&"stamina", 100.0, 80.0)
	var bar := StatBar.new()
	bar.bind_stat(stats, &"stamina", "Stamina")
	_assert(bar.get_value_text() == "80 / 100", "StatBar shows current and max")
	_assert(is_equal_approx(bar.get_displayed_ratio(), 0.8), "StatBar ratio tracks StatSet")
	stats.set_value(&"stamina", 25.0)
	_assert(bar.get_value_text() == "25 / 100" and is_equal_approx(bar.get_displayed_ratio(), 0.25), "StatBar updates on stat_changed")
	bar.unbind()
	stats.set_value(&"stamina", 10.0)
	_assert(bar.get_value_text() == "25 / 100", "StatBar ignores changes after unbind")
	bar.free()

	var health := HealthComponent.new()
	health.max_hp = 40.0
	var health_bar := StatBar.new()
	health_bar.bind_health(health, "Health")
	_assert(health_bar.get_value_text() == "40 / 40", "StatBar.bind_health reads HealthComponent")
	health.apply_damage(15.0)
	_assert(health_bar.get_value_text() == "25 / 40" and is_equal_approx(health_bar.get_displayed_ratio(), 25.0 / 40.0), "StatBar follows health damage")
	health_bar.free()
	health.free()

	var router := get_root().get_node_or_null("InputRouter")
	_assert(router != null, "InputRouter autoload available for inventory HUD")
	var stack_before := int(router.call("get_stack_size")) if router != null else 0
	var panel := InventoryPanel.new()
	get_root().add_child(panel)
	var inv := InventoryContainer.new(4, 99)
	panel.bind_inventory(inv)
	inv.add_item(&"ore", 3)
	var rows := panel.get_row_texts()
	_assert(rows.size() == 1 and rows[0] == "Ore x3", "InventoryPanel renders occupied slot rows")
	_assert(_find_label_prefix(panel, "Empty slots") == "Empty slots: 3", "InventoryPanel counts empty slots from max_slots")
	panel.set_open(true)
	_assert(panel.is_open() and router != null and int(router.call("get_active_context")) == 1, "InventoryPanel open pushes UI context")
	panel.toggle()
	_assert(not panel.is_open() and router != null and int(router.call("get_stack_size")) == stack_before, "InventoryPanel close pops UI context")

	var dropped: Array = []
	panel.drop_requested.connect(func(item_id: StringName, amount: int) -> void: dropped.append([item_id, amount]))
	var drop_btn: Button = null
	for node in panel.find_children("*", "Button", true, false):
		drop_btn = node as Button
		break
	_assert(drop_btn != null, "InventoryPanel row exposes a drop button")
	if drop_btn != null:
		drop_btn.pressed.emit()
	_assert(dropped.size() == 1 and String(dropped[0][0]) == "ore" and int(dropped[0][1]) == 1, "InventoryPanel drop requests one item")
	_assert(inv.count_item(&"ore") == 2, "InventoryPanel drop removes one item")
	var ui := get_root().get_node_or_null("UIRouter")
	if ui != null and ui.has_method("clear_toasts"):
		ui.call("clear_toasts")
	if panel.is_open():
		panel.set_open(false)
	get_root().remove_child(panel)
	panel.free()

	var tracker := QuestTracker.new()
	var quests := QuestHud.new()
	get_root().add_child(quests)
	quests.bind_tracker(tracker)
	tracker.register_quest(QuestDef.from_dict({
		"id": "activate_beacons",
		"title": "Link Beacons",
		"objectives": [{
			"id": "lit",
			"type": "event",
			"event": "beacon_lit_changed",
			"description": "Light beacons",
			"target": 3,
		}],
	}))
	tracker.start_quest(&"activate_beacons")
	var quest_text := "\n".join(quests.get_row_texts())
	_assert("Link Beacons" in quest_text and "Light beacons 0/3" in quest_text, "QuestHud shows active objective")
	tracker.handle_event(&"beacon_lit_changed", {})
	quest_text = "\n".join(quests.get_row_texts())
	_assert("Light beacons 1/3" in quest_text, "QuestHud updates objective progress")
	tracker.handle_event(&"beacon_lit_changed", {})
	tracker.handle_event(&"beacon_lit_changed", {})
	quest_text = "\n".join(quests.get_row_texts())
	_assert("COMPLETE" in quest_text, "QuestHud shows completion text")
	quests.acknowledge_completion(&"activate_beacons")
	_assert(not ("COMPLETE" in "\n".join(quests.get_row_texts())), "QuestHud.acknowledge_completion clears the completed row")
	tracker.unbind()
	get_root().remove_child(quests)
	quests.free()

	var hud_stats := StatSet.new()
	hud_stats.define_stat(&"stamina", 100.0)
	var hud_inv := InventoryContainer.new(2, 99)
	var hud_tracker := QuestTracker.new()
	var hud := GameplayHud.new()
	get_root().add_child(hud)
	hud.bind_player_hud(hud_stats, &"stamina", hud_inv, hud_tracker, "Stamina")
	_assert(hud.stats_root.get_child_count() == 1, "GameplayHud hosts a stat bar")
	_assert(hud.inventory != null and not hud.inventory.is_open(), "GameplayHud inventory starts closed")
	_assert(hud.quests != null, "GameplayHud hosts the quest tracker")
	get_root().remove_child(hud)
	hud.free()


func _test_loading_and_shader_warmup() -> void:
	var ui := get_root().get_node_or_null("UIRouter")
	_assert(ui != null, "UIRouter autoload is available for loading progress")
	if ui == null:
		return
	ui.call("set_loading_progress", 0.0)
	_assert(is_equal_approx(float(ui.call("get_loading_progress")), 0.0), "Loading progress starts at 0")
	ui.call("set_loading_progress", 1.0)
	_assert(is_equal_approx(float(ui.call("get_loading_progress")), 1.0), "Loading progress reaches 1")
	ui.call("hide_loading")

	var warmup := ShaderWarmupScript.new()
	get_root().add_child(warmup)
	_assert(not warmup.is_queued_for_deletion(), "Shader warmup stays for the frame it is added")
	warmup._process(0.016)
	_assert(warmup.warmed and warmup.is_queued_for_deletion(), "Shader warmup leaves the tree after one process step")


func _test_status_cooldown_and_tags() -> void:
	var tags := GameplayTagsScript.new()
	tags.add(&"State.Stunned")
	_assert(tags.has(&"State") and tags.has(&"State.Stunned"), "GameplayTags treats State.Stunned as State")
	_assert(not tags.has(&"State.Burning"), "GameplayTags does not match a sibling tag")

	var stats := StatSet.new()
	stats.define_stat(&"speed", 10.0)
	var status := StatusControllerScript.new()
	status.stats = stats
	status.apply_status(&"haste", {"duration": 1.0, "stat_id": &"speed", "mult": 1.3, "tags": ["State.Haste"]})
	_assert(is_equal_approx(stats.get_max(&"speed"), 13.0), "Haste raises the speed maximum by 30 percent")
	_assert(status.tags.has(&"State"), "Haste grants the State tag family")
	status.advance(1.1)
	_assert(not status.has_status(&"haste"), "Haste expires after its duration")
	_assert(is_equal_approx(stats.get_max(&"speed"), 10.0), "Expired haste restores the original speed maximum")
	_assert(not status.tags.has(&"State.Haste"), "Expired haste removes its tag")

	var health := HealthComponent.new()
	health.max_hp = 20.0
	status.health = health
	status.apply_status(&"poison", {"duration": 5.0, "tick_interval": 1.0, "damage_per_tick": 5.0})
	status.advance(1.0)
	_assert(is_equal_approx(health.get_hp(), 15.0), "Poison tick damages health")

	var cooldowns := CooldownTrackerScript.new()
	_assert(cooldowns.try_start(&"mine", 1.0), "Cooldown accepts the first use")
	_assert(not cooldowns.try_start(&"mine", 1.0), "Cooldown rejects a second use while active")
	cooldowns.advance(1.0)
	_assert(cooldowns.try_start(&"mine", 0.5), "Cooldown allows the action after it elapses")
	status.free()


func _test_hitbox_and_juice() -> void:
	var health := HealthComponent.new()
	health.max_hp = 100.0
	health.invuln_time = 10.0
	var hurt := HurtboxScript.new()
	hurt.health = health
	hurt.faction = &"player"
	get_root().add_child(hurt)
	var hit := HitboxScript.new()
	hit.faction = &"enemy"
	hit.damage = 10.0
	get_root().add_child(hit)
	var camera := CameraRig.new()
	var juice := JuiceBusScript.new()
	juice.camera = camera
	get_root().add_child(juice)

	var applied := hit.strike(hurt, false, Vector3.FORWARD)
	_assert(is_equal_approx(applied, 10.0), "Hitbox damages a hostile hurtbox")
	_assert(juice.floater_count == 1 and is_equal_approx(juice.last_amount, 10.0), "Juice bus records one floater for the hit")
	_assert(camera.get_shake_remaining() > 0.0, "Juice bus shakes the camera")
	var clock := get_root().get_node_or_null("GameClock")
	_assert(clock != null and is_equal_approx(float(clock.call("get_scale")), 0.2), "Juice bus applies a short hitstop")
	_assert(is_equal_approx(Engine.time_scale, 1.0), "Hitstop leaves Engine.time_scale unchanged")
	var blocked := hit.strike(hurt, false, Vector3.FORWARD)
	_assert(is_equal_approx(blocked, 0.0), "Invulnerability frames ignore the second hit")
	juice.advance(1.0)
	_assert(clock != null and is_equal_approx(float(clock.call("get_scale")), 1.0), "Hitstop restores gameplay scale")

	var ally := HurtboxScript.new()
	ally.health = HealthComponent.new()
	ally.health.max_hp = 50.0
	ally.faction = &"enemy"
	get_root().add_child(ally)
	_assert(is_equal_approx(hit.strike(ally, false, Vector3.FORWARD), 0.0), "Same-faction hits are ignored")

	if clock != null:
		clock.call("pop_scale", &"hitstop")
	juice.queue_free()
	hurt.queue_free()
	hit.queue_free()
	ally.queue_free()


func _test_game_clock() -> void:
	var clock := get_root().get_node_or_null("GameClock")
	_assert(clock != null, "Autoload GameClock exists")
	if clock == null:
		return
	clock.call("pop_scale", &"hitstop")
	clock.call("reset_world_time")
	clock.call("set_gameplay_running", false)
	_assert(is_equal_approx(float(clock.call("gameplay_delta", 0.5)), 0.0), "Paused gameplay delta is zero")
	_assert(is_equal_approx(float(clock.call("ui_delta", 0.5)), 0.5), "UI delta ignores pause")

	clock.call("set_gameplay_running", true)
	clock.call("push_scale", &"hitstop", 0.2)
	_assert(is_equal_approx(float(clock.call("get_scale")), 0.2), "Hitstop scale is 0.2")
	_assert(is_equal_approx(float(clock.call("gameplay_delta", 1.0)), 0.2), "Hitstop scales gameplay delta")
	_assert(is_equal_approx(Engine.time_scale, 1.0), "Hitstop does not change Engine.time_scale")

	_clock_timer_fired = false
	var timer_id := int(clock.call("after_gameplay", 0.5, Callable(self, "_on_game_clock_timer")))
	clock.call("advance_frame", 1.0)
	_assert(timer_id > 0 and not _clock_timer_fired, "Gameplay timer waits for scaled time")
	clock.call("pop_scale", &"hitstop")
	clock.call("advance_frame", 0.5)
	_assert(_clock_timer_fired, "Gameplay timer fires after scaled time elapses")

	var exported: Dictionary = clock.call("export_state") as Dictionary
	var saved_seconds := float(exported.get("world_seconds", -1.0))
	_assert(is_equal_approx(saved_seconds, 0.7), "World seconds accumulate scaled gameplay time")

	var saves := get_root().get_node_or_null("SaveService")
	_assert(saves != null, "SaveService is available for the clock roundtrip")
	if saves != null:
		var err := int(saves.call("save_slot", "clock_slot", {"world": {"seed": 1}}))
		_assert(err == OK, "Clock section saves with the slot")
		clock.call("reset_world_time")
		var loaded: Dictionary = saves.call("load_slot", "clock_slot") as Dictionary
		_assert(bool(loaded.get("ok", false)), "Clock slot loads")
		saves.call("apply_saveables", loaded.get("data", {}))
		var restored: Dictionary = clock.call("export_state") as Dictionary
		_assert(is_equal_approx(float(restored.get("world_seconds", -1.0)), saved_seconds), "Save restores world_seconds")
		saves.call("delete_slot", "clock_slot")

	var flow := get_root().get_node_or_null("GameFlow")
	if flow != null:
		flow.call("start_new_game", {"seed": 1})
		var cleared: Dictionary = clock.call("export_state") as Dictionary
		_assert(is_equal_approx(float(cleared.get("world_seconds", -1.0)), 0.0), "New game resets world time")
	clock.call("set_gameplay_running", false)
	clock.call("pop_scale", &"hitstop")


func _test_input_glyphs_focus_tooltip_coach() -> void:
	var router := InputRouterScript.new()
	router.register_action(&"interact", [KEY_E], "Interact")
	_assert(router.glyph_name(&"interact") == "E", "Keyboard glyph uses the bound key label")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	router.note_input_event(pad)
	_assert(router.glyph_name(&"interact") == "A", "Joypad input switches the interact glyph to A")

	var ui := UIRouterScript.new()
	get_root().add_child(ui)
	var button := Button.new()
	button.name = "RememberedButton"
	get_root().add_child(button)
	button.grab_focus()
	var packed := PackedScene.new()
	var probe := Control.new()
	packed.pack(probe)
	probe.free()
	ui.register_screen(&"focus_probe", packed)
	ui.push_screen(&"focus_probe")
	ui.pop_screen()
	_assert(get_root().gui_get_focus_owner() == button, "Closing a screen restores the previous focus")
	button.queue_free()
	ui.queue_free()

	var tip := TooltipFrameScript.new()
	tip.request("Wood", Rect2(1200, 10, 40, 20), Vector2(1280, 720))
	tip.advance(0.05)
	_assert(not tip.shown, "Tooltip waits out its delay")
	tip.advance(0.2)
	_assert(tip.shown and tip.position.x < 1200.0, "Tooltip flips inward at the right edge")

	var flags := FlagStore.new()
	_assert(CoachMarksScript.try_show(flags, &"first_pickup"), "Coach mark shows the first time")
	_assert(not CoachMarksScript.try_show(flags, &"first_pickup"), "Coach mark does not repeat for the same flag")


func _test_bug_report_and_platform() -> void:
	GuLog.info("bug", "pack-test")
	var console := get_root().get_node_or_null("DevConsole")
	_assert(console != null, "DevConsole autoload can write a bug pack")
	if console != null:
		var clock := get_root().get_node_or_null("GameClock")
		if clock != null:
			clock.call("apply_state", {"world_seconds": 12.5})
		var written := str(console.call("write_bug_report", "user://bug_reports/unit", Vector3(1, 2, 3)))
		_assert(FileAccess.file_exists(written.path_join("log.txt")), "Bug pack contains the log")
		_assert(FileAccess.file_exists(written.path_join("screenshot.png")), "Bug pack contains a screenshot")
		_assert(FileAccess.file_exists(written.path_join("save.json")), "Bug pack contains a save copy")
		var position_text := FileAccess.get_file_as_string(written.path_join("position.json"))
		_assert("1" in position_text and "2" in position_text and "3" in position_text, "Bug pack records the player position")
		_assert("world_seconds" in position_text and "12.5" in position_text, "Bug pack records world time")
		if clock != null:
			clock.call("reset_world_time")

	var platform := get_root().get_node_or_null("PlatformService")
	_assert(platform != null, "PlatformService autoload is registered")
	if platform != null:
		platform.call("unlock_achievement", "test_foundation_badge")
		_assert(bool(platform.call("has_achievement", "test_foundation_badge")), "Mock platform records an achievement")
		var raw := FileAccess.get_file_as_string("user://platform_mock.json")
		_assert("test_foundation_badge" in raw, "Mock platform writes the achievement JSON")


func _test_ai_perception() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	var agent := AiAgentScript.new()
	agent.tick(0.1, origin, forward, Vector3(0, 0, -20), true)
	_assert(agent.mode == AiAgentScript.Mode.PATROL, "A distant target leaves the agent on patrol")
	var chase: Vector3 = agent.tick(0.1, origin, forward, Vector3(0, 0, -3), true)
	_assert(agent.mode == AiAgentScript.Mode.CHASE and chase.length() > 0.1, "A target inside the cone starts a chase")
	agent.tick(0.2, origin, forward, Vector3(0, 0, -3), false)
	_assert(agent.mode == AiAgentScript.Mode.LEASH, "Losing the target starts the leash timer")
	agent.tick(1.0, origin, forward, Vector3(0, 0, -3), false)
	_assert(agent.mode == AiAgentScript.Mode.PATROL, "The agent returns to patrol after the leash timeout")
	_assert(AiPerceptionScript.hears(origin, Vector3(1, 0, 0), 4.0), "Hearing range includes a nearby noise")
	agent.tick(0.1, origin, forward, Vector3(0, 0, -3), false, Vector3(1, 0, 0))
	_assert(agent.blackboard.has_value(&"heard_position"), "A heard noise is written to the blackboard")


func _test_summit_star_clarity() -> void:
	var shore := float(SkyTimeScript.altitude_clarity(1.1, 0.95, 11.0))
	var ridge := float(SkyTimeScript.altitude_clarity(5.0, 0.95, 11.0))
	var summit := float(SkyTimeScript.altitude_clarity(10.4, 0.95, 11.0))
	_assert(shore < 0.05, "Night sky stays dim near the shore")
	_assert(ridge > shore and ridge < summit, "Star clarity rises from the ridge toward the summit")
	_assert(summit > 0.95, "A summit night is clear enough to see the stars")
	var shader := load("res://shaders/sky_weather.gdshader") as Shader
	_assert(shader != null and shader.code.contains("altitude_clarity"), "Sky shader exposes summit star clarity")


func _test_play_smoke() -> void:
	var flow := get_root().get_node_or_null("GameFlow")
	var saves := get_root().get_node_or_null("SaveService")
	_assert(flow != null and saves != null, "Play smoke can use GameFlow and SaveService")
	if flow == null or saves == null:
		return
	var world := MockWorld.new()
	get_root().add_child(world)
	flow.call("register_world", world)
	_assert(flow.call("get_world") == world, "Play smoke registers the world")
	flow.call("start_new_game", {"seed": 7})
	_assert(int(flow.call("get_state")) == GameFlowScript.State.PLAYING, "Play smoke reaches PLAYING")
	_assert(world.started_count >= 1, "Play smoke starts a new world")
	var save_err := int(flow.call("save_current_game", "play_smoke"))
	_assert(save_err == OK, "Play smoke writes a save")
	world.applied_doc = {}
	var loaded := bool(flow.call("load_game", "play_smoke"))
	_assert(loaded, "Play smoke loads the save")
	var applied := world.applied_doc
	var world_doc: Dictionary = applied.get("world", {}) as Dictionary
	_assert(int(world_doc.get("seed", -1)) == 777, "Play smoke restores the saved world seed")
	saves.call("delete_slot", "play_smoke")
	world.queue_free()
	if _failures.is_empty():
		_quit_through_flow = true


func _find_label_prefix(root: Node, prefix: String) -> String:
	for node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text.begins_with(prefix):
			return label.text
	return ""
