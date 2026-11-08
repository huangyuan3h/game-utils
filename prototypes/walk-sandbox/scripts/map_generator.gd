class_name MapGenerator
extends RefCounted
## Abstract random map generator for the walk sandbox.
## Produces heightfield + biome grids. All cells stay walkable via height-follow.

enum Biome { RIVER, SAND, DIRT, GRASS, MOUNTAIN }

const DEFAULT_SIZE := 120.0
const DEFAULT_GRID := 96
const DEFAULT_BASE := 1.0
const DEFAULT_MAX_H := 9.5
## Neighbor step cap (world meters). Height-follow allows steeper visuals than physics climb.
const DEFAULT_MAX_STEP := 1.15


static func generate_random(p_seed: int = -1, opts: Dictionary = {}) -> Dictionary:
	## Public entry: random (or given) seed → map data.
	var s: int = p_seed if p_seed >= 0 else int(Time.get_ticks_usec()) ^ randi()
	return generate(s, opts)


static func generate(p_seed: int, opts: Dictionary = {}) -> Dictionary:
	var size: float = float(opts.get("size", DEFAULT_SIZE))
	var grid: int = int(opts.get("grid", DEFAULT_GRID))
	var base_h: float = float(opts.get("base_height", DEFAULT_BASE))
	var max_h: float = float(opts.get("max_height", DEFAULT_MAX_H))
	var max_step: float = float(opts.get("max_step", DEFAULT_MAX_STEP))
	var relief: float = float(opts.get("relief", 1.0))  # 1 = default, >1 more dramatic

	var noise_h := _make_noise(p_seed, 0.011, 5, 0.5)
	var noise_detail := _make_noise(p_seed + 3, 0.035, 3, 0.45)
	var noise_m := _make_noise(p_seed + 17, 0.02, 3, 0.5)
	var noise_r := _make_noise(p_seed + 91, 0.009, 2, 0.5)

	var heights := PackedFloat32Array()
	heights.resize(grid * grid)
	var biomes := PackedByteArray()
	biomes.resize(grid * grid)
	biomes.fill(Biome.GRASS)

	# 1) Height bake — broad hills + medium ridges + fine detail
	for z in grid:
		for x in grid:
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			var n1 := noise_h.get_noise_2d(wx, wz)
			var n2 := noise_h.get_noise_2d(wx * 0.4 + 20.0, wz * 0.4 - 11.0)
			var n3 := noise_detail.get_noise_2d(wx, wz)
			# Soft highland lobes
			var lobe := maxf(n2, 0.0)
			lobe = pow(lobe, 1.35)
			var h := base_h
			h += n1 * 2.4 * relief
			h += lobe * (max_h - base_h) * 0.9 * relief
			h += n3 * 0.55 * relief
			# Keep map edges slightly lower so the playable bowl reads clearly
			var edge := maxf(absf(wx), absf(wz)) / (size * 0.5)
			h *= lerpf(1.0, 0.88, smoothstep(0.82, 1.0, edge))
			heights[_i(grid, x, z)] = h

	# 2) Meandering shallow rivers (domain-warped ridges → continuous channels)
	var noise_warp := _make_noise(p_seed + 211, 0.0065, 3, 0.5)
	for z in grid:
		for x in grid:
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			# Warp sample domain so channels bend instead of forming blotchy blobs
			var wxw := wx + noise_warp.get_noise_2d(wx, wz) * 14.0
			var wzw := wz + noise_warp.get_noise_2d(wx + 40.0, wz - 18.0) * 14.0
			var ridge := absf(noise_r.get_noise_2d(wxw, wzw))
			# Soft secondary thread for forks / braids
			var ridge2 := absf(noise_r.get_noise_2d(wxw * 0.72 + 55.0, wzw * 0.72 - 33.0))
			ridge = minf(ridge, ridge2 * 1.15 + 0.01)
			var i := _i(grid, x, z)
			if ridge < 0.078:
				var deepen := (0.078 - ridge) / 0.078
				deepen = deepen * deepen # rounder channel bed
				heights[i] -= (0.28 + deepen * 0.48) * relief
				biomes[i] = Biome.RIVER
			elif ridge < 0.118:
				# Soft banks — still slightly carved for a V-shaped valley
				var bank := (0.118 - ridge) / 0.04
				heights[i] -= (0.06 + bank * 0.14) * relief

	# 3) Smooth then slope-limit (still walkable, but keeps relief)
	heights = _smooth(heights, biomes, grid, 2)
	heights = _limit_slopes(heights, grid, max_step, 5)

	# 4) Biomes from height + moisture (preserve rivers)
	var h_min := INF
	var h_max := -INF
	for i in heights.size():
		h_min = minf(h_min, heights[i])
		h_max = maxf(h_max, heights[i])
	var h_span := maxf(h_max - h_min, 0.001)

	for z in grid:
		for x in grid:
			var i := _i(grid, x, z)
			if int(biomes[i]) == Biome.RIVER:
				continue
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			var h := heights[i]
			var t := (h - h_min) / h_span
			var moist := (noise_m.get_noise_2d(wx, wz) + 1.0) * 0.5
			var b: int = Biome.GRASS
			if t > 0.72:
				b = Biome.MOUNTAIN
			elif t < 0.22 and moist < 0.48:
				b = Biome.SAND
			elif moist < 0.30 or (t > 0.55 and moist < 0.48):
				b = Biome.DIRT
			else:
				b = Biome.GRASS
			biomes[i] = b

	return {
		"seed": p_seed,
		"size": size,
		"grid": grid,
		"base_height": base_h,
		"max_height": max_h,
		"heights": heights,
		"biomes": biomes,
		"h_min": h_min,
		"h_max": h_max,
	}


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
				var blend := 0.4 if int(biomes[i]) == Biome.RIVER else 0.55
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
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
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
