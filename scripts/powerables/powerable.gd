@tool
@abstract
class_name Powerable
extends Node3D
## Vive en una cara de una Box. Tiene su activation_condition y qué hace cuando se activa o desactiva (turn_on/turn_off)

enum Face { TOP, BOTTOM, POS_X, NEG_X, POS_Y, NEG_Y }

const FACE_NORMAL: Dictionary[Face, Vector3i] = {
	Face.TOP: Vector3i(0, 0, 1),
	Face.BOTTOM: Vector3i(0, 0, -1),
	Face.POS_X: Vector3i(1, 0, 0),
	Face.NEG_X: Vector3i(-1, 0, 0),
	Face.POS_Y: Vector3i(0, 1, 0),
	Face.NEG_Y: Vector3i(0, -1, 0),
}

const FACE_ROTATIONS: Dictionary[Face, Vector3] = {
	Face.TOP: Vector3(0, 0, 0),
	Face.BOTTOM: Vector3(180, 0, 0),
	Face.POS_X: Vector3(0, 0, -90),
	Face.NEG_X: Vector3(0, 0, 90),
	Face.POS_Y: Vector3(90, 0, 0),
	Face.NEG_Y: Vector3(-90, 0, 0),
}
const BOX_CENTRE := Vector3(0.5, 0.5, 0.5)

const LIT_RED := Color(1.0, 0.1, 0.06)
const DIM_RED := Color(0.38, 0.07, 0.05)
const STAND_GREY := Color(0.55, 0.55, 0.57)

@export var face := Face.TOP:
	set(value):
		face = value
		notify_property_list_changed()
		_request_redraw()
		_ask_every_powerable_of_the_box_to_check_its_warnings()

@export_group("Connects", "connects_")
@export var connects_pos_x := false:
	set(value):
		connects_pos_x = value
		_request_redraw()
@export var connects_neg_x := false:
	set(value):
		connects_neg_x = value
		_request_redraw()
@export var connects_pos_y := false:
	set(value):
		connects_pos_y = value
		_request_redraw()
@export var connects_neg_y := false:
	set(value):
		connects_neg_y = value
		_request_redraw()
@export var connects_up := false:
	set(value):
		connects_up = value
		_request_redraw()
@export var connects_down := false:
	set(value):
		connects_down = value
		_request_redraw()
@export_group("")

var box: Box:
	get:
		return get_parent() as Box

var _redraw_pending := false


func _ready() -> void:
	_redraw()



func normal() -> Vector3i:
	return FACE_NORMAL[face]

static func face_toward(direction: Vector3i) -> Face:
	return FACE_NORMAL.find_key(direction)


func allowed_directions() -> Array[Vector3i]:
	var ticked: Dictionary[Vector3i, bool] = {
		Vector3i(1, 0, 0): connects_pos_x,
		Vector3i(-1, 0, 0): connects_neg_x,
		Vector3i(0, 1, 0): connects_pos_y,
		Vector3i(0, -1, 0): connects_neg_y,
		Vector3i(0, 0, 1): connects_up,
		Vector3i(0, 0, -1): connects_down,
	}
	var allowed: Array[Vector3i] = []
	for direction in ticked:
		if ticked[direction] and direction != normal() and direction != -normal():
			allowed.append(direction)
	return allowed



@abstract func activation_condition(active_neighbours: Array[Powerable], pressed: bool) -> bool


static func powered(active_neighbours: Array[Powerable]) -> bool:
	for neighbour in active_neighbours:
		if neighbour.TRANSMITS:
			return true
	return false



@abstract func turn_on() -> void
@abstract func turn_off() -> void



@abstract func _build_look() -> void


func _request_redraw() -> void:
	if not is_node_ready() or _redraw_pending:
		return
	_redraw_pending = true
	_redraw.call_deferred()

func _redraw() -> void:
	_redraw_pending = false
	position = BOX_CENTRE + Vector3(GridCoordsProvider.grid_to_godot(normal())) * 0.5
	rotation_degrees = Vector3.ZERO
	for part in get_children():
		remove_child(part)
		part.queue_free()
	_build_look()



func _add_part(mesh: Mesh, material: Material, height: float, along := Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = Vector3(GridCoordsProvider.grid_to_godot(normal())) * height + along
	part.rotation_degrees = FACE_ROTATIONS[face]
	add_child(part)
	return part

static func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	return material


static func _paint(material: StandardMaterial3D, colour: Color, glowing: bool) -> void:
	material.albedo_color = colour
	material.emission_enabled = glowing
	material.emission = colour


#==================Cosas del editor==================

## Esconde las dos casillas a lo largo de la normal
func _validate_property(property: Dictionary) -> void:
	var off_the_face: Array[String] = []
	match face:
		Face.TOP, Face.BOTTOM: off_the_face = ["connects_up", "connects_down"]
		Face.POS_X, Face.NEG_X: off_the_face = ["connects_pos_x", "connects_neg_x"]
		Face.POS_Y, Face.NEG_Y: off_the_face = ["connects_pos_y", "connects_neg_y"]
	if property.name in off_the_face:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if box == null:
		warnings.append("A powerable must be a child of a Box: it belongs to that box and sits on one of its faces.")
	elif box.powerable_on(face) != self:
		warnings.append("%s is already on this face of the box. Only one powerable per face counts, and it is that one." % box.powerable_on(face).name)
	return warnings

func _ask_every_powerable_of_the_box_to_check_its_warnings() -> void:
	if box == null:
		update_configuration_warnings()
		return
	for sibling in box.get_children():
		if sibling is Powerable:
			sibling.update_configuration_warnings()
