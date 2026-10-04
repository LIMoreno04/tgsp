class_name LevelIndex
extends RefCounted

const LOWEST_Z := -1
const GRID_UP := Vector3i(0, 0, 1)
const GRID_DOWN := Vector3i(0, 0, -1)

const NEIGHBOURS_3D: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	GRID_UP, GRID_DOWN,
]
const NEIGHBOURS_2D: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


#==================La snapshot==================

## Cada celda ocupada y su caja.
var cells_3D: Dictionary[Vector3i, Box] = {}
## La caja de arriba de cada columna.
var grid_2D: Dictionary[Vector2i, Box] = {}

var _cell_of: Dictionary[Box, Vector3i] = {} # En una snapshot hipotética una caja no está en su world_cell, así que se usa esto.
var _lowest_z := 0
var _highest_z := 0


func add(box: Box, cell: Vector3i) -> void:
	if cells_3D.has(cell):
		push_error("Two boxes share the cell %s: %s and %s." % [cell, cells_3D[cell].get_path(), box.get_path()])
		return
	cells_3D[cell] = box
	_cell_of[box] = cell
	_lowest_z = mini(_lowest_z, cell.z)
	_highest_z = maxi(_highest_z, cell.z)
	var column := Vector2i(cell.x, cell.y)
	if not grid_2D.has(column) or cell_of(grid_2D[column]).z < cell.z:
		grid_2D[column] = box


func cell_of(box: Box) -> Vector3i:
	return _cell_of[box]

func column_of(box: Box) -> Vector2i:
	var cell := cell_of(box)
	return Vector2i(cell.x, cell.y)

func top_of(column: Vector2i) -> Box:
	return grid_2D.get(column)


## Esta snapshot, sin algunas cajas.
func without(boxes: Array[Box]) -> LevelIndex:
	var rest := LevelIndex.new()
	rest.cells_3D = cells_3D.duplicate()
	rest.grid_2D = grid_2D.duplicate()
	rest._cell_of = _cell_of.duplicate()
	rest._lowest_z = _lowest_z
	rest._highest_z = _highest_z
	for box in boxes:
		rest.cells_3D.erase(cell_of(box))
		rest._cell_of.erase(box)
	for box in boxes:
		var column := column_of(box)
		if rest.grid_2D.get(column) == box:
			rest._recalculate_the_top(column)
	return rest

## Esta snapshot, con algunas cajas movidas un paso.
func moved(boxes: Array[Box], step: Vector3i) -> LevelIndex:
	var after := without(boxes)
	for box in boxes:
		after.add(box, cell_of(box) + step)
	return after


func _recalculate_the_top(column: Vector2i) -> void:
	grid_2D.erase(column)
	for z in range(_highest_z, _lowest_z - 1, -1):
		var box: Box = cells_3D.get(Vector3i(column.x, column.y, z))
		if box != null:
			grid_2D[column] = box
			return


#==================Qué se mueve junto==================

static func same_structure(a: Box, b: Box) -> bool:
	if a.get_parent() is Structure and b.get_parent() is Structure:
		return a.get_parent() == b.get_parent()
	else:
		return a == b


## En 3D, cara a cara; en 2D, tapa con tapa. Nunca pasa por las cajas de `avoiding`.
func boxes_of_same_structure_connected_to(box: Box, perspective: Room.Perspective, avoiding: Array[Box] = []) -> Array[Box]:
	var connected: Array[Box] = [box]
	var to_look_around: Array[Box] = [box]
	while not to_look_around.is_empty():
		var current: Box = to_look_around.pop_back()
		for neighbour in _neighbours_of(current, perspective):
			if same_structure(current, neighbour) and not connected.has(neighbour) and not avoiding.has(neighbour):
				connected.append(neighbour)
				to_look_around.append(neighbour)
	return connected

## En 3D, las cajas de las seis celdas de al lado; en 2D, las tapas de las cuatro columnas de al lado.
func _neighbours_of(box: Box, perspective: Room.Perspective) -> Array[Box]:
	var neighbours: Array[Box] = []
	if Room.is_3d(perspective):
		for direction in NEIGHBOURS_3D:
			var neighbour: Box = cells_3D.get(cell_of(box) + direction)
			if neighbour != null:
				neighbours.append(neighbour)
	elif Room.is_2d(perspective):
		for direction in NEIGHBOURS_2D:
			var neighbour := top_of(column_of(box) + direction)
			if neighbour != null:
				neighbours.append(neighbour)
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
	return neighbours


## En 2D, también las cajas de la misma estructura tapadas por las que se agarran.
func boxes_grabbed_along_with(box: Box, perspective: Room.Perspective) -> Array[Box]:
	var structure := boxes_of_same_structure_connected_to(box, perspective)
	if Room.is_3d(perspective):
		return structure

	for tile: Box in structure.duplicate():
		var column := column_of(tile)
		for z in range(cell_of(tile).z - 1, LOWEST_Z - 1, -1):
			var hidden: Box = cells_3D.get(Vector3i(column.x, column.y, z))
			if hidden == null:
				continue
			if not same_structure(tile, hidden):
				break
			if not structure.has(hidden):
				structure.append(hidden)
	return structure

## En 3D, también las estructuras apoyadas encima que pueden venir.
func boxes_that_would_move(box: Box, direction: Vector2i, perspective: Room.Perspective) -> Array[Box]:
	var unit := boxes_grabbed_along_with(box, perspective)
	if Room.is_2d(perspective):
		return unit

	var someone_joined := true
	while someone_joined:
		someone_joined = false
		for unit_box: Box in unit.duplicate():
			var above: Box = cells_3D.get(cell_of(unit_box) + GRID_UP)
			if above == null or unit.has(above):
				continue
			var rider := boxes_of_same_structure_connected_to(above, perspective)
			if not can_move_one_cell(rider, unit, direction, perspective):
				continue
			for rider_box in rider:
				if not unit.has(rider_box):
					unit.append(rider_box)
					someone_joined = true
	return unit


#==================Movimiento==================

# Todas las reglas de un movimiento que no dependen del jugador.
func can_move_grabbed_box(box: Box, direction: Vector2i, perspective: Room.Perspective) -> bool:
	var unit := boxes_that_would_move(box, direction, perspective)
	if not can_move_one_cell(boxes_grabbed_along_with(box, perspective), unit, direction, perspective):
		return false
	if would_uncover_a_column_it_could_not_go_over(unit, direction, perspective):
		return false
	return not would_leave_anything_floating(unit, step_after_landing(unit, direction, perspective))


func can_move_one_cell(structure: Array[Box], already_moving: Array[Box], direction: Vector2i, perspective: Room.Perspective) -> bool:
	if contains_terrain(structure):
		return false
	if Room.is_3d(perspective):
		for structure_box in structure:
			var occupant: Box = cells_3D.get(cell_of(structure_box) + Vector3i(direction.x, direction.y, 0))
			if occupant != null and not structure.has(occupant) and not already_moving.has(occupant):
				return false
		return true
	elif Room.is_2d(perspective):
		var rest_of_the_room := without(already_moving)
		for structure_box in structure:
			if not rest_of_the_room.could_go_over(column_of(structure_box) + direction):
				return false
		return true
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
		return false

func could_go_over(column: Vector2i) -> bool:
	var top := top_of(column)
	return top == null or top.walkable

# En 2D, para no hacer aparecer cajas de la nada.
func would_uncover_a_column_it_could_not_go_over(unit: Array[Box], direction: Vector2i, perspective: Room.Perspective) -> bool:
	if not Room.is_2d(perspective):
		return false
	var rest_of_the_room := without(unit)
	var covered_after: Dictionary[Vector2i, bool] = {}
	for unit_box in unit:
		covered_after[column_of(unit_box) + direction] = true
	for unit_box in unit:
		var column := column_of(unit_box)
		if not covered_after.has(column) and not rest_of_the_room.could_go_over(column):
			return true
	return false


# calcula el cambio de altura (mecánica de aterrizar)
func step_after_landing(unit: Array[Box], direction: Vector2i, perspective: Room.Perspective) -> Vector3i:
	var step := Vector3i(direction.x, direction.y, 0)
	if not Room.is_2d(perspective):
		return step

	var rest_of_the_room := without(unit)
	var rises: Array[int] = []
	for unit_box in unit:
		var landing := rest_of_the_room.top_of(column_of(unit_box) + direction)
		if landing != null:
			rises.append(cell_of(landing).z + 1 - cell_of(unit_box).z)
	if not rises.is_empty():
		step.z = rises.max()
	if keeps_its_height(unit):
		step.z = maxi(step.z, 0)
	return step

static func keeps_its_height(boxes: Array[Box]) -> bool:
	for box in boxes:
		if box.keeps_height:
			return true
	return false


func would_leave_anything_floating(unit: Array[Box], step: Vector3i) -> bool:
	var after := moved(unit, step)
	if not after.is_held(unit):
		return true
	for left_behind in pieces_left_behind(unit):
		if not contains_terrain(left_behind) and not after.is_held(left_behind):
			return true
	return false


func pieces_left_behind(unit: Array[Box]) -> Array[Array]:
	var pieces: Array[Array] = []
	for unit_box in unit:
		for direction: Vector3i in NEIGHBOURS_3D:
			var neighbour: Box = cells_3D.get(cell_of(unit_box) + direction)
			if neighbour == null or unit.has(neighbour):
				continue
			if direction == GRID_UP or same_structure(unit_box, neighbour):
				pieces.append(_piece_without(neighbour, unit))
	return pieces

func _piece_without(box: Box, unit: Array[Box]) -> Array[Box]:
	return boxes_of_same_structure_connected_to(box, Room.Perspective.ISO_3D, unit)

func is_held(boxes: Array[Box]) -> bool:
	if rests_on_something(boxes):
		return true
	return keeps_its_height(boxes) and touches_something(boxes)

## Si alguna de estas cajas tiene abajo una caja que no es otra del array.
func rests_on_something(boxes: Array[Box]) -> bool:
	for box in boxes:
		var below: Box = cells_3D.get(cell_of(box) + GRID_DOWN)
		if below != null and not boxes.has(below):
			return true
	return false

## La misma idea, pero por los seis lados.
func touches_something(boxes: Array[Box]) -> bool:
	for box in boxes:
		for direction: Vector3i in NEIGHBOURS_3D:
			var neighbour: Box = cells_3D.get(cell_of(box) + direction)
			if neighbour != null and not boxes.has(neighbour):
				return true
	return false

static func contains_terrain(boxes: Array[Box]) -> bool:
	for box in boxes:
		if box.is_terrain():
			return true
	return false


#==================Jugador==================

func floor_of(cell: Vector3i, perspective: Room.Perspective) -> Box:
	var floor_box: Box = null
	if Room.is_3d(perspective):
		floor_box = cells_3D.get(cell + GRID_DOWN)
	elif Room.is_2d(perspective):
		floor_box = top_of(Vector2i(cell.x, cell.y))
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")

	return floor_box

func can_player_be_on(player_position: Vector3i, perspective: Room.Perspective) -> bool:
	var floor_box := floor_of(player_position, perspective)
	if Room.is_3d(perspective):
		return floor_box != null and floor_box.walkable and not cells_3D.has(player_position)
	elif Room.is_2d(perspective):
		return floor_box != null and floor_box.walkable
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
		return false

func is_occluded(cell: Vector3i) -> bool:
	var roof := top_of(Vector2i(cell.x, cell.y))
	return roof != null and cell_of(roof).z >= cell.z

func has_grab_barrier(column: Vector2i, facing: Box.Facing, perspective: Room.Perspective) -> bool:
	if not Room.is_2d(perspective):
		return false
	var tile := top_of(column)
	return tile != null and tile.walkable and tile.movable_2d_from(facing)


func choose_box_to_grab(player_cell: Vector3i, facing: Vector2, perspective: Room.Perspective) -> Box:
	var player_column := Vector2i(player_cell.x, player_cell.y)
	var chosen: Box = null
	var best_alignment := -INF
	for direction: Vector2i in NEIGHBOURS_2D:
		if has_grab_barrier(player_column, Box.facing_toward(direction), perspective):
			continue
		var neighbour: Box = null
		if Room.is_3d(perspective):
			neighbour = cells_3D.get(player_cell + Vector3i(direction.x, direction.y, 0))
		elif Room.is_2d(perspective):
			neighbour = top_of(player_column + direction)
		else:
			assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
			return null
		if neighbour == null:
			continue
		var face_toward_player := Box.facing_toward(-direction)
		if Room.is_3d(perspective) and not neighbour.movable_3d_from(face_toward_player):
			continue
		if Room.is_2d(perspective) and not neighbour.movable_2d_from(face_toward_player):
			continue
		var alignment := facing.dot(Vector2(direction))
		if alignment > best_alignment:
			chosen = neighbour
			best_alignment = alignment
	return chosen


func can_player_move_grabbed_box(box: Box, direction: Vector2i, player_cell: Vector3i, perspective: Room.Perspective) -> bool:
	var unit := boxes_that_would_move(box, direction, perspective)
	if unit.has(floor_of(player_cell, perspective)):
		return false
	if not can_move_grabbed_box(box, direction, perspective):
		return false
	var after := moved(unit, step_after_landing(unit, direction, perspective))
	var destination := player_cell + Vector3i(direction.x, direction.y, 0)
	if not after.can_player_be_on(destination, perspective):
		return false
	return not would_player_cross_a_stripe(player_cell, direction, after, perspective)


func would_player_cross_a_stripe(player_cell: Vector3i, direction: Vector2i, after: LevelIndex, perspective: Room.Perspective) -> bool:
	var leaving := Vector2i(player_cell.x, player_cell.y)
	if has_grab_barrier(leaving, Box.facing_toward(direction), perspective):
		return true
	return after.has_grab_barrier(leaving + direction, Box.facing_toward(-direction), perspective)


enum ColliderType { POS_X, NEG_X, POS_Y, NEG_Y, SOLID }

const EDGE_COLLIDER_ON: Dictionary[Box.Facing, ColliderType] = {
	Box.Facing.POS_X: ColliderType.POS_X,
	Box.Facing.NEG_X: ColliderType.NEG_X,
	Box.Facing.POS_Y: ColliderType.POS_Y,
	Box.Facing.NEG_Y: ColliderType.NEG_Y,
}

## [SOLID] = collider tapando la celda entera, [POS_X, NEG_Y, etc] = collider sólo en esos bordes de la celda (sólo en 2D)
## Básicamente agarra todas las columnas del plano + las que están al lado de las caminables (así agarra agujeros y el borde del mapa)
func colliders_plane(height: int, perspective: Room.Perspective) -> Dictionary[Vector2i, Array]:
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
