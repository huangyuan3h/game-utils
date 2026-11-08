shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.06, 0.22, 0.32, 0.72);
uniform vec4 shallow_color : source_color = vec4(0.22, 0.48, 0.52, 0.48);
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.96, 0.9);
uniform float flow_speed : hint_range(0.0, 2.0) = 0.42;
uniform float ripple_scale : hint_range(0.5, 20.0) = 6.5;
uniform float wave_amp : hint_range(0.0, 0.2) = 0.035;
uniform float specular_boost : hint_range(0.0, 2.0) = 0.85;

varying vec2 v_world_xz;
varying vec2 v_flow;
varying float v_edge;
varying float v_depth;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise2(p);
		p = p * 2.07 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world_xz = UV;
	v_flow = normalize(UV2 + vec2(0.0001));
	v_edge = COLOR.r; // 1 near bank / shallow
	v_depth = COLOR.g; // 0 shallow .. 1 deep center

	float phase = dot(v_world_xz, v_flow) * ripple_scale;
	float cross = dot(v_world_xz, vec2(-v_flow.y, v_flow.x)) * ripple_scale * 0.7;
	float wave = sin(phase * 1.7 - TIME * 2.4) * 0.55
		+ sin(cross * 2.1 + TIME * 1.6) * 0.35
		+ sin(phase * 0.6 + cross * 0.9 - TIME * 1.1) * 0.25;
	VERTEX.y += wave * wave_amp * mix(1.0, 0.35, v_edge);
}

void fragment() {
	vec2 flow = v_flow;
	vec2 perp = vec2(-flow.y, flow.x);

	// Dual scrolling layers along flow (caustic / ripple motion)
	vec2 uv_a = v_world_xz * 0.55 - flow * TIME * flow_speed;
	vec2 uv_b = v_world_xz * 0.95 + perp * TIME * flow_speed * 0.35 - flow * TIME * flow_speed * 0.55;
	float n_a = fbm(uv_a * ripple_scale);
	float n_b = fbm(uv_b * ripple_scale * 1.35 + 3.7);
	float ripples = n_a * 0.65 + n_b * 0.35;

	// Perturb normals for glitter / moving specular
	float e = 0.035;
	float hx = fbm((uv_a + vec2(e, 0.0)) * ripple_scale) - fbm((uv_a - vec2(e, 0.0)) * ripple_scale);
	float hz = fbm((uv_a + vec2(0.0, e)) * ripple_scale) - fbm((uv_a - vec2(0.0, e)) * ripple_scale);
	vec3 n = normalize(NORMAL + vec3(hx, 0.0, hz) * 1.8);
	NORMAL = n;

	float ndv = clamp(dot(normalize(n), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 2.8);

	vec3 base = mix(shallow_color.rgb, deep_color.rgb, v_depth);
	base = mix(base, base * vec3(0.85, 0.95, 1.05), ripples * 0.35);

	// Foam: bank wash + streaked whitecaps traveling with flow
	float streak = fbm(v_world_xz * 2.4 - flow * TIME * flow_speed * 1.7);
	float foam_streak = smoothstep(0.62, 0.88, streak);
	float bank_foam = v_edge * (0.45 + 0.55 * smoothstep(0.4, 0.85, n_b));
	float foam = clamp(bank_foam + foam_streak * (0.12 + v_edge * 0.35), 0.0, 1.0);

	vec3 col = mix(base, foam_color.rgb, foam);
	col += fresnel * vec3(0.18, 0.28, 0.35) * specular_boost;

	float alpha = mix(shallow_color.a, deep_color.a, v_depth);
	alpha = clamp(alpha + fresnel * 0.22 + foam * 0.18 - ripples * 0.04, 0.28, 0.92);

	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = mix(0.06, 0.35, foam);
	METALLIC = 0.05;
	SPECULAR = 0.65 + fresnel * 0.25 * specular_boost;
	EMISSION = foam_color.rgb * foam * 0.04;
}
