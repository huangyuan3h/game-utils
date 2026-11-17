extends RefCounted
## Continuous river ribbon: deeper U-shaped thalweg, mitered banks, estuary flare,
## and mouth/spillway descriptors for seamless lake/sea plume blending.

const MapGen = preload("res://scripts/map_generator.gd")

var _ctx: TerrainBuildContext
## Extracted mouth & spillway descriptors passed to sea/lake shaders.
var mouths: Array[Dictionary] = []


func build(ctx: TerrainBuildContext) -> Dictionary:
	_ctx = ctx
	mouths.clear()
	var mesh := _build_rivers()
	return {
		"mesh": mesh,
		"mouths": mouths.duplicate(),
	}


func create_material(ctx: TerrainBuildContext) -> ShaderMaterial:
	_ctx = ctx
	if _ctx == null or _ctx.data == null:
		return null
	var data := _ctx.data
	var shader := load("res://shaders/water_river.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 1
	mat.set_shader_parameter("half_world", Vector2(data.size * 0.5, data.size * 0.5))
	mat.set_shader_parameter("sea_edge", data.sea_edge)
	mat.set_shader_parameter("water_y", data.water_y)
	mat.set_shader_parameter("height_tex", _ctx.height_tex)
	mat.set_shader_parameter("height_min", data.h_min)
	mat.set_shader_parameter("height_span", maxf(data.h_max - data.h_min, 0.001))
	mat.set_shader_parameter("shallow_col", Vector3(0.24, 0.60, 0.54))
	mat.set_shader_parameter("deep_col", Vector3(0.04, 0.21, 0.31))
	mat.set_shader_parameter("sea_shallow_col", Vector3(0.28, 0.66, 0.60))
	mat.set_shader_parameter("sea_deep_col", Vector3(0.04, 0.23, 0.39))
	mat.set_shader_parameter("lake_shallow_col", Vector3(0.28, 0.66, 0.60))
	mat.set_shader_parameter("lake_deep_col", Vector3(0.05, 0.25, 0.36))
	mat.set_shader_parameter("foam_col", Vector3(0.95, 0.98, 0.97))
	mat.set_shader_parameter("flow_speed", 0.56)
	return mat


func _river_mouth_y(pts: PackedVector2Array) -> float:
	var data := _ctx.data
	if pts.is_empty():
		return data.water_y
	return MapGen._mouth_water_y(pts[pts.size() - 1], data.biomes, data.grid, data.size, data.water_y, data.lakes)


func _head_lake_y(p: Vector2) -> float:
	## If this stream starts at a lake rim (outlet spillway), return that lake's surface Y.
	for lake in _ctx.data.lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake.get("radius", 8.0))
		if p.distance_to(c) <= r * 1.18:
			return float(lake["water_y"])
	return -INF


func _nearest_built_height(p: Vector2, built_centres: Array) -> Vector2:
	## Returns Vector2(closest_y, closest_dist) among already-built upstream/main ribbons.
	var best_d := INF
	var best_y := -INF
	for arr in built_centres:
		var cs: Array[Vector3] = arr
		for v in cs:
			var d := Vector2(v.x, v.z).distance_to(p)
			if d < best_d:
				best_d = d
				best_y = v.y
	return Vector2(best_y, best_d)


func _resample_polyline(pts: PackedVector2Array, spacing: float) -> PackedVector2Array:
	## Even spacing removes Chaikin clumps that twist wide ribbons.
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
	if out[out.size() - 1].distance_to(last) > spacing * 0.25:
		out.append(last)
	return out


func _sample_trench_bed(x: float, z: float, half_w: float, dir_xz: Vector2) -> float:
	## Prefer the carved channel floor, not the taller bank (bank max -> vertical curtains).
	var perp := Vector2(-dir_xz.y, dir_xz.x)
	if perp.length_squared() < 1e-8:
		perp = Vector2(1.0, 0.0)
	else:
		perp = perp.normalized()
	var best: float = _ctx.sample_height(x, z)
	for s in [-0.45, -0.2, 0.2, 0.45]:
		best = minf(best, _ctx.sample_height(x + perp.x * half_w * s, z + perp.y * half_w * s))
	return best


func _flatten_river_centres(
	centres: Array[Vector3], beds: Array[float], mouth_y: float
) -> void:
	## Monotone downhill sheet. Steeper in the headwaters, calmer near the mouth.
	if centres.size() < 2:
		return
	const MIN_STEP := 0.001
	for i in centres.size():
		var t := float(i) / float(maxi(centres.size() - 1, 1))
		var wy: float = beds[i] + lerpf(0.16, 0.28, pow(t, 0.6))
		if t > 0.68:
			wy = lerpf(wy, mouth_y + 0.02, smoothstep(0.68, 1.0, t))
		centres[i].y = maxf(wy, beds[i] + 0.10)
	for i in range(1, centres.size()):
		var t := float(i) / float(maxi(centres.size() - 1, 1))
		var max_grade := lerpf(0.34, 0.16, smoothstep(0.25, 0.85, t))
		var dxz: float = Vector2(centres[i].x - centres[i - 1].x, centres[i].z - centres[i - 1].z).length()
		dxz = maxf(dxz, 0.05)
		var y: float = centres[i].y
		y = minf(y, centres[i - 1].y - MIN_STEP)
		y = maxf(y, centres[i - 1].y - dxz * max_grade)
		y = maxf(y, beds[i] + 0.08)
		if y > centres[i - 1].y:
			y = centres[i - 1].y - MIN_STEP
		centres[i].y = y
	for i in range(centres.size() - 2, -1, -1):
		var t := float(i) / float(maxi(centres.size() - 1, 1))
		var max_grade := lerpf(0.34, 0.16, smoothstep(0.25, 0.85, t))
		var dxz: float = Vector2(centres[i].x - centres[i + 1].x, centres[i].z - centres[i + 1].z).length()
		dxz = maxf(dxz, 0.05)
		var y: float = centres[i].y
		y = minf(y, centres[i + 1].y + dxz * max_grade)
		y = maxf(y, beds[i] + 0.08)
		centres[i].y = y
	for _pass in 2:
		for i in range(1, centres.size() - 1):
			var y: float = (centres[i - 1].y + centres[i].y + centres[i + 1].y) / 3.0
			y = maxf(y, beds[i] + 0.08)
			centres[i].y = y
	for i in range(1, centres.size()):
		var t := float(i) / float(maxi(centres.size() - 1, 1))
		var max_grade := lerpf(0.34, 0.16, smoothstep(0.25, 0.85, t))
		var dxz: float = Vector2(centres[i].x - centres[i - 1].x, centres[i].z - centres[i - 1].z).length()
		dxz = maxf(dxz, 0.05)
		if centres[i].y > centres[i - 1].y:
			centres[i].y = centres[i - 1].y - MIN_STEP
		if centres[i - 1].y - centres[i].y > dxz * max_grade:
			centres[i].y = centres[i - 1].y - dxz * max_grade


func _seat_channel(
	centres: Array[Vector3], half_ws: Array[float], alongs: Array[float], open_waters: Array[bool]
) -> void:
	## Drop terrain vertices under every landward ribbon station into a U-shaped thalweg
	## so water reads with genuine center depth and gentle wadeable banks.
	if centres.is_empty():
		return
	var data := _ctx.data
	var step: float = data.size / float(data.grid - 1)
	var half: float = data.size * 0.5
	for i in centres.size():
		if open_waters[i]:
			continue
		var c: Vector3 = centres[i]
		var hw := maxf(half_ws[i], 0.55)
		_seat_disc(c, hw, alongs[i], step, half)


func _seat_disc(c: Vector3, hw: float, along: float, step: float, half: float) -> void:
	## Lower grid verts in a U-shaped channel cross-section with soft shoulder banks.
	var data := _ctx.data
	var bed_r: float = maxf(hw + step * 0.20, step * 0.85)
	var reach: float = bed_r + step * 2.40
	var rad := int(ceil(reach / step)) + 1
	var cx := int(round((c.x + half) / step))
	var cz := int(round((c.z + half) / step))
	var x0: int = clampi(cx - rad, 0, int(data.grid) - 1)
	var x1: int = clampi(cx + rad, 0, int(data.grid) - 1)
	var z0: int = clampi(cz - rad, 0, int(data.grid) - 1)
	var z1: int = clampi(cz + rad, 0, int(data.grid) - 1)
	var center_depth := lerpf(0.44, 0.88, pow(clampf(along, 0.0, 1.0), 0.65))
	var edge_depth := lerpf(0.14, 0.24, clampf(along, 0.0, 1.0))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var idx: int = _ctx.idx(x, z)
			var b: int = int(data.biomes[idx])
			var wx: float = -half + float(x) * step
			var wz: float = -half + float(z) * step
			var d := Vector2(wx - c.x, wz - c.z).length()
			if d > reach:
				continue
			var target: float = data.heights[idx]
			if d <= bed_r:
				var r_norm := clampf(d / maxf(bed_r, 0.01), 0.0, 1.0)
				# U-shaped thalweg: deep in the central channel, rising smoothly toward banks
				var u_bed := r_norm * r_norm
				target = c.y - lerpf(center_depth, edge_depth, u_bed)
				if b != MapGen.Biome.SEA and b != MapGen.Biome.LAKE:
					data.biomes[idx] = MapGen.Biome.RIVER
			else:
				var u := clampf((d - bed_r) / maxf(reach - bed_r, 0.01), 0.0, 1.0)
				u = u * u * (3.0 - 2.0 * u)
				target = lerpf(c.y - edge_depth, data.heights[idx], u)
			if target < data.heights[idx]:
				data.heights[idx] = target


func _clearance_pass(verts: PackedVector3Array, colors: PackedColorArray, seat_flags: Array[bool]) -> void:
	## Final seat using the actual ribbon midpoints (miter can drift from centres).
	if verts.size() < 2:
		return
	var data := _ctx.data
	var step: float = data.size / float(data.grid - 1)
	var half: float = data.size * 0.5
	var stations := mini(verts.size() / 2, seat_flags.size())
	for i in range(stations):
		if not seat_flags[i]:
			continue
		var c: Vector3 = (verts[i * 2] + verts[i * 2 + 1]) * 0.5
		var hw: float = verts[i * 2].distance_to(verts[i * 2 + 1]) * 0.5
		var along: float = colors[i * 2].r
		_seat_disc(c, maxf(hw, 0.55), along, step, half)


func _is_lake_xz(x: float, z: float) -> bool:
	var b: int = _ctx.sample_biome(x, z)
	if b == MapGen.Biome.LAKE:
		return true
	var p := Vector2(x, z)
	for lake in _ctx.data.lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake.get("radius", 8.0))
		if p.distance_to(c) <= r * 0.98:
			return true
	return false


func _is_open_water_xz(x: float, z: float) -> bool:
	var b: int = _ctx.sample_biome(x, z)
	if b == MapGen.Biome.SEA or b == MapGen.Biome.LAKE:
		return true
	return MapGen._sea_proximity(x, z, _ctx.data.size, _ctx.data.sea_edge) >= 0.70


func _extend_to_shallow_shore(line: PackedVector2Array, is_tributary: bool) -> PackedVector2Array:
	## Extend mouth smoothly ~2.8 m into open water so estuary flare and sea/lake plumes overlap cleanly.
	if line.size() < 3 or is_tributary:
		return line
	var out := PackedVector2Array()
	var water_dist := 0.0
	var entered_water := false
	for i in line.size():
		var p: Vector2 = line[i]
		# Ignore the head spillway when looking for the mouth
		if i > line.size() / 3 and _is_open_water_xz(p.x, p.y):
			if not entered_water:
				entered_water = true
			elif out.size() > 0:
				water_dist += out[out.size() - 1].distance_to(p)
			out.append(p)
			if water_dist >= 2.8:
				return out
		else:
			out.append(p)
	if entered_water:
		return out
	var last: Vector2 = out[out.size() - 1]
	var prev: Vector2 = out[out.size() - 2]
	var flow := (last - prev)
	if flow.length_squared() < 1e-6:
		return out
	flow = flow.normalized()
	var probe := last
	for _k in 6:
		probe += flow * 0.65
		out.append(probe)
		if _is_open_water_xz(probe.x, probe.y):
			out.append(probe + flow * 1.4)
			break
	return out


func _estuary_half_width(t: float, over_water: float) -> float:
	## Natural widening downstream into a flared estuary fan at lake/sea entry.
	var base := MapGen.river_half_width(t)
	var source_taper := smoothstep(0.0, 0.08, t)
	var flare := smoothstep(0.55, 0.94, t)
	var plume := smoothstep(0.32, 1.0, over_water)
	var mul := lerpf(0.95, 1.32, pow(flare, 1.15))
	mul = lerpf(mul, 1.65, pow(plume, 0.85))
	return base * mul * lerpf(0.45, 1.0, source_taper)


func _limit_width_by_curvature(centres: Array[Vector3], half_ws: Array[float]) -> void:
	## Cap width only by actual geometric radius of curvature so wide lower rivers
	## do not get clamped by segment resampling spacing.
	if centres.size() < 3:
		return
	for i in range(1, centres.size() - 1):
		var p0 := Vector2(centres[i - 1].x, centres[i - 1].z)
		var p1 := Vector2(centres[i].x, centres[i].z)
		var p2 := Vector2(centres[i + 1].x, centres[i + 1].z)
		var d0 := p1 - p0
		var d1 := p2 - p1
		var l0 := d0.length()
		var l1 := d1.length()
		if l0 < 1e-4 or l1 < 1e-4:
			continue
		var cos_turn := clampf((d0 / l0).dot(d1 / l1), -1.0, 1.0)
		var theta := acos(cos_turn)
		var ds := (l0 + l1) * 0.5
		# Discrete radius of curvature R = ds / theta
		var r_curv := ds / maxf(theta, 0.01)
		var turn_cap := maxf(0.58, r_curv * 0.78)
		var turn_scale := smoothstep(0.05, 0.88, cos_turn)
		half_ws[i] = minf(half_ws[i], turn_cap) * lerpf(0.55, 1.0, turn_scale)
	# Smooth width so neighboring stations don't create stepped silhouettes
	for _pass in 2:
		for i in range(1, half_ws.size() - 1):
			half_ws[i] = (half_ws[i - 1] + half_ws[i] * 2.0 + half_ws[i + 1]) * 0.25


func _mitered_bank_offsets(
	centres: Array[Vector3], half_ws: Array[float]
) -> Array:
	## Build continuous left/right banks with miter joins (no stacked rectangle layers at bends).
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	if centres.is_empty():
		return [lefts, rights]
	const MITER_LIMIT := 1.85
	var n := centres.size()
	for i in n:
		var cur: Vector3 = centres[i]
		var d_in := Vector3(0, 0, 1)
		var d_out := Vector3(0, 0, 1)
		if i > 0:
			d_in = cur - centres[i - 1]
		elif n > 1:
			d_in = centres[1] - cur
		if i < n - 1:
			d_out = centres[i + 1] - cur
		elif i > 0:
			d_out = cur - centres[i - 1]
		d_in.y = 0.0
		d_out.y = 0.0
		if d_in.length_squared() < 1e-8:
			d_in = d_out
		if d_out.length_squared() < 1e-8:
			d_out = d_in
		d_in = d_in.normalized()
		d_out = d_out.normalized()
		var n_in := Vector3(-d_in.z, 0.0, d_in.x)
		var n_out := Vector3(-d_out.z, 0.0, d_out.x)
		var miter := n_in + n_out
		if miter.length_squared() < 1e-8:
			miter = n_out
		else:
			miter = miter.normalized()
		var den := miter.dot(n_out)
		var scale: float = half_ws[i]
		if absf(den) > 1e-4:
			scale = half_ws[i] / den
		# Bevel when the miter would explode on a sharp corner
		if absf(scale) > half_ws[i] * MITER_LIMIT:
			scale = signf(scale) * half_ws[i] * MITER_LIMIT
			miter = (n_in + n_out)
			if miter.length_squared() < 1e-8:
				miter = n_out
			else:
				miter = miter.normalized()
		var left := cur + miter * scale
		var right := cur - miter * scale
		left.y = cur.y
		right.y = cur.y
		# Prevent bank crossover (bow-tie) — fall back to simple perpendicular
		var across := right - left
		var mid_n := (n_in + n_out)
		if mid_n.length_squared() > 1e-8:
			mid_n = mid_n.normalized()
		else:
			mid_n = n_out
		if across.dot(mid_n) > 0.0:
			left = cur + n_out * half_ws[i]
			right = cur - n_out * half_ws[i]
			left.y = cur.y
			right.y = cur.y
		lefts.append(left)
		rights.append(right)
	# Light bank smooth keeps edges continuous without reintroducing overlap
	for _pass in 2:
		for i in range(1, n - 1):
			var yl := lefts[i].y
			var yr := rights[i].y
			lefts[i] = (lefts[i - 1] + lefts[i] + lefts[i + 1]) / 3.0
			rights[i] = (rights[i - 1] + rights[i] + rights[i + 1]) / 3.0
			lefts[i].y = yl
			rights[i].y = yr
	return [lefts, rights]


func _record_mouth_descriptors(
	line: PackedVector2Array,
	centres: Array[Vector3],
	half_ws: Array[float],
	open_waters: Array[bool],
	head_lake_y: float,
	is_trib: bool
) -> void:
	## Capture shoreline crossing positions and flow vectors for sea & lake plume shaders.
	var n := centres.size()
	if n < 4:
		return

	# 1) Lake spillway / outlet at river head
	if head_lake_y > -900.0:
		var head_idx := 0
		for i in range(n):
			if not _is_lake_xz(centres[i].x, centres[i].z):
				head_idx = i
				break
		var h_prev := maxi(0, head_idx - 2)
		var h_next := mini(n - 1, head_idx + 4)
		var h_dir := Vector2(centres[h_next].x - centres[h_prev].x, centres[h_next].z - centres[h_prev].z)
		if h_dir.length_squared() > 1e-6:
			h_dir = h_dir.normalized()
		else:
			h_dir = Vector2(0.0, 1.0)
		var hw := maxf(half_ws[head_idx], 0.9)
		mouths.append({
			"target": "lake",
			"pos": Vector2(centres[head_idx].x, centres[head_idx].z),
			"dir": h_dir,
			"half_w": hw,
			"plume_len": clampf(hw * 3.0, 3.6, 6.8),
			"mode": -1.0, # outlet spillway drawing out of lake
			"strength": 0.9,
		})

	# 2) River mouth entering sea or lake
	if is_trib:
		return
	var shore_idx := n - 1
	var found_open := false
	for i in range(n / 3, n):
		if open_waters[i]:
			shore_idx = i
			found_open = true
			break
	if not found_open:
		shore_idx = maxi(0, n - 3)
	var m_prev := maxi(0, shore_idx - 4)
	var m_next := mini(n - 1, shore_idx + 2)
	var m_dir := Vector2(centres[m_next].x - centres[m_prev].x, centres[m_next].z - centres[m_prev].z)
	if m_dir.length_squared() < 1e-6 and line.size() >= 2:
		m_dir = line[line.size() - 1] - line[line.size() - 2]
	if m_dir.length_squared() > 1e-6:
		m_dir = m_dir.normalized()
	else:
		m_dir = Vector2(0.0, 1.0)
	var end_c := centres[n - 1]
	var target := "lake" if _is_lake_xz(end_c.x, end_c.z) or _is_lake_xz(centres[shore_idx].x, centres[shore_idx].z) else "sea"
	var m_hw := maxf(half_ws[shore_idx], 1.2)
	mouths.append({
		"target": target,
		"pos": Vector2(centres[shore_idx].x, centres[shore_idx].z),
		"dir": m_dir,
		"half_w": m_hw,
		"plume_len": clampf(m_hw * 3.2, 4.8, 9.2),
		"mode": 1.0, # inflow mouth entering lake/sea
		"strength": 1.0,
	})


func _build_rivers() -> ArrayMesh:
	## One continuous flat ribbon per river — same Y across the width so banks never
	## punch holes through the water (that read as a broken / dashed stream).
	## Mouth flares smoothly into a dissolving estuary plume over sea/lake.
	if _ctx == null or _ctx.data == null or _ctx.data.rivers.is_empty():
		return null

	var rivers := _ctx.data.rivers
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var seat_flags: Array[bool] = []
	var built_centres: Array = []

	# Pre-collect tributary join positions on the main stem so the main creek widens slightly downstream.
	var join_points: Array[Vector2] = []
	if rivers.size() > 1:
		var main_raw: PackedVector2Array = rivers[0]
		for ri in range(1, rivers.size()):
			var r_pts: PackedVector2Array = rivers[ri]
			if r_pts.is_empty():
				continue
			var tip: Vector2 = r_pts[r_pts.size() - 1]
			if not _is_open_water_xz(tip.x, tip.y) and MapGen._dist_to_polyline(tip, main_raw) < 4.0:
				join_points.append(tip)

	for ri in rivers.size():
		var raw: PackedVector2Array = rivers[ri]
		if raw.size() < 2:
			continue
		var line := MapGen._sanitize_polyline(
			_resample_polyline(MapGen._smooth_polyline(raw, 2), 0.34)
		)
		if line.size() < 4:
			continue
		var path_len := 0.0
		for i in range(line.size() - 1):
			path_len += line[i].distance_to(line[i + 1])
		if path_len < 8.0:
			continue

		var end_p: Vector2 = line[line.size() - 1]
		var near_built: Vector2 = _nearest_built_height(end_p, built_centres)
		var is_trib: bool = ri > 0 and not _is_open_water_xz(end_p.x, end_p.y) and near_built.x > -900.0 and near_built.y < 3.5

		line = MapGen._sanitize_polyline(
			_resample_polyline(
				MapGen._smooth_polyline(_extend_to_shallow_shore(line, is_trib), 1), 0.36
			)
		)
		if line.size() < 4:
			continue

		var mouth_y: float = near_built.x if is_trib else _river_mouth_y(line)
		var head_lake_y := _head_lake_y(line[0])

		var centres: Array[Vector3] = []
		var half_ws: Array[float] = []
		var beds: Array[float] = []
		var alongs: Array[float] = []
		var over_ws: Array[float] = []
		var head_fades: Array[float] = []
		var open_waters: Array[bool] = []

		var main_join_along := INF
		if ri == 0 and not join_points.is_empty():
			for jp in join_points:
				for i in line.size():
					if line[i].distance_to(jp) < 2.2:
						main_join_along = minf(main_join_along, float(i) / float(maxi(line.size() - 1, 1)))
						break

		var cum_d := PackedFloat32Array()
		cum_d.resize(line.size())
		cum_d[0] = 0.0
		for i in range(1, line.size()):
			cum_d[i] = cum_d[i - 1] + line[i].distance_to(line[i - 1])
		var total_d := maxf(cum_d[line.size() - 1], 0.01)

		# Locate the shoreline crossing distance so `over` transitions continuously
		# across both the lower bank (~4.5m before shore) and the submerged estuary fan.
		var shore_d := total_d
		if not is_trib:
			for i in range(line.size() / 3, line.size()):
				if _is_open_water_xz(line[i].x, line[i].y):
					shore_d = cum_d[i]
					break

		for i in range(line.size()):
			var t := float(i) / float(maxi(line.size() - 1, 1))
			var a2: Vector2 = line[i]
			var dir2 := Vector2(0, 1)
			if i < line.size() - 1:
				dir2 = line[i + 1] - a2
			elif i > 0:
				dir2 = a2 - line[i - 1]
			if dir2.length_squared() < 1e-8:
				dir2 = Vector2(0, 1)
			else:
				dir2 = dir2.normalized()

			var head_f := 0.0
			if head_lake_y > -900.0:
				head_f = 1.0 - smoothstep(0.2, 3.6, cum_d[i])
			var in_open := _is_open_water_xz(a2.x, a2.y) and (t > 0.65 or (total_d - cum_d[i]) < 4.5)
			open_waters.append(in_open or head_f > 0.55)

			var over := 0.0
			var tail_dist := total_d - cum_d[i]
			if is_trib:
				over = 1.0 - smoothstep(0.0, 2.2, tail_dist)
			else:
				var pre_span := 4.5
				var post_span := maxf(total_d - shore_d, 0.8)
				if cum_d[i] <= shore_d:
					over = smoothstep(shore_d - pre_span, shore_d, cum_d[i]) * 0.48
				else:
					over = lerpf(0.48, 1.0, smoothstep(0.0, post_span, cum_d[i] - shore_d))

			var wdt := _estuary_half_width(t, 0.0 if is_trib else over)
			if ri == 0 and t > main_join_along:
				wdt += 0.30 * smoothstep(main_join_along, minf(main_join_along + 0.08, 1.0), t)
			if head_lake_y > -900.0:
				wdt = lerpf(wdt, maxf(wdt, 1.30), head_f)
			if is_trib:
				wdt = lerpf(wdt, wdt * 0.88, over)

			var bed := _sample_trench_bed(a2.x, a2.y, maxf(wdt * 0.45, 0.9), dir2)
			if over > 0.35:
				bed = minf(bed, mouth_y - 0.25)
			if head_f > 0.40:
				bed = minf(bed, head_lake_y - 0.25)
			centres.append(Vector3(a2.x, bed + lerpf(0.18, 0.30, pow(t, 0.6)), a2.y))
			half_ws.append(wdt)
			beds.append(bed)
			alongs.append(t)
			over_ws.append(over)
			head_fades.append(head_f)

		_flatten_river_centres(centres, beds, mouth_y)
		for i in centres.size():
			if head_fades[i] > 0.01 and head_lake_y > -900.0:
				centres[i].y = lerpf(centres[i].y, head_lake_y, smoothstep(0.01, 0.95, head_fades[i]))
			if over_ws[i] > 0.02:
				var blend := smoothstep(0.02, 0.88, over_ws[i])
				if not is_trib:
					blend *= smoothstep(0.58, 0.92, alongs[i])
				centres[i].y = lerpf(centres[i].y, mouth_y, blend)
		_flatten_river_centres(centres, beds, mouth_y)
		# Lock spillway start & open-water estuary right to lake/sea level so no step occurs
		for i in centres.size():
			if head_fades[i] > 0.30 and head_lake_y > -900.0:
				centres[i].y = lerpf(centres[i].y, head_lake_y, smoothstep(0.30, 0.95, head_fades[i]))
			if over_ws[i] > 0.36 and (is_trib or alongs[i] > 0.72):
				centres[i].y = lerpf(centres[i].y, mouth_y, smoothstep(0.36, 0.85, over_ws[i]))

		_limit_width_by_curvature(centres, half_ws)
		_seat_channel(centres, half_ws, alongs, open_waters)
		var banks: Array = _mitered_bank_offsets(centres, half_ws)
		var lefts: Array = banks[0]
		var rights: Array = banks[1]

		var base_vi := verts.size()
		var base_seat := seat_flags.size()
		var dist_acc := 0.0
		var prev_center := centres[0]
		for i in range(centres.size()):
			var cur: Vector3 = centres[i]
			if i > 0:
				dist_acc += Vector2(cur.x, cur.z).distance_to(Vector2(prev_center.x, prev_center.z))
			prev_center = cur
			var left: Vector3 = lefts[i]
			var right: Vector3 = rights[i]
			verts.append(left)
			verts.append(right)
			uvs.append(Vector2(0.0, dist_acc * 0.30))
			uvs.append(Vector2(1.0, dist_acc * 0.30))
			# COLOR.a encodes expected thalweg depth maturity [0.45..1.0] for shader absorption
			var depth_maturity := lerpf(0.45, 1.0, pow(alongs[i], 0.65))
			var c := Color(alongs[i], over_ws[i], head_fades[i], depth_maturity)
			colors.append(c)
			colors.append(c)
			seat_flags.append(not open_waters[i])

		var kept := centres.size()
		if kept < 3:
			verts.resize(base_vi)
			uvs.resize(base_vi)
			colors.resize(base_vi)
			seat_flags.resize(base_seat)
			continue
		_record_mouth_descriptors(line, centres, half_ws, open_waters, head_lake_y, is_trib)
		built_centres.append(centres)
		for i in range(kept - 1):
			var v0 := base_vi + i * 2
			indices.append_array([v0, v0 + 2, v0 + 1, v0 + 1, v0 + 2, v0 + 3])

	if verts.is_empty():
		return null

	_clearance_pass(verts, colors, seat_flags)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
