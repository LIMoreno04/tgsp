@tool
class_name ButtonPowerable
extends Powerable

const TRANSMITS := true


const STAND_WIDTH := 0.45 # >(1-J)
const STAND_HEIGHT := 0.5
const BUTTON_RADIUS := 0.1
const BUTTON_HEIGHT := 0.06

## Cómo empieza
@export var switched_on := false

var _light := StandardMaterial3D.new()


func activation_condition(_active_neighbours: Array[Powerable], _pressed: bool) -> bool:
	return switched_on


func turn_on() -> void:
	_paint(_light, LIT_RED, true)

func turn_off() -> void:
	_paint(_light, DIM_RED, false)


func _build_look() -> void:
	turn_off()
	var stand := BoxMesh.new()
	stand.size = Vector3(STAND_WIDTH, STAND_HEIGHT, STAND_WIDTH)
	_add_part(stand, _material(STAND_GREY), STAND_HEIGHT / 2.0)
	var button := CylinderMesh.new()
	button.top_radius = BUTTON_RADIUS
	button.bottom_radius = BUTTON_RADIUS
	button.height = BUTTON_HEIGHT
	_add_part(button, _light, STAND_HEIGHT + BUTTON_HEIGHT / 2.0)


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.usage = PROPERTY_USAGE_NO_EDITOR
