class_name PerspectiveManager
extends Node


signal perspective_changed(new_perspective: Room.Perspective)

@export var starting_perspective: Room.Perspective = Room.Perspective.ISO_3D

@onready var room: Room = get_parent()

var current: Room.Perspective = Room.Perspective.ISO_3D
## La altura del jugador
var height := 0


func _ready() -> void:
	current = starting_perspective
	height = room.player_spawn_point.z


func is_3d() -> bool:
	return current == Room.Perspective.ISO_3D

func is_2d() -> bool:
	return current == Room.Perspective.TOP_2D


## De 3D a 2D no se puede con algo encima de la cabeza. De 2D a 3D siempre se puede, y el
## jugador queda parado sobre la caja de arriba de su columna.
func toggle(player_column: Vector2i) -> bool:
	if is_3d():
		if room.index.is_occluded(Vector3i(player_column.x, player_column.y, height)):
			return false
		current = Room.Perspective.TOP_2D
	else:
		height = room.index.cell_of(room.index.top_of(player_column)).z + 1
		current = Room.Perspective.ISO_3D
	perspective_changed.emit(current)
	return true

func restore(perspective: Room.Perspective, restored_height: int) -> void:
	height = restored_height
	if perspective != current:
		current = perspective
		perspective_changed.emit(current)
