extends Node
## Lightweight decoupled publish/subscribe event bus for cross-system gameplay events.

signal event_emitted(event_name: StringName, payload: Dictionary)

var _listeners: Dictionary = {} ## StringName -> Array[Callable]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func subscribe(event_name: StringName, callback: Callable) -> void:
	if event_name == &"" or not callback.is_valid():
		return
	var list: Array = _listeners.get(event_name, []) as Array
	for existing: Callable in list:
		if existing == callback:
			return
	list.append(callback)
	_listeners[event_name] = list


func unsubscribe(event_name: StringName, callback: Callable) -> void:
	if not _listeners.has(event_name):
		return
	var list: Array = _listeners[event_name] as Array
	for i in range(list.size() - 1, -1, -1):
		if list[i] == callback:
			list.remove_at(i)
	if list.is_empty():
		_listeners.erase(event_name)


func unsubscribe_all(target: Object) -> void:
	if target == null:
		return
	var empty_keys: Array[StringName] = []
	for event_name: StringName in _listeners:
		var list: Array = _listeners[event_name] as Array
		for i in range(list.size() - 1, -1, -1):
			var cb: Callable = list[i] as Callable
			if not cb.is_valid() or cb.get_object() == target:
				list.remove_at(i)
		if list.is_empty():
			empty_keys.append(event_name)
	for k in empty_keys:
		_listeners.erase(k)


func emit_event(event_name: StringName, payload: Dictionary = {}) -> void:
	if event_name == &"":
		return
	if _listeners.has(event_name):
		var list: Array = _listeners[event_name] as Array
		var snapshot: Array = list.duplicate()
		var pruned := false
		for i in range(list.size() - 1, -1, -1):
			if not (list[i] as Callable).is_valid():
				list.remove_at(i)
				pruned = true
		if pruned and list.is_empty():
			_listeners.erase(event_name)

		for cb: Callable in snapshot:
			if cb.is_valid():
				cb.call(payload)

	event_emitted.emit(event_name, payload)


func clear_subscribers(event_name: StringName = &"") -> void:
	if event_name == &"":
		_listeners.clear()
	else:
		_listeners.erase(event_name)


func get_subscriber_count(event_name: StringName) -> int:
	if not _listeners.has(event_name):
		return 0
	var list: Array = _listeners[event_name] as Array
	for i in range(list.size() - 1, -1, -1):
		if not (list[i] as Callable).is_valid():
			list.remove_at(i)
	if list.is_empty():
		_listeners.erase(event_name)
		return 0
	return list.size()
