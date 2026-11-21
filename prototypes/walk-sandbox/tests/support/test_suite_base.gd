extends RefCounted
## Shared fixtures for the headless test suites. The runner owns the SceneTree and counters.

## Suite handle back to the SceneTree runner (assertions and root access go through it).
var t: SceneTree = null




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

	func is_open_water(_x: float, _z: float) -> bool:
		return biome == MapTypes.Biome.SEA or biome == MapTypes.Biome.LAKE


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


class MockPoolItem extends Node3D:
	var acquired_count: int = 0
	var released_count: int = 0

	func on_pool_acquire() -> void:
		acquired_count += 1

	func on_pool_release() -> void:
		released_count += 1


class MockCollector extends Node3D:
	var inventory: InventoryContainer = null

	func get_inventory() -> InventoryContainer:
		return inventory

## Gameplay timer flag used by the GameClock suite.
var _clock_timer_fired: bool = false
## Quit request proxied to the runner so the play smoke can exit through GameFlow.
var _quit_through_flow: bool:
	get:
		return bool(t.get("_quit_through_flow"))
	set(value):
		t.set("_quit_through_flow", value)
## SceneTree.paused accessor so suite bodies can read and write tree pause state.
var paused: bool:
	get:
		return t.paused
	set(value):
		t.paused = value


func _assert(cond: bool, msg: String) -> void:
	t.call("record_assert", cond, msg)


func get_root() -> Window:
	return t.root


func _on_game_clock_timer() -> void:
	_clock_timer_fired = true


func _wipe_user_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in DirAccess.get_files_at(path):
		dir.remove(String(name))
	DirAccess.remove_absolute(path)


func _dialogue_choice_index(view: Dictionary, text: String) -> int:
	var choices: Variant = view.get("choices", [])
	if choices is Array:
		for raw in choices as Array:
			if raw is Dictionary and str((raw as Dictionary).get("text", "")) == text:
				return int((raw as Dictionary).get("index", -1))
	return -1


func _find_label_prefix(root: Node, prefix: String) -> String:
	for node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text.begins_with(prefix):
			return label.text
	return ""
