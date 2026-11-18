extends Node
## Centralized input context stack and rebindable action registry backed by SettingsStore.

signal context_changed(active_context: int, stack_size: int)
signal bindings_changed(action: StringName)

enum Context { GAMEPLAY, UI, MODAL, CUTSCENE }
enum Device { KEYBOARD, XBOX, PLAYSTATION }

var settings_store: Node = null
var device: Device = Device.KEYBOARD

var _stack: Array[Dictionary] = []
var _registered_actions: Dictionary = {} ## StringName -> {"defaults": Array[int], "label": String, "current_key": int}
var _action_order: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_settings_store()


func _input(event: InputEvent) -> void:
	note_input_event(event)


func note_input_event(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var pad_name := Input.get_joy_name(event.device).to_lower()
		if pad_name.contains("playstation") or pad_name.contains("dualshock") or pad_name.contains("dualsense"):
			device = Device.PLAYSTATION
		else:
			device = Device.XBOX
	elif event is InputEventKey or event is InputEventMouse:
		device = Device.KEYBOARD


func glyph_name(action: StringName) -> String:
	if device == Device.PLAYSTATION:
		return "Cross" if action == &"interact" else "Pad"
	if device == Device.XBOX:
		return "A" if action == &"interact" else "Pad"
	return get_action_key_label(action)


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


func register_action(action: StringName, default_keys: Array, label: String = "") -> void:
	if action == &"":
		return
	var defaults: Array[int] = []
	for k in default_keys:
		defaults.append(int(k))

	if not _registered_actions.has(action):
		_action_order.append(action)

	var primary_default := defaults[0] if not defaults.is_empty() else 0
	var saved := _get_saved_bindings()
	var key_str := String(action)
	var chosen_key := int(saved[key_str]) if saved.has(key_str) else primary_default

	_registered_actions[action] = {
		"defaults": defaults,
		"label": label if label != "" else key_str,
		"current_key": chosen_key,
	}

	if saved.has(key_str):
		_apply_key_to_input_map(action, [chosen_key])
	else:
		_ensure_default_keys(action, defaults)


func rebind_action_key(action: StringName, physical_keycode: int, allow_swap: bool = true) -> Dictionary:
	if not _registered_actions.has(action):
		return {"ok": false, "error": "unregistered_action", "conflict": &""}
	if physical_keycode <= 0:
		return {"ok": false, "error": "invalid_keycode", "conflict": &""}

	var prev_key := int((_registered_actions[action] as Dictionary)["current_key"])
	var conflict_action := &""
	for other: StringName in _registered_actions:
		if other == action:
			continue
		if int((_registered_actions[other] as Dictionary)["current_key"]) == physical_keycode:
			conflict_action = other
			break

	if conflict_action != &"" and not allow_swap:
		return {"ok": false, "error": "conflict", "conflict": conflict_action}

	if conflict_action != &"":
		(_registered_actions[conflict_action] as Dictionary)["current_key"] = prev_key
		_apply_key_to_input_map(conflict_action, [prev_key] if prev_key > 0 else [])
		bindings_changed.emit(conflict_action)

	(_registered_actions[action] as Dictionary)["current_key"] = physical_keycode
	_apply_key_to_input_map(action, [physical_keycode])
	_save_bindings_to_store()
	bindings_changed.emit(action)

	return {
		"ok": true,
		"conflict": &"",
		"swapped_with": conflict_action,
	}


func reset_bindings() -> void:
	for action: StringName in _action_order:
		var entry := _registered_actions[action] as Dictionary
		var defaults: Array[int] = entry["defaults"] as Array[int]
		var primary := defaults[0] if not defaults.is_empty() else 0
		entry["current_key"] = primary
		_apply_key_to_input_map(action, defaults)
		bindings_changed.emit(action)

	var store := _get_store()
	if store != null and store.has_method("set_value"):
		store.call("set_value", "input_bindings", {})


func get_action_keycode(action: StringName) -> int:
	if _registered_actions.has(action):
		return int((_registered_actions[action] as Dictionary)["current_key"])
	var action_name := String(action)
	if InputMap.has_action(action_name):
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventKey:
				return int((ev as InputEventKey).physical_keycode)
	return 0


func get_action_key_label(action: StringName) -> String:
	var code := get_action_keycode(action)
	if code <= 0:
		return "Unbound"
	return OS.get_keycode_string(code as Key)


func list_registered_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for action: StringName in _action_order:
		var entry := _registered_actions[action] as Dictionary
		out.append({
			"action": action,
			"label": str(entry["label"]),
			"keycode": int(entry["current_key"]),
			"key_label": get_action_key_label(action),
		})
	return out


func _ensure_default_keys(action: StringName, defaults: Array[int]) -> void:
	var action_name := String(action)
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for code in defaults:
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		if not InputMap.action_has_event(action_name, ev):
			InputMap.action_add_event(action_name, ev)


func _apply_key_to_input_map(action: StringName, keys: Array) -> void:
	var action_name := String(action)
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for ev in InputMap.action_get_events(action_name).duplicate():
		if ev is InputEventKey:
			InputMap.action_erase_event(action_name, ev)
	for code in keys:
		if int(code) <= 0:
			continue
		var nev := InputEventKey.new()
		nev.physical_keycode = int(code) as Key
		InputMap.action_add_event(action_name, nev)


func _get_store() -> Node:
	if settings_store != null and is_instance_valid(settings_store):
		return settings_store
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/SettingsStore")


func _get_saved_bindings() -> Dictionary:
	var store := _get_store()
	if store == null or not store.has_method("get_value"):
		return {}
	var raw: Variant = store.call("get_value", "input_bindings", {})
	return raw as Dictionary if raw is Dictionary else {}


func _save_bindings_to_store() -> void:
	var store := _get_store()
	if store == null or not store.has_method("set_value"):
		return
	var packed: Dictionary = {}
	for action: StringName in _registered_actions:
		var entry := _registered_actions[action] as Dictionary
		packed[String(action)] = int(entry["current_key"])
	store.call("set_value", "input_bindings", packed)


func _connect_settings_store() -> void:
	var store := _get_store()
	if store != null and store.has_signal("settings_loaded"):
		if not store.is_connected("settings_loaded", Callable(self, "_on_settings_loaded")):
			store.connect("settings_loaded", Callable(self, "_on_settings_loaded"))


func _on_settings_loaded() -> void:
	var saved := _get_saved_bindings()
	for action: StringName in _action_order:
		var key_str := String(action)
		var entry := _registered_actions[action] as Dictionary
		if saved.has(key_str):
			var code := int(saved[key_str])
			entry["current_key"] = code
			_apply_key_to_input_map(action, [code])
		else:
			var defaults: Array[int] = entry["defaults"] as Array[int]
			var primary := defaults[0] if not defaults.is_empty() else 0
			entry["current_key"] = primary
			_apply_key_to_input_map(action, defaults)
		bindings_changed.emit(action)
