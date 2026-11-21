extends "res://tests/support/test_suite_base.gd"
## Actions, IK, events, camera, stats, data tables, pools, input rebinding, and quests.


func run_all() -> void:
	_test_character_action_architecture()
	_test_work_ik_and_tool_visual()
	_test_event_bus()
	_test_camera_rig_shake()
	_test_stat_set_and_inventory()
	_test_data_table_loader()
	_test_save_migrations_and_backup()
	_test_pool_service_and_scene_loader()
	_test_input_rebinding_and_dev_console()
	_test_flags_and_quest_tracker()
	_test_dialogue()


func _test_character_action_architecture() -> void:
	var reg := CharacterActionRegistry.create_default()
	for id: StringName in [&"gather", &"mine", &"chop", &"build"]:
		_assert(reg.has_action(id), "Default registry includes action '%s'" % String(id))
		var spec := reg.get_spec(id)
		_assert(spec != null and spec.is_valid(), "Action spec '%s' is valid" % String(id))

	var bad_spec := CharacterActionSpec.new({"id": "", "duration": 0.0})
	_assert(not reg.register(bad_spec), "Registry rejects invalid CharacterActionSpec")

	var custom := CharacterActionSpec.new({
		"id": "fish",
		"display_name": "FISH",
		"duration": 0.8,
		"hit_phases": [0.5],
		"move_policy": CharacterActionSpec.MovePolicy.LOCK,
		"allow_in_water": true,
		"max_water_depth": 1.0,
	})
	_assert(reg.register(custom) and reg.has_action(&"fish"), "Registry supports dynamic custom action registration")
	reg.unregister(&"fish")
	_assert(not reg.has_action(&"fish"), "Registry supports unregistering actions")

	var ctrl := CharacterActionController.new()
	var loco := CharacterLocomotion.new()
	var terrain := MockTerrain.new()
	terrain.ground_y = 2.0
	terrain.water_y = -INF
	terrain.biome = MapTypes.Biome.GRASS
	loco.step(Vector3.ZERO, Vector3.ZERO, Vector2.ZERO, false, terrain, 0.05)

	var started_log: Array[StringName] = []
	var beat_log: Array[Array] = []
	var done_log: Array[Array] = []
	var cancel_log: Array[Array] = []
	ctrl.action_started.connect(func(id: StringName, _s: CharacterActionSpec) -> void: started_log.append(id))
	ctrl.action_beat.connect(func(id: StringName, b: int, c: int) -> void: beat_log.append([id, b, c]))
	ctrl.action_completed.connect(func(id: StringName, c: int) -> void: done_log.append([id, c]))
	ctrl.action_cancelled.connect(func(id: StringName, r: StringName) -> void: cancel_log.append([id, r]))

	# Single-cycle tap completion + double-beat build action
	_assert(ctrl.try_start(&"build", loco, {
		"origin_pos": Vector3.ZERO,
		"target_pos": Vector3(2.0, 0.0, 0.0),
	}), "Build action starts on dry ground")
	_assert(ctrl.is_acting(), "ActionController reports is_acting() after start")
	_assert(ctrl.has_target_yaw and is_equal_approx(ctrl.target_yaw, PI * 0.5), "ActionController computes target_yaw toward target_pos")
	_assert(started_log.size() == 1 and started_log[0] == &"build", "action_started signal fires once")

	for _i in 30:
		var frame := ctrl.step(0.05, loco, Vector2.ZERO, false)
		var lres := loco.step(
			Vector3.ZERO,
			Vector3(1.0, 0.0, 0.0),
			Vector2.ZERO,
			false,
			terrain,
			0.05,
			float(frame.get("move_scale", 1.0)),
			float(frame.get("facing_override_yaw", 0.0)) if bool(frame.get("has_facing_override", false)) else NAN
		)
		if not ctrl.is_acting():
			_assert((lres["velocity"] as Vector3).length() < 1.0, "Locomotion decelerates while action locks movement")
			break
	_assert(not ctrl.is_acting(), "Single tap action finishes cleanly after 1 cycle")
	_assert(beat_log.size() == 2, "Build action emits 2 hit beats per cycle")
	_assert(done_log.size() == 1 and int(done_log[0][1]) == 1, "action_completed reports 1 finished cycle")

	# Continuous hold looping (mine) + movement interrupt
	beat_log.clear()
	_assert(ctrl.try_start(&"mine", loco), "Mine action starts")
	for _i in 30:
		ctrl.step(0.05, loco, Vector2.ZERO, true)
	_assert(ctrl.is_acting() and ctrl.cycle_count >= 1, "Holding input loops mine action past cycle 1")
	_assert(beat_log.size() >= 1, "Looped mine action emits hit beats")

	var moved_frame := ctrl.step(0.016, loco, Vector2(1.0, 0.0), false)
	_assert(not bool(moved_frame.get("is_acting", true)), "Movement cancels CANCEL_ON_MOVE action immediately")
	_assert(cancel_log.size() == 1 and cancel_log[0][1] == &"moved", "Cancel reason is 'moved'")

	# Environment guards: deep water & climbing
	loco.swim_amt = 0.8
	loco.water_depth = 1.3
	_assert(not ctrl.try_start(&"chop", loco), "Cannot start chop while swimming in deep water")
	_assert(ctrl.last_cancel_reason == &"swimming", "Blocked reason is 'swimming'")

	loco.swim_amt = 0.0
	loco.water_depth = 0.0
	loco.is_climbing = true
	loco.climb_amt = 0.8
	_assert(not ctrl.try_start(&"gather", loco), "Cannot start gather while climbing steep cliff")
	_assert(ctrl.last_cancel_reason == &"climbing", "Blocked reason is 'climbing'")


func _test_work_ik_and_tool_visual() -> void:
	var packed := load("res://assets/models/quaternius/AnimatedHuman.fbx") as PackedScene
	_assert(packed != null, "AnimatedHuman.fbx loads for WorkIKSolver test")
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_assert(skel != null, "AnimatedHuman.fbx exposes Skeleton3D")
	if skel == null:
		model.free()
		return

	var ik := WorkIKSolver.new()
	ik.bind_skeleton(skel)
	_assert(ik.has_valid_rig(), "WorkIKSolver binds to AnimatedHuman Skeleton3D")

	for profile: StringName in [&"gather", &"mine", &"chop", &"build"]:
		for phase in [0.1, 0.45, 0.75]:
			ik.apply_work(profile, phase, 1.0, 0.05)
	var hips_idx := skel.find_bone("Hips")
	var hips_q := skel.get_bone_pose_rotation(hips_idx)
	_assert(hips_q.is_normalized() and is_finite(hips_q.x), "WorkIKSolver produces valid normalized bone rotations")

	var tool_vis := HandToolVisual.new()
	tool_vis.bind_skeleton(skel)
	var attach := skel.find_child("RightHandToolAttachment", false, false) as BoneAttachment3D
	_assert(attach != null and attach.bone_name == "RightHand", "HandToolVisual attaches BoneAttachment3D to RightHand")
	tool_vis.set_active_tool(CharacterActionSpec.ToolType.AXE)
	var axe_node := attach.find_child("Axe", true, false) as Node3D
	var pick_node := attach.find_child("Pickaxe", true, false) as Node3D
	_assert(axe_node != null and axe_node.visible, "Axe tool becomes visible when active")
	_assert(pick_node != null and not pick_node.visible, "Pickaxe tool stays hidden when Axe is active")
	tool_vis.cleanup()
	tool_vis.free()
	model.free()


func _test_event_bus() -> void:
	var bus_autoload := get_root().get_node_or_null("EventBus")
	_assert(bus_autoload != null, "Autoload EventBus exists on SceneTree root")

	var bus := EventBusScript.new()
	var received: Array[Dictionary] = []
	var cb := func(payload: Dictionary) -> void: received.append(payload)

	bus.subscribe(&"quest_step", cb)
	bus.subscribe(&"quest_step", cb) # idempotent duplicate check
	_assert(bus.get_subscriber_count(&"quest_step") == 1, "EventBus avoids duplicate callback subscriptions")

	bus.emit_event(&"quest_step", {"step": 2})
	_assert(received.size() == 1 and int(received[0]["step"]) == 2, "EventBus delivers payload to subscribers")

	bus.unsubscribe(&"quest_step", cb)
	bus.emit_event(&"quest_step", {"step": 3})
	_assert(received.size() == 1, "EventBus stops delivering after unsubscribe")

	var target := Node.new()
	var obj_cb := Callable(target, "set_name")
	bus.subscribe(&"rename_evt", obj_cb)
	bus.unsubscribe_all(target)
	_assert(bus.get_subscriber_count(&"rename_evt") == 0, "EventBus.unsubscribe_all removes target callbacks")
	target.free()
	bus.free()


func _test_camera_rig_shake() -> void:
	var host := Node3D.new()
	get_root().add_child(host)

	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	host.add_child(rig)

	var target := Node3D.new()
	target.position = Vector3(5.0, 1.0, -3.0)
	host.add_child(target)

	rig.set_target(target)
	_assert(rig.global_position.is_equal_approx(Vector3(5.0, 1.0, -3.0) + CameraRig.DEFAULT_OFFSET), "CameraRig snaps to target on set_target")

	rig.set_zoom(0.2)
	_assert(is_equal_approx(rig.get_zoom(), CameraRig.ZOOM_MIN), "CameraRig clamps zoom min")
	rig.set_zoom(1.0)

	rig.set_yaw(PI * 0.5)
	_assert(is_equal_approx(rig.get_yaw(), PI * 0.5), "CameraRig stores yaw")
	rig._process(2.0)
	var orbited := target.global_position + Basis(Vector3.UP, PI * 0.5) * CameraRig.DEFAULT_OFFSET
	_assert(rig.global_position.distance_to(orbited) < 0.05, "CameraRig orbits around the target")
	var ahead := rig.world_move(Vector2(0.0, -1.0))
	_assert(ahead.distance_to(Vector2(-1.0, 0.0)) < 0.02, "Forward follows the camera yaw")
	rig.set_yaw(0.0)

	rig.add_shake(0.5, 0.4)
	_assert(rig.get_shake_remaining() > 0.35, "CameraRig.add_shake schedules impulse")
	rig._process(0.1)
	_assert(rig.get_shake_remaining() < 0.35, "CameraRig decays shake over time")
	rig._process(0.5)
	_assert(is_equal_approx(cam.h_offset, 0.0) and is_equal_approx(cam.v_offset, 0.0), "CameraRig resets offsets after shake ends")

	rig.clear_target()
	host.free()


func _test_stat_set_and_inventory() -> void:
	# Decoupled Dictionary loco check for CharacterActionController
	var ctrl := CharacterActionController.new()
	_assert(ctrl.try_start(&"gather", {"swim_amt": 0.0, "is_climbing": false, "water_depth": 0.0}), "ActionController accepts Dictionary loco state")
	_assert(not ctrl.try_start(&"chop", {"swim_amt": 0.9, "water_depth": 1.2}), "ActionController blocks swimming via Dictionary state")

	var stats := StatSet.new()
	stats.define_stat(&"hp", 100.0, 80.0)
	stats.define_stat(&"stamina", 50.0)
	_assert(is_equal_approx(stats.get_value(&"hp"), 80.0), "StatSet initializes custom initial value")
	_assert(stats.spend(&"stamina", 20.0) and is_equal_approx(stats.get_value(&"stamina"), 30.0), "StatSet.spend deducts atomically")
	_assert(not stats.spend(&"stamina", 40.0) and is_equal_approx(stats.get_value(&"stamina"), 30.0), "StatSet.spend fails safely on insufficient resource")

	stats.add_modifier(&"hp", &"armor_buff", 50.0, 1.0)
	_assert(is_equal_approx(stats.get_max(&"hp"), 150.0), "StatSet additive modifier scales max")
	stats.set_value(&"hp", 150.0)
	stats.remove_modifier(&"hp", &"armor_buff")
	_assert(is_equal_approx(stats.get_value(&"hp"), 100.0), "Removing modifier clamps current value to new max")

	var inv := InventoryContainer.new(2, 10)
	var wood := ItemDef.new()
	wood.id = &"wood"
	wood.display_name = "Wood"
	wood.max_stack = 5
	inv.register_item(wood)

	var leftover := inv.add_item(&"wood", 12)
	_assert(leftover == 2, "InventoryContainer respects max_slots=2 and max_stack=5 (10 stored, 2 leftover)")
	_assert(inv.count_item(&"wood") == 10 and inv.has_item(&"wood", 10), "InventoryContainer sums stacks accurately")
	_assert(not inv.remove_item(&"wood", 11) and inv.count_item(&"wood") == 10, "Atomic remove_item leaves inventory intact when short")
	_assert(inv.remove_item(&"wood", 7) and inv.count_item(&"wood") == 3, "remove_item drains across stacks accurately")
	_assert(inv.can_add(&"wood", 7) and not inv.can_add(&"wood", 8), "InventoryContainer.can_add respects leftover stack space and free slots")
	_assert(inv.can_add(&"ore", 10) and not inv.can_add(&"ore", 11), "InventoryContainer.can_add uses default max stack for unregistered items")
	_assert(inv.count_item(&"wood") == 3, "InventoryContainer.can_add does not mutate slots")

	# SaveService round-trip for StatSet + InventoryContainer
	var tmp_dir := "user://test_saves_p1"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	var err := svc.save_slot("p1_slot", {
		"world": {"seed": 11},
		"stats": stats.export_state(),
		"inventory": inv.export_state(),
	})
	_assert(err == OK, "SaveService writes StatSet + InventoryContainer state")
	var loaded := svc.load_slot("p1_slot")
	_assert(bool(loaded.get("ok", false)), "SaveService reloads P1 slot")

	var stats2 := StatSet.new()
	stats2.apply_state((loaded["data"] as Dictionary).get("stats", {}) as Dictionary)
	_assert(is_equal_approx(stats2.get_value(&"stamina"), 30.0), "StatSet restores stamina value across SaveService")

	var inv2 := InventoryContainer.new()
	inv2.apply_state((loaded["data"] as Dictionary).get("inventory", {}) as Dictionary)
	_assert(inv2.count_item(&"wood") == 3 and inv2.max_slots == 2, "InventoryContainer restores items and max_slots across SaveService")

	svc.delete_slot("p1_slot")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()


func _test_data_table_loader() -> void:
	var table_path := "user://test_items_p2.json"
	var f := FileAccess.open(table_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 1,
		"table": "items",
		"rows": [
			{"id": "herb", "heal": 15},
			{"id": "crystal", "heal": 50},
		],
	}))
	f.close()

	var rows := DataTableLoader.load_table(table_path)
	_assert(rows.size() == 2, "DataTableLoader loads compiled JSON table rows")
	var by_id := DataTableLoader.index_by_id(rows)
	_assert(by_id.has("crystal") and int((by_id["crystal"] as Dictionary)["heal"]) == 50, "DataTableLoader.index_by_id indexes rows")
	var herb := DataTableLoader.find_by_id(rows, "herb")
	_assert(int(herb.get("heal", 0)) == 15, "DataTableLoader.find_by_id finds row by id")

	if FileAccess.file_exists(table_path):
		DirAccess.remove_absolute(table_path)


func _test_save_migrations_and_backup() -> void:
	var tmp_dir := "user://test_saves_arch"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	svc.delete_slot("mig_slot")

	# 1) Saveable registry integration
	var inv := InventoryContainer.new()
	inv.add_item(&"ore", 5)
	svc.register_saveable("inventory", inv)
	var save_err := svc.save_slot("mig_slot", {"world": {"seed": 55}})
	_assert(save_err == OK, "SaveService writes slot with registered Saveable")

	# Mutate and verify backup creation on second save
	inv.add_item(&"ore", 3)
	var save_err2 := svc.save_slot("mig_slot", {"world": {"seed": 56}})
	_assert(save_err2 == OK, "SaveService overwrites slot atomically and writes .bak")
	_assert(FileAccess.file_exists(svc.get_backup_path("mig_slot")), "SaveService creates .bak on overwrite")

	# Corrupt primary JSON -> automatic recovery from .bak (seed 55, ore 5)
	var cf := FileAccess.open(svc.get_slot_path("mig_slot"), FileAccess.WRITE)
	cf.store_string("{corrupt_primary")
	cf.close()
	var rec := svc.load_slot("mig_slot")
	_assert(bool(rec.get("ok", false)) and bool(rec.get("recovered_from_backup", false)), "SaveService recovers from .bak when primary JSON is corrupt")
	var rec_data := rec["data"] as Dictionary
	_assert(int((rec_data["world"] as Dictionary)["seed"]) == 55, "Backup recovery restores previous valid world seed")
	var inv_reloaded := InventoryContainer.new()
	svc.register_saveable("inventory", inv_reloaded)
	svc.apply_saveables(rec_data)
	_assert(inv_reloaded.count_item(&"ore") == 5, "SaveService.apply_saveables restores InventoryContainer from backup")

	# 2) Schema migration chain v1 -> v2 -> v3
	svc.current_schema_version = 3
	svc.register_migration(1, func(d: Dictionary) -> Dictionary:
		var next := d.duplicate(true)
		next["migrated_v2"] = true
		return next
	)
	svc.register_migration(2, func(d: Dictionary) -> Dictionary:
		var next := d.duplicate(true)
		next["migrated_v3"] = "done"
		return next
	)
	var mig := svc.load_slot("mig_slot")
	_assert(bool(mig.get("ok", false)), "SaveService runs v1->v2->v3 migration chain")
	var mig_data := mig["data"] as Dictionary
	_assert(int(mig_data.get("schema_version", 0)) == 3, "Migrated save reaches target schema_version 3")
	_assert(bool(mig_data.get("migrated_v2", false)) and str(mig_data.get("migrated_v3", "")) == "done", "Migrations apply in order")

	svc.delete_slot("mig_slot")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()


func _test_pool_service_and_scene_loader() -> void:
	var pool_autoload := get_root().get_node_or_null("PoolService")
	_assert(pool_autoload != null, "Autoload PoolService exists on SceneTree root")

	var pool := PoolServiceScript.new()
	get_root().add_child(pool)

	var packed := PackedScene.new()
	var tpl := MockPoolItem.new()
	packed.pack(tpl)
	tpl.free()

	pool.prewarm(packed, 2)
	var s1 := pool.get_pool_stats(packed)
	_assert(int(s1["available"]) == 2 and int(s1["active"]) == 0, "PoolService.prewarm populates available pool")

	var parent_node := Node3D.new()
	get_root().add_child(parent_node)
	var inst := pool.acquire(packed, parent_node) as MockPoolItem
	_assert(inst != null and inst.get_parent() == parent_node and inst.visible, "PoolService.acquire activates and parents node")
	_assert(inst.acquired_count == 1, "PoolService.acquire invokes on_pool_acquire()")

	pool.release(inst)
	_assert(inst.released_count == 1 and not inst.visible and inst.get_parent() == pool, "PoolService.release parks node and invokes on_pool_release()")
	var s2 := pool.get_pool_stats(packed)
	_assert(int(s2["available"]) == 2 and int(s2["active"]) == 0, "PoolService stats restore after release")

	pool.clear_pool(packed)
	parent_node.queue_free()
	pool.queue_free()

	var loader := SceneLoader.new()
	get_root().add_child(loader)
	_assert(loader.request_load("res://does_not_exist.tscn") == ERR_FILE_NOT_FOUND, "SceneLoader rejects missing scene paths")
	_assert(loader.request_load("res://scenes/ui/title_screen.tscn") == OK, "SceneLoader starts threaded request on valid scene")
	for _i in 100:
		if not loader.is_loading():
			break
		OS.delay_msec(10)
		loader._poll_once()
	_assert(not loader.is_loading() and is_equal_approx(loader.get_progress(), 1.0), "SceneLoader completes loading title_screen.tscn")
	loader.queue_free()


func _test_input_rebinding_and_dev_console() -> void:
	var tmp_cfg := "user://test_bindings_arch.cfg"
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)

	var store := SettingsStoreScript.new()
	store.config_path = tmp_cfg
	store.load_settings()

	var ir := InputRouterScript.new()
	ir.settings_store = store
	ir.register_action(&"test_jump", [KEY_SPACE], "Jump")
	ir.register_action(&"test_dash", [KEY_Q], "Dash")

	_assert(ir.get_action_keycode(&"test_jump") == KEY_SPACE, "InputRouter registers default keycode")
	var rebind_res := ir.rebind_action_key(&"test_jump", KEY_Q, true)
	_assert(bool(rebind_res.get("ok", false)) and rebind_res.get("swapped_with") == &"test_dash", "InputRouter swaps conflicting key binding")
	_assert(ir.get_action_keycode(&"test_jump") == KEY_Q and ir.get_action_keycode(&"test_dash") == KEY_SPACE, "Swapped actions update both keycodes")

	# Reload SettingsStore + InputRouter to verify persistence
	var store2 := SettingsStoreScript.new()
	store2.config_path = tmp_cfg
	store2.load_settings()
	var ir2 := InputRouterScript.new()
	ir2.settings_store = store2
	ir2.register_action(&"test_jump", [KEY_SPACE], "Jump")
	ir2.register_action(&"test_dash", [KEY_Q], "Dash")
	_assert(ir2.get_action_keycode(&"test_jump") == KEY_Q, "Persisted input_bindings survive SettingsStore reload")

	ir2.reset_bindings()
	_assert(ir2.get_action_keycode(&"test_jump") == KEY_SPACE, "InputRouter.reset_bindings restores defaults")

	# GuLog + DevConsole checks
	GuLog.clear()
	GuLog.info("Test", "Structured info entry")
	GuLog.error("Test", "Structured error entry")
	_assert(GuLog.get_entries(GuLog.Level.ERROR).size() == 1, "GuLog filters entries by minimum level")

	var console_autoload := get_root().get_node_or_null("DevConsole")
	_assert(console_autoload != null, "Autoload DevConsole exists on SceneTree root")

	var console := DevConsoleScript.new()
	console.input_router = ir2
	get_root().add_child(console)
	console.register_command("sum", "Add two ints", func(args: Array[String]) -> String:
		return str(int(args[0]) + int(args[1]))
	)
	_assert(console.execute("sum 3 4") == "7", "DevConsole executes custom command")
	console.set_open(true)
	_assert(console.is_open() and not ir2.allow_debug(), "Opening DevConsole pushes MODAL context")
	console.set_open(false)
	_assert(not console.is_open() and ir2.allow_debug(), "Closing DevConsole restores gameplay context")

	console.queue_free()
	ir.free()
	ir2.free()
	store.free()
	store2.free()
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)


func _test_flags_and_quest_tracker() -> void:
	var flags := FlagStore.new()
	var flag_events := [0]
	flags.flag_changed.connect(func(_id: StringName, _old_v: Variant, _new_v: Variant) -> void: flag_events[0] += 1)

	flags.set_flag(&"met_elder", true)
	_assert(flags.get_bool(&"met_elder"), "FlagStore stores boolean flags")
	_assert(flags.inc_counter(&"beacons_lit", 2) == 2, "FlagStore.inc_counter increments integer counters")
	_assert(flag_events[0] == 2, "FlagStore emits flag_changed on mutations")

	var bus := EventBusScript.new()
	var inv := InventoryContainer.new()
	var stats := StatSet.new()
	stats.define_stat(&"xp", 1000.0, 0.0)

	var tracker := QuestTracker.new()
	tracker.bind(bus, flags, inv, stats)

	var loaded_count := tracker.register_from_rows([
		{
			"id": "sector_trial",
			"title": "Sector Trial",
			"objectives": [
				{"id": "beacons", "type": "event", "event": "beacon_lit_changed", "filter": {"lit": true}, "target": 2},
				{"id": "gather_wood", "type": "inventory_count", "item_id": "wood", "target": 3},
				{"id": "flag_ready", "type": "flag", "flag_id": "met_elder", "flag_value": true, "target": 1},
			],
			"rewards": [
				{"type": "item", "id": "coin", "amount": 10},
				{"type": "stat", "id": "xp", "delta": 50.0},
				{"type": "flag", "id": "trial_done", "value": true},
			],
		},
	])
	_assert(loaded_count == 1, "QuestTracker.register_from_rows registers DataTableLoader-style rows")
	_assert(tracker.start_quest(&"sector_trial"), "QuestTracker starts registered quest")

	# Non-matching filter should not advance beacon objective
	bus.emit_event(&"beacon_lit_changed", {"lit": false})
	var st1 := tracker.get_quest_status(&"sector_trial")
	_assert(int((st1["objectives"][0] as Dictionary)["current"]) == 0, "QuestTracker ignores events failing filter")

	# Matching event advances objective
	bus.emit_event(&"beacon_lit_changed", {"lit": true})
	var st2 := tracker.get_quest_status(&"sector_trial")
	_assert(int((st2["objectives"][0] as Dictionary)["current"]) == 1, "QuestTracker advances event objective via EventBus")

	# SaveService round-trip while quest is in progress
	var tmp_dir := "user://test_saves_quests"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	svc.register_saveable("flags", flags)
	svc.register_saveable("quests", tracker)
	var err := svc.save_slot("quest_slot", {"world": {"seed": 77}})
	_assert(err == OK, "SaveService persists FlagStore + QuestTracker saveables")

	var loaded := svc.load_slot("quest_slot")
	_assert(bool(loaded.get("ok", false)), "SaveService loads quest save slot")

	var flags2 := FlagStore.new()
	var inv2 := InventoryContainer.new()
	var stats2 := StatSet.new()
	stats2.define_stat(&"xp", 1000.0, 0.0)
	var tracker2 := QuestTracker.new()
	tracker2.register_from_rows([
		{
			"id": "sector_trial",
			"title": "Sector Trial",
			"objectives": [
				{"id": "beacons", "type": "event", "event": "beacon_lit_changed", "filter": {"lit": true}, "target": 2},
				{"id": "gather_wood", "type": "inventory_count", "item_id": "wood", "target": 3},
				{"id": "flag_ready", "type": "flag", "flag_id": "met_elder", "flag_value": true, "target": 1},
			],
			"rewards": [
				{"type": "item", "id": "coin", "amount": 10},
				{"type": "stat", "id": "xp", "delta": 50.0},
				{"type": "flag", "id": "trial_done", "value": true},
			],
		},
	])
	tracker2.bind(bus, flags2, inv2, stats2)
	flags2.apply_state((loaded["data"] as Dictionary).get("flags", {}) as Dictionary)
	tracker2.apply_state((loaded["data"] as Dictionary).get("quests", {}) as Dictionary)
	var st_restored := tracker2.get_quest_status(&"sector_trial")
	_assert(tracker2.is_active(&"sector_trial") and int((st_restored["objectives"][0] as Dictionary)["current"]) == 1, "Restored QuestTracker keeps partial progress")

	# Finish remaining objectives -> verify completion + rewards
	inv2.add_item(&"wood", 3)
	bus.emit_event(&"beacon_lit_changed", {"lit": true})
	_assert(tracker2.is_completed(&"sector_trial"), "Quest completes once all event + inventory + flag objectives meet target")
	_assert(inv2.count_item(&"coin") == 10, "Quest completion grants item reward to InventoryContainer")
	_assert(is_equal_approx(stats2.get_value(&"xp"), 50.0), "Quest completion grants stat reward to StatSet")
	_assert(flags2.get_bool(&"trial_done"), "Quest completion sets reward flag in FlagStore")

	tracker.unbind()
	tracker2.unbind()
	svc.delete_slot("quest_slot")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()
	bus.free()


func _test_dialogue() -> void:
	var broken := DialogueDef.from_dict({
		"id": "bad",
		"start": "a",
		"nodes": [{"id": "a", "next": "missing"}],
	})
	_assert(not broken.is_valid(), "DialogueDef rejects a next target that does not exist")
	var runner := DialogueRunner.new()
	var rejected := runner.start(broken)
	_assert(not bool(rejected.get("ok", true)) and bool(rejected.get("ended", false)), "DialogueRunner refuses an invalid graph")

	var flags := FlagStore.new()
	runner.bind(flags, null, null, null)
	var gated := DialogueDef.from_dict({
		"id": "gate",
		"start": "greet",
		"nodes": [
			{
				"id": "greet",
				"speaker": "Elder",
				"text": "Well?",
				"choices": [
					{
						"text": "You know me.",
						"next": "known",
						"conditions": [{"type": "flag", "id": "met_elder", "op": "eq", "value": true}],
						"effects": [{"type": "inc_flag", "id": "talks", "delta": 1}],
					},
				],
			},
			{"id": "known", "text": "Welcome back."},
		],
	})
	var view := runner.start(gated)
	_assert((view.get("choices", []) as Array).is_empty() and bool(view.get("terminal", false)), "Flag condition hides the only choice")
	flags.set_flag(&"met_elder", true)
	view = runner.start(gated)
	_assert((view.get("choices", []) as Array).size() == 1, "Flag condition reveals the choice")
	view = runner.choose(0)
	_assert(flags.get_int(&"talks") == 1 and String(view.get("node_id", "")) == "known", "Choice effect writes a flag and advances")

	var quests := QuestTracker.new()
	quests.register_quest(QuestDef.from_dict({
		"id": "errand",
		"objectives": [{"id": "wait", "type": "event", "event": "never_happens", "target": 1}],
	}))
	var hire := DialogueRunner.new()
	hire.bind(flags, quests, null, null)
	var hire_def := DialogueDef.from_dict({
		"id": "hire",
		"start": "ask",
		"nodes": [{
			"id": "ask",
			"text": "Help?",
			"choices": [{
				"text": "Yes",
				"effects": [{"type": "start_quest", "id": "errand"}],
			}],
		}],
	})
	view = hire.start(hire_def)
	view = hire.choose(0)
	_assert(bool(view.get("ended", false)) and quests.is_active(&"errand"), "Dialogue start_quest accepts a quest")
	view = hire.start(hire_def)
	view = hire.choose(0)
	_assert(bool(view.get("ok", false)) and bool(view.get("ended", false)) and quests.is_active(&"errand"), "start_quest is a no-op when the quest is already active")

	var short_inv := InventoryContainer.new()
	short_inv.add_item(&"wood", 1)
	var trade := DialogueRunner.new()
	trade.bind(null, null, short_inv, null)
	var trade_def := DialogueDef.from_dict({
		"id": "trade",
		"start": "offer",
		"nodes": [
			{
				"id": "offer",
				"text": "Three wood.",
				"choices": [{
					"text": "Hand them over.",
					"next": "thanks",
					"effects": [{"type": "remove_item", "id": "wood", "amount": 3}],
				}],
			},
			{"id": "thanks", "text": "Good."},
		],
	})
	view = trade.start(trade_def)
	view = trade.choose(0)
	_assert(str(view.get("error", "")) == "missing_item" and String(view.get("node_id", "")) == "offer", "Short inventory keeps the line in place")
	_assert(short_inv.count_item(&"wood") == 1, "Failed remove_item does not change the inventory")

	var tight := InventoryContainer.new(1, 1)
	tight.add_item(&"wood", 1)
	var pack := DialogueRunner.new()
	pack.bind(null, null, tight, null)
	var pack_def := DialogueDef.from_dict({
		"id": "pack",
		"start": "offer",
		"nodes": [
			{
				"id": "offer",
				"text": "Swap?",
				"choices": [{
					"text": "Deal",
					"next": "thanks",
					"effects": [
						{"type": "remove_item", "id": "wood", "amount": 1},
						{"type": "add_item", "id": "ore", "amount": 2},
					],
				}],
			},
			{"id": "thanks", "text": "Done."},
		],
	})
	view = pack.start(pack_def)
	view = pack.choose(0)
	_assert(str(view.get("error", "")) == "inventory_full" and String(view.get("node_id", "")) == "offer", "Full pack keeps the line in place")
	_assert(tight.count_item(&"wood") == 1 and tight.count_item(&"ore") == 0, "Failed exchange rolls back both sides")

	var bus := EventBusScript.new()
	var bag := InventoryContainer.new()
	var story_flags := FlagStore.new()
	var story := QuestTracker.new()
	var wood_quest: QuestDef = GameContent.quest(&"gather_wood")
	_assert(wood_quest != null and wood_quest.is_valid(), "gather_wood quest loads from data")
	story.register_quest(wood_quest)
	story.bind(bus, story_flags, bag)
	var elder := DialogueRunner.new()
	elder.bind(story_flags, story, bag, bus)
	var elder_def: DialogueDef = GameContent.dialogue(&"elder_intro")
	_assert(elder_def != null and elder_def.is_valid(), "Elder dialogue graph loads from data and is valid")
	view = elder.start(elder_def)
	var accept := _dialogue_choice_index(view, "I will bring three wood.")
	_assert(accept >= 0 and _dialogue_choice_index(view, "Here is the wood.") == -1, "Delivery stays hidden until the quest is active and stocked")
	view = elder.choose(accept)
	_assert(story.is_active(&"gather_wood") and story_flags.get_bool(&"met_elder"), "Accept choice starts the quest and sets a flag")
	_assert(String(view.get("node_id", "")) == "accepted", "Accept choice advances to the accepted line")

	bag.add_item(&"wood", 2)
	view = elder.start(elder_def)
	_assert(_dialogue_choice_index(view, "Here is the wood.") == -1, "Delivery stays hidden until the player holds 3 wood")
	bag.add_item(&"wood", 1)
	view = elder.start(elder_def)
	var deliver := _dialogue_choice_index(view, "Here is the wood.")
	_assert(deliver >= 0, "Delivery appears once the quest is active and the wood is in hand")
	view = elder.choose(deliver)
	_assert(bag.count_item(&"wood") == 0, "Delivery removes the promised wood")
	_assert(story.is_completed(&"gather_wood"), "Delivery event completes the quest")
	_assert(bag.count_item(&"coin") == 8, "Quest reward grants coins after delivery")
	_assert(story_flags.get_bool(&"elder_paid"), "Quest reward sets the paid flag")
	_assert(String(view.get("node_id", "")) == "paid", "Delivery advances to the paid line")

	view = elder.start(elder_def)
	_assert((view.get("choices", []) as Array).is_empty() and bool(view.get("can_continue", false)), "Completed quest hides choices and offers Continue")
	view = elder.continue_line()
	_assert(String(view.get("node_id", "")) == "done" and bool(view.get("terminal", false)) and not bool(view.get("ended", true)), "Completed branch lands on the closing line")

	var router := get_root().get_node("InputRouter")
	var was_gameplay := bool(router.call("is_gameplay_active"))
	var stack_before := int(router.call("get_stack_size"))
	var host := Node3D.new()
	get_root().add_child(host)
	var box := DialogueBox.new()
	host.add_child(box)
	var box_flags := FlagStore.new()
	box.bind(box_flags, null, null, null)
	var npc := DialogueInteractable.new()
	npc.dialogue = DialogueDef.from_dict({
		"id": "hi",
		"start": "a",
		"nodes": [{
			"id": "a",
			"speaker": "Elder",
			"text": "Hello",
			"effects": [{"type": "set_flag", "id": "spoke", "value": true}],
		}],
	})
	host.add_child(npc)
	_assert(npc.interact(host), "DialogueInteractable accepts an actor")
	_assert(box.is_open() and box_flags.get_bool(&"spoke"), "DialogueInteractable opens DialogueBox and applies the line")
	_assert(not bool(router.call("is_gameplay_active")), "DialogueBox pushes the UI input context")
	var close_btn := box.find_child("CloseButton", true, false) as Button
	_assert(close_btn != null, "Terminal line shows Close")
	if close_btn != null:
		close_btn.pressed.emit()
	_assert(not box.is_open(), "Close dismisses DialogueBox")
	_assert(bool(router.call("is_gameplay_active")) == was_gameplay, "Closing DialogueBox restores the previous gameplay input state")
	_assert(int(router.call("get_stack_size")) == stack_before, "Closing DialogueBox pops its input context")

	story.unbind()
	host.free()
	bus.free()
