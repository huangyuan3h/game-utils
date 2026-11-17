class_name HandToolVisual
extends Node3D
## Attaches procedural low-poly tools (Pickaxe, Axe, Hammer) to the character's
## RightHand bone via BoneAttachment3D and spawns brief impact spark bursts on hits.

var _attachment: BoneAttachment3D = null
var _tool_holder: Node3D = null
var _tools: Dictionary = {} ## int (CharacterActionSpec.ToolType) -> MeshInstance3D
var _active_tool: int = CharacterActionSpec.ToolType.NONE


func bind_skeleton(skeleton: Skeleton3D) -> void:
	cleanup()
	if skeleton == null:
		return
	var hand_idx := skeleton.find_bone("RightHand")
	if hand_idx < 0:
		return

	_attachment = BoneAttachment3D.new()
	_attachment.name = "RightHandToolAttachment"
	_attachment.bone_name = "RightHand"
	skeleton.add_child(_attachment)

	_tool_holder = Node3D.new()
	_tool_holder.name = "ToolHolder"
	# Compensate for parent rig/armature scaling so tool dimensions are in world meters.
	var skel_scale := _estimate_skeleton_scale(skeleton)
	var inv := 1.0 / maxf(skel_scale, 0.01)
	_tool_holder.scale = Vector3.ONE * inv
	# Position slightly in palm and orient handle perpendicular to +Y finger extension.
	_tool_holder.position = Vector3(0.0, 0.0018, 0.0)
	_tool_holder.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_attachment.add_child(_tool_holder)

	_tools[CharacterActionSpec.ToolType.PICKAXE] = _make_tool_node("Pickaxe", _build_pickaxe_mesh())
	_tools[CharacterActionSpec.ToolType.AXE] = _make_tool_node("Axe", _build_axe_mesh())
	_tools[CharacterActionSpec.ToolType.HAMMER] = _make_tool_node("Hammer", _build_hammer_mesh())
	for tool_node: Node3D in _tools.values():
		tool_node.visible = false
		_tool_holder.add_child(tool_node)

	set_active_tool(_active_tool)


func set_active_tool(tool_type: int) -> void:
	_active_tool = tool_type
	for key in _tools.keys():
		var mi := _tools[key] as Node3D
		if mi != null:
			mi.visible = (int(key) == tool_type)


func spawn_impact_burst(action_id: StringName, visual_root: Node3D) -> void:
	if visual_root == null or not visual_root.is_inside_tree():
		return
	var world_pos := _get_tip_world_pos()
	if world_pos == Vector3.ZERO:
		world_pos = visual_root.global_position + visual_root.global_basis * Vector3(0.0, 0.65, 0.65)

	var col := Color(0.95, 0.85, 0.45)
	match action_id:
		&"gather":
			col = Color(0.45, 0.85, 0.35)
		&"mine":
			col = Color(0.85, 0.92, 1.0)
		&"chop":
			col = Color(0.76, 0.52, 0.26)
		&"build":
			col = Color(1.0, 0.78, 0.30)

	var fx_root := visual_root.get_tree().current_scene
	if fx_root == null:
		return

	var particles := CPUParticles3D.new()
	particles.name = "ActionHitBurst"
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.amount = 10
	particles.lifetime = 0.36
	particles.emitting = true
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 65.0
	particles.initial_velocity_min = 1.6
	particles.initial_velocity_max = 3.2
	particles.gravity = Vector3(0.0, -9.8, 0.0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2

	var box := BoxMesh.new()
	box.size = Vector3(0.055, 0.055, 0.055)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.65
	mat.roughness = 0.6
	box.material = mat
	particles.mesh = box

	fx_root.add_child(particles)
	particles.global_position = world_pos
	var timer := fx_root.get_tree().create_timer(0.6)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)


func cleanup() -> void:
	if _attachment != null and is_instance_valid(_attachment):
		_attachment.queue_free()
	_attachment = null
	_tool_holder = null
	_tools.clear()


func _get_tip_world_pos() -> Vector3:
	if _tool_holder != null and is_instance_valid(_tool_holder) and _tool_holder.is_inside_tree():
		return _tool_holder.to_global(Vector3(0.0, 0.55, 0.0))
	return Vector3.ZERO


func _estimate_skeleton_scale(skeleton: Skeleton3D) -> float:
	if skeleton.is_inside_tree():
		var s := skeleton.global_basis.get_scale()
		return (absf(s.x) + absf(s.y) + absf(s.z)) / 3.0
	var accum := 1.0
	var cur: Node = skeleton
	while cur != null:
		if cur is Node3D:
			var sc := (cur as Node3D).scale
			accum *= (absf(sc.x) + absf(sc.y) + absf(sc.z)) / 3.0
		cur = cur.get_parent()
	return accum


func _make_tool_node(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.65
	mat.metallic = 0.15
	mi.material_override = mat
	return mi


func _build_pickaxe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.46, 0.30, 0.16)
	var iron := Color(0.62, 0.67, 0.74)
	_add_box(st, Vector3(0.0, 0.24, 0.0), Vector3(0.045, 0.68, 0.045), wood)
	_add_box(st, Vector3(0.0, 0.54, 0.0), Vector3(0.08, 0.08, 0.28), iron)
	_add_box(st, Vector3(0.0, 0.50, 0.19), Vector3(0.05, 0.05, 0.18), iron.lightened(0.08))
	_add_box(st, Vector3(0.0, 0.50, -0.19), Vector3(0.05, 0.05, 0.18), iron.lightened(0.08))
	st.generate_normals()
	return st.commit()


func _build_axe_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.48, 0.31, 0.16)
	var steel := Color(0.74, 0.78, 0.84)
	_add_box(st, Vector3(0.0, 0.24, 0.0), Vector3(0.045, 0.66, 0.045), wood)
	_add_box(st, Vector3(0.0, 0.52, 0.08), Vector3(0.05, 0.14, 0.20), steel.darkened(0.15))
	_add_box(st, Vector3(0.0, 0.52, 0.19), Vector3(0.025, 0.18, 0.07), steel)
	st.generate_normals()
	return st.commit()


func _build_hammer_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.50, 0.34, 0.18)
	var head := Color(0.54, 0.56, 0.62)
	_add_box(st, Vector3(0.0, 0.18, 0.0), Vector3(0.042, 0.46, 0.042), wood)
	_add_box(st, Vector3(0.0, 0.41, 0.02), Vector3(0.10, 0.10, 0.22), head)
	st.generate_normals()
	return st.commit()


func _add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var v := [
		center + Vector3(-hx, -hy, -hz), # 0
		center + Vector3( hx, -hy, -hz), # 1
		center + Vector3( hx,  hy, -hz), # 2
		center + Vector3(-hx,  hy, -hz), # 3
		center + Vector3(-hx, -hy,  hz), # 4
		center + Vector3( hx, -hy,  hz), # 5
		center + Vector3( hx,  hy,  hz), # 6
		center + Vector3(-hx,  hy,  hz), # 7
	]
	var quads := [
		[0, 1, 2, 3], # -Z
		[5, 4, 7, 6], # +Z
		[4, 0, 3, 7], # -X
		[1, 5, 6, 2], # +X
		[3, 2, 6, 7], # +Y
		[4, 5, 1, 0], # -Y
	]
	for q in quads:
		st.set_color(col); st.add_vertex(v[q[0]])
		st.set_color(col); st.add_vertex(v[q[1]])
		st.set_color(col); st.add_vertex(v[q[2]])
		st.set_color(col); st.add_vertex(v[q[0]])
		st.set_color(col); st.add_vertex(v[q[2]])
		st.set_color(col); st.add_vertex(v[q[3]])
