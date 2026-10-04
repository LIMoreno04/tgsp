class_name LevelIndex
extends RefCounted
## Dónde está cada caja, en las dos perspectivas.
## Room tiene el estado actual; para saber cómo quedaría todo después de mover algo arma otro,
## hipotético, y le hace las preguntas correspondientes.

## Cada celda ocupada y su caja.
var cells_3D: Dictionary[Vector3i, Box] = {}
## La caja de arriba de cada columna.
var grid_2D: Dictionary[Vector2i, Box] = {}

var _cell_of: Dictionary[Box, Vector3i] = {}


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


func cell_of(box: Box) -> Vector3i: # Necesaria en la versión hipotética para validar movimientos, dónde la ubicación de las cajas no corresponde
	return _cell_of[box]


## Este estado excluyendo algunas cajas
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
		var column := Vector2i(cell_of(box).x, cell_of(box).y)
		if rest.grid_2D.get(column) == box:
			rest._recalculate_the_top(column)
	return rest

## Este estado, con algunas cajas movidas un paso
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


func top_of(column: Vector2i) -> Box:
	return grid_2D.get(column)

## En 2D una caja puede quedar sobre algo caminable o sobre el vacío. Que algo de la unidad siga
## apoyado lo decide Room.would_leave_anything_floating, igual que en 3D.
func could_go_over(column: Vector2i) -> bool:
	var top := top_of(column)
	return top == null or top.walkable

## Si alguna de estas cajas tiene una caja abajo que no es otra del array.
func rests_on_something(boxes: Array[Box]) -> bool:
	for box in boxes:
		var below: Box = cells_3D.get(cell_of(box) + Room.GRID_DOWN)
		if below != null and not boxes.has(below):
			return true
	return false

## Misma idea pero para los 6 lados de la caja.
func touches_something(boxes: Array[Box]) -> bool:
	for box in boxes:
		for direction: Vector3i in Room.NEIGHBOURS_3D:
			var neighbour: Box = cells_3D.get(cell_of(box) + direction)
			if neighbour != null and not boxes.has(neighbour):
				return true
	return false


func floor_of(cell: Vector3i, perspective: Room.Perspective) -> Box:
	var floor_box: Box = null
	if Room.is_3d(perspective):
		var floor_cell := cell + Room.GRID_DOWN
		floor_box = cells_3D[floor_cell] if cells_3D.has(floor_cell) else null
	elif Room.is_2d(perspective):
		floor_box = grid_2D.get(Vector2i(cell.x,cell.y))
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")

	return floor_box

func can_player_be_on(player_position: Vector3i, perspective: Room.Perspective) -> bool:
	var floor_box = floor_of(player_position, perspective)
	if Room.is_3d(perspective):
		return floor_box != null and floor_box.walkable and not cells_3D.has(player_position)
	elif Room.is_2d(perspective):
		return floor_box != null and floor_box.walkable
	else:
		assert(false, "Error CATASTRÓFICO: Perspectiva no definida")
		return false

func is_occluded(cell: Vector3i) -> bool:
	var roof := top_of(Vector2i(cell.x,cell.y))
	return roof != null and cell_of(roof).z >= cell.z

func has_grab_barrier(column: Vector2i, facing: Box.Facing, perspective: Room.Perspective) -> bool:
	if not Room.is_2d(perspective):
		return false
	var tile := top_of(column)
	return tile != null and tile.walkable and tile.movable_2d_from(facing)
