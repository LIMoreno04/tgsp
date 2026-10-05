@tool
class_name Room
extends Node3D


#==================General=====================
signal dimensions_changed
signal moved

@export var dimensions: Vector3i = Vector3i(5, 5, 5):
	set(value):
		dimensions = value
		dimensions_changed.emit()
		notify_property_list_changed()
		update_configuration_warnings()
@export var player_spawn_point: Vector3i = Vector3i(2, 2, 0):
	set(value):
		player_spawn_point = value
		update_configuration_warnings()

@export_tool_button("Print map 3D", "3D") var print3d := _print_map_3d_button
@export_tool_button("Print map 2D", "2D") var print2d := _print_map_2d_button


func _init() -> void:
	set_notify_local_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		update_configuration_warnings()

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

#==================La snapshot del nivel==================

## El mapa del nivel
var index := LevelIndex.new()

func rebuild_index() -> void:
	index = _index_of_the_boxes_in_the_tree()

func _index_of_the_boxes_in_the_tree() -> LevelIndex:
	var new_index := LevelIndex.new()
	for child in get_children():
		if child is RoomShell:
			for part in child.get_children():
				if part is Structure:
					_add_structure_to_index(part, new_index)
		elif child is GridEntity:
			_add_nested_nodes_to_index(child, new_index)
	return new_index

func _add_structure_to_index(structure: Structure, to_index: LevelIndex) -> void:
	for box in structure.boxes():
		to_index.add(box, box.world_cell)

func _add_nested_nodes_to_index(node: GridEntity, to_index: LevelIndex) -> void:
	if node is Box:
		to_index.add(node, node.world_cell)
	elif node is Structure:
		_add_structure_to_index(node, to_index)
	else:
		for child in node.get_children():
			if child is GridEntity:
				_add_nested_nodes_to_index(child, to_index)


func maximum_reach() -> Vector3i:
	var x_max := dimensions.x
	var y_max := dimensions.y
	var z_max := dimensions.z
	for occupied_cell: Vector3i in index.cells_3D:
		x_max = max(x_max, occupied_cell.x + 1)
		y_max = max(y_max, occupied_cell.y + 1)
		z_max = max(z_max, occupied_cell.z + 1) #el +1 porque las coords de grilla empiezan en 0,0,0; y acá busco tamaño, no coords
	return Vector3i(x_max,y_max,z_max)

func volumetric_center() -> Vector3:
	return GridCoordsProvider.grid_to_godot(maximum_reach())*(0.5)

#==================Movimiento==================

func try_to_move_grabbed_box(box: Box, direction: Vector2i, perspective: Perspective) -> bool:
	if not index.can_move_grabbed_box(box, direction, perspective):
		return false
	_move_the_unit_of(box, direction, perspective)
	return true

func move_grabbed_box(box: Box, direction: Vector2i, player_cell: Vector3i, perspective: Perspective) -> bool:
	if not index.can_player_move_grabbed_box(box, direction, player_cell, perspective):
		return false
	_move_the_unit_of(box, direction, perspective)
	return true

func _move_the_unit_of(grabbed: Box, direction: Vector2i, perspective: Perspective) -> void:
	var unit := index.boxes_that_would_move(grabbed, direction, perspective)
	var step := index.step_after_landing(unit, direction, perspective)
	for unit_box in unit:
		unit_box.cell += step
	rebuild_index()
	moved.emit()

## donde está cada caja ahora
func box_cells() -> Dictionary[Box, Vector3i]:
	var cells: Dictionary[Box, Vector3i] = {}
	for box: Box in index.cells_3D.values():
		cells[box] = box.cell
	return cells

func restore(cells: Dictionary[Box, Vector3i]) -> void:
	for box in cells:
		box.cell = cells[box]
	rebuild_index()
	moved.emit()

#==================Avisos en el editor==================

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		warnings.append("The Room must sit at the origin, unrotated and unscaled: the rules only see the cells of its boxes, so moving the Room moves them on screen but not for the rules.")
	if not _index_of_the_boxes_in_the_tree().can_player_be_on(player_spawn_point, _starting_perspective()):
		warnings.append("The player cannot stand at player_spawn_point %s in the perspective the level starts in." % player_spawn_point)
	return warnings

func _starting_perspective() -> Perspective:
	if perspective_manager == null:
		return Perspective.ISO_3D
	return perspective_manager.starting_perspective

#==================Debug: los índices en el Output==================

## En el editor el índice sólo se arma en _ready, así que los botones lo rehacen antes
## de imprimir.
func _print_map_3d_button() -> void:
	rebuild_index()
	RoomMapPrinter.new(self).print_cells_3D()

func _print_map_2d_button() -> void:
	rebuild_index()
	RoomMapPrinter.new(self).print_grid_2D()
