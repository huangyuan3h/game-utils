extends Node3D
## Day/night time and continuous weather atmosphere controller.
## T — cycle time speed · Y — cycle weather · L — trigger lightning

enum Weather { CLEAR, CLOUDY, OVERCAST, RAIN, STORM, SNOW }

const WEATHER_NAMES := ["Clear", "Cloudy", "Overcast", "Rain", "Storm", "Snow"]
const SPEEDS := [1.0, 30.0, 120.0, 600.0]
const SPEED_LABELS := ["1×", "30×", "120×", "600×"]
const BASE_HOURS_PER_SECOND := 0.02

# Target profiles: coverage, darkness, obscure, rain, snow, wind, fog_density
const WEATHER_TARGETS := {
	Weather.CLEAR: {
		"coverage": 0.22, "darkness": 0.05, "obscure": 0.0,
		"rain": 0.0, "snow": 0.0, "wind": 0.14, "fog": 0.0012,
	},
	Weather.CLOUDY: {
		"coverage": 0.56, "darkness": 0.22, "obscure": 0.35,
		"rain": 0.0, "snow": 0.0, "wind": 0.28, "fog": 0.0022,
	},
	Weather.OVERCAST: {
		"coverage": 0.88, "darkness": 0.62, "obscure": 0.78,
		"rain": 0.0, "snow": 0.0, "wind": 0.38, "fog": 0.0042,
	},
	Weather.RAIN: {
		"coverage": 0.92, "darkness": 0.76, "obscure": 0.88,
		"rain": 0.58, "snow": 0.0, "wind": 0.52, "fog": 0.0068,
	},
	Weather.STORM: {
		"coverage": 0.99, "darkness": 0.96, "obscure": 0.98,
		"rain": 1.0, "snow": 0.0, "wind": 0.95, "fog": 0.0115,
	},
	Weather.SNOW: {
		"coverage": 0.86, "darkness": 0.38, "obscure": 0.74,
		"rain": 0.0, "snow": 0.92, "wind": 0.44, "fog": 0.0085,
	},
}

@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _sun_light: DirectionalLight3D = $SunLight
@onready var _moon_light: DirectionalLight3D = $MoonLight
@onready var _lightning_light: DirectionalLight3D = $LightningLight
@onready var _lightning: Node3D = $WeatherLightning
@onready var _particles: Node3D = $WeatherParticles
@onready var _audio: Node = $WeatherAudio

var hour: float = 8.0
var speed_index: int = 0
var weather: Weather = Weather.CLEAR

var _sky_mat: ShaderMaterial
var _environment: Environment
var _anchor_node: Node3D = null
var _terrain: Node = null

# Continuous atmospheric state
var _cloud_coverage: float = 0.22
var _cloud_darkness: float = 0.05
var _weather_obscure: float = 0.0
var _rain_intensity: float = 0.0
var _snow_intensity: float = 0.0
var _wind_strength: float = 0.14
var _fog_density: float = 0.0012
var _ground_wetness: float = 0.0
var _snow_cover: float = 0.0
var _storm_amount: float = 0.0

var _sim_time: float = 0.0
var _wind_offset := Vector2.ZERO
var _cloud_morph: float = 0.0
var _wind_vector := Vector3(1.2, 0.0, 0.35)
var _gust: float = 0.0


func _ready() -> void:
	_bind_keys()
	_setup_sky_environment()
	_wire_subsystems()
	_apply_preset_immediate(weather)
	_apply_visuals(0.0)


func set_context(p_terrain: Node, p_anchor: Node3D) -> void:
	_terrain = p_terrain
	_anchor_node = p_anchor
	if _lightning != null:
		_lightning.set("terrain", p_terrain)
	if _particles != null:
		_particles.set("terrain", p_terrain)


func _process(delta: float) -> void:
	if _is_gameplay_input_allowed():
		if Input.is_action_just_pressed("time_speed"):
			speed_index = (speed_index + 1) % SPEEDS.size()
		if Input.is_action_just_pressed("weather_cycle"):
			weather = ((int(weather) + 1) % WEATHER_NAMES.size()) as Weather
		if Input.is_action_just_pressed("trigger_lightning"):
			if _lightning != null and _lightning.has_method("trigger_now"):
				_lightning.call("trigger_now", _get_anchor_pos())

	hour = fposmod(hour + BASE_HOURS_PER_SECOND * SPEEDS[speed_index] * delta, 24.0)
	_sim_time += delta
	_step_weather_state(delta)
	_apply_visuals(delta)


func export_state() -> Dictionary:
	return {
		"hour": hour,
		"weather": int(weather),
		"speed_index": speed_index,
	}


func apply_state(state_data: Dictionary) -> void:
	if state_data.has("hour"):
		hour = fposmod(float(state_data["hour"]), 24.0)
	if state_data.has("speed_index"):
		speed_index = clampi(int(state_data["speed_index"]), 0, SPEEDS.size() - 1)
	if state_data.has("weather"):
		var w_idx := clampi(int(state_data["weather"]), 0, WEATHER_NAMES.size() - 1)
		weather = w_idx as Weather
		_apply_preset_immediate(weather)
	_apply_visuals(0.0)


func _is_gameplay_input_allowed() -> bool:
	var router := get_node_or_null("/root/InputRouter")
	if router != null and router.has_method("is_gameplay_active"):
		return bool(router.call("is_gameplay_active"))
	return true


func get_hud_line() -> String:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	var phase := _phase_name()
	var w_label: String = WEATHER_NAMES[int(weather)]
	var extras: Array[String] = []
	if _ground_wetness > 0.12:
		extras.append("wet %.0f%%" % (_ground_wetness * 100.0))
	if _snow_cover > 0.08:
		extras.append("snow %.0f%%" % (_snow_cover * 100.0))
	var extra_str := (" (" + ", ".join(extras) + ")") if not extras.is_empty() else ""
	return "Time %02d:%02d (%s) · speed %s [T] · weather %s%s [Y] · bolt [L]" % [
		h, m, phase, SPEED_LABELS[speed_index], w_label, extra_str
	]


func get_night_factor() -> float:
	var elev := _sun_elevation_rad()
	return 1.0 - clampf(elev * 1.15 + 0.15, 0.0, 1.0)


func get_weather_params() -> Dictionary:
	return {
		"rain_intensity": _rain_intensity,
		"snow_intensity": _snow_intensity,
		"ground_wetness": _ground_wetness,
		"snow_cover": _snow_cover,
		"wind_strength": _wind_strength,
		"wind_vector": _wind_vector,
		"cloud_darkness": _cloud_darkness,
		"lightning_flash": float(_lightning.get("flash_intensity")) if _lightning != null else 0.0,
	}


func _phase_name() -> String:
	if hour >= 5.0 and hour < 7.0:
		return "sunrise"
	if hour >= 7.0 and hour < 17.0:
		return "day"
	if hour >= 17.0 and hour < 19.5:
		return "sunset"
	return "night"


func _bind_keys() -> void:
	_bind("time_speed", [KEY_T])
	_bind("weather_cycle", [KEY_Y])
	_bind("trigger_lightning", [KEY_L])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _setup_sky_environment() -> void:
	var sky_shader := load("res://shaders/sky_weather.gdshader") as Shader
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sky_shader

	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_energy = 0.55
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 1.02

	_environment.glow_enabled = true
	_environment.glow_intensity = 0.45
	_environment.glow_bloom = 0.14
	_environment.glow_hdr_threshold = 1.05
	_environment.glow_hdr_scale = 1.8

	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_environment.fog_density = 0.0015
	_environment.fog_sky_affect = 0.42
	_environment.fog_height = 2.0
	_environment.fog_height_density = 0.02

	_environment.adjustment_enabled = true
	_environment.adjustment_brightness = 1.0
	_environment.adjustment_contrast = 1.04
	_environment.adjustment_saturation = 1.05
	_env.environment = _environment


func _wire_subsystems() -> void:
	if _lightning != null:
		_lightning.set("lightning_light", _lightning_light)
		if _lightning.has_signal("strike_triggered") and _audio != null and _audio.has_method("trigger_thunder"):
			if not _lightning.is_connected("strike_triggered", Callable(_audio, "trigger_thunder")):
				_lightning.connect("strike_triggered", Callable(_audio, "trigger_thunder"))


func _apply_preset_immediate(w: Weather) -> void:
	var t: Dictionary = WEATHER_TARGETS[w]
	_cloud_coverage = float(t["coverage"])
	_cloud_darkness = float(t["darkness"])
	_weather_obscure = float(t["obscure"])
	_rain_intensity = float(t["rain"])
	_snow_intensity = float(t["snow"])
	_wind_strength = float(t["wind"])
	_fog_density = float(t["fog"])
	_storm_amount = 1.0 if w == Weather.STORM else 0.0


func _step_weather_state(delta: float) -> void:
	var t: Dictionary = WEATHER_TARGETS[weather]
	var k := 1.0 - exp(-0.85 * delta)
	_cloud_coverage = lerpf(_cloud_coverage, float(t["coverage"]), k)
	_cloud_darkness = lerpf(_cloud_darkness, float(t["darkness"]), k)
	_weather_obscure = lerpf(_weather_obscure, float(t["obscure"]), k)
	_rain_intensity = lerpf(_rain_intensity, float(t["rain"]), 1.0 - exp(-1.15 * delta))
	_snow_intensity = lerpf(_snow_intensity, float(t["snow"]), 1.0 - exp(-1.1 * delta))
	_wind_strength = lerpf(_wind_strength, float(t["wind"]), 1.0 - exp(-0.9 * delta))
	_fog_density = lerpf(_fog_density, float(t["fog"]), k)

	var target_storm := 1.0 if weather == Weather.STORM else 0.0
	_storm_amount = lerpf(_storm_amount, target_storm, 1.0 - exp(-1.0 * delta))

	# Surface memory: ground gets wet rapidly in rain and dries gradually; snow accumulates & melts smoothly.
	if _rain_intensity > 0.08:
		_ground_wetness = move_toward(_ground_wetness, clampf(0.45 + _rain_intensity * 0.65, 0.0, 1.0), delta * (0.18 + _rain_intensity * 0.25))
		_snow_cover = move_toward(_snow_cover, 0.0, delta * (0.09 + _rain_intensity * 0.16))
	else:
		var dry_rate := lerpf(0.055, 0.015, _cloud_darkness)
		_ground_wetness = move_toward(_ground_wetness, 0.0, delta * dry_rate)

	if _snow_intensity > 0.08:
		_snow_cover = move_toward(_snow_cover, 1.0, delta * (0.14 * _snow_intensity))
	elif _rain_intensity <= 0.08:
		var melt_rate := lerpf(0.05, 0.018, _cloud_darkness)
		_snow_cover = move_toward(_snow_cover, 0.0, delta * melt_rate)

	# Dynamic wind & gusts
	_gust = 0.5 + 0.3 * sin(_sim_time * 0.45) + 0.2 * sin(_sim_time * 1.13 + 1.4)
	var wind_angle := 0.32 + sin(_sim_time * 0.07) * 0.25
	var wind_speed := lerpf(0.8, 7.5, _wind_strength) * (0.78 + _gust * 0.48)
	_wind_vector = Vector3(cos(wind_angle) * wind_speed, 0.0, sin(wind_angle) * wind_speed)

	var time_mul: float = 1.0 + float(SPEEDS[speed_index]) * 0.008
	_wind_offset += Vector2(_wind_vector.x, _wind_vector.z) * 0.018 * delta * time_mul
	_cloud_morph += delta * (0.35 + _wind_strength * 0.9) * minf(time_mul, 4.0)


func _sun_elevation_rad() -> float:
	return sin((hour / 24.0 - 0.25) * TAU)


func _safe_look_at(node: Node3D, target: Vector3) -> void:
	var to_target := target - node.global_position
	if to_target.length_squared() < 0.0001:
		return
	var forward := to_target.normalized()
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.95:
		up = Vector3.RIGHT
	node.look_at(target, up)


func _get_anchor_pos() -> Vector3:
	if _anchor_node != null and is_instance_valid(_anchor_node):
		return _anchor_node.global_position
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	return Vector3.ZERO


func _apply_visuals(delta: float) -> void:
	var elev := _sun_elevation_rad()
	var day_f := clampf(elev * 1.15 + 0.15, 0.0, 1.0)
	var night_f := 1.0 - day_f
	var sunset_f := 0.0
	if hour > 5.0 and hour < 8.0:
		sunset_f = 1.0 - absf(hour - 6.5) / 1.5
	elif hour > 16.5 and hour < 19.5:
		sunset_f = 1.0 - absf(hour - 18.0) / 1.5
	sunset_f = clampf(sunset_f, 0.0, 1.0)

	var az := (hour / 24.0) * TAU
	var sun_dir := Vector3(sin(az) * cos(elev * PI * 0.5), elev, -cos(az) * cos(elev * PI * 0.5))
	if sun_dir.length_squared() < 0.0001:
		sun_dir = Vector3.UP
	sun_dir = sun_dir.normalized()

	_sun_light.global_position = sun_dir * 40.0
	_safe_look_at(_sun_light, Vector3.ZERO)
	_moon_light.global_position = -sun_dir * 40.0
	_safe_look_at(_moon_light, Vector3.ZERO)

	# Update lightning before lighting/sky so flash affects same frame
	var anchor := _get_anchor_pos()
	var lightning_flash := 0.0
	var lightning_dir := Vector3(0.0, 0.5, -1.0)
	if _lightning != null and _lightning.has_method("update_storm"):
		_lightning.call("update_storm", _storm_amount, anchor, delta)
		lightning_flash = float(_lightning.get("flash_intensity"))
		lightning_dir = _lightning.get("flash_direction")

	var sun_dim := lerpf(1.0, 0.22, _weather_obscure)
	sun_dim = lerpf(sun_dim, 0.34, _snow_intensity * 0.5)
	_sun_light.light_energy = maxf(elev, 0.0) * 1.42 * sun_dim
	var day_sun := Color(1.0, 0.96, 0.88).lerp(Color(0.84, 0.90, 0.98), _snow_intensity * 0.65)
	_sun_light.light_color = day_sun.lerp(Color(1.0, 0.55, 0.25), sunset_f * (1.0 - _weather_obscure * 0.6))
	_sun_light.shadow_enabled = elev > 0.02 and _weather_obscure < 0.85

	_moon_light.light_energy = night_f * 0.55 * lerpf(1.0, 0.45, _weather_obscure)
	_moon_light.light_color = Color(0.70, 0.78, 1.0)

	# Sky palette
	var day_top := Color(0.22, 0.50, 0.90)
	var day_horizon := Color(0.70, 0.84, 0.96)
	var sunset_top := Color(0.24, 0.20, 0.44)
	var sunset_horizon := Color(1.0, 0.46, 0.24)
	var night_top := Color(0.02, 0.03, 0.08)
	var night_horizon := Color(0.05, 0.08, 0.15)

	var top := day_top.lerp(night_top, night_f).lerp(sunset_top, sunset_f * day_f)
	var horizon := day_horizon.lerp(night_horizon, night_f).lerp(sunset_horizon, sunset_f)

	var overcast_top := Color(0.28, 0.31, 0.36).lerp(Color(0.04, 0.05, 0.08), night_f)
	var overcast_hor := Color(0.42, 0.46, 0.51).lerp(Color(0.07, 0.08, 0.12), night_f)
	var snow_top := Color(0.56, 0.62, 0.70).lerp(Color(0.08, 0.10, 0.15), night_f)
	var snow_hor := Color(0.76, 0.81, 0.88).lerp(Color(0.14, 0.17, 0.24), night_f)

	top = top.lerp(overcast_top, _cloud_darkness * 0.82)
	horizon = horizon.lerp(overcast_hor, _cloud_darkness * 0.82)
	top = top.lerp(snow_top, _snow_intensity * 0.75)
	horizon = horizon.lerp(snow_hor, _snow_intensity * 0.78)
	var ground_col := Color(0.12, 0.16, 0.11).lerp(Color(0.02, 0.03, 0.05), night_f)
	ground_col = ground_col.lerp(Color(0.55, 0.60, 0.68), _snow_cover * 0.5 * day_f)

	# Push sky shader uniforms
	_sky_mat.set_shader_parameter("sun_dir", sun_dir)
	_sky_mat.set_shader_parameter("moon_dir", -sun_dir)
	_sky_mat.set_shader_parameter("day_factor", day_f)
	_sky_mat.set_shader_parameter("night_factor", night_f)
	_sky_mat.set_shader_parameter("sunset_factor", sunset_f * (1.0 - _cloud_darkness * 0.7))
	_sky_mat.set_shader_parameter("sky_top_col", top)
	_sky_mat.set_shader_parameter("sky_horizon_col", horizon)
	_sky_mat.set_shader_parameter("ground_col", ground_col)
	_sky_mat.set_shader_parameter("cloud_coverage", _cloud_coverage)
	_sky_mat.set_shader_parameter("cloud_darkness", _cloud_darkness)
	_sky_mat.set_shader_parameter("weather_obscure", _weather_obscure)
	_sky_mat.set_shader_parameter("wind_offset", _wind_offset)
	_sky_mat.set_shader_parameter("cloud_morph", _cloud_morph)
	_sky_mat.set_shader_parameter("lightning_flash", lightning_flash)
	_sky_mat.set_shader_parameter("lightning_dir", lightning_dir)

	# Ambient, fog & post-processing
	var env_dim := lerpf(1.0, 0.52, _cloud_darkness)
	_environment.ambient_light_energy = lerpf(0.32, 0.68, day_f) * env_dim + lightning_flash * 0.25
	_environment.background_energy_multiplier = lerpf(0.60, 1.05, day_f)

	var fog_col := horizon.lerp(Color(0.75, 0.84, 0.94), day_f * 0.15)
	if _rain_intensity > 0.1:
		fog_col = fog_col.lerp(Color(0.34, 0.40, 0.46).lerp(Color(0.06, 0.08, 0.12), night_f), _rain_intensity * 0.55)
	if _snow_intensity > 0.1:
		fog_col = fog_col.lerp(Color(0.78, 0.84, 0.90).lerp(Color(0.14, 0.18, 0.25), night_f), _snow_intensity * 0.65)
	fog_col = fog_col.lerp(Color(0.78, 0.88, 1.0), clampf(lightning_flash * 0.45, 0.0, 0.6))

	_environment.fog_light_color = fog_col
	_environment.fog_density = _fog_density + sunset_f * 0.0018 * (1.0 - night_f)
	_environment.fog_height = lerpf(1.2, 4.5, _rain_intensity + _snow_intensity * 0.6)
	_environment.fog_height_density = lerpf(0.015, 0.075, maxf(_rain_intensity, _snow_intensity * 0.8) + sunset_f * 0.35)
	_environment.fog_sky_affect = lerpf(0.32, 0.72, clampf(_fog_density * 80.0, 0.0, 1.0))

	_environment.adjustment_saturation = lerpf(1.06, 0.84, _rain_intensity * 0.75 + _snow_intensity * 0.45)
	_environment.adjustment_brightness = 1.0 + lightning_flash * 0.12

	# Update precipitation & audio subsystems
	if _particles != null and _particles.has_method("update_particles"):
		_particles.call(
			"update_particles",
			anchor,
			_wind_vector,
			_rain_intensity,
			_snow_intensity,
			day_f,
			lightning_flash,
			delta
		)
	if _audio != null and _audio.has_method("update_ambience"):
		_audio.call("update_ambience", _rain_intensity, _snow_intensity, _wind_strength, _gust, delta)
