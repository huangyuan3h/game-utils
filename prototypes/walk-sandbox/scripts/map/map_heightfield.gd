extends RefCounted
## Grid indexing, coast factors, noise, and heightfield post-passes.
class_name MapHeightfield

const MapTypes = preload("res://scripts/map/map_types.gd")

static func _sea_proximity(wx: float, wz: float, size: float, sea_edge: int) -> float:
	var half := size * 0.5
	match sea_edge:
		0:
			return clampf((wz / half + 1.0) * 0.5, 0.0, 1.0)
		1:
			return clampf((-wz / half + 1.0) * 0.5, 0.0, 1.0)
		2:
			return clampf((wx / half + 1.0) * 0.5, 0.0, 1.0)
		_:
			return clampf((-wx / half + 1.0) * 0.5, 0.0, 1.0)


static func _inland_factor(wx: float, wz: float, size: float, sea_edge: int) -> float:
	return 1.0 - _sea_proximity(wx, wz, size, sea_edge)


static func _cell_world(x: int, z: int, grid: int, size: float) -> Vector2:
	return Vector2(
		(float(x) / float(grid - 1) - 0.5) * size,
		(float(z) / float(grid - 1) - 0.5) * size
	)


static func _make_noise(p_seed: int, freq: float, octaves: int, gain: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	return n


static func _i(grid: int, x: int, z: int) -> int:
	return z * grid + x


static func _smooth(heights: PackedFloat32Array, biomes: PackedByteArray, grid: int, times: int) -> PackedFloat32Array:
	var cur := heights
	for _t in times:
		var next := cur.duplicate()
		for z in range(1, grid - 1):
			for x in range(1, grid - 1):
				var i := _i(grid, x, z)
				var avg := (
					cur[_i(grid, x - 1, z)]
					+ cur[_i(grid, x + 1, z)]
					+ cur[_i(grid, x, z - 1)]
					+ cur[_i(grid, x, z + 1)]
					+ cur[i]
				) / 5.0
				var b := int(biomes[i])
				var blend := 0.55
				if b == MapTypes.Biome.RIVER:
					blend = 0.35
				elif b == MapTypes.Biome.SEA or b == MapTypes.Biome.LAKE:
					blend = 0.4
				next[i] = lerpf(cur[i], avg, blend)
		cur = next
	return cur


static func _limit_slopes(heights: PackedFloat32Array, grid: int, max_step: float, passes: int) -> PackedFloat32Array:
	var cur := heights.duplicate()
	for _p in passes:
		for z in grid:
			for x in grid:
				var i := _i(grid, x, z)
				var h: float = cur[i]
				var dirs: Array[Vector2i] = [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				]
				for d: Vector2i in dirs:
					var nx: int = x + d.x
					var nz: int = z + d.y
					if nx < 0 or nz < 0 or nx >= grid or nz >= grid:
						continue
					var j: int = _i(grid, nx, nz)
					var nh: float = cur[j]
					var diff: float = nh - h
					if diff > max_step:
						cur[j] = h + max_step
					elif diff < -max_step:
						cur[j] = h - max_step
	return cur
