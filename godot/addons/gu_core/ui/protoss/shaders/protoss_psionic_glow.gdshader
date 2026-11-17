shader_type canvas_item;
// Pulsing psionic energy flow for dividers, crest accents, and telemetry indicators.

uniform vec4 base_color : source_color = vec4(0.08, 0.50, 0.65, 0.85);
uniform vec4 pulse_color : source_color = vec4(0.22, 0.91, 1.0, 1.0);
uniform float flow_speed : hint_range(0.1, 3.0) = 0.75;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec2 uv = UV;
	// Traveling energy packet from center outward symmetrically
	float sym_x = abs(uv.x - 0.5) * 2.0;
	float wave = 0.5 + 0.5 * sin(sym_x * 6.28318 - TIME * flow_speed * 4.0);
	float taper = smoothstep(1.0, 0.05, sym_x);
	vec3 col = mix(base_color.rgb, pulse_color.rgb, wave * pulse_strength);
	float alpha = mix(base_color.a, 1.0, wave * 0.5) * taper;
	COLOR = vec4(col, alpha) * COLOR.a;
}
