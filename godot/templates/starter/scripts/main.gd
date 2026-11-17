extends Node3D
## Starter world entry point wired to GameFlow, UIRouter, and SaveService.

const TITLE_SCENE := preload("res://scenes/ui/title_screen.tscn")
const PAUSE_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/settings_panel.tscn")

var _world_seed: int = 42
var _ticks: int = 0


func _ready() -> void:
	_register_ui_screens()
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
	var ui := get_node_or_null("/root/UIRouter")
	if ui != null and ui.has_method("show_toast"):
		ui.call("show_toast", "New session started (seed %d)" % _world_seed, 2.2, &"info")


func export_save_state() -> Dictionary:
	return {
		"world": {"seed": _world_seed},
		"session": {"ticks": _ticks},
	}


func apply_save_state(doc: Dictionary) -> void:
	var w: Dictionary = doc.get("world", {}) as Dictionary
	_world_seed = int(w.get("seed", 42))
	var s: Dictionary = doc.get("session", {}) as Dictionary
	_ticks = int(s.get("ticks", 0))


func _register_ui_screens() -> void:
	var ui := get_node_or_null("/root/UIRouter")
	if ui == null:
		return
	ui.call("register_screen", &"title", TITLE_SCENE)
	ui.call("register_screen", &"pause", PAUSE_SCENE)
	ui.call("register_screen", &"settings", SETTINGS_SCENE)
