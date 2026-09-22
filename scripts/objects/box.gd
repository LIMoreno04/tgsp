@tool
extends GridEntity
class_name Box
signal _request_rebuild


enum Mobility { STATIC, MOVABLE, MOVABLE_3D, MOVABLE_2D, WALL }

enum Side { POS_X, NEG_X, POS_Y, NEG_Y }

## Qué cara de la pared lleva la textura del piso: la +X o la +Y (de grilla).
enum WallAxis { X, Y }

const SIDE_NORMAL := {
	Side.POS_X: Vector3(1, 0, 0),
	Side.NEG_X: Vector3(-1, 0, 0),
	Side.POS_Y: Vector3(0, 0, 1),
	Side.NEG_Y: Vector3(0, 0, -1),
}

@export var walkable := false:
	set(value):
		walkable = value
		_request_rebuild.emit()

@export var mobility := Mobility.STATIC:
	set(value):
		mobility = value
		notify_property_list_changed()
		_request_rebuild.emit()

## Sólo importa en WALL.
@export var wall_axis := WallAxis.X:
	set(value):
		wall_axis = value
		_request_rebuild.emit()

@export_group("Movable sides", "from_")
@export var from_pos_x := false:
	set(value):
		from_pos_x = value
		movable_from[Side.POS_X] = value
		_request_rebuild.emit()
@export var from_neg_x := false:
	set(value):
		from_neg_x = value
		movable_from[Side.NEG_X] = value
		_request_rebuild.emit()
@export var from_pos_y := false:
	set(value):
		from_pos_y = value
		movable_from[Side.POS_Y] = value
		_request_rebuild.emit()
@export var from_neg_y := false:
	set(value):
		from_neg_y = value
		movable_from[Side.NEG_Y] = value
		_request_rebuild.emit()
@export_group("")

var movable_from := {
	Side.POS_X: from_pos_x,
	Side.NEG_X: from_neg_x,
	Side.POS_Y: from_pos_y,
	Side.NEG_Y: from_neg_y,
}

func _validate_property(property: Dictionary) -> void:
	if property.name.begins_with("from_") and !(mobility in [Mobility.MOVABLE_2D, Mobility.MOVABLE_3D]):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "wall_axis" and mobility != Mobility.WALL:
		property.usage = PROPERTY_USAGE_NO_EDITOR

@export var top_half_only := false:
	set(value):
		top_half_only = value
		_request_rebuild.emit()
