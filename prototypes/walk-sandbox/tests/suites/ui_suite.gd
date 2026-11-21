extends "res://tests/support/test_suite_base.gd"
## Save slots, world entities, HUD, status, combat feedback, clock, and debug tools.


func run_all() -> void:
	_test_save_slots_panel_and_keybind_list()
	_test_world_entity_primitives()
	_test_gameplay_hud()
	_test_loading_and_shader_warmup()
	_test_status_cooldown_and_tags()
	_test_hitbox_and_juice()
	_test_game_clock()
	_test_input_glyphs_focus_tooltip_coach()
	_test_bug_report_and_platform()


func _test_save_slots_panel_and_keybind_list() -> void:
	# 1) SaveService slot metadata & SaveSlotsPanel
	var tmp_dir := "user://test_saves_slots_ui"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	svc.delete_slot("alpha")
	svc.delete_slot("beta")
	svc.save_slot("alpha", {"world": {"seed": 1}})
	svc.save_slot("beta", {"world": {"seed": 2}})
	var metas := svc.list_slot_metadata()
	_assert(metas.size() == 2, "SaveService.list_slot_metadata returns all saved slots")
	_assert(bool((metas[0] as Dictionary).get("exists", false)), "Slot metadata marks existing slot")
	_assert(str((metas[0] as Dictionary).get("saved_at_text", "")) != "", "Slot metadata formats timestamp text")

	var mock_world := MockWorld.new()
	get_root().add_child(mock_world)

	var flow := GameFlowScript.new()
	get_root().add_child(flow)
	flow.register_world(mock_world)

	var slots_scene := load("res://addons/gu_core/ui/save_slots_panel.tscn") as PackedScene
	_assert(slots_scene != null, "save_slots_panel.tscn loads cleanly")
	var slots_inst := slots_scene.instantiate() as SaveSlotsPanel
	slots_inst.save_service = svc
	slots_inst.game_flow = flow
	get_root().add_child(slots_inst)
	slots_inst.on_ui_enter({"mode": "load", "allow_save": false})
	_assert(slots_inst.get_mode() == "load" and slots_inst.get_slot_count() == 2, "SaveSlotsPanel populates existing slots in load mode")
	slots_inst.set_mode("save")
	_assert(slots_inst.get_mode() == "load", "SaveSlotsPanel blocks save mode when allow_save=false")

	slots_inst.on_ui_enter({"mode": "save", "allow_save": true})
	_assert(slots_inst.get_mode() == "save", "SaveSlotsPanel enables save mode when allow_save=true")
	_assert(slots_inst.delete_slot_confirmed("alpha") == OK and slots_inst.get_slot_count() == 1, "SaveSlotsPanel.delete_slot_confirmed deletes slot and refreshes list")
	slots_inst.free()

	# Verify GameFlow.open_save_slots auto-registers & opens screen on UIRouter
	var gf_aut := get_root().get_node_or_null("GameFlow")
	var ui_aut := get_root().get_node_or_null("UIRouter")
	if gf_aut != null and ui_aut != null:
		gf_aut.call("open_save_slots", "load")
		_assert(ui_aut.call("top_screen_id") == &"save_slots", "GameFlow.open_save_slots pushes save_slots onto UIRouter")
		ui_aut.call("clear_screens")

	svc.delete_slot("alpha")
	svc.delete_slot("beta")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	flow.queue_free()
	mock_world.queue_free()
	svc.free()

	# 2) KeybindList dynamic rows + capture/cancel/swap + SettingsPanel tabs
	var tmp_cfg := "user://test_keybind_ui.cfg"
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)
	var store := SettingsStoreScript.new()
	store.config_path = tmp_cfg
	store.load_settings()

	var ir := InputRouterScript.new()
	ir.settings_store = store
	ir.register_action(&"ui_act_a", [KEY_J], "Action A")
	ir.register_action(&"ui_act_b", [KEY_K], "Action B")

	var kb := KeybindList.new()
	kb.input_router = ir
	get_root().add_child(kb)
	_assert(kb.get_action_count() == 2, "KeybindList builds one row per registered action")
	_assert(kb.get_button_text(&"ui_act_a") == "J", "KeybindList renders current key label")

	kb.begin_listen(&"ui_act_a")
	_assert(kb.is_listening() and not ir.allow_debug(), "KeybindList.begin_listen pushes MODAL context")
	var esc_res := kb.capture_key_event(&"ui_act_a", KEY_ESCAPE)
	_assert(bool(esc_res.get("cancelled", false)) and not kb.is_listening() and ir.allow_debug(), "KEY_ESCAPE cancels key capture and restores context")
	_assert(kb.get_button_text(&"ui_act_a") == "J", "Cancelled capture preserves previous key label")

	var swap_res := kb.capture_key_event(&"ui_act_a", KEY_K)
	_assert(bool(swap_res.get("ok", false)), "KeybindList.capture_key_event rebinds and swaps conflicts")
	_assert(kb.get_button_text(&"ui_act_a") == "K" and kb.get_button_text(&"ui_act_b") == "J", "KeybindList refreshes both swapped button labels")

	kb.reset_all()
	_assert(kb.get_button_text(&"ui_act_a") == "J" and kb.get_button_text(&"ui_act_b") == "K", "KeybindList.reset_all restores default labels")

	kb.free()
	ir.free()
	store.free()
	if FileAccess.file_exists(tmp_cfg):
		DirAccess.remove_absolute(tmp_cfg)

	# Verify SettingsPanel tab toggle and locale options from the shared catalog.
	var lang_store := get_root().get_node_or_null("SettingsStore")
	var spawned_store: Node = null
	if lang_store == null:
		spawned_store = SettingsStoreScript.new()
		spawned_store.name = "SettingsStore"
		spawned_store.config_path = "user://test_settings_panel_locale.cfg"
		spawned_store.translation_dir = "res://data"
		get_root().add_child(spawned_store)
		lang_store = spawned_store
	var sp_packed := load("res://scenes/ui/settings_panel.tscn") as PackedScene
	var sp_inst := sp_packed.instantiate() as Control
	get_root().add_child(sp_inst)
	sp_inst.call("show_tab", "controls")
	var sys_sec := sp_inst.get_node_or_null("%SystemSection") as Control
	var ctrl_sec := sp_inst.get_node_or_null("%ControlsSection") as Control
	_assert(sys_sec != null and not sys_sec.visible and ctrl_sec != null and ctrl_sec.visible, "SettingsPanel switches between System and Controls tabs")
	var lang := sp_inst.get_node_or_null("%LanguageOption") as OptionButton
	var locale_count := 0
	if lang_store != null:
		var locales: Variant = lang_store.call("get_locales")
		if locales is PackedStringArray or locales is Array:
			locale_count = locales.size()
	_assert(lang != null and locale_count > 0 and lang.item_count == locale_count, "SettingsPanel language options match SettingsStore locales")
	var zh_index := -1
	for i in lang.item_count:
		if lang.get_item_text(i) == "中文":
			zh_index = i
	_assert(zh_index >= 0, "SettingsPanel lists 中文")
	var prev_ui_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh")
	var title := (load("res://scenes/ui/title_screen.tscn") as PackedScene).instantiate()
	get_root().add_child(title)
	_assert((title.get_node("%ContinueButton") as Button).text == "继续", "Title screen switches to Chinese")
	get_root().remove_child(title)
	title.free()
	TranslationServer.set_locale(prev_ui_locale)
	get_root().remove_child(sp_inst)
	sp_inst.free()
	if spawned_store != null:
		get_root().remove_child(spawned_store)
		spawned_store.free()
		if FileAccess.file_exists("user://test_settings_panel_locale.cfg"):
			DirAccess.remove_absolute("user://test_settings_panel_locale.cfg")


func _test_world_entity_primitives() -> void:
	# 1) HealthComponent damage, invuln window, heal, death, revive
	var hc := HealthComponent.new()
	hc.max_hp = 50.0
	hc.invuln_time = 0.25
	get_root().add_child(hc)
	var died_hits := [0]
	hc.died.connect(func(_src: Node) -> void: died_hits[0] += 1)

	_assert(is_equal_approx(hc.apply_damage(20.0), 20.0), "HealthComponent applies initial damage")
	_assert(is_equal_approx(hc.apply_damage(10.0), 0.0), "HealthComponent blocks damage during invuln window")
	hc._process(0.30)
	_assert(is_equal_approx(hc.heal(10.0), 10.0) and is_equal_approx(hc.get_hp(), 40.0), "HealthComponent heals after invuln expires")
	hc.apply_damage(99.0)
	_assert(hc.is_dead() and died_hits[0] == 1, "HealthComponent emits died once when HP hits zero")
	_assert(is_equal_approx(hc.heal(10.0), 0.0), "HealthComponent ignores heal while dead")
	hc.revive(true)
	_assert(not hc.is_dead() and is_equal_approx(hc.get_hp(), 50.0), "HealthComponent.revive restores alive state and max HP")
	get_root().remove_child(hc)
	hc.free()

	# 2) WorldPickup magnet, InventoryContainer overflow, EventBus, PoolService
	var host := Node3D.new()
	get_root().add_child(host)

	var bus := EventBusScript.new()
	var picked_events: Array[Dictionary] = []
	bus.subscribe(&"item_picked_up", func(p: Dictionary) -> void: picked_events.append(p))

	var pool := PoolServiceScript.new()
	get_root().add_child(pool)

	var pickup_packed := PackedScene.new()
	var tpl_pickup := WorldPickup.new()
	pickup_packed.pack(tpl_pickup)
	tpl_pickup.free()
	pool.prewarm(pickup_packed, 2)

	var collector := MockCollector.new()
	collector.inventory = InventoryContainer.new(1, 3) # max 3 items total
	collector.add_to_group(WorldPickup.COLLECTOR_GROUP)
	collector.position = Vector3.ZERO
	host.add_child(collector)

	var drop := pool.acquire(pickup_packed, host) as WorldPickup
	drop.event_bus = bus
	drop.pool_service = pool
	drop.position = Vector3(2.2, 0.0, 0.0)
	drop.configure(&"ore", 5, Color(0.4, 0.8, 1.0))

	# Magnet slides pickup closer, collects 3, leaves 2 behind because inventory is full
	for _i in 6:
		drop.step_pickup(0.1)
	_assert(collector.inventory.count_item(&"ore") == 3, "WorldPickup collects up to InventoryContainer capacity")
	_assert(drop.amount == 2 and not drop.is_collected(), "WorldPickup retains uncollected leftover when inventory full")
	_assert(picked_events.size() == 1 and int(picked_events[0]["amount"]) == 3, "WorldPickup emits EventBus item_picked_up")

	# Expand inventory slots and finish collecting -> recycles back into PoolService
	collector.inventory.max_slots = 2
	drop.step_pickup(0.1)
	_assert(collector.inventory.count_item(&"ore") == 5, "WorldPickup delivers remaining items once space opens")
	_assert(drop.is_collected() and drop.get_parent() == pool, "WorldPickup recycles into PoolService after full collection")
	var pstats := pool.get_pool_stats(pickup_packed)
	_assert(int(pstats["available"]) == 2 and int(pstats["active"]) == 0, "PoolService restores available count after pickup release")

	# 3) ResourceNode harvest -> deplete -> drop -> respawn -> SaveService round-trip
	var rnode := ResourceNode.new()
	rnode.event_bus = bus
	rnode.pool_service = pool
	rnode.pickup_scene = pickup_packed
	rnode.respawn_time = 2.0
	host.add_child(rnode)
	rnode.configure("ore_test", &"ore", &"mine", [{"item_id": "ore", "min": 2, "max": 2, "chance": 1.0}], 20.0, 10.0)

	_assert(is_equal_approx(rnode.apply_harvest_hit(collector), 10.0), "ResourceNode takes first harvest hit")
	_assert(not rnode.is_depleted(), "ResourceNode stays active while HP > 0")
	rnode.apply_harvest_hit(collector)
	_assert(rnode.is_depleted() and not rnode.can_interact(collector), "ResourceNode depletes and disables interaction at 0 HP")

	var spawned_pickups := 0
	for ch in host.get_children():
		if ch is WorldPickup:
			spawned_pickups += 1
	_assert(spawned_pickups >= 1, "Depleted ResourceNode spawns WorldPickup drop(s)")

	var saved_state := rnode.export_state()
	_assert(bool(saved_state.get("depleted", false)), "ResourceNode.export_state captures depleted state")

	rnode._process(2.5)
	_assert(not rnode.is_depleted() and is_equal_approx(rnode.get_health().get_hp(), 20.0), "ResourceNode respawns after respawn_time elapses")

	rnode.apply_state(saved_state)
	_assert(rnode.is_depleted() and not rnode.can_interact(collector), "ResourceNode.apply_state restores depleted state")

	pool.clear_pool(pickup_packed)
	pool.queue_free()
	bus.free()
	host.free()


func _test_gameplay_hud() -> void:
	var stats := StatSet.new()
	stats.define_stat(&"stamina", 100.0, 80.0)
	var bar := StatBar.new()
	bar.bind_stat(stats, &"stamina", "Stamina")
	_assert(bar.get_value_text() == "80 / 100", "StatBar shows current and max")
	_assert(is_equal_approx(bar.get_displayed_ratio(), 0.8), "StatBar ratio tracks StatSet")
	stats.set_value(&"stamina", 25.0)
	_assert(bar.get_value_text() == "25 / 100" and is_equal_approx(bar.get_displayed_ratio(), 0.25), "StatBar updates on stat_changed")
	bar.unbind()
	stats.set_value(&"stamina", 10.0)
	_assert(bar.get_value_text() == "25 / 100", "StatBar ignores changes after unbind")
	bar.free()

	var health := HealthComponent.new()
	health.max_hp = 40.0
	var health_bar := StatBar.new()
	health_bar.bind_health(health, "Health")
	_assert(health_bar.get_value_text() == "40 / 40", "StatBar.bind_health reads HealthComponent")
	health.apply_damage(15.0)
	_assert(health_bar.get_value_text() == "25 / 40" and is_equal_approx(health_bar.get_displayed_ratio(), 25.0 / 40.0), "StatBar follows health damage")
	health_bar.free()
	health.free()

	var router := get_root().get_node_or_null("InputRouter")
	_assert(router != null, "InputRouter autoload available for inventory HUD")
	var stack_before := int(router.call("get_stack_size")) if router != null else 0
	var panel := InventoryPanel.new()
	get_root().add_child(panel)
	var inv := InventoryContainer.new(4, 99)
	panel.bind_inventory(inv)
	inv.add_item(&"ore", 3)
	var rows := panel.get_row_texts()
	_assert(rows.size() == 1 and rows[0] == "Ore x3", "InventoryPanel renders occupied slot rows")
	_assert(_find_label_prefix(panel, "Empty slots") == "Empty slots: 3", "InventoryPanel counts empty slots from max_slots")
	panel.set_open(true)
	_assert(panel.is_open() and router != null and int(router.call("get_active_context")) == 1, "InventoryPanel open pushes UI context")
	panel.toggle()
	_assert(not panel.is_open() and router != null and int(router.call("get_stack_size")) == stack_before, "InventoryPanel close pops UI context")

	var dropped: Array = []
	panel.drop_requested.connect(func(item_id: StringName, amount: int) -> void: dropped.append([item_id, amount]))
	var drop_btn: Button = null
	for node in panel.find_children("*", "Button", true, false):
		drop_btn = node as Button
		break
	_assert(drop_btn != null, "InventoryPanel row exposes a drop button")
	if drop_btn != null:
		drop_btn.pressed.emit()
	_assert(dropped.size() == 1 and String(dropped[0][0]) == "ore" and int(dropped[0][1]) == 1, "InventoryPanel drop requests one item")
	_assert(inv.count_item(&"ore") == 2, "InventoryPanel drop removes one item")
	var ui := get_root().get_node_or_null("UIRouter")
	if ui != null and ui.has_method("clear_toasts"):
		ui.call("clear_toasts")
	if panel.is_open():
		panel.set_open(false)
	get_root().remove_child(panel)
	panel.free()

	var tracker := QuestTracker.new()
	var quests := QuestHud.new()
	get_root().add_child(quests)
	quests.bind_tracker(tracker)
	tracker.register_quest(QuestDef.from_dict({
		"id": "activate_beacons",
		"title": "Link Beacons",
		"objectives": [{
			"id": "lit",
			"type": "event",
			"event": "beacon_lit_changed",
			"description": "Light beacons",
			"target": 3,
		}],
	}))
	tracker.start_quest(&"activate_beacons")
	var quest_text := "\n".join(quests.get_row_texts())
	_assert("Link Beacons" in quest_text and "Light beacons 0/3" in quest_text, "QuestHud shows active objective")
	tracker.handle_event(&"beacon_lit_changed", {})
	quest_text = "\n".join(quests.get_row_texts())
	_assert("Light beacons 1/3" in quest_text, "QuestHud updates objective progress")
	tracker.handle_event(&"beacon_lit_changed", {})
	tracker.handle_event(&"beacon_lit_changed", {})
	quest_text = "\n".join(quests.get_row_texts())
	_assert("COMPLETE" in quest_text, "QuestHud shows completion text")
	quests.acknowledge_completion(&"activate_beacons")
	_assert(not ("COMPLETE" in "\n".join(quests.get_row_texts())), "QuestHud.acknowledge_completion clears the completed row")
	tracker.unbind()
	get_root().remove_child(quests)
	quests.free()

	var hud_stats := StatSet.new()
	hud_stats.define_stat(&"stamina", 100.0)
	var hud_inv := InventoryContainer.new(2, 99)
	var hud_tracker := QuestTracker.new()
	var hud := GameplayHud.new()
	get_root().add_child(hud)
	hud.bind_player_hud(hud_stats, &"stamina", hud_inv, hud_tracker, "Stamina")
	_assert(hud.stats_root.get_child_count() == 1, "GameplayHud hosts a stat bar")
	_assert(hud.inventory != null and not hud.inventory.is_open(), "GameplayHud inventory starts closed")
	_assert(hud.quests != null, "GameplayHud hosts the quest tracker")
	get_root().remove_child(hud)
	hud.free()


func _test_loading_and_shader_warmup() -> void:
	var ui := get_root().get_node_or_null("UIRouter")
	_assert(ui != null, "UIRouter autoload is available for loading progress")
	if ui == null:
		return
	ui.call("set_loading_progress", 0.0)
	_assert(is_equal_approx(float(ui.call("get_loading_progress")), 0.0), "Loading progress starts at 0")
	ui.call("set_loading_progress", 1.0)
	_assert(is_equal_approx(float(ui.call("get_loading_progress")), 1.0), "Loading progress reaches 1")
	ui.call("hide_loading")

	var warmup := ShaderWarmupScript.new()
	get_root().add_child(warmup)
	_assert(not warmup.is_queued_for_deletion(), "Shader warmup stays for the frame it is added")
	warmup._process(0.016)
	_assert(warmup.warmed and warmup.is_queued_for_deletion(), "Shader warmup leaves the tree after one process step")


func _test_status_cooldown_and_tags() -> void:
	var tags := GameplayTagsScript.new()
	tags.add(&"State.Stunned")
	_assert(tags.has(&"State") and tags.has(&"State.Stunned"), "GameplayTags treats State.Stunned as State")
	_assert(not tags.has(&"State.Burning"), "GameplayTags does not match a sibling tag")

	var stats := StatSet.new()
	stats.define_stat(&"speed", 10.0)
	var status := StatusControllerScript.new()
	status.stats = stats
	status.apply_status(&"haste", {"duration": 1.0, "stat_id": &"speed", "mult": 1.3, "tags": ["State.Haste"]})
	_assert(is_equal_approx(stats.get_max(&"speed"), 13.0), "Haste raises the speed maximum by 30 percent")
	_assert(status.tags.has(&"State"), "Haste grants the State tag family")
	status.advance(1.1)
	_assert(not status.has_status(&"haste"), "Haste expires after its duration")
	_assert(is_equal_approx(stats.get_max(&"speed"), 10.0), "Expired haste restores the original speed maximum")
	_assert(not status.tags.has(&"State.Haste"), "Expired haste removes its tag")

	var health := HealthComponent.new()
	health.max_hp = 20.0
	status.health = health
	status.apply_status(&"poison", {"duration": 5.0, "tick_interval": 1.0, "damage_per_tick": 5.0})
	status.advance(1.0)
	_assert(is_equal_approx(health.get_hp(), 15.0), "Poison tick damages health")

	var cooldowns := CooldownTrackerScript.new()
	_assert(cooldowns.try_start(&"mine", 1.0), "Cooldown accepts the first use")
	_assert(not cooldowns.try_start(&"mine", 1.0), "Cooldown rejects a second use while active")
	cooldowns.advance(1.0)
	_assert(cooldowns.try_start(&"mine", 0.5), "Cooldown allows the action after it elapses")
	status.free()


func _test_hitbox_and_juice() -> void:
	var health := HealthComponent.new()
	health.max_hp = 100.0
	health.invuln_time = 10.0
	var hurt := HurtboxScript.new()
	hurt.health = health
	hurt.faction = &"player"
	get_root().add_child(hurt)
	var hit := HitboxScript.new()
	hit.faction = &"enemy"
	hit.damage = 10.0
	get_root().add_child(hit)
	var camera := CameraRig.new()
	var juice := JuiceBusScript.new()
	juice.camera = camera
	get_root().add_child(juice)

	var applied := hit.strike(hurt, false, Vector3.FORWARD)
	_assert(is_equal_approx(applied, 10.0), "Hitbox damages a hostile hurtbox")
	_assert(juice.floater_count == 1 and is_equal_approx(juice.last_amount, 10.0), "Juice bus records one floater for the hit")
	_assert(camera.get_shake_remaining() > 0.0, "Juice bus shakes the camera")
	var clock := get_root().get_node_or_null("GameClock")
	_assert(clock != null and is_equal_approx(float(clock.call("get_scale")), 0.2), "Juice bus applies a short hitstop")
	_assert(is_equal_approx(Engine.time_scale, 1.0), "Hitstop leaves Engine.time_scale unchanged")
	var blocked := hit.strike(hurt, false, Vector3.FORWARD)
	_assert(is_equal_approx(blocked, 0.0), "Invulnerability frames ignore the second hit")
	juice.advance(1.0)
	_assert(clock != null and is_equal_approx(float(clock.call("get_scale")), 1.0), "Hitstop restores gameplay scale")

	var ally := HurtboxScript.new()
	ally.health = HealthComponent.new()
	ally.health.max_hp = 50.0
	ally.faction = &"enemy"
	get_root().add_child(ally)
	_assert(is_equal_approx(hit.strike(ally, false, Vector3.FORWARD), 0.0), "Same-faction hits are ignored")

	if clock != null:
		clock.call("pop_scale", &"hitstop")
	juice.queue_free()
	hurt.queue_free()
	hit.queue_free()
	ally.queue_free()


func _test_game_clock() -> void:
	var clock := get_root().get_node_or_null("GameClock")
	_assert(clock != null, "Autoload GameClock exists")
	if clock == null:
		return
	clock.call("pop_scale", &"hitstop")
	clock.call("reset_world_time")
	clock.call("set_gameplay_running", false)
	_assert(is_equal_approx(float(clock.call("gameplay_delta", 0.5)), 0.0), "Paused gameplay delta is zero")
	_assert(is_equal_approx(float(clock.call("ui_delta", 0.5)), 0.5), "UI delta ignores pause")

	clock.call("set_gameplay_running", true)
	clock.call("push_scale", &"hitstop", 0.2)
	_assert(is_equal_approx(float(clock.call("get_scale")), 0.2), "Hitstop scale is 0.2")
	_assert(is_equal_approx(float(clock.call("gameplay_delta", 1.0)), 0.2), "Hitstop scales gameplay delta")
	_assert(is_equal_approx(Engine.time_scale, 1.0), "Hitstop does not change Engine.time_scale")

	_clock_timer_fired = false
	var timer_id := int(clock.call("after_gameplay", 0.5, Callable(self, "_on_game_clock_timer")))
	clock.call("advance_frame", 1.0)
	_assert(timer_id > 0 and not _clock_timer_fired, "Gameplay timer waits for scaled time")
	clock.call("pop_scale", &"hitstop")
	clock.call("advance_frame", 0.5)
	_assert(_clock_timer_fired, "Gameplay timer fires after scaled time elapses")

	var exported: Dictionary = clock.call("export_state") as Dictionary
	var saved_seconds := float(exported.get("world_seconds", -1.0))
	_assert(is_equal_approx(saved_seconds, 0.7), "World seconds accumulate scaled gameplay time")

	var saves := get_root().get_node_or_null("SaveService")
	_assert(saves != null, "SaveService is available for the clock roundtrip")
	if saves != null:
		var err := int(saves.call("save_slot", "clock_slot", {"world": {"seed": 1}}))
		_assert(err == OK, "Clock section saves with the slot")
		clock.call("reset_world_time")
		var loaded: Dictionary = saves.call("load_slot", "clock_slot") as Dictionary
		_assert(bool(loaded.get("ok", false)), "Clock slot loads")
		saves.call("apply_saveables", loaded.get("data", {}))
		var restored: Dictionary = clock.call("export_state") as Dictionary
		_assert(is_equal_approx(float(restored.get("world_seconds", -1.0)), saved_seconds), "Save restores world_seconds")
		saves.call("delete_slot", "clock_slot")

	var flow := get_root().get_node_or_null("GameFlow")
	if flow != null:
		flow.call("start_new_game", {"seed": 1})
		var cleared: Dictionary = clock.call("export_state") as Dictionary
		_assert(is_equal_approx(float(cleared.get("world_seconds", -1.0)), 0.0), "New game resets world time")
	clock.call("set_gameplay_running", false)
	clock.call("pop_scale", &"hitstop")


func _test_input_glyphs_focus_tooltip_coach() -> void:
	var router := InputRouterScript.new()
	router.register_action(&"interact", [KEY_E], "Interact")
	_assert(router.glyph_name(&"interact") == "E", "Keyboard glyph uses the bound key label")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	router.note_input_event(pad)
	_assert(router.glyph_name(&"interact") == "A", "Joypad input switches the interact glyph to A")

	var ui := UIRouterScript.new()
	get_root().add_child(ui)
	var button := Button.new()
	button.name = "RememberedButton"
	get_root().add_child(button)
	button.grab_focus()
	var packed := PackedScene.new()
	var probe := Control.new()
	packed.pack(probe)
	probe.free()
	ui.register_screen(&"focus_probe", packed)
	ui.push_screen(&"focus_probe")
	ui.pop_screen()
	_assert(get_root().gui_get_focus_owner() == button, "Closing a screen restores the previous focus")
	button.queue_free()
	ui.queue_free()

	var tip := TooltipFrameScript.new()
	tip.request("Wood", Rect2(1200, 10, 40, 20), Vector2(1280, 720))
	tip.advance(0.05)
	_assert(not tip.shown, "Tooltip waits out its delay")
	tip.advance(0.2)
	_assert(tip.shown and tip.position.x < 1200.0, "Tooltip flips inward at the right edge")

	var flags := FlagStore.new()
	_assert(CoachMarksScript.try_show(flags, &"first_pickup"), "Coach mark shows the first time")
	_assert(not CoachMarksScript.try_show(flags, &"first_pickup"), "Coach mark does not repeat for the same flag")


func _test_bug_report_and_platform() -> void:
	GuLog.info("bug", "pack-test")
	var console := get_root().get_node_or_null("DevConsole")
	_assert(console != null, "DevConsole autoload can write a bug pack")
	if console != null:
		var clock := get_root().get_node_or_null("GameClock")
		if clock != null:
			clock.call("apply_state", {"world_seconds": 12.5})
		var written := str(console.call("write_bug_report", "user://bug_reports/unit", Vector3(1, 2, 3)))
		_assert(FileAccess.file_exists(written.path_join("log.txt")), "Bug pack contains the log")
		_assert(FileAccess.file_exists(written.path_join("screenshot.png")), "Bug pack contains a screenshot")
		_assert(FileAccess.file_exists(written.path_join("save.json")), "Bug pack contains a save copy")
		var position_text := FileAccess.get_file_as_string(written.path_join("position.json"))
		_assert("1" in position_text and "2" in position_text and "3" in position_text, "Bug pack records the player position")
		_assert("world_seconds" in position_text and "12.5" in position_text, "Bug pack records world time")
		if clock != null:
			clock.call("reset_world_time")

	var platform := get_root().get_node_or_null("PlatformService")
	_assert(platform != null, "PlatformService autoload is registered")
	if platform != null:
		platform.call("unlock_achievement", "test_foundation_badge")
		_assert(bool(platform.call("has_achievement", "test_foundation_badge")), "Mock platform records an achievement")
		var raw := FileAccess.get_file_as_string("user://platform_mock.json")
		_assert("test_foundation_badge" in raw, "Mock platform writes the achievement JSON")
