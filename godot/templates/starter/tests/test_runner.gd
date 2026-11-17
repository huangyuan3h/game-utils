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
	for name in ["SettingsStore", "InputRouter", "AudioManager", "SaveService", "UIRouter", "GameFlow", "EventBus", "PoolService", "DevConsole"]:
		_assert(get_root().get_node_or_null(name) != null, "Autoload %s present" % name)

	var console := get_root().get_node_or_null("DevConsole")
	if console != null:
		_assert(str(console.call("execute", "echo hello")) == "hello", "DevConsole executes built-in echo")

	var bus := get_root().get_node_or_null("EventBus")
	if bus != null:
		var hits := [0]
		var cb := func(_p: Dictionary) -> void: hits[0] += 1
		bus.call("subscribe", &"starter_ping", cb)
		bus.call("emit_event", &"starter_ping", {})
		bus.call("unsubscribe", &"starter_ping", cb)
		_assert(hits[0] == 1, "EventBus delivers and unsubscribes events")

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

	var ctrl := CharacterActionController.new()
	_assert(ctrl.try_start(&"gather", {"swim_amt": 0.0}), "CharacterActionController works in starter without CharacterLocomotion")

	var stats := StatSet.new()
	stats.define_stat(&"hp", 100.0)
	_assert(stats.spend(&"hp", 25.0) and is_equal_approx(stats.get_value(&"hp"), 75.0), "StatSet works in starter")

	var inv := InventoryContainer.new()
	_assert(inv.add_item(&"coin", 10) == 0 and inv.count_item(&"coin") == 10, "InventoryContainer works in starter")

	var table_path := "user://starter_table.json"
	var tf := FileAccess.open(table_path, FileAccess.WRITE)
	tf.store_string('{"rows":[{"id":"potion","val":20}]}')
	tf.close()
	var rows := DataTableLoader.load_table(table_path)
	_assert(rows.size() == 1 and int(DataTableLoader.find_by_id(rows, "potion").get("val", 0)) == 20, "DataTableLoader works in starter")
	DirAccess.remove_absolute(table_path)

	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_assert(main_scene != null, "Starter main.tscn loads")
	for ui_path in [
		"res://scenes/ui/title_screen.tscn",
		"res://scenes/ui/pause_menu.tscn",
		"res://scenes/ui/settings_panel.tscn",
	]:
		_assert(load(ui_path) is PackedScene, "Starter UI loads: %s" % ui_path)
