class_name JuiceBus
extends Node
## Turns combat_hit events into hitstop, camera shake, and a floating-text count.

const HITSTOP_SOURCE := &"hitstop"
const HITSTOP_SCALE := 0.2
const HITSTOP_SECONDS := 0.05

var camera: CameraRig = null
var floater_count: int = 0
var last_amount: float = 0.0
var shake_count: int = 0
var hitstop_remaining: float = 0.0

var _callback: Callable = Callable()


func _ready() -> void:
	_callback = _on_combat_hit
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method("subscribe"):
		bus.call("subscribe", &"combat_hit", _callback)


func _exit_tree() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and _callback.is_valid() and bus.has_method("unsubscribe"):
		bus.call("unsubscribe", &"combat_hit", _callback)
	_end_hitstop()


func _on_combat_hit(payload: Dictionary) -> void:
	last_amount = float(payload.get("amount", 0.0))
	floater_count += 1
	shake_count += 1
	if camera != null:
		camera.add_shake(0.25, 0.12)
	hitstop_remaining = HITSTOP_SECONDS
	var clock := _clock()
	if clock != null and clock.has_method("push_scale"):
		clock.call("push_scale", HITSTOP_SOURCE, HITSTOP_SCALE)


func advance(delta: float) -> void:
	if hitstop_remaining <= 0.0:
		return
	# Count the window in the caller's unscaled delta so hitstop does not stretch itself.
	hitstop_remaining = maxf(0.0, hitstop_remaining - maxf(0.0, delta))
	if hitstop_remaining <= 0.0:
		_end_hitstop()


func _end_hitstop() -> void:
	hitstop_remaining = 0.0
	var clock := _clock()
	if clock != null and clock.has_method("pop_scale"):
		clock.call("pop_scale", HITSTOP_SOURCE)


func _clock() -> Node:
	return get_node_or_null("/root/GameClock")
