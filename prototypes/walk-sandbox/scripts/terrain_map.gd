extends StaticBody3D
## Renders MapGenerator data.
## Ground mesh stays here. Sea, lake, and river meshes are built by scripts/terrain/.

const MapGen = preload("res://scripts/map_generator.gd")
const SeaMesh = preload("res://scripts/terrain/sea_mesh.gd")
const LakeMesh = preload("res://scripts/terrain/lake_mesh.gd")
const RiverMesh = preload("res://scripts/terrain/river_mesh.gd")

@onready var _mesh_instance: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $Collision
@onready var _water: MeshInstance3D = $Water
@onready var _rivers_mesh: MeshInstance3D = $Rivers
@onready var _lakes_mesh: MeshInstance3D = $Lakes

var seed_value: int = 42
var map_size: float = MapGen.DEFAULT_SIZE
var grid: int = MapGen.DEFAULT_GRID
var water_y: float = MapGen.DEFAULT_WATER_Y
var sea_edge: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
var _biomes: PackedByteArray = PackedByteArray()
var _rivers: Array = []
var _lakes: Array = []
var _noise_m: FastNoiseLite
var _h_min: float = 0.0
var _h_max: float = 1.0
var _height_tex: ImageTexture


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	if _rivers_mesh == null:
		_rivers_mesh = MeshInstance3D.new()
		_rivers_mesh.name = "Rivers"
		add_child(_rivers_mesh)
	if _lakes_mesh == null:
		_lakes_mesh = MeshInstance3D.new()
		_lakes_mesh.name = "Lakes"
		add_child(_lakes_mesh)
	generate_random(seed_value)


## --- Public API -----------------------------------------------------------

func generate_random(p_seed: int = -1, opts: Dictionary = {}) -> Dictionary:
	var data: Dictionary = MapGen.generate_random(p_seed, opts)
	_apply_map_data(data)
	return data


func rebuild(p_seed: int = 42, opts: Dictionary = {}) -> void:
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


func sample_water_surface(x: float, z: float) -> float:
	## Open-water surface Y the player can swim on, or -INF if dry / too shallow.
	var h := sample_height(x, z)
	var b := sample_biome(x, z)
	var best := -INF
	if b == MapGen.Biome.SEA or h < water_y - 0.15:
		# Coastal sea plane covers any bed below the shared waterline
		if b == MapGen.Biome.SEA or MapGen._sea_proximity(x, z, map_size, sea_edge) > 0.48 \
				or h < water_y - 0.45:
			if water_y - h > 0.35:
				best = maxf(best, water_y)
	for lake in _lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake.get("radius", 6.0))
		var ly: float = float(lake["water_y"])
		if Vector2(x, z).distance_to(c) <= r * 1.08 and ly - h > 0.35:
			best = maxf(best, ly)
	# Rivers are a shallow walkable sheet — do not report them as swimmable open water.
	return best


func nearest_water_distance(x: float, z: float) -> float:
	## Horizontal distance to nearest river / lake / sea (for ambience fade).
	var p := Vector2(x, z)
	var b := sample_biome(x, z)
	if b == MapGen.Biome.SEA or b == MapGen.Biome.LAKE or b == MapGen.Biome.RIVER:
		return 0.0
	var best := INF
	for river in _rivers:
		best = minf(best, MapGen._dist_to_polyline(p, river as PackedVector2Array))
	for lake in _lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake.get("radius", 6.0))
		best = minf(best, maxf(0.0, p.distance_to(c) - r * 0.85))
	# Distance toward the coastal sea plane
	var half := map_size * 0.5
	var sea_d := INF
	match sea_edge:
		0:
			sea_d = half - z
		1:
			sea_d = z + half
		2:
			sea_d = half - x
		_:
			sea_d = x + half
	# Sea starts roughly in the outer ~22% of the map
	best = minf(best, maxf(0.0, sea_d - map_size * 0.12))
	return best


func biome_name_at(x: float, z: float) -> String:
	match sample_biome(x, z):
		MapGen.Biome.SEA:
			return "Sea"
		MapGen.Biome.LAKE:
			return "Lake"
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
	water_y = float(data.get("water_y", MapGen.DEFAULT_WATER_Y))
	sea_edge = int(data.get("sea_edge", 0))
	_heights = data.get("heights", PackedFloat32Array()) as PackedFloat32Array
	_biomes = data.get("biomes", PackedByteArray()) as PackedByteArray
	_rivers = data.get("rivers", []) as Array
	_lakes = data.get("lakes", []) as Array
	_h_min = float(data.get("h_min", 0.0))
	_h_max = float(data.get("h_max", 1.0))
	_noise_m = FastNoiseLite.new()
	_noise_m.seed = seed_value + 17
	_noise_m.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_m.frequency = 0.02
	_height_tex = _make_height_texture()
	_build_mesh()
	_collision.shape = null
	_build_sea()
	_build_lakes()
	_build_rivers()


func _idx(x: int, z: int) -> int:
	return z * grid + x


func _biome_color(b: int, h: float, wx: float, wz: float) -> Color:
	var grit := (_noise_m.get_noise_2d(wx * 3.1, wz * 3.1) + 1.0) * 0.5
	var t := 0.0
	if _h_max > _h_min:
		t = clampf((h - _h_min) / (_h_max - _h_min), 0.0, 1.0)
	match b:
		MapGen.Biome.SEA:
			# Seabed tint under translucent sea plane
			return Color(0.22, 0.34, 0.30).lerp(Color(0.18, 0.28, 0.26), grit)
		MapGen.Biome.LAKE:
			return Color(0.16, 0.32, 0.30).lerp(Color(0.20, 0.36, 0.28), grit)
		MapGen.Biome.RIVER:
			# Wet bed under the water ribbon (darker so clear water reads on top)
			return Color(0.22, 0.28, 0.24).lerp(Color(0.28, 0.26, 0.20), grit)
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


func _make_height_texture() -> ImageTexture:
	## R channel = normalized height for sea depth/foam sampling.
	## Mipmaps + linear filter keep far shorelines calm (no near/far pop).
	var img := Image.create(grid, grid, false, Image.FORMAT_RF)
	var span := maxf(_h_max - _h_min, 0.001)
	for z in grid:
		for x in grid:
			var n := (_heights[_idx(x, z)] - _h_min) / span
			img.set_pixel(x, z, Color(n, 0, 0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	return tex


func _refresh_height_range() -> void:
	var lo := INF
	var hi := -INF
	for h in _heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	_h_min = lo
	_h_max = hi




func _build_sea() -> void:
	SeaMesh.new().build(self)


func _build_lakes() -> void:
	LakeMesh.new().build(self)


func _build_rivers() -> void:
	RiverMesh.new().build(self)
