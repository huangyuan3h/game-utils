class_name DialogueBox
extends Control
## Bottom-of-screen dialogue panel. Pushes an InputRouter UI context while open
## so gameplay movement and interaction stay blocked without pausing the world.

signal dialogue_started(dialogue_id: StringName)
signal dialogue_ended(dialogue_id: StringName)

const GROUP_NAME := &"gu_dialogue_box"
const _CONTEXT_OWNER := &"dialogue_box"
const _UI_CONTEXT := 1 ## InputRouter.Context.UI

var _runner := DialogueRunner.new()
var _open := false
var _context_pushed := false
var _ui_ready := false

var _speaker_label: Label
var _body_label: Label
var _error_label: Label
var _choice_box: VBoxContainer


func _enter_tree() -> void:
	if not is_in_group(GROUP_NAME):
		add_to_group(GROUP_NAME)


func _exit_tree() -> void:
	_pop_context()
	if is_in_group(GROUP_NAME):
		remove_from_group(GROUP_NAME)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_ensure_ui()
	if not _runner.ended.is_connected(_on_runner_ended):
		_runner.ended.connect(_on_runner_ended)


func bind(
	p_flags: FlagStore = null,
	p_quests: QuestTracker = null,
	p_inventory: InventoryContainer = null,
	p_event_bus: Object = null
) -> void:
	_runner.bind(p_flags, p_quests, p_inventory, p_event_bus)


func is_open() -> bool:
	return _open


func start(def: DialogueDef) -> bool:
	_ensure_ui()
	if _open:
		_dismiss(false)
	var view := _runner.start(def)
	if not bool(view.get("ok", false)) or bool(view.get("ended", false)):
		return false
	_open = true
	visible = true
	_push_context()
	_render(view)
	dialogue_started.emit(def.id if def != null else &"")
	return true


func close() -> void:
	if _runner.is_active():
		_runner.close()
		return
	if _open:
		_dismiss(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		_mark_input_handled()
		return
	if event.is_action_pressed(&"ui_accept"):
		_activate_single_advance()


func _ensure_ui() -> void:
	if _ui_ready:
		return
	_ui_ready = true

	var theme_path := "res://addons/gu_core/ui/default_theme.tres"
	if ResourceLoader.exists(theme_path):
		theme = load(theme_path) as Theme

	var panel := PanelContainer.new()
	panel.name = "DialoguePanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 48.0
	panel.offset_right = -48.0
	panel.offset_top = -228.0
	panel.offset_bottom = -24.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.name = "SpeakerLabel"
	_speaker_label.add_theme_font_size_override("font_size", 18)
	_speaker_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	vbox.add_child(_speaker_label)

	_body_label = Label.new()
	_body_label.name = "BodyLabel"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_body_label)

	_error_label = Label.new()
	_error_label.name = "ErrorLabel"
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	_error_label.visible = false
	vbox.add_child(_error_label)

	_choice_box = VBoxContainer.new()
	_choice_box.name = "Choices"
	_choice_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_choice_box)


func _render(view: Dictionary) -> void:
	_speaker_label.text = tr(str(view.get("speaker", "")))
	_body_label.text = tr(str(view.get("text", "")))
	var error := str(view.get("error", ""))
	_error_label.text = _error_text(error)
	_error_label.visible = _error_label.text != ""
	_clear_choices()

	var choices: Variant = view.get("choices", [])
	if choices is Array:
		for raw in choices as Array:
			if not (raw is Dictionary):
				continue
			var choice := raw as Dictionary
			var button := _make_button(tr(str(choice.get("text", ""))))
			var index := int(choice.get("index", -1))
			button.pressed.connect(_on_choice_pressed.bind(index))
			_choice_box.add_child(button)

	if bool(view.get("can_continue", false)):
		var cont := _make_button(tr("Continue"))
		cont.name = "ContinueButton"
		cont.pressed.connect(_on_continue_pressed)
		_choice_box.add_child(cont)
	elif bool(view.get("terminal", false)):
		var close_btn := _make_button("Close")
		close_btn.name = "CloseButton"
		close_btn.pressed.connect(_on_close_pressed)
		_choice_box.add_child(close_btn)


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 36)
	return button


func _clear_choices() -> void:
	if _choice_box == null:
		return
	for child in _choice_box.get_children():
		_choice_box.remove_child(child)
		child.queue_free()


func _on_choice_pressed(index: int) -> void:
	if not _open:
		return
	var view := _runner.choose(index)
	if bool(view.get("ended", false)):
		return
	_render(view)


func _on_continue_pressed() -> void:
	if not _open:
		return
	var view := _runner.continue_line()
	if bool(view.get("ended", false)):
		return
	_render(view)


func _activate_single_advance() -> void:
	if _choice_box == null or _choice_box.get_child_count() != 1:
		return
	var only := _choice_box.get_child(0) as Button
	if only == null:
		return
	if only.name == "ContinueButton" or only.name == "CloseButton":
		only.pressed.emit()
		_mark_input_handled()


func _on_close_pressed() -> void:
	close()


func _mark_input_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _on_runner_ended(dialogue_id: StringName) -> void:
	_dismiss(false)
	dialogue_ended.emit(dialogue_id)


func _dismiss(emit_ended: bool) -> void:
	var was_open := _open
	_open = false
	visible = false
	_pop_context()
	_clear_choices()
	if emit_ended and was_open:
		dialogue_ended.emit(&"")


func _push_context() -> void:
	if _context_pushed:
		return
	var router := get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("push_context"):
		router.call("push_context", _UI_CONTEXT, _CONTEXT_OWNER)
		_context_pushed = true


func _pop_context() -> void:
	if not _context_pushed:
		return
	_context_pushed = false
	var router := get_node_or_null("/root/InputRouter")
	if router != null and is_instance_valid(router) and router.has_method("pop_context"):
		router.call("pop_context", _CONTEXT_OWNER)


func _error_text(code: String) -> String:
	match code:
		"missing_item":
			return "You don't have the required items."
		"inventory_full":
			return "Not enough room in your pack."
		"unknown_quest":
			return "That task is unavailable."
		_:
			return ""
