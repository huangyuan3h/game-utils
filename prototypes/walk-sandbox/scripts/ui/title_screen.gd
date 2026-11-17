extends Control
## Protoss-themed title overlay bound to GameFlow and SaveService.

@onready var _panel: PanelContainer = %Panel
@onready var _continue_btn: Button = %ContinueButton
@onready var _new_btn: Button = %NewWorldButton
@onready var _settings_btn: Button = %SettingsButton
@onready var _quit_btn: Button = %QuitButton


func _ready() -> void:
	_continue_btn.pressed.connect(_on_continue)
	_new_btn.pressed.connect(_on_new_world)
	_settings_btn.pressed.connect(_on_settings)
	_quit_btn.pressed.connect(_on_quit)
	ProtossUiFx.attach_tree(self, [_quit_btn])
	_refresh_continue()


func on_ui_enter(_params: Dictionary = {}) -> void:
	_refresh_continue()
	ProtossUiFx.animate_panel_enter(_panel, self, false)


func _refresh_continue() -> void:
	var save_svc := get_node_or_null("/root/SaveService")
	var flow := get_node_or_null("/root/GameFlow")
	var slot := str(flow.get("default_save_slot")) if flow != null else "autosave"
	var has_save := save_svc != null and bool(save_svc.call("has_slot", slot))
	_continue_btn.disabled = not has_save


func _on_continue() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("load_game")


func _on_new_world() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("start_new_game", {})


func _on_settings() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("open_settings")


func _on_quit() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("quit_game")
