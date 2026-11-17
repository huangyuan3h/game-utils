class_name SurfaceResolver
extends RefCounted
## Maps biome, water depth, and snow cover to discrete surface audio categories.

const MapTypes = preload("res://scripts/map/map_types.gd")

enum SurfaceType { GRASS, SAND, DIRT, ROCK, SNOW, SHALLOW_WATER }

const WATER_DEPTH_THRESHOLD := 0.08
const SNOW_COVER_THRESHOLD := 0.35


static func surface_name(surface: int) -> String:
	match surface:
		SurfaceType.GRASS:
			return "grass"
		SurfaceType.SAND:
			return "sand"
		SurfaceType.DIRT:
			return "dirt"
		SurfaceType.ROCK:
			return "rock"
		SurfaceType.SNOW:
			return "snow"
		SurfaceType.SHALLOW_WATER:
			return "shallow_water"
		_:
			return "grass"


static func resolve(biome: int, water_depth: float = 0.0, snow_cover: float = 0.0) -> int:
	if water_depth >= WATER_DEPTH_THRESHOLD or biome == MapTypes.Biome.RIVER:
		return SurfaceType.SHALLOW_WATER
	if (biome == MapTypes.Biome.SEA or biome == MapTypes.Biome.LAKE) and water_depth > 0.01:
		return SurfaceType.SHALLOW_WATER
	if snow_cover >= SNOW_COVER_THRESHOLD or biome == MapTypes.Biome.ALPINE:
		return SurfaceType.SNOW

	match biome:
		MapTypes.Biome.SAND:
			return SurfaceType.SAND
		MapTypes.Biome.DIRT:
			return SurfaceType.DIRT
		MapTypes.Biome.MOUNTAIN, MapTypes.Biome.CLIFF:
			return SurfaceType.ROCK
		MapTypes.Biome.GRASS, MapTypes.Biome.MEADOW, MapTypes.Biome.FOREST:
			return SurfaceType.GRASS
		MapTypes.Biome.SEA, MapTypes.Biome.LAKE:
			return SurfaceType.SHALLOW_WATER
		_:
			return SurfaceType.GRASS


static func resolve_at(
	terrain: Object,
	world_pos: Vector3,
	water_depth: float = 0.0,
	snow_cover: float = 0.0
) -> int:
	var biome := MapTypes.Biome.GRASS
	if terrain != null and terrain.has_method("sample_biome"):
		biome = int(terrain.call("sample_biome", world_pos.x, world_pos.z))
	return resolve(biome, water_depth, snow_cover)
