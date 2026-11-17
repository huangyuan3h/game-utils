extends Control
## Protoss-themed pause overlay menu: Resume, Save, Settings, Return to Title.

@onready var _panel: PanelContainer = %Panel
@onready var _resume_btn: Button = %ResumeButton
@onready var _save_btn: Button = %SaveButton
@onready var _settings_btn: Button = %SettingsButton
@onready var _title_btn: Button = %TitleButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_resume_btn.pressed.connect(_on_resume)
	_save_btn.pressed.connect(_on_save)
	_settings_btn.pressed.connect(_on_settings)
	_title_btn.pressed.connect(_on_title)
	ProtossUiFx.attach_tree(self, [_resume_btn, _title_btn])


func on_ui_enter(_params: Dictionary = {}) -> void:
	_status_label.text = ""
	ProtossUiFx.animate_panel_enter(_panel, self, true)


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
		_status_label.add_theme_color_override("font_color", Color(0.31, 0.95, 0.78, 1))
		_status_label.text = "CHRONO ARCHIVE SYNCED (autosave)"
	else:
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.42, 1))
		_status_label.text = "ARCHIVE FAILED (%d)" % err


func _on_settings() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.call("open_settings")


func _on_title() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow == null:
		return
	var ui := get_node_or_null("/root/UIRouter")
	if ui != null and ui.has_method("show_confirm"):
		ui.call(
			"show_confirm",
			"RETURN TO NEXUS",
			"Unsaved exploration progress will be lost. Return to title screen?",
			func() -> void:
				if is_instance_valid(flow):
					flow.call("return_to_title"),
			{"confirm_text": "RETURN", "cancel_text": "STAY"}
		)
	else:
		flow.call("return_to_title")
