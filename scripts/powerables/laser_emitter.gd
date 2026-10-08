@tool
class_name LaserEmitter
extends Powerable


const TRANSMITS := false

const HOUSING_WIDTH := 0.3
const HOUSING_DEPTH := 0.12
const LENS_RADIUS := 0.08
const LENS_DEPTH := 0.03
const BEAM_RADIUS := 0.035
const BEAM_RED := Color(1.0, 0.04, 0.04)

@export var always_on := false

var _lens := StandardMaterial3D.new()
var _beam_material := StandardMaterial3D.new()
var _beam_mesh := CylinderMesh.new()
var _beam: MeshInstance3D


func _init() -> void:
	face = Face.POS_X


func activation_condition(inputs: Inputs) -> bool:
	return always_on or Powerable.powered(inputs.active_neighbours)


func turn_on() -> void:
	_paint(_lens, LIT_RED, true)
	_beam.visible = true

func turn_off() -> void:
	_paint(_lens, DIM_RED, false)
	_beam.visible = false

## El largo se calcula en levelindex
func show_beam(length: float) -> void:
	_beam_mesh.height = maxf(length, 0.001)
	_beam.position = Vector3(GridCoordsProvider.grid_to_godot(normal())) * length / 2.0


func _build_look() -> void:
	var housing := BoxMesh.new()
	housing.size = Vector3(HOUSING_WIDTH, HOUSING_DEPTH, HOUSING_WIDTH)
	_add_part(housing, _material(STAND_GREY), HOUSING_DEPTH / 2.0)
	var lens := CylinderMesh.new()
	lens.top_radius = LENS_RADIUS
	lens.bottom_radius = LENS_RADIUS
	lens.height = LENS_DEPTH
	_add_part(lens, _lens, HOUSING_DEPTH + LENS_DEPTH / 2.0)
	_beam_mesh.top_radius = BEAM_RADIUS
	_beam_mesh.bottom_radius = BEAM_RADIUS
	_paint(_beam_material, BEAM_RED, true)
	_beam = _add_part(_beam_mesh, _beam_material, 0.0)
	turn_off()


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.hint_string = _faces_hint(SIDE_FACES)
