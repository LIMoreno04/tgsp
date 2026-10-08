@tool
class_name ExitDoor
extends Door
## Una puerta verde que termina el nivel cuando el jugador la cruza abierta. Por defecto reinicia el nivel

const GREEN := Color(0.15, 0.68, 0.3)

## Ruta de archivo. No precargar la escena, cargaría todas en cadena hasta el final
@export_file("*.tscn") var next_level := ""


func _ready() -> void:
	super()
	if not Engine.is_editor_hint():
		_listen_to_the_player.call_deferred()


func _colour() -> Color:
	return GREEN


## El Level arma su jugador en su propio _ready, después de este, así que se busca en diferido.
## Fuera de un Level (en las pruebas) no hay a quién escuchar.
func _listen_to_the_player() -> void:
	var level := _room().get_parent() as Level
	if level == null:
		return
	level.player.cell_changed.connect(_on_the_player_stepping)

func _on_the_player_stepping(from: Vector3i, to: Vector3i) -> void:
	var room := _room()
	if room.index.closed_doors.has(self):
		return
	if not room.index.is_at_the_player_level(self, room.perspective_manager.current, to.z):
		return
	if _crosses_its_edge(from, to):
		_finish_the_level()

## El centro del jugador pasó por encima de su borde, de un lado al otro, en cualquier sentido.
func _crosses_its_edge(from: Vector3i, to: Vector3i) -> bool:
	var inside := _room().index.column_of(box)
	var outside := inside + Box.FACING_DIRECTION[edge]
	var from_column := Vector2i(from.x, from.y)
	var to_column := Vector2i(to.x, to.y)
	return (from_column == inside and to_column == outside) or (from_column == outside and to_column == inside)

func _finish_the_level() -> void:
	if next_level.is_empty():
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(next_level)


func _room() -> Room:
	return box.room_above() as Room
