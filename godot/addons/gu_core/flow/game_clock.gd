extends Node
## Gameplay, UI, and real-time channels. Gameplay scale lives here so hitstop never writes Engine.time_scale.

var world_seconds: float = 0.0

var _real_seconds: float = 0.0
var _gameplay_running: bool = false
var _scales: Dictionary = {}
var _next_timer_id: int = 1
var _timers: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var save_svc := get_node_or_null("/root/SaveService")
	if save_svc != null and save_svc.has_method("register_saveable"):
		save_svc.call("register_saveable", "clock", self)


func _process(delta: float) -> void:
	advance_frame(delta)


func gameplay_delta(frame_delta: float) -> float:
	if not _gameplay_running:
		return 0.0
	return maxf(0.0, frame_delta) * get_scale()


func ui_delta(frame_delta: float) -> float:
	return maxf(0.0, frame_delta)


func real_seconds() -> float:
	return _real_seconds


func get_scale() -> float:
	var scale := 1.0
	for source: StringName in _scales:
		scale *= float(_scales[source])
	return scale


func push_scale(source: StringName, scale: float) -> void:
	if source == &"":
		return
	_scales[source] = maxf(0.0, scale)


func pop_scale(source: StringName) -> void:
	_scales.erase(source)


func after_gameplay(seconds: float, callback: Callable) -> int:
	return _schedule(&"gameplay", seconds, callback)


func after_ui(seconds: float, callback: Callable) -> int:
	return _schedule(&"ui", seconds, callback)


func cancel(timer_id: int) -> void:
	for index in range(_timers.size() - 1, -1, -1):
		if int(_timers[index]["id"]) == timer_id:
			_timers.remove_at(index)
			return


func advance_frame(frame_delta: float) -> void:
	var safe := maxf(0.0, frame_delta)
	_real_seconds += safe
	var gameplay_step := gameplay_delta(safe)
	var ui_step := ui_delta(safe)
	world_seconds += gameplay_step
	var due: Array[Callable] = []
	var index := 0
	while index < _timers.size():
		var timer := _timers[index]
		var step := gameplay_step if (timer["channel"] as StringName) == &"gameplay" else ui_step
		timer["remaining"] = float(timer["remaining"]) - step
		if float(timer["remaining"]) <= 0.0:
			due.append(timer["callback"] as Callable)
			_timers.remove_at(index)
		else:
			index += 1
	for callback: Callable in due:
		if callback.is_valid():
			callback.call()


func set_gameplay_running(running: bool) -> void:
	_gameplay_running = running


func reset_world_time() -> void:
	world_seconds = 0.0


func export_state() -> Dictionary:
	return {"world_seconds": world_seconds}


func apply_state(data: Dictionary) -> void:
	world_seconds = maxf(0.0, float(data.get("world_seconds", 0.0)))


func _schedule(channel: StringName, seconds: float, callback: Callable) -> int:
	var timer_id := _next_timer_id
	_next_timer_id += 1
	if seconds <= 0.0:
		if callback.is_valid():
			callback.call()
		return timer_id
	_timers.append({
		"id": timer_id,
		"channel": channel,
		"remaining": seconds,
		"callback": callback,
	})
	return timer_id
