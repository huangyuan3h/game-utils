extends Node3D
## Camera/player-following precipitation particles:
## - Near high-velocity rain streaks (aligned to wind + fall velocity)
## - Distant translucent rain curtains for valley/sea depth
## - Terrain/water height-conforming splash droplets via MultiMesh
## - Two-layer turbulent drifting snowflakes with soft radial textures

var terrain: Node = null

var _rain_near: GPUParticles3D
var _rain_near_mat: ParticleProcessMaterial
var _rain_near_draw_mat: StandardMaterial3D

var _rain_curtain: GPUParticles3D
var _rain_curtain_mat: ParticleProcessMaterial
var _rain_curtain_draw_mat: StandardMaterial3D

var _snow_near: GPUParticles3D
var _snow_near_mat: ParticleProcessMaterial
var _snow_near_draw_mat: StandardMaterial3D

var _snow_far: GPUParticles3D
var _snow_far_mat: ParticleProcessMaterial
var _snow_far_draw_mat: StandardMaterial3D

var _splash_mm: MultiMeshInstance3D
var _splash_mat: StandardMaterial3D
var _splashes: Array[Dictionary] = []
var _splash_cursor: int = 0
var _splash_spawn_acc: float = 0.0
var _rng := RandomNumberGenerator.new()

const SPLASH_POOL_SIZE := 120


func _ready() -> void:
	_rng.randomize()
	_setup_rain_near()
	_setup_rain_curtain()
	_setup_snow_layers()
	_setup_splashes()


func update_particles(
	anchor_pos: Vector3,
	wind_vec: Vector3,
	rain_intensity: float,
	snow_intensity: float,
	day_factor: float,
	lightning_flash: float,
	delta: float
) -> void:
	var r := clampf(rain_intensity, 0.0, 1.0)
	var s := clampf(snow_intensity, 0.0, 1.0)

	# Anchor rain & snow emitters above the player/camera region.
	var rain_origin := anchor_pos + Vector3(wind_vec.x * -0.4, 15.0, wind_vec.z * -0.4)
	_rain_near.global_position = rain_origin
	_rain_curtain.global_position = anchor_pos + Vector3(wind_vec.x * -0.8, 18.0, wind_vec.z * -0.8)

	var snow_origin := anchor_pos + Vector3(wind_vec.x * -0.8, 11.5, wind_vec.z * -0.8)
	_snow_near.global_position = snow_origin
	_snow_far.global_position = anchor_pos + Vector3(wind_vec.x * -1.2, 14.0, wind_vec.z * -1.2)

	# Rain near streaks
	_rain_near.emitting = r > 0.02
	_rain_near.amount_ratio = clampf(pow(r, 0.85), 0.0, 1.0)
	var fall_speed := lerpf(17.0, 26.0, r)
	var vel_near := Vector3(wind_vec.x * 1.45, -fall_speed, wind_vec.z * 1.45)
	_rain_near_mat.direction = vel_near.normalized()
	_rain_near_mat.initial_velocity_min = vel_near.length() * 0.88
	_rain_near_mat.initial_velocity_max = vel_near.length() * 1.15
	_rain_near_mat.gravity = Vector3(wind_vec.x * 2.5, -14.0, wind_vec.z * 2.5)
	var rain_bright := lerpf(0.36, 0.78, day_factor) + lightning_flash * 0.45
	_rain_near_draw_mat.albedo_color = Color(
		0.76 * rain_bright,
		0.84 * rain_bright,
		0.96 * rain_bright,
		lerpf(0.24, 0.46, r)
	)

	# Distant rain curtains
	_rain_curtain.emitting = r > 0.18
	_rain_curtain.amount_ratio = smoothstep(0.15, 1.0, r)
	var vel_curtain := Vector3(wind_vec.x * 1.2, -lerpf(12.0, 19.0, r), wind_vec.z * 1.2)
	_rain_curtain_mat.direction = vel_curtain.normalized()
	_rain_curtain_mat.initial_velocity_min = vel_curtain.length() * 0.85
	_rain_curtain_mat.initial_velocity_max = vel_curtain.length() * 1.1
	_rain_curtain_draw_mat.albedo_color = Color(
		0.62 * rain_bright,
		0.70 * rain_bright,
		0.82 * rain_bright,
		lerpf(0.05, 0.14, r)
	)

	# Snow layers
	_snow_near.emitting = s > 0.02
	_snow_far.emitting = s > 0.05
	_snow_near.amount_ratio = clampf(pow(s, 0.85), 0.0, 1.0)
	_snow_far.amount_ratio = clampf(s, 0.0, 1.0)
	var snow_drift := Vector3(wind_vec.x * 0.85, -1.65, wind_vec.z * 0.85)
	_snow_near_mat.direction = snow_drift.normalized()
	_snow_near_mat.gravity = Vector3(wind_vec.x * 0.55, -0.45, wind_vec.z * 0.55)
	_snow_far_mat.direction = snow_drift.normalized()
	_snow_far_mat.gravity = Vector3(wind_vec.x * 0.65, -0.55, wind_vec.z * 0.65)
	var snow_bright := lerpf(0.45, 0.98, day_factor) + lightning_flash * 0.3
	_snow_near_draw_mat.albedo_color = Color(0.92 * snow_bright, 0.95 * snow_bright, 1.0 * snow_bright, lerpf(0.65, 0.92, s))
	_snow_far_draw_mat.albedo_color = Color(0.88 * snow_bright, 0.92 * snow_bright, 0.98 * snow_bright, lerpf(0.42, 0.72, s))

	_update_splashes(anchor_pos, r, rain_bright, delta)


func _setup_rain_near() -> void:
	_rain_near = GPUParticles3D.new()
	_rain_near.name = "RainNear"
	_rain_near.amount = 2400
	_rain_near.lifetime = 0.95
	_rain_near.preprocess = 0.5
	_rain_near.emitting = false
	_rain_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_near.visibility_aabb = AABB(Vector3(-28, -28, -28), Vector3(56, 40, 56))

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(16.0, 2.5, 16.0)
	pmat.particle_flag_align_y = true
	pmat.direction = Vector3(0.0, -1.0, 0.0)
	pmat.spread = 4.0
	pmat.initial_velocity_min = 18.0
	pmat.initial_velocity_max = 24.0
	pmat.gravity = Vector3(0.0, -14.0, 0.0)
	pmat.scale_min = 0.75
	pmat.scale_max = 1.25
	_rain_near_mat = pmat
	_rain_near.process_material = pmat

	_rain_near_draw_mat = StandardMaterial3D.new()
	_rain_near_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_near_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_near_draw_mat.albedo_texture = _make_streak_texture(8, 32)
	_rain_near_draw_mat.albedo_color = Color(0.75, 0.85, 0.98, 0.38)
	_rain_near_draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rain_near_draw_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_rain_near.draw_pass_1 = _make_crossed_quad_mesh(0.024, 0.85, _rain_near_draw_mat)
	add_child(_rain_near)


func _setup_rain_curtain() -> void:
	_rain_curtain = GPUParticles3D.new()
	_rain_curtain.name = "RainCurtain"
	_rain_curtain.amount = 320
	_rain_curtain.lifetime = 1.4
	_rain_curtain.preprocess = 0.6
	_rain_curtain.emitting = false
	_rain_curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_curtain.visibility_aabb = AABB(Vector3(-42, -32, -42), Vector3(84, 48, 84))

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(30.0, 3.0, 30.0)
	pmat.particle_flag_align_y = true
	pmat.direction = Vector3(0.0, -1.0, 0.0)
	pmat.spread = 5.0
	pmat.initial_velocity_min = 14.0
	pmat.initial_velocity_max = 18.0
	pmat.gravity = Vector3(0.0, -8.0, 0.0)
	pmat.scale_min = 0.85
	pmat.scale_max = 1.35
	_rain_curtain_mat = pmat
	_rain_curtain.process_material = pmat

	_rain_curtain_draw_mat = StandardMaterial3D.new()
	_rain_curtain_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_curtain_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_curtain_draw_mat.albedo_texture = _make_streak_texture(16, 48)
	_rain_curtain_draw_mat.albedo_color = Color(0.65, 0.72, 0.84, 0.12)
	_rain_curtain_draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rain_curtain_draw_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_rain_curtain.draw_pass_1 = _make_crossed_quad_mesh(0.26, 3.8, _rain_curtain_draw_mat)
	add_child(_rain_curtain)


func _setup_snow_layers() -> void:
	var flake_tex := _make_radial_soft_texture(32)

	# Near larger drifting snowflakes
	_snow_near = GPUParticles3D.new()
	_snow_near.name = "SnowNear"
	_snow_near.amount = 900
	_snow_near.lifetime = 5.5
	_snow_near.preprocess = 2.0
	_snow_near.emitting = false
	_snow_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow_near.visibility_aabb = AABB(Vector3(-24, -22, -24), Vector3(48, 32, 48))

	_snow_near_mat = ParticleProcessMaterial.new()
	_snow_near_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_near_mat.emission_box_extents = Vector3(15.0, 2.5, 15.0)
	_snow_near_mat.direction = Vector3(0.0, -1.0, 0.0)
	_snow_near_mat.spread = 22.0
	_snow_near_mat.initial_velocity_min = 1.1
	_snow_near_mat.initial_velocity_max = 2.1
	_snow_near_mat.gravity = Vector3(0.0, -0.45, 0.0)
	_snow_near_mat.turbulence_enabled = true
	_snow_near_mat.turbulence_noise_strength = 1.6
	_snow_near_mat.turbulence_noise_scale = 2.4
	_snow_near_mat.turbulence_noise_speed_random = 0.5
	_snow_near_mat.scale_min = 0.65
	_snow_near_mat.scale_max = 1.45
	_snow_near.process_material = _snow_near_mat

	_snow_near_draw_mat = StandardMaterial3D.new()
	_snow_near_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snow_near_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_snow_near_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_snow_near_draw_mat.albedo_texture = flake_tex
	_snow_near_draw_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	_snow_near_draw_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q_near := QuadMesh.new()
	q_near.size = Vector2(0.085, 0.085)
	q_near.material = _snow_near_draw_mat
	_snow_near.draw_pass_1 = q_near
	add_child(_snow_near)

	# Far denser fine snow layer
	_snow_far = GPUParticles3D.new()
	_snow_far.name = "SnowFar"
	_snow_far.amount = 1400
	_snow_far.lifetime = 6.5
	_snow_far.preprocess = 2.5
	_snow_far.emitting = false
	_snow_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow_far.visibility_aabb = AABB(Vector3(-34, -26, -34), Vector3(68, 38, 68))

	_snow_far_mat = ParticleProcessMaterial.new()
	_snow_far_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_snow_far_mat.emission_box_extents = Vector3(26.0, 3.5, 26.0)
	_snow_far_mat.direction = Vector3(0.0, -1.0, 0.0)
	_snow_far_mat.spread = 26.0
	_snow_far_mat.initial_velocity_min = 1.4
	_snow_far_mat.initial_velocity_max = 2.6
	_snow_far_mat.gravity = Vector3(0.0, -0.55, 0.0)
	_snow_far_mat.turbulence_enabled = true
	_snow_far_mat.turbulence_noise_strength = 2.1
	_snow_far_mat.turbulence_noise_scale = 1.8
	_snow_far_mat.scale_min = 0.6
	_snow_far_mat.scale_max = 1.2
	_snow_far.process_material = _snow_far_mat

	_snow_far_draw_mat = StandardMaterial3D.new()
	_snow_far_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snow_far_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_snow_far_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_snow_far_draw_mat.albedo_texture = flake_tex
	_snow_far_draw_mat.albedo_color = Color(0.90, 0.94, 0.99, 0.60)
	_snow_far_draw_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q_far := QuadMesh.new()
	q_far.size = Vector2(0.055, 0.055)
	q_far.material = _snow_far_draw_mat
	_snow_far.draw_pass_1 = q_far
	add_child(_snow_far)


func _setup_splashes() -> void:
	_splash_mm = MultiMeshInstance3D.new()
	_splash_mm.name = "RainSplashes"
	_splash_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_splash_mat = StandardMaterial3D.new()
	_splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_splash_mat.vertex_color_use_as_albedo = true
	_splash_mat.albedo_texture = _make_ring_texture(32)
	_splash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_splash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	var plane := PlaneMesh.new()
	plane.size = Vector2(0.24, 0.24)
	plane.material = _splash_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	mm.instance_count = SPLASH_POOL_SIZE
	for i in SPLASH_POOL_SIZE:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
		mm.set_instance_color(i, Color(1, 1, 1, 0))
		_splashes.append({"age": 99.0, "life": 0.22, "pos": Vector3.ZERO})

	_splash_mm.multimesh = mm
	add_child(_splash_mm)


func _update_splashes(anchor_pos: Vector3, rain_intensity: float, rain_bright: float, delta: float) -> void:
	var mm := _splash_mm.multimesh
	if mm == null:
		return
	if rain_intensity <= 0.04:
		_splash_mm.visible = false
		return
	_splash_mm.visible = true

	var spawn_rate := lerpf(35.0, 260.0, pow(rain_intensity, 1.1))
	_splash_spawn_acc += spawn_rate * delta
	var to_spawn := mini(int(_splash_spawn_acc), 18)
	_splash_spawn_acc -= float(to_spawn)

	for _k in to_spawn:
		var ang := _rng.randf_range(0.0, TAU)
		var rad := sqrt(_rng.randf()) * 14.0
		var wx := anchor_pos.x + cos(ang) * rad
		var wz := anchor_pos.z + sin(ang) * rad
		var wy := 0.0
		if terrain != null:
			if terrain.has_method("sample_height"):
				wy = float(terrain.call("sample_height", wx, wz))
			if terrain.has_method("sample_water_surface"):
				var water_y := float(terrain.call("sample_water_surface", wx, wz))
				if water_y > wy:
					wy = water_y
		var slot := _splashes[_splash_cursor]
		slot["pos"] = Vector3(wx, wy + 0.025, wz)
		slot["age"] = 0.0
		slot["life"] = _rng.randf_range(0.16, 0.28)
		_splash_cursor = (_splash_cursor + 1) % SPLASH_POOL_SIZE

	for i in SPLASH_POOL_SIZE:
		var slot := _splashes[i]
		var age: float = float(slot["age"]) + delta
		var life: float = float(slot["life"])
		slot["age"] = age
		if age >= life:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(0.0001, 0.0001, 0.0001)), Vector3.ZERO))
			mm.set_instance_color(i, Color(1, 1, 1, 0))
		else:
			var u := age / life
			var s := lerpf(0.25, 1.35, u)
			var alpha := (1.0 - u) * lerpf(0.35, 0.68, rain_intensity)
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(s, 1.0, s)), slot["pos"])
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, Color(0.82 * rain_bright, 0.90 * rain_bright, 1.0 * rain_bright, alpha))


func _make_crossed_quad_mesh(width: float, height: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var hh := height * 0.5
	var quads := [
		[Vector3(-hw, -hh, 0.0), Vector3(hw, -hh, 0.0), Vector3(hw, hh, 0.0), Vector3(-hw, hh, 0.0)],
		[Vector3(0.0, -hh, -hw), Vector3(0.0, -hh, hw), Vector3(0.0, hh, hw), Vector3(0.0, hh, -hw)],
	]
	for q in quads:
		st.set_uv(Vector2(0, 1))
		st.add_vertex(q[0])
		st.set_uv(Vector2(1, 1))
		st.add_vertex(q[1])
		st.set_uv(Vector2(1, 0))
		st.add_vertex(q[2])
		st.set_uv(Vector2(0, 1))
		st.add_vertex(q[0])
		st.set_uv(Vector2(1, 0))
		st.add_vertex(q[2])
		st.set_uv(Vector2(0, 0))
		st.add_vertex(q[3])
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


func _make_streak_texture(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var vy := float(y) / float(maxi(h - 1, 1))
		var v_fade := sin(vy * PI)
		v_fade = pow(v_fade, 0.7)
		for x in w:
			var vx := (float(x) / float(maxi(w - 1, 1))) * 2.0 - 1.0
			var h_fade := clampf(1.0 - vx * vx, 0.0, 1.0)
			var a := v_fade * h_fade
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _make_radial_soft_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - smoothstep(0.15, 1.0, r), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)


func _make_ring_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var ring := exp(-pow((r - 0.68) / 0.18, 2.0))
			var center := exp(-pow(r / 0.25, 2.0)) * 0.45
			var edge_clip := 1.0 - smoothstep(0.85, 1.0, r)
			var a := clampf((ring + center) * edge_clip, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
