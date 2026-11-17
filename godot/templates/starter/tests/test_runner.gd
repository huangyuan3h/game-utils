extends SceneTree
## Smoke unit test runner for starter projects scaffolded via `gu init`.

var _failures: Array[String] = []
var _passed: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_all()
	if _failures.is_empty():
		print("[PASS] Starter skeleton tests passed (%d assertions)." % _passed)
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + f)
		quit(1)
	return true


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failures.append(msg)


func _run_all() -> void:
	for name in ["SettingsStore", "InputRouter", "AudioManager", "SaveService", "UIRouter", "GameFlow"]:
		_assert(get_root().get_node_or_null(name) != null, "Autoload %s present" % name)

	var am := get_root().get_node_or_null("AudioManager")
	if am != null:
		var stream := AudioStreamWAV.new()
		var p3d := am.call("play_sfx_at", Vector3(2.0, 1.0, -3.0), stream, -3.0) as AudioStreamPlayer3D
		_assert(p3d != null and p3d.stream == stream, "AudioManager.play_sfx_at allocates 3D player")

	var ui := get_root().get_node_or_null("UIRouter")
	var ir := get_root().get_node_or_null("InputRouter")
	if ui != null and ir != null:
		ui.call("show_toast", "Starter smoke toast", 0.5, &"info")
		_assert(int(ui.call("get_active_toast_count")) >= 1, "UIRouter.show_toast activates banner")
		ui.call("clear_toasts")

		var dlg := ui.call("show_confirm", "Confirm", "Proceed?", Callable()) as Control
		_assert(dlg != null, "UIRouter.show_confirm creates dialog")
		_assert(not bool(ir.call("allow_debug")), "Modal confirm pushes MODAL input context")
		dlg.call("cancel")
		_assert(bool(ir.call("allow_debug")), "Cancelling modal restores previous input context")

		ui.call("fade_out", 0.0)
		_assert(is_equal_approx(float(ui.call("get_transition_alpha")), 1.0), "UIRouter.fade_out reaches opaque")
		ui.call("fade_in", 0.0)
		_assert(is_equal_approx(float(ui.call("get_transition_alpha")), 0.0), "UIRouter.fade_in returns transparent")

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_assert(main_scene != null, "Starter main.tscn loads")
	for ui_path in [
		"res://scenes/ui/title_screen.tscn",
		"res://scenes/ui/pause_menu.tscn",
		"res://scenes/ui/settings_panel.tscn",
	]:
		_assert(load(ui_path) is PackedScene, "Starter UI loads: %s" % ui_path)
