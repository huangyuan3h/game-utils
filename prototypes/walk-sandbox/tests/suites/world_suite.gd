extends "res://tests/support/test_suite_base.gd"
## Spawn location, interaction, surface audio, and beacon persistence.


func run_all() -> void:
	_test_world_locator()
	_test_interaction_system()
	_test_surface_resolver_and_audio_bank()
	_test_beacon_save_roundtrip()


func _test_world_locator() -> void:
	var seeds := [17, 42, 108, 256, 999]
	var min_spacing := 16.0
	for s: int in seeds:
		var data: MapData = MapGen.generate(s, {"relief": 1.0})
		var spawn: Vector3 = WorldLocatorScript.find_spawn_point(data)
		var spawn_biome := data.sample_biome(spawn.x, spawn.z)
		_assert(
			spawn_biome != MapTypes.Biome.SEA
			and spawn_biome != MapTypes.Biome.LAKE
			and spawn_biome != MapTypes.Biome.RIVER
			and spawn_biome != MapTypes.Biome.CLIFF,
			"Seed %d spawn biome (%s) avoids water and cliff" % [s, MapTypes.biome_name(spawn_biome)]
		)
		_assert(
			data.sample_water_surface(spawn.x, spawn.z) <= -1000.0,
			"Seed %d spawn is not in swimmable water" % s
		)
		_assert(spawn.y >= data.water_y, "Seed %d spawn sits at or above water_y" % s)

		var pois: Array[Dictionary] = WorldLocatorScript.find_poi_spots(data, 6, min_spacing, spawn)
		_assert(pois.size() >= 3, "Seed %d locates at least 3 POI spots (got %d)" % [s, pois.size()])
		for i in pois.size():
			var p: Vector3 = pois[i]["position"] as Vector3
			var b: int = int(pois[i]["biome"])
			_assert(
				b != MapTypes.Biome.SEA
				and b != MapTypes.Biome.LAKE
				and b != MapTypes.Biome.RIVER
				and b != MapTypes.Biome.CLIFF,
				"Seed %d POI %d avoids water and cliff" % [s, i]
			)
			_assert(data.sample_water_surface(p.x, p.z) <= -1000.0, "Seed %d POI %d is dry" % [s, i])
			for j in range(i + 1, pois.size()):
				var q: Vector3 = pois[j]["position"] as Vector3
				var d := Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z))
				_assert(d >= min_spacing - 0.01, "Seed %d POIs %d-%d respect min_spacing (%.2f)" % [s, i, j, d])


func _test_interaction_system() -> void:
	var host := Node3D.new()
	get_root().add_child(host)

	var actor := Node3D.new()
	actor.position = Vector3.ZERO
	host.add_child(actor)

	var router := InputRouterScript.new()
	host.add_child(router)

	var interactor := InteractorScript.new()
	interactor.interact_range = 3.0
	interactor.auto_bind_input = false
	interactor.input_router = router
	actor.add_child(interactor)
	interactor.set_actor(actor)

	var near_item := InteractableScript.new()
	near_item.interaction_id = "near"
	near_item.prompt_text = "Open Crate"
	near_item.position = Vector3(1.0, 0.0, 0.0)
	host.add_child(near_item)

	var far_item := InteractableScript.new()
	far_item.interaction_id = "far"
	far_item.prompt_text = "Pull Lever"
	far_item.position = Vector3(2.1, 0.0, 0.0)
	host.add_child(far_item)

	var focus_events: Array[Interactable] = []
	interactor.focus_changed.connect(func(t: Interactable) -> void: focus_events.append(t))

	var triggered := [0]
	near_item.interacted.connect(func(_a: Node) -> void: triggered[0] += 1)
	var far_triggered := [0]
	far_item.interacted.connect(func(_a: Node) -> void: far_triggered[0] += 1)

	var focused := interactor.refresh_focus()
	_assert(focused == near_item, "Interactor focuses nearest interactable")
	_assert(focus_events.size() == 1 and focus_events[0] == near_item, "focus_changed emits on initial focus")

	# InputRouter blocking check
	router.push_context(InputRouterScript.Context.UI, &"modal_test")
	_assert(not interactor.try_interact(), "Interactor blocks try_interact when InputRouter is in UI context")
	_assert(triggered[0] == 0, "Blocked interaction does not fire interacted signal")

	router.pop_context(&"modal_test")
	_assert(interactor.try_interact(), "Interactor succeeds when InputRouter returns to GAMEPLAY")
	_assert(triggered[0] == 1, "Unblocked interaction fires interacted signal")

	# Disabling closer target switches focus to second target
	near_item.enabled = false
	var next_focus := interactor.refresh_focus()
	_assert(next_focus == far_item, "Disabling focused target shifts focus to next valid interactable")
	_assert(interactor.try_interact() and far_triggered[0] == 1, "Interactor triggers newly focused target")

	host.free()


func _test_surface_resolver_and_audio_bank() -> void:
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.GRASS, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.GRASS,
		"Grass biome resolves to GRASS surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.SAND, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.SAND,
		"Sand biome resolves to SAND surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.DIRT, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.DIRT,
		"Dirt biome resolves to DIRT surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.CLIFF, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.ROCK,
		"Cliff biome resolves to ROCK surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.GRASS, 0.0, 0.6) == SurfaceResolverScript.SurfaceType.SNOW,
		"High snow_cover overrides Grass to SNOW surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.ALPINE, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.SNOW,
		"Alpine biome resolves to SNOW surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.RIVER, 0.0, 0.0) == SurfaceResolverScript.SurfaceType.SHALLOW_WATER,
		"River biome resolves to SHALLOW_WATER surface"
	)
	_assert(
		SurfaceResolverScript.resolve(MapTypes.Biome.SAND, 0.15, 0.0) == SurfaceResolverScript.SurfaceType.SHALLOW_WATER,
		"Shallow water_depth overrides Sand to SHALLOW_WATER surface"
	)
	_assert(
		SurfaceResolverScript.resolve_by_name("Alpine", 0.0, 0.0) == SurfaceResolverScript.SurfaceType.SNOW,
		"SurfaceResolver.resolve_by_name maps Alpine to SNOW without MapTypes dependency"
	)

	var bank := SurfaceAudioBankScript.new()
	bank.load_default_fallbacks()
	_assert(not bank.fallback_walk.is_empty(), "SurfaceAudioBank loads default walk fallback streams")
	_assert(not bank.fallback_run.is_empty(), "SurfaceAudioBank loads default run fallback streams")

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var fb_stream := bank.get_stream(SurfaceResolverScript.SurfaceType.SAND, false, rng)
	_assert(fb_stream != null and bank.fallback_walk.has(fb_stream), "Empty surface pool falls back to foot_walk_*.wav")

	var custom_stream := AudioStreamWAV.new()
	bank.sand_walk = [custom_stream]
	_assert(
		bank.get_stream(SurfaceResolverScript.SurfaceType.SAND, false, rng) == custom_stream,
		"Populated surface pool overrides fallback stream"
	)


func _test_beacon_save_roundtrip() -> void:
	var host := Node3D.new()
	get_root().add_child(host)

	var b1 := WorldBeaconScript.new()
	b1.configure("beacon_1", 1, "Grass", Color(0.24, 0.88, 1.0))
	host.add_child(b1)

	var b2 := WorldBeaconScript.new()
	b2.configure("beacon_2", 2, "Sand", Color(0.96, 0.78, 0.28))
	host.add_child(b2)

	_assert(not b1.is_lit and not b2.is_lit, "Beacons initialize unlit")
	_assert(b1.interact(host), "Interacting with WorldBeacon toggles it")
	_assert(b1.is_lit, "Beacon_1 becomes lit after interact")

	var lit_ids: Array[String] = []
	for b in [b1, b2]:
		if b.is_lit:
			lit_ids.append(b.interaction_id)

	var tmp_dir := "user://test_saves_phase3"
	var svc := SaveServiceScript.new()
	svc.save_dir = tmp_dir
	var err := svc.save_slot("beacon_slot", {
		"world": {"seed": 42, "landform": 0, "relief": 1.0},
		"beacons": {"lit_ids": lit_ids},
	})
	_assert(err == OK, "SaveService persists beacon lit_ids")

	var loaded := svc.load_slot("beacon_slot")
	_assert(bool(loaded.get("ok", false)), "SaveService reloads beacon slot cleanly")
	var restored_ids: Array = ((loaded["data"] as Dictionary).get("beacons", {}) as Dictionary).get("lit_ids", []) as Array

	var b1_reloaded := WorldBeaconScript.new()
	b1_reloaded.configure("beacon_1", 1, "Grass", Color(0.24, 0.88, 1.0))
	host.add_child(b1_reloaded)
	b1_reloaded.set_lit(restored_ids.has(b1_reloaded.interaction_id), false)

	var b2_reloaded := WorldBeaconScript.new()
	b2_reloaded.configure("beacon_2", 2, "Sand", Color(0.96, 0.78, 0.28))
	host.add_child(b2_reloaded)
	b2_reloaded.set_lit(restored_ids.has(b2_reloaded.interaction_id), false)

	_assert(b1_reloaded.is_lit, "Reloaded Beacon_1 restores lit state from SaveService")
	_assert(not b2_reloaded.is_lit, "Reloaded Beacon_2 remains unlit from SaveService")

	svc.delete_slot("beacon_slot")
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)
	svc.free()
	host.free()
