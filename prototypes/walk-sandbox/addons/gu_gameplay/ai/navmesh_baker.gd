class_name NavMeshBaker
extends RefCounted
## Bakes a NavigationMesh at runtime from a single ground MeshInstance3D.
## Reading the CPU mesh arrays avoids the GPU readback that `add_mesh` triggers.

const DEFAULT_CELL_SIZE := 0.6


static func bake(
	region: NavigationRegion3D,
	ground: MeshInstance3D,
	cell_size: float = DEFAULT_CELL_SIZE,
	max_slope_deg: float = 45.0
) -> bool:
	if region == null or ground == null or ground.mesh == null:
		return false
	var mesh := ground.mesh
	if mesh.get_surface_count() == 0:
		return false

	var cell := maxf(0.2, cell_size)
	var nav := NavigationMesh.new()
	nav.cell_size = cell
	nav.cell_height = cell * 0.5
	nav.agent_radius = cell
	nav.agent_height = maxf(1.2, cell * 3.0)
	nav.agent_max_climb = cell
	nav.agent_max_slope = clampf(max_slope_deg, 1.0, 89.0)
	nav.region_min_size = cell * 4.0

	var source := NavigationMeshSourceGeometryData3D.new()
	var xform := ground.global_transform
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if raw_indices == null or (raw_indices as PackedInt32Array).is_empty():
			var sequential := PackedInt32Array()
			sequential.resize(vertices.size())
			for i in vertices.size():
				sequential[i] = i
			arrays[Mesh.ARRAY_INDEX] = sequential
		source.add_mesh_array(arrays, xform)

	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	if nav.get_polygon_count() == 0:
		return false
	region.navigation_mesh = nav
	region.enabled = true
	return true
