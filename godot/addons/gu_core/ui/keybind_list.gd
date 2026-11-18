class_name KeybindList
extends VBoxContainer
## Data-driven key rebinding list backed by InputRouter and SettingsStore.

signal binding_updated(action: StringName)

const LISTEN_OWNER := &"keybind_listen"

var input_router: Node = null
var ui_router: Node = null

var _listening_action: StringName = &""
var _buttons_by_action: Dictionary = {} ## StringName -> Button


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	set_process_input(false)
	var ir := _get_input_router()
	if ir != null and ir.has_signal("bindings_changed"):
		if not ir.is_connected("bindings_changed", Callable(self, "_on_router_bindings_changed")):
			ir.connect("bindings_changed", Callable(self, "_on_router_bindings_changed"))
	rebuild()


func _exit_tree() -> void:
	_cancel_listen()


func get_action_count() -> int:
	return _buttons_by_action.size()


func is_listening() -> bool:
	return _listening_action != &""


func get_button_text(action: StringName) -> String:
	var btn := _buttons_by_action.get(action, null) as Button
	return btn.text if btn != null else ""


func rebuild() -> void:
	_cancel_listen()
	_buttons_by_action.clear()
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()

	var ir := _get_input_router()
	var actions: Array = ir.call("list_registered_actions") as Array if (ir != null and ir.has_method("list_registered_actions")) else []
	if actions.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No rebindable actions registered."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62, 0.9))
		add_child(empty_lbl)
		return

	for item: Variant in actions:
		if not (item is Dictionary):
			continue
		var entry := item as Dictionary
		var action := entry["action"] as StringName
		var label_text := str(entry.get("label", String(action)))
		var key_text := str(entry.get("key_label", "Unbound"))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = label_text
		row.add_child(lbl)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 34)
		btn.text = key_text
		btn.pressed.connect(func() -> void: begin_listen(action))
		row.add_child(btn)
		add_child(row)

		_buttons_by_action[action] = btn

	ProtossUiFx.attach_tree(self)


func begin_listen(action: StringName) -> void:
	if not _buttons_by_action.has(action):
		return
	if _listening_action != &"" and _listening_action != action:
		_refresh_labels()
	_listening_action = action
	var btn := _buttons_by_action[action] as Button
	if btn != null:
		btn.text = "Press key... (ESC)"
	var ir := _get_input_router()
	if ir != null and ir.has_method("push_context"):
		ir.call("push_context", 2, LISTEN_OWNER) # InputRouter.Context.MODAL == 2
	set_process_input(true)


func capture_key_event(action: StringName, physical_keycode: int) -> Dictionary:
	var target_action := action if action != &"" else _listening_action
	_cancel_listen()
	if target_action == &"":
		return {"ok": false, "cancelled": true}
	if physical_keycode == KEY_ESCAPE:
		_refresh_labels()
		return {"ok": false, "cancelled": true}

	var ir := _get_input_router()
	if ir == null or not ir.has_method("rebind_action_key"):
		return {"ok": false, "error": "no_input_router"}

	var res := ir.call("rebind_action_key", target_action, physical_keycode, true) as Dictionary
	_refresh_labels()
	if bool(res.get("ok", false)):
		binding_updated.emit(target_action)
		var ui := _get_ui_router()
		if ui != null and ui.has_method("show_toast"):
			var swapped := res.get("swapped_with", &"") as StringName
			var key_lbl := str(ir.call("get_action_key_label", target_action))
			if swapped != &"":
				ui.call("show_toast", "Swapped %s <-> %s (%s)" % [String(target_action), String(swapped), key_lbl], 2.0, &"info")
			else:
				ui.call("show_toast", "Bound %s -> %s" % [String(target_action), key_lbl], 2.0, &"success")
	return res


func reset_all() -> void:
	_cancel_listen()
	var ir := _get_input_router()
	if ir != null and ir.has_method("reset_bindings"):
		ir.call("reset_bindings")
	_refresh_labels()
	var ui := _get_ui_router()
	if ui != null and ui.has_method("show_toast"):
		ui.call("show_toast", "Keybindings reset to defaults", 2.0, &"info")


func _input(event: InputEvent) -> void:
	if _listening_action == &"":
		return
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and not kev.echo:
			if is_inside_tree():
				get_viewport().set_input_as_handled()
			capture_key_event(_listening_action, int(kev.physical_keycode))


func _cancel_listen() -> void:
	if _listening_action != &"":
		_listening_action = &""
		var ir := _get_input_router()
		if ir != null and ir.has_method("pop_context"):
			ir.call("pop_context", LISTEN_OWNER)
	set_process_input(false)


func _refresh_labels() -> void:
	var ir := _get_input_router()
	if ir == null or not ir.has_method("get_action_key_label"):
		return
	for action: StringName in _buttons_by_action:
		var btn := _buttons_by_action[action] as Button
		if btn != null:
			btn.text = str(ir.call("get_action_key_label", action))


func _on_router_bindings_changed(_action: StringName) -> void:
	if _listening_action == &"":
		_refresh_labels()


func _get_input_router() -> Node:
	if input_router != null and is_instance_valid(input_router):
		return input_router
	return get_node_or_null("/root/InputRouter")


func _get_ui_router() -> Node:
	if ui_router != null and is_instance_valid(ui_router):
		return ui_router
	return get_node_or_null("/root/UIRouter")
