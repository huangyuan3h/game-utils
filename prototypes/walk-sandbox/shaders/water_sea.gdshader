shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Coastal sea: depth tint + calm shore foam + slow swell.
// Camera-distance LOD keeps far water calm (no shimmer pop when walking closer).

uniform vec2 half_world = vec2(60.0, 60.0);
uniform sampler2D height_tex : filter_linear_mipmap, repeat_disable;
uniform float water_y = 0.95;
uniform float height_min = 0.0;
uniform float height_span = 10.0;
uniform vec3 shallow_col = vec3(0.30, 0.70, 0.65);
uniform vec3 deep_col = vec3(0.030, 0.235, 0.425);
uniform vec3 foam_col = vec3(0.97, 0.99, 0.97);

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

void vertex() {
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cam_d = length(CAMERA_POSITION_WORLD - world_p);
	vec2 ht_uv = (world_p.xz + half_world) / (half_world * 2.0);
	float terr_h = texture(height_tex, clamp(ht_uv, vec2(0.001), vec2(0.999))).r;
	terr_h = terr_h * height_span + height_min;
	float depth = water_y - terr_h;
	float shore_fade = smoothstep(0.20, 1.15, depth);
	float near = 1.0 - smoothstep(10.0, 36.0, v_cam_d);
	float w1 = sin(world_p.x * 0.14 + TIME * 0.18) * 0.65
		+ sin(world_p.z * 0.17 - TIME * 0.15) * 0.50
		+ sin((world_p.x + world_p.z) * 0.09 + TIME * 0.10) * 0.35;
	VERTEX.y += w1 * 0.055 * shore_fade * mix(0.5, 1.0, near);
	VERTEX.y -= 0.025 * (1.0 - shore_fade);
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
	NORMAL = normalize(vec3(wn.x, 1.0, wn.y));

	float depth_t = clamp(depth / 1.4, 0.0, 1.0);
	vec3 col = mix(shallow_col, deep_col, pow(depth_t, 0.65));
	col = mix(col * 0.9 + vec3(0.10, 0.09, 0.05), col, smoothstep(0.0, 0.35, depth_t));

	float crest = sin(world_p.x * 0.28 + world_p.z * 0.20 - TIME * 0.45
		+ vnoise(world_p.xz * 0.22) * 1.2) * 0.5 + 0.5;
	float shallow = 1.0 - smoothstep(0.0, 0.55, depth_t);
	col += vec3(0.18, 0.22, 0.24) * pow(crest, 2.8) * shallow * 0.22 * mid;

	float foam_n = vnoise(world_p.xz * mix(1.4, 2.6, detail) + vec2(wt * 0.14, -wt * 0.12));
	float lap = sin(TIME * 0.55 + vnoise(world_p.xz * 0.70) * 6.28) * 0.16;
	float foam_band = 1.0 - smoothstep(0.02, 0.30, depth + (foam_n - 0.5) * 0.22 + lap);
	foam_band *= 1.0 - smoothstep(0.35, 1.2, depth);
	float foam2 = 1.0 - smoothstep(0.0, 0.08, abs(depth - 0.22 - lap * 0.40 - (foam_n - 0.5) * 0.14));
	foam2 *= 1.0 - smoothstep(0.4, 1.0, depth);
	float foam_amt = clamp(foam2 * 0.18 + foam_band * 0.48, 0.0, 1.0) * mix(0.65, 1.0, mid);
	col = mix(col, foam_col, foam_amt);

	ALBEDO = col;
	ROUGHNESS = mix(0.26, 0.17, detail);
	SPECULAR = mix(0.32, 0.45, detail);
	METALLIC = 0.0;

	// Soft shoreline instead of a hard discard pop with camera motion
	float shore_aa = max(fwidth(depth), 0.02);
	float shore_alpha = smoothstep(-shore_aa, 0.08 + shore_aa, depth);
	if (shore_alpha < 0.02) {
		discard;
	}
	ALPHA = mix(0.70, 0.90, smoothstep(0.0, 0.9, depth_t)) * shore_alpha;
	ALPHA = max(ALPHA, foam_band * 0.65 * shore_alpha);
}
