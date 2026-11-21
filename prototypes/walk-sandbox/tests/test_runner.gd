extends SceneTree
## Headless test entry point. The suites under tests/suites/ run in this order.
##
## Run with:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path prototypes/walk-sandbox --script res://tests/test_runner.gd

const SUITES := [
	preload("res://tests/suites/terrain_suite.gd"),
	preload("res://tests/suites/character_suite.gd"),
	preload("res://tests/suites/core_suite.gd"),
	preload("res://tests/suites/world_suite.gd"),
	preload("res://tests/suites/content_suite.gd"),
	preload("res://tests/suites/systems_suite.gd"),
	preload("res://tests/suites/ui_suite.gd"),
	preload("res://tests/suites/finale_suite.gd"),
]

var _failures: Array[String] = []
var _passed: int = 0
var _quit_through_flow: bool = false
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	for suite_script in SUITES:
		var suite: RefCounted = suite_script.new()
		suite.set("t", self)
		suite.call("run_all")
	if _failures.is_empty():
		print("[PASS] All %d assertions passed across %d suites." % [_passed, SUITES.size()])
		if _quit_through_flow:
			var flow := get_root().get_node_or_null("GameFlow")
			if flow != null and flow.has_method("quit_game"):
				flow.call("quit_game")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + f)
		print("[FAIL] %d assertion(s) failed (%d passed)." % [_failures.size(), _passed])
		quit(1)
	return true


func record_assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(msg)


func no_failures() -> bool:
	return _failures.is_empty()
