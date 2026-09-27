@tool
class_name RoomShell
extends Node3D


const STRUCTURE_SCENE: PackedScene = preload("res://scenes/prefabs/structure.tscn")

const FLOOR := "Floor"
const WALL_X := "WallX" # la pared en x = -1; se queda con la columna de la esquina (-1, -1)
const WALL_Y := "WallY" # la pared en y = -1

@onready var room: Room = get_parent()

func on_dimensions_change():
	_lay_out()
	fill()
	remove_excess()
	update_configuration_warnings()

func _init() -> void:
	set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		update_configuration_warnings()

func _ready() -> void:
	room.dimensions_changed.connect(on_dimensions_change)

## Como Structure.fill: agrega una caja en cada celda del marco que no tenga una y no
## toca las que ya existen. Sólo las nuevas se marcan como piso o pared.
func fill() -> void:
	for part_name in [FLOOR, WALL_X, WALL_Y]:
		if _part(part_name) == null:
			_create_part(part_name)
	_lay_out()
	_fill_part(_part(FLOOR), &"is_floor")
	_fill_part(_part(WALL_X), &"is_wall")
	_fill_part(_part(WALL_Y), &"is_wall")


## Como Structure.remove_excess: borra las cajas que quedaron fuera del marco.
func remove_excess() -> void:
	_lay_out()
	for part_name in [FLOOR, WALL_X, WALL_Y]:
		var part := _part(part_name)
		if part != null:
			part.remove_excess()


func _lay_out() -> void:
	_place(FLOOR, Vector3i(0, 0, -1), Vector3i(room.dimensions.x, room.dimensions.y, 1))
	_place(WALL_X, Vector3i(-1, -1, -1), Vector3i(1, room.dimensions.y + 1, room.dimensions.z + 1))
	_place(WALL_Y, Vector3i(0, -1, -1), Vector3i(room.dimensions.x, 1, room.dimensions.z + 1))


func _place(part_name: String, first_cell: Vector3i, size: Vector3i) -> void:
	var part := _part(part_name)
	if part == null:
		return
	part.cell = first_cell
	part.dimensions = size


func _fill_part(part: Structure, flag: StringName) -> void:
	var existing: Dictionary[Box, bool] = {}
	for box in part.boxes():
		existing[box] = true
	part.fill()
	for box in part.boxes():
		if not existing.has(box):
			box.set(flag, true)


func _part(part_name: String) -> Structure:
	return get_node_or_null(part_name) as Structure


func _create_part(part_name: String) -> void:
	var part := STRUCTURE_SCENE.instantiate() as Structure
	part.name = part_name
	add_child(part)
	part.owner = get_tree().edited_scene_root


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if room.dimensions.x <= 0 or room.dimensions.y <= 0 or room.dimensions.z <= 0:
		warnings.append("Dimensions must be greater than zero.")
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		warnings.append("The shell must sit at the origin: world_cell does not see this node's transform.")
	return warnings
