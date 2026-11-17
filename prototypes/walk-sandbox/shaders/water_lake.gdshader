shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
// Inland lake: terrain height_tex depth tint + contour shore foam + river inlet/spillway plumes.

uniform vec2 half_world = vec2(60.0, 60.0);
uniform sampler2D height_tex : filter_linear_mipmap, repeat_disable;
uniform float height_grid = 144.0;
uniform float height_min = 0.0;
uniform float height_span = 10.0;
uniform vec3 shallow_col = vec3(0.28, 0.66, 0.60);
uniform vec3 deep_col = vec3(0.05, 0.25, 0.36);
uniform vec3 river_shallow_col = vec3(0.24, 0.60, 0.54);
uniform vec3 river_deep_col = vec3(0.04, 0.21, 0.31);
uniform vec3 foam_col = vec3(0.95, 0.98, 0.97);

uniform int mouth_count = 0;
uniform vec4 mouth_pos_dir[8];
uniform vec4 mouth_info[8];

uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float wind_strength : hint_range(0.0, 1.5) = 0.14;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;

varying float v_radial;
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
		float scale = (l == 0) ? 2.1 : 3.6;
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
	v_radial = UV.x;
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cam_d = length(CAMERA_POSITION_WORLD - world_p);
	float calm = 1.0 - smoothstep(0.45, 0.95, v_radial);
	float near = 1.0 - smoothstep(8.0, 30.0, v_cam_d);
	float wave_spd = mix(1.0, 2.0, clamp(wind_strength, 0.0, 1.0));
	float wave_amp = mix(0.018, 0.048, clamp(wind_strength, 0.0, 1.0));
	float swell = sin(world_p.x * 0.22 + TIME * 0.18 * wave_spd) * 0.55
		+ sin(world_p.z * 0.18 - TIME * 0.14 * wave_spd) * 0.45;
	VERTEX.y += swell * wave_amp * calm * mix(0.45, 1.0, near);
}

void fragment() {
	vec2 ht_uv = ((world_p.xz + half_world) / (half_world * 2.0) * (height_grid - 1.0) + 0.5) / height_grid;
	float terr_h = texture(height_tex, clamp(ht_uv, vec2(0.001), vec2(0.999))).r;
	terr_h = terr_h * height_span + height_min;
	float depth = world_p.y - terr_h;

	float r = clamp(v_radial, 0.0, 1.0);
	float detail = 1.0 - smoothstep(8.0, 32.0, v_cam_d);
	float mid = 1.0 - smoothstep(16.0, 48.0, v_cam_d);
	float wt = TIME * 0.16;

	vec2 uv_lo = world_p.xz * 0.14 + vec2(wt * 0.012, -wt * 0.010);
	vec2 uv_hi = world_p.xz * 0.34 + vec2(wt * 0.018, -wt * 0.014);
	float n = mix(vnoise(uv_lo), vnoise(uv_hi), detail);
	vec2 wn = (vec2(vnoise(uv_lo), vnoise(uv_lo + 3.7)) - 0.5) * 0.08 * mid
		+ (vec2(vnoise(uv_hi), vnoise(uv_hi + 5.1)) - 0.5) * 0.06 * detail;

	// Accumulate river inflow plumes & lake-spillway draw-out currents
	float mouth_notch = 0.0;
	float inflow_plume = 0.0;
	float plume_foam = 0.0;
	vec2 plume_wn = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= mouth_count) {
			break;
		}
		vec4 pd = mouth_pos_dir[i];
		vec4 mi = mouth_info[i];
		float half_w = max(mi.x, 0.4);
		float plume_len = max(mi.y, 1.0);
		float mode = mi.z; // +1 = river inflow, -1 = lake spillway outlet
		float strength = mi.w;

		vec2 rel = world_p.xz - pd.xy;
		vec2 fwd = normalize(pd.zw);
		vec2 perp = vec2(-fwd.y, fwd.x);
		float axial = (mode >= 0.0) ? dot(rel, fwd) : dot(rel, -fwd);
		float lat = abs(dot(rel, perp));
		if (axial < -2.6 || axial > plume_len || lat > half_w * 3.0) {
			continue;
		}

		float fan_t = clamp(max(axial, 0.0) / plume_len, 0.0, 1.0);
		float local_hw = half_w * mix(1.08, mode >= 0.0 ? 2.55 : 2.15, pow(fan_t, 0.85));

		// Clear shoreline foam right across river inlets and spillway outlets
		float n_ax = smoothstep(-2.4, -0.35, axial) * (1.0 - smoothstep(0.6, 2.8, axial));
		float n_lat = 1.0 - smoothstep(half_w * 0.65, half_w * 1.75, lat);
		mouth_notch = max(mouth_notch, n_ax * n_lat * strength);

		float p_ax = smoothstep(-1.4, 0.45, axial) * (1.0 - smoothstep(plume_len * 0.16, plume_len, axial));
		float p_lat = 1.0 - smoothstep(local_hw * 0.30, local_hw * 1.18, lat);
		float p_mask = p_ax * p_lat * strength;

		float phase_dir = (mode >= 0.0) ? (axial * 4.4 - TIME * 1.85) : (axial * 4.0 + TIME * 1.55);
		float pn = vnoise(vec2(dot(rel, perp) * 1.35, axial * 1.05 + (mode >= 0.0 ? -TIME * 0.65 : TIME * 0.55)));
		float pw = sin(phase_dir + (pn - 0.5) * 2.2) * 0.5 + 0.5;
		float motion_decay = (1.0 - fan_t * 0.78);

		vec2 flow_dir = (mode >= 0.0) ? fwd : -fwd;
		plume_wn += (flow_dir * (pw - 0.5) * 0.18 + perp * (pn - 0.5) * 0.12) * p_mask * motion_decay;

		if (mode >= 0.0) {
			inflow_plume = max(inflow_plume, p_mask);
			float edge_wisp = smoothstep(local_hw * 0.42, local_hw * 0.85, lat)
				* (1.0 - smoothstep(local_hw * 0.85, local_hw * 1.18, lat));
			float jet_wisp = smoothstep(0.62, 0.92, pn * pw * 1.38) * (1.0 - fan_t);
			plume_foam = max(plume_foam, (edge_wisp * 0.22 + jet_wisp * 0.42) * p_mask);
		} else {
			// Gentle accelerating ripples approaching the outlet weir
			float out_wisp = smoothstep(0.68, 0.94, pn * pw * 1.30) * (1.0 - fan_t) * 0.22;
			plume_foam = max(plume_foam, out_wisp * p_mask);
		}
	}

	wn += plume_wn * mid;
	if (rain_intensity > 0.04) {
		wn += water_rain_ripples(world_p.xz, TIME) * rain_intensity * detail;
	}
	wn *= mix(1.0, 1.45, clamp(wind_strength, 0.0, 1.0));
	NORMAL = normalize(vec3(wn.x, 1.0, wn.y));

	float depth_t = clamp(depth / 1.35, 0.0, 1.0);
	vec3 col = mix(shallow_col, deep_col, pow(depth_t, 0.65));
	vec3 river_tint = mix(river_shallow_col, river_deep_col, pow(depth_t, 0.72));
	col = mix(col, river_tint, inflow_plume * 0.58);
	col = mix(col, col * vec3(0.95, 0.99, 1.0), n * 0.05 * mid);
	col = mix(col, col * vec3(0.74, 0.80, 0.88), cloud_darkness * 0.52);

	float foam_n = vnoise(world_p.xz * mix(1.2, 2.2, detail) + vec2(wt * 0.08, -wt * 0.05));
	float lap = sin(TIME * 0.45 + vnoise(world_p.xz * 0.6) * 6.28) * 0.035;
	float wet_band = smoothstep(0.0, 0.06, depth);
	float shore_foam = (1.0 - smoothstep(0.02, 0.16, depth + (foam_n - 0.5) * 0.08 + lap))
		* (1.0 - smoothstep(0.20, 0.55, depth)) * wet_band;
	shore_foam *= (1.0 - mouth_notch * 0.92);
	float total_foam = clamp(shore_foam * 0.34 + plume_foam * 0.48, 0.0, 1.0) * mix(0.55, 1.0, mid);
	col = mix(col, foam_col, total_foam);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.8);
	col += vec3(0.05, 0.09, 0.11) * fresnel * 0.25;

	ALBEDO = col;
	ROUGHNESS = mix(0.24, 0.15, detail);
	SPECULAR = mix(0.32, 0.45, detail);
	METALLIC = 0.0;

	float shore_aa = max(fwidth(depth), 0.02);
	float shore_alpha = smoothstep(-shore_aa * 0.5, 0.14 + shore_aa, depth);
	float rim_guard = 1.0 - smoothstep(0.92, 1.0, r);
	float alpha = mix(0.20, 0.88, pow(smoothstep(0.0, 0.85, depth_t), 0.85)) * shore_alpha * rim_guard;
	alpha = max(alpha, total_foam * 0.48 * shore_alpha * rim_guard);
	if (alpha < 0.015) {
		discard;
	}
	ALPHA = alpha;
}
