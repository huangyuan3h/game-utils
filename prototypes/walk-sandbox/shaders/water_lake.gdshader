shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Flat lake disc with slow swell + soft shore. Detail fades with camera distance
// so far lakes stay calm instead of aliasing into a sudden "near" look.

uniform vec3 shallow_col = vec3(0.25, 0.58, 0.52);
uniform vec3 deep_col = vec3(0.07, 0.30, 0.34);
uniform vec3 foam_col = vec3(0.94, 0.97, 0.96);

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

void vertex() {
	v_radial = UV.x;
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cam_d = length(CAMERA_POSITION_WORLD - world_p);
	float calm = 1.0 - smoothstep(0.50, 1.0, v_radial);
	float near = 1.0 - smoothstep(8.0, 30.0, v_cam_d);
	float swell = sin(world_p.x * 0.22 + TIME * 0.18) * 0.55
		+ sin(world_p.z * 0.18 - TIME * 0.14) * 0.45;
	VERTEX.y += swell * 0.030 * calm * mix(0.45, 1.0, near);
}

void fragment() {
	float r = clamp(v_radial, 0.0, 1.0);
	float detail = 1.0 - smoothstep(8.0, 32.0, v_cam_d);
	float mid = 1.0 - smoothstep(16.0, 48.0, v_cam_d);
	float wt = TIME * 0.12;

	// Prefer low-frequency field far away; blend in finer ripples nearby
	vec2 uv_lo = world_p.xz * 0.12 + vec2(wt * 0.010, -wt * 0.008);
	vec2 uv_hi = world_p.xz * 0.28 + vec2(wt * 0.014, -wt * 0.011);
	float n = mix(vnoise(uv_lo), vnoise(uv_hi), detail);
	vec2 wn = (vec2(vnoise(uv_lo), vnoise(uv_lo + 3.7)) - 0.5) * 0.05 * mid
		+ (vec2(vnoise(uv_hi), vnoise(uv_hi + 5.1)) - 0.5) * 0.04 * detail;
	NORMAL = normalize(vec3(wn.x, 1.0, wn.y));

	vec3 col = mix(deep_col, shallow_col, pow(r, 1.15));
	col = mix(col, col * vec3(0.95, 0.99, 1.0), n * 0.04 * mid);

	float foam_n = vnoise(world_p.xz * mix(0.9, 1.8, detail) + vec2(wt * 0.06, -wt * 0.04));
	float aa = max(fwidth(r), 0.015);
	float foam = smoothstep(0.55 - aa, 0.90 + aa, r + (foam_n - 0.5) * 0.04 * detail);
	col = mix(col, foam_col, foam * 0.28 * mix(0.6, 1.0, mid));

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.8);
	col += vec3(0.05, 0.09, 0.11) * fresnel * 0.25;

	ALBEDO = col;
	ROUGHNESS = mix(0.24, 0.15, detail);
	SPECULAR = mix(0.32, 0.45, detail);
	METALLIC = 0.0;

	float edge_fade = 1.0 - smoothstep(0.48 - aa, 1.0 + aa, r);
	edge_fade *= edge_fade;
	ALPHA = mix(0.86, 0.0, smoothstep(0.42, 1.0, r)) * max(edge_fade, 0.001);
	if (ALPHA < 0.012) {
		discard;
	}
}
