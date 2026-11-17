extends Node
## Centralized input context stack preventing gameplay/camera input leakage during UI or modals.

signal context_changed(active_context: int, stack_size: int)

enum Context { GAMEPLAY, UI, MODAL, CUTSCENE }

var _stack: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func push_context(ctx: Context, owner: StringName) -> void:
	if owner == &"":
		push_warning("InputRouter.push_context called with empty owner.")
		return
	for i in range(_stack.size() - 1, -1, -1):
		if _stack[i]["owner"] == owner:
			_stack.remove_at(i)
	_stack.append({"owner": owner, "context": int(ctx)})
	context_changed.emit(get_active_context(), _stack.size())


func pop_context(owner: StringName) -> void:
	var changed := false
	for i in range(_stack.size() - 1, -1, -1):
		if _stack[i]["owner"] == owner:
			_stack.remove_at(i)
			changed = true
	if changed:
		context_changed.emit(get_active_context(), _stack.size())


func clear_contexts() -> void:
	if _stack.is_empty():
		return
	_stack.clear()
	context_changed.emit(get_active_context(), 0)


func get_active_context() -> Context:
	if _stack.is_empty():
		return Context.GAMEPLAY
	return int(_stack[_stack.size() - 1]["context"]) as Context


func get_stack_size() -> int:
	return _stack.size()


func is_gameplay_active() -> bool:
	return get_active_context() == Context.GAMEPLAY


func is_ui_active() -> bool:
	var ctx := get_active_context()
	return ctx == Context.UI or ctx == Context.MODAL


func allow_debug() -> bool:
	return get_active_context() != Context.MODAL
