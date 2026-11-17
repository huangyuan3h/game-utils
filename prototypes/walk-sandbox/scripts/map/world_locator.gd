class_name WorldLocator
extends RefCounted
## Data-driven spawn and point-of-interest (POI) placement on procedural MapData.
## Avoids open water, river channels, steep cliffs, and map edges while favoring biome diversity.

const MapTypes = preload("res://scripts/map/map_types.gd")

const SPAWN_MAX_SLOPE := 0.34
const SPAWN_MIN_CLEARANCE := 0.35
const POI_MAX_SLOPE := 0.38
const POI_MIN_CLEARANCE := 0.30
const BORDER_MARGIN_RATIO := 0.08


static func find_spawn_point(data: MapData) -> Vector3:
	if data == null or not data.is_valid():
		return Vector3.ZERO

	var margin := maxf(6.0, data.size * BORDER_MARGIN_RATIO)
	var half_usable := maxf(4.0, data.size * 0.5 - margin)
	var step := maxf(2.0, data.size / 48.0)

	var best_pos := Vector3.ZERO
	var best_score := -INF

	# Primary pass: flat, dry, centered, non-cliff terrain well above waterline.
	var z := -half_usable
	while z <= half_usable:
		var x := -half_usable
		while x <= half_usable:
			var cand := _score_spawn_candidate(data, x, z, SPAWN_MAX_SLOPE, SPAWN_MIN_CLEARANCE)
			if cand["valid"] and float(cand["score"]) > best_score:
				best_score = float(cand["score"])
				best_pos = cand["pos"] as Vector3
			x += step
		z += step

	if best_score > -INF:
		return best_pos

	# Fallback pass: relax slope and water clearance so extreme seeds still resolve safely.
	z = -half_usable
	while z <= half_usable:
		var x := -half_usable
		while x <= half_usable:
			var cand := _score_spawn_candidate(data, x, z, 0.60, 0.08)
			if cand["valid"] and float(cand["score"]) > best_score:
				best_score = float(cand["score"])
				best_pos = cand["pos"] as Vector3
			x += step
		z += step

	if best_score > -INF:
		return best_pos

	# Last resort: highest sample near center.
	var h0 := data.sample_height(0.0, 0.0)
	return Vector3(0.0, h0 + 0.02, 0.0)


static func find_poi_spots(
	data: MapData,
	count: int = 6,
	min_spacing: float = 16.0,
	avoid_point: Variant = null
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if data == null or not data.is_valid() or count <= 0:
		return results

	var avoid_2d := Vector2.ZERO
	var has_avoid := false
	if avoid_point is Vector3:
		var av3 := avoid_point as Vector3
		avoid_2d = Vector2(av3.x, av3.z)
		has_avoid = true
	elif avoid_point is Vector2:
		avoid_2d = avoid_point as Vector2
		has_avoid = true

	var spawn_clearance := maxf(8.0, min_spacing * 0.65)
	var margin := maxf(6.0, data.size * BORDER_MARGIN_RATIO)
	var half_usable := maxf(4.0, data.size * 0.5 - margin)
	var step := maxf(2.4, data.size / 42.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.seed_value) ^ 0x7F4A7C15

	var candidates: Array[Dictionary] = []
	var z := -half_usable
	while z <= half_usable:
		var x := -half_usable
		while x <= half_usable:
			if has_avoid and Vector2(x, z).distance_to(avoid_2d) < spawn_clearance:
				x += step
				continue
			var cand := _evaluate_poi_candidate(data, x, z, POI_MAX_SLOPE, POI_MIN_CLEARANCE, rng)
			if cand["valid"]:
				candidates.append(cand)
			x += step
		z += step

	# Fallback candidate pass with relaxed slope if terrain is unusually rugged.
	if candidates.size() < count:
		candidates.clear()
		z = -half_usable
		while z <= half_usable:
			var x := -half_usable
			while x <= half_usable:
				if has_avoid and Vector2(x, z).distance_to(avoid_2d) < spawn_clearance * 0.6:
					x += step
					continue
				var cand := _evaluate_poi_candidate(data, x, z, 0.52, 0.12, rng)
				if cand["valid"]:
					candidates.append(cand)
				x += step
			z += step

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["base_score"]) > float(b["base_score"])
	)

	var selected_2d: Array[Vector2] = []
	var used_biomes: Dictionary = {}
	var min_spacing_sq := min_spacing * min_spacing

	for idx in count:
		var best_idx := -1
		var best_total := -INF
		for ci in candidates.size():
			var c := candidates[ci]
			var p2 := c["pos_2d"] as Vector2
			var too_close := false
			for prev in selected_2d:
				if p2.distance_squared_to(prev) < min_spacing_sq:
					too_close = true
					break
			if too_close:
				continue

			var biome_id := int(c["biome"])
			var diversity_bonus := 8.0 if not used_biomes.has(biome_id) else 0.0
			var total := float(c["base_score"]) + diversity_bonus
			if total > best_total:
				best_total = total
				best_idx = ci

		if best_idx < 0:
			break

		var chosen := candidates[best_idx]
		candidates.remove_at(best_idx)
		var pos := chosen["pos"] as Vector3
		var biome_id := int(chosen["biome"])
		selected_2d.append(chosen["pos_2d"] as Vector2)
		used_biomes[biome_id] = true

		results.append({
			"id": "beacon_%d" % (results.size() + 1),
			"index": results.size() + 1,
			"position": pos,
			"biome": biome_id,
			"biome_name": MapTypes.biome_name(biome_id),
		})

	return results


static func _is_water_or_cliff_biome(b: int) -> bool:
	return (
		b == MapTypes.Biome.SEA
		or b == MapTypes.Biome.LAKE
		or b == MapTypes.Biome.RIVER
		or b == MapTypes.Biome.CLIFF
	)


static func _score_spawn_candidate(
	data: MapData,
	x: float,
	z: float,
	max_slope: float,
	min_clearance: float
) -> Dictionary:
	var b := data.sample_biome(x, z)
	if _is_water_or_cliff_biome(b):
		return {"valid": false}
	if data.sample_water_surface(x, z) > -1000.0:
		return {"valid": false}

	var h := data.sample_height(x, z)
	if h < data.water_y + min_clearance:
		return {"valid": false}

	var slope := data.sample_slope(x, z)
	if slope > max_slope:
		return {"valid": false}

	var water_dist := data.nearest_water_distance(x, z)
	if water_dist < 2.2:
		return {"valid": false}

	var center_dist := Vector2(x, z).length() / maxf(data.size * 0.5, 1.0)
	var biome_bonus := 0.0
	match b:
		MapTypes.Biome.GRASS, MapTypes.Biome.MEADOW:
			biome_bonus = 2.0
		MapTypes.Biome.SAND, MapTypes.Biome.DIRT:
			biome_bonus = 1.2
		MapTypes.Biome.FOREST:
			biome_bonus = 0.8
		MapTypes.Biome.ALPINE:
			biome_bonus = -2.0

	var score := biome_bonus - slope * 6.0 - center_dist * 3.0 + minf(water_dist, 12.0) * 0.15
	return {
		"valid": true,
		"score": score,
		"pos": Vector3(x, h + 0.02, z),
	}


static func _evaluate_poi_candidate(
	data: MapData,
	x: float,
	z: float,
	max_slope: float,
	min_clearance: float,
	rng: RandomNumberGenerator
) -> Dictionary:
	var b := data.sample_biome(x, z)
	if _is_water_or_cliff_biome(b):
		return {"valid": false}
	if data.sample_water_surface(x, z) > -1000.0:
		return {"valid": false}

	var h := data.sample_height(x, z)
	if h < data.water_y + min_clearance:
		return {"valid": false}

	var slope := data.sample_slope(x, z)
	if slope > max_slope:
		return {"valid": false}

	var water_dist := data.nearest_water_distance(x, z)
	if water_dist < 1.5:
		return {"valid": false}

	var biome_pref := 1.0
	if b == MapTypes.Biome.ALPINE:
		biome_pref = 0.3
	elif b == MapTypes.Biome.MEADOW or b == MapTypes.Biome.FOREST or b == MapTypes.Biome.MOUNTAIN:
		biome_pref = 1.4

	var base_score := biome_pref - slope * 5.0 + minf(water_dist, 10.0) * 0.1 + rng.randf_range(0.0, 0.8)
	return {
		"valid": true,
		"pos": Vector3(x, h, z),
		"pos_2d": Vector2(x, z),
		"biome": b,
		"base_score": base_score,
	}
