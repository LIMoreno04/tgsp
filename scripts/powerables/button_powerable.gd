@tool
class_name ButtonPowerable
extends Powerable

const TRANSMITS := true


const STAND_WIDTH := 0.45 # >(1-J)
const STAND_HEIGHT := 0.5
## En una pared no hay pedestal: una base corta, sin hitbox.
const WALL_STAND_HEIGHT := 0.08
const BUTTON_RADIUS := 0.1
const BUTTON_HEIGHT := 0.06

## Cómo empieza
@export var switched_on := false

var _light := StandardMaterial3D.new()


func activation_condition(_inputs: Inputs) -> bool:
	return switched_on


func turn_on() -> void:
	_paint(_light, LIT_RED, true)

func turn_off() -> void:
	_paint(_light, DIM_RED, false)


func _build_look() -> void:
	turn_off()
	var stand_height := STAND_HEIGHT if face == Face.TOP else WALL_STAND_HEIGHT
	var stand := BoxMesh.new()
	stand.size = Vector3(STAND_WIDTH, stand_height, STAND_WIDTH)
	_add_part(stand, _material(STAND_GREY), stand_height / 2.0)
	var button := CylinderMesh.new()
	button.top_radius = BUTTON_RADIUS
	button.bottom_radius = BUTTON_RADIUS
	button.height = BUTTON_HEIGHT
	_add_part(button, _light, stand_height + BUTTON_HEIGHT / 2.0)


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.hint_string = _faces_hint([Face.TOP, Face.POS_X, Face.NEG_X, Face.POS_Y, Face.NEG_Y])
