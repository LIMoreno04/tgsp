@tool
class_name Door
extends Powerable


const TRANSMITS := false

const BOX_MESH := preload("res://scripts/objects/box_mesh.gd")

const THICKNESS: float = BOX_MESH.MOVABLE_STRIPE_WIDTH
const HEIGHT := 1.0
const COLOUR := Color(0.2, 0.2, 0.22)

@export var edge := Box.Facing.POS_X:
	set(value):
		edge = value
		_request_redraw()

@export var always_open := false

var _slab: MeshInstance3D


func activation_condition(active_neighbours: Array[Powerable], _pressed: bool) -> bool:
	return Powerable.powered(active_neighbours)


func turn_on() -> void:
	_slab.visible = false

func turn_off() -> void:
	_slab.visible = true


func _colour() -> Color:
	return COLOUR


func _build_look() -> void:
	var strip := Box.strip_along(edge, THICKNESS)
	var slab := BoxMesh.new()
	slab.size = Vector3(strip.size.x, HEIGHT, strip.size.y)
	_slab = _add_part(slab, _material(_colour()), HEIGHT / 2.0, Vector3(strip.get_center().x, 0, strip.get_center().y))


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.usage = PROPERTY_USAGE_NO_EDITOR
