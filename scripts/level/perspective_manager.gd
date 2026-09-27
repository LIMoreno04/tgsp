class_name PerspectiveManager
extends Node


signal perspective_changed(new_perspective: Room.Perspective)

@export var starting_perspective: Room.Perspective = Room.Perspective.ISO_3D

var current: Room.Perspective = Room.Perspective.ISO_3D

var _blockers := []


func _ready() -> void:
	current = starting_perspective


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


## Cambia de perspectiva si nadie la está bloqueando. Quien llama ya le tiene que haber
## preguntado al Room si el jugador puede: acá sólo se mira el candado.
func toggle() -> bool:
	if is_locked():
		return false
	current = Room.Perspective.TOP_2D if is_3d() else Room.Perspective.ISO_3D
	perspective_changed.emit(current)
	return true
