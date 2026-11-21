extends "res://tests/support/test_suite_base.gd"
## Procedural heightfield, terrain build staging, and river channel geometry.


func run_all() -> void:
	_test_map_data_and_generator()
	_test_terrain_build_context_and_meshes()
	_test_river_channel_and_confluence()


func _test_map_data_and_generator() -> void:
	var d1: MapData = MapGen.generate(42, {"relief": 1.0})
	var d2: MapData = MapGen.generate(42, {"relief": 1.0})
	_assert(d1 != null, "MapGenerator.generate returns non-null MapData")
	_assert(d1.is_valid(), "Generated MapData passes is_valid()")
	_assert(d1.seed_value == 42, "MapData keeps seed_value")
	_assert(d1.heights.size() == d1.grid * d1.grid, "Heights array matches grid*grid")
	_assert(d1.h_min <= d1.h_max, "h_min <= h_max")

	var all_finite := true
	for h in d1.heights:
		if is_nan(h) or is_inf(h):
			all_finite = false
			break
	_assert(all_finite, "All terrain heights are finite")
	_assert(is_equal_approx(d1.sample_height(0.0, 0.0), d2.sample_height(0.0, 0.0)), "Generation is deterministic per seed")

	var h_edge := d1.sample_height(9999.0, -9999.0)
	_assert(not is_nan(h_edge) and not is_inf(h_edge), "Out-of-bounds height query clamps safely")
	var b_edge := d1.sample_biome(9999.0, -9999.0)
	_assert(b_edge >= 0, "Out-of-bounds biome query clamps safely")


func _test_terrain_build_context_and_meshes() -> void:
	var data: MapData = MapGen.generate(108, {"relief": 1.0})
	var ctx := TerrainBuildContext.new(data)

	var rb := RiverMesh.new()
	var r_res: Dictionary = rb.build(ctx)
	ctx.mouths = r_res.get("mouths", []) as Array[Dictionary]
	data.refresh_height_range()

	var img := Image.create(data.grid, data.grid, false, Image.FORMAT_RF)
	ctx.height_tex = ImageTexture.create_from_image(img)

	var s_res: Dictionary = SeaMesh.new().build(ctx)
	_assert(s_res.get("mesh") is Mesh, "SeaMesh builds a Mesh via TerrainBuildContext")
	_assert(s_res.get("material") is ShaderMaterial, "SeaMesh builds a ShaderMaterial")

	var l_res: Dictionary = LakeMesh.new().build(ctx)
	if not data.lakes.is_empty():
		_assert(l_res.get("mesh") is Mesh, "LakeMesh builds a Mesh when lakes exist")

	var packed: Dictionary = ctx.pack_mouth_uniforms("sea")
	_assert(int(packed.get("count", -1)) <= 8, "pack_mouth_uniforms caps count at MAX_MOUTHS (8)")
	_assert((packed.get("pos_dir", []) as Array).size() == 8, "pack_mouth_uniforms pads pos_dir to 8")

	var spawn := WorldLocatorScript.find_spawn_point(data)
	var pois := WorldLocatorScript.find_poi_spots(data, 6, 16.0, spawn)
	ctx.clear_spots.append(Vector2(spawn.x, spawn.z))
	for spot: Dictionary in pois:
		var sp := spot["position"] as Vector3
		ctx.clear_spots.append(Vector2(sp.x, sp.z))
	var props_root := Node3D.new()
	var lpm := LandPropsMesh.new()
	lpm.build(ctx, props_root)
	_assert(props_root.get_child_count() > 0, "LandPropsMesh builds foliage/prop batches from TerrainBuildContext")
	var trees_in_river := 0
	for tree_name in ["PineTrees", "BroadleafTrees"]:
		var batch := props_root.get_node_or_null(tree_name) as MultiMeshInstance3D
		if batch == null or batch.multimesh == null:
			continue
		for ti in batch.multimesh.instance_count:
			var origin := batch.multimesh.get_instance_transform(ti).origin
			if lpm._too_close_to_river(origin.x, origin.z):
				trees_in_river += 1
	_assert(trees_in_river == 0, "Trees stay off the river bank")
	_assert(lpm._near_clear_spot(spawn.x, spawn.z, 2.8), "LandPropsMesh respects dynamic clear_spots for spawn")
	if not pois.is_empty():
		var p0 := pois[0]["position"] as Vector3
		_assert(lpm._near_clear_spot(p0.x, p0.z, 2.8), "LandPropsMesh respects dynamic clear_spots for POIs")
	props_root.free()


func _test_river_channel_and_confluence() -> void:
	var found_trib := false
	for seed in [108, 42, 7, 19, 64, 3]:
		var data: MapData = MapGen.generate(seed, {"relief": 1.0})
		if data.rivers.size() < 2:
			continue
		var main: PackedVector2Array = data.rivers[0]
		var gap := INF
		for ri in range(1, data.rivers.size()):
			var trib: PackedVector2Array = data.rivers[ri]
			if trib.is_empty():
				continue
			var tip: Vector2 = trib[trib.size() - 1]
			var d := MapRivers._dist_to_polyline(tip, main)
			if d < gap:
				gap = d
		if gap > 6.0:
			continue
		_assert(
			gap > 0.2 and gap < 3.4,
			"Tributary meets the main bank without crossing it (seed %d)" % seed
		)
		var ctx := TerrainBuildContext.new(data)
		var mesh := RiverMesh.new().build(ctx).get("mesh") as ArrayMesh
		_assert(mesh != null, "River mesh builds for a joined watershed")
		if mesh == null:
			return
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var floating := 0
		var buried := 0
		var checked := 0
		for i in range(0, verts.size() - 1, 2):
			var col := colors[i]
			if col.g > 0.45 or col.b > 0.45:
				continue
			var mid := (verts[i] + verts[i + 1]) * 0.5
			var bed := ctx.sample_height(mid.x, mid.z)
			checked += 1
			if mid.y - bed > 1.35:
				floating += 1
			elif bed > mid.y + 0.55:
				buried += 1
		_assert(checked > 8, "Inland river stations are checked")
		_assert(floating == 0 and buried == 0, "River sheet stays in the carved channel (seed %d)" % seed)
		found_trib = true
		break
	_assert(found_trib, "A generated map includes a tributary confluence")
