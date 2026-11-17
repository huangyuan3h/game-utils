class_name SurfaceResolver
extends RefCounted
## Maps biome ids/names, water depth, and snow cover to discrete surface audio categories.
## Self-contained inside gu_gameplay with zero dependency on project-specific map scripts.

enum SurfaceType { GRASS, SAND, DIRT, ROCK, SNOW, SHALLOW_WATER }

## Canonical biome indices matching standard terrain generators (0..10).
enum Biome { SEA = 0, LAKE = 1, RIVER = 2, SAND = 3, DIRT = 4, GRASS = 5, MOUNTAIN = 6, MEADOW = 7, FOREST = 8, CLIFF = 9, ALPINE = 10 }

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
	if water_depth >= WATER_DEPTH_THRESHOLD or biome == Biome.RIVER:
		return SurfaceType.SHALLOW_WATER
	if (biome == Biome.SEA or biome == Biome.LAKE) and water_depth > 0.01:
		return SurfaceType.SHALLOW_WATER
	if snow_cover >= SNOW_COVER_THRESHOLD or biome == Biome.ALPINE:
		return SurfaceType.SNOW

	match biome:
		Biome.SAND:
			return SurfaceType.SAND
		Biome.DIRT:
			return SurfaceType.DIRT
		Biome.MOUNTAIN, Biome.CLIFF:
			return SurfaceType.ROCK
		Biome.GRASS, Biome.MEADOW, Biome.FOREST:
			return SurfaceType.GRASS
		Biome.SEA, Biome.LAKE:
			return SurfaceType.SHALLOW_WATER
		_:
			return SurfaceType.GRASS


static func resolve_by_name(biome_name: String, water_depth: float = 0.0, snow_cover: float = 0.0) -> int:
	var key := biome_name.strip_edges().to_lower()
	match key:
		"sea", "ocean":
			return resolve(Biome.SEA, water_depth, snow_cover)
		"lake":
			return resolve(Biome.LAKE, water_depth, snow_cover)
		"river", "stream", "creek":
			return resolve(Biome.RIVER, water_depth, snow_cover)
		"sand", "beach", "desert":
			return resolve(Biome.SAND, water_depth, snow_cover)
		"dirt", "mud", "soil":
			return resolve(Biome.DIRT, water_depth, snow_cover)
		"mountain", "cliff", "rock", "stone":
			return resolve(Biome.CLIFF, water_depth, snow_cover)
		"alpine", "snow", "tundra", "ice":
			return resolve(Biome.ALPINE, water_depth, snow_cover)
		"meadow", "forest", "grass", "plains":
			return resolve(Biome.GRASS, water_depth, snow_cover)
		_:
			return resolve(Biome.GRASS, water_depth, snow_cover)


static func resolve_at(
	terrain: Object,
	world_pos: Vector3,
	water_depth: float = 0.0,
	snow_cover: float = 0.0
) -> int:
	if terrain != null and terrain.has_method("sample_biome"):
		return resolve(int(terrain.call("sample_biome", world_pos.x, world_pos.z)), water_depth, snow_cover)
	if terrain != null and terrain.has_method("biome_name_at"):
		return resolve_by_name(str(terrain.call("biome_name_at", world_pos.x, world_pos.z)), water_depth, snow_cover)
	return resolve(Biome.GRASS, water_depth, snow_cover)
