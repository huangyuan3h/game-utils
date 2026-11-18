class_name SaveSlotsPanel
extends Control
## Reusable Protoss-themed save/load slots browser bound to SaveService, GameFlow, and UIRouter.

@onready var _panel: PanelContainer = %Panel
@onready var _header_label: Label = %HeaderLabel
@onready var _mode_row: HBoxContainer = %ModeRow
@onready var _load_mode_btn: Button = %LoadModeButton
@onready var _save_mode_btn: Button = %SaveModeButton
@onready var _new_slot_row: HBoxContainer = %NewSlotRow
@onready var _slot_input: LineEdit = %SlotNameInput
@onready var _create_save_btn: Button = %CreateSaveButton
@onready var _slot_list: VBoxContainer = %SlotList
@onready var _back_btn: Button = %BackButton

var save_service: Node = null
var game_flow: Node = null
var ui_router: Node = null

var _mode: String = "load"
var _allow_save: bool = false
var _slot_count: int = 0


func _ready() -> void:
	if _load_mode_btn != null:
		_load_mode_btn.pressed.connect(func() -> void: set_mode("load"))
	if _save_mode_btn != null:
		_save_mode_btn.pressed.connect(func() -> void: set_mode("save"))
	if _create_save_btn != null:
		_create_save_btn.pressed.connect(_on_create_save_pressed)
	if _slot_input != null:
		_slot_input.text_submitted.connect(func(_txt: String) -> void: _on_create_save_pressed())
	if _back_btn != null:
		_back_btn.pressed.connect(_on_back)
		ProtossUiFx.attach_tree(self, [_back_btn])
	_apply_mode_ui()
	refresh_slots()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_mode_ui()
		refresh_slots()


func on_ui_enter(params: Dictionary = {}) -> void:
	_allow_save = bool(params.get("allow_save", false))
	var req_mode := str(params.get("mode", "load"))
	_mode = "save" if (req_mode == "save" and _allow_save) else "load"
	_apply_mode_ui()
	refresh_slots()
	ProtossUiFx.animate_panel_enter(_panel, self, true)


func get_mode() -> String:
	return _mode


func set_mode(next_mode: String) -> void:
	if next_mode == "save" and not _allow_save:
		return
	_mode = "save" if next_mode == "save" else "load"
	_apply_mode_ui()
	refresh_slots()


func get_slot_count() -> int:
	return _slot_count


func refresh_slots() -> void:
	if _slot_list == null:
		return
	for ch in _slot_list.get_children():
		_slot_list.remove_child(ch)
		ch.queue_free()

	var svc := _get_save_service()
	var metas: Array = svc.call("list_slot_metadata") as Array if (svc != null and svc.has_method("list_slot_metadata")) else []
	_slot_count = metas.size()

	if metas.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = tr("SLOTS_EMPTY")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62, 0.9))
		_slot_list.add_child(empty_lbl)
		return

	for item: Variant in metas:
		if not (item is Dictionary):
			continue
		var meta := item as Dictionary
		_slot_list.add_child(_build_slot_row(meta))


func save_to_slot(slot_name: String) -> Error:
	var svc := _get_save_service()
	var flow := _get_game_flow()
	var clean_name := str(svc.call("sanitize_slot", slot_name)) if svc != null else slot_name.strip_edges()
	if clean_name == "":
		clean_name = "slot_1"
	if flow == null or not flow.has_method("save_current_game"):
		return ERR_UNAVAILABLE
	var err := int(flow.call("save_current_game", clean_name)) as Error
	var ui := _get_ui_router()
	if err == OK:
		if ui != null and ui.has_method("show_toast"):
			ui.call("show_toast", tr("SLOTS_SAVED") % clean_name, 2.2, &"success")
		refresh_slots()
	elif ui != null and ui.has_method("show_toast"):
		ui.call("show_toast", tr("SLOTS_SAVE_FAILED") % err, 2.5, &"error")
	return err


func load_from_slot(slot_name: String) -> bool:
	var flow := _get_game_flow()
	if flow == null or not flow.has_method("load_game"):
		return false
	var ok := bool(flow.call("load_game", slot_name))
	if not ok:
		var ui := _get_ui_router()
		if ui != null and ui.has_method("show_toast"):
			ui.call("show_toast", tr("SLOTS_LOAD_FAILED") % slot_name, 2.5, &"error")
	return ok


func delete_slot_confirmed(slot_name: String) -> Error:
	var svc := _get_save_service()
	if svc == null or not svc.has_method("delete_slot"):
		return ERR_UNAVAILABLE
	var err := int(svc.call("delete_slot", slot_name)) as Error
	if err == OK:
		var ui := _get_ui_router()
		if ui != null and ui.has_method("show_toast"):
			ui.call("show_toast", tr("SLOTS_DELETED") % slot_name, 2.0, &"info")
		refresh_slots()
	return err


func _build_slot_row(meta: Dictionary) -> Control:
	var slot_name := str(meta.get("slot", ""))
	var ts_text := str(meta.get("saved_at_text", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var info_lbl := Label.new()
	info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var when := ts_text if ts_text != "" else tr("SLOTS_UNKNOWN_TIME")
	info_lbl.text = "%s  —  %s" % [slot_name, when]
	info_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(info_lbl)

	var primary_btn := Button.new()
	primary_btn.custom_minimum_size = Vector2(104, 34)
	if _mode == "save":
		primary_btn.text = tr("SLOTS_OVERWRITE")
		primary_btn.pressed.connect(func() -> void: _confirm_save_overwrite(slot_name))
	else:
		primary_btn.text = tr("SLOTS_LOAD")
		primary_btn.pressed.connect(func() -> void: load_from_slot(slot_name))
	row.add_child(primary_btn)

	var del_btn := Button.new()
	del_btn.custom_minimum_size = Vector2(84, 34)
	del_btn.text = tr("SLOTS_DELETE")
	del_btn.pressed.connect(func() -> void: _confirm_delete(slot_name))
	row.add_child(del_btn)

	ProtossUiFx.attach_tree(row, [del_btn])
	return row


func _on_create_save_pressed() -> void:
	var raw := _slot_input.text.strip_edges() if _slot_input != null else ""
	if raw == "":
		raw = "slot_%d" % (_slot_count + 1)
	var svc := _get_save_service()
	var clean := str(svc.call("sanitize_slot", raw)) if svc != null else raw
	if svc != null and bool(svc.call("has_slot", clean)):
		_confirm_save_overwrite(clean)
	else:
		if save_to_slot(clean) == OK and _slot_input != null:
			_slot_input.text = ""


func _confirm_save_overwrite(slot_name: String) -> void:
	var ui := _get_ui_router()
	if ui != null and ui.has_method("show_confirm"):
		ui.call(
			"show_confirm",
			tr("SLOTS_OVERWRITE_TITLE"),
			tr("SLOTS_OVERWRITE_BODY") % slot_name,
			func() -> void: save_to_slot(slot_name),
			{"confirm_text": tr("SLOTS_OVERWRITE"), "cancel_text": tr("SLOTS_CANCEL")}
		)
	else:
		save_to_slot(slot_name)


func _confirm_delete(slot_name: String) -> void:
	var ui := _get_ui_router()
	if ui != null and ui.has_method("show_confirm"):
		ui.call(
			"show_confirm",
			tr("SLOTS_DELETE_TITLE"),
			tr("SLOTS_DELETE_BODY") % slot_name,
			func() -> void: delete_slot_confirmed(slot_name),
			{"confirm_text": tr("SLOTS_DELETE"), "cancel_text": tr("SLOTS_CANCEL")}
		)
	else:
		delete_slot_confirmed(slot_name)


func _apply_mode_ui() -> void:
	if _header_label != null:
		_header_label.text = tr("SLOTS_HEADER_SAVE") if _mode == "save" else tr("SLOTS_HEADER_LOAD")
	if _load_mode_btn != null:
		_load_mode_btn.text = tr("SLOTS_LOAD_MODE")
	if _save_mode_btn != null:
		_save_mode_btn.text = tr("SLOTS_SAVE_MODE")
	if _create_save_btn != null:
		_create_save_btn.text = tr("SLOTS_SAVE_NEW")
	if _slot_input != null:
		_slot_input.placeholder_text = tr("SLOTS_NAME_PLACEHOLDER")
	if _back_btn != null:
		_back_btn.text = tr("SLOTS_BACK")
	if _mode_row != null:
		_mode_row.visible = _allow_save
	if _save_mode_btn != null:
		_save_mode_btn.disabled = (not _allow_save) or (_mode == "save")
	if _load_mode_btn != null:
		_load_mode_btn.disabled = (_mode == "load")
	if _new_slot_row != null:
		_new_slot_row.visible = (_mode == "save" and _allow_save)


func _on_back() -> void:
	var flow := _get_game_flow()
	if flow != null and flow.has_method("close_top_ui"):
		flow.call("close_top_ui")


func _get_save_service() -> Node:
	if save_service != null and is_instance_valid(save_service):
		return save_service
	return get_node_or_null("/root/SaveService")


func _get_game_flow() -> Node:
	if game_flow != null and is_instance_valid(game_flow):
		return game_flow
	return get_node_or_null("/root/GameFlow")


func _get_ui_router() -> Node:
	if ui_router != null and is_instance_valid(ui_router):
		return ui_router
	return get_node_or_null("/root/UIRouter")
