class_name MapGenerator
extends RefCounted
## Procedural walkable map. This file is the pipeline only:
##   heightfield -> coast -> lakes -> rivers -> smooth -> land biomes.
## Stages live in scripts/map/. Public entry points stay here.

const MapTypes = preload("res://scripts/map/map_types.gd")
const MapHeightfield = preload("res://scripts/map/map_heightfield.gd")
const MapLandforms = preload("res://scripts/map/map_landforms.gd")
const MapLakes = preload("res://scripts/map/map_lakes.gd")
const MapRivers = preload("res://scripts/map/map_rivers.gd")

## Re-export so existing callers (TerrainMap, Player) keep using MapGenerator.
const Biome = MapTypes.Biome
const Landform = MapTypes.Landform
const DEFAULT_SIZE := MapTypes.DEFAULT_SIZE
const DEFAULT_GRID := MapTypes.DEFAULT_GRID
const DEFAULT_BASE := MapTypes.DEFAULT_BASE
const DEFAULT_MAX_H := MapTypes.DEFAULT_MAX_H
const DEFAULT_MAX_STEP := MapTypes.DEFAULT_MAX_STEP
const DEFAULT_WATER_Y := MapTypes.DEFAULT_WATER_Y
const RIVER_HALF_W_SRC := MapTypes.RIVER_HALF_W_SRC
const RIVER_HALF_W_MOUTH := MapTypes.RIVER_HALF_W_MOUTH
const RIVER_DEPTH_SRC := MapTypes.RIVER_DEPTH_SRC
const RIVER_DEPTH_MOUTH := MapTypes.RIVER_DEPTH_MOUTH
const RIVER_BANK_MUL := MapTypes.RIVER_BANK_MUL
const LAKE_RIVER_GAP := MapTypes.LAKE_RIVER_GAP


static func generate_random(p_seed: int = -1, opts: Dictionary = {}) -> MapData:
	var s: int = p_seed if p_seed >= 0 else int(Time.get_ticks_usec()) ^ randi()
	return generate(s, opts)


static func river_half_width(along: float) -> float:
	return MapRivers.river_half_width(along)


static func river_depth(along: float) -> float:
	return MapRivers.river_depth(along)


static func biome_name(b: int) -> String:
	return MapTypes.biome_name(b)


static func landform_name(lf: int) -> String:
	return MapTypes.landform_name(lf)


static func generate(p_seed: int, opts: Dictionary = {}) -> MapData:
	var size: float = float(opts.get("size", DEFAULT_SIZE))
	var grid: int = int(opts.get("grid", DEFAULT_GRID))
	var base_h: float = float(opts.get("base_height", DEFAULT_BASE))
	var max_h: float = float(opts.get("max_height", DEFAULT_MAX_H))
	var max_step: float = float(opts.get("max_step", DEFAULT_MAX_STEP))
	var relief: float = float(opts.get("relief", 1.0))
	var water_y: float = float(opts.get("water_y", DEFAULT_WATER_Y))

	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var sea_edge: int = int(opts.get("sea_edge", rng.randi_range(0, 3)))
	var landform: int = int(opts.get("landform", -1))
	if landform < 0 or landform > MapTypes.Landform.ROLLING_ARCHIPELAGO:
		landform = rng.randi_range(0, MapTypes.Landform.ROLLING_ARCHIPELAGO)

	var noise_m := MapHeightfield._make_noise(p_seed + 17, 0.02, 3, 0.5)

	var biomes := PackedByteArray()
	biomes.resize(grid * grid)
	biomes.fill(MapTypes.Biome.GRASS)

	# 1) Height bake — domain-warped landform archetype + coastal falloff
	var base_field: Dictionary = MapLandforms.build_base_heightfield(
		p_seed, grid, size, base_h, max_h, relief, water_y, sea_edge, landform
	)
	var heights: PackedFloat32Array = base_field["heights"] as PackedFloat32Array
	var coast_prox: PackedFloat32Array = base_field["coast_prox"] as PackedFloat32Array

	# 2) Coastal SEA + beach (uses shaped coast_prox for headlands / islets / coves)
	for z in grid:
		for x in grid:
			var i := MapHeightfield._i(grid, x, z)
			var eff_sea_p := coast_prox[i]
			if eff_sea_p > 0.70:
				var t := smoothstep(0.70, 0.92, eff_sea_p)
				heights[i] = lerpf(heights[i], water_y - _sea_swim_depth(eff_sea_p), t)
				biomes[i] = MapTypes.Biome.SEA
			elif eff_sea_p > 0.56:
				var t2 := smoothstep(0.56, 0.70, eff_sea_p)
				heights[i] = lerpf(heights[i], water_y - 0.06, t2 * 0.65)
				biomes[i] = MapTypes.Biome.SAND

	# Pre-tag mountain peaks (used by lake & river source placement)
	var h_min0 := INF
	var h_max0 := -INF
	for i in heights.size():
		h_min0 = minf(h_min0, heights[i])
		h_max0 = maxf(h_max0, heights[i])
	var mountain_cut := lerpf(h_min0, h_max0, 0.70)
	for z in grid:
		for x in grid:
			var i := MapHeightfield._i(grid, x, z)
			if int(biomes[i]) == MapTypes.Biome.SEA or int(biomes[i]) == MapTypes.Biome.SAND:
				continue
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			if heights[i] >= mountain_cut and MapHeightfield._inland_factor(wx, wz, size, sea_edge) > 0.40:
				biomes[i] = MapTypes.Biome.MOUNTAIN

	# 3) Inland LAKE basins (closed depressions)
	var lake_result: Dictionary = MapLakes._place_lakes(heights, biomes, grid, size, sea_edge, water_y, relief, rng)
	heights = lake_result["heights"] as PackedFloat32Array
	var lakes: Array = lake_result["lakes"] as Array

	# 4) Rivers: mountain → lake or sea (+ optional lake outlet to sea)
	var rivers: Array = MapRivers._trace_rivers(heights, biomes, grid, size, sea_edge, water_y, lakes, rng)
	# Optional lake → sea outlet (does not replace the main watershed)
	if not lakes.is_empty() and rivers.size() < 4:
		var outlet_river: PackedVector2Array = MapRivers._trace_lake_outlet(
			heights, biomes, grid, size, sea_edge, water_y, lakes[0] as Dictionary, rng
		)
		# Keep only outlets that quickly leave the lake (no shore-hugging ribbon)
		if outlet_river.size() >= 8:
			var mid_clear := INF
			var i0 := int(outlet_river.size() * 0.2)
			var i1 := maxi(i0 + 1, int(outlet_river.size() * 0.9))
			for i in range(i0, i1):
				mid_clear = minf(mid_clear, MapLakes._lake_shore_clearance(outlet_river[i], lakes))
			if mid_clear >= MapTypes.LAKE_RIVER_GAP * 0.65:
				rivers.append(outlet_river)

	# 5) Enforce downhill + carve river channels
	heights = MapRivers._enforce_downhill(heights, biomes, grid, size, rivers, water_y, lakes)
	heights = MapRivers._carve_rivers(heights, biomes, grid, size, rivers, water_y, lakes, relief)

	# 6) Smooth + slope-limit
	heights = MapHeightfield._smooth(heights, biomes, grid, 2)
	heights = MapHeightfield._limit_slopes(heights, grid, max_step, 5)
	for z in grid:
		for x in grid:
			var i := MapHeightfield._i(grid, x, z)
			var b := int(biomes[i])
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			if b == MapTypes.Biome.SEA:
				var sea_prox := maxf(coast_prox[i], MapHeightfield._sea_proximity(wx, wz, size, sea_edge))
				# Re-assert after slope limiting so the offshore shelf stays swimmable.
				heights[i] = minf(heights[i], water_y - _sea_swim_depth(sea_prox))
			elif b == MapTypes.Biome.LAKE:
				var ly := MapLakes._lake_y_at_cell(lakes, x, z, grid, size, water_y)
				heights[i] = minf(heights[i], ly - _lake_swim_depth(lakes, wx, wz))
	MapLakes._enforce_lake_containment(heights, biomes, grid, size, lakes)

	# 7) Post-pass slope/cavity/moisture fields & expressive land biomes
	var fields: Dictionary = MapLandforms.compute_terrain_fields(
		heights, biomes, grid, size, sea_edge, rivers, lakes, noise_m
	)
	var slopes: PackedFloat32Array = fields["slopes"] as PackedFloat32Array
	var cavities: PackedFloat32Array = fields["cavities"] as PackedFloat32Array
	var moisture: PackedFloat32Array = fields["moisture"] as PackedFloat32Array

	var h_min := INF
	var h_max := -INF
	for i in heights.size():
		h_min = minf(h_min, heights[i])
		h_max = maxf(h_max, heights[i])
	var h_span := maxf(h_max - h_min, 0.001)

	for z in grid:
		for x in grid:
			var i := MapHeightfield._i(grid, x, z)
			var b0 := int(biomes[i])
			if b0 == MapTypes.Biome.SEA or b0 == MapTypes.Biome.LAKE or b0 == MapTypes.Biome.RIVER:
				continue
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			var h := heights[i]
			var t := (h - h_min) / h_span
			var slope := slopes[i]
			var moist := moisture[i]

			if b0 == MapTypes.Biome.SAND and (
				coast_prox[i] > 0.52
				or MapLakes._near_lake(lakes, wx, wz)
			):
				if slope > 0.58 and h > water_y + 1.1:
					biomes[i] = MapTypes.Biome.CLIFF
				continue

			if slope > 0.50 and h > water_y + 0.95:
				biomes[i] = MapTypes.Biome.CLIFF
			elif t > 0.80 and h > water_y + 6.8:
				biomes[i] = MapTypes.Biome.ALPINE
			elif t > 0.64 or b0 == MapTypes.Biome.MOUNTAIN:
				biomes[i] = MapTypes.Biome.MOUNTAIN
			elif h < water_y + 0.75 and moist < 0.52:
				biomes[i] = MapTypes.Biome.SAND
			elif moist > 0.60 and slope < 0.36 and t < 0.54:
				biomes[i] = MapTypes.Biome.MEADOW
			elif moist > 0.45 and t >= 0.22 and t <= 0.66 and slope < 0.46:
				biomes[i] = MapTypes.Biome.FOREST
			elif moist < 0.30 or (t > 0.46 and moist < 0.43):
				biomes[i] = MapTypes.Biome.DIRT
			else:
				biomes[i] = MapTypes.Biome.GRASS

	var data := MapData.new()
	data.seed_value = p_seed
	data.size = size
	data.grid = grid
	data.base_height = base_h
	data.max_height = max_h
	data.water_y = water_y
	data.sea_edge = sea_edge
	data.landform = landform
	data.heights = heights
	data.biomes = biomes
	data.slopes = slopes
	data.cavities = cavities
	data.moisture = moisture
	data.coast_prox = coast_prox
	data.rivers = rivers
	data.lakes = lakes
	data.h_min = h_min
	data.h_max = h_max
	return data


## --- Compatibility wrappers (terrain mesh still calls these) --------------

static func _sea_swim_depth(sea_prox: float) -> float:
	## Beach line stays wadeable; the outer shelf passes chest depth so swim engages.
	var u := smoothstep(0.70, 1.0, sea_prox)
	return lerpf(0.42, 2.15, pow(u, 0.80))


static func _lake_swim_depth(lakes: Array, wx: float, wz: float) -> float:
	## Shallow rim, swimmable center. Matches player DEPTH_SWIM (1.15 m).
	var depth := 0.45
	var p := Vector2(wx, wz)
	for lake in lakes:
		var c: Vector2 = lake["center"]
		var r: float = maxf(float(lake.get("radius", 8.0)), 1.0)
		var nd := p.distance_to(c) / r
		if nd > 1.15:
			continue
		var u := clampf(1.0 - nd, 0.0, 1.0)
		depth = maxf(depth, lerpf(0.42, 1.85, pow(u, 0.55)))
	return depth


static func _sea_proximity(wx: float, wz: float, size: float, sea_edge: int) -> float:
	return MapHeightfield._sea_proximity(wx, wz, size, sea_edge)


static func _dist_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	return MapRivers._dist_to_polyline(p, pts)


static func _mouth_water_y(
	p: Vector2, biomes: PackedByteArray, grid: int, size: float, water_y: float, lakes: Array
) -> float:
	return MapLakes._mouth_water_y(p, biomes, grid, size, water_y, lakes)


static func _sanitize_polyline(pts: PackedVector2Array) -> PackedVector2Array:
	return MapRivers._sanitize_polyline(pts)


static func _smooth_polyline(pts: PackedVector2Array, iters: int) -> PackedVector2Array:
	return MapRivers._smooth_polyline(pts, iters)
