@tool
class_name LaserReceiver
extends Powerable

const TRANSMITS := true

const TARGET_WIDTH := 0.5
const TARGET_DEPTH := 0.03
const BULLSEYE_RADIUS := 0.13
const BULLSEYE_DEPTH := 0.05

var _bullseye := StandardMaterial3D.new()


func _init() -> void:
	face = Face.POS_X


func activation_condition(inputs: Inputs) -> bool:
	return inputs.hit_by_a_laser


func turn_on() -> void:
	_paint(_bullseye, LIT_RED, true)

func turn_off() -> void:
	_paint(_bullseye, DIM_RED, false)


func _build_look() -> void:
	turn_off()
	var target := BoxMesh.new()
	target.size = Vector3(TARGET_WIDTH, TARGET_DEPTH, TARGET_WIDTH)
	_add_part(target, _material(STAND_GREY), TARGET_DEPTH / 2.0)
	var bullseye := CylinderMesh.new()
	bullseye.top_radius = BULLSEYE_RADIUS
	bullseye.bottom_radius = BULLSEYE_RADIUS
	bullseye.height = BULLSEYE_DEPTH
	_add_part(bullseye, _bullseye, BULLSEYE_DEPTH / 2.0)


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.hint_string = _faces_hint(SIDE_FACES)
