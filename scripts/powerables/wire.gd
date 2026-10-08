@tool
class_name Wire
extends Powerable

const TRANSMITS := true

const DOT_RADIUS := 0.045
const DOT_THICKNESS := 0.012
const DOT_SPACING := 0.2
const DOTS_PER_ARM := 2

const LIFT := 0.004 # Razón por la que los cables de pared se ven en 2D, pero si no se los come la textura de las cajas
const DARK := Color(0.09, 0.09, 0.1)

var _dots := StandardMaterial3D.new()


func activation_condition(active_neighbours: Array[Powerable], _pressed: bool) -> bool:
	return Powerable.powered(active_neighbours)


func turn_on() -> void:
	_paint(_dots, LIT_RED, true)

func turn_off() -> void:
	_paint(_dots, DARK, false)


func _build_look() -> void:
	turn_off()
	_add_dot(Vector3.ZERO)
	for direction in allowed_directions():
		var toward_the_edge := Vector3(GridCoordsProvider.grid_to_godot(direction))
		for step in range(1, DOTS_PER_ARM + 1):
			_add_dot(toward_the_edge * DOT_SPACING * step)

func _add_dot(along: Vector3) -> void:
	var dot := CylinderMesh.new()
	dot.top_radius = DOT_RADIUS
	dot.bottom_radius = DOT_RADIUS
	dot.height = DOT_THICKNESS
	dot.radial_segments = 12
	dot.rings = 1
	_add_part(dot, _dots, LIFT + DOT_THICKNESS / 2.0, along)
