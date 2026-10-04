class_name PerspectiveManager
extends Node


signal perspective_changed(new_perspective: Room.Perspective)

@export var starting_perspective: Room.Perspective = Room.Perspective.ISO_3D

@onready var room: Room = get_parent()

var current: Room.Perspective = Room.Perspective.ISO_3D
## La altura del corte 3D en el que vive el jugador. Sólo la cambia toggle(), al volver a 3D.
var height := 0

var _blockers := []


func _ready() -> void:
	current = starting_perspective
	height = room.player_spawn_point.z


func is_3d() -> bool:
	return current == Room.Perspective.ISO_3D

func is_2d() -> bool:
	return current == Room.Perspective.TOP_2D


func block(blocker: Node) -> void:
	if not _blockers.has(blocker):
		_blockers.append(blocker)

func unblock(blocker: Node) -> void:
	_blockers.erase(blocker)

## Descarta los que ya no existen: un nodo liberado a mitad de una animación no tiene
## que dejar la perspectiva trabada para siempre.
func is_locked() -> bool:
	var alive := []
	for blocker in _blockers:
		if is_instance_valid(blocker):
			alive.append(blocker)
	_blockers = alive
	return not _blockers.is_empty()


## De 3D a 2D no se puede con algo encima de la cabeza. De 2D a 3D siempre se puede, y el
## jugador queda parado sobre la caja de arriba de su columna.
func toggle(player_column: Vector2i) -> bool:
	if is_locked():
		return false
	if is_3d():
		if room.is_occluded(Vector3i(player_column.x, player_column.y, height)):
			return false
		current = Room.Perspective.TOP_2D
	else:
		height = room.grid_2D[player_column].world_cell.z + 1
		current = Room.Perspective.ISO_3D
	perspective_changed.emit(current)
	return true
