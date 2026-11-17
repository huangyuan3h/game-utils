shader_type sky;
// Procedural atmospheric sky: Rayleigh-like gradient, sun/moon discs with scattering halos,
// twinkling stars, multi-layered FBM clouds with sun rim lighting, and in-cloud lightning glow.

uniform vec3 sun_dir = vec3(0.4, 0.5, -0.7);
uniform vec3 moon_dir = vec3(-0.4, -0.5, 0.7);
uniform float day_factor : hint_range(0.0, 1.0) = 1.0;
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform float sunset_factor : hint_range(0.0, 1.0) = 0.0;

uniform vec3 sky_top_col : source_color = vec3(0.20, 0.48, 0.88);
uniform vec3 sky_horizon_col : source_color = vec3(0.68, 0.82, 0.94);
uniform vec3 ground_col : source_color = vec3(0.14, 0.17, 0.14);

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.28;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.15;
uniform float weather_obscure : hint_range(0.0, 1.0) = 0.0;
uniform vec2 wind_offset = vec2(0.0, 0.0);
uniform float cloud_morph = 0.0;

uniform float lightning_flash : hint_range(0.0, 2.0) = 0.0;
uniform vec3 lightning_dir = vec3(0.0, 0.35, -1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
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

float fbm4(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.03 + vec2(17.1, 31.7);
		a *= 0.5;
	}
	return v;
}

float star_layer(vec3 dir, float scale, float density) {
	vec3 cell = floor(dir * scale);
	vec3 local = fract(dir * scale) - 0.5;
	float rnd = hash13(cell);
	if (rnd < density) {
		return 0.0;
	}
	vec3 jitter = vec3(
		hash13(cell + 1.3) - 0.5,
		hash13(cell + 7.1) - 0.5,
		hash13(cell + 13.7) - 0.5
	) * 0.55;
	float dist = length(local - jitter);
	float size = mix(0.04, 0.11, fract(rnd * 37.0));
	float twinkle = 0.72 + 0.28 * sin(TIME * (1.8 + fract(rnd * 19.0) * 3.5) + rnd * 60.0);
	return smoothstep(size, 0.0, dist) * twinkle;
}

float sample_clouds(vec2 uv, float coverage) {
	float base = fbm4(uv * 0.42 + vec2(cloud_morph * 0.06, -cloud_morph * 0.04));
	float detail = fbm4(uv * 1.15 - vec2(cloud_morph * 0.11, cloud_morph * 0.08));
	float raw = base * 0.72 + detail * 0.28;
	float thresh = mix(0.76, 0.22, coverage);
	float softness = mix(0.18, 0.30, coverage);
	return smoothstep(thresh - softness * 0.5, thresh + softness, raw);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 s_dir = normalize(sun_dir);
	vec3 m_dir = normalize(moon_dir);

	float elev = dir.y;
	float horizon_mix = pow(1.0 - clamp(abs(elev), 0.0, 1.0), 2.6);
	vec3 col = mix(sky_top_col, sky_horizon_col, horizon_mix);

	// Ground hemisphere blend below horizon.
	if (elev < 0.0) {
		float g_t = smoothstep(0.0, -0.35, elev);
		col = mix(sky_horizon_col * 0.85, ground_col, g_t);
	}

	// Sun Mie forward glow near horizon & solar azimuth.
	float sun_cos = max(dot(dir, s_dir), 0.0);
	float sun_vis = smoothstep(-0.12, 0.12, s_dir.y) * (1.0 - weather_obscure * 0.85);
	vec3 sun_halo_col = mix(vec3(1.0, 0.92, 0.74), vec3(1.0, 0.48, 0.20), sunset_factor);
	float sun_halo = pow(sun_cos, 10.0) * 0.35 + pow(sun_cos, 64.0) * 0.45;
	col += sun_halo_col * sun_halo * sun_vis * (0.35 + 0.65 * day_factor);

	// Crisp sun disc (occluded softly by heavy overcast/storm).
	float sun_disc = smoothstep(0.9986, 0.9994, dot(dir, s_dir));
	col += sun_halo_col * sun_disc * 4.5 * smoothstep(-0.04, 0.05, s_dir.y) * (1.0 - weather_obscure * 0.92);

	// Moon disc + subtle maria + halo at night.
	float moon_cos = max(dot(dir, m_dir), 0.0);
	float moon_vis = night_factor * smoothstep(-0.08, 0.10, m_dir.y) * (1.0 - weather_obscure * 0.85);
	float moon_halo = pow(moon_cos, 36.0) * 0.22;
	col += vec3(0.55, 0.68, 0.92) * moon_halo * moon_vis;
	float moon_disc = smoothstep(0.9991, 0.9995, dot(dir, m_dir));
	if (moon_disc > 0.001) {
		float maria = vnoise(dir.xy * 65.0 + dir.z * 42.0);
		vec3 moon_col = mix(vec3(0.76, 0.80, 0.90), vec3(0.96, 0.98, 1.0), maria * 0.55 + 0.45);
		col = mix(col, moon_col * 1.35, moon_disc * moon_vis);
	}

	// Stars (upper sky, visible at night and faded by cloud cover).
	if (elev > 0.02 && night_factor > 0.04 && !AT_CUBEMAP_PASS) {
		float star_fade = night_factor * smoothstep(0.02, 0.25, elev) * (1.0 - weather_obscure * 0.9);
		float stars = star_layer(dir, 95.0, 0.986) * 1.15 + star_layer(dir, 170.0, 0.990) * 0.75;
		col += vec3(0.85, 0.91, 1.0) * stars * star_fade;
	}

	// Procedural multi-layered clouds across upper hemisphere.
	if (elev > 0.005 && cloud_coverage > 0.02) {
		vec2 dome_uv = dir.xz / (elev + 0.16);
		vec2 c_uv = dome_uv + wind_offset;

		float density = sample_clouds(c_uv, cloud_coverage);
		// High thin cirrus wisps for clear/cloudy sky depth.
		float cirrus = smoothstep(0.55, 0.85, fbm4(dome_uv * 0.9 + wind_offset * 0.6)) * 0.28 * (1.0 - cloud_darkness);
		float total_cloud = clamp(density + cirrus * (1.0 - density), 0.0, 1.0);

		// Sunward thickness sampling for silver/golden cloud rims.
		vec2 sun_step = normalize(s_dir.xz + vec2(0.0001)) * 0.22;
		float sun_density = sample_clouds(c_uv + sun_step, cloud_coverage);
		float rim = clamp(density - sun_density, 0.0, 1.0) * 1.8 + pow(sun_cos, 6.0) * 0.45;

		vec3 day_cloud_lit = mix(vec3(0.98, 0.99, 1.0), vec3(1.0, 0.62, 0.34), sunset_factor);
		vec3 day_cloud_shadow = mix(vec3(0.62, 0.69, 0.80), vec3(0.46, 0.32, 0.44), sunset_factor);
		vec3 night_cloud_lit = vec3(0.16, 0.20, 0.30);
		vec3 night_cloud_shadow = vec3(0.05, 0.07, 0.12);

		vec3 lit_col = mix(day_cloud_lit, night_cloud_lit, night_factor);
		vec3 dark_col = mix(day_cloud_shadow, night_cloud_shadow, night_factor);

		// Heavy overcast / storm cloud darkening.
		vec3 storm_base = mix(vec3(0.24, 0.27, 0.32), vec3(0.06, 0.07, 0.10), night_factor);
		lit_col = mix(lit_col, storm_base * 1.35, cloud_darkness * 0.82);
		dark_col = mix(dark_col, storm_base * 0.65, cloud_darkness * 0.90);

		float light_term = clamp(0.42 + rim * (1.0 - cloud_darkness * 0.65) - density * 0.38, 0.0, 1.0);
		vec3 cloud_col = mix(dark_col, lit_col, light_term);

		// In-cloud sheet lightning glow near active bolt direction.
		if (lightning_flash > 0.001) {
			float l_align = pow(max(dot(dir, normalize(lightning_dir)), 0.0), 3.0);
			float scatter = (0.35 + 0.65 * l_align) * (0.4 + 0.6 * density);
			cloud_col += vec3(0.68, 0.80, 1.0) * lightning_flash * scatter * 1.45;
		}

		// Horizon atmospheric fade so clouds melt seamlessly into fog.
		float horizon_fade = smoothstep(0.005, 0.16, elev);
		float cloud_alpha = total_cloud * horizon_fade * mix(0.86, 0.98, cloud_darkness);
		col = mix(col, cloud_col, cloud_alpha);
	}

	// General sky flash wash during lightning strike.
	if (lightning_flash > 0.001) {
		float flash_align = 0.4 + 0.6 * pow(max(dot(dir, normalize(lightning_dir)), 0.0), 2.0);
		col += vec3(0.42, 0.52, 0.72) * lightning_flash * flash_align * 0.55;
	}

	COLOR = col;
}
