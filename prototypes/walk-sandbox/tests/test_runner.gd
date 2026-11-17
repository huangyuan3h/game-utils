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
const LandPropsMesh = preload("res://scripts/terrain/land_props_mesh.gd")
const WorldBeaconScript = preload("res://scripts/world/world_beacon.gd")

const InputRouterScript = preload("res://addons/gu_core/input/input_router.gd")
const SettingsStoreScript = preload("res://addons/gu_core/settings/settings_store.gd")
const AudioManagerScript = preload("res://addons/gu_core/audio/audio_manager.gd")
const SaveServiceScript = preload("res://addons/gu_core/save/save_service.gd")
const UIRouterScript = preload("res://addons/gu_core/ui/ui_router.gd")
const GameFlowScript = preload("res://addons/gu_core/flow/game_flow.gd")
const EventBusScript = preload("res://addons/gu_core/events/event_bus.gd")

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


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_all()
	if _failures.is_empty():
		print("[PASS] All %d Phase 1 + Phase 2 + Phase 3 assertions passed." % _passed)
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
	_test_character_locomotion()
	_test_character_climbing()
	_test_input_router()
	_test_settings_store()
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
	_assert(lpm._near_clear_spot(spawn.x, spawn.z, 2.8), "LandPropsMesh respects dynamic clear_spots for spawn")
	if not pois.is_empty():
		var p0 := pois[0]["position"] as Vector3
		_assert(lpm._near_clear_spot(p0.x, p0.z, 2.8), "LandPropsMesh respects dynamic clear_spots for POIs")
	props_root.free()


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
	_assert(loco.speed_3d <= CharacterLocomotion.CLIMB_SPEED + 0.35, "3D climb speed is regulated near CLIMB_SPEED")

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

	var ui := get_root().get_node_or_null("UIRouter")
	_assert(ui != null, "UIRouter autoload available for theme check")
	if ui != null:
		var stack_root := ui.get_node_or_null("UIRouterLayer/ScreenStack") as Control
		_assert(stack_root != null and stack_root.theme != null, "UIRouter ScreenStack has active Theme attached")

	var screen_paths := [
		"res://scenes/ui/title_screen.tscn",
		"res://scenes/ui/pause_menu.tscn",
		"res://scenes/ui/settings_panel.tscn",
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
