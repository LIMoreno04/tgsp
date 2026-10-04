@tool
class_name Room
extends Node3D


#==================General=====================
signal dimensions_changed
signal moved

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

## Se va a buscar cada vez que se necesita (lazy) porque no está disponible en _ready.
var perspective_manager: PerspectiveManager:
	get:
		return get_node_or_null("PerspectiveManager")

static func is_3d(perspective: Perspective) -> bool:
	return perspective == Perspective.ISO_3D

static func is_2d(perspective: Perspective) -> bool:
	return perspective == Perspective.TOP_2D

func volumetric_center() -> Vector3:
	return GridCoordsProvider.grid_to_godot(maximum_reach())*(0.5)

#==================estructura del nivel==================
const LOWEST_Z := -1
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

## El estado del nivel en ambas perspectivas. Para mover se crea otro LevelIndex hipotético
var index := LevelIndex.new()
var cells_3D: Dictionary[Vector3i,Box]:
	get:
		return index.cells_3D
var grid_2D: Dictionary[Vector2i,Box]:
	get:
		return index.grid_2D

func column_of(box: Box) -> Vector2i:
	return Vector2i(box.world_cell.x, box.world_cell.y)

func add_to_index(box: Box) -> void:
	index.add(box, box.world_cell)

func _add_structure_to_index(structure: Structure) -> void:
	for box in structure.boxes():
		add_to_index(box)

func _add_nested_nodes_to_index(node: GridEntity) -> void:
	if node is Box:
		add_to_index(node)
	elif node is Structure:
		_add_structure_to_index(node)
	else:
		for child in node.get_children():
			if child is GridEntity:
				_add_nested_nodes_to_index(child)


func rebuild_index() -> void:
	index = LevelIndex.new()
	for child in get_children():
		if child is RoomShell:
			for part in child.get_children():
				if part is Structure:
					_add_structure_to_index(part)
		elif child is GridEntity:
			_add_nested_nodes_to_index(child)

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

	var has_box_above := true
	while has_box_above:
		has_box_above = false
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
					has_box_above = true
	return unit


#==================Movimiento==================


func can_move_one_cell(structure: Array[Box], already_moving: Array[Box], direction: Vector2i, perspective: Perspective) -> bool:
	for structure_box in structure:
		if structure_box.is_wall or structure_box.is_floor:
			return false
		if is_3d(perspective):
			var target := structure_box.world_cell + Vector3i(direction.x, direction.y, 0)
			if cells_3D.has(target) and not structure.has(cells_3D[target]) and not already_moving.has(cells_3D[target]):
				return false
		elif is_2d(perspective):
			if not index.without(already_moving).could_go_over(column_of(structure_box) + direction):
				return false
		else:
			assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
			return false
	return true


## En 2D para no hacer aparecer cajas de la nada
func would_uncover_a_column_it_could_not_go_over(unit: Array[Box], direction: Vector2i, perspective: Perspective) -> bool:
	if not is_2d(perspective):
		return false
	var rest_of_the_room := index.without(unit)
	var covered_after: Dictionary[Vector2i, bool] = {}
	for unit_box in unit:
		covered_after[column_of(unit_box) + direction] = true
	for unit_box in unit:
		var column := column_of(unit_box)
		if not covered_after.has(column) and not rest_of_the_room.could_go_over(column):
			return true
	return false


## Cálculo de la altura de un movimiento
func step_after_landing(unit: Array[Box], direction: Vector2i, perspective: Perspective) -> Vector3i:
	var step := Vector3i(direction.x, direction.y, 0)
	if is_2d(perspective):
		var rest_of_the_room := index.without(unit)
		var offsets: Array[int] = []
		for unit_box in unit:
			var landing := rest_of_the_room.top_of(column_of(unit_box) + direction)
			if landing != null:
				offsets.append(landing.world_cell.z + 1 - unit_box.world_cell.z)
		if not offsets.is_empty():
			step.z = offsets.max()
		if keeps_its_height(unit):
			step.z = maxi(step.z, 0)
	return step


func keeps_its_height(boxes: Array[Box]) -> bool:
	for box in boxes:
		if box.keeps_height:
			return true
	return false


func would_leave_anything_floating(unit: Array[Box], step: Vector3i) -> bool:
	var after := index.moved(unit, step)
	if not is_held(unit, after):
		return true
	for left_behind in pieces_left_behind(unit):
		if not contains_terrain(left_behind) and not is_held(left_behind, after):
			return true
	return false

## Lo que se queda y estaba pegado a la unidad: lo que tenía encima, y lo de su misma estructura
## que no viene. Eso último pasa en 2D, cuando una caja de la estructura está tapada por otra:
## se separa y se queda donde estaba, y puede que sin nada abajo.
func pieces_left_behind(unit: Array[Box]) -> Array[Array]:
	var pieces: Array[Array] = []
	for unit_box in unit:
		for direction: Vector3i in NEIGHBOURS_3D:
			var neighbour: Box = cells_3D.get(unit_box.world_cell + direction)
			if neighbour == null or unit.has(neighbour):
				continue
			if direction == GRID_UP or same_structure(unit_box, neighbour):
				pieces.append(_piece_without(neighbour, unit))
	return pieces

## Las cajas de su estructura conectadas a esta en 3D, sin pasar por la unidad.
func _piece_without(box: Box, unit: Array[Box]) -> Array[Box]:
	var piece: Array[Box] = []
	for piece_box in boxes_of_same_structure_connected_to(box, Perspective.ISO_3D, unit.duplicate()):
		if not unit.has(piece_box):
			piece.append(piece_box)
	return piece

## Apoyada en algo de abajo; o, si tiene keeps_height, agarrada a cualquier cosa que toque.
func is_held(boxes: Array[Box], world: LevelIndex) -> bool:
	if world.rests_on_something(boxes):
		return true
	return keeps_its_height(boxes) and world.touches_something(boxes)

func contains_terrain(boxes: Array[Box]) -> bool:
	for box in boxes:
		if box.is_wall or box.is_floor:
			return true
	return false


func try_to_move_grabbed_box(box: Box, direction: Vector2i, perspective: Perspective) -> bool:
	var grabbed := boxes_grabbed_along_with(box, perspective)
	var unit := boxes_that_would_move(box, direction, perspective)
	if not can_move_one_cell(grabbed, unit, direction, perspective):
		return false
	if would_uncover_a_column_it_could_not_go_over(unit, direction, perspective):
		return false
	var step := step_after_landing(unit, direction, perspective)
	if would_leave_anything_floating(unit, step):
		return false

	for unit_box in unit:
		unit_box.cell += step
	rebuild_index()
	moved.emit()
	return true

# ======================Jugador=======================

func floor_of(cell: Vector3i, perspective: Perspective) -> Box:
	return index.floor_of(cell, perspective)

func can_player_be_on(player_position: Vector3i, perspective: Perspective) -> bool:
	return index.can_player_be_on(player_position, perspective)

func is_occluded(cell: Vector3i) -> bool:
	return index.is_occluded(cell)

func has_grab_barrier(column: Vector2i, facing: Box.Facing, perspective: Perspective) -> bool:
	return index.has_grab_barrier(column, facing, perspective)

enum ColliderType { POS_X, NEG_X, POS_Y, NEG_Y, SOLID }

const EDGE_COLLIDER_ON: Dictionary[Box.Facing, ColliderType] = {
	Box.Facing.POS_X: ColliderType.POS_X,
	Box.Facing.NEG_X: ColliderType.NEG_X,
	Box.Facing.POS_Y: ColliderType.POS_Y,
	Box.Facing.NEG_Y: ColliderType.NEG_Y,
}

## [SOLID] = collider tapando la celda entera, [POS_X, NEG_Y, etc] = collider sólo en esos bordes de la celda (sólo en 2D)
## Básicamente agarra todas las columnas del plano + las que están al lado de las caminables (así agarra agujeros y el borde del mapa)
func colliders_plane(height: int, perspective: Perspective) -> Dictionary[Vector2i, Array]:
	var columns_to_test: Dictionary[Vector2i, bool] = {}
	for column: Vector2i in grid_2D:
		columns_to_test[column] = true
		if can_player_be_on(Vector3i(column.x, column.y, height), perspective):
			for direction: Vector2i in NEIGHBOURS_2D:
				columns_to_test[column + direction] = true

	var colliders: Dictionary[Vector2i, Array] = {}
	for column: Vector2i in columns_to_test:
		if not can_player_be_on(Vector3i(column.x, column.y, height), perspective):
			colliders[column] = [ColliderType.SOLID]
			continue
		var edges := []
		for direction: Vector2i in NEIGHBOURS_2D:
			var facing := Box.facing_toward(direction)
			if has_grab_barrier(column, facing, perspective):
				edges.append(EDGE_COLLIDER_ON[facing])
		if not edges.is_empty():
			colliders[column] = edges
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


## Solo importa en 2D
func would_player_cross_a_stripe(player_cell: Vector3i, direction: Vector2i, after: LevelIndex, perspective: Perspective) -> bool:
	var leaving := Vector2i(player_cell.x, player_cell.y)
	if has_grab_barrier(leaving, Box.facing_toward(direction), perspective):
		return true
	return after.has_grab_barrier(leaving + direction, Box.facing_toward(-direction), perspective)


func move_grabbed_box(box: Box, direction: Vector2i, player_cell: Vector3i, perspective: Perspective) -> bool:
	var unit := boxes_that_would_move(box, direction, perspective)
	if unit.has(floor_of(player_cell, perspective)):
		return false

	if not can_move_one_cell(boxes_grabbed_along_with(box, perspective), unit, direction, perspective):
		return false
	var after := index.moved(unit, step_after_landing(unit, direction, perspective))

	var destination := player_cell + Vector3i(direction.x, direction.y, 0)
	if not after.can_player_be_on(destination, perspective):
		return false
	if would_player_cross_a_stripe(player_cell, direction, after, perspective):
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
