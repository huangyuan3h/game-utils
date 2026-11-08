extends StaticBody3D
## Renders map data from MapGenerator. Player uses sample_height() (no mesh traps).

const MapGen = preload("res://scripts/map_generator.gd")
const WATER_OFFSET := 0.12

@onready var _mesh_instance: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $Collision
@onready var _water: MeshInstance3D = $Water

var seed_value: int = 42
var map_size: float = MapGen.DEFAULT_SIZE
var grid: int = MapGen.DEFAULT_GRID
var _heights: PackedFloat32Array = PackedFloat32Array()
var _biomes: PackedByteArray = PackedByteArray()
var _noise_m: FastNoiseLite
var _h_min: float = 0.0
var _h_max: float = 1.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	generate_random(seed_value)


## --- Public API -----------------------------------------------------------

func generate_random(p_seed: int = -1, opts: Dictionary = {}) -> Dictionary:
	## Abstract entry used by the game: randomly (or deterministically) build a map.
	var data: Dictionary = MapGen.generate_random(p_seed, opts)
	_apply_map_data(data)
	return data


func rebuild(p_seed: int = 42, opts: Dictionary = {}) -> void:
	## Deterministic rebuild with an explicit seed.
	generate_random(p_seed, opts)


func sample_height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var half := map_size * 0.5
	var u := clampf((x + half) / map_size, 0.0, 1.0)
	var v := clampf((z + half) / map_size, 0.0, 1.0)
	var fx := u * float(grid - 1)
	var fz := v * float(grid - 1)
	var x0 := int(fx)
	var z0 := int(fz)
	var x1 := mini(x0 + 1, grid - 1)
	var z1 := mini(z0 + 1, grid - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := _heights[_idx(x0, z0)]
	var h10 := _heights[_idx(x1, z0)]
	var h01 := _heights[_idx(x0, z1)]
	var h11 := _heights[_idx(x1, z1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func sample_biome(x: float, z: float) -> int:
	if _biomes.is_empty():
		return MapGen.Biome.GRASS
	var half := map_size * 0.5
	var u := clampf((x + half) / map_size, 0.0, 1.0)
	var v := clampf((z + half) / map_size, 0.0, 1.0)
	var ix := clampi(int(round(u * float(grid - 1))), 0, grid - 1)
	var iz := clampi(int(round(v * float(grid - 1))), 0, grid - 1)
	return int(_biomes[_idx(ix, iz)])


func biome_name_at(x: float, z: float) -> String:
	match sample_biome(x, z):
		MapGen.Biome.RIVER:
			return "River"
		MapGen.Biome.SAND:
			return "Sand"
		MapGen.Biome.DIRT:
			return "Dirt"
		MapGen.Biome.GRASS:
			return "Grass"
		MapGen.Biome.MOUNTAIN:
			return "Mountain"
		_:
			return "?"


## --- Internals ------------------------------------------------------------

func _apply_map_data(data: Dictionary) -> void:
	seed_value = int(data.get("seed", 42))
	map_size = float(data.get("size", MapGen.DEFAULT_SIZE))
	grid = int(data.get("grid", MapGen.DEFAULT_GRID))
	_heights = data.get("heights", PackedFloat32Array()) as PackedFloat32Array
	_biomes = data.get("biomes", PackedByteArray()) as PackedByteArray
	_h_min = float(data.get("h_min", 0.0))
	_h_max = float(data.get("h_max", 1.0))
	_noise_m = FastNoiseLite.new()
	_noise_m.seed = seed_value + 17
	_noise_m.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_m.frequency = 0.02
	_build_mesh()
	_collision.shape = null
	_build_water()


func _idx(x: int, z: int) -> int:
	return z * grid + x


func _biome_color(b: int, h: float, wx: float, wz: float) -> Color:
	var grit := (_noise_m.get_noise_2d(wx * 3.1, wz * 3.1) + 1.0) * 0.5
	var t := 0.0
	if _h_max > _h_min:
		t = clampf((h - _h_min) / (_h_max - _h_min), 0.0, 1.0)
	match b:
		MapGen.Biome.RIVER:
			return Color(0.22, 0.34, 0.22).lerp(Color(0.28, 0.36, 0.24), grit)
		MapGen.Biome.SAND:
			return Color(0.76, 0.68, 0.48).lerp(Color(0.62, 0.54, 0.36), grit * 0.5)
		MapGen.Biome.DIRT:
			return Color(0.42, 0.30, 0.20).lerp(Color(0.34, 0.24, 0.16), grit * 0.4)
		MapGen.Biome.GRASS:
			return Color(0.28, 0.48, 0.22).lerp(Color(0.40, 0.46, 0.24), grit)
		MapGen.Biome.MOUNTAIN:
			var rock := Color(0.48, 0.46, 0.44).lerp(Color(0.34, 0.33, 0.32), grit)
			return rock.lerp(Color(0.78, 0.80, 0.82), smoothstep(0.75, 1.0, t))
		_:
			return Color(0.5, 0.5, 0.5)


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := map_size * 0.5
	var step := map_size / float(grid - 1)
	for z in range(grid - 1):
		for x in range(grid - 1):
			_add_quad(st, x, z, half, step)
	st.generate_normals()
	st.generate_tangents()
	_mesh_instance.mesh = st.commit()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.albedo_texture = _make_detail_texture()
	mat.uv1_scale = Vector3(48, 48, 48)
	_mesh_instance.material_override = mat


func _add_quad(st: SurfaceTool, x: int, z: int, half: float, step: float) -> void:
	var corners := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
	for oi in [0, 1, 2, 0, 2, 3]:
		var c: Vector2i = corners[oi]
		var wx := -half + float(c.x) * step
		var wz := -half + float(c.y) * step
		var h := _heights[_idx(c.x, c.y)]
		var b := int(_biomes[_idx(c.x, c.y)])
		st.set_color(_biome_color(b, h, wx, wz))
		st.set_uv(Vector2((wx + half) / map_size, (wz + half) / map_size))
		st.add_vertex(Vector3(wx, h, wz))


func _make_detail_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	for y in 128:
		for x in 128:
			var v := 0.82 + rng.randf() * 0.18
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)


func _river_mask(x: int, z: int) -> float:
	## Soft river membership: 1.0 on river cells, fades across 1-cell banks.
	if x < 0 or z < 0 or x >= grid or z >= grid:
		return 0.0
	if int(_biomes[_idx(x, z)]) == MapGen.Biome.RIVER:
		return 1.0
	var near := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			if nx < 0 or nz < 0 or nx >= grid or nz >= grid:
				continue
			if int(_biomes[_idx(nx, nz)]) == MapGen.Biome.RIVER:
				near = maxf(near, 0.55)
	return near


func _flow_at(x: int, z: int) -> Vector2:
	## Downhill flow from local height gradient (XZ world plane).
	var x0 := clampi(x - 1, 0, grid - 1)
	var x1 := clampi(x + 1, 0, grid - 1)
	var z0 := clampi(z - 1, 0, grid - 1)
	var z1 := clampi(z + 1, 0, grid - 1)
	var dh_dx := (_heights[_idx(x1, z)] - _heights[_idx(x0, z)]) / float(maxi(x1 - x0, 1))
	var dh_dz := (_heights[_idx(x, z1)] - _heights[_idx(x, z0)]) / float(maxi(z1 - z0, 1))
	var flow := Vector2(-dh_dx, -dh_dz)
	if flow.length_squared() < 1e-6:
		# Flat pockets: bias along river chain (prefer +X/+Z so motion never dies)
		flow = Vector2(0.35, 0.65)
	return flow.normalized()


func _smoothed_water_y(x: int, z: int) -> float:
	## Average nearby river beds so the surface isn't a stairstep mosaic.
	var sum := 0.0
	var wsum := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			if nx < 0 or nz < 0 or nx >= grid or nz >= grid:
				continue
			var m := _river_mask(nx, nz)
			if m <= 0.0:
				continue
			var w := m * (1.5 if dx == 0 and dz == 0 else 1.0)
			sum += _heights[_idx(nx, nz)] * w
			wsum += w
	if wsum <= 0.0:
		return _heights[_idx(clampi(x, 0, grid - 1), clampi(z, 0, grid - 1))] + WATER_OFFSET
	return sum / wsum + WATER_OFFSET


func _build_water() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := map_size * 0.5
	var step := map_size / float(grid - 1)

	for z in range(grid - 1):
		for x in range(grid - 1):
			var m00 := _river_mask(x, z)
			var m10 := _river_mask(x + 1, z)
			var m11 := _river_mask(x + 1, z + 1)
			var m01 := _river_mask(x, z + 1)
			var masks := [m00, m10, m11, m01]
			var riverish := 0
			for m in masks:
				if m > 0.4:
					riverish += 1
			if riverish < 1:
				continue

			var corners := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
			var verts: Array[Vector3] = []
			var flows: Array[Vector2] = []
			var edges: Array[float] = []
			var depths: Array[float] = []
			for ci in 4:
				var c: Vector2i = corners[ci]
				var wx := -half + float(c.x) * step
				var wz := -half + float(c.y) * step
				var wy := _smoothed_water_y(c.x, c.y)
				verts.append(Vector3(wx, wy, wz))
				flows.append(_flow_at(c.x, c.y))
				var m: float = masks[ci]
				# Edge foam strong on soft banks / partial river cells
				edges.append(clampf(1.0 - m * 0.85, 0.05, 1.0) if m < 0.99 else 0.08)
				depths.append(clampf(m, 0.15, 1.0))

			for oi in [0, 1, 2, 0, 2, 3]:
				var p: Vector3 = verts[oi]
				var f: Vector2 = flows[oi]
				# COLOR.r = edge/foam, COLOR.g = depth toward channel center
				st.set_color(Color(edges[oi], depths[oi], 0.0, 1.0))
				st.set_uv(Vector2(p.x, p.z))
				st.set_uv2(f)
				st.add_vertex(p)

	st.generate_normals()
	_water.mesh = st.commit()

	var shader := load("res://shaders/water_flow.gdshader") as Shader
	var wmat := ShaderMaterial.new()
	wmat.shader = shader
	wmat.set_shader_parameter("deep_color", Color(0.05, 0.20, 0.30, 0.74))
	wmat.set_shader_parameter("shallow_color", Color(0.24, 0.50, 0.52, 0.46))
	wmat.set_shader_parameter("foam_color", Color(0.90, 0.95, 0.97, 0.9))
	wmat.set_shader_parameter("flow_speed", 0.48)
	wmat.set_shader_parameter("ripple_scale", 6.8)
	wmat.set_shader_parameter("wave_amp", 0.04)
	_water.material_override = wmat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
