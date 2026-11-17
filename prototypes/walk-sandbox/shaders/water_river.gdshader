shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Creek/river ribbon: Beer-Lambert depth absorption + smooth estuary & spillway blending.
// COLOR.r = along [0..1], COLOR.g = mouth/confluence fade, COLOR.b = lake-spillway head fade, COLOR.a = depth maturity.

uniform vec2 half_world = vec2(60.0, 60.0);
uniform int sea_edge = 0;
uniform float water_y = 0.95;
uniform sampler2D height_tex : filter_linear_mipmap, repeat_disable;
uniform float height_min = 0.0;
uniform float height_span = 10.0;
uniform vec3 shallow_col = vec3(0.24, 0.60, 0.54);
uniform vec3 deep_col = vec3(0.04, 0.21, 0.31);
uniform vec3 sea_shallow_col = vec3(0.28, 0.66, 0.60);
uniform vec3 sea_deep_col = vec3(0.04, 0.23, 0.39);
uniform vec3 lake_shallow_col = vec3(0.28, 0.66, 0.60);
uniform vec3 lake_deep_col = vec3(0.05, 0.25, 0.36);
uniform vec3 foam_col = vec3(0.95, 0.98, 0.97);
uniform float flow_speed : hint_range(0.0, 4.0) = 0.56;
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float wind_strength : hint_range(0.0, 1.5) = 0.14;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.0;

varying vec2 uv_p;
varying vec3 world_p;
varying float v_cam_d;
varying float v_along;
varying float v_over;
varying float v_head;
varying float v_depth_mat;

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
		float scale = (l == 0) ? 2.4 : 4.0;
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
		n += dir * wave * 0.22;
	}
	return n;
}

void vertex() {
	uv_p = UV;
	v_along = COLOR.r;
	v_over = COLOR.g;
	v_head = COLOR.b;
	v_depth_mat = COLOR.a;
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cam_d = length(CAMERA_POSITION_WORLD - world_p);
	float near = 1.0 - smoothstep(6.0, 22.0, v_cam_d);
	float junction = clamp(max(v_over, v_head), 0.0, 1.0);
	VERTEX.y += sin(UV.y * 5.0 - TIME * 1.15 + UV.x * 3.14) * 0.004 * near * (1.0 - junction);
}

void fragment() {
	vec2 ht_uv = (world_p.xz + half_world) / (half_world * 2.0);
	float terr_h = texture(height_tex, clamp(ht_uv, vec2(0.001), vec2(0.999))).r;
	terr_h = terr_h * height_span + height_min;
	float raw_depth = world_p.y - terr_h;

	float across = abs(UV.x - 0.5) * 2.0;
	float detail = 1.0 - smoothstep(8.0, 30.0, v_cam_d);
	float mid = 1.0 - smoothstep(16.0, 44.0, v_cam_d);
	float flow = TIME * flow_speed;

	// Decelerate flowing energy smoothly into calm lake/sea water without phase distortion
	float mouth_calm = 1.0 - smoothstep(0.12, 0.88, v_over);
	float head_calm = 1.0 - smoothstep(0.05, 0.82, v_head);
	float flow_energy = mouth_calm * mix(0.55, 1.0, head_calm);

	float n1 = vnoise(vec2(UV.x * 4.2, UV.y * 2.3 - flow * 0.78));
	float n2 = vnoise(vec2(UV.x * 7.2 + 4.3, UV.y * 4.0 - flow * 1.25));
	float n3 = vnoise(vec2(UV.x * 11.0 + 1.9, UV.y * 6.5 - flow * 1.75));
	float ripple = sin(UV.y * 10.0 - flow * 2.4 + (n1 - 0.5) * 2.4) * 0.5 + 0.5;
	float streak = vnoise(vec2(UV.x * 5.6 + 1.7, UV.y * 4.8 - flow * 1.65));

	// Ambient calm ripples used at estuary/spillway handoff to match lake/sea motion
	vec2 calm_uv = world_p.xz * 0.24 + vec2(TIME * 0.015, -TIME * 0.012);
	float calm_n1 = vnoise(calm_uv);
	float calm_n2 = vnoise(calm_uv * 1.9 + vec2(3.7, 5.1));

	// U-shaped thalweg depth with Beer-Lambert exponential light absorption
	float bank_profile = 1.0 - smoothstep(0.32, 0.96, across);
	float bed_presence = smoothstep(-0.02, 0.08, raw_depth);
	float min_thalweg = mix(0.06, 0.26 * v_depth_mat, bank_profile) * bed_presence;
	float eff_depth = max(max(raw_depth, 0.0), min_thalweg) * mix(0.45, 1.05, bank_profile);
	float absorb = 1.0 - exp(-eff_depth * 3.1);
	vec3 col = mix(shallow_col, deep_col, pow(absorb, 0.80));

	// Deeper center water column attenuation & subtle moving current sheen
	col *= mix(1.0, 0.86, pow(absorb, 1.35) * bank_profile);
	float flow_glint = (ripple * 0.45 + streak * 0.35 + n3 * 0.20) * bank_profile * detail * flow_energy;
	col += vec3(0.055, 0.095, 0.105) * flow_glint;

	// Distinguish lake vs sea surface elevation for exact palette matching at mouths
	float is_lake_elev = smoothstep(water_y + 0.20, water_y + 0.60, world_p.y);
	vec3 target_shallow = mix(sea_shallow_col, lake_shallow_col, is_lake_elev);
	vec3 target_deep = mix(sea_deep_col, lake_deep_col, is_lake_elev);
	float open_depth = max(raw_depth, 0.0);
	float open_dt = clamp(open_depth / 1.35, 0.0, 1.0);
	vec3 target_col = mix(target_shallow, target_deep, pow(open_dt, 0.65));

	float mouth_col_mix = smoothstep(0.12, 0.86, v_over);
	float head_col_mix = smoothstep(0.10, 0.85, v_head);
	col = mix(col, target_col, max(mouth_col_mix, head_col_mix));

	// Bank riffles and delicate current foam that dissolve into estuary wisps
	float edge_foam = smoothstep(0.68, 0.85, across + (n1 - 0.5) * 0.14)
		* (1.0 - smoothstep(0.86, 0.99, across)) * 0.34;
	float current_foam = smoothstep(0.68, 0.93, streak * n2 * 1.40) * bank_profile * 0.28 * detail;
	float estuary_wisp = smoothstep(0.62, 0.90, n2 * n3 * 1.45) * smoothstep(0.10, 0.55, v_over)
		* (1.0 - smoothstep(0.65, 0.98, v_over)) * 0.22 * mid;
	float foam = (clamp(edge_foam + current_foam, 0.0, 1.0) * flow_energy + estuary_wisp)
		* mix(0.45, 1.0, mid);
	col = mix(col, foam_col, foam * 0.52);

	vec2 flow_wn = vec2(
		(n1 - 0.5) * 0.20 + (n3 - 0.5) * 0.10 + (ripple - 0.5) * 0.10,
		(n2 - 0.5) * 0.20 + (n3 - 0.5) * 0.08 - (ripple - 0.5) * 0.10
	) * mix(0.45, 1.0, bank_profile);
	vec2 calm_wn = vec2(calm_n1 - 0.5, calm_n2 - 0.5) * 0.10;
	vec2 wn = mix(calm_wn, flow_wn, flow_energy) * mid;
	if (rain_intensity > 0.04) {
		wn += water_rain_ripples(world_p.xz, TIME) * rain_intensity * detail;
	}
	col = mix(col, col * vec3(0.76, 0.82, 0.88), cloud_darkness * 0.48);
	NORMAL = normalize(vec3(wn.x, 1.0, wn.y));

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	col += vec3(0.06, 0.11, 0.13) * fresnel * 0.34;

	ALBEDO = col;
	ROUGHNESS = mix(0.22, 0.12, detail);
	SPECULAR = mix(0.40, 0.58, detail);
	METALLIC = 0.0;

	float aa = max(fwidth(across), 0.02);
	float bank_alpha = 1.0 - smoothstep(0.66 - aa, 0.99 + aa, across + (n1 - 0.5) * 0.08 * detail);
	float depth_aa = max(fwidth(raw_depth), 0.02);
	float bed_alpha = smoothstep(-depth_aa - 0.03, 0.07 + depth_aa, raw_depth);

	// Long, feather-soft estuary & spillway alpha handoff (no abrupt shoreline cut)
	float mouth_fade = 1.0 - smoothstep(0.32, 0.98, v_over);
	float head_fade = 1.0 - smoothstep(0.08, 0.92, v_head);

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
	float deep_sea_handoff = smoothstep(0.68, 0.78, sea_prox)
		* smoothstep(0.28, 0.68, water_y - terr_h)
		* (1.0 - is_lake_elev);
	mouth_fade *= (1.0 - deep_sea_handoff * 0.88);

	float base_alpha = mix(0.36, 0.91, pow(absorb, 0.80));
	float alpha = base_alpha * bank_alpha * bed_alpha * mouth_fade * head_fade;
	alpha = max(alpha, foam * 0.45 * bank_alpha * bed_alpha * mouth_fade * head_fade);
	if (alpha < 0.012) {
		discard;
	}
	ALPHA = alpha;
}
