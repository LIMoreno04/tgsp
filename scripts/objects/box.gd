@tool
class_name Box
extends GridEntity

signal appearance_changed

enum Facing { POS_X, NEG_X, POS_Y, NEG_Y }

const FACING_NORMAL := {
	Facing.POS_X: Vector3(1, 0, 0),
	Facing.NEG_X: Vector3(-1, 0, 0),
	Facing.POS_Y: Vector3(0, 0, 1),
	Facing.NEG_Y: Vector3(0, 0, -1),
}

@export var walkable := false:
	set(value):
		walkable = value or is_floor # Un piso siempre se puede pisar.
		if walkable:
			movable_2d_whole_face = false
		notify_property_list_changed()
		appearance_changed.emit()

@export var is_wall := false:
	set(value):
		is_wall = value
		notify_property_list_changed()
		appearance_changed.emit()
		_ask_the_parent_to_check_its_warnings()

@export var is_floor := false:
	set(value):
		is_floor = value
		if is_floor:
			walkable = true
		notify_property_list_changed()
		appearance_changed.emit()
		_ask_the_parent_to_check_its_warnings()

@export var keeps_height := false:
	set(value):
		keeps_height = value
		_ask_the_parent_to_check_its_warnings()

@export var top_half_only := false:
	set(value):
		top_half_only = value
		appearance_changed.emit()

@export_group("3D movability", "movable_3d_")
@export var movable_3d_pos_x := false:
	set(value):
		movable_3d_pos_x = value
		appearance_changed.emit()
@export var movable_3d_neg_x := false:
	set(value):
		movable_3d_neg_x = value
		appearance_changed.emit()
@export var movable_3d_pos_y := false:
	set(value):
		movable_3d_pos_y = value
		appearance_changed.emit()
@export var movable_3d_neg_y := false:
	set(value):
		movable_3d_neg_y = value
		appearance_changed.emit()

@export_group("2D movability", "movable_2d_")
@export var movable_2d_pos_x := false:
	set(value):
		movable_2d_pos_x = value
		appearance_changed.emit()
@export var movable_2d_neg_x := false:
	set(value):
		movable_2d_neg_x = value
		appearance_changed.emit()
@export var movable_2d_pos_y := false:
	set(value):
		movable_2d_pos_y = value
		appearance_changed.emit()
@export var movable_2d_neg_y := false:
	set(value):
		movable_2d_neg_y = value
		appearance_changed.emit()
@export var movable_2d_whole_face := false:
	set(value):
		movable_2d_whole_face = value
		if movable_2d_whole_face:
			walkable = false
		notify_property_list_changed()
		appearance_changed.emit()
@export_group("")

@onready var _mesh: Node3D = $Mesh
@onready var _mesh_rest_x := _mesh.position.x
var _shake: Tween

## Para decir que no se pudo mover solo se hace vibrar la mesh. De momento siempre vibra en x.
func shake() -> void:
	if is_instance_valid(_shake):
		_shake.kill()
	_shake = Shake.sideways(_mesh, _mesh_rest_x)


func _get_configuration_warnings() -> PackedStringArray:
	if global_name_of(get_parent()) == &"Structure":
		return _warnings_about_its_transform() # Si las reglas no la ven, lo avisa su Structure, una vez por todas sus cajas.
	return super()

## Su Structure avisa si mezcla terreno con cajas que no lo son, o si sólo algunas mantienen la altura.
func _ask_the_parent_to_check_its_warnings() -> void:
	if get_parent() != null:
		get_parent().update_configuration_warnings()


func _validate_property(property: Dictionary) -> void:
	if property.name.contains("movable") and is_terrain():
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "walkable" and is_floor:
		property.usage |= PROPERTY_USAGE_READ_ONLY


func is_terrain() -> bool:
	return is_wall or is_floor


static func facing_toward(direction: Vector2i) -> Facing:
	match direction:
		Vector2i(1, 0): return Facing.POS_X
		Vector2i(-1, 0): return Facing.NEG_X
		Vector2i(0, 1): return Facing.POS_Y
		Vector2i(0, -1): return Facing.NEG_Y
	assert(false, "No hay cara para la dirección %s" % direction)
	return Facing.POS_X

func movable_3d_from(facing: Facing) -> bool:
	if is_terrain():
		return false
	match facing:
		Facing.POS_X: return movable_3d_pos_x
		Facing.NEG_X: return movable_3d_neg_x
		Facing.POS_Y: return movable_3d_pos_y
		Facing.NEG_Y: return movable_3d_neg_y
		_: return false

func movable_3d_from_any_side() -> bool:
	for facing: Facing in Facing.values():
		if movable_3d_from(facing):
			return true
	return false

func movable_2d_from(facing: Facing) -> bool:
	if is_terrain():
		return false
	if movable_2d_whole_face:
		return true
	match facing:
		Facing.POS_X: return movable_2d_pos_x
		Facing.NEG_X: return movable_2d_neg_x
		Facing.POS_Y: return movable_2d_pos_y
		Facing.NEG_Y: return movable_2d_neg_y
		_: return false

func movable_2d_from_every_side() -> bool:
	return movable_2d_whole_face and not is_terrain()
