class_name Hitbox
extends Node3D
## Applies a filtered hit to a Hurtbox. Same-faction targets are ignored.

signal hit_landed(amount: float, crit: bool)

@export var faction: StringName = &"enemy"
@export var damage: float = 10.0
@export var crit_multiplier: float = 2.0
@export var knockback_strength: float = 1.0


func strike(target, crit: bool = false, direction: Vector3 = Vector3.FORWARD) -> float:
	if target == null or (faction != &"" and faction == target.faction):
		return 0.0
	var amount := damage * (crit_multiplier if crit else 1.0)
	var impulse := direction.normalized() * knockback_strength
	if direction.length_squared() <= 0.0001:
		impulse = Vector3.ZERO
	var applied: float = target.receive(amount, self, impulse, crit)
	if applied > 0.0:
		hit_landed.emit(applied, crit)
	return applied
