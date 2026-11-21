extends Node3D
## Starter world entry point wired to GameFlow, UIRouter, SaveService, and the shared 3D player.

const TITLE_SCENE := preload("res://scenes/ui/title_screen.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/settings_panel.tscn")

@onready var _player: GuPlayer = $Player
@onready var _camera_rig: CameraRig = $CameraPivot

var _world_seed: int = 42
var _ticks: int = 0
var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_register_ui_screens()
	if _player != null:
		_spawn_position = _player.global_position
		if _camera_rig != null:
			_camera_rig.set_target(_player)
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("register_world", self)
		flow.call("enter_title")


func _process(_delta: float) -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null and int(flow.call("get_state")) == 3:
		_ticks += 1


func start_new_world(opts: Dictionary = {}) -> void:
	_world_seed = int(opts.get("seed", 42))
	_ticks = 0
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
