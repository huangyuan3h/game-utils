extends Control
## Starter pause menu: Resume, Save, Settings, Return to Title (with modal confirmation).

@onready var _panel: PanelContainer = %Panel
@onready var _resume_btn: Button = %ResumeButton
@onready var _save_btn: Button = %SaveButton
@onready var _slots_btn: Button = get_node_or_null("%SlotsButton") as Button
@onready var _settings_btn: Button = %SettingsButton
@onready var _title_btn: Button = %TitleButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_resume_btn.pressed.connect(_on_resume)
	_save_btn.pressed.connect(_on_save)
	if _slots_btn != null:
		_slots_btn.pressed.connect(_on_slots)
	_settings_btn.pressed.connect(_on_settings)
	_title_btn.pressed.connect(_on_title)
	ProtossUiFx.attach_tree(self, [_resume_btn, _title_btn])
	_refresh_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func on_ui_enter(_params: Dictionary = {}) -> void:
	_status_label.text = ""
	_refresh_texts()
	ProtossUiFx.animate_panel_enter(_panel, self, true)


func _refresh_texts() -> void:
	_set_tr(get_node_or_null("Center/Panel/VBox/Header"), "PAUSE_HEADER")
	_set_tr(_resume_btn, "PAUSE_RESUME")
	_set_tr(_save_btn, "PAUSE_SAVE")
	_set_tr(_slots_btn, "PAUSE_SLOTS")
	_set_tr(_settings_btn, "PAUSE_SETTINGS")
	_set_tr(_title_btn, "PAUSE_TITLE")


func _set_tr(node: Node, key: String) -> void:
	if node == null or not ("text" in node):
		return
	node.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	node.text = tr(key)


func _on_resume() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("set_paused", false)


func _on_save() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		return
	var err: int = int(flow.call("save_current_game"))
	if err == OK:
		_status_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1))
		_status_label.text = tr("PAUSE_SAVED")
	else:
		_status_label.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62, 1))
		_status_label.text = tr("PAUSE_SAVE_FAILED") % err


func _on_settings() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("open_settings")


func _on_slots() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null and flow.has_method("open_save_slots"):
		flow.call("open_save_slots", "save")


func _on_title() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		return
	var ui := get_node_or_null("/root/UIRouter")
	if ui != null and ui.has_method("show_confirm"):
		ui.call(
			"show_confirm",
			tr("PAUSE_CONFIRM_TITLE"),
			tr("PAUSE_CONFIRM_BODY"),
			func() -> void:
				if is_instance_valid(flow):
					flow.call("return_to_title"),
			{"confirm_text": tr("PAUSE_CONFIRM_OK"), "cancel_text": tr("PAUSE_CONFIRM_CANCEL")}
		)
	else:
		flow.call("return_to_title")
