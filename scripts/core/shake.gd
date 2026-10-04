class_name Shake
extends RefCounted
## Un sacudón corto de lado a lado: la forma de decir "no se puede" sin decir nada más.

const SECONDS := 0.15
const DISTANCE := 0.06


## Sólo mueve la x local de `target`, ida y vuelta alrededor de `rest_x`, y la deja ahí. Devuelve
## el tween para que quien sacude lo corte si vuelve a sacudir antes de que termine.
static func sideways(target: Node3D, rest_x: float) -> Tween:
	var shake := target.create_tween()
	shake.tween_property(target, "position:x", rest_x + DISTANCE, SECONDS / 4.0)
	shake.tween_property(target, "position:x", rest_x - DISTANCE, SECONDS / 2.0)
	shake.tween_property(target, "position:x", rest_x, SECONDS / 4.0)
	return shake
