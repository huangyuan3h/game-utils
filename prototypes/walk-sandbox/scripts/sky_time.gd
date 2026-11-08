extends Node3D
## Day/night time system: sun, moon, stars, clouds, simple weather.
## T — cycle time speed · Y — cycle weather

enum Weather { CLEAR, CLOUDY, OVERCAST, RAIN }

const SPEEDS := [1.0, 30.0, 120.0, 600.0]  # game-seconds per real-second scale on hours
const SPEED_LABELS := ["1×", "30×", "120×", "600×"]

## One real second at 1× advances this many in-game hours.
const HOURS_PER_REAL_SECOND_AT_1X := 1.0 / 60.0  # 1 real min ≈ 1 game hour at 1×? too fast
# Prefer: at 1×, a full day takes 20 real minutes → 24h / 1200s = 0.02 h/s
const BASE_HOURS_PER_SECOND := 0.02

@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _sun_light: DirectionalLight3D = $SunLight
@onready var _moon_light: DirectionalLight3D = $MoonLight
@onready var _sun_disc: MeshInstance3D = $SunDisc
@onready var _moon_disc: MeshInstance3D = $MoonDisc
@onready var _stars: MultiMeshInstance3D = $Stars
@onready var _clouds: Node3D = $Clouds
@onready var _rain: GPUParticles3D = $Rain

var hour: float = 8.0  # start mid-morning
var speed_index: int = 0
var weather: Weather = Weather.CLEAR
var _sky: ProceduralSkyMaterial
var _cloud_mats: Array[StandardMaterial3D] = []
var _cloud_bases: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_bind_keys()
	_setup_sky()
	_setup_stars()
	_setup_clouds()
	_setup_rain()
	_apply_visuals(0.0)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("time_speed"):
		speed_index = (speed_index + 1) % SPEEDS.size()
	if Input.is_action_just_pressed("weather_cycle"):
		weather = ((int(weather) + 1) % 4) as Weather
		_refresh_weather_nodes()

	hour = fposmod(hour + BASE_HOURS_PER_SECOND * SPEEDS[speed_index] * delta, 24.0)
	_apply_visuals(delta)


func get_hud_line() -> String:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	var phase := _phase_name()
	var wnames := ["Clear", "Cloudy", "Overcast", "Rain"]
	return "Time %02d:%02d (%s) · speed %s [T] · weather %s [Y]" % [
		h, m, phase, SPEED_LABELS[speed_index], wnames[int(weather)]
	]


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


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _setup_sky() -> void:
	_sky = ProceduralSkyMaterial.new()
	_sky.sky_curve = 0.08
	_sky.ground_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = _sky
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.adjustment_enabled = true
	_env.environment = environment


func _setup_stars() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.95, 1.0)
	mat.emission_energy_multiplier = 2.5
	mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 220
	for i in mm.instance_count:
		var dir := Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(0.05, 1.0),
			_rng.randf_range(-1.0, 1.0)
		).normalized()
		var dist := _rng.randf_range(70.0, 95.0)
		var xf := Transform3D(Basis.IDENTITY, dir * dist)
		var s := _rng.randf_range(0.35, 1.4)
		xf.basis = xf.basis.scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, xf)
	_stars.multimesh = mm


func _setup_clouds() -> void:
	for c in _clouds.get_children():
		c.queue_free()
	_cloud_mats.clear()
	_cloud_bases.clear()
	for i in 10:
		var cloud := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = _rng.randf_range(2.2, 4.5)
		sphere.height = sphere.radius * _rng.randf_range(0.55, 0.85)
		cloud.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.55)
		mat.roughness = 1.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		cloud.material_override = mat
		var base := Vector3(
			_rng.randf_range(-80.0, 80.0),
			_rng.randf_range(14.0, 28.0),
			_rng.randf_range(-80.0, 80.0)
		)
		cloud.position = base
		cloud.scale = Vector3(_rng.randf_range(1.5, 3.2), 0.55, _rng.randf_range(1.2, 2.6))
		_clouds.add_child(cloud)
		_cloud_mats.append(mat)
		_cloud_bases.append(base)
	_refresh_weather_nodes()


func _setup_rain() -> void:
	_rain.emitting = false
	_rain.amount = 900
	_rain.lifetime = 0.9
	_rain.visibility_aabb = AABB(Vector3(-70, 0, -70), Vector3(140, 50, 140))
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.15, -1, 0.05)
	mat.spread = 8.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 16.0
	mat.gravity = Vector3(0, -2, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.05
	mat.color = Color(0.7, 0.8, 0.95, 0.55)
	_rain.process_material = mat
	var draw := SphereMesh.new()
	draw.radius = 0.03
	draw.height = 0.08
	_rain.draw_pass_1 = draw


func _refresh_weather_nodes() -> void:
	_rain.emitting = weather == Weather.RAIN


func _sun_elevation_rad() -> float:
	# 6:00 rise, 12:00 zenith, 18:00 set
	return sin((hour / 24.0 - 0.25) * TAU)


## Avoid look_at(…, UP) when the view direction is nearly vertical (noon/midnight).
func _safe_look_at(node: Node3D, target: Vector3) -> void:
	var to_target := target - node.global_position
	if to_target.length_squared() < 0.0001:
		return
	var forward := to_target.normalized()
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.95:
		up = Vector3.RIGHT
	node.look_at(target, up)


func _apply_visuals(delta: float) -> void:
	var elev := _sun_elevation_rad()
	var day_f := clampf(elev * 1.15 + 0.15, 0.0, 1.0)  # soft day amount
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

	# Lights: Godot DirectionalLight shines along -Z
	_sun_light.global_position = sun_dir * 40.0
	_safe_look_at(_sun_light, Vector3.ZERO)
	_moon_light.global_position = -sun_dir * 40.0
	_safe_look_at(_moon_light, Vector3.ZERO)

	var cloud_dim := 1.0
	match weather:
		Weather.CLEAR:
			cloud_dim = 1.0
		Weather.CLOUDY:
			cloud_dim = 0.75
		Weather.OVERCAST, Weather.RAIN:
			cloud_dim = 0.45

	_sun_light.light_energy = maxf(elev, 0.0) * 1.35 * cloud_dim
	_sun_light.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.55, 0.25), sunset_f)
	_sun_light.shadow_enabled = elev > 0.02
	_moon_light.light_energy = night_f * 0.28
	_moon_light.light_color = Color(0.65, 0.75, 1.0)

	_sun_disc.visible = elev > -0.05
	_sun_disc.global_position = sun_dir * 85.0
	_safe_look_at(_sun_disc, Vector3.ZERO)
	var sun_mat := _sun_disc.material_override as StandardMaterial3D
	if sun_mat:
		sun_mat.emission = Color(1.0, 0.92, 0.55).lerp(Color(1.0, 0.4, 0.15), sunset_f)
		sun_mat.emission_energy_multiplier = 3.0 + sunset_f * 2.0
		sun_mat.albedo_color = sun_mat.emission

	_moon_disc.visible = night_f > 0.25
	_moon_disc.global_position = -sun_dir * 80.0
	_safe_look_at(_moon_disc, Vector3.ZERO)

	_stars.transparency = 1.0 - night_f * 0.95
	_stars.visible = night_f > 0.05

	# Sky colors
	var day_top := Color(0.28, 0.55, 0.92)
	var day_horizon := Color(0.72, 0.85, 0.95)
	var sunset_top := Color(0.25, 0.22, 0.45)
	var sunset_horizon := Color(1.0, 0.45, 0.25)
	var night_top := Color(0.02, 0.03, 0.08)
	var night_horizon := Color(0.05, 0.07, 0.14)

	var top := day_top.lerp(night_top, night_f).lerp(sunset_top, sunset_f * day_f)
	var horizon := day_horizon.lerp(night_horizon, night_f).lerp(sunset_horizon, sunset_f)
	if weather == Weather.OVERCAST or weather == Weather.RAIN:
		top = top.lerp(Color(0.35, 0.38, 0.42), 0.55)
		horizon = horizon.lerp(Color(0.45, 0.47, 0.5), 0.5)
	elif weather == Weather.CLOUDY:
		top = top.lerp(Color(0.4, 0.5, 0.65), 0.25)

	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon.darkened(0.15)
	_sky.ground_bottom_color = Color(0.12, 0.16, 0.1).lerp(Color(0.02, 0.03, 0.05), night_f)
	_sky.sky_energy_multiplier = lerpf(0.35, 1.15, day_f) * cloud_dim
	_env.environment.ambient_light_energy = lerpf(0.18, 0.65, day_f) * cloud_dim
	_env.environment.background_energy_multiplier = lerpf(0.4, 1.0, day_f)

	# Drift clouds
	var wind: Vector3 = Vector3(1.2, 0, 0.35) * (1.0 + SPEEDS[speed_index] * 0.002)
	var cloud_alpha := 0.0
	match weather:
		Weather.CLEAR:
			cloud_alpha = 0.25
		Weather.CLOUDY:
			cloud_alpha = 0.55
		Weather.OVERCAST:
			cloud_alpha = 0.78
		Weather.RAIN:
			cloud_alpha = 0.7
	for i in _clouds.get_child_count():
		var cloud := _clouds.get_child(i) as MeshInstance3D
		if cloud == null:
			continue
		cloud.position += wind * delta
		if cloud.position.x > 90.0:
			cloud.position.x = -90.0
		if cloud.position.z > 90.0:
			cloud.position.z = -90.0
		if cloud.position.x < -90.0:
			cloud.position.x = 90.0
		if cloud.position.z < -90.0:
			cloud.position.z = 90.0
		var mat := _cloud_mats[i] if i < _cloud_mats.size() else null
		if mat:
			var tint := Color(1, 1, 1).lerp(Color(0.45, 0.48, 0.52), 0.0 if weather == Weather.CLEAR else 0.55)
			if weather == Weather.RAIN:
				tint = Color(0.4, 0.42, 0.46)
			mat.albedo_color = Color(tint.r, tint.g, tint.b, cloud_alpha * lerpf(0.35, 1.0, day_f + 0.2))
		cloud.visible = cloud_alpha > 0.05

	# Keep rain over the playable ground (follow origin; fine for sandbox)
	_rain.position = Vector3(0, 18, 0)
