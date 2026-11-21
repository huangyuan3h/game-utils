extends Node3D
## Starter world: playable plane plus a content-driven quest, guide dialogue, HUD, and saves.

const TITLE_SCENE := preload("res://scenes/ui/title_screen.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/settings_panel.tscn")

@onready var _player: GuPlayer = $Player
@onready var _camera_rig: CameraRig = $CameraPivot

var _flags := FlagStore.new()
var _quests := QuestTracker.new()
var _dialogue_box: DialogueBox = null
var _hud: GameplayHud = null
var _guide: DialogueInteractable = null
var _prompt_panel: PanelContainer = null
var _prompt_label: Label = null
var _focused: Interactable = null
var _world_seed: int = 42
var _ticks: int = 0
var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_register_ui_screens()
	if _player != null:
		_spawn_position = _player.global_position
	if _camera_rig != null and _player != null:
		_camera_rig.set_target(_player)
	_register_content()
	_setup_dialogue()
	_setup_guide()
	_setup_hud()
	_setup_prompt()
	_connect_interactor()
	_quests.quest_completed.connect(_on_quest_completed)

	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("register_world", self)
		flow.call("enter_title")


func _exit_tree() -> void:
	_quests.unbind()
	var save_svc := get_node_or_null("/root/SaveService")
	if save_svc != null and save_svc.has_method("unregister_saveable"):
		save_svc.call("unregister_saveable", "flags")
		save_svc.call("unregister_saveable", "quests")


func _process(_delta: float) -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null and int(flow.call("get_state")) == 3:
		_ticks += 1
	_refresh_prompt()


func start_new_world(opts: Dictionary = {}) -> void:
	_world_seed = int(opts.get("seed", 42))
	_ticks = 0
	_flags.clear()
	_quests.apply_state({"active": {}, "completed": []})
	for quest_def in GameContent.quests():
		if quest_def.auto_start:
			_quests.start_quest(quest_def.id)
	_reset_player()
	if _camera_rig != null and _player != null:
		_camera_rig.set_target(_player)
	var ui := get_node_or_null("/root/UIRouter")
	if ui != null and ui.has_method("show_toast"):
		ui.call("show_toast", "New session started (seed %d)" % _world_seed, 2.2, &"info")


func export_save_state() -> Dictionary:
	return {
		"world": {"seed": _world_seed},
		"session": {"ticks": _ticks},
		"player": {
			"position": [_player.global_position.x, _player.global_position.y, _player.global_position.z],
			"facing_yaw": _player.get_facing_yaw(),
			"run_mode": _player.get_run_mode(),
		},
	}


func apply_save_state(doc: Dictionary) -> void:
	var w: Dictionary = doc.get("world", {}) as Dictionary
	_world_seed = int(w.get("seed", 42))
	var s: Dictionary = doc.get("session", {}) as Dictionary
	_ticks = int(s.get("ticks", 0))
	var p: Dictionary = doc.get("player", {}) as Dictionary
	var pos: Array = p.get("position", []) as Array
	if _player != null and pos.size() == 3:
		_player.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		_player.velocity = Vector3.ZERO
		_player.set_facing_yaw(float(p.get("facing_yaw", 0.0)))
		_player.set_run_mode(bool(p.get("run_mode", false)))


func _register_content() -> void:
	var quest_defs := GameContent.quests()
	for quest_def in quest_defs:
		_quests.register_quest(quest_def)
	_quests.bind(get_node_or_null("/root/EventBus"), _flags, _player.get_inventory())
	for quest_def in quest_defs:
		if quest_def.auto_start:
			_quests.start_quest(quest_def.id)
	for item_def in GameContent.items():
		_player.get_inventory().register_item(item_def)
	var save_svc := get_node_or_null("/root/SaveService")
	if save_svc != null and save_svc.has_method("register_saveable"):
		save_svc.call("register_saveable", "flags", _flags)
		save_svc.call("register_saveable", "quests", _quests)


func _setup_dialogue() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DialogueLayer"
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_dialogue_box = DialogueBox.new()
	_dialogue_box.name = "DialogueBox"
	layer.add_child(_dialogue_box)
	_dialogue_box.bind(_flags, _quests, _player.get_inventory(), get_node_or_null("/root/EventBus"))


func _setup_guide() -> void:
	var def := GameContent.dialogue(&"guide_intro")
	if def == null:
		return
	_guide = DialogueInteractable.new()
	_guide.name = "Guide"
	_guide.display_name = "Guide"
	_guide.prompt_text = "Talk to the Guide"
	_guide.interaction_id = "guide"
	_guide.interaction_priority = 5
	_guide.dialogue = def
	add_child(_guide)
	_guide.global_position = _spawn_position + Vector3(3.0, 0.0, -1.0)


func _setup_hud() -> void:
	_hud = GameplayHud.new()
	_hud.name = "GameplayHud"
	add_child(_hud)
	_hud.bind_player_hud(
		_player.get_stats(),
		&"stamina",
		_player.get_inventory(),
		_quests,
		tr("Stamina")
	)


func _setup_prompt() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PromptLayer"
	layer.layer = 35
	add_child(layer)
	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "InteractionPrompt"
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.offset_left = -140.0
	_prompt_panel.offset_right = 140.0
	_prompt_panel.offset_top = -76.0
	_prompt_panel.offset_bottom = -36.0
	_prompt_panel.visible = false
	layer.add_child(_prompt_panel)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt_label)


func _connect_interactor() -> void:
	var interactor := _player.get_interactor()
	if interactor != null and not interactor.focus_changed.is_connected(_on_focus_changed):
		interactor.focus_changed.connect(_on_focus_changed)


func _on_focus_changed(target: Interactable) -> void:
	_focused = target


func _refresh_prompt() -> void:
	if _prompt_panel == null or _prompt_label == null:
		return
	var router := get_node_or_null("/root/InputRouter")
	var gameplay_ok := router == null or bool(router.call("is_gameplay_active"))
	var target := _focused
	if target == null or not is_instance_valid(target) or not gameplay_ok:
		_prompt_panel.visible = false
		return
	_prompt_label.text = "[E] %s" % tr(target.get_prompt_text())
	_prompt_panel.visible = true


func _on_quest_completed(quest_id: StringName) -> void:
	var flow := get_node_or_null("/root/GameFlow")
	var ui := get_node_or_null("/root/UIRouter")
	if flow == null or int(flow.call("get_state")) != 3 or ui == null:
		return
	var title := tr(str(_quests.get_quest_status(quest_id).get("title", String(quest_id))))
	ui.call("show_toast", "QUEST COMPLETE: %s" % title, 3.0, &"success")


func _reset_player() -> void:
	if _player == null:
		return
	_player.global_position = _spawn_position
	_player.velocity = Vector3.ZERO
	_player.set_facing_yaw(0.0)
	_player.set_run_mode(false)


func _register_ui_screens() -> void:
	var ui := get_node_or_null("/root/UIRouter")
	if ui == null:
		return
	ui.call("register_screen", &"title", TITLE_SCENE)
	ui.call("register_screen", &"pause", PAUSE_SCENE)
	ui.call("register_screen", &"settings", SETTINGS_SCENE)
