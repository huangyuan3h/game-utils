shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// River ribbon: UV.x across, UV.y downstream.
// COLOR.r = along [0..1], COLOR.g = over open water — estuary dissolves into sea/lake.

uniform vec3 deep_c = vec3(0.08, 0.32, 0.40);
uniform vec3 light_c = vec3(0.30, 0.58, 0.58);
uniform vec3 sea_c = vec3(0.30, 0.70, 0.65);
uniform vec3 foam_c = vec3(0.94, 0.97, 0.96);
uniform float flow_speed : hint_range(0.0, 4.0) = 0.45;

varying vec2 uv_p;
varying float v_cam_d;
varying float v_along;
varying float v_over;

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
	uv_p = UV;
	v_along = COLOR.r;
	v_over = COLOR.g;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_cam_d = length(CAMERA_POSITION_WORLD - world);
	float near = 1.0 - smoothstep(6.0, 22.0, v_cam_d);
	float mouth = smoothstep(0.55, 1.0, v_along);
	VERTEX.y += sin(UV.y * 4.0 - TIME * 0.7 + UV.x * 3.14) * 0.008 * near * (1.0 - mouth * 0.7);
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float detail = 1.0 - smoothstep(7.0, 28.0, v_cam_d);
	float mid = 1.0 - smoothstep(14.0, 40.0, v_cam_d);
	float flow = TIME * flow_speed;

	// Estuary: how much this fragment has already "become the sea"
	float estuary = smoothstep(0.50, 0.92, v_along);
	float dissolve = smoothstep(0.62, 0.995, v_along) * mix(0.55, 1.0, v_over);
	float plume = estuary * v_over;

	float n1 = vnoise(vec2(UV.x * 3.2, UV.y * 1.35 - flow * 0.32));
	float n2 = vnoise(vec2(UV.x * 5.5 + 5.0, UV.y * 2.4 - flow * 0.48));
	float body = sin(UV.y * 5.5 - flow * 1.1 + (n1 - 0.5) * 1.2) * 0.5 + 0.5;
	float streak = sin(UV.y * 11.0 - flow * 1.6 + sin(UV.x * 4.0) * 0.7 + (n1 - 0.5) * 1.6) * 0.5 + 0.5;
	// Flow streaks fade as the plume spreads into open water
	float flow_mix = mix(body * 0.35, mix(body, streak, 0.55), detail) * (1.0 - dissolve * 0.85);

	vec3 col = mix(light_c, deep_c, smoothstep(0.0, 0.85, across));
	col *= 0.90 + flow_mix * 0.16 * (1.0 - across * 0.7);
	col = mix(col, col * 0.96 + vec3(0.02, 0.03, 0.03), n2 * 0.10 * mid * (1.0 - across));
	// Tint toward coastal sea as the mouth opens
	col = mix(col, sea_c, estuary * 0.55 + dissolve * 0.35);

	float aa = max(fwidth(across), 0.02);
	// Banks soften and open with the estuary flare
	float edge0 = mix(0.70, 0.28, estuary);
	float edge1 = mix(1.0, 0.92, estuary);
	float edge_foam = smoothstep(0.62 - aa, 0.98 + aa, across + (n1 - 0.5) * 0.12 * detail) * 0.45;
	edge_foam *= (1.0 - dissolve);
	float mouth_foam = smoothstep(0.55, 0.85, v_along) * (0.10 + 0.14 * n1) * (1.0 - across * 0.35) * mid;
	float foam = clamp(edge_foam + mouth_foam * (1.0 - dissolve * 0.6), 0.0, 1.0) * mix(0.55, 1.0, detail);
	col = mix(col, foam_c, foam * 0.42);

	float rip = sin(UV.y * 9.0 - TIME * 1.1 + UV.x * 4.0) * 0.18 * detail * (1.0 - dissolve);
	NORMAL = normalize(vec3(
		(n1 - 0.5) * 0.14 * mid * (1.0 - dissolve * 0.5) + rip * 0.04,
		1.0,
		(n2 - 0.5) * 0.14 * mid * (1.0 - dissolve * 0.5) - rip * 0.04
	));

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.28, 0.18, detail), 0.22, dissolve);
	SPECULAR = mix(mix(0.35, 0.55, detail), 0.40, dissolve);

	float rim = smoothstep(edge0 - aa, edge1 + aa, across);
	float alpha = mix(0.90, 0.20, rim);
	// Soft dissolve of the plume into the sea plane — diffusion, not a hard tube tip
	alpha *= 1.0 - dissolve * 0.92;
	alpha *= mix(1.0, 0.35, plume * rim);
	if (alpha < 0.02) {
		discard;
	}
	ALPHA = alpha;
}
