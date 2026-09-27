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
		walkable = value
		if walkable:
			movable_2d_whole_face = false
		notify_property_list_changed()
		appearance_changed.emit()

@export var is_wall := false:
	set(value):
		is_wall = value
		notify_property_list_changed()
		appearance_changed.emit()

@export var is_floor := false:
	set(value):
		is_floor = value
		if is_floor:
			walkable = true
		notify_property_list_changed()
		appearance_changed.emit()

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

func _validate_property(property: Dictionary) -> void:
	if property.name.contains("movable") and (is_wall or is_floor):
		property.usage = PROPERTY_USAGE_NO_EDITOR


static func facing_toward(direction: Vector2i) -> Facing:
	match direction:
		Vector2i(1, 0): return Facing.POS_X
		Vector2i(-1, 0): return Facing.NEG_X
		Vector2i(0, 1): return Facing.POS_Y
		Vector2i(0, -1): return Facing.NEG_Y
	assert(false, "No hay cara para la dirección %s" % direction)
	return Facing.POS_X

func movable_3d_from(facing: Facing) -> bool:
	match facing:
		Facing.POS_X: return movable_3d_pos_x
		Facing.NEG_X: return movable_3d_neg_x
		Facing.POS_Y: return movable_3d_pos_y
		Facing.NEG_Y: return movable_3d_neg_y
		_: return false

func movable_2d() -> bool:
	return movable_2d_whole_face or movable_2d_pos_x or movable_2d_neg_x or movable_2d_pos_y or movable_2d_neg_y

func movable_2d_from(facing: Facing) -> bool:
	if movable_2d_whole_face:
		return true
	match facing:
		Facing.POS_X: return movable_2d_pos_x
		Facing.NEG_X: return movable_2d_neg_x
		Facing.POS_Y: return movable_2d_pos_y
		Facing.NEG_Y: return movable_2d_neg_y
		_: return false
