extends RefCounted
## Round lake discs matched to the carved basin shoreline.

const MapLakes = preload("res://scripts/map/map_lakes.gd")

var _ctx: TerrainBuildContext


func build(ctx: TerrainBuildContext) -> Dictionary:
	_ctx = ctx
	return _build_lakes()


func _lake_outline_radii(cells: Array, center: Vector2, segs: int) -> PackedFloat32Array:
	## Build a mostly circular shore: grid cells only nudge a round bowl (no stair-steps).
	var radii := PackedFloat32Array()
	radii.resize(segs)
	radii.fill(0.0)
	var data := _ctx.data
	var half: float = data.size * 0.5
	var step: float = data.size / float(data.grid - 1)
	var mean_r := 0.0
	var n_sample := 0
	for c in cells:
		var cell: Vector2i = c
		var x0: float = -half + float(cell.x) * step
		var z0: float = -half + float(cell.y) * step
		# Sample cell center + corners so bins fill, then we circularize
		var samples: Array[Vector2] = [
			Vector2(x0 + step * 0.5, z0 + step * 0.5),
			Vector2(x0, z0), Vector2(x0 + step, z0),
			Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step),
		]
		for sample: Vector2 in samples:
			var d: Vector2 = sample - center
			var dist: float = d.length()
			if dist < 1e-4:
				continue
			var ang := atan2(d.y, d.x)
			if ang < 0.0:
				ang += TAU
			var idx := int(floor(ang / TAU * float(segs))) % segs
			radii[idx] = maxf(radii[idx], dist)
			mean_r += dist
			n_sample += 1
	if n_sample > 0:
		mean_r /= float(n_sample)
	else:
		mean_r = float(cells.size()) * 0.08
	# Fill gaps
	var filled := radii.duplicate()
	for i in segs:
		if filled[i] > 0.05:
			continue
		var best: float = mean_r
		for k in range(1, segs):
			var a: float = radii[(i - k + segs) % segs]
			var b: float = radii[(i + k) % segs]
			if a > 0.05 or b > 0.05:
				best = maxf(a, b)
				break
		filled[i] = best
	# Wide circular blur — kill grid stair-steps
	var cur := filled
	for _pass in 4:
		var nxt := PackedFloat32Array()
		nxt.resize(segs)
		for i in segs:
			var acc := 0.0
			var wsum := 0.0
			for k in range(-5, 6):
				var w := 1.0 - absf(float(k)) / 6.0
				acc += cur[(i + k + segs) % segs] * w
				wsum += w
			nxt[i] = acc / wsum
		cur = nxt
	# Pull hard toward a circle, keep a little organic oval
	var out := PackedFloat32Array()
	out.resize(segs)
	var circle_r := maxf(mean_r, 3.0)
	var sum := 0.0
	for i in segs:
		sum += cur[i]
	circle_r = maxf(sum / float(segs), circle_r)
	for i in segs:
		var ang := TAU * float(i) / float(segs)
		# 18% of the blurred polar shape, 82% circle -> smooth organic shoreline
		out[i] = lerpf(circle_r, cur[i], 0.18) * MapLakes._lake_organic_scale(ang, center) * 1.02
	return out


func _build_lakes() -> Dictionary:
	## Smooth basin-fitted water disc (tightly bounded within the carved shore bank).
	if _ctx == null or _ctx.data == null or _ctx.data.lakes.is_empty():
		return {"mesh": null, "material": null}

	var data := _ctx.data
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const SEGS := 72
	const RINGS := 12

	for lake in data.lakes:
		var ly: float = float(lake["water_y"])
		var center: Vector2 = lake["center"]
		var cells: Array = lake.get("cells", []) as Array
		if cells.is_empty():
			continue
		var radii := _lake_outline_radii(cells, center, SEGS)
		# Match the generator's organic shoreline + slight bank tuck so terrain height_tex cuts the edge cleanly.
		if lake.has("radius"):
			var base_r: float = float(lake["radius"])
			for s in SEGS:
				var ang := TAU * float(s) / float(SEGS)
				var exact_r := base_r * MapLakes._lake_organic_scale(ang, center) * 1.04
				radii[s] = minf(maxf(radii[s], exact_r * 0.96), exact_r)
		var base_vi := verts.size()
		verts.append(Vector3(center.x, ly, center.y))
		uvs.append(Vector2(0.0, 0.0)) # UV.x = normalized radius (0 center .. 1 shore)
		for ring in range(1, RINGS + 1):
			var t := float(ring) / float(RINGS)
			# Push more rings toward the rim for a long soft fade
			var rt := pow(t, 0.75)
			for s in SEGS:
				var ang := TAU * float(s) / float(SEGS)
				var r := radii[s] * rt
				verts.append(Vector3(center.x + cos(ang) * r, ly, center.y + sin(ang) * r))
				uvs.append(Vector2(t, ang / TAU))
		for s in SEGS:
			indices.append_array([base_vi, base_vi + 1 + s, base_vi + 1 + ((s + 1) % SEGS)])
		for ring in range(RINGS - 1):
			for s in SEGS:
				var i0 := base_vi + 1 + ring * SEGS + s
				var i1 := base_vi + 1 + ring * SEGS + ((s + 1) % SEGS)
				var i2 := base_vi + 1 + (ring + 1) * SEGS + ((s + 1) % SEGS)
				var i3 := base_vi + 1 + (ring + 1) * SEGS + s
				indices.append_array([i0, i3, i1, i1, i3, i2])

	if verts.is_empty():
		return {"mesh": null, "material": null}

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var shader := load("res://shaders/water_lake.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("half_world", Vector2(data.size * 0.5, data.size * 0.5))
	mat.set_shader_parameter("height_tex", _ctx.height_tex)
	mat.set_shader_parameter("height_grid", float(data.grid))
	mat.set_shader_parameter("height_min", data.h_min)
	mat.set_shader_parameter("height_span", maxf(data.h_max - data.h_min, 0.001))
	mat.set_shader_parameter("shallow_col", Vector3(0.28, 0.66, 0.60))
	mat.set_shader_parameter("deep_col", Vector3(0.05, 0.25, 0.36))
	mat.set_shader_parameter("foam_col", Vector3(0.95, 0.98, 0.97))
	mat.set_shader_parameter("river_shallow_col", Vector3(0.24, 0.60, 0.54))
	mat.set_shader_parameter("river_deep_col", Vector3(0.04, 0.21, 0.31))
	var packed: Dictionary = _ctx.pack_mouth_uniforms("lake")
	mat.set_shader_parameter("mouth_count", int(packed["count"]))
	mat.set_shader_parameter("mouth_pos_dir", packed["pos_dir"])
	mat.set_shader_parameter("mouth_info", packed["info"])

	return {
		"mesh": mesh,
		"material": mat,
	}
