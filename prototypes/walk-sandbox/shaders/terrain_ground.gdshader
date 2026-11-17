shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Expressive procedural land shader:
// - Vertex COLOR encodes continuous 4-way surface weights: (sand, vegetation, dirt, rock)
// - field_tex encodes per-cell (moisture, slope, cavity, lushness/meadow)
// - Slope-driven rock strata, shoreline wetness, alpine snowline, and world-space micro-normals.

uniform vec2 half_world = vec2(60.0, 60.0);
uniform float water_y = 0.95;
uniform float height_min = 0.0;
uniform float height_span = 10.0;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D field_tex : filter_linear_mipmap, repeat_disable;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_p;
varying vec3 world_n;
varying float v_cam_d;
varying vec4 v_weights;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.7, 29.3);
		a *= 0.5;
	}
	return v;
}

vec2 puddle_ripple_normal(vec2 xz, float time) {
	vec2 n = vec2(0.0);
	for (int l = 0; l < 2; l++) {
		float scale = (l == 0) ? 2.4 : 3.9;
		vec2 p = xz * scale + float(l) * 13.7;
		vec2 cell = floor(p);
		vec2 loc = fract(p) - 0.5;
		float rnd = hash12(cell);
		float phase = fract(time * (1.25 + rnd * 0.45) + rnd);
		vec2 center = (vec2(hash12(cell + 3.1), hash12(cell + 7.9)) - 0.5) * 0.45;
		vec2 d = loc - center;
		float dist = length(d);
		float radius = phase * 0.48;
		float ring_band = exp(-pow((dist - radius) / 0.055, 2.0));
		float wave = sin((dist - radius) * 44.0) * ring_band * (1.0 - phase);
		vec2 dir = (dist > 0.001) ? (d / dist) : vec2(0.0);
		n += dir * wave * 0.28;
	}
	return n;
}

void vertex() {
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_cam_d = length(CAMERA_POSITION_WORLD - world_p);
	v_weights = COLOR;
}

void fragment() {
	vec2 map_uv = clamp((world_p.xz + half_world) / (half_world * 2.0), vec2(0.001), vec2(0.999));
	vec4 field = texture(field_tex, map_uv);
	float moist = field.r;
	float cell_slope = field.g;
	float cavity = field.b;
	float lushness = field.a;

	float h_norm = clamp((world_p.y - height_min) / max(height_span, 0.001), 0.0, 1.0);
	float detail = 1.0 - smoothstep(10.0, 38.0, v_cam_d);
	float mid = 1.0 - smoothstep(22.0, 68.0, v_cam_d);

	// Multi-scale procedural patterns
	float macro_n = fbm3(world_p.xz * 0.075);
	float med_n = fbm3(world_p.xz * 0.38);
	float fine_n = vnoise(world_p.xz * 2.8);
	float micro_n = vnoise(world_p.xz * 9.5);

	// True geometric slope blended with grid slope for crisp escarpments
	float geo_slope = 1.0 - clamp(world_n.y, 0.0, 1.0);
	float slope = max(geo_slope * 1.45, cell_slope);

	// Base weights from vertex COLOR
	float w_sand = v_weights.r;
	float w_veg = v_weights.g;
	float w_dirt = v_weights.b;
	float w_rock = v_weights.a;

	// Automatic slope-driven rock exposure (cliffs & steep banks)
	float auto_rock = smoothstep(0.24, 0.52, slope + (med_n - 0.5) * 0.14);
	w_rock = max(w_rock, auto_rock);
	float non_rock = max(w_sand + w_veg + w_dirt, 0.0001);
	float keep_soft = clamp(1.0 - auto_rock * 0.92, 0.0, 1.0);
	w_sand *= keep_soft;
	w_veg *= keep_soft;
	w_dirt *= keep_soft;
	float w_sum = max(w_sand + w_veg + w_dirt + w_rock, 0.0001);
	w_sand /= w_sum;
	w_veg /= w_sum;
	w_dirt /= w_sum;
	w_rock /= w_sum;

	// --- 1) Sand & gravel ---
	float ripple = sin(world_p.x * 3.6 + world_p.z * 2.1 + med_n * 4.5) * 0.5 + 0.5;
	vec3 dry_sand = mix(vec3(0.76, 0.67, 0.48), vec3(0.66, 0.57, 0.39), med_n * 0.7 + fine_n * 0.3);
	dry_sand = mix(dry_sand, vec3(0.83, 0.75, 0.56), ripple * 0.18 * detail);
	// Subtle pebble / shell speckle
	float pebble = smoothstep(0.78, 0.96, micro_n) * detail;
	dry_sand = mix(dry_sand, vec3(0.50, 0.45, 0.38), pebble * 0.25);

	// --- 2) Vegetation: Grass / Meadow / Forest ---
	vec3 grass_warm = vec3(0.36, 0.50, 0.22);
	vec3 grass_lush = vec3(0.22, 0.44, 0.19);
	vec3 forest_moss = vec3(0.16, 0.31, 0.15);
	vec3 forest_humus = vec3(0.22, 0.25, 0.14);
	vec3 veg_col = mix(grass_warm, grass_lush, clamp(moist * 0.75 + macro_n * 0.35, 0.0, 1.0));
	// Forest canopy shadow & moss tint where lushness < 0.45
	float forest_f = 1.0 - smoothstep(0.15, 0.52, lushness);
	veg_col = mix(veg_col, mix(forest_moss, forest_humus, med_n * 0.65), forest_f * 0.78);
	// Meadow wildflower & clover mottling where lushness > 0.65
	float meadow_f = smoothstep(0.62, 0.92, lushness);
	vec3 meadow_col = mix(vec3(0.29, 0.54, 0.22), vec3(0.42, 0.56, 0.24), med_n);
	float flower_mask = smoothstep(0.80, 0.95, vnoise(world_p.xz * 5.2 + 7.1)) * meadow_f * detail;
	vec3 flower_tint = mix(vec3(0.95, 0.82, 0.28), vec3(0.88, 0.55, 0.72), hash12(floor(world_p.xz * 5.2)));
	veg_col = mix(veg_col, meadow_col, meadow_f * 0.65);
	veg_col = mix(veg_col, flower_tint, flower_mask * 0.55);
	// Fine grass blade contrast
	veg_col *= mix(0.90, 1.10, fine_n * 0.65 + micro_n * 0.35);

	// --- 3) Dirt / Loam / Scree ---
	vec3 dirt_base = mix(vec3(0.44, 0.32, 0.21), vec3(0.31, 0.22, 0.15), med_n * 0.7 + fine_n * 0.3);
	dirt_base = mix(dirt_base, vec3(0.52, 0.44, 0.34), smoothstep(0.68, 0.92, fine_n) * 0.38);

	// --- 4) Stratified Cliff Rock & Alpine Snow ---
	float strata_coord = world_p.y * 2.9 + fbm3(world_p.xz * 0.18) * 2.4;
	float strata = sin(strata_coord * 2.2) * 0.5 + 0.5;
	float strata_fine = sin(strata_coord * 7.5 + med_n * 2.0) * 0.5 + 0.5;
	vec3 rock_dark = vec3(0.28, 0.27, 0.26);
	vec3 rock_warm = vec3(0.47, 0.43, 0.38);
	vec3 rock_slate = vec3(0.38, 0.40, 0.43);
	vec3 rock_col = mix(rock_dark, rock_warm, strata * 0.70 + med_n * 0.30);
	rock_col = mix(rock_col, rock_slate, strata_fine * 0.32);
	rock_col *= mix(0.84, 1.14, fine_n);

	// Alpine snow & frost on high, gentler upward-facing crests
	float flat_top = smoothstep(0.70, 0.89, world_n.y);
	float snow_line = smoothstep(0.64, 0.84, h_norm + (macro_n - 0.5) * 0.16 + (med_n - 0.5) * 0.08);
	float snow_mask = snow_line * flat_top * smoothstep(0.25, 0.75, w_rock + (1.0 - slope) * 0.4);
	vec3 snow_col = mix(vec3(0.84, 0.89, 0.95), vec3(0.95, 0.97, 0.99), fine_n);
	rock_col = mix(rock_col, snow_col, snow_mask * 0.90);

	// Combine surface layers
	vec3 albedo = dry_sand * w_sand + veg_col * w_veg + dirt_base * w_dirt + rock_col * w_rock;

	// Shoreline & riparian wetness (darkens sand/dirt/rock right above water_y or in wet gullies)
	float above_sea = world_p.y - water_y;
	float shore_wet = (1.0 - smoothstep(-0.08, 0.42, above_sea)) * smoothstep(-1.6, -0.05, above_sea);
	float bank_wet = smoothstep(0.68, 0.95, moist) * smoothstep(0.50, 0.78, cavity) * (1.0 - smoothstep(0.35, 0.65, slope));
	float sea_submerged = smoothstep(0.02, -0.45, above_sea);
	float river_bed_mask = smoothstep(0.88, 0.99, moist) * smoothstep(0.58, 0.80, cavity) * (1.0 - w_veg);
	float dry_land = (1.0 - sea_submerged) * (1.0 - river_bed_mask * 0.85);

	// Weather-driven snow blanket across land surfaces
	float weather_snow_slope = smoothstep(0.50, 0.84, world_n.y);
	float weather_snow_bias = (macro_n - 0.5) * 0.22 + (med_n - 0.5) * 0.12 + h_norm * 0.16;
	float weather_snow_thresh = mix(1.25, -0.18, snow_cover);
	float weather_snow = smoothstep(weather_snow_thresh - 0.18, weather_snow_thresh + 0.12, weather_snow_slope + weather_snow_bias)
		* smoothstep(0.02, 0.14, snow_cover) * dry_land;

	// Weather wetness & flat-ground puddles (suppressed by snow)
	float flat_land = smoothstep(0.84, 0.96, world_n.y) * dry_land;
	float puddle_n = fbm3(world_p.xz * 0.34 + vec2(4.2, 9.1));
	float puddle_thresh = mix(0.90, 0.48, wetness);
	float puddle = smoothstep(puddle_thresh, puddle_thresh + 0.14, puddle_n)
		* flat_land * smoothstep(0.18, 0.70, wetness) * (1.0 - weather_snow);

	float weather_wet = wetness * dry_land * (1.0 - weather_snow * 0.85);
	float total_wet = clamp(max(max(shore_wet * 0.92, bank_wet * 0.62), weather_wet), 0.0, 1.0);
	albedo *= mix(1.0, 0.56, total_wet);
	albedo = mix(albedo, albedo * 0.52, puddle * 0.82);

	// Blend seasonal snow surface
	albedo = mix(albedo, snow_col, weather_snow * 0.92);

	// Subtle seabed / riverbed silt tint under shallow translucent water
	albedo = mix(albedo, vec3(0.19, 0.29, 0.27), clamp(sea_submerged * 0.68 + river_bed_mask * 0.42, 0.0, 0.75));

	// Cavity / valley ambient occlusion + ridge warmth
	float ao = mix(0.78, 1.06, 1.0 - smoothstep(0.45, 0.88, cavity));
	albedo *= mix(ao, 1.0, weather_snow * 0.5);

	// --- Micro-normal perturbation in world space -> view space ---
	float eps = 0.16;
	float h_c = vnoise(world_p.xz * 2.8) * 0.55 + vnoise(world_p.xz * 7.5) * 0.25;
	float h_x = vnoise((world_p.xz + vec2(eps, 0.0)) * 2.8) * 0.55 + vnoise((world_p.xz + vec2(eps, 0.0)) * 7.5) * 0.25;
	float h_z = vnoise((world_p.xz + vec2(0.0, eps)) * 2.8) * 0.55 + vnoise((world_p.xz + vec2(0.0, eps)) * 7.5) * 0.25;
	// Add strata ledges to rock normal
	float rock_bump = (strata_fine - 0.5) * 0.28 * w_rock;
	float total_snow = clamp(max(snow_mask, weather_snow), 0.0, 1.0);
	float bump_amp = mix(0.22, 0.55, w_rock + w_dirt * 0.4) * (1.0 - total_snow * 0.65) * (1.0 - puddle * 0.90) * mid;
	vec3 grad_n = vec3((h_c - h_x) / eps, 0.0, (h_c - h_z) / eps) * bump_amp;
	grad_n.y += rock_bump * 0.35 * (1.0 - weather_snow * 0.7);
	if (puddle > 0.05 && rain_intensity > 0.05) {
		vec2 rn = puddle_ripple_normal(world_p.xz, TIME) * puddle * rain_intensity * detail;
		grad_n.x += rn.x;
		grad_n.z += rn.y;
	}
	vec3 perturbed_world_n = normalize(world_n + grad_n);

	ALBEDO = albedo;
	NORMAL = normalize((VIEW_MATRIX * vec4(perturbed_world_n, 0.0)).xyz);

	float snow_sparkle = smoothstep(0.88, 0.99, vnoise(world_p.xz * 14.0)) * total_snow * detail;
	float base_rough = w_sand * 0.88 + w_veg * 0.90 + w_dirt * 0.93 + w_rock * (0.82 - total_snow * 0.22);
	base_rough = mix(base_rough, 0.22, total_wet * 0.85);
	base_rough = mix(base_rough, 0.06, puddle * 0.94);
	base_rough = mix(base_rough, 0.62 - snow_sparkle * 0.24, weather_snow * 0.75);
	ROUGHNESS = clamp(base_rough, 0.05, 0.96);
	SPECULAR = clamp(mix(0.22, 0.62, max(total_wet * 0.85, puddle)) + total_snow * 0.20 + snow_sparkle * 0.25, 0.0, 0.95);
	METALLIC = 0.0;
}
