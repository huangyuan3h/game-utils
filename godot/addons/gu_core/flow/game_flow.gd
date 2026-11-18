extends Node
## Top-level game flow state machine coordinating world lifecycle, pause, save/load, and UIRouter.

signal state_changed(prev_state: int, new_state: int)
signal world_registered(world: Node)

enum State { BOOT, TITLE, LOADING, PLAYING, PAUSED }

var state: State = State.BOOT
var title_screen_id: StringName = &"title"
var pause_screen_id: StringName = &"pause"
var settings_screen_id: StringName = &"settings"
var save_slots_screen_id: StringName = &"save_slots"
var default_save_slot: String = "autosave"

const DEFAULT_SAVE_SLOTS_SCENE_PATH := "res://addons/gu_core/ui/save_slots_panel.tscn"

var _world: Node = null
var _quitting: bool = false
var _scene_loader: SceneLoader = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree() != null:
		get_tree().auto_accept_quit = false
	_ensure_scene_loader()
	_ensure_cancel_action()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


func register_world(world: Node) -> void:
	_world = world
	world_registered.emit(world)


func get_world() -> Node:
	return _world


func get_state() -> State:
	return state


func enter_title() -> void:
	_set_tree_paused(false)
	_set_state(State.TITLE)
	var ui := _ui_router()
	if ui != null:
		ui.call("clear_screens")
		if ui.call("has_registered", title_screen_id):
			ui.call("push_screen", title_screen_id, {}, 1)


func start_new_game(opts: Dictionary = {}) -> void:
	_reset_clock()
	_set_tree_paused(false)
	_set_state(State.LOADING)
	var ui := _ui_router()
	if ui != null:
		ui.call("clear_screens")
	if _world != null and _world.has_method("start_new_world"):
		_world.call("start_new_world", opts)
	_set_state(State.PLAYING)


func load_game(slot: String = "") -> bool:
	var target_slot := slot if slot != "" else default_save_slot
	var save_svc := _save_service()
	if save_svc == null:
		return false
	var res: Dictionary = save_svc.call("load_slot", target_slot) as Dictionary
	if not bool(res.get("ok", false)):
		push_warning("GameFlow.load_game failed: %s" % str(res.get("error", "unknown")))
		return false

	_reset_clock()
	_set_tree_paused(false)
	_set_state(State.LOADING)
	var ui := _ui_router()
	if ui != null:
		ui.call("clear_screens")
	var data: Dictionary = res.get("data", {}) as Dictionary
	if _world != null and _world.has_method("apply_save_state"):
		_world.call("apply_save_state", data)
	save_svc.call("apply_saveables", data)
	_set_state(State.PLAYING)
	return true


func save_current_game(slot: String = "") -> Error:
	var target_slot := slot if slot != "" else default_save_slot
	var save_svc := _save_service()
	if save_svc == null:
		return ERR_UNAVAILABLE
	var payload: Dictionary = {}
	if _world != null and _world.has_method("export_save_state"):
		payload = _world.call("export_save_state") as Dictionary
	elif _world == null:
		return ERR_UNAVAILABLE
	return int(save_svc.call("save_slot", target_slot, payload)) as Error


func set_paused(paused: bool) -> void:
	if paused and state != State.PLAYING:
		return
	if not paused and state != State.PAUSED:
		return

	_set_tree_paused(paused)
	var ui := _ui_router()
	if paused:
		_set_state(State.PAUSED)
		if ui != null and ui.call("has_registered", pause_screen_id):
			ui.call("push_screen", pause_screen_id, {}, 1)
	else:
		if ui != null:
			ui.call("clear_screens")
		_set_state(State.PLAYING)


func toggle_pause() -> void:
	if state == State.PLAYING:
		set_paused(true)
	elif state == State.PAUSED:
		set_paused(false)


func open_settings() -> void:
	var ui := _ui_router()
	if ui != null and ui.call("has_registered", settings_screen_id):
		ui.call("push_screen", settings_screen_id, {}, 1)


func open_save_slots(mode: String = "load") -> void:
	var ui := _ui_router()
	if ui == null:
		return
	if not bool(ui.call("has_registered", save_slots_screen_id)) and ResourceLoader.exists(DEFAULT_SAVE_SLOTS_SCENE_PATH):
		var packed := load(DEFAULT_SAVE_SLOTS_SCENE_PATH) as PackedScene
		if packed != null:
			ui.call("register_screen", save_slots_screen_id, packed)
	if bool(ui.call("has_registered", save_slots_screen_id)):
		ui.call("push_screen", save_slots_screen_id, {
			"mode": mode,
			"allow_save": state != State.TITLE,
		}, 1)


func close_top_ui() -> void:
	var ui := _ui_router()
	if ui == null:
		return
	var top := StringName(ui.call("top_screen_id"))
	if state == State.PAUSED and top == pause_screen_id:
		set_paused(false)
	else:
		ui.call("pop_screen")


func return_to_title() -> void:
	enter_title()


func get_scene_loader() -> SceneLoader:
	_ensure_scene_loader()
	return _scene_loader


func load_scene_async(scene_path: String, transition_s: float = 0.25) -> bool:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return false
	_ensure_scene_loader()
	_set_tree_paused(false)
	_set_state(State.LOADING)

	var ui := _ui_router()
	if ui != null:
		ui.call("clear_screens")
		if transition_s > 0.0 and ui.has_method("fade_out"):
			await ui.call("fade_out", transition_s)

	if ui != null and ui.has_method("set_loading_progress"):
		ui.call("set_loading_progress", 0.0)
	var packed := await _scene_loader.load_packed_async(scene_path)
	if ui != null and ui.has_method("hide_loading"):
		ui.call("hide_loading")
	if packed == null:
		if ui != null and transition_s > 0.0 and ui.has_method("fade_in"):
			await ui.call("fade_in", transition_s)
		return false

	var tree := get_tree()
	if tree != null:
		tree.change_scene_to_packed(packed)
	if ui != null and transition_s > 0.0 and ui.has_method("fade_in"):
		await ui.call("fade_in", transition_s)
	return true


func _ensure_scene_loader() -> void:
	if _scene_loader != null and is_instance_valid(_scene_loader):
		return
	_scene_loader = SceneLoader.new()
	_scene_loader.name = "SceneLoader"
	add_child(_scene_loader)
	if not _scene_loader.progress_changed.is_connected(_on_scene_load_progress):
		_scene_loader.progress_changed.connect(_on_scene_load_progress)


func _on_scene_load_progress(_scene_path: String, progress: float) -> void:
	var ui := _ui_router()
	if ui != null and ui.has_method("set_loading_progress"):
		ui.call("set_loading_progress", progress)


func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	var tree := get_tree()
	if tree == null:
		return
	var audio_mgr := get_node_or_null("/root/AudioManager")
	if audio_mgr != null and audio_mgr.has_method("prepare_shutdown"):
		audio_mgr.call("prepare_shutdown")
	# Wait for at least one audio mix buffer (~20-50ms) so AudioServer drains
	# stopped playbacks before SceneTree/ObjectDB teardown.
	if AudioServer.get_driver_name() != "Dummy":
		await tree.create_timer(0.06, true, false, true).timeout
	if is_instance_valid(tree):
		tree.quit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var ui := _ui_router()
	if state == State.PLAYING:
		set_paused(true)
		get_viewport().set_input_as_handled()
	elif state == State.PAUSED:
		close_top_ui()
		get_viewport().set_input_as_handled()
	elif state == State.TITLE and ui != null and int(ui.call("stack_size")) > 1:
		ui.call("pop_screen")
		get_viewport().set_input_as_handled()


func _set_state(next_state: State) -> void:
	if state == next_state:
		return
	var prev := state
	state = next_state
	state_changed.emit(int(prev), int(next_state))
	var clock := _clock()
	if clock != null and clock.has_method("set_gameplay_running"):
		clock.call("set_gameplay_running", next_state == State.PLAYING)


func _set_tree_paused(paused: bool) -> void:
	if get_tree() != null:
		get_tree().paused = paused


func _ui_router() -> Node:
	return get_node_or_null("/root/UIRouter")


func _save_service() -> Node:
	return get_node_or_null("/root/SaveService")


func _clock() -> Node:
	return get_node_or_null("/root/GameClock")


func _reset_clock() -> void:
	var clock := _clock()
	if clock != null and clock.has_method("reset_world_time"):
		clock.call("reset_world_time")


func _ensure_cancel_action() -> void:
	if not InputMap.has_action("ui_cancel"):
		InputMap.add_action("ui_cancel")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	if not InputMap.action_has_event("ui_cancel", ev):
		InputMap.action_add_event("ui_cancel", ev)
