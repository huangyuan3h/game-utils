extends Control
## Starter title overlay bound to GameFlow and SaveService.

@onready var _panel: PanelContainer = %Panel
@onready var _title_label: Label = %TitleLabel
@onready var _continue_btn: Button = %ContinueButton
@onready var _load_slots_btn: Button = get_node_or_null("%LoadSlotsButton") as Button
@onready var _new_btn: Button = %NewWorldButton
@onready var _settings_btn: Button = %SettingsButton
@onready var _quit_btn: Button = %QuitButton


func _ready() -> void:
	if _title_label != null:
		var app_name := str(ProjectSettings.get_setting("application/config/name", "Starter Game"))
		_title_label.text = app_name.to_upper()
	_continue_btn.pressed.connect(_on_continue)
	if _load_slots_btn != null:
		_load_slots_btn.pressed.connect(_on_load_slots)
	_new_btn.pressed.connect(_on_new_world)
	_settings_btn.pressed.connect(_on_settings)
	_quit_btn.pressed.connect(_on_quit)
	ProtossUiFx.attach_tree(self, [_quit_btn])
	_refresh_texts()
	_refresh_continue()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func on_ui_enter(_params: Dictionary = {}) -> void:
	_refresh_texts()
	_refresh_continue()
	ProtossUiFx.animate_panel_enter(_panel, self, false)


func _refresh_texts() -> void:
	_set_tr(get_node_or_null("Center/Panel/VBox/SectorTag"), "TITLE_TAG")
	_set_tr(_continue_btn, "TITLE_CONTINUE")
	_set_tr(_load_slots_btn, "TITLE_LOAD")
	_set_tr(_new_btn, "TITLE_NEW")
	_set_tr(_settings_btn, "TITLE_SETTINGS")
	_set_tr(_quit_btn, "TITLE_QUIT")


func _set_tr(node: Node, key: String) -> void:
	if node == null or not ("text" in node):
		return
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	node.text = tr(key)


func _refresh_continue() -> void:
	var save_svc := get_node_or_null("/root/SaveService")
	var flow := get_node_or_null("/root/GameFlow")
	var slot := str(flow.get("default_save_slot")) if flow != null else "autosave"
	var has_save := save_svc != null and bool(save_svc.call("has_slot", slot))
	_continue_btn.disabled = not has_save
	if _load_slots_btn != null:
		var any_slots := save_svc != null and not (save_svc.call("list_slots") as Array).is_empty()
		_load_slots_btn.disabled = not any_slots


func _on_continue() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("load_game")


func _on_load_slots() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null and flow.has_method("open_save_slots"):
		flow.call("open_save_slots", "load")


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
