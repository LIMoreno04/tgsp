@tool
class_name Room
extends Node3D


#==================General=====================
signal dimensions_changed
@export var dimensions:Vector3i = Vector3i(5,5,5):
	set(value):
		dimensions = value
		dimensions_changed.emit()
		notify_property_list_changed()
@export var player_spawn_point: Vector3i = Vector3i(2,2,0)

@export_tool_button("Print map 3D", "3D") var print3d := _print_map_3d_button
@export_tool_button("Print map 2D", "2D") var print2d := _print_map_2d_button


func _ready() -> void:
	rebuild_index()

#===============Perspectiva==================

enum Perspective {ISO_3D, TOP_2D}

@onready var perspective_manager: PerspectiveManager = get_node_or_null("PerspectiveManager")

static func is_3d(perspective: Perspective) -> bool:
	return perspective == Perspective.ISO_3D

static func is_2d(perspective: Perspective) -> bool:
	return perspective == Perspective.TOP_2D

func volumetric_center() -> Vector3:
	return GridCoordsProvider.grid_to_godot(maximum_reach())*(0.5)

#==================estructura del nivel==================
const LOWEST_Z := -2
const GRID_UP := Vector3i(0,0,1)
const GRID_DOWN := Vector3i(0,0,-1)

const NEIGHBOURS_3D: Array[Vector3i] = [
	Vector3i(1,0,0), Vector3i(-1,0,0),
	Vector3i(0,1,0), Vector3i(0,-1,0),
	GRID_UP, GRID_DOWN,
]
const NEIGHBOURS_2D: Array[Vector2i] = [
	Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
]

var cells_3D: Dictionary[Vector3i,Box]
var grid_2D: Dictionary[Vector2i,Box]

func column_of(box: Box) -> Vector2i:
	return Vector2i(box.world_cell.x, box.world_cell.y)

func add_to_index(box: Box) -> void:
	var cell := box.world_cell
	var projected_cell := column_of(box)
	
	if cells_3D.has(cell):
		push_error("Two boxes share the cell %s: %s and %s." % [cell, cells_3D[cell].get_path(), box.get_path()])
		return

	cells_3D[cell] = box
	if not grid_2D.has(projected_cell) or grid_2D[projected_cell].world_cell.z < cell.z:
		grid_2D[projected_cell] = box

func _add_structure_to_index(structure: Structure) -> void:
	for box in structure.boxes():
		add_to_index(box)


func rebuild_index() ->void:
	cells_3D.clear()
	grid_2D.clear()
	for child in get_children():
		if child is Box:
			add_to_index(child)
		elif child is Structure:
			_add_structure_to_index(child)
		elif child is RoomShell:
			for part in child.get_children():
				if part is Structure:
					_add_structure_to_index(part)


func maximum_reach() -> Vector3i:
	var x_max := dimensions.x
	var y_max := dimensions.y
	var z_max := dimensions.z
	for occupied_cell: Vector3i in cells_3D:
		x_max = max(x_max, occupied_cell.x + 1)
		y_max = max(y_max, occupied_cell.y + 1)
		z_max = max(z_max, occupied_cell.z + 1) #el +1 porque las coords de grilla empiezan en 0,0,0; y acá busco tamaño, no coords
	return Vector3i(x_max,y_max,z_max)

func same_structure(a: Box,b: Box) -> bool:
	if a.get_parent() is Structure and b.get_parent() is Structure:
		return a.get_parent() == b.get_parent()
	else:
		return a == b

func boxes_of_same_structure_connected_to(box: Box, perspective: Perspective, visited: Array[Box] = [])->Array[Box]:
	var _visited := visited.duplicate()
	_visited.append(box)

	var orthogonal_dirs := []
	var map_dict: Dictionary = {}
	if is_3d(perspective):
		orthogonal_dirs = NEIGHBOURS_3D
		map_dict = cells_3D
	elif is_2d(perspective):
		orthogonal_dirs = NEIGHBOURS_2D
		map_dict = grid_2D
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")

	for orthogonal_dir in orthogonal_dirs:
		var target = box.world_cell + orthogonal_dir if is_3d(perspective) else column_of(box) + orthogonal_dir
		if map_dict.has(target) and same_structure(box, map_dict[target]) and not _visited.has(map_dict[target]):
			_visited = boxes_of_same_structure_connected_to(map_dict[target], perspective, _visited)

	return _visited


#==================Qué se mueve junto==================

# En 2d las tapadas por lo que estoy agarrando
func boxes_grabbed_along_with(box: Box, perspective: Perspective) -> Array[Box]:
	var structure := boxes_of_same_structure_connected_to(box, perspective)
	if is_3d(perspective):
		return structure

	for tile: Box in structure.duplicate():
		var column := column_of(tile)
		for z in range(tile.world_cell.z - 1, LOWEST_Z - 1, -1):
			var cell := Vector3i(column.x, column.y, z)
			if not cells_3D.has(cell):
				continue
			if not same_structure(tile, cells_3D[cell]):
				break
			if not structure.has(cells_3D[cell]):
				structure.append(cells_3D[cell])
	return structure

# En 3d las apoyadas encima
func boxes_that_would_move(box: Box, direction: Vector2i, perspective: Perspective) -> Array[Box]:
	var unit := boxes_grabbed_along_with(box, perspective)
	if is_2d(perspective):
		return unit

	var grown := true
	while grown:
		grown = false
		for unit_box: Box in unit.duplicate():
			var above := unit_box.world_cell + GRID_UP
			if not cells_3D.has(above) or unit.has(cells_3D[above]):
				continue
			var rider := boxes_of_same_structure_connected_to(cells_3D[above], perspective)
			if not can_move_one_cell(rider, unit, direction, perspective):
				continue
			for rider_box in rider:
				if not unit.has(rider_box):
					unit.append(rider_box)
					grown = true
	return unit


#==================Movimiento==================


func highest_filtered_box_in_column(column: Vector2i, filter: Array[Box] = []) -> Box:
	var highest: Box = null
	for occupied_cell: Vector3i in cells_3D:
		if occupied_cell.x != column.x or occupied_cell.y != column.y or filter.has(cells_3D[occupied_cell]):
			continue
		if highest == null or occupied_cell.z > highest.world_cell.z:
			highest = cells_3D[occupied_cell]
	return highest


func can_move_one_cell(structure: Array[Box], already_moving: Array[Box], direction: Vector2i, perspective: Perspective) -> bool:
	for structure_box in structure:
		if structure_box.is_wall or structure_box.is_floor:
			return false
		if is_3d(perspective):
			var target := structure_box.world_cell + Vector3i(direction.x, direction.y, 0)
			if cells_3D.has(target) and not structure.has(cells_3D[target]) and not already_moving.has(cells_3D[target]):
				return false
		elif is_2d(perspective):
			var landing := highest_filtered_box_in_column(column_of(structure_box) + direction, already_moving)
			if landing == null or not landing.walkable:
				return false
		else:
			assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
			return false
	return true


## Si después de moverse la unidad sigue tocando algo que no se mueva (para no quedar volando).
func would_unit_stay_connected(unit: Array[Box], step: Vector3i) -> bool:
	for unit_box in unit:
		var moved := unit_box.world_cell + step
		for direction: Vector3i in NEIGHBOURS_3D:
			var neighbour: Box = cells_3D.get(moved + direction)
			if neighbour != null and not unit.has(neighbour):
				return true
	return false


func try_to_move_grabbed_box(box: Box, direction: Vector2i, perspective: Perspective) -> bool:
	var grabbed := boxes_grabbed_along_with(box, perspective)
	var unit := boxes_that_would_move(box, direction, perspective)
	if not can_move_one_cell(grabbed, unit, direction, perspective):
		return false

	var step := Vector3i(direction.x, direction.y, 0)
	if is_2d(perspective):
		var offsets: Array[int] = []
		for unit_box in unit:
			var landing := highest_filtered_box_in_column(column_of(unit_box) + direction, unit)
			if landing != null:
				offsets.append(landing.world_cell.z + 1 - unit_box.world_cell.z)
		if not offsets.is_empty():
			step.z = offsets.max()

	if not would_unit_stay_connected(unit, step):
		return false

	for unit_box in unit:
		unit_box.cell += step
	rebuild_index()
	return true

# ======================Jugador=======================

func floor_of(cell: Vector3i, perspective: Perspective) -> Box:
	var floor_box: Box = null
	if is_3d(perspective):
		var floor_cell := cell + GRID_DOWN
		floor_box = cells_3D[floor_cell] if cells_3D.has(floor_cell) else null
	elif is_2d(perspective):
		floor_box = grid_2D.get(Vector2i(cell.x,cell.y))
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")

	return floor_box

func can_player_be_on(player_position: Vector3i, perspective: Perspective) -> bool:
	var floor_box = floor_of(player_position, perspective)
	if is_3d(perspective):
		return floor_box != null and floor_box.walkable and not cells_3D.has(player_position)
	elif is_2d(perspective):
		return floor_box != null and floor_box.walkable
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
		return false	

func is_occluded(cell: Vector3i) -> bool:
	var roof := highest_filtered_box_in_column(Vector2i(cell.x,cell.y))
	return roof != null and roof.world_cell.z >= cell.z

## La raya naranja de un techo caminable es una pared por ese lado.
func has_grab_barrier(column: Vector2i, facing: Box.Facing, perspective: Perspective) -> bool:
	if not is_2d(perspective):
		return false
	var tile: Box = grid_2D.get(column)
	return tile != null and tile.walkable and tile.movable_2d_from(facing)

## Dónde tiene que haber collider en el plano por el que camina el jugador.
## [] = collider tapando la celda entera, [Box.Facing (tipo POS_X o NEG_y)] = collider solo en ese borde de la celda (solo en 2D)
func colliders_plane(height: int, perspective: Perspective) -> Dictionary[Vector2i, Array]:
	var colliders: Dictionary[Vector2i, Array] = {}

	for column: Vector2i in grid_2D:
		if not can_player_be_on(Vector3i(column.x, column.y, height), perspective):
			colliders[column] = []
			continue
		var edges := []
		for direction: Vector2i in NEIGHBOURS_2D:
			var facing := Box.facing_toward(direction)
			if has_grab_barrier(column, facing, perspective):
				edges.append(facing)
		if not edges.is_empty():
			colliders[column] = edges

	# El anillo de afuera es siempre sólido: el interior va de (0,0) a dimensions - 1, y
	# ahí no hay cajas que el recorrido de arriba pueda ver.
	for x in range(-1, dimensions.x + 1):
		colliders[Vector2i(x, -1)] = []
		colliders[Vector2i(x, dimensions.y)] = []
	for y in range(-1, dimensions.y + 1):
		colliders[Vector2i(-1, y)] = []
		colliders[Vector2i(dimensions.x, y)] = []

	return colliders


func choose_box_to_grab(player_cell: Vector3i, facing: Vector2, perspective: Perspective) -> Box:
	var player_column := Vector2i(player_cell.x, player_cell.y)
	var chosen: Box = null
	var best_alignment := -INF
	for direction: Vector2i in NEIGHBOURS_2D:
		if has_grab_barrier(player_column, Box.facing_toward(direction), perspective):
			continue
		var neighbour: Box = null
		if is_3d(perspective):
			neighbour = cells_3D.get(player_cell + Vector3i(direction.x, direction.y, 0))
		elif is_2d(perspective):
			neighbour = grid_2D.get(player_column + direction)
		else:
			assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
			return null
		if neighbour == null:
			continue
		var face_toward_player := Box.facing_toward(-direction)
		if is_3d(perspective) and not neighbour.movable_3d_from(face_toward_player):
			continue
		if is_2d(perspective) and not neighbour.movable_2d_from(face_toward_player):
			continue
		var alignment := facing.dot(Vector2(direction))
		if alignment > best_alignment:
			chosen = neighbour
			best_alignment = alignment
	return chosen


func could_player_stand_on_after_moving(destination: Vector3i, unit: Array[Box], perspective: Perspective) -> bool:
	if is_3d(perspective):
		var blocking: Box = cells_3D.get(destination)
		if blocking != null and not unit.has(blocking):
			return false
		var support: Box = cells_3D.get(destination + GRID_DOWN)
		return support != null and support.walkable and not unit.has(support)
	elif is_2d(perspective):
		var top := highest_filtered_box_in_column(Vector2i(destination.x, destination.y), unit)
		return top != null and top.walkable
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
		return false


func move_grabbed_box(box: Box, direction: Vector2i, player_cell: Vector3i, perspective: Perspective) -> bool:
	var unit := boxes_that_would_move(box, direction, perspective)
	if unit.has(floor_of(player_cell, perspective)):
		return false
	var destination := player_cell + Vector3i(direction.x, direction.y, 0)
	if not could_player_stand_on_after_moving(destination, unit, perspective):
		return false
	return try_to_move_grabbed_box(box, direction, perspective)


#==================Debug: los índices en el Output==================

## En el editor el índice sólo se arma en _ready, así que los botones lo rehacen antes
## de imprimir.
func _print_map_3d_button() -> void:
	rebuild_index()
	RoomMapPrinter.new(self).print_cells_3D()

func _print_map_2d_button() -> void:
	rebuild_index()
	RoomMapPrinter.new(self).print_grid_2D()
