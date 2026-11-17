extends Node3D
## Procedural 3D forked lightning system for storms.
## Generates jagged multi-branch ribbons, multi-pulse flash envelopes,
## directional ground illumination, and emits thunder distance events.

signal strike_triggered(distance_m: float, intensity: float)

var terrain: Node = null
var lightning_light: DirectionalLight3D = null

var flash_intensity: float = 0.0
var flash_direction: Vector3 = Vector3(0.0, 0.5, -1.0)

var _mesh_instance: MeshInstance3D
var _bolt_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

var _storm_amount: float = 0.0
var _cooldown: float = 1.5
var _pulse_age: float = 99.0
var _pulse_duration: float = 0.35
var _pulse_peaks: Array[float] = [0.0, 0.11]
var _current_strength: float = 1.0


func _ready() -> void:
	_rng.randomize()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "BoltMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visible = false
	add_child(_mesh_instance)

	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.albedo_color = Color(0.92, 0.96, 1.0, 1.0)
	_bolt_mat.emission_enabled = true
	_bolt_mat.emission = Color(0.72, 0.86, 1.0)
	_bolt_mat.emission_energy_multiplier = 10.0
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = _bolt_mat


func update_storm(storm_amount: float, anchor_pos: Vector3, delta: float) -> void:
	_storm_amount = clampf(storm_amount, 0.0, 1.0)

	if _pulse_age < _pulse_duration:
		_pulse_age += delta
		var env := _evaluate_pulse(_pulse_age / _pulse_duration)
		flash_intensity = env * _current_strength
		_mesh_instance.visible = env > 0.08
		_bolt_mat.albedo_color.a = clampf(env * 1.1, 0.0, 1.0)
		_bolt_mat.emission_energy_multiplier = 4.0 + env * 10.0
	else:
		flash_intensity = move_toward(flash_intensity, 0.0, delta * 12.0)
		_mesh_instance.visible = false

	_update_light()

	if _storm_amount < 0.35:
		_cooldown = minf(_cooldown, 1.4)
		return

	_cooldown -= delta
	if _cooldown <= 0.0:
		_spawn_strike(anchor_pos)
		var min_wait := lerpf(7.5, 2.8, _storm_amount)
		var max_wait := lerpf(13.0, 6.8, _storm_amount)
		_cooldown = _rng.randf_range(min_wait, max_wait)


func trigger_now(anchor_pos: Vector3) -> void:
	_spawn_strike(anchor_pos)


func _evaluate_pulse(u: float) -> float:
	if u < 0.0 or u >= 1.0:
		return 0.0
	var val := 0.0
	for p in _pulse_peaks.size():
		var dt := u - _pulse_peaks[p]
		if dt >= 0.0:
			var amp := 1.0 if p == 0 else 0.78 / float(p)
			val = maxf(val, amp * exp(-dt * 12.5))
	return clampf(val, 0.0, 1.0)


func _update_light() -> void:
	if lightning_light == null:
		return
	lightning_light.light_energy = flash_intensity * 3.6
	lightning_light.light_color = Color(0.78, 0.88, 1.0)
	lightning_light.visible = flash_intensity > 0.02
	if lightning_light.visible:
		var look_src := flash_direction * 45.0
		lightning_light.global_position = look_src
		var up := Vector3.UP
		if absf(flash_direction.normalized().dot(up)) > 0.95:
			up = Vector3.RIGHT
		lightning_light.look_at(Vector3.ZERO, up)


func _spawn_strike(anchor_pos: Vector3) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(34.0, 105.0)
	var strike_xz := Vector2(anchor_pos.x + cos(angle) * dist, anchor_pos.z + sin(angle) * dist)
	var ground_y := 0.0
	if terrain != null and terrain.has_method("sample_height"):
		ground_y = float(terrain.call("sample_height", strike_xz.x, strike_xz.y))

	# Mix cloud-to-ground bolts and higher in-cloud/horizon bolts.
	var cloud_to_ground := _rng.randf() < 0.72
	var start_pos := Vector3(
		strike_xz.x + _rng.randf_range(-10.0, 10.0),
		_rng.randf_range(52.0, 68.0),
		strike_xz.y + _rng.randf_range(-10.0, 10.0)
	)
	var end_pos := Vector3(strike_xz.x, ground_y - 0.5, strike_xz.y) if cloud_to_ground else Vector3(
		strike_xz.x + _rng.randf_range(-26.0, 26.0),
		_rng.randf_range(24.0, 38.0),
		strike_xz.y + _rng.randf_range(-26.0, 26.0)
	)

	_mesh_instance.mesh = _build_forked_bolt_mesh(start_pos, end_pos)
	_mesh_instance.visible = true

	var mid_pos := start_pos.lerp(end_pos, 0.35)
	var rel := mid_pos - anchor_pos
	flash_direction = rel.normalized() if rel.length_squared() > 0.01 else Vector3(0.0, 0.5, -1.0)
	_current_strength = _rng.randf_range(0.85, 1.35)
	_pulse_duration = _rng.randf_range(0.28, 0.44)
	_pulse_age = 0.0

	if _rng.randf() < 0.55:
		_pulse_peaks = [0.0, _rng.randf_range(0.22, 0.36), _rng.randf_range(0.48, 0.64)]
	else:
		_pulse_peaks = [0.0, _rng.randf_range(0.25, 0.45)]

	var strike_dist := anchor_pos.distance_to(end_pos)
	strike_triggered.emit(strike_dist, _current_strength)


func _build_forked_bolt_mesh(start_pos: Vector3, end_pos: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var main_pts := _subdivide_bolt(start_pos, end_pos, 4, 6.2)
	_add_ribbon_chain(st, main_pts, 0.32, 0.14)

	# Spawn 2..4 secondary branches from upper/mid segments.
	var branch_count := _rng.randi_range(2, 4)
	for _b in branch_count:
		var idx := _rng.randi_range(2, maxi(2, main_pts.size() - 5))
		var b_start := main_pts[idx]
		var remaining := (end_pos.y - b_start.y)
		var b_dir := Vector3(
			_rng.randf_range(-16.0, 16.0),
			remaining * _rng.randf_range(0.45, 0.85),
			_rng.randf_range(-16.0, 16.0)
		)
		var b_pts := _subdivide_bolt(b_start, b_start + b_dir, 3, 2.8)
		_add_ribbon_chain(st, b_pts, 0.14, 0.03)

	return st.commit()


func _subdivide_bolt(a: Vector3, b: Vector3, iterations: int, max_jitter: float) -> PackedVector3Array:
	var pts: Array[Vector3] = [a, b]
	var jitter := max_jitter
	for _it in iterations:
		var next: Array[Vector3] = []
		for i in range(pts.size() - 1):
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var mid := (p0 + p1) * 0.5
			mid.x += _rng.randf_range(-jitter, jitter)
			mid.z += _rng.randf_range(-jitter, jitter)
			mid.y += _rng.randf_range(-jitter * 0.25, jitter * 0.25)
			next.append(p0)
			next.append(mid)
		next.append(pts[pts.size() - 1])
		pts = next
		jitter *= 0.52
	return PackedVector3Array(pts)


func _add_ribbon_chain(st: SurfaceTool, pts: PackedVector3Array, width_start: float, width_end: float) -> void:
	if pts.size() < 2:
		return
	var count := pts.size()
	for i in range(count - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var seg := p1 - p0
		if seg.length_squared() < 1e-6:
			continue
		var dir := seg.normalized()
		var side_a := dir.cross(Vector3.RIGHT)
		if side_a.length_squared() < 1e-4:
			side_a = dir.cross(Vector3.FORWARD)
		side_a = side_a.normalized()
		var side_b := dir.cross(side_a).normalized()

		var t0 := float(i) / float(count - 1)
		var t1 := float(i + 1) / float(count - 1)
		var w0 := lerpf(width_start, width_end, t0)
		var w1 := lerpf(width_start, width_end, t1)

		# Two crossed orthogonal quads ensure visibility from every camera azimuth.
		for axis: Vector3 in [side_a, side_b]:
			var a0 := p0 - axis * w0
			var b0 := p0 + axis * w0
			var a1 := p1 - axis * w1
			var b1 := p1 + axis * w1
			st.add_vertex(a0)
			st.add_vertex(b0)
			st.add_vertex(b1)
			st.add_vertex(a0)
			st.add_vertex(b1)
			st.add_vertex(a1)
