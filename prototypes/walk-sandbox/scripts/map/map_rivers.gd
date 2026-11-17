extends RefCounted
## River courses: downhill trace, guaranteed sea/lake outlet, meander, and channel carve.
class_name MapRivers

const MapTypes = preload("res://scripts/map/map_types.gd")
const MapHeightfield = preload("res://scripts/map/map_heightfield.gd")
const MapLakes = preload("res://scripts/map/map_lakes.gd")


static func river_half_width(along: float) -> float:
	return lerpf(MapTypes.RIVER_HALF_W_SRC, MapTypes.RIVER_HALF_W_MOUTH, pow(clampf(along, 0.0, 1.0), 0.55))


static func river_depth(along: float) -> float:
	return lerpf(MapTypes.RIVER_DEPTH_SRC, MapTypes.RIVER_DEPTH_MOUTH, pow(clampf(along, 0.0, 1.0), 0.35))


## --- Rivers ---------------------------------------------------------------
## Guarantee algorithm:
##   1. Pick highland springs
##   2. Flow downhill (prefer sea; lakes allowed)
##   3. If no water hit → steer to nearest sea/lake until hit (always succeeds)
##   4. Meander gently, then snap the tip into the water body
##   5. Drop only duplicates / tiny stubs — never keep a river without an outlet

static func _trace_rivers(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	water_y: float,
	lakes: Array,
	rng: RandomNumberGenerator
) -> Array:
	var sources := _collect_river_sources(heights, biomes, grid, size, sea_edge, water_y)
	var candidates: Array = []
	for src in sources:
		# Prefer a sea-bound course; fall back to any water, then force-steer.
		var built: Dictionary = _build_guaranteed_river(
			src, heights, biomes, grid, size, sea_edge, lakes, rng, "sea"
		)
		if built.is_empty():
			built = _build_guaranteed_river(
				src, heights, biomes, grid, size, sea_edge, lakes, rng, "any"
			)
		if built.is_empty():
			continue
		candidates.append(built)

	# Absolute fallback: one forced sea river from the tallest source
	if candidates.is_empty() and not sources.is_empty():
		var forced: Dictionary = _build_guaranteed_river(
			sources[0], heights, biomes, grid, size, sea_edge, lakes, rng, "sea"
		)
		if forced.is_empty():
			forced = _force_river_to_sea(
				sources[0], heights, biomes, grid, size, sea_edge, lakes, rng
			)
		if not forced.is_empty():
			candidates.append(forced)

	return _pick_best_rivers(candidates, 2)


static func _collect_river_sources(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	water_y: float
) -> Array[Vector2i]:
	var sources: Array[Vector2i] = []
	var mountain_cells: Array[Vector2i] = []
	for z in grid:
		for x in grid:
			if int(biomes[MapHeightfield._i(grid, x, z)]) != MapTypes.Biome.MOUNTAIN:
				continue
			var wxz := MapHeightfield._cell_world(x, z, grid, size)
			if MapHeightfield._sea_proximity(wxz.x, wxz.y, size, sea_edge) > 0.40:
				continue
			if heights[MapHeightfield._i(grid, x, z)] < water_y + 2.5:
				continue
			mountain_cells.append(Vector2i(x, z))
	mountain_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return heights[MapHeightfield._i(grid, a.x, a.y)] > heights[MapHeightfield._i(grid, b.x, b.y)]
	)
	for c in mountain_cells:
		var ok := true
		for s in sources:
			if abs(c.x - s.x) + abs(c.y - s.y) < grid / 5:
				ok = false
				break
		if ok:
			sources.append(c)
		if sources.size() >= 8:
			break
	if sources.is_empty() and not mountain_cells.is_empty():
		sources.append(mountain_cells[0])
	if sources.is_empty():
		var best := Vector2i(grid / 2, grid / 2)
		var best_h := -INF
		for z in range(grid / 5, grid * 4 / 5):
			for x in range(grid / 5, grid * 4 / 5):
				var wxz2 := MapHeightfield._cell_world(x, z, grid, size)
				if MapHeightfield._sea_proximity(wxz2.x, wxz2.y, size, sea_edge) > 0.45:
					continue
				var hh := heights[MapHeightfield._i(grid, x, z)]
				if hh > best_h:
					best_h = hh
					best = Vector2i(x, z)
		sources.append(best)
	return sources


static func _build_guaranteed_river(
	src: Vector2i,
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	lakes: Array,
	rng: RandomNumberGenerator,
	mode: String ## "sea" | "lake" | "any"
) -> Dictionary:
	var trace: Dictionary = _trace_downhill_to_water(
		src, heights, biomes, grid, size, sea_edge, lakes, rng, mode
	)
	var path: Array[Vector2i] = trace.get("path", []) as Array
	var outlet: String = str(trace.get("outlet", ""))
	if outlet == "" or path.size() < 8:
		# Steer until we physically enter a water cell — always terminates
		trace = _steer_to_nearest_water(
			src if path.is_empty() else path[path.size() - 1],
			path, heights, biomes, grid, size, sea_edge, lakes, rng, mode
		)
		path = trace.get("path", []) as Array
		outlet = str(trace.get("outlet", ""))
	if outlet == "" or path.size() < 8:
		return {}

	var pts := PackedVector2Array()
	for cell in path:
		pts.append(MapHeightfield._cell_world(cell.x, cell.y, grid, size))
	pts = _sine_meander_path(pts, size, sea_edge, rng)
	if outlet == "sea":
		pts = MapLakes._push_polyline_from_lakes(pts, lakes, MapTypes.LAKE_RIVER_GAP * 0.85, 0.0)
	else:
		pts = MapLakes._push_polyline_from_lakes(pts, lakes, MapTypes.LAKE_RIVER_GAP * 0.6, 0.25)
	pts = _snap_mouth_into_water(pts, outlet, lakes, sea_edge, size)
	if not _river_reaches_outlet(pts, outlet, lakes, sea_edge, size):
		pts = _hard_guarantee_mouth(pts, outlet, lakes, sea_edge, size)
	if pts.size() < 6 or not _river_reaches_outlet(pts, outlet, lakes, sea_edge, size):
		return {}
	var plen := _polyline_length(pts)
	if plen < 12.0:
		return {}
	return {
		"pts": pts,
		"src": src,
		"outlet": outlet,
		"len": plen,
		"near": _polyline_min_dist(pts, Vector2.ZERO),
		"lake_clear": MapLakes._polyline_lake_clearance(pts, lakes, 0.2 if outlet == "lake" else 0.0),
	}


static func _trace_downhill_to_water(
	src: Vector2i,
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	lakes: Array,
	rng: RandomNumberGenerator,
	mode: String
) -> Dictionary:
	var path: Array[Vector2i] = []
	var visited: Dictionary = {}
	var cur := src
	var prev := Vector2i(0, 0)
	var outlet := ""
	for _step in 220:
		if visited.has(cur):
			break
		visited[cur] = true
		path.append(cur)
		var cb := int(biomes[MapHeightfield._i(grid, cur.x, cur.y)])
		if cb == MapTypes.Biome.SEA and mode != "lake":
			outlet = "sea"
			break
		if cb == MapTypes.Biome.LAKE and mode != "sea":
			outlet = "lake"
			break
		var best_n := Vector2i(-9999, -9999)
		var best_score := 1e30
		var cur_h := heights[MapHeightfield._i(grid, cur.x, cur.y)]
		for d: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var n: Vector2i = cur + d
			if n.x < 1 or n.y < 1 or n.x >= grid - 1 or n.y >= grid - 1:
				continue
			if visited.has(n):
				continue
			var nb := int(biomes[MapHeightfield._i(grid, n.x, n.y)])
			if mode == "sea" and nb == MapTypes.Biome.LAKE:
				continue
			if mode == "lake" and nb == MapTypes.Biome.SEA:
				continue
			if nb == MapTypes.Biome.SEA or nb == MapTypes.Biome.LAKE:
				best_n = n
				best_score = -1e29
				outlet = "sea" if nb == MapTypes.Biome.SEA else "lake"
				break
			var nh := heights[MapHeightfield._i(grid, n.x, n.y)]
			var score: float = nh + rng.randf() * 0.04
			if nh > cur_h:
				score += (nh - cur_h) * 4.0 + 0.35
			var nwx: Vector2 = MapHeightfield._cell_world(n.x, n.y, grid, size)
			var sea_p := MapHeightfield._sea_proximity(nwx.x, nwx.y, size, sea_edge)
			score += nwx.length() * 0.01
			if mode == "lake" and not lakes.is_empty():
				var along_approx := float(path.size()) / 220.0
				var lc: Vector2 = lakes[0]["center"]
				var lake_d := nwx.distance_to(lc)
				if along_approx < 0.7:
					score += maxf(0.0, float(lakes[0]["radius"]) + MapTypes.LAKE_RIVER_GAP - lake_d) * 0.7
				else:
					score += lake_d * 0.04
			elif mode == "sea":
				score -= sea_p * 0.55
				for lake in lakes:
					var gap := nwx.distance_to(lake["center"] as Vector2) - float(lake["radius"])
					if gap < MapTypes.LAKE_RIVER_GAP:
						score += (MapTypes.LAKE_RIVER_GAP - gap) * 1.2
			else: # any
				score -= sea_p * 0.35
				if not lakes.is_empty():
					score += nwx.distance_to(lakes[0]["center"] as Vector2) * 0.01
			if prev != Vector2i(0, 0):
				var come: Vector2i = cur - prev
				if d == -come:
					score += 0.3
			if score < best_score:
				best_score = score
				best_n = n
		if best_n.x == -9999:
			break
		if best_score < -1e28:
			path.append(best_n)
			break
		prev = cur
		cur = best_n
	return {"path": path, "outlet": outlet}


static func _steer_to_nearest_water(
	from: Vector2i,
	existing: Array,
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	lakes: Array,
	rng: RandomNumberGenerator,
	mode: String
) -> Dictionary:
	## Greedy steer toward a concrete water target until the cell biome is water.
	var path: Array[Vector2i] = existing.duplicate()
	var visited: Dictionary = {}
	for c in path:
		visited[c] = true
	var cur: Vector2i = from if path.is_empty() else path[path.size() - 1]
	var target := _pick_water_target_cell(cur, biomes, grid, size, sea_edge, lakes, mode)
	var outlet := ""
	for _step in 260:
		if visited.has(cur) and path.size() > existing.size() + 2:
			# mild escape: jump toward target
			cur = Vector2i(
				clampi(cur.x + int(signi(target.x - cur.x)), 1, grid - 2),
				clampi(cur.y + int(signi(target.y - cur.y)), 1, grid - 2)
			)
		if not visited.has(cur):
			visited[cur] = true
			path.append(cur)
		var cb := int(biomes[MapHeightfield._i(grid, cur.x, cur.y)])
		if cb == MapTypes.Biome.SEA and mode != "lake":
			outlet = "sea"
			break
		if cb == MapTypes.Biome.LAKE and mode != "sea":
			outlet = "lake"
			break
		var best_n := Vector2i(-9999, -9999)
		var best_score := 1e30
		var cur_h := heights[MapHeightfield._i(grid, cur.x, cur.y)]
		for d: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var n: Vector2i = cur + d
			if n.x < 1 or n.y < 1 or n.x >= grid - 1 or n.y >= grid - 1:
				continue
			if visited.has(n):
				continue
			var nb := int(biomes[MapHeightfield._i(grid, n.x, n.y)])
			if mode == "sea" and nb == MapTypes.Biome.LAKE:
				continue
			if nb == MapTypes.Biome.SEA or nb == MapTypes.Biome.LAKE:
				if mode == "sea" and nb != MapTypes.Biome.SEA:
					continue
				if mode == "lake" and nb != MapTypes.Biome.LAKE:
					continue
				best_n = n
				best_score = -1e29
				outlet = "sea" if nb == MapTypes.Biome.SEA else "lake"
				break
			var nh := heights[MapHeightfield._i(grid, n.x, n.y)]
			var score: float = float(absi(n.x - target.x) + absi(n.y - target.y))
			score += nh * 0.15
			if nh > cur_h:
				score += (nh - cur_h) * 2.5
			score += rng.randf() * 0.05
			if score < best_score:
				best_score = score
				best_n = n
		if best_n.x == -9999:
			# teleport one step toward target
			var step := Vector2i(int(signi(target.x - cur.x)), int(signi(target.y - cur.y)))
			if step == Vector2i.ZERO:
				break
			cur = Vector2i(
				clampi(cur.x + step.x, 1, grid - 2),
				clampi(cur.y + step.y, 1, grid - 2)
			)
			continue
		if best_score < -1e28:
			path.append(best_n)
			break
		cur = best_n
	return {"path": path, "outlet": outlet}


static func _pick_water_target_cell(
	from: Vector2i,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	lakes: Array,
	mode: String
) -> Vector2i:
	## Concrete cell inside sea or lake to steer toward.
	if mode != "sea" and not lakes.is_empty():
		var lake: Dictionary = lakes[0]
		var c: Vector2 = lake["center"]
		return Vector2i(
			clampi(int(round((c.x / size + 0.5) * float(grid - 1))), 2, grid - 3),
			clampi(int(round((c.y / size + 0.5) * float(grid - 1))), 2, grid - 3)
		)
	# Sea: walk the coastal band for a SEA cell nearest to `from`
	var best := from
	var best_d := 1_000_000
	var band := maxi(2, grid / 12)
	match sea_edge:
		0: # +Z sea
			for x in range(1, grid - 1):
				for z in range(grid - band, grid - 1):
					if int(biomes[MapHeightfield._i(grid, x, z)]) == MapTypes.Biome.SEA:
						var d := absi(x - from.x) + absi(z - from.y)
						if d < best_d:
							best_d = d
							best = Vector2i(x, z)
		1: # -Z sea
			for x in range(1, grid - 1):
				for z in range(1, band):
					if int(biomes[MapHeightfield._i(grid, x, z)]) == MapTypes.Biome.SEA:
						var d := absi(x - from.x) + absi(z - from.y)
						if d < best_d:
							best_d = d
							best = Vector2i(x, z)
		2: # +X sea
			for z in range(1, grid - 1):
				for x in range(grid - band, grid - 1):
					if int(biomes[MapHeightfield._i(grid, x, z)]) == MapTypes.Biome.SEA:
						var d := absi(x - from.x) + absi(z - from.y)
						if d < best_d:
							best_d = d
							best = Vector2i(x, z)
		_: # -X sea
			for z in range(1, grid - 1):
				for x in range(1, band):
					if int(biomes[MapHeightfield._i(grid, x, z)]) == MapTypes.Biome.SEA:
						var d := absi(x - from.x) + absi(z - from.y)
						if d < best_d:
							best_d = d
							best = Vector2i(x, z)
	if best_d >= 1_000_000:
		# No SEA cell found — aim at map edge center
		var outward := _sea_outward(sea_edge)
		best = Vector2i(
			clampi(grid / 2 + int(outward.x) * (grid / 2 - 2), 1, grid - 2),
			clampi(grid / 2 + int(outward.y) * (grid / 2 - 2), 1, grid - 2)
		)
	return best


static func _force_river_to_sea(
	src: Vector2i,
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	lakes: Array,
	rng: RandomNumberGenerator
) -> Dictionary:
	var empty: Array[Vector2i] = []
	var trace: Dictionary = _steer_to_nearest_water(
		src, empty, heights, biomes, grid, size, sea_edge, lakes, rng, "sea"
	)
	var path: Array[Vector2i] = trace.get("path", []) as Array
	if path.size() < 6:
		return {}
	var pts := PackedVector2Array()
	for cell in path:
		pts.append(MapHeightfield._cell_world(cell.x, cell.y, grid, size))
	pts = _sine_meander_path(pts, size, sea_edge, rng)
	pts = MapLakes._push_polyline_from_lakes(pts, lakes, MapTypes.LAKE_RIVER_GAP * 0.7, 0.0)
	pts = _hard_guarantee_mouth(pts, "sea", lakes, sea_edge, size)
	return {
		"pts": pts,
		"src": src,
		"outlet": "sea",
		"len": _polyline_length(pts),
		"near": _polyline_min_dist(pts, Vector2.ZERO),
		"lake_clear": MapLakes._polyline_lake_clearance(pts, lakes, 0.0),
	}


static func _river_reaches_outlet(
	pts: PackedVector2Array, outlet: String, lakes: Array, sea_edge: int, size: float
) -> bool:
	if pts.size() < 2:
		return false
	var end: Vector2 = pts[pts.size() - 1]
	if outlet == "lake":
		for lake in lakes:
			if end.distance_to(lake["center"] as Vector2) <= float(lake["radius"]) * 0.95:
				return true
		return false
	return MapHeightfield._sea_proximity(end.x, end.y, size, sea_edge) >= 0.70


static func _snap_mouth_into_water(
	pts: PackedVector2Array, outlet: String, lakes: Array, sea_edge: int, size: float
) -> PackedVector2Array:
	## Soft natural entry: ease the last stretch into sea/lake, then hard-guarantee tip.
	if pts.size() < 2:
		return pts
	var out := pts.duplicate()
	var last: Vector2 = out[out.size() - 1]
	var prev: Vector2 = out[out.size() - 2]
	var flow := (last - prev).normalized()
	if flow.length_squared() < 1e-6:
		flow = _sea_outward(sea_edge)
	if outlet == "lake" and not lakes.is_empty():
		var best_i := 0
		var best_d := INF
		for i in lakes.size():
			var d: float = last.distance_to(lakes[i]["center"] as Vector2)
			if d < best_d:
				best_d = d
				best_i = i
		var c: Vector2 = lakes[best_i]["center"]
		var r: float = float(lakes[best_i]["radius"])
		var to_c := (c - last).normalized()
		var enter := (flow * 0.3 + to_c * 0.7).normalized()
		out.append(last + enter * maxf(2.0, r * 0.25))
		out.append(c - to_c * (r * 0.45))
		out.append(c - to_c * (r * 0.18))
	else:
		var outward := _sea_outward(sea_edge)
		var dir := (flow * 0.45 + outward * 0.55).normalized()
		out.append(last + dir * (size * 0.03))
		out.append(last + dir * (size * 0.055) + outward * (size * 0.02))
		out.append(_sea_mouth_anchor(size, sea_edge, last))
	return out


static func _sea_mouth_anchor(size: float, sea_edge: int, near: Vector2) -> Vector2:
	## A point firmly in open coastal water, biased toward the river approach.
	var half := size * 0.5
	var outward := _sea_outward(sea_edge)
	var edge := outward * (half * 0.92)
	match sea_edge:
		0, 1:
			return Vector2(clampf(near.x, -half * 0.7, half * 0.7), edge.y)
		_:
			return Vector2(edge.x, clampf(near.y, -half * 0.7, half * 0.7))


static func _hard_guarantee_mouth(
	pts: PackedVector2Array, outlet: String, lakes: Array, sea_edge: int, size: float
) -> PackedVector2Array:
	## Last resort: append a tip that geometrically lies inside the water body.
	if pts.is_empty():
		return pts
	var out := pts.duplicate()
	var last: Vector2 = out[out.size() - 1]
	if outlet == "lake" and not lakes.is_empty():
		var best_i := 0
		var best_d := INF
		for i in lakes.size():
			var d: float = last.distance_to(lakes[i]["center"] as Vector2)
			if d < best_d:
				best_d = d
				best_i = i
		var c: Vector2 = lakes[best_i]["center"]
		var r: float = float(lakes[best_i]["radius"])
		out.append(c.lerp(last, 0.15))
		out.append(c + (last - c).normalized() * (r * 0.15))
	else:
		out.append(_sea_mouth_anchor(size, sea_edge, last))
	return out


static func _polyline_length(pts: PackedVector2Array) -> float:
	var L := 0.0
	for i in range(pts.size() - 1):
		L += pts[i].distance_to(pts[i + 1])
	return L


static func _polyline_min_dist(pts: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for q in pts:
		best = minf(best, q.distance_to(p))
	return best


static func _pick_best_rivers(candidates: Array, want: int) -> Array:
	## Prefer long near-spawn streams; keep ≥1 sea river when available; ≤1 lake feeder.
	if candidates.is_empty():
		return []
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: float = float(a["len"]) - float(a["near"]) * 1.3 + float(a.get("lake_clear", 0.0)) * 0.4
		var sb: float = float(b["len"]) - float(b["near"]) * 1.3 + float(b.get("lake_clear", 0.0)) * 0.4
		if str(a["outlet"]) == "sea":
			sa += 14.0
		if str(b["outlet"]) == "sea":
			sb += 14.0
		return sa > sb
	)
	var picked: Array = []
	var used_src: Dictionary = {}
	var lake_rivers := 0
	for c in candidates:
		if str(c["outlet"]) != "sea":
			continue
		used_src["%d,%d" % [(c["src"] as Vector2i).x, (c["src"] as Vector2i).y]] = true
		picked.append(c["pts"])
		break
	for c in candidates:
		if picked.size() >= want:
			break
		var src: Vector2i = c["src"]
		var key := "%d,%d" % [src.x, src.y]
		if used_src.has(key):
			continue
		var outlet := str(c["outlet"])
		if outlet == "lake" and lake_rivers >= 1:
			continue
		var pts: PackedVector2Array = c["pts"]
		var dup := false
		for prev in picked:
			var other: PackedVector2Array = prev
			if _polyline_min_dist(pts, other[other.size() / 2]) < 6.0 \
					and _polyline_min_dist(other, pts[pts.size() / 2]) < 6.0:
				dup = true
				break
		if dup:
			continue
		used_src[key] = true
		if outlet == "lake":
			lake_rivers += 1
		picked.append(pts)
	return picked


static func _trace_lake_outlet(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	water_y: float,
	lake: Dictionary,
	rng: RandomNumberGenerator
) -> PackedVector2Array:
	## Short river from lake shore downhill to the sea (leaves quickly, no shore wrap).
	var center: Vector2 = lake["center"]
	var cx := clampi(int(round((center.x / size + 0.5) * float(grid - 1))), 2, grid - 3)
	var cz := clampi(int(round((center.y / size + 0.5) * float(grid - 1))), 2, grid - 3)
	var sea_dir := _sea_outward(sea_edge)
	# Start on the seaward shore, not the lake center
	var start := Vector2i(cx, cz)
	var radius_cells := maxi(2, int(round(float(lake["radius"]) / (size / float(grid - 1)))))
	start = Vector2i(
		clampi(cx + int(signf(sea_dir.x)) * radius_cells, 1, grid - 2),
		clampi(cz + int(signf(sea_dir.y)) * radius_cells, 1, grid - 2)
	)
	for _k in 6:
		if int(biomes[MapHeightfield._i(grid, start.x, start.y)]) != MapTypes.Biome.LAKE:
			break
		start = Vector2i(
			clampi(start.x + int(signf(sea_dir.x)), 1, grid - 2),
			clampi(start.y + int(signf(sea_dir.y)), 1, grid - 2)
		)

	var path: Array[Vector2i] = []
	var visited: Dictionary = {}
	var cur := start
	var reached := false
	for _step in 100:
		if visited.has(cur):
			break
		visited[cur] = true
		path.append(cur)
		if int(biomes[MapHeightfield._i(grid, cur.x, cur.y)]) == MapTypes.Biome.SEA:
			reached = true
			break
		var best_n := Vector2i(-9999, -9999)
		var best_score := 1e30
		var dirs: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]
		var cur_h := heights[MapHeightfield._i(grid, cur.x, cur.y)]
		for d: Vector2i in dirs:
			var n: Vector2i = cur + d
			if n.x < 1 or n.y < 1 or n.x >= grid - 1 or n.y >= grid - 1:
				continue
			if visited.has(n):
				continue
			if int(biomes[MapHeightfield._i(grid, n.x, n.y)]) == MapTypes.Biome.LAKE:
				continue
			if int(biomes[MapHeightfield._i(grid, n.x, n.y)]) == MapTypes.Biome.SEA:
				best_n = n
				best_score = -1e29
				break
			var nh := heights[MapHeightfield._i(grid, n.x, n.y)]
			var score: float = nh + rng.randf() * 0.04
			if nh > cur_h:
				score += (nh - cur_h) * 3.5 + 0.3
			var nwx: Vector2 = MapHeightfield._cell_world(n.x, n.y, grid, size)
			score -= MapHeightfield._sea_proximity(nwx.x, nwx.y, size, sea_edge) * 0.6
			if score < best_score:
				best_score = score
				best_n = n
		if best_n.x == -9999:
			break
		if best_score < -1e28:
			path.append(best_n)
			reached = true
			break
		cur = best_n

	if not reached or path.size() < 8:
		return PackedVector2Array()
	var pts := PackedVector2Array()
	for cell in path:
		pts.append(MapHeightfield._cell_world(cell.x, cell.y, grid, size))
	pts = _sine_meander_path(pts, size, sea_edge, rng)
	pts = MapLakes._push_polyline_from_lakes(pts, [lake], MapTypes.LAKE_RIVER_GAP, 0.0, 0.08)
	pts = _snap_mouth_into_water(pts, "sea", [lake], sea_edge, size)
	if not _river_reaches_outlet(pts, "sea", [lake], sea_edge, size):
		pts = _hard_guarantee_mouth(pts, "sea", [lake], sea_edge, size)
	if not _river_reaches_outlet(pts, "sea", [lake], sea_edge, size):
		return PackedVector2Array()
	return pts


static func _sparsify_path(pts: PackedVector2Array, min_dist: float) -> PackedVector2Array:
	## Keep endpoints + points far enough apart (drop grid zigzag clutter).
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	var last: Vector2 = pts[0]
	for i in range(1, pts.size() - 1):
		if pts[i].distance_to(last) >= min_dist:
			out.append(pts[i])
			last = pts[i]
	var end: Vector2 = pts[pts.size() - 1]
	if out[out.size() - 1].distance_to(end) > 0.01:
		out.append(end)
	return out


static func _resample_arc(pts: PackedVector2Array, spacing: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	var carry := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 1e-5:
			continue
		var dir := seg / seg_len
		var dist := spacing - carry
		while dist <= seg_len:
			out.append(a + dir * dist)
			dist += spacing
		carry = seg_len - (dist - spacing)
	var last: Vector2 = pts[pts.size() - 1]
	if out[out.size() - 1].distance_to(last) > spacing * 0.2:
		out.append(last)
	return out


static func _sine_meander_path(
	raw: PackedVector2Array, size: float, sea_edge: int, rng: RandomNumberGenerator
) -> PackedVector2Array:
	## Gentle sine meander along a sparsified downhill backbone.
	## Keep amplitude << wavelength so the path never folds into a starburst.
	if raw.size() < 3:
		return _sanitize_polyline(raw)
	var backbone := _sparsify_path(raw, 4.0)
	backbone = _smooth_polyline(backbone, 2)
	backbone = _resample_arc(backbone, 1.6)
	if backbone.size() < 4:
		return _sanitize_polyline(backbone)

	var cum: PackedFloat32Array = PackedFloat32Array()
	cum.resize(backbone.size())
	cum[0] = 0.0
	for i in range(1, backbone.size()):
		cum[i] = cum[i - 1] + backbone[i].distance_to(backbone[i - 1])
	var total := cum[cum.size() - 1]
	if total < 10.0:
		return _sanitize_polyline(backbone)

	var phase1 := rng.randf() * TAU
	var phase2 := rng.randf() * TAU
	# Long wavelength + modest amp → readable small stream, not shards
	var wave1 := lerpf(22.0, 36.0, rng.randf())
	var wave2 := wave1 * 0.55
	# Modest amp + long wavelength → readable meander without tight S folds that stack ribbon quads
	var max_amp := mini(2.2, total * 0.045)
	var out := PackedVector2Array()
	out.append(backbone[0])
	for i in range(1, backbone.size() - 1):
		var s := cum[i]
		var along := s / total
		var sea_p := MapHeightfield._sea_proximity(backbone[i].x, backbone[i].y, size, sea_edge)
		var amp := lerpf(0.20, max_amp, pow(along, 0.7)) * lerpf(0.7, 1.0, sea_p)
		amp *= 1.0 - smoothstep(0.85, 1.0, along) * 0.8
		var tang: Vector2 = (backbone[i + 1] - backbone[i - 1]).normalized()
		if tang.length_squared() < 1e-6:
			out.append(backbone[i])
			continue
		var perp := Vector2(-tang.y, tang.x)
		var bend := sin(s * TAU / wave1 + phase1) * 0.78 + sin(s * TAU / wave2 + phase2) * 0.22
		out.append(backbone[i] + perp * (bend * amp))
	out.append(backbone[backbone.size() - 1])

	out = _smooth_polyline(out, 2)
	out = _resample_arc(out, 1.15)
	return _sanitize_polyline(out)


static func _sanitize_polyline(pts: PackedVector2Array) -> PackedVector2Array:
	## Drop spikes/reversals so ribbon quads stay a single forward thread.
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	var prev_dir := Vector2.ZERO
	for i in range(1, pts.size()):
		var p: Vector2 = pts[i]
		var last: Vector2 = out[out.size() - 1]
		var step := p - last
		var sl := step.length()
		if sl < 0.18:
			continue # too tight — skip
		var dir := step / sl
		if prev_dir != Vector2.ZERO and dir.dot(prev_dir) < 0.05:
			# Hard reverse / spike — skip this point
			continue
		out.append(p)
		prev_dir = dir
	# Always keep true endpoint if missing
	var end: Vector2 = pts[pts.size() - 1]
	if out.size() < 2:
		return pts
	if out[out.size() - 1].distance_to(end) > 0.5:
		# Only append end if it continues forward
		var d2 := (end - out[out.size() - 1]).normalized()
		if prev_dir == Vector2.ZERO or d2.dot(prev_dir) > 0.0:
			out.append(end)
	return out if out.size() >= 2 else pts


static func _sea_outward(sea_edge: int) -> Vector2:
	match sea_edge:
		0:
			return Vector2(0, 1)
		1:
			return Vector2(0, -1)
		2:
			return Vector2(1, 0)
		_:
			return Vector2(-1, 0)


static func _smooth_polyline(pts: PackedVector2Array, iters: int) -> PackedVector2Array:
	var cur := pts
	for _i in iters:
		if cur.size() < 3:
			return cur
		var nxt := PackedVector2Array()
		nxt.append(cur[0])
		for i in range(cur.size() - 1):
			var a: Vector2 = cur[i]
			var b: Vector2 = cur[i + 1]
			nxt.append(a.lerp(b, 0.25))
			nxt.append(a.lerp(b, 0.75))
		nxt.append(cur[cur.size() - 1])
		cur = nxt
	return cur


static func _dist_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0 if len2 < 1e-8 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		best = minf(best, p.distance_to(a.lerp(b, t)))
	return best


static func _along_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	if pts.size() < 2:
		return 0.0
	var best_t := 0.0
	var best_d := INF
	var total := 0.0
	var seglen: Array[float] = []
	for i in range(pts.size() - 1):
		var L := pts[i].distance_to(pts[i + 1])
		seglen.append(L)
		total += L
	if total < 1e-4:
		return 0.0
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var len2 := ab.length_squared()
		var u := 0.0 if len2 < 1e-8 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var d := p.distance_to(a.lerp(b, u))
		if d < best_d:
			best_d = d
			best_t = (acc + seglen[i] * u) / total
		acc += seglen[i]
	return best_t


static func _enforce_downhill(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	rivers: Array,
	water_y: float,
	lakes: Array
) -> PackedFloat32Array:
	var out := heights.duplicate()
	for river in rivers:
		var pts: PackedVector2Array = river
		if pts.size() < 2:
			continue
		var mouth_y := MapLakes._mouth_water_y(pts[pts.size() - 1], biomes, grid, size, water_y, lakes)
		var prev_h := INF
		for i in range(pts.size()):
			var p: Vector2 = pts[i]
			var along := float(i) / float(pts.size() - 1)
			var ix := clampi(int(round((p.x / size + 0.5) * float(grid - 1))), 1, grid - 2)
			var iz := clampi(int(round((p.y / size + 0.5) * float(grid - 1))), 1, grid - 2)
			var idx := MapHeightfield._i(grid, ix, iz)
			if int(biomes[idx]) == MapTypes.Biome.LAKE or int(biomes[idx]) == MapTypes.Biome.SEA:
				continue
			var target := out[idx]
			if prev_h < INF:
				target = minf(target, prev_h - 0.04)
			target = lerpf(target, mouth_y - 0.08, pow(along, 1.5) * 0.4)
			out[idx] = target
			prev_h = target
	return out


static func _carve_rivers(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	rivers: Array,
	water_y: float,
	lakes: Array,
	relief: float
) -> PackedFloat32Array:
	## Dig a local trench under the path so water can sit at bed+epsilon (no aqueduct).
	if rivers.is_empty():
		return heights
	var out := heights.duplicate()
	var mouths: Array[float] = []
	for river in rivers:
		var pts: PackedVector2Array = river
		mouths.append(MapLakes._mouth_water_y(pts[pts.size() - 1], biomes, grid, size, water_y, lakes))

	for z in grid:
		for x in grid:
			var i := MapHeightfield._i(grid, x, z)
			var b0 := int(biomes[i])
			if b0 == MapTypes.Biome.SEA or b0 == MapTypes.Biome.LAKE:
				continue
			var p := MapHeightfield._cell_world(x, z, grid, size)
			var d_min := INF
			var along := 0.0
			var mouth_y := water_y
			for ri in rivers.size():
				var pts: PackedVector2Array = rivers[ri]
				var d := _dist_to_polyline(p, pts)
				if d < d_min:
					d_min = d
					along = _along_polyline(p, pts)
					mouth_y = mouths[ri]
			var half_w := river_half_width(along)
			var bank := half_w * MapTypes.RIVER_BANK_MUL
			if d_min > bank:
				continue
			var bed_w := smoothstep(bank, half_w * 0.15, d_min)
			var deepen := river_depth(along) * clampf(relief, 0.75, 1.45) * bed_w
			out[i] -= deepen
			# Carve a trench wider than the water ribbon so banks never cover the mesh
			if d_min < half_w * 1.15:
				biomes[i] = MapTypes.Biome.RIVER
				if along > 0.85:
					out[i] = minf(out[i], mouth_y - 0.12)
			elif d_min < bank and int(biomes[i]) != MapTypes.Biome.RIVER:
				if along > 0.45:
					biomes[i] = MapTypes.Biome.SAND
	return out
