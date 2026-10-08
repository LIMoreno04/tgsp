@tool
class_name PressurePlate
extends Powerable
## Activa mientras algo está parado encima (LevelIndex.is_pressed). Sólo va en la cara de arriba.

const TRANSMITS := true

const OUTER_WIDTH := 0.8
const OUTER_HEIGHT := 0.02
const PLATE_WIDTH := 0.6
const PLATE_HEIGHT := 0.045

var _pad := StandardMaterial3D.new()


func activation_condition(_active_neighbours: Array[Powerable], pressed: bool) -> bool:
	return pressed


func turn_on() -> void:
	_paint(_pad, LIT_RED, true)

func turn_off() -> void:
	_paint(_pad, DIM_RED, false)


func _build_look() -> void:
	turn_off()
	var plate := BoxMesh.new()
	plate.size = Vector3(OUTER_WIDTH, OUTER_HEIGHT, OUTER_WIDTH)
	_add_part(plate, _material(STAND_GREY), OUTER_HEIGHT / 2.0)
	var pad := BoxMesh.new()
	pad.size = Vector3(PLATE_WIDTH, PLATE_HEIGHT, PLATE_WIDTH)
	_add_part(pad, _pad, PLATE_HEIGHT / 2.0)


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.usage = PROPERTY_USAGE_NO_EDITOR
