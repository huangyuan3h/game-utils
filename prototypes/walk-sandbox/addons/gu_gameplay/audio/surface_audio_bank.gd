class_name SurfaceAudioBank
extends Resource
## Footstep AudioStream bank organized by SurfaceType with automatic default fallback.

@export var grass_walk: Array[AudioStream] = []
@export var grass_run: Array[AudioStream] = []
@export var sand_walk: Array[AudioStream] = []
@export var sand_run: Array[AudioStream] = []
@export var dirt_walk: Array[AudioStream] = []
@export var dirt_run: Array[AudioStream] = []
@export var rock_walk: Array[AudioStream] = []
@export var rock_run: Array[AudioStream] = []
@export var snow_walk: Array[AudioStream] = []
@export var snow_run: Array[AudioStream] = []
@export var water_walk: Array[AudioStream] = []
@export var water_run: Array[AudioStream] = []

@export var fallback_walk: Array[AudioStream] = []
@export var fallback_run: Array[AudioStream] = []


func load_default_fallbacks(
	walk_pattern: String = "res://assets/sfx/foot_walk_%d.wav",
	run_pattern: String = "res://assets/sfx/foot_run_%d.wav",
	count: int = 4
) -> void:
	fallback_walk.clear()
	fallback_run.clear()
	for i in count:
		var wpath := walk_pattern % i
		var rpath := run_pattern % i
		if ResourceLoader.exists(wpath):
			var ws := load(wpath) as AudioStream
			if ws != null:
				fallback_walk.append(ws)
		if ResourceLoader.exists(rpath):
			var rs := load(rpath) as AudioStream
			if rs != null:
				fallback_run.append(rs)


func get_streams(surface: int, running: bool) -> Array[AudioStream]:
	var primary := _surface_pool(surface, running)
	if not primary.is_empty():
		return primary
	if running:
		var walk_for_surface := _surface_pool(surface, false)
		if not walk_for_surface.is_empty():
			return walk_for_surface
		if not fallback_run.is_empty():
			return fallback_run
	return fallback_walk


func get_stream(surface: int, running: bool, rng: RandomNumberGenerator = null) -> AudioStream:
	var pool := get_streams(surface, running)
	if pool.is_empty():
		return null
	if pool.size() == 1 or rng == null:
		return pool[0]
	return pool[rng.randi_range(0, pool.size() - 1)]


func _surface_pool(surface: int, running: bool) -> Array[AudioStream]:
	match surface:
		SurfaceResolver.SurfaceType.GRASS:
			return grass_run if running else grass_walk
		SurfaceResolver.SurfaceType.SAND:
			return sand_run if running else sand_walk
		SurfaceResolver.SurfaceType.DIRT:
			return dirt_run if running else dirt_walk
		SurfaceResolver.SurfaceType.ROCK:
			return rock_run if running else rock_walk
		SurfaceResolver.SurfaceType.SNOW:
			return snow_run if running else snow_walk
		SurfaceResolver.SurfaceType.SHALLOW_WATER:
			return water_run if running else water_walk
		_:
			return fallback_run if running else fallback_walk
