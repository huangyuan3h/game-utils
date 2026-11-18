class_name Hurtbox
extends Node3D
## Receives hits for one faction and forwards damage to HealthComponent.

signal hit_received(amount: float, source: Node, knockback: Vector3)

@export var faction: StringName = &"neutral"

var health: HealthComponent = null


func receive(amount: float, source: Node, knockback: Vector3, crit: bool) -> float:
	if health == null or amount <= 0.0:
		return 0.0
	var applied := health.apply_damage(amount, source)
	if applied <= 0.0:
		return 0.0
	hit_received.emit(applied, source, knockback)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_method("emit_event"):
		bus.call("emit_event", &"combat_hit", {
			"amount": applied,
			"crit": crit,
			"knockback": knockback,
			"source": source,
		})
	return applied
