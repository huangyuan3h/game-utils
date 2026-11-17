class_name MapGenerator
extends RefCounted
## Procedural walkable map. This file is the pipeline only:
##   heightfield -> coast -> lakes -> rivers -> smooth -> land biomes.
## Stages live in scripts/map/. Public entry points stay here.

const MapTypes = preload("res://scripts/map/map_types.gd")
const MapHeightfield = preload("res://scripts/map/map_heightfield.gd")
const MapLakes = preload("res://scripts/map/map_lakes.gd")
const MapRivers = preload("res://scripts/map/map_rivers.gd")

## Re-export so existing callers (TerrainMap, Player) keep using MapGenerator.
const Biome = MapTypes.Biome
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


static func generate_random(p_seed: int = -1, opts: Dictionary = {}) -> Dictionary:
	var s: int = p_seed if p_seed >= 0 else int(Time.get_ticks_usec()) ^ randi()
	return generate(s, opts)


static func river_half_width(along: float) -> float:
	return MapRivers.river_half_width(along)


static func river_depth(along: float) -> float:
	return MapRivers.river_depth(along)


static func generate(p_seed: int, opts: Dictionary = {}) -> Dictionary:
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

	var noise_h := MapHeightfield._make_noise(p_seed, 0.011, 5, 0.5)
	var noise_detail := MapHeightfield._make_noise(p_seed + 3, 0.035, 3, 0.45)
	var noise_m := MapHeightfield._make_noise(p_seed + 17, 0.02, 3, 0.5)
	var noise_ridge := MapHeightfield._make_noise(p_seed + 41, 0.007, 3, 0.5)

	var heights := PackedFloat32Array()
	heights.resize(grid * grid)
	var biomes := PackedByteArray()
	biomes.resize(grid * grid)
	biomes.fill(MapTypes.Biome.GRASS)

	# 1) Height bake — inland mountains, coastal falloff
	for z in grid:
		for x in grid:
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			var inland := MapHeightfield._inland_factor(wx, wz, size, sea_edge)
			var sea_prox := MapHeightfield._sea_proximity(wx, wz, size, sea_edge)
			var n1 := noise_h.get_noise_2d(wx, wz)
			var n2 := noise_h.get_noise_2d(wx * 0.4 + 20.0, wz * 0.4 - 11.0)
			var n3 := noise_detail.get_noise_2d(wx, wz)
			var ridge := maxf(noise_ridge.get_noise_2d(wx * 0.7, wz * 0.7), 0.0)
			ridge = pow(ridge, 1.25) * pow(inland, 1.6)
			var lobe := pow(maxf(n2, 0.0), 1.35) * inland
			var h := base_h
			h += n1 * 2.0 * relief
			h += lobe * (max_h - base_h) * 0.55 * relief
			h += ridge * (max_h - base_h) * 0.95 * relief
			h += n3 * 0.45 * relief
			h += inland * 1.6 * relief
			h = lerpf(h, water_y - 0.15, smoothstep(0.55, 1.0, sea_prox) * 0.9)
			heights[MapHeightfield._i(grid, x, z)] = h

	# 2) Coastal SEA + beach
	for z in grid:
		for x in grid:
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			var sea_prox := MapHeightfield._sea_proximity(wx, wz, size, sea_edge)
			var i := MapHeightfield._i(grid, x, z)
			if sea_prox > 0.70:
				var t := smoothstep(0.70, 0.92, sea_prox)
				heights[i] = lerpf(heights[i], water_y - 0.55 - (sea_prox - 0.70) * 1.3, t)
				biomes[i] = MapTypes.Biome.SEA
			elif sea_prox > 0.56:
				var t2 := smoothstep(0.56, 0.70, sea_prox)
				heights[i] = lerpf(heights[i], water_y - 0.06, t2 * 0.75)
				biomes[i] = MapTypes.Biome.SAND

	# Pre-tag mountain peaks
	var h_min0 := INF
	var h_max0 := -INF
	for i in heights.size():
		h_min0 = minf(h_min0, heights[i])
		h_max0 = maxf(h_max0, heights[i])
	var mountain_cut := lerpf(h_min0, h_max0, 0.72)
	for z in grid:
		for x in grid:
			var i := MapHeightfield._i(grid, x, z)
			if int(biomes[i]) == MapTypes.Biome.SEA or int(biomes[i]) == MapTypes.Biome.SAND:
				continue
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			if heights[i] >= mountain_cut and MapHeightfield._inland_factor(wx, wz, size, sea_edge) > 0.45:
				biomes[i] = MapTypes.Biome.MOUNTAIN

	# 3) Inland LAKE basins (closed depressions)
	var lake_result: Dictionary = MapLakes._place_lakes(heights, biomes, grid, size, sea_edge, water_y, relief, rng)
	heights = lake_result["heights"] as PackedFloat32Array
	var lakes: Array = lake_result["lakes"] as Array

	# 4) Rivers: mountain → lake or sea (+ optional lake outlet to sea)
	var rivers: Array = MapRivers._trace_rivers(heights, biomes, grid, size, sea_edge, water_y, lakes, rng)
	if not lakes.is_empty() and rivers.size() < 3:
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
			if mid_clear >= MapTypes.LAKE_RIVER_GAP * 0.75:
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
			if b == MapTypes.Biome.SEA:
				heights[i] = minf(heights[i], water_y - 0.35)
			elif b == MapTypes.Biome.LAKE:
				# Keep lake bed under its water surface
				var ly := MapLakes._lake_y_at_cell(lakes, x, z, grid, size, water_y)
				heights[i] = minf(heights[i], ly - 0.25)

	# 7) Remaining land biomes (preserve SEA / LAKE / RIVER / MOUNTAIN / coastal SAND)
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
			if b0 == MapTypes.Biome.SEA or b0 == MapTypes.Biome.LAKE or b0 == MapTypes.Biome.RIVER or b0 == MapTypes.Biome.MOUNTAIN:
				continue
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			if b0 == MapTypes.Biome.SAND and (
				MapHeightfield._sea_proximity(wx, wz, size, sea_edge) > 0.52
				or MapLakes._near_lake(lakes, wx, wz)
			):
				continue
			var h := heights[i]
			var t := (h - h_min) / h_span
			var moist := (noise_m.get_noise_2d(wx, wz) + 1.0) * 0.5
			if t > 0.70:
				biomes[i] = MapTypes.Biome.MOUNTAIN
			elif t < 0.22 and moist < 0.48:
				biomes[i] = MapTypes.Biome.SAND
			elif moist < 0.30 or (t > 0.55 and moist < 0.48):
				biomes[i] = MapTypes.Biome.DIRT
			else:
				biomes[i] = MapTypes.Biome.GRASS

	return {
		"seed": p_seed,
		"size": size,
		"grid": grid,
		"base_height": base_h,
		"max_height": max_h,
		"water_y": water_y,
		"sea_edge": sea_edge,
		"heights": heights,
		"biomes": biomes,
		"rivers": rivers,
		"lakes": lakes,
		"h_min": h_min,
		"h_max": h_max,
	}


## --- Compatibility wrappers (terrain mesh still calls these) --------------

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
