extends RefCounted
## Continuous river ribbon: gentle grade, mitered banks, estuary plume, seated channel.

const MapGen = preload("res://scripts/map_generator.gd")

var _map: Node


func build(map: Node) -> void:
	_map = map
	_build_rivers()


func _river_mouth_y(pts: PackedVector2Array) -> float:
	if pts.is_empty():
		return _map.water_y
	return MapGen._mouth_water_y(pts[pts.size() - 1], _map._biomes, _map.grid, _map.map_size, _map.water_y, _map._lakes)



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
	## Prefer the carved channel floor, not the taller bank (bank max → vertical curtains).
	var perp := Vector2(-dir_xz.y, dir_xz.x)
	if perp.length_squared() < 1e-8:
		perp = Vector2(1.0, 0.0)
	else:
		perp = perp.normalized()
	var best: float = _map.sample_height(x, z)
	for s in [-0.45, -0.2, 0.2, 0.45]:
		best = minf(best, _map.sample_height(x + perp.x * half_w * s, z + perp.y * half_w * s))
	return best



func _flatten_river_centres(
	centres: Array[Vector3], beds: Array[float], mouth_y: float
) -> void:
	## Keep the ribbon nearly horizontal: gentle downhill, hard max grade.
	## Prevents the tall vertical "water curtain" when the path crosses a cliff.
	if centres.size() < 2:
		return
	const MAX_GRADE := 0.18 ## |ΔY| / ΔXZ — steeper reads as a wall
	const MIN_STEP := 0.001
	# Seed from trench, ease toward mouth near the end
	for i in centres.size():
		var t := float(i) / float(maxi(centres.size() - 1, 1))
		var wy: float = beds[i] + 0.12
		if t > 0.72:
			wy = lerpf(wy, mouth_y + 0.05, smoothstep(0.72, 1.0, t))
		centres[i].y = maxf(wy, beds[i] + 0.08)
	# Forward: monotone downhill + grade clamp
	for i in range(1, centres.size()):
		var dxz: float = Vector2(centres[i].x - centres[i - 1].x, centres[i].z - centres[i - 1].z).length()
		dxz = maxf(dxz, 0.05)
		var y: float = centres[i].y
		y = minf(y, centres[i - 1].y - MIN_STEP)
		y = maxf(y, centres[i - 1].y - dxz * MAX_GRADE)
		y = maxf(y, beds[i] + 0.06)
		# If bed wants a cliff, stay on the gentle ramp (short aqueduct > vertical wall)
		if y > centres[i - 1].y:
			y = centres[i - 1].y - MIN_STEP
		centres[i].y = y
	# Backward: pull spikes down so a single high bank sample cannot erect a wall
	for i in range(centres.size() - 2, -1, -1):
		var dxz: float = Vector2(centres[i].x - centres[i + 1].x, centres[i].z - centres[i + 1].z).length()
		dxz = maxf(dxz, 0.05)
		var y: float = centres[i].y
		y = minf(y, centres[i + 1].y + dxz * MAX_GRADE)
		y = maxf(y, beds[i] + 0.06)
		centres[i].y = y
	# Light smooth without reintroducing steep grades
	for _pass in 3:
		for i in range(1, centres.size() - 1):
			var y: float = (centres[i - 1].y + centres[i].y + centres[i + 1].y) / 3.0
			y = maxf(y, beds[i] + 0.06)
			centres[i].y = y
	# Final forward grade enforce after smooth
	for i in range(1, centres.size()):
		var dxz: float = Vector2(centres[i].x - centres[i - 1].x, centres[i].z - centres[i - 1].z).length()
		dxz = maxf(dxz, 0.05)
		if centres[i].y > centres[i - 1].y:
			centres[i].y = centres[i - 1].y - MIN_STEP
		if centres[i - 1].y - centres[i].y > dxz * MAX_GRADE:
			centres[i].y = centres[i - 1].y - dxz * MAX_GRADE



func _seat_channel(centres: Array[Vector3], half_ws: Array[float], over_ws: Array[float]) -> void:
	## Drop every terrain vertex under the ribbon so the water reads as one sheet,
	## not blue shards poking through stair-stepped banks.
	if centres.is_empty():
		return
	var step: float = _map.map_size / float(_map.grid - 1)
	var half: float = _map.map_size * 0.5
	for i in centres.size():
		if over_ws[i] > 0.45:
			continue
		var c: Vector3 = centres[i]
		var hw := maxf(half_ws[i], 0.9)
		# Grid quads are ~1.3 m. Sink a full cell past the bank or a corner stays high and covers the sheet.
		var bed_r: float = hw + step * 0.95
		var reach: float = bed_r + step * 1.15
		var rad := int(ceil(reach / step)) + 1
		var cx := int(round((c.x + half) / step))
		var cz := int(round((c.z + half) / step))
		var x0: int = clampi(cx - rad, 0, int(_map.grid) - 1)
		var x1: int = clampi(cx + rad, 0, int(_map.grid) - 1)
		var z0: int = clampi(cz - rad, 0, int(_map.grid) - 1)
		var z1: int = clampi(cz + rad, 0, int(_map.grid) - 1)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var idx: int = _map._idx(x, z)
				var b: int = int(_map._biomes[idx])
				if b == MapGen.Biome.SEA or b == MapGen.Biome.LAKE:
					continue
				var wx: float = -half + float(x) * step
				var wz: float = -half + float(z) * step
				var d := Vector2(wx - c.x, wz - c.z).length()
				if d > reach:
					continue
				var target: float = _map._heights[idx]
				if d <= bed_r:
					target = c.y - 0.36
					_map._biomes[idx] = MapGen.Biome.RIVER
				else:
					var u := clampf((d - bed_r) / maxf(reach - bed_r, 0.01), 0.0, 1.0)
					u = u * u * (3.0 - 2.0 * u)
					target = lerpf(c.y - 0.08, _map._heights[idx], u)
				if target < _map._heights[idx]:
					_map._heights[idx] = target



func _is_open_water_xz(x: float, z: float) -> bool:
	var b: int = _map.sample_biome(x, z)
	if b == MapGen.Biome.SEA or b == MapGen.Biome.LAKE:
		return true
	return _map.sample_height(x, z) < _map.water_y - 0.20



func _append_estuary_plume(line: PackedVector2Array, mouth_y: float) -> PackedVector2Array:
	## Fan the last stretch into open water so the mouth reads as diffusion, not a tube tip.
	if line.size() < 3:
		return line
	var out := line.duplicate()
	var last: Vector2 = out[out.size() - 1]
	var prev: Vector2 = out[out.size() - 2]
	var flow := last - prev
	if flow.length_squared() < 1e-6:
		return out
	flow = flow.normalized()
	# Only plume when the tip already reaches open water (sea/lake)
	if not _is_open_water_xz(last.x, last.y):
		# Nudge a few steps toward lower ground / sea until we hit water, then plume
		var probe := last
		var found := false
		for _k in 8:
			probe += flow * 1.1
			if _is_open_water_xz(probe.x, probe.y):
				out.append(probe)
				last = probe
				found = true
				break
		if not found:
			return out
	# Wide dissolving plume into the receiving body
	var tip := last
	for k in 7:
		var u := float(k + 1) / 7.0
		var step := lerpf(0.9, 2.4, u)
		# Slight lateral spread so the fan is not a perfect capsule
		var side := Vector2(-flow.y, flow.x) * sin(u * PI) * lerpf(0.0, 1.6, u)
		tip = tip + flow * step + side * 0.15
		out.append(tip)
	return out



func _estuary_half_width(t: float, over_water: float) -> float:
	## Inland channel → strong mouth flare → even wider dissolving plume over sea/lake.
	var base := MapGen.river_half_width(t)
	var source_taper := smoothstep(0.0, 0.10, t)
	var flare := smoothstep(0.52, 0.92, t) # start widening before the shore
	var plume := smoothstep(0.78, 1.0, t) * over_water
	var mul := lerpf(0.88, 2.35, pow(flare, 1.15))
	mul = lerpf(mul, 3.6, pow(plume, 0.85))
	return base * mul * lerpf(0.35, 1.0, source_taper)



func _limit_width_by_curvature(centres: Array[Vector3], half_ws: Array[float]) -> void:
	## Wide ribbon + tight bend → overlapping quads (visible dark "layers"). Cap width to turn radius.
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
		var turn := (d0 / l0).dot(d1 / l1)
		# Allow full width only when nearly straight; shrink hard on hairpins
		var turn_scale := smoothstep(0.15, 0.92, turn)
		var seg_cap := minf(l0, l1) * 0.48
		half_ws[i] = minf(half_ws[i], maxf(0.55, seg_cap)) * lerpf(0.42, 1.0, turn_scale)
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



func _build_rivers() -> void:
	## One continuous flat ribbon per river — same Y across the width so banks never
	## punch holes through the water (that read as a broken / dashed stream).
	## Mouth flares into a dissolving estuary plume over sea/lake.
	if _map._rivers_mesh == null:
		return
	if _map._rivers.is_empty():
		_map._rivers_mesh.mesh = null
		return

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for river in _map._rivers:
		var raw: PackedVector2Array = river
		if raw.size() < 2:
			continue
		# Extra smooth + denser samples keep bends as one sheet (no stacked quads)
		var line := MapGen._sanitize_polyline(
			_resample_polyline(MapGen._smooth_polyline(raw, 2), 0.32)
		)
		if line.size() < 4:
			continue
		var path_len := 0.0
		for i in range(line.size() - 1):
			path_len += line[i].distance_to(line[i + 1])
		if path_len < 10.0:
			continue

		var mouth_y := _river_mouth_y(line)
		line = MapGen._sanitize_polyline(
			_resample_polyline(
				MapGen._smooth_polyline(_append_estuary_plume(line, mouth_y), 1), 0.36
			)
		)
		if line.size() < 4:
			continue

		var centres: Array[Vector3] = []
		var half_ws: Array[float] = []
		var beds: Array[float] = []
		var alongs: Array[float] = []
		var over_ws: Array[float] = []
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
			var over := 1.0 if _is_open_water_xz(a2.x, a2.y) else 0.0
			if t > 0.70:
				over = maxf(over, smoothstep(0.70, 0.95, t))
			var wdt := _estuary_half_width(t, over)
			var bed := _sample_trench_bed(a2.x, a2.y, maxf(wdt * 0.35, 1.0), dir2)
			if over > 0.5:
				bed = minf(bed, mouth_y - 0.08)
			centres.append(Vector3(a2.x, bed + 0.12, a2.y))
			half_ws.append(wdt)
			beds.append(bed)
			alongs.append(t)
			over_ws.append(over)

		_flatten_river_centres(centres, beds, mouth_y)
		for i in centres.size():
			if over_ws[i] > 0.05:
				var blend := smoothstep(0.05, 1.0, over_ws[i]) * smoothstep(0.65, 0.95, alongs[i])
				centres[i].y = lerpf(centres[i].y, mouth_y + 0.03, blend)
		_flatten_river_centres(centres, beds, mouth_y)
		for i in centres.size():
			if over_ws[i] > 0.35 and alongs[i] > 0.8:
				centres[i].y = minf(centres[i].y, mouth_y + 0.04)

		_limit_width_by_curvature(centres, half_ws)
		_seat_channel(centres, half_ws, over_ws)
		var banks: Array = _mitered_bank_offsets(centres, half_ws)
		var lefts: Array = banks[0]
		var rights: Array = banks[1]

		var base_vi := verts.size()
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
			uvs.append(Vector2(0.0, dist_acc * 0.28))
			uvs.append(Vector2(1.0, dist_acc * 0.28))
			var c := Color(alongs[i], over_ws[i], 0.0, 1.0)
			colors.append(c)
			colors.append(c)

		var kept := centres.size()
		if kept < 3:
			verts.resize(base_vi)
			uvs.resize(base_vi)
			colors.resize(base_vi)
			continue
		for i in range(kept - 1):
			var v0 := base_vi + i * 2
			indices.append_array([v0, v0 + 2, v0 + 1, v0 + 1, v0 + 2, v0 + 3])

	if verts.is_empty():
		_map._rivers_mesh.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_map._rivers_mesh.mesh = mesh
	_map._rivers_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Channel was lowered under the ribbon — rebuild the ground so banks no longer cover the water.
	_map._refresh_height_range()
	_map._height_tex = _map._make_height_texture()
	_map._build_mesh()
	_map._build_sea()

	var shader := load("res://shaders/water_river.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 2
	mat.set_shader_parameter("deep_c", Vector3(0.08, 0.32, 0.40))
	mat.set_shader_parameter("light_c", Vector3(0.30, 0.58, 0.58))
	mat.set_shader_parameter("sea_c", Vector3(0.30, 0.70, 0.65))
	mat.set_shader_parameter("foam_c", Vector3(0.94, 0.97, 0.96))
	mat.set_shader_parameter("flow_speed", 0.45)
	_map._rivers_mesh.material_override = mat

