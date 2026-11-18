extends RefCounted
## Procedural low-poly land props (grass tufts, flowers, reeds, shrubs, trees, boulders)
## rendered via MultiMeshInstance3D with zero collision shapes so all terrain stays walkable.

const MapGen = preload("res://scripts/map_generator.gd")
const MapLakes = preload("res://scripts/map/map_lakes.gd")
const MapRivers = preload("res://scripts/map/map_rivers.gd")
## Keep trunks and canopies off the channel. Gap is measured past the bank.
const TREE_RIVER_GAP := 3.2

var _ctx: TerrainBuildContext


func build(ctx: TerrainBuildContext, props_root: Node3D) -> void:
	_ctx = ctx
	if _ctx == null or _ctx.data == null or props_root == null:
		return
	var data := _ctx.data
	for ch in props_root.get_children():
		props_root.remove_child(ch)
		ch.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.seed_value) ^ 0x5A17C3

	var grass_xforms: Array[Transform3D] = []
	var grass_cols: Array[Color] = []
	var grass_custom: Array[Color] = []

	var flower_xforms: Array[Transform3D] = []
	var flower_cols: Array[Color] = []
	var flower_custom: Array[Color] = []

	var reed_xforms: Array[Transform3D] = []
	var reed_cols: Array[Color] = []
	var reed_custom: Array[Color] = []

	var shrub_xforms: Array[Transform3D] = []
	var shrub_cols: Array[Color] = []
	var shrub_custom: Array[Color] = []

	var pine_xforms: Array[Transform3D] = []
	var pine_cols: Array[Color] = []
	var pine_custom: Array[Color] = []

	var broad_xforms: Array[Transform3D] = []
	var broad_cols: Array[Color] = []
	var broad_custom: Array[Color] = []

	var rock_xforms: Array[Transform3D] = []
	var rock_cols: Array[Color] = []

	var half: float = float(data.size) * 0.5 - 2.0
	var noise_patch := FastNoiseLite.new()
	noise_patch.seed = int(data.seed_value) + 313
	noise_patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_patch.frequency = 0.065

	# 1) Dense ground cover (grass tufts + wildflowers) on jittered ~1.15m lattice
	var grass_step := 1.15
	var nx := int((half * 2.0) / grass_step)
	for iz in nx:
		for ix in nx:
			var wx := -half + (float(ix) + rng.randf_range(0.08, 0.92)) * grass_step
			var wz := -half + (float(iz) + rng.randf_range(0.08, 0.92)) * grass_step
			var b: int = _ctx.sample_biome(wx, wz)
			if b != MapGen.Biome.GRASS and b != MapGen.Biome.MEADOW and b != MapGen.Biome.FOREST:
				continue
			var h: float = _ctx.sample_height(wx, wz)
			var local_wy: float = _local_water_y(wx, wz)
			if h < local_wy + 0.18:
				continue
			var slope: float = _ctx.sample_slope(wx, wz)
			if slope > 0.45:
				continue
			var patch := (noise_patch.get_noise_2d(wx, wz) + 1.0) * 0.5
			var keep_prob := 0.58 if b == MapGen.Biome.GRASS else (0.82 if b == MapGen.Biome.MEADOW else 0.45)
			if patch < 0.25:
				keep_prob *= 0.45
			if rng.randf() > keep_prob:
				continue

			var yaw := rng.randf() * TAU
			var sy := rng.randf_range(0.75, 1.38) * (1.15 if b == MapGen.Biome.MEADOW else 0.95)
			var sxz := rng.randf_range(0.85, 1.40)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sxz, sy, sxz)), Vector3(wx, h - 0.04, wz))
			grass_xforms.append(xf)

			var tint := Color(0.90, 1.0, 0.88)
			if b == MapGen.Biome.MEADOW:
				tint = Color(0.95, 1.08, 0.85).lerp(Color(1.06, 1.04, 0.78), rng.randf() * 0.5)
			elif b == MapGen.Biome.FOREST:
				tint = Color(0.68, 0.84, 0.66).lerp(Color(0.76, 0.90, 0.70), rng.randf())
			else:
				tint = Color(0.84, 0.96, 0.76).lerp(Color(1.02, 0.98, 0.72), rng.randf() * 0.45)
			grass_cols.append(tint)
			grass_custom.append(Color(rng.randf(), rng.randf_range(0.7, 1.25), rng.randf(), 1.0))

			# Wildflowers clustered in MEADOW and sunny GRASS patches
			var flower_prob := 0.34 if b == MapGen.Biome.MEADOW else (0.08 if b == MapGen.Biome.GRASS else 0.0)
			if flower_prob > 0.0 and patch > 0.38 and rng.randf() < flower_prob:
				var f_yaw := rng.randf() * TAU
				var fs := rng.randf_range(0.85, 1.35)
				var f_xf := Transform3D(Basis(Vector3.UP, f_yaw).scaled(Vector3(fs, fs, fs)), Vector3(wx + rng.randf_range(-0.25, 0.25), h - 0.02, wz + rng.randf_range(-0.25, 0.25)))
				flower_xforms.append(f_xf)
				var palette := [
					Color(1.0, 0.86, 0.32),
					Color(0.96, 0.60, 0.72),
					Color(0.84, 0.76, 1.0),
					Color(1.0, 0.97, 0.88),
				]
				flower_cols.append(palette[rng.randi_range(0, palette.size() - 1)])
				flower_custom.append(Color(rng.randf(), rng.randf_range(0.8, 1.3), rng.randf(), 1.0))

	# 2) Riparian reeds along riverbanks and lake rims
	_populate_shore_reeds(rng, reed_xforms, reed_cols, reed_custom)

	# 3) Macro props (trees, shrubs, boulders) on ~3.6m jittered lattice with spot clearance
	var macro_step := 3.6
	var mx := int((half * 2.0) / macro_step)
	for iz in mx:
		for ix in mx:
			var wx := -half + (float(ix) + rng.randf_range(0.15, 0.85)) * macro_step
			var wz := -half + (float(iz) + rng.randf_range(0.15, 0.85)) * macro_step
			if _near_clear_spot(wx, wz, 2.8):
				continue
			var b: int = _ctx.sample_biome(wx, wz)
			var h: float = _ctx.sample_height(wx, wz)
			var slope: float = _ctx.sample_slope(wx, wz)
			var water_y: float = float(data.water_y)
			var nrm := _sample_normal(wx, wz)
			var patch := (noise_patch.get_noise_2d(wx * 0.7, wz * 0.7) + 1.0) * 0.5

			# Boulders & coastal rocks
			var rock_prob := 0.0
			if b == MapGen.Biome.CLIFF or b == MapGen.Biome.ALPINE:
				rock_prob = 0.58
			elif b == MapGen.Biome.MOUNTAIN:
				rock_prob = 0.40
			elif b == MapGen.Biome.DIRT:
				rock_prob = 0.18
			elif b == MapGen.Biome.SAND and h > water_y - 0.30 and h < water_y + 1.2 and patch > 0.56:
				rock_prob = 0.14
			elif (b == MapGen.Biome.GRASS or b == MapGen.Biome.FOREST) and slope > 0.32:
				rock_prob = 0.22

			if rng.randf() < rock_prob:
				var r_scale := rng.randf_range(0.45, 1.15)
				if b == MapGen.Biome.CLIFF or b == MapGen.Biome.MOUNTAIN:
					r_scale *= rng.randf_range(1.0, 1.45)
				var rock_basis := _align_up(Vector3.UP.lerp(nrm, 0.45).normalized(), rng.randf() * TAU)
				rock_basis = rock_basis.scaled(Vector3(
					r_scale * rng.randf_range(0.85, 1.35),
					r_scale * rng.randf_range(0.60, 1.10),
					r_scale * rng.randf_range(0.85, 1.35)
				))
				rock_xforms.append(Transform3D(rock_basis, Vector3(wx, h - r_scale * 0.22, wz)))
				if b == MapGen.Biome.SAND:
					rock_cols.append(Color(0.60, 0.54, 0.46).lerp(Color(0.48, 0.45, 0.40), rng.randf()))
				elif b == MapGen.Biome.ALPINE:
					rock_cols.append(Color(0.68, 0.72, 0.76).lerp(Color(0.48, 0.50, 0.54), rng.randf()))
				else:
					rock_cols.append(Color(0.46, 0.45, 0.43).lerp(Color(0.60, 0.56, 0.50), rng.randf()))
				continue

			# Trees & shrubs on walkable dry ground (clear of both sea and lake waterlines)
			var local_wy: float = _local_water_y(wx, wz)
			if h < local_wy + 0.38 or slope > 0.40:
				continue

			var clear_of_river := not _too_close_to_river(wx, wz)
			if b == MapGen.Biome.FOREST:
				if clear_of_river and rng.randf() < 0.54:
					var ts := rng.randf_range(0.82, 1.38)
					var up_dir := Vector3.UP.lerp(nrm, 0.10).normalized()
					var tb := _align_up(up_dir, rng.randf() * TAU).scaled(Vector3(ts, ts * rng.randf_range(0.95, 1.25), ts))
					if patch > 0.34:
						pine_xforms.append(Transform3D(tb, Vector3(wx, h - 0.10, wz)))
						pine_cols.append(Color(0.88, 0.96, 0.88).lerp(Color(1.04, 1.0, 0.92), rng.randf() * 0.45))
						pine_custom.append(Color(rng.randf(), 0.28, rng.randf(), 1.0))
					else:
						broad_xforms.append(Transform3D(tb, Vector3(wx, h - 0.10, wz)))
						broad_cols.append(Color(0.86, 0.98, 0.82).lerp(Color(1.02, 0.94, 0.72), rng.randf() * 0.4))
						broad_custom.append(Color(rng.randf(), 0.34, rng.randf(), 1.0))
				elif rng.randf() < 0.48:
					_add_shrub(wx, h, wz, rng, shrub_xforms, shrub_cols, shrub_custom)

			elif b == MapGen.Biome.MEADOW or b == MapGen.Biome.GRASS:
				if clear_of_river and patch > 0.46 and rng.randf() < 0.24:
					var ts2 := rng.randf_range(0.78, 1.22)
					var tb2 := _align_up(Vector3.UP.lerp(nrm, 0.10).normalized(), rng.randf() * TAU).scaled(Vector3(ts2, ts2, ts2))
					broad_xforms.append(Transform3D(tb2, Vector3(wx, h - 0.08, wz)))
					broad_cols.append(Color(0.92, 1.02, 0.84).lerp(Color(1.06, 0.96, 0.72), rng.randf() * 0.5))
					broad_custom.append(Color(rng.randf(), 0.36, rng.randf(), 1.0))
				elif rng.randf() < 0.18:
					_add_shrub(wx, h, wz, rng, shrub_xforms, shrub_cols, shrub_custom)

			elif b == MapGen.Biome.MOUNTAIN and h < float(data.h_max) - 1.8:
				if clear_of_river and rng.randf() < 0.14:
					var ts3 := rng.randf_range(0.65, 1.05)
					var tb3 := _align_up(Vector3.UP.lerp(nrm, 0.08).normalized(), rng.randf() * TAU).scaled(Vector3(ts3, ts3, ts3))
					pine_xforms.append(Transform3D(tb3, Vector3(wx, h - 0.10, wz)))
					pine_cols.append(Color(0.78, 0.90, 0.84))
					pine_custom.append(Color(rng.randf(), 0.24, rng.randf(), 1.0))

			elif b == MapGen.Biome.DIRT and rng.randf() < 0.14:
				_add_shrub(wx, h, wz, rng, shrub_xforms, shrub_cols, shrub_custom, true)

	# 3) Commit MultiMeshInstance3D batches
	_spawn_multimesh(props_root, "GrassTufts", _make_grass_mesh(), _make_foliage_material(0.08, 1.8, true), grass_xforms, grass_cols, grass_custom, false)
	_spawn_multimesh(props_root, "Wildflowers", _make_flower_mesh(), _make_foliage_material(0.09, 1.9, true), flower_xforms, flower_cols, flower_custom, false)
	_spawn_multimesh(props_root, "ShoreReeds", _make_reed_mesh(), _make_foliage_material(0.11, 1.5, true), reed_xforms, reed_cols, reed_custom, false)
	_spawn_multimesh(props_root, "Shrubs", _make_shrub_mesh(), _make_foliage_material(0.04, 1.4, false), shrub_xforms, shrub_cols, shrub_custom, true)
	_spawn_multimesh(props_root, "PineTrees", _make_pine_mesh(), _make_foliage_material(0.06, 1.1, false), pine_xforms, pine_cols, pine_custom, true)
	_spawn_multimesh(props_root, "BroadleafTrees", _make_broadleaf_mesh(), _make_foliage_material(0.07, 1.2, false), broad_xforms, broad_cols, broad_custom, true)
	_spawn_multimesh(props_root, "Boulders", _make_rock_mesh(), _make_rock_material(), rock_xforms, rock_cols, [], true)


func _populate_shore_reeds(
	rng: RandomNumberGenerator,
	reed_xforms: Array[Transform3D],
	reed_cols: Array[Color],
	reed_custom: Array[Color]
) -> void:
	var data := _ctx.data
	var half_limit: float = float(data.size) * 0.5 - 2.0
	var water_y: float = float(data.water_y)
	# Sample along lake shorelines
	for lake in data.lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake.get("radius", 8.0))
		var ly: float = float(lake.get("water_y", water_y))
		var ring_count := maxi(16, int(round(r * 2.2)))
		for i in ring_count:
			if rng.randf() > 0.58:
				continue
			var ang := TAU * float(i) / float(ring_count) + rng.randf_range(-0.15, 0.15)
			var org := MapLakes._lake_organic_scale(ang, c)
			var dist := r * org * 0.98 + rng.randf_range(-0.12, 0.95)
			var rx := c.x + cos(ang) * dist
			var rz := c.y + sin(ang) * dist
			if absf(rx) > half_limit or absf(rz) > half_limit or _near_clear_spot(rx, rz, 2.2):
				continue
			var rh: float = _ctx.sample_height(rx, rz)
			if rh < ly - 0.12 or rh > ly + 0.45:
				continue
			var rs := rng.randf_range(0.85, 1.35)
			reed_xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rs, rs, rs)), Vector3(rx, rh - 0.05, rz)))
			reed_cols.append(Color(0.88, 0.96, 0.76).lerp(Color(0.98, 0.92, 0.66), rng.randf() * 0.45))
			reed_custom.append(Color(rng.randf(), rng.randf_range(0.9, 1.35), rng.randf(), 1.0))

	# Sample along river banks
	for river in data.rivers:
		var pts: PackedVector2Array = river
		if pts.size() < 2:
			continue
		for i in range(2, pts.size(), 2):
			if rng.randf() > 0.45:
				continue
			var along := float(i) / float(maxi(pts.size() - 1, 1))
			if along > 0.90:
				continue
			var p: Vector2 = pts[i]
			var prev: Vector2 = pts[maxi(0, i - 1)]
			var dir := (p - prev).normalized()
			if dir.length_squared() < 1e-6:
				continue
			var perp := Vector2(-dir.y, dir.x)
			var side := 1.0 if rng.randf() > 0.5 else -1.0
			var bank_off := MapGen.river_half_width(along) * rng.randf_range(1.05, 1.65)
			var rp := p + perp * (side * bank_off)
			if absf(rp.x) > half_limit or absf(rp.y) > half_limit or _near_clear_spot(rp.x, rp.y, 2.2):
				continue
			var b: int = _ctx.sample_biome(rp.x, rp.y)
			if b == MapGen.Biome.SEA or b == MapGen.Biome.LAKE or b == MapGen.Biome.RIVER:
				continue
			var rh: float = _ctx.sample_height(rp.x, rp.y)
			if rh < water_y + 0.05:
				continue
			var rs := rng.randf_range(0.80, 1.28)
			reed_xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rs, rs, rs)), Vector3(rp.x, rh - 0.05, rp.y)))
			reed_cols.append(Color(0.88, 0.96, 0.76).lerp(Color(0.98, 0.92, 0.66), rng.randf() * 0.45))
			reed_custom.append(Color(rng.randf(), rng.randf_range(0.9, 1.35), rng.randf(), 1.0))


func _add_shrub(
	wx: float,
	h: float,
	wz: float,
	rng: RandomNumberGenerator,
	xforms: Array[Transform3D],
	cols: Array[Color],
	custom: Array[Color],
	dry: bool = false
) -> void:
	var ss := rng.randf_range(0.70, 1.25)
	xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(ss, ss * rng.randf_range(0.8, 1.15), ss)), Vector3(wx, h - 0.06, wz)))
	if dry:
		cols.append(Color(0.76, 0.72, 0.48).lerp(Color(0.62, 0.66, 0.44), rng.randf()))
	else:
		cols.append(Color(0.84, 0.96, 0.78).lerp(Color(0.98, 0.94, 0.70), rng.randf() * 0.4))
	custom.append(Color(rng.randf(), rng.randf_range(0.5, 0.9), rng.randf(), 1.0))


func _local_water_y(wx: float, wz: float) -> float:
	## Highest relevant water level at (wx, wz) across sea and nearby lake basins.
	var data := _ctx.data
	var wy := float(data.water_y)
	var p := Vector2(wx, wz)
	for lake in data.lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake.get("radius", 8.0))
		if p.distance_to(c) <= r * 1.28:
			wy = maxf(wy, float(lake["water_y"]))
	return wy


func _too_close_to_river(x: float, z: float) -> bool:
	if _ctx == null or _ctx.data == null:
		return false
	var p := Vector2(x, z)
	for river in _ctx.data.rivers:
		var pts: PackedVector2Array = river
		if pts.size() < 2:
			continue
		var along := MapRivers._along_polyline(p, pts)
		var bank := MapGen.river_half_width(along)
		if MapRivers._dist_to_polyline(p, pts) < bank + TREE_RIVER_GAP:
			return true
	return false


func _near_clear_spot(x: float, z: float, radius: float) -> bool:
	if _ctx == null or _ctx.clear_spots.is_empty():
		return false
	var p := Vector2(x, z)
	var r2 := radius * radius
	for s: Vector2 in _ctx.clear_spots:
		if p.distance_squared_to(s) < r2:
			return true
	return false


func _sample_normal(x: float, z: float) -> Vector3:
	var d := 0.65
	var hx0: float = _ctx.sample_height(x - d, z)
	var hx1: float = _ctx.sample_height(x + d, z)
	var hz0: float = _ctx.sample_height(x, z - d)
	var hz1: float = _ctx.sample_height(x, z + d)
	return Vector3(hx0 - hx1, 2.0 * d, hz0 - hz1).normalized()


func _align_up(up_vec: Vector3, yaw: float) -> Basis:
	var y := up_vec.normalized()
	var ref := Vector3(sin(yaw), 0.0, cos(yaw))
	var x := y.cross(ref)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _spawn_multimesh(
	parent: Node3D,
	node_name: String,
	mesh: Mesh,
	mat: Material,
	xforms: Array[Transform3D],
	cols: Array[Color],
	custom: Array[Color],
	cast_shadow: bool
) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, custom[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


func _make_foliage_material(sway_amp: float, sway_speed: float, dist_fade: bool) -> ShaderMaterial:
	var shader := load("res://shaders/foliage_sway.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("sway_amp", sway_amp)
	mat.set_shader_parameter("sway_speed", sway_speed)
	mat.set_shader_parameter("use_distance_fade", dist_fade)
	mat.set_shader_parameter("fade_start", 40.0)
	mat.set_shader_parameter("fade_end", 56.0)
	return mat


func _make_rock_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.88
	mat.metallic = 0.0
	return mat


## --- Procedural Low-Poly Mesh Builders ------------------------------------

func _make_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_col := Color(0.16, 0.30, 0.12)
	var tip_col := Color(0.36, 0.56, 0.24)
	for i in 3:
		var ang := float(i) * (TAU / 3.0) + 0.2
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var base_c := dir * 0.04
		var lean := dir * 0.10
		var h := 0.28 + float(i % 2) * 0.07
		var p0 := base_c - side * 0.045
		var p1 := base_c + side * 0.045
		var p2 := base_c + lean + Vector3(0.0, h, 0.0)
		st.set_color(root_col)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(p0)
		st.set_color(root_col)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(p1)
		st.set_color(tip_col)
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(p2)
	st.generate_normals()
	return st.commit()


func _make_flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_bot := Color(0.18, 0.38, 0.14)
	var stem_top := Color(0.30, 0.52, 0.20)
	# Two tiny crossed blades + bright blossom crown
	for i in 2:
		var ang := float(i) * PI * 0.5
		var side := Vector3(cos(ang), 0.0, sin(ang)) * 0.025
		st.set_color(stem_bot)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(-side)
		st.set_color(stem_bot)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(side)
		st.set_color(stem_top)
		st.set_uv(Vector2(0.5, 0.85))
		st.add_vertex(Vector3(0.02, 0.28, 0.01))
	var center := Vector3(0.02, 0.29, 0.01)
	var petal := Color(1.0, 1.0, 1.0)
	for p in 4:
		var a0 := float(p) * PI * 0.5
		var a1 := a0 + PI * 0.38
		var q0 := center + Vector3(cos(a0) * 0.08, 0.03, sin(a0) * 0.08)
		var q1 := center + Vector3(cos(a1) * 0.08, 0.03, sin(a1) * 0.08)
		st.set_color(petal)
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(center)
		st.set_color(petal)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(q0)
		st.set_color(petal)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(q1)
	st.generate_normals()
	return st.commit()


func _make_reed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_c := Color(0.20, 0.34, 0.14)
	var tip_c := Color(0.46, 0.52, 0.22)
	var head_c := Color(0.36, 0.20, 0.10)
	for i in 4:
		var ang := float(i) * (TAU / 4.0) + 0.35
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var base_c := dir * 0.07
		var h := 0.85 + float(i % 2) * 0.22
		var lean := dir * 0.16
		st.set_color(root_c)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(base_c - side * 0.04)
		st.set_color(root_c)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(base_c + side * 0.04)
		st.set_color(tip_c)
		st.set_uv(Vector2(0.5, 1.0))
		st.add_vertex(base_c + lean + Vector3(0.0, h, 0.0))
		if i < 2:
			# Cattail spike
			var c_bot := base_c + lean * 0.72 + Vector3(0.0, h * 0.72, 0.0)
			var c_top := c_bot + lean * 0.18 + Vector3(0.0, 0.18, 0.0)
			st.set_color(head_c)
			st.set_uv(Vector2(0.2, 0.8))
			st.add_vertex(c_bot - side * 0.03)
			st.set_color(head_c)
			st.set_uv(Vector2(0.8, 0.8))
			st.add_vertex(c_bot + side * 0.03)
			st.set_color(head_c)
			st.set_uv(Vector2(0.5, 0.95))
			st.add_vertex(c_top)
	st.generate_normals()
	return st.commit()


func _make_shrub_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_icosphere(st, Vector3(0.0, 0.26, 0.0), Vector3(0.42, 0.32, 0.40), Color(0.20, 0.39, 0.16), Color(0.32, 0.50, 0.22), 0.15, 0.65)
	_append_icosphere(st, Vector3(0.20, 0.20, 0.14), Vector3(0.28, 0.24, 0.28), Color(0.18, 0.36, 0.14), Color(0.30, 0.48, 0.20), 0.10, 0.60)
	_append_icosphere(st, Vector3(-0.18, 0.22, -0.12), Vector3(0.30, 0.25, 0.26), Color(0.22, 0.40, 0.16), Color(0.34, 0.52, 0.24), 0.10, 0.60)
	st.generate_normals()
	return st.commit()


func _make_pine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_cone(st, Vector3.ZERO, 0.20, 0.08, 1.35, 6, Color(0.26, 0.18, 0.11), Color(0.34, 0.24, 0.15), 0.0, 0.0)
	_append_cone(st, Vector3(0.0, 1.05, 0.0), 1.15, 0.12, 1.55, 7, Color(0.12, 0.27, 0.14), Color(0.19, 0.38, 0.19), 0.22, 0.55)
	_append_cone(st, Vector3(0.0, 2.05, 0.0), 0.88, 0.08, 1.40, 7, Color(0.14, 0.31, 0.16), Color(0.22, 0.42, 0.21), 0.45, 0.78)
	_append_cone(st, Vector3(0.0, 2.95, 0.0), 0.58, 0.02, 1.25, 6, Color(0.17, 0.35, 0.18), Color(0.26, 0.48, 0.24), 0.65, 1.00)
	st.generate_normals()
	return st.commit()


func _make_broadleaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_cone(st, Vector3.ZERO, 0.22, 0.11, 1.75, 6, Color(0.28, 0.20, 0.12), Color(0.36, 0.26, 0.16), 0.0, 0.0)
	_append_icosphere(st, Vector3(0.0, 2.25, 0.0), Vector3(1.05, 0.88, 1.02), Color(0.20, 0.40, 0.16), Color(0.36, 0.56, 0.22), 0.35, 0.90)
	_append_icosphere(st, Vector3(0.55, 1.95, 0.25), Vector3(0.68, 0.62, 0.68), Color(0.18, 0.37, 0.14), Color(0.34, 0.52, 0.20), 0.30, 0.80)
	_append_icosphere(st, Vector3(-0.50, 2.02, -0.30), Vector3(0.72, 0.64, 0.70), Color(0.22, 0.42, 0.18), Color(0.38, 0.58, 0.24), 0.32, 0.82)
	st.generate_normals()
	return st.commit()


func _make_rock_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := [
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.95, 0.18, 0.22),
		Vector3(0.28, 0.25, 0.92),
		Vector3(-0.85, 0.14, 0.35),
		Vector3(-0.32, 0.22, -0.88),
		Vector3(0.55, -0.25, -0.58),
		Vector3(0.0, -0.75, 0.0),
	]
	# Faceted rock tris
	var faces := [
		[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 5], [0, 5, 1],
		[6, 2, 1], [6, 3, 2], [6, 4, 3], [6, 5, 4], [6, 1, 5],
	]
	for f in faces:
		for vi in f:
			var v: Vector3 = base[vi]
			var shade := clampf(v.y * 0.35 + 0.68, 0.45, 1.0)
			st.set_color(Color(shade, shade * 0.98, shade * 0.95))
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _append_cone(
	st: SurfaceTool,
	origin: Vector3,
	r_bot: float,
	r_top: float,
	height: float,
	segs: int,
	col_bot: Color,
	col_top: Color,
	uv_bot: float,
	uv_top: float
) -> void:
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var b0 := origin + Vector3(cos(a0) * r_bot, 0.0, sin(a0) * r_bot)
		var b1 := origin + Vector3(cos(a1) * r_bot, 0.0, sin(a1) * r_bot)
		var t0 := origin + Vector3(cos(a0) * r_top, height, sin(a0) * r_top)
		var t1 := origin + Vector3(cos(a1) * r_top, height, sin(a1) * r_top)
		st.set_color(col_bot); st.set_uv(Vector2(0.0, uv_bot)); st.add_vertex(b0)
		st.set_color(col_top); st.set_uv(Vector2(0.0, uv_top)); st.add_vertex(t0)
		st.set_color(col_bot); st.set_uv(Vector2(1.0, uv_bot)); st.add_vertex(b1)

		st.set_color(col_bot); st.set_uv(Vector2(1.0, uv_bot)); st.add_vertex(b1)
		st.set_color(col_top); st.set_uv(Vector2(0.0, uv_top)); st.add_vertex(t0)
		st.set_color(col_top); st.set_uv(Vector2(1.0, uv_top)); st.add_vertex(t1)

		# Underside cap so canopy reads solid from low camera
		if r_bot > 0.25:
			var center_b := origin + Vector3(0.0, 0.05, 0.0)
			st.set_color(col_bot.darkened(0.25)); st.set_uv(Vector2(0.5, uv_bot)); st.add_vertex(center_b)
			st.set_color(col_bot.darkened(0.25)); st.set_uv(Vector2(0.0, uv_bot)); st.add_vertex(b0)
			st.set_color(col_bot.darkened(0.25)); st.set_uv(Vector2(1.0, uv_bot)); st.add_vertex(b1)


func _append_icosphere(
	st: SurfaceTool,
	center: Vector3,
	radii: Vector3,
	col_bot: Color,
	col_top: Color,
	uv_bot: float,
	uv_top: float
) -> void:
	# Faceted 8-sided double pyramid / diamond crown for clean low-poly foliage
	var segs := 7
	var top := center + Vector3(0.0, radii.y, 0.0)
	var bot := center - Vector3(0.0, radii.y * 0.78, 0.0)
	var mid_col := col_bot.lerp(col_top, 0.55)
	var uv_mid := lerpf(uv_bot, uv_top, 0.55)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var w0 := 0.92 + 0.14 * sin(float(i) * 2.1)
		var w1 := 0.92 + 0.14 * sin(float(i + 1) * 2.1)
		var m0 := center + Vector3(cos(a0) * radii.x * w0, 0.0, sin(a0) * radii.z * w0)
		var m1 := center + Vector3(cos(a1) * radii.x * w1, 0.0, sin(a1) * radii.z * w1)
		# Upper dome
		st.set_color(col_top); st.set_uv(Vector2(0.5, uv_top)); st.add_vertex(top)
		st.set_color(mid_col); st.set_uv(Vector2(1.0, uv_mid)); st.add_vertex(m1)
		st.set_color(mid_col); st.set_uv(Vector2(0.0, uv_mid)); st.add_vertex(m0)
		# Lower dome
		st.set_color(col_bot); st.set_uv(Vector2(0.5, uv_bot)); st.add_vertex(bot)
		st.set_color(mid_col); st.set_uv(Vector2(0.0, uv_mid)); st.add_vertex(m0)
		st.set_color(mid_col); st.set_uv(Vector2(1.0, uv_mid)); st.add_vertex(m1)
