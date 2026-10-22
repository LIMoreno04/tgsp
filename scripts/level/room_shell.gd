@tool
class_name RoomShell
extends Node3D


const STRUCTURE_SCENE: PackedScene = preload("res://scenes/prefabs/structure.tscn")

const FLOOR := "Floor"
const WALL_X := "WallX" # la pared en x = -1; se queda con la columna de la esquina (-1, -1)
const WALL_Y := "WallY" # la pared en y = -1

## Lo que un achique le sacó al marco en una celda: la caja, con sus ediciones y sus powerables, o
## null si la celda era un agujero.
class Trimmed:
	var box: Box
	## La cáscara no ve la historia de deshacer del editor: si el cuarto vuelve justo al tamaño que
	## tenía antes del achique, lo toma por deshacerlo y devuelve lo recortado tal cual.
	var room_size_before: Vector3i
	## Fuera del árbol pierden el owner, y sin owner no se guardan.
	var saved_nodes: Array[Node] = []
	## Su lugar entre las cajas de su parte, para que deshacer deje el archivo igual que antes.
	var index_in_part := 0

@onready var room: Room = get_parent()

## Por celda del mundo, el recorte más reciente al final. Sólo en memoria, como la historia de
## deshacer, y se libera con la cáscara.
var _trimmed: Dictionary[Vector3i, Array] = {}
var _room_size_laid_out: Vector3i

func on_dimensions_change():
	var frame_before := _frame_laid_out_last_time()
	for part_name in [FLOOR, WALL_X, WALL_Y]:
		if _part(part_name) == null:
			_create_part(part_name)
	_lay_out()
	_fill_part(_part(FLOOR), &"is_floor", frame_before)
	_fill_part(_part(WALL_X), &"is_wall", frame_before)
	_fill_part(_part(WALL_Y), &"is_wall", frame_before)
	_trim_what_fell_outside(frame_before)
	_room_size_laid_out = room.dimensions
	update_configuration_warnings()

func _init() -> void:
	set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		update_configuration_warnings()
	elif what == NOTIFICATION_PREDELETE:
		for trimmed_here: Array in _trimmed.values():
			for trimmed: Trimmed in trimmed_here:
				if is_instance_valid(trimmed.box):
					trimmed.box.free()

func _ready() -> void:
	_room_size_laid_out = room.dimensions
	room.dimensions_changed.connect(on_dimensions_change)


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


## El único registro del marco anterior es el `cell` y las `dimensions` que _lay_out le dejó a cada
## parte, que se guardan con la escena. Una parte que todavía no existe no tenía marco, así que una
## cáscara nueva se llena entera.
func _frame_laid_out_last_time() -> Dictionary[Vector3i, bool]:
	var frame: Dictionary[Vector3i, bool] = {}
	for part_name in [FLOOR, WALL_X, WALL_Y]:
		var part := _part(part_name)
		if part == null:
			continue
		for cell_in_part in part.prism_cells():
			frame[part.cell + cell_in_part] = true
	return frame


## Sólo las celdas nuevas del marco: una celda que ya estaba en él y no tiene caja es un agujero
## hecho a propósito. Una celda nueva recibe lo que un achique le recortó si el cuarto volvió al
## tamaño de antes de ese achique, y si no una caja nueva, marcada como piso o pared.
func _fill_part(part: Structure, flag: StringName, frame_before: Dictionary[Vector3i, bool]) -> void:
	var occupied: Dictionary[Vector3i, bool] = {}
	for box in part.boxes():
		occupied[box.cell] = true
	var coming_back: Array[Trimmed] = []
	var new_cells: Array[Vector3i] = []
	for cell_in_part in part.prism_cells():
		var world_cell := part.cell + cell_in_part
		if occupied.has(cell_in_part) or frame_before.has(world_cell):
			continue
		var trimmed := _take_trimmed_for_this_size(world_cell)
		if trimmed != null:
			coming_back.append(trimmed)
		else:
			new_cells.append(cell_in_part)
	# Cada una vuelve a su lugar de antes; de la primera a la última, así ninguna corre a otra.
	coming_back.sort_custom(func(a: Trimmed, b: Trimmed) -> bool: return a.index_in_part < b.index_in_part)
	for trimmed in coming_back:
		_put_back(trimmed, part)
	for cell_in_part in new_cells:
		var box := Structure.BOX_SCENE.instantiate() as Box
		box.cell = cell_in_part
		part.add_child(box, true)
		box.owner = get_tree().edited_scene_root
		box.set(flag, true)


func _take_trimmed_for_this_size(world_cell: Vector3i) -> Trimmed:
	var trimmed_here: Array = _trimmed.get(world_cell, [])
	for i in range(trimmed_here.size() - 1, -1, -1):
		var trimmed: Trimmed = trimmed_here[i]
		if trimmed.room_size_before == room.dimensions:
			trimmed_here.remove_at(i)
			return trimmed
	return null


func _put_back(trimmed: Trimmed, part: Structure) -> void:
	if trimmed.box == null:
		return
	part.add_child(trimmed.box, true)
	part.move_child(trimmed.box, mini(trimmed.index_in_part, part.get_child_count() - 1))
	for node in trimmed.saved_nodes:
		node.owner = get_tree().edited_scene_root


## No se borra: se guarda, agujeros incluidos, por si se deshace el achique.
func _trim_what_fell_outside(frame_before: Dictionary[Vector3i, bool]) -> void:
	var trimmed_boxes_at: Dictionary[Vector3i, bool] = {}
	for part_name in [FLOOR, WALL_X, WALL_Y]:
		var part := _part(part_name)
		var prism := part.prism_cells()
		# Los lugares se miran antes de sacar ninguna: sacar una corre a las de después.
		var falling: Dictionary[Box, int] = {}
		for box in part.boxes():
			if not prism.has(box.cell):
				falling[box] = box.get_index()
		for box: Box in falling:
			trimmed_boxes_at[part.cell + box.cell] = true
			_keep_trimmed(part.cell + box.cell, box, falling[box])
	var frame_now := _frame_laid_out_last_time()
	for world_cell in frame_before:
		if not frame_now.has(world_cell) and not trimmed_boxes_at.has(world_cell):
			_keep_trimmed(world_cell, null)


func _keep_trimmed(world_cell: Vector3i, box: Box, index_in_part := 0) -> void:
	var trimmed := Trimmed.new()
	trimmed.box = box
	trimmed.room_size_before = _room_size_laid_out
	trimmed.index_in_part = index_in_part
	if box != null:
		trimmed.saved_nodes = _nodes_saved_with(box)
		box.get_parent().remove_child(box)
	if not _trimmed.has(world_cell):
		_trimmed[world_cell] = []
	_trimmed[world_cell].append(trimmed)


func _nodes_saved_with(box: Box) -> Array[Node]:
	var saved: Array[Node] = []
	if box.owner == null:
		return saved
	saved.append(box)
	for node in box.find_children("*", "", true, false):
		if node.owner == box.owner:
			saved.append(node)
	return saved


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
