shader_type canvas_item;
// Khalai holographic lattice + sweeping psionic scan wave overlay for Protoss panels.

uniform vec4 scan_color : source_color = vec4(0.22, 0.91, 1.0, 1.0);
uniform vec4 gold_rim_color : source_color = vec4(0.95, 0.81, 0.40, 1.0);
uniform float grid_alpha : hint_range(0.0, 0.25) = 0.045;
uniform float scan_alpha : hint_range(0.0, 0.30) = 0.075;
uniform float scan_speed : hint_range(0.05, 1.5) = 0.22;
uniform float rim_alpha : hint_range(0.0, 0.25) = 0.06;

void fragment() {
	vec2 uv = UV;

	// Subtle diagonal Khalai lattice
	float diag_a = abs(fract((uv.x * 26.0 + uv.y * 18.0)) - 0.5);
	float diag_b = abs(fract((uv.x * 26.0 - uv.y * 18.0)) - 0.5);
	float lattice = smoothstep(0.055, 0.0, min(diag_a, diag_b)) * grid_alpha;

	// Fine horizontal CRT/holo micro-lines
	float h_lines = (0.5 + 0.5 * sin(uv.y * 220.0)) * 0.018;

	// Periodic downward psionic scan wave
	float wave_pos = fract(TIME * scan_speed);
	float dist = abs(uv.y - wave_pos);
	float wave = exp(-dist * 24.0) * scan_alpha;

	// Soft golden-cyan inner border shimmer
	float edge_x = min(uv.x, 1.0 - uv.x);
	float edge_y = min(uv.y, 1.0 - uv.y);
	float edge = exp(-min(edge_x, edge_y) * 18.0) * rim_alpha;

	vec3 col = scan_color.rgb * (lattice + h_lines + wave) + gold_rim_color.rgb * edge;
	float alpha = clamp(lattice + h_lines + wave + edge, 0.0, 0.35);
	COLOR = vec4(col, alpha);
}
