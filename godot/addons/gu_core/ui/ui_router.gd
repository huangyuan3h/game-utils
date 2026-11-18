extends Node
## Overlay UI stack router coordinating screen instances, InputRouter contexts,
## queued toast notifications, modal confirmation dialogs, and screen transitions.

signal screen_pushed(screen_id: StringName)
signal screen_popped(screen_id: StringName)
signal stack_emptied
signal toast_shown(message: String, tone: StringName)
signal transition_finished

const DEFAULT_THEME_PATH := "res://addons/gu_core/ui/default_theme.tres"
const FontFallbackScript := preload("res://addons/gu_core/i18n/font_fallback.gd")
const CONFIRM_SCREEN_ID := &"__confirm__"
const MAX_ACTIVE_TOASTS := 3

var _registry: Dictionary = {} ## StringName -> PackedScene
var _stack: Array[Dictionary] = [] ## [{"id": StringName, "node": Control, "owner": StringName}]
var _layer: CanvasLayer = null
var _root: Control = null

var _overlay_layer: CanvasLayer = null
var _toast_box: VBoxContainer = null
var _toast_queue: Array[Dictionary] = []
var _active_toasts: int = 0

var _transition_rect: ColorRect = null
var _transition_tween: Tween = null
var _transitioning: bool = false
var _loading_root: Control = null
var _loading_bar: ProgressBar = null


class ConfirmDialog extends Control:
	signal confirmed
	signal cancelled

	var _on_confirm: Callable
	var _on_cancel: Callable
	var _router: Node
	var _resolved: bool = false

	func setup(
		p_router: Node,
		title_text: String,
		body_text: String,
		p_on_confirm: Callable,
		p_on_cancel: Callable,
		confirm_label: String,
		cancel_label: String,
		theme_res: Theme
	) -> void:
		_router = p_router
		_on_confirm = p_on_confirm
		_on_cancel = p_on_cancel
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_preset(Control.PRESET_FULL_RECT)
		if theme_res != null:
			theme = theme_res

		var backdrop := ColorRect.new()
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.color = Color(0.01, 0.02, 0.05, 0.72)
		add_child(backdrop)

		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)

		var panel := PanelContainer.new()
		panel.name = "Panel"
		panel.custom_minimum_size = Vector2(400, 0)
		center.add_child(panel)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 12)
		panel.add_child(vbox)

		var title_lbl := Label.new()
		title_lbl.name = "TitleLabel"
		title_lbl.text = title_text
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.add_theme_font_size_override("font_size", 20)
		title_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
		vbox.add_child(title_lbl)

		var body_lbl := Label.new()
		body_lbl.name = "BodyLabel"
		body_lbl.text = body_text
		body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(body_lbl)

		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row.add_theme_constant_override("separation", 14)
		vbox.add_child(btn_row)

		var cancel_btn := Button.new()
		cancel_btn.name = "CancelButton"
		cancel_btn.custom_minimum_size = Vector2(140, 38)
		cancel_btn.text = cancel_label
		cancel_btn.pressed.connect(cancel)
		btn_row.add_child(cancel_btn)

		var confirm_btn := Button.new()
		confirm_btn.name = "ConfirmButton"
		confirm_btn.custom_minimum_size = Vector2(140, 38)
		confirm_btn.text = confirm_label
		confirm_btn.pressed.connect(confirm)
		btn_row.add_child(confirm_btn)

		if ResourceLoader.exists("res://addons/gu_core/ui/protoss_ui_fx.gd"):
			ProtossUiFx.attach_tree(self, [cancel_btn])

	func confirm() -> void:
		if _resolved:
			return
		_resolved = true
		if _router != null and is_instance_valid(_router) and _router.call("top_screen_id") == CONFIRM_SCREEN_ID:
			_router.call("pop_screen")
		confirmed.emit()
		if _on_confirm.is_valid():
			_on_confirm.call()

	func cancel() -> void:
		if _resolved:
			return
		_resolved = true
		if _router != null and is_instance_valid(_router) and _router.call("top_screen_id") == CONFIRM_SCREEN_ID:
			_router.call("pop_screen")
		cancelled.emit()
		if _on_cancel.is_valid():
			_on_cancel.call()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_layer()


func register_screen(screen_id: StringName, scene: PackedScene) -> void:
	if screen_id == &"" or scene == null:
		return
	_registry[screen_id] = scene


func has_registered(screen_id: StringName) -> bool:
	return _registry.has(screen_id)


func push_screen(screen_id: StringName, params: Dictionary = {}, input_ctx: int = 1) -> Control:
	if not _registry.has(screen_id):
		push_warning("UIRouter: screen '%s' is not registered." % String(screen_id))
		return null
	_ensure_layer()
	var packed: PackedScene = _registry[screen_id] as PackedScene
	var inst := packed.instantiate() as Control
	if inst == null:
		push_warning("UIRouter: screen '%s' root must inherit Control." % String(screen_id))
		return null

	_push_instance(screen_id, inst, params, input_ctx)
	return inst


func show_confirm(
	title: String,
	body: String,
	on_confirm: Callable = Callable(),
	opts: Dictionary = {}
) -> Control:
	_ensure_layer()
	var on_cancel: Callable = opts.get("on_cancel", Callable()) as Callable
	var confirm_label := str(opts.get("confirm_text", "CONFIRM"))
	var cancel_label := str(opts.get("cancel_text", "CANCEL"))
	var dlg := ConfirmDialog.new()
	dlg.name = "ConfirmDialog"
	dlg.setup(self, title, body, on_confirm, on_cancel, confirm_label, cancel_label, _root.theme)
	_push_instance(CONFIRM_SCREEN_ID, dlg, {}, 2) # InputRouter.Context.MODAL == 2
	return dlg


func pop_screen() -> void:
	if _stack.is_empty():
		return
	var entry: Dictionary = _stack.pop_back()
	var screen_id: StringName = entry["id"] as StringName
	var node := entry["node"] as Control
	var owner: StringName = entry["owner"] as StringName

	var input_router := get_node_or_null("/root/InputRouter")
	if input_router != null and input_router.has_method("pop_context"):
		input_router.call("pop_context", owner)

	if is_instance_valid(node):
		if node.has_method("on_ui_exit"):
			node.call("on_ui_exit")
		node.queue_free()

	var remembered: Variant = entry.get("focus", null)
	if remembered is Control and is_instance_valid(remembered):
		(remembered as Control).grab_focus()

	if not _stack.is_empty():
		var new_top := _stack[_stack.size() - 1]["node"] as Control
		if is_instance_valid(new_top):
			new_top.visible = true
	else:
		stack_emptied.emit()

	screen_popped.emit(screen_id)


func replace_screen(screen_id: StringName, params: Dictionary = {}, input_ctx: int = 1) -> Control:
	if not _stack.is_empty():
		pop_screen()
	return push_screen(screen_id, params, input_ctx)


func clear_screens() -> void:
	while not _stack.is_empty():
		pop_screen()


func is_open() -> bool:
	return not _stack.is_empty()


func stack_size() -> int:
	return _stack.size()


func top_screen_id() -> StringName:
	if _stack.is_empty():
		return &""
	return _stack[_stack.size() - 1]["id"] as StringName


func set_loading_progress(progress: float) -> void:
	_ensure_loading_bar()
	_loading_root.visible = true
	_loading_bar.value = clampf(progress, 0.0, 1.0) * 100.0


func hide_loading() -> void:
	if _loading_root != null:
		_loading_root.visible = false


func get_loading_progress() -> float:
	if _loading_bar == null:
		return 0.0
	return _loading_bar.value / 100.0


func show_toast(message: String, duration: float = 2.6, tone: StringName = &"info") -> void:
	if message == "":
		return
	_ensure_layer()
	_toast_queue.append({
		"message": message,
		"duration": maxf(duration, 0.2),
		"tone": tone,
	})
	_pump_toasts()


func clear_toasts() -> void:
	_toast_queue.clear()
	_active_toasts = 0
	if _toast_box != null and is_instance_valid(_toast_box):
		for ch in _toast_box.get_children():
			_toast_box.remove_child(ch)
			ch.queue_free()


func get_active_toast_count() -> int:
	return _active_toasts


func get_queued_toast_count() -> int:
	return _toast_queue.size()


func fade_out(duration: float = 0.25) -> void:
	_ensure_layer()
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_rect.visible = true
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	if duration <= 0.0 or not is_inside_tree():
		_transition_rect.color.a = 1.0
		_transitioning = false
		transition_finished.emit()
		return
	_transitioning = true
	_transition_tween = create_tween()
	_transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_property(_transition_rect, "color:a", 1.0, duration).set_trans(Tween.TRANS_SINE)
	await _transition_tween.finished
	_transitioning = false
	transition_finished.emit()


func fade_in(duration: float = 0.25) -> void:
	_ensure_layer()
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if duration <= 0.0 or not is_inside_tree():
		_transition_rect.color.a = 0.0
		_transition_rect.visible = false
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_transitioning = false
		transition_finished.emit()
		return
	_transitioning = true
	_transition_tween = create_tween()
	_transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition_tween.tween_property(_transition_rect, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE)
	await _transition_tween.finished
	if is_instance_valid(_transition_rect):
		_transition_rect.visible = false
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false
	transition_finished.emit()


func run_transition(mid_action: Callable, duration: float = 0.22) -> void:
	await fade_out(duration)
	if mid_action.is_valid():
		mid_action.call()
	await fade_in(duration)


func is_transitioning() -> bool:
	return _transitioning


func get_transition_alpha() -> float:
	if _transition_rect == null:
		return 0.0
	return _transition_rect.color.a


func _push_instance(screen_id: StringName, inst: Control, params: Dictionary, input_ctx: int) -> void:
	if not _stack.is_empty():
		var prev := _stack[_stack.size() - 1]["node"] as Control
		if is_instance_valid(prev):
			prev.visible = false

	_root.add_child(inst)
	var owner := StringName("ui:" + String(screen_id) + ":" + str(inst.get_instance_id()))
	var previous_focus: Control = null
	var viewport := get_viewport()
	if viewport != null:
		previous_focus = viewport.gui_get_focus_owner()
	_stack.append({"id": screen_id, "node": inst, "owner": owner, "focus": previous_focus})

	var input_router := get_node_or_null("/root/InputRouter")
	if input_router != null and input_router.has_method("push_context"):
		input_router.call("push_context", input_ctx, owner)

	if inst.has_method("on_ui_enter"):
		inst.call("on_ui_enter", params)
	screen_pushed.emit(screen_id)


func _ensure_loading_bar() -> void:
	_ensure_layer()
	if _loading_root != null and is_instance_valid(_loading_root):
		return
	var overlay := _overlay_layer.get_node_or_null("OverlayRoot") as Control
	if overlay == null:
		return
	_loading_root = CenterContainer.new()
	_loading_root.name = "LoadingRoot"
	_loading_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_root.visible = false
	_loading_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(_loading_root)
	_loading_bar = ProgressBar.new()
	_loading_bar.name = "LoadingBar"
	_loading_bar.custom_minimum_size = Vector2(320, 18)
	_loading_bar.max_value = 100.0
	_loading_bar.value = 0.0
	_loading_root.add_child(_loading_bar)


func _pump_toasts() -> void:
	while _active_toasts < MAX_ACTIVE_TOASTS and not _toast_queue.is_empty():
		var item: Dictionary = _toast_queue.pop_front() as Dictionary
		_spawn_toast_banner(str(item["message"]), float(item["duration"]), item["tone"] as StringName)


func _spawn_toast_banner(message: String, duration: float, tone: StringName) -> void:
	if _toast_box == null or not is_instance_valid(_toast_box):
		return
	_active_toasts += 1

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(280, 0)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var lbl := Label.new()
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", _tone_color(tone))
	panel.add_child(lbl)
	_toast_box.add_child(panel)

	toast_shown.emit(message, tone)

	if not is_inside_tree():
		panel.modulate.a = 1.0
		return

	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(panel, "modulate:a", 1.0, 0.16)
	tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.24)
	tw.tween_callback(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
		_active_toasts = maxi(0, _active_toasts - 1)
		_pump_toasts()
	)


func _tone_color(tone: StringName) -> Color:
	match tone:
		&"success":
			return Color(0.95, 0.95, 0.95, 1.0)
		&"warning":
			return Color(0.78, 0.78, 0.78, 1.0)
		&"error":
			return Color(0.62, 0.62, 0.62, 1.0)
		_:
			return Color(0.9, 0.9, 0.9, 1.0)


func _ensure_layer() -> void:
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "UIRouterLayer"
		_layer.layer = 50
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_layer)

		_root = Control.new()
		_root.name = "ScreenStack"
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists(DEFAULT_THEME_PATH):
			_root.theme = load(DEFAULT_THEME_PATH) as Theme
			FontFallbackScript.apply_theme(_root.theme)
		_layer.add_child(_root)

	if _overlay_layer == null or not is_instance_valid(_overlay_layer):
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.name = "UIOverlayLayer"
		_overlay_layer.layer = 100
		_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_overlay_layer)

		var overlay_root := Control.new()
		overlay_root.name = "OverlayRoot"
		overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _root != null and _root.theme != null:
			overlay_root.theme = _root.theme
		_overlay_layer.add_child(overlay_root)

		_toast_box = VBoxContainer.new()
		_toast_box.name = "ToastContainer"
		_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_toast_box.offset_left = -200.0
		_toast_box.offset_top = 18.0
		_toast_box.offset_right = 200.0
		_toast_box.offset_bottom = 240.0
		_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_box.add_theme_constant_override("separation", 8)
		overlay_root.add_child(_toast_box)

		_transition_rect = ColorRect.new()
		_transition_rect.name = "TransitionCurtain"
		_transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_transition_rect.color = Color(0.01, 0.02, 0.04, 0.0)
		_transition_rect.visible = false
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay_root.add_child(_transition_rect)
