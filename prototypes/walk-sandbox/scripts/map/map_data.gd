class_name MapData
extends Resource
## Strongly-typed procedural world data container + spatial query API.
## Pure data resource (no SceneTree or Mesh dependencies), safe for background generation and unit tests.

const MapTypes = preload("res://scripts/map/map_types.gd")
const MapHeightfield = preload("res://scripts/map/map_heightfield.gd")
const MapRivers = preload("res://scripts/map/map_rivers.gd")

@export var seed_value: int = 42
@export var size: float = MapTypes.DEFAULT_SIZE
@export var grid: int = MapTypes.DEFAULT_GRID
@export var base_height: float = MapTypes.DEFAULT_BASE
@export var max_height: float = MapTypes.DEFAULT_MAX_H
@export var water_y: float = MapTypes.DEFAULT_WATER_Y
@export var sea_edge: int = 0
@export var landform: int = MapTypes.Landform.COASTAL_VALLEY
@export var h_min: float = 0.0
@export var h_max: float = 1.0

@export var heights: PackedFloat32Array = PackedFloat32Array()
@export var biomes: PackedByteArray = PackedByteArray()
@export var slopes: PackedFloat32Array = PackedFloat32Array()
@export var cavities: PackedFloat32Array = PackedFloat32Array()
@export var moisture: PackedFloat32Array = PackedFloat32Array()
@export var coast_prox: PackedFloat32Array = PackedFloat32Array()
@export var rivers: Array = []
@export var lakes: Array = []


func idx(x: int, z: int) -> int:
	return z * grid + x


func is_valid() -> bool:
	var expected := grid * grid
	return grid >= 2 and size > 0.0 and heights.size() == expected and biomes.size() == expected


func refresh_height_range() -> void:
	if heights.is_empty():
		h_min = 0.0
		h_max = 1.0
		return
	var lo := INF
	var hi := -INF
	for h in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	h_min = lo
	h_max = hi


func sample_height(x: float, z: float) -> float:
	if heights.is_empty() or grid < 2 or size <= 0.0:
		return 0.0
	var half := size * 0.5
	var u := clampf((x + half) / size, 0.0, 1.0)
	var v := clampf((z + half) / size, 0.0, 1.0)
	var fx := u * float(grid - 1)
	var fz := v * float(grid - 1)
	var x0 := int(fx)
	var z0 := int(fz)
	var x1 := mini(x0 + 1, grid - 1)
	var z1 := mini(z0 + 1, grid - 1)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := heights[idx(x0, z0)]
	var h10 := heights[idx(x1, z0)]
	var h01 := heights[idx(x0, z1)]
	var h11 := heights[idx(x1, z1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func sample_biome(x: float, z: float) -> int:
	if biomes.is_empty() or grid < 2 or size <= 0.0:
		return MapTypes.Biome.GRASS
	var half := size * 0.5
	var u := clampf((x + half) / size, 0.0, 1.0)
	var v := clampf((z + half) / size, 0.0, 1.0)
	var ix := clampi(int(round(u * float(grid - 1))), 0, grid - 1)
	var iz := clampi(int(round(v * float(grid - 1))), 0, grid - 1)
	return int(biomes[idx(ix, iz)])


func sample_slope(x: float, z: float) -> float:
	if slopes.is_empty() or grid < 2 or size <= 0.0:
		return 0.0
	var half := size * 0.5
	var u := clampf((x + half) / size, 0.0, 1.0)
	var v := clampf((z + half) / size, 0.0, 1.0)
	var ix := clampi(int(round(u * float(grid - 1))), 0, grid - 1)
	var iz := clampi(int(round(v * float(grid - 1))), 0, grid - 1)
	return slopes[idx(ix, iz)]


func sample_water_surface(x: float, z: float) -> float:
	## Open-water surface Y the player can swim on, or -INF if dry / too shallow.
	var h := sample_height(x, z)
	var b := sample_biome(x, z)
	var best := -INF
	if b == MapTypes.Biome.SEA or h < water_y - 0.15:
		# Coastal sea plane covers any bed below the shared waterline
		if b == MapTypes.Biome.SEA or MapHeightfield._sea_proximity(x, z, size, sea_edge) > 0.48 \
				or h < water_y - 0.45:
			if water_y - h > 0.35:
				best = maxf(best, water_y)
	for lake in lakes:
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
	if b == MapTypes.Biome.SEA or b == MapTypes.Biome.LAKE or b == MapTypes.Biome.RIVER:
		return 0.0
	var best := INF
	for river in rivers:
		best = minf(best, MapRivers._dist_to_polyline(p, river as PackedVector2Array))
	for lake in lakes:
		var c: Vector2 = lake["center"]
		var r: float = float(lake.get("radius", 6.0))
		best = minf(best, maxf(0.0, p.distance_to(c) - r * 0.85))
	# Distance toward the coastal sea plane
	var half := size * 0.5
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
	best = minf(best, maxf(0.0, sea_d - size * 0.12))
	return best


func biome_name_at(x: float, z: float) -> String:
	return MapTypes.biome_name(sample_biome(x, z))


func landform_name() -> String:
	return MapTypes.landform_name(landform)
