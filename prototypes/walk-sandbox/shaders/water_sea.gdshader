shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
// Coastal sea: depth tint + calm shore foam + slow swell + river estuary plume blending.

uniform vec2 half_world = vec2(60.0, 60.0);
uniform int sea_edge = 0;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_disable;
uniform float water_y = 0.95;
uniform float height_min = 0.0;
uniform float height_span = 10.0;
uniform vec3 shallow_col = vec3(0.28, 0.66, 0.60);
uniform vec3 deep_col = vec3(0.04, 0.23, 0.39);
uniform vec3 river_shallow_col = vec3(0.24, 0.60, 0.54);
uniform vec3 river_deep_col = vec3(0.04, 0.21, 0.31);
uniform vec3 foam_col = vec3(0.95, 0.98, 0.97);

uniform int mouth_count = 0;
uniform vec4 mouth_pos_dir[8];
uniform vec4 mouth_info[8];

uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float wind_strength : hint_range(0.0, 1.5) = 0.14;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_p;
varying float v_cam_d;

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

vec2 water_rain_ripples(vec2 xz, float time) {
	vec2 n = vec2(0.0);
	for (int l = 0; l < 2; l++) {
		float scale = (l == 0) ? 1.85 : 3.2;
		vec2 p = xz * scale + float(l) * 19.3;
		vec2 cell = floor(p);
		vec2 loc = fract(p) - 0.5;
		float rnd = hash12(cell);
		float phase = fract(time * (1.35 + rnd * 0.45) + rnd);
		vec2 center = (vec2(hash12(cell + 2.3), hash12(cell + 8.7)) - 0.5) * 0.48;
		vec2 d = loc - center;
		float dist = length(d);
		float radius = phase * 0.48;
		float ring_band = exp(-pow((dist - radius) / 0.055, 2.0));
		float wave = sin((dist - radius) * 42.0) * ring_band * (1.0 - phase);
		vec2 dir = (dist > 0.001) ? (d / dist) : vec2(0.0);
		n += dir * wave * 0.24;
	}
	return n;
}

void vertex() {
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cam_d = length(CAMERA_POSITION_WORLD - world_p);
	vec2 ht_uv = (world_p.xz + half_world) / (half_world * 2.0);
	float terr_h = texture(height_tex, clamp(ht_uv, vec2(0.001), vec2(0.999))).r;
	terr_h = terr_h * height_span + height_min;
	float depth = water_y - terr_h;
	float shore_fade = smoothstep(0.20, 1.15, depth);
	float near = 1.0 - smoothstep(10.0, 36.0, v_cam_d);
	float wave_spd = mix(1.0, 2.2, clamp(wind_strength, 0.0, 1.0));
	float wave_amp = mix(0.050, 0.145, clamp(wind_strength, 0.0, 1.0));
	float w1 = sin(world_p.x * 0.14 + TIME * 0.18 * wave_spd) * 0.65
		+ sin(world_p.z * 0.17 - TIME * 0.15 * wave_spd) * 0.50
		+ sin((world_p.x + world_p.z) * 0.09 + TIME * 0.10 * wave_spd) * 0.35;

	// Keep the immediate estuary opening level with water_y so river & sea meet seamlessly
	float mouth_calm = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= mouth_count) {
			break;
		}
		vec4 pd = mouth_pos_dir[i];
		vec4 mi = mouth_info[i];
		float d = length(world_p.xz - pd.xy);
		mouth_calm = max(mouth_calm, 1.0 - smoothstep(mi.x * 0.8, mi.x * 2.6, d));
	}

	VERTEX.y += w1 * wave_amp * shore_fade * mix(0.5, 1.0, near) * (1.0 - mouth_calm * 0.65);
	VERTEX.y -= 0.025 * (1.0 - shore_fade) * (1.0 - mouth_calm);
}

void fragment() {
	vec2 ht_uv = (world_p.xz + half_world) / (half_world * 2.0);
	float terr_h = texture(height_tex, clamp(ht_uv, vec2(0.001), vec2(0.999))).r;
	terr_h = terr_h * height_span + height_min;
	float depth = water_y - terr_h;

	float detail = 1.0 - smoothstep(9.0, 34.0, v_cam_d);
	float mid = 1.0 - smoothstep(18.0, 52.0, v_cam_d);
	float wt = TIME * 0.40;

	vec2 uv1 = world_p.xz * mix(0.22, 0.40, detail) + vec2(wt * 0.06, wt * 0.04);
	vec2 uv2 = world_p.xz * mix(0.40, 0.75, detail) - vec2(wt * 0.045, wt * 0.08);
	vec2 wn = (vec2(vnoise(uv1), vnoise(vec2(uv1.y, uv1.x) + 5.0)) - 0.5) * 0.28 * mid
		+ (vec2(vnoise(uv2), vnoise(vec2(uv2.y, uv2.x) + 9.0)) - 0.5) * 0.16 * detail;

	// River-into-sea estuary plume & coastal surf clearing
	float mouth_notch = 0.0;
	float estuary_plume = 0.0;
	float plume_foam = 0.0;
	vec2 plume_wn = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= mouth_count) {
			break;
		}
		vec4 pd = mouth_pos_dir[i];
		vec4 mi = mouth_info[i];
		float half_w = max(mi.x, 0.6);
		float plume_len = max(mi.y, 2.0);
		float strength = mi.w;

		vec2 rel = world_p.xz - pd.xy;
		vec2 fwd = normalize(pd.zw);
		vec2 perp = vec2(-fwd.y, fwd.x);
		float axial = dot(rel, fwd);
		float lat = abs(dot(rel, perp));
		if (axial < -2.8 || axial > plume_len || lat > half_w * 3.2) {
			continue;
		}

		float fan_t = clamp(max(axial, 0.0) / plume_len, 0.0, 1.0);
		float local_hw = half_w * mix(1.10, 2.85, pow(fan_t, 0.85));

		// Suppress the beach surf line inside the river mouth channel
		float n_ax = smoothstep(-2.6, -0.35, axial) * (1.0 - smoothstep(0.8, 3.4, axial));
		float n_lat = 1.0 - smoothstep(half_w * 0.65, half_w * 1.85, lat);
		mouth_notch = max(mouth_notch, n_ax * n_lat * strength);

		float p_ax = smoothstep(-1.5, 0.5, axial) * (1.0 - smoothstep(plume_len * 0.15, plume_len, axial));
		float p_lat = 1.0 - smoothstep(local_hw * 0.28, local_hw * 1.20, lat);
		float p_mask = p_ax * p_lat * strength;
		estuary_plume = max(estuary_plume, p_mask);

		float pn = vnoise(vec2(dot(rel, perp) * 1.25, axial * 1.0 - TIME * 0.70));
		float pw = sin(axial * 4.2 - TIME * 1.85 + (pn - 0.5) * 2.2) * 0.5 + 0.5;
		float motion_decay = (1.0 - fan_t * 0.80);

		plume_wn += (fwd * (pw - 0.5) * 0.22 + perp * (pn - 0.5) * 0.14) * p_mask * motion_decay;

		// Mixing-front foam wisps where freshwater fans into coastal surf
		float edge_wisp = smoothstep(local_hw * 0.45, local_hw * 0.88, lat)
			* (1.0 - smoothstep(local_hw * 0.88, local_hw * 1.20, lat));
		float jet_wisp = smoothstep(0.60, 0.90, pn * pw * 1.40) * (1.0 - fan_t * 0.85);
		float mix_front = smoothstep(0.15, 0.45, fan_t) * (1.0 - smoothstep(0.55, 0.98, fan_t));
		plume_foam = max(plume_foam, (edge_wisp * 0.24 + jet_wisp * 0.42 + mix_front * pn * 0.22) * p_mask);
	}

	wn += plume_wn * mid;
	if (rain_intensity > 0.04) {
		wn += water_rain_ripples(world_p.xz, TIME) * rain_intensity * detail;
	}
	wn *= mix(1.0, 1.35, clamp(wind_strength, 0.0, 1.0));
	NORMAL = normalize(vec3(wn.x, 1.0, wn.y));

	float depth_t = clamp(depth / 1.4, 0.0, 1.0);
	vec3 col = mix(shallow_col, deep_col, pow(depth_t, 0.65));
	col = mix(col * 0.9 + vec3(0.10, 0.09, 0.05), col, smoothstep(0.0, 0.35, depth_t));

	// Freshwater plume tint fading smoothly into deep sea blue
	vec3 fresh_col = mix(river_shallow_col, river_deep_col, pow(depth_t, 0.72));
	col = mix(col, fresh_col, estuary_plume * 0.62);
	col = mix(col, col * vec3(0.72, 0.78, 0.86), cloud_darkness * 0.55);

	float crest = sin(world_p.x * 0.28 + world_p.z * 0.20 - TIME * 0.45 * mix(1.0, 1.9, clamp(wind_strength, 0.0, 1.0))
		+ vnoise(world_p.xz * 0.22) * 1.2) * 0.5 + 0.5;
	float shallow = 1.0 - smoothstep(0.0, 0.55, depth_t);
	float storm_cap = pow(crest, 3.2) * smoothstep(0.45, 1.0, wind_strength) * 0.22 * mid;
	col += vec3(0.18, 0.22, 0.24) * pow(crest, 2.8) * shallow * 0.22 * mid;
	col = mix(col, foam_col * 0.85, storm_cap);

	float foam_n = vnoise(world_p.xz * mix(1.4, 2.6, detail) + vec2(wt * 0.14, -wt * 0.12));
	float lap = sin(TIME * 0.55 + vnoise(world_p.xz * 0.70) * 6.28) * 0.16;
	float foam_band = 1.0 - smoothstep(0.02, 0.30, depth + (foam_n - 0.5) * 0.22 + lap);
	foam_band *= 1.0 - smoothstep(0.35, 1.2, depth);
	float foam2 = 1.0 - smoothstep(0.0, 0.08, abs(depth - 0.22 - lap * 0.40 - (foam_n - 0.5) * 0.14));
	foam2 *= 1.0 - smoothstep(0.4, 1.0, depth);
	float shore_suppression = 1.0 - mouth_notch * 0.90;
	float foam_amt = clamp((foam2 * 0.18 + foam_band * 0.48) * shore_suppression + plume_foam * 0.50, 0.0, 1.0)
		* mix(0.65, 1.0, mid);
	col = mix(col, foam_col, foam_amt);

	ALBEDO = col;
	ROUGHNESS = mix(0.26, 0.17, detail);
	SPECULAR = mix(0.32, 0.45, detail);
	METALLIC = 0.0;

	// Only render the sea plane in the coastal band; never flood inland valleys.
	float sea_prox = 0.0;
	if (sea_edge == 0) {
		sea_prox = clamp((world_p.z / half_world.y + 1.0) * 0.5, 0.0, 1.0);
	} else if (sea_edge == 1) {
		sea_prox = clamp((-world_p.z / half_world.y + 1.0) * 0.5, 0.0, 1.0);
	} else if (sea_edge == 2) {
		sea_prox = clamp((world_p.x / half_world.x + 1.0) * 0.5, 0.0, 1.0);
	} else {
		sea_prox = clamp((-world_p.x / half_world.x + 1.0) * 0.5, 0.0, 1.0);
	}
	float coast_mask = smoothstep(0.45, 0.58, sea_prox);
	float shore_aa = max(fwidth(depth), 0.02);
	float shore_alpha = smoothstep(-shore_aa, 0.08 + shore_aa, depth) * coast_mask;
	if (shore_alpha < 0.02) {
		discard;
	}
	ALPHA = mix(0.70, 0.90, smoothstep(0.0, 0.9, depth_t)) * shore_alpha;
	ALPHA = max(ALPHA, foam_amt * 0.85 * shore_alpha);
}
