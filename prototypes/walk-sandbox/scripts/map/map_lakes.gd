extends RefCounted
## Inland lake basins: placement, shore queries, and the water height a river mouth should meet.
class_name MapLakes

const MapTypes = preload("res://scripts/map/map_types.gd")
const MapHeightfield = preload("res://scripts/map/map_heightfield.gd")

static func _lake_organic_scale(ang: float, center: Vector2) -> float:
	## Deterministic subtle oval/organic shoreline contour shared between height carving and lake mesh.
	return 1.0 + 0.04 * sin(ang * 2.0 + center.x * 0.11) + 0.025 * sin(ang * 3.0 - center.y * 0.09)


static func _sample_rim_stats(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	cx: int,
	cz: int,
	radius_cells: int
) -> Dictionary:
	## Inspect the perimeter ring around a candidate lake center to evaluate slope and containment.
	var rim_min := INF
	var rim_max := -INF
	var rim_sum := 0.0
	var rim_count := 0
	var has_sea := false
	var r_lo := float(radius_cells) * 0.88
	var r_hi := float(radius_cells) * 1.22
	var z0 := maxi(1, cz - radius_cells - 2)
	var z1 := mini(grid - 1, cz + radius_cells + 3)
	var x0 := maxi(1, cx - radius_cells - 2)
	var x1 := mini(grid - 1, cx + radius_cells + 3)
	for z in range(z0, z1):
		for x in range(x0, x1):
			var d := sqrt(float((x - cx) * (x - cx) + (z - cz) * (z - cz)))
			if d < r_lo or d > r_hi:
				continue
			var i := MapHeightfield._i(grid, x, z)
			if int(biomes[i]) == MapTypes.Biome.SEA:
				has_sea = true
				break
			var h := heights[i]
			rim_min = minf(rim_min, h)
			rim_max = maxf(rim_max, h)
			rim_sum += h
			rim_count += 1
		if has_sea:
			break
	var rim_mean := rim_sum / float(maxi(rim_count, 1))
	return {
		"valid": (not has_sea) and rim_count >= 12,
		"min": rim_min,
		"max": rim_max,
		"mean": rim_mean,
	}


static func _carve_lake_basin(
	out: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	cx: int,
	cz: int,
	radius_cells: int,
	lake_water: float
) -> Dictionary:
	## Carve the submerged lake bowl and raise/blend a continuous containment bank outside the shore.
	var step := size / float(grid - 1)
	var center_w := MapHeightfield._cell_world(cx, cz, grid, size)
	var r_world := float(radius_cells) * step
	var outer_cells := int(ceil(float(radius_cells) * 1.85)) + 1
	var z0 := maxi(1, cz - outer_cells)
	var z1 := mini(grid - 1, cz + outer_cells + 1)
	var x0 := maxi(1, cx - outer_cells)
	var x1 := mini(grid - 1, cx + outer_cells + 1)

	var cells: Array[Vector2i] = []
	var cell_set: Dictionary = {}

	for z in range(z0, z1):
		for x in range(x0, x1):
			var i := MapHeightfield._i(grid, x, z)
			if int(biomes[i]) == MapTypes.Biome.SEA:
				continue
			var pw := MapHeightfield._cell_world(x, z, grid, size)
			var d_vec := pw - center_w
			var dist := d_vec.length()
			var ang := atan2(d_vec.y, d_vec.x)
			if ang < 0.0:
				ang += TAU
			var eff_r := r_world * _lake_organic_scale(ang, center_w)
			var eff_nd := dist / maxf(eff_r, 0.1)
			if eff_nd > 1.75:
				continue

			if eff_nd <= 0.96:
				# Inside lake waterline: carve shallow wadeable rim -> swimmable center.
				var u := clampf(1.0 - eff_nd / 0.96, 0.0, 1.0)
				var bed := lerpf(lake_water - 0.38, lake_water - 1.85, pow(u, 0.55))
				out[i] = minf(out[i], bed)
				biomes[i] = MapTypes.Biome.LAKE
				var c := Vector2i(x, z)
				cells.append(c)
				cell_set[c] = true
			elif eff_nd <= 1.20:
				# Immediate shore bank: keep ground strictly above lake_water so water cannot spill.
				var t_bank := smoothstep(0.96, 1.20, eff_nd)
				var bank_floor := lerpf(lake_water + 0.08, lake_water + 0.34, t_bank)
				out[i] = maxf(out[i], bank_floor)
			else:
				# Outer berm blend: taper smoothly back to surrounding terrain.
				var t_out := 1.0 - smoothstep(1.20, 1.75, eff_nd)
				var berm_target := lerpf(out[i], lake_water + 0.34, t_out)
				out[i] = maxf(out[i], berm_target)

	for c in cells:
		for d: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= grid or n.y >= grid:
				continue
			if cell_set.has(n):
				continue
			var ni := MapHeightfield._i(grid, n.x, n.y)
			if int(biomes[ni]) == MapTypes.Biome.SEA or int(biomes[ni]) == MapTypes.Biome.LAKE:
				continue
			if int(biomes[ni]) != MapTypes.Biome.MOUNTAIN:
				biomes[ni] = MapTypes.Biome.SAND

	var min_x := center_w.x
	var max_x := center_w.x
	var min_z := center_w.y
	var max_z := center_w.y
	for c in cells:
		var pw := MapHeightfield._cell_world(c.x, c.y, grid, size)
		min_x = minf(min_x, pw.x)
		max_x = maxf(max_x, pw.x)
		min_z = minf(min_z, pw.y)
		max_z = maxf(max_z, pw.y)
	var pad := step * 0.6
	return {
		"center": center_w,
		"water_y": lake_water,
		"cells": cells,
		"radius": r_world,
		"rect": Rect2(Vector2(min_x - pad, min_z - pad), Vector2(max_x - min_x + pad * 2.0, max_z - min_z + pad * 2.0)),
	}


static func _place_lakes(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	water_y: float,
	relief: float,
	rng: RandomNumberGenerator
) -> Dictionary:
	## Carve 1–2 inland bowls with closed shore rims and flood them as LAKE biomes.
	var out := heights.duplicate()
	var lakes: Array = []
	var target_count := 1 + (1 if rng.randf() > 0.35 else 0)
	var used_centers: Array[Vector2i] = []
	var step := size / float(grid - 1)

	for _lake_idx in target_count:
		var best_cand: Dictionary = {}
		var best_score := -INF
		for _attempt in 42:
			var cx := rng.randi_range(grid / 5, grid * 4 / 5)
			var cz := rng.randi_range(grid / 5, grid * 4 / 5)
			var wxz := MapHeightfield._cell_world(cx, cz, grid, size)
			if MapHeightfield._sea_proximity(wxz.x, wxz.y, size, sea_edge) > 0.42:
				continue
			var ci := MapHeightfield._i(grid, cx, cz)
			if int(biomes[ci]) == MapTypes.Biome.SEA:
				continue
			if int(biomes[ci]) == MapTypes.Biome.MOUNTAIN and out[ci] > water_y + 4.0:
				continue
			var too_close := false
			for uc in used_centers:
				if abs(cx - uc.x) + abs(cz - uc.y) < grid / 4:
					too_close = true
					break
			if too_close:
				continue

			var radius_cells := maxi(6, int(round(rng.randf_range(10.0, 14.0) / step)))
			var rim := _sample_rim_stats(out, biomes, grid, cx, cz, radius_cells)
			if not bool(rim["valid"]):
				continue
			var rim_min := float(rim["min"])
			var rim_max := float(rim["max"])
			var rim_mean := float(rim["mean"])
			var rim_span := rim_max - rim_min
			if rim_min < water_y + 0.45:
				continue
			if rim_span > 4.2 * maxf(relief, 0.6):
				continue

			# Prefer flat/gentle basins whose rim stays well above sea level.
			var center_h := out[ci]
			var concavity := rim_mean - center_h
			var score := -rim_span * 1.6 + clampf(concavity, -1.5, 2.0) * 0.9 \
				+ MapHeightfield._inland_factor(wxz.x, wxz.y, size, sea_edge) * 1.4 \
				+ rng.randf() * 0.8
			if score > best_score:
				best_score = score
				best_cand = {
					"cx": cx,
					"cz": cz,
					"radius_cells": radius_cells,
					"rim_min": rim_min,
					"rim_mean": rim_mean,
				}

		if best_cand.is_empty():
			continue

		var bcx := int(best_cand["cx"])
		var bcz := int(best_cand["cz"])
		var brad := int(best_cand["radius_cells"])
		var r_min := float(best_cand["rim_min"])
		var r_mean := float(best_cand["rim_mean"])
		# Keep water level anchored to the actual terrain rim, never perched above flat lowlands.
		var rim_ref := lerpf(r_min, r_mean, 0.35)
		var lake_water := rim_ref - rng.randf_range(0.16, 0.36)
		lake_water = clampf(lake_water, water_y + 0.55, r_min + 0.25)

		var lake := _carve_lake_basin(out, biomes, grid, size, bcx, bcz, brad, lake_water)
		if (lake["cells"] as Array).size() >= 18:
			lakes.append(lake)
			used_centers.append(Vector2i(bcx, bcz))

	# Guarantee at least one inland lake with a valid containment rim.
	if lakes.is_empty():
		var best := Vector2i(grid / 2, grid / 2)
		var best_score := -INF
		var radius_cells2 := maxi(6, int(round(11.5 / step)))
		var best_rim := {"min": water_y + 1.0, "mean": water_y + 1.2}
		for z in range(grid / 4, grid * 3 / 4, 2):
			for x in range(grid / 4, grid * 3 / 4, 2):
				var wxz := MapHeightfield._cell_world(x, z, grid, size)
				if MapHeightfield._sea_proximity(wxz.x, wxz.y, size, sea_edge) > 0.40:
					continue
				if int(biomes[MapHeightfield._i(grid, x, z)]) == MapTypes.Biome.SEA:
					continue
				var rim2 := _sample_rim_stats(out, biomes, grid, x, z, radius_cells2)
				if not bool(rim2["valid"]):
					continue
				var rmin2 := float(rim2["min"])
				var rspan2 := float(rim2["max"]) - rmin2
				var score := -rspan2 * 1.5 + MapHeightfield._inland_factor(wxz.x, wxz.y, size, sea_edge) * 2.0
				if rmin2 < water_y + 0.45:
					score -= (water_y + 0.45 - rmin2) * 4.0
				if score > best_score:
					best_score = score
					best = Vector2i(x, z)
					best_rim = rim2
		var r_min2 := float(best_rim["min"])
		var r_mean2 := float(best_rim["mean"])
		var lake_water2 := clampf(lerpf(r_min2, r_mean2, 0.35) - 0.22, water_y + 0.55, maxf(water_y + 0.55, r_min2 + 0.25))
		lakes.append(_carve_lake_basin(out, biomes, grid, size, best.x, best.y, radius_cells2, lake_water2))

	return {"heights": out, "lakes": lakes}


static func _enforce_lake_containment(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	lakes: Array
) -> void:
	## Re-assert closed lake banks after smoothing/slope-limiting/river-valley carving
	## while keeping carved river inlets and spillway outlets (Biome.RIVER) open.
	if lakes.is_empty():
		return
	var step := size / float(grid - 1)
	for lake in lakes:
		var center_w: Vector2 = lake["center"]
		var r_world: float = float(lake.get("radius", 8.0))
		var ly: float = float(lake["water_y"])
		var reach := r_world * 1.38
		var cx := int(round((center_w.x / size + 0.5) * float(grid - 1)))
		var cz := int(round((center_w.y / size + 0.5) * float(grid - 1)))
		var rad := int(ceil(reach / step)) + 2
		var z0 := maxi(0, cz - rad)
		var z1 := mini(grid - 1, cz + rad)
		var x0 := maxi(0, cx - rad)
		var x1 := mini(grid - 1, cx + rad)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var i := MapHeightfield._i(grid, x, z)
				var b := int(biomes[i])
				if b == MapTypes.Biome.SEA or b == MapTypes.Biome.LAKE or b == MapTypes.Biome.RIVER:
					continue
				var pw := MapHeightfield._cell_world(x, z, grid, size)
				var d_vec := pw - center_w
				var dist := d_vec.length()
				var ang := atan2(d_vec.y, d_vec.x)
				if ang < 0.0:
					ang += TAU
				var eff_r := r_world * _lake_organic_scale(ang, center_w)
				var eff_nd := dist / maxf(eff_r, 0.1)
				if eff_nd < 0.94 or eff_nd > 1.38:
					continue
				var bank_floor := ly + 0.10
				if eff_nd <= 1.15:
					bank_floor = lerpf(ly + 0.08, ly + 0.30, smoothstep(0.94, 1.15, eff_nd))
				else:
					bank_floor = lerpf(ly + 0.30, ly + 0.05, smoothstep(1.15, 1.38, eff_nd))
				heights[i] = maxf(heights[i], bank_floor)


static func _near_lake(lakes: Array, wx: float, wz: float) -> bool:
	for lake in lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake["radius"]) + 2.0
		if Vector2(wx, wz).distance_to(c) < r:
			return true
	return false


static func _lake_shore_clearance(p: Vector2, lakes: Array) -> float:
	## Distance beyond the nearest lake shore (negative = inside/over water).
	if lakes.is_empty():
		return INF
	var best := INF
	for lake in lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake["radius"])
		best = minf(best, p.distance_to(c) - r)
	return best


static func _polyline_lake_clearance(
	pts: PackedVector2Array, lakes: Array, skip_tail_frac: float = 0.0
) -> float:
	if pts.is_empty() or lakes.is_empty():
		return INF
	var last := maxi(1, int(ceil(float(pts.size()) * (1.0 - clampf(skip_tail_frac, 0.0, 0.9)))))
	var best := INF
	for i in last:
		best = minf(best, _lake_shore_clearance(pts[i], lakes))
	return best


static func _push_polyline_from_lakes(
	pts: PackedVector2Array,
	lakes: Array,
	gap: float,
	protect_tail_frac: float = 0.0,
	protect_head_frac: float = 0.0
) -> PackedVector2Array:
	## Nudge points that skim a lake shore so ribbons don't merge into the disc.
	if pts.size() < 2 or lakes.is_empty():
		return pts
	var out := pts.duplicate()
	var i0 := int(floor(float(out.size()) * clampf(protect_head_frac, 0.0, 0.4)))
	var i1 := int(floor(float(out.size()) * (1.0 - clampf(protect_tail_frac, 0.0, 0.5))))
	for pass_i in 2:
		var use_gap := gap if pass_i == 0 else minf(gap, 2.5)
		for i in range(i0, i1):
			var p: Vector2 = out[i]
			for lake in lakes:
				var c: Vector2 = lake["center"]
				var need := float(lake["radius"]) + use_gap
				var d: Vector2 = p - c
				var dist := d.length()
				if dist < 1e-4:
					d = Vector2(1, 0)
					dist = 1e-4
				if dist < need:
					out[i] = c + d * (need / dist)
					p = out[i]
	return out


static func _lake_y_at_cell(
	lakes: Array, x: int, z: int, grid: int, size: float, fallback: float
) -> float:
	var p := MapHeightfield._cell_world(x, z, grid, size)
	for lake in lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake["radius"]) + 1.5
		if p.distance_to(c) <= r:
			return float(lake["water_y"])
	return fallback


static func _mouth_water_y(
	p: Vector2, biomes: PackedByteArray, grid: int, size: float, water_y: float, lakes: Array
) -> float:
	## Water surface height where a river ends (sea or lake).
	var ix := clampi(int(round((p.x / size + 0.5) * float(grid - 1))), 0, grid - 1)
	var iz := clampi(int(round((p.y / size + 0.5) * float(grid - 1))), 0, grid - 1)
	var b := int(biomes[MapHeightfield._i(grid, ix, iz)])
	if b == MapTypes.Biome.LAKE:
		return _lake_y_at_cell(lakes, ix, iz, grid, size, water_y + 1.0)
	# Near any lake center
	for lake in lakes:
		var c: Vector2 = lake["center"]
		if p.distance_to(c) < float(lake["radius"]) + 3.0:
			return float(lake["water_y"])
	return water_y
