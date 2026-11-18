class_name ShaderWarmup
extends Node3D
## Instances hidden materials and a particle system for one frame so common shader variants compile before play.

var warmed: bool = false


func add_shader(shader: Shader) -> void:
	if shader == null:
		return
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	mesh.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mesh.material_override = mat
	add_child(mesh)


func _ready() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "WarmupParticles"
	particles.amount = 1
	particles.emitting = true
	add_child(particles)
	visible = false


func _process(_delta: float) -> void:
	if warmed:
		return
	warmed = true
	queue_free()
