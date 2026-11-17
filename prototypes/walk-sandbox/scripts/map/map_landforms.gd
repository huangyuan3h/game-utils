extends RefCounted
## Landform archetypes, domain-warped height shaping, and post-pass slope/moisture/cavity fields.
class_name MapLandforms

const MapTypes = preload("res://scripts/map/map_types.gd")
const MapHeightfield = preload("res://scripts/map/map_heightfield.gd")
const MapRivers = preload("res://scripts/map/map_rivers.gd")
const MapLakes = preload("res://scripts/map/map_lakes.gd")


static func build_base_heightfield(
	p_seed: int,
	grid: int,
	size: float,
	base_h: float,
	max_h: float,
	relief: float,
	water_y: float,
	sea_edge: int,
	landform: int
) -> Dictionary:
	## Bake initial terrain relief + effective coastal proximity according to landform archetype.
	var noise_h := MapHeightfield._make_noise(p_seed, 0.012, 5, 0.52)
	var noise_detail := MapHeightfield._make_noise(p_seed + 3, 0.042, 3, 0.45)
	var noise_ridge := MapHeightfield._make_noise(p_seed + 41, 0.009, 4, 0.50)
	var noise_warp_x := MapHeightfield._make_noise(p_seed + 73, 0.014, 3, 0.50)
	var noise_warp_z := MapHeightfield._make_noise(p_seed + 97, 0.014, 3, 0.50)
	var noise_coast := MapHeightfield._make_noise(p_seed + 131, 0.024, 3, 0.52)
	var noise_islet := MapHeightfield._make_noise(p_seed + 179, 0.038, 3, 0.48)

	var heights := PackedFloat32Array()
	heights.resize(grid * grid)
	var coast_prox := PackedFloat32Array()
	coast_prox.resize(grid * grid)

	var h_span := maxf(max_h - base_h, 1.0)
	var warp_amp := 11.0 if landform != MapTypes.Landform.TERRACED_HIGHLANDS else 8.5

	for z in grid:
		for x in grid:
			var wx := (float(x) / float(grid - 1) - 0.5) * size
			var wz := (float(z) / float(grid - 1) - 0.5) * size
			var sea_p := MapHeightfield._sea_proximity(wx, wz, size, sea_edge)
			var inland := 1.0 - sea_p

			# Domain warp coordinates so ridges, valleys, and shores curve organically
			var qx := wx + noise_warp_x.get_noise_2d(wx, wz) * warp_amp
			var qz := wz + noise_warp_z.get_noise_2d(wx + 19.0, wz - 23.0) * warp_amp

			var n1 := noise_h.get_noise_2d(qx, qz)
			var n2 := noise_h.get_noise_2d(qx * 0.48 + 20.0, qz * 0.48 - 11.0)
			var n3 := noise_detail.get_noise_2d(wx, wz)

			# Sharp ridged multifractal component for mountain spines and spurs
			var r_raw := 1.0 - absf(noise_ridge.get_noise_2d(qx * 0.85, qz * 0.85))
			var ridge := pow(clampf(r_raw, 0.0, 1.0), 2.15) * pow(inland, 1.25)
			var lobe := pow(maxf(n2, 0.0), 1.28) * inland

			# Lateral coordinate perpendicular to sea direction (for valleys, fjords, headlands)
			var lat := _lateral_norm(wx, wz, size, sea_edge)
			var coast_wave := noise_coast.get_noise_2d(qx * 0.8, qz * 0.8)

			var h := base_h
			var eff_sea_p := sea_p

			match landform:
				MapTypes.Landform.TERRACED_HIGHLANDS:
					# Broad stepped plateaus & mesa benches with crisp escarpments
					var raw_h := base_h + n1 * 1.9 * relief + lobe * h_span * 0.72 * relief + ridge * h_span * 0.78 * relief + inland * 3.0 * relief
					var terraced := _soft_terrace(raw_h - base_h, 1.85, 0.62) + base_h
					var plateau_mask := smoothstep(0.18, 0.55, inland)
					h = lerpf(raw_h, terraced, plateau_mask * 0.84) + n3 * 0.34 * relief
					eff_sea_p = clampf(sea_p + coast_wave * 0.055, 0.0, 1.0)

				MapTypes.Landform.FJORD_HEADLAND:
					# Carved coastal headlands jutting seaward, sheltered coves, and a central fjord valley
					var valley_cut := exp(-pow((lat + coast_wave * 0.25) / 0.28, 2.0))
					var headland_lobe := cos(lat * PI * 2.5 + coast_wave * 1.4)
					# Keep coves inside sea_p >= 0.66 so sea shader & river mouths always align
					eff_sea_p = clampf(sea_p - headland_lobe * 0.095 * smoothstep(0.45, 0.82, sea_p) + valley_cut * 0.06, 0.0, 1.0)
					var wall := (1.0 - valley_cut * 0.52) * pow(inland, 0.95)
					h += n1 * 2.1 * relief
					h += lobe * h_span * 0.62 * relief
					h += ridge * h_span * 1.08 * relief * wall
					h += n3 * 0.45 * relief
					h += wall * 2.8 * relief

				MapTypes.Landform.ROLLING_ARCHIPELAGO:
					# Gentle rolling coastal hills + offshore islets / sandbars with surf rings
					h += n1 * 1.65 * relief
					h += lobe * h_span * 0.44 * relief
					h += ridge * h_span * 0.62 * relief
					h += n3 * 0.38 * relief
					h += inland * 1.85 * relief
					var islet_n := noise_islet.get_noise_2d(qx * 1.15, qz * 1.15)
					var shallow_band := smoothstep(0.56, 0.68, sea_p) * (1.0 - smoothstep(0.84, 0.94, sea_p))
					var islet_lift := smoothstep(0.12, 0.45, islet_n) * shallow_band
					eff_sea_p = clampf(sea_p + coast_wave * 0.06 - islet_lift * 0.22, 0.0, 1.0)
					if islet_lift > 0.05:
						h = maxf(h, water_y + islet_lift * 2.15 * relief)

				_:
					# COASTAL_VALLEY: sweeping mountain-to-sea watershed with central meadow basin
					var central_dip := exp(-pow((lat + coast_wave * 0.22) / 0.36, 2.0)) * smoothstep(0.15, 0.65, inland)
					h += n1 * 2.0 * relief
					h += lobe * h_span * 0.60 * relief
					h += ridge * h_span * 0.98 * relief * (1.0 - central_dip * 0.35)
					h += n3 * 0.45 * relief
					h += inland * 2.35 * relief
					h -= central_dip * 0.95 * relief
					eff_sea_p = clampf(sea_p + coast_wave * 0.055, 0.0, 1.0)

			# Guarantee outer edge remains open sea for clean horizon & river mouths
			if sea_p > 0.89:
				eff_sea_p = maxf(eff_sea_p, sea_p)

			var land_floor := water_y + 0.24 + smoothstep(0.64, 0.20, eff_sea_p) * 1.45
			h = maxf(h, land_floor)
			h = lerpf(h, water_y - 0.16, smoothstep(0.56, 1.0, eff_sea_p) * 0.92)

			var idx := MapHeightfield._i(grid, x, z)
			heights[idx] = h
			coast_prox[idx] = eff_sea_p

	return {
		"heights": heights,
		"coast_prox": coast_prox,
	}


static func compute_terrain_fields(
	heights: PackedFloat32Array,
	biomes: PackedByteArray,
	grid: int,
	size: float,
	sea_edge: int,
	rivers: Array,
	lakes: Array,
	noise_m: FastNoiseLite
) -> Dictionary:
	## Compute per-cell slope [0..1], cavity [0..1], and moisture [0..1] after smooth/slope-limit.
	var n := grid * grid
	var slopes := PackedFloat32Array()
	slopes.resize(n)
	var cavities := PackedFloat32Array()
	cavities.resize(n)
	var moisture := PackedFloat32Array()
	moisture.resize(n)

	var step := size / float(grid - 1)
	var inv_2step := 1.0 / maxf(2.0 * step, 0.01)

	# Precompute river bounding boxes for fast distance queries
	var river_bounds: Array[Rect2] = []
	for r in rivers:
		var pts: PackedVector2Array = r
		var rmin := Vector2(INF, INF)
		var rmax := Vector2(-INF, -INF)
		for rp in pts:
			rmin = rmin.min(rp)
			rmax = rmax.max(rp)
		river_bounds.append(Rect2(rmin - Vector2(12.0, 12.0), (rmax - rmin) + Vector2(24.0, 24.0)))

	for z in grid:
		var zm := maxi(0, z - 1)
		var zp := mini(grid - 1, z + 1)
		for x in grid:
			var xm := maxi(0, x - 1)
			var xp := mini(grid - 1, x + 1)
			var i := MapHeightfield._i(grid, x, z)
			var hc := heights[i]

			var hx0 := heights[MapHeightfield._i(grid, xm, z)]
			var hx1 := heights[MapHeightfield._i(grid, xp, z)]
			var hz0 := heights[MapHeightfield._i(grid, x, zm)]
			var hz1 := heights[MapHeightfield._i(grid, x, zp)]

			var dhdx := (hx1 - hx0) * inv_2step
			var dhdz := (hz1 - hz0) * inv_2step
			var grad := sqrt(dhdx * dhdx + dhdz * dhdz)
			# Map gradient [0..0.95] -> [0..1] (max_step 0.78/0.84 ~ 0.93)
			var slope_n := clampf(grad / 0.88, 0.0, 1.0)
			slopes[i] = slope_n

			var avg4 := (hx0 + hx1 + hz0 + hz1) * 0.25
			# >0.5 in concave gullies/valleys, <0.5 on exposed ridges/crests
			cavities[i] = clampf((avg4 - hc) * 2.8 + 0.5, 0.0, 1.0)

			var wxz := MapHeightfield._cell_world(x, z, grid, size)
			var base_m := (noise_m.get_noise_2d(wxz.x, wxz.y) + 1.0) * 0.5

			# Boost moisture near rivers and lakes for lush riparian meadows & forests
			var river_d := INF
			for ri in rivers.size():
				if river_bounds[ri].has_point(wxz):
					river_d = minf(river_d, MapRivers._dist_to_polyline(wxz, rivers[ri] as PackedVector2Array))
			var river_wet := 1.0 - smoothstep(1.2, 9.5, river_d)

			var lake_wet := 0.0
			for lk in lakes:
				var c: Vector2 = lk["center"]
				var r: float = float(lk.get("radius", 8.0))
				var ld := wxz.distance_to(c) - r
				lake_wet = maxf(lake_wet, 1.0 - smoothstep(0.0, 7.5, maxf(ld, 0.0)))

			var valley_wet := smoothstep(0.50, 0.80, cavities[i]) * 0.22
			var slope_dry := slope_n * 0.34
			var b := int(biomes[i])
			var m := clampf(base_m * 0.78 + maxf(river_wet * 0.42, lake_wet * 0.36) + valley_wet - slope_dry, 0.0, 1.0)
			if b == MapTypes.Biome.SEA or b == MapTypes.Biome.LAKE or b == MapTypes.Biome.RIVER:
				m = 1.0
			moisture[i] = m

	return {
		"slopes": slopes,
		"cavities": cavities,
		"moisture": moisture,
	}


static func _soft_terrace(val: float, step_h: float, sharpness: float) -> float:
	if val <= 0.0 or step_h <= 0.01:
		return val
	var q := val / step_h
	var f := floorf(q)
	var frac := q - f
	var s := smoothstep(0.5 - (1.0 - sharpness) * 0.45, 0.5 + (1.0 - sharpness) * 0.45, frac)
	return (f + s) * step_h


static func _lateral_norm(wx: float, wz: float, size: float, sea_edge: int) -> float:
	var half := maxf(size * 0.5, 1.0)
	match sea_edge:
		0, 1:
			return clampf(wx / half, -1.0, 1.0)
		_:
			return clampf(wz / half, -1.0, 1.0)
