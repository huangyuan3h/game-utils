shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
// Weather-responsive procedural foliage shader for MultiMesh grass, wildflowers, reeds, shrubs, and tree canopies.
// INSTANCE_CUSTOM.x = phase offset, INSTANCE_CUSTOM.y = sway weight, INSTANCE_CUSTOM.z = tint shift.

uniform float sway_speed = 1.65;
uniform float sway_amp = 0.08;
uniform float fade_start = 42.0;
uniform float fade_end = 56.0;
uniform bool use_distance_fade = false;

uniform float wind_strength : hint_range(0.0, 1.5) = 0.14;
uniform vec2 wind_dir = vec2(0.95, 0.31);
uniform float snow_cover : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec4 v_col;
varying float v_cam_d;
varying float v_height;
varying vec3 v_world_n;

void vertex() {
	v_col = COLOR;
	v_height = clamp(UV.y, 0.0, 1.0);
	vec3 inst_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_cam_d = length(CAMERA_POSITION_WORLD - inst_world);

	float w_mul = mix(0.8, 2.8, clamp(wind_strength, 0.0, 1.0));
	float spd_mul = mix(0.95, 2.05, clamp(wind_strength, 0.0, 1.0));
	float phase = INSTANCE_CUSTOM.x * 6.2831853 + inst_world.x * 0.25 + inst_world.z * 0.21;
	float sway_w = INSTANCE_CUSTOM.y * v_height * v_height;
	float sp = sway_speed * spd_mul;
	float gust = sin(TIME * sp + phase) * 0.72 + sin(TIME * (sp * 2.15) + phase * 1.7) * 0.28;
	float cross_gust = cos(TIME * (sp * 0.85) + phase * 1.3);

	vec2 wdir = normalize(wind_dir + vec2(0.0001));
	float lean = wind_strength * 0.65 * sway_w;
	VERTEX.x += gust * sway_amp * w_mul * sway_w + wdir.x * lean * sway_amp * 2.2;
	VERTEX.z += cross_gust * sway_amp * 0.65 * w_mul * sway_w + wdir.y * lean * sway_amp * 2.2;
}

void fragment() {
	if (use_distance_fade && v_cam_d > fade_end) {
		discard;
	}
	if (use_distance_fade && v_cam_d > fade_start) {
		float f = 1.0 - smoothstep(fade_start, fade_end, v_cam_d);
		vec2 p = floor(FRAGCOORD.xy);
		float dither = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
		if (dither > f) {
			discard;
		}
	}

	vec3 col = v_col.rgb;
	col *= mix(1.0, 0.78, wetness * 0.65 * (1.0 - snow_cover));

	// Frost/snow accumulation on upper foliage & upward-facing canopy crowns
	float up_face = smoothstep(0.10, 0.75, v_world_n.y);
	float frost_mask = smoothstep(0.28, 0.88, v_height) * mix(0.45, 1.0, up_face) * snow_cover;
	col = mix(col, vec3(0.90, 0.94, 0.99), frost_mask * 0.82);

	ALBEDO = col;
	float rough = mix(0.88, 0.72, v_height);
	rough = mix(rough, 0.34, wetness * 0.60 * (1.0 - snow_cover));
	rough = mix(rough, 0.66, frost_mask);
	ROUGHNESS = rough;
	SPECULAR = mix(0.18, 0.45, wetness * 0.65 + frost_mask * 0.2);
	METALLIC = 0.0;
}
