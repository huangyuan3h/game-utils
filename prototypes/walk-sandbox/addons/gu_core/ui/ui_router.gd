extends Node
## Overlay UI stack router that coordinates screen instances and InputRouter contexts.

signal screen_pushed(screen_id: StringName)
signal screen_popped(screen_id: StringName)
signal stack_emptied

const DEFAULT_THEME_PATH := "res://addons/gu_core/ui/protoss/protoss_theme.tres"
const FALLBACK_THEME_PATH := "res://addons/gu_core/ui/default_theme.tres"

var _registry: Dictionary = {} ## StringName -> PackedScene
var _stack: Array[Dictionary] = [] ## [{"id": StringName, "node": Control, "owner": StringName}]
var _layer: CanvasLayer = null
var _root: Control = null


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

	if not _stack.is_empty():
		var prev := _stack[_stack.size() - 1]["node"] as Control
		if is_instance_valid(prev):
			prev.visible = false

	_root.add_child(inst)
	var owner := StringName("ui:" + String(screen_id) + ":" + str(inst.get_instance_id()))
	_stack.append({"id": screen_id, "node": inst, "owner": owner})

	var input_router := get_node_or_null("/root/InputRouter")
	if input_router != null and input_router.has_method("push_context"):
		input_router.call("push_context", input_ctx, owner)

	if inst.has_method("on_ui_enter"):
		inst.call("on_ui_enter", params)
	screen_pushed.emit(screen_id)
	return inst


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


func _ensure_layer() -> void:
	if _layer != null and is_instance_valid(_layer):
		return
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
	elif ResourceLoader.exists(FALLBACK_THEME_PATH):
		_root.theme = load(FALLBACK_THEME_PATH) as Theme
	_layer.add_child(_root)
