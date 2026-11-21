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
	for name in ["SettingsStore", "InputRouter", "AudioManager", "SaveService", "UIRouter", "GameFlow", "GameClock", "EventBus", "PoolService", "DevConsole", "PlatformService"]:
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

	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	_assert(packed_scene != null, "Starter main scene loads")
	if packed_scene != null:
		var scene := packed_scene.instantiate()
		var player := scene.get_node_or_null("Player")
		_assert(player is GuPlayer, "Starter main scene contains a GuPlayer")
		_assert(scene.get_node_or_null("CameraPivot") != null, "Starter main scene contains a camera rig")
		var boot_probe := scene.get_node_or_null("Player") as GuPlayer
		if boot_probe != null:
			scene.remove_child(boot_probe)
			get_root().add_child(boot_probe)
			_assert(boot_probe.get_locomotion() != null, "GuPlayer boots its locomotion state")
			_assert(InputMap.has_action("move_forward"), "GuPlayer registers movement actions")
			get_root().remove_child(boot_probe)
			boot_probe.free()
		scene.free()

	var content_quests := GameContent.quests()
	_assert(content_quests.size() == 1 and content_quests[0].id == &"meet_guide", "Starter content defines the sample quest")
	var guide_def := GameContent.dialogue(&"guide_intro")
	_assert(guide_def != null and guide_def.is_valid(), "Starter guide dialogue loads")
	var catalog := TranslationCatalog.new()
	_assert(catalog.load_dir("res://data") == OK, "Starter localization loads")
	_assert(catalog.message("zh", "Meet the Guide") == "与向导会面", "Starter content has a zh translation")
	catalog.unload()

	var full_scene := packed_scene.instantiate()
	get_root().add_child(full_scene)
	_assert(full_scene.get_node_or_null("Guide") != null, "Starter scene spawns the guide NPC")
	_assert(full_scene.get_node_or_null("GameplayHud") != null, "Starter scene spawns the gameplay HUD")
	var tracker := full_scene.get("_quests") as QuestTracker
	_assert(tracker != null and tracker.is_active(&"meet_guide"), "Starter starts the sample quest")
	var guide := full_scene.get_node_or_null("Guide") as DialogueInteractable
	_assert(guide != null and guide.interact(full_scene.get_node("Player")), "Guide interaction opens dialogue")
	_assert(tracker != null and tracker.is_completed(&"meet_guide"), "Guide dialogue completes the sample quest")
	get_root().remove_child(full_scene)
	full_scene.free()

	var stats := StatSet.new()
	stats.define_stat(&"hp", 100.0)
	_assert(stats.spend(&"hp", 25.0) and is_equal_approx(stats.get_value(&"hp"), 75.0), "StatSet works in starter")

	var inv := InventoryContainer.new()
	_assert(inv.add_item(&"coin", 10) == 0 and inv.count_item(&"coin") == 10, "InventoryContainer works in starter")

	var flags := FlagStore.new()
	var qt := QuestTracker.new()
	qt.bind(bus, flags, inv)
	qt.register_quest(QuestDef.from_dict({
		"id": "q_start",
		"objectives": [{"id": "ping", "type": "event", "event": "starter_ping", "target": 1}],
		"rewards": [{"type": "flag", "id": "q_done", "value": true}],
	}))
	qt.start_quest(&"q_start")
	if bus != null:
		bus.call("emit_event", &"starter_ping", {})
	_assert(qt.is_completed(&"q_start") and flags.get_bool(&"q_done"), "QuestTracker + FlagStore work in starter")
	qt.unbind()

	var talk_flags := FlagStore.new()
	var talk := DialogueRunner.new()
	talk.bind(talk_flags, null, null, null)
	var talk_view := talk.start(DialogueDef.from_dict({
		"id": "hi",
		"start": "a",
		"nodes": [{
			"id": "a",
			"text": "Hello",
			"effects": [{"type": "set_flag", "id": "spoke", "value": true}],
		}],
	}))
	_assert(bool(talk_view.get("ok", false)) and talk_flags.get_bool(&"spoke"), "DialogueRunner sets a flag")
	if ir != null:
		var was_gameplay := bool(ir.call("is_gameplay_active"))
		var box := DialogueBox.new()
		get_root().add_child(box)
		box.bind(talk_flags, null, null, null)
		_assert(box.start(DialogueDef.from_dict({
			"id": "box",
			"start": "a",
			"nodes": [{"id": "a", "speaker": "Guide", "text": "Ready"}],
		})), "DialogueBox opens")
		_assert(box.is_open() and not bool(ir.call("is_gameplay_active")), "DialogueBox pushes UI input context")
		var close_btn := box.find_child("CloseButton", true, false) as Button
		_assert(close_btn != null, "DialogueBox shows Close on a terminal line")
		if close_btn != null:
			close_btn.pressed.emit()
		_assert(not box.is_open() and bool(ir.call("is_gameplay_active")) == was_gameplay, "Closing DialogueBox restores gameplay input")
		box.free()

	var hc := HealthComponent.new()
	hc.max_hp = 30.0
	_assert(is_equal_approx(hc.apply_damage(12.0), 12.0) and is_equal_approx(hc.get_hp(), 18.0), "HealthComponent works in starter")
	var health_bar := StatBar.new()
	health_bar.bind_health(hc, "Health")
	_assert(health_bar.get_value_text() == "18 / 30", "StatBar follows HealthComponent in starter")
	health_bar.free()
	hc.free()

	var stats_bar := StatBar.new()
	stats_bar.bind_stat(stats, &"hp", "HP")
	_assert(stats_bar.get_value_text() == "75 / 100", "StatBar follows StatSet in starter")
	stats_bar.free()

	if ir != null:
		var stack_before := int(ir.call("get_stack_size"))
		var panel := InventoryPanel.new()
		get_root().add_child(panel)
		panel.bind_inventory(inv)
		var slot_rows := panel.get_row_texts()
		_assert(slot_rows.size() == 1 and slot_rows[0] == "Coin x10", "InventoryPanel renders slot rows in starter")
		panel.set_open(true)
		_assert(int(ir.call("get_active_context")) == 1, "InventoryPanel pushes UI input context")
		panel.set_open(false)
		_assert(int(ir.call("get_stack_size")) == stack_before, "InventoryPanel pops UI input context")
		get_root().remove_child(panel)
		panel.free()

	var quest_hud := QuestHud.new()
	get_root().add_child(quest_hud)
	var quest_tracker := QuestTracker.new()
	quest_hud.bind_tracker(quest_tracker)
	quest_tracker.register_quest(QuestDef.from_dict({
		"id": "q_hud",
		"title": "Starter Quest",
		"objectives": [{"id": "step", "type": "event", "event": "starter_ping", "description": "Ping", "target": 1}],
	}))
	quest_tracker.start_quest(&"q_hud")
	_assert("Ping 0/1" in "\n".join(quest_hud.get_row_texts()), "QuestHud shows objective progress")
	quest_tracker.handle_event(&"starter_ping", {})
	_assert("COMPLETE" in "\n".join(quest_hud.get_row_texts()), "QuestHud shows completion text")
	quest_hud.acknowledge_completion(&"q_hud")
	_assert(not ("COMPLETE" in "\n".join(quest_hud.get_row_texts())), "QuestHud completion can be acknowledged")
	quest_tracker.unbind()
	get_root().remove_child(quest_hud)
	quest_hud.free()

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
		"res://addons/gu_core/ui/save_slots_panel.tscn",
	]:
		var packed := load(ui_path) as PackedScene
		_assert(packed is PackedScene, "Starter UI loads: %s" % ui_path)
		if packed != null:
			var ui_inst := packed.instantiate() as Control
			_assert(ui_inst != null and ui_inst.get_node_or_null("%Panel") != null, "Starter UI exposes %%Panel: %s" % ui_path)
			ui_inst.free()
