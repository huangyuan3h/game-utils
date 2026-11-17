extends RefCounted
## Inland lake basins: placement, shore queries, and the water height a river mouth should meet.
class_name MapLakes

const MapTypes = preload("res://scripts/map/map_types.gd")
const MapHeightfield = preload("res://scripts/map/map_heightfield.gd")

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
	## Carve 1–2 inland bowls and flood them as LAKE biomes.
	var out := heights.duplicate()
	var lakes: Array = []
	var target_count := 1 + (1 if rng.randf() > 0.35 else 0)
	var used_centers: Array[Vector2i] = []

	for _attempt in 24:
		if lakes.size() >= target_count:
			break
		var cx := rng.randi_range(grid / 5, grid * 4 / 5)
		var cz := rng.randi_range(grid / 5, grid * 4 / 5)
		var wxz := MapHeightfield._cell_world(cx, cz, grid, size)
		if MapHeightfield._sea_proximity(wxz.x, wxz.y, size, sea_edge) > 0.42:
			continue
		if int(biomes[MapHeightfield._i(grid, cx, cz)]) == MapTypes.Biome.SEA:
			continue
		if int(biomes[MapHeightfield._i(grid, cx, cz)]) == MapTypes.Biome.MOUNTAIN and heights[MapHeightfield._i(grid, cx, cz)] > water_y + 4.0:
			continue # avoid carving mountain peaks into lakes
		var too_close := false
		for uc in used_centers:
			if abs(cx - uc.x) + abs(cz - uc.y) < grid / 4:
				too_close = true
				break
		if too_close:
			continue

		var radius_cells := rng.randi_range(8, 12)
		var deepen := (0.95 + rng.randf() * 0.65) * relief
		var bed_center := out[MapHeightfield._i(grid, cx, cz)] - deepen
		var lake_water := bed_center + 0.55 + rng.randf() * 0.30
		# Keep lakes clearly above sea so the coastal plane does not flood them
		lake_water = maxf(lake_water, water_y + 0.85)
		bed_center = minf(bed_center, lake_water - 0.45)

		# Snapshot region so a rejected bowl does not leave scars
		var snap: Dictionary = {}
		var z0 := maxi(1, cz - radius_cells - 2)
		var z1 := mini(grid - 1, cz + radius_cells + 3)
		var x0 := maxi(1, cx - radius_cells - 2)
		var x1 := mini(grid - 1, cx + radius_cells + 3)
		for z in range(z0, z1):
			for x in range(x0, x1):
				snap[MapHeightfield._i(grid, x, z)] = out[MapHeightfield._i(grid, x, z)]

		var cells: Array[Vector2i] = []
		var r2 := float(radius_cells * radius_cells)
		for z in range(z0, z1):
			for x in range(x0, x1):
				var dx := float(x - cx)
				var dz := float(z - cz)
				var d2 := dx * dx + dz * dz
				if d2 > r2 * 1.35:
					continue
				var i := MapHeightfield._i(grid, x, z)
				if int(biomes[i]) == MapTypes.Biome.SEA:
					continue
				var t := clampf(1.0 - d2 / (r2 * 1.15), 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				var target_bed := lerpf(out[i], bed_center, t * 0.95)
				out[i] = minf(out[i], target_bed)
				if out[i] < lake_water - 0.05 and d2 <= r2:
					cells.append(Vector2i(x, z))

		if cells.size() < 18 or cells.size() > 220:
			for k in snap.keys():
				out[int(k)] = float(snap[k])
			continue

		# Mark lake cells + sand shore ring
		var cell_set: Dictionary = {}
		for c in cells:
			cell_set[c] = true
			biomes[MapHeightfield._i(grid, c.x, c.y)] = MapTypes.Biome.LAKE
			out[MapHeightfield._i(grid, c.x, c.y)] = minf(out[MapHeightfield._i(grid, c.x, c.y)], lake_water - 0.30)

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

		var center_w := MapHeightfield._cell_world(cx, cz, grid, size)
		# Axis-aligned footprint for mesh (expanded slightly)
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		for c in cells:
			var pw := MapHeightfield._cell_world(c.x, c.y, grid, size)
			min_x = minf(min_x, pw.x)
			max_x = maxf(max_x, pw.x)
			min_z = minf(min_z, pw.y)
			max_z = maxf(max_z, pw.y)
		var pad := size / float(grid - 1) * 0.6
		lakes.append({
			"center": center_w,
			"water_y": lake_water,
			"cells": cells,
			"radius": float(radius_cells) * size / float(grid - 1),
			"rect": Rect2(Vector2(min_x - pad, min_z - pad), Vector2(max_x - min_x + pad * 2.0, max_z - min_z + pad * 2.0)),
		})
		used_centers.append(Vector2i(cx, cz))

	# Guarantee at least one inland lake
	if lakes.is_empty():
		var best := Vector2i(grid / 2, grid / 2)
		var best_score := -INF
		for z in range(grid / 4, grid * 3 / 4):
			for x in range(grid / 4, grid * 3 / 4):
				var wxz := MapHeightfield._cell_world(x, z, grid, size)
				if MapHeightfield._sea_proximity(wxz.x, wxz.y, size, sea_edge) > 0.40:
					continue
				if int(biomes[MapHeightfield._i(grid, x, z)]) == MapTypes.Biome.SEA:
					continue
				# Prefer mid-elevation inland bowls
				var score := -out[MapHeightfield._i(grid, x, z)] + MapHeightfield._inland_factor(wxz.x, wxz.y, size, sea_edge) * 2.0
				if score > best_score:
					best_score = score
					best = Vector2i(x, z)
		var cx2 := best.x
		var cz2 := best.y
		var radius_cells2 := 10
		var lake_water2 := maxf(out[MapHeightfield._i(grid, cx2, cz2)] - 0.15, water_y + 0.9)
		var bed2 := lake_water2 - 0.70
		var cells2: Array[Vector2i] = []
		var r22 := float(radius_cells2 * radius_cells2)
		for z in range(maxi(1, cz2 - radius_cells2 - 1), mini(grid - 1, cz2 + radius_cells2 + 2)):
			for x in range(maxi(1, cx2 - radius_cells2 - 1), mini(grid - 1, cx2 + radius_cells2 + 2)):
				var dx := float(x - cx2)
				var dz := float(z - cz2)
				var d2 := dx * dx + dz * dz
				if d2 > r22 * 1.15:
					continue
				var i := MapHeightfield._i(grid, x, z)
				if int(biomes[i]) == MapTypes.Biome.SEA:
					continue
				var t := clampf(1.0 - d2 / r22, 0.0, 1.0)
				out[i] = lerpf(out[i], bed2, t * 0.9)
				if d2 <= r22 * 0.92:
					cells2.append(Vector2i(x, z))
					biomes[i] = MapTypes.Biome.LAKE
					out[i] = minf(out[i], lake_water2 - 0.28)
		for c in cells2:
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if n.x < 0 or n.y < 0 or n.x >= grid or n.y >= grid:
					continue
				var ni := MapHeightfield._i(grid, n.x, n.y)
				if int(biomes[ni]) == MapTypes.Biome.GRASS or int(biomes[ni]) == MapTypes.Biome.DIRT:
					biomes[ni] = MapTypes.Biome.SAND
		var center_w2 := MapHeightfield._cell_world(cx2, cz2, grid, size)
		var pad2 := size / float(grid - 1) * 0.6
		var min_x2 := center_w2.x
		var max_x2 := center_w2.x
		var min_z2 := center_w2.y
		var max_z2 := center_w2.y
		for c in cells2:
			var pw := MapHeightfield._cell_world(c.x, c.y, grid, size)
			min_x2 = minf(min_x2, pw.x)
			max_x2 = maxf(max_x2, pw.x)
			min_z2 = minf(min_z2, pw.y)
			max_z2 = maxf(max_z2, pw.y)
		lakes.append({
			"center": center_w2,
			"water_y": lake_water2,
			"cells": cells2,
			"radius": float(radius_cells2) * size / float(grid - 1),
			"rect": Rect2(Vector2(min_x2 - pad2, min_z2 - pad2), Vector2(max_x2 - min_x2 + pad2 * 2.0, max_z2 - min_z2 + pad2 * 2.0)),
		})

	return {"heights": out, "lakes": lakes}


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
	for i in range(i0, i1):
		var p: Vector2 = out[i]
		for lake in lakes:
			var c: Vector2 = lake["center"]
			var need := float(lake["radius"]) + gap
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
