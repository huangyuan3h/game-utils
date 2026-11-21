class_name NightHeadlight
extends OmniLight3D
## Auto-fading character headlamp driven by sky_time.get_night_factor().


func _ready() -> void:
	name = "HeadLight"
	light_color = Color(1.0, 0.92, 0.78)
	light_energy = 0.0
	omni_range = 12.0
	omni_attenuation = 1.4
	shadow_enabled = false
	position = Vector3(0.0, 1.85, 0.12)
	visible = false


func update_from_sky(sky_time: Object, delta: float) -> void:
	var night := 0.0
	if sky_time != null and sky_time.has_method("get_night_factor"):
		night = float(sky_time.call("get_night_factor"))
	var target := 0.0
	if night > 0.35:
		target = lerpf(0.0, 2.4, smoothstep(0.35, 0.85, night))
	light_energy = move_toward(light_energy, target, 4.0 * delta)
	visible = light_energy > 0.02
