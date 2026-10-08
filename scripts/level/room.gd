@tool
class_name Room
extends Node3D


#==================General=====================
signal dimensions_changed
signal moved
signal buttons_changed
signal power_changed

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
	var closed_doors := index.closed_doors
	index = _index_of_the_boxes_in_the_tree()
	index.closed_doors = closed_doors

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

func button_states() -> Dictionary[ButtonPowerable, bool]:
	var states: Dictionary[ButtonPowerable, bool] = {}
	for powerable in index.every_powerable():
		var button := powerable as ButtonPowerable
		if button != null:
			states[button] = button.switched_on
	return states

## `displayed_as_on` también vuelve: los rayos se trazan desde las puertas y los emisores como se
## ven, así que sin eso una puerta que un láser sostenía quedaría sostenida.
func restore(cells: Dictionary[Box, Vector3i], switched_on: Dictionary[ButtonPowerable, bool], displayed_as_on: Dictionary[Powerable, bool]) -> void:
	for box in cells:
		box.cell = cells[box]
	for button in switched_on:
		button.switched_on = switched_on[button]
	rebuild_index()
	_show_power_as(displayed_as_on)
	moved.emit()
	buttons_changed.emit()


#==================Powerables==================

## Solo Room cambia el estado de un powerable, como los movimientos
func press(button: ButtonPowerable) -> void:
	button.switched_on = not button.switched_on
	buttons_changed.emit()


## Displayed en vez de directo "on" porque las puertas pueden estar abiertas y no estar recibiendo power
var _powerables_displayed_as_on: Dictionary[Powerable, bool] = {}

var doors_stopped_by_the_player: Array[Door] = []

var beams: Array[LevelIndex.Beam] = []
var _hit_by_lasers: Dictionary[Powerable, bool] = {}


func update_power(perspective: Perspective, player_cell: Vector3i, player_body: Rect2) -> void:
	_hit_by_lasers = index.hit_by_lasers(_beams_of_the_active_emitters(perspective), perspective, player_cell.z, player_body)
	var active := index.active_powerables(perspective, player_cell, _hit_by_lasers)
	var new_powerables_displayed_as_on: Dictionary[Powerable, bool] = {}
	var closed_doors: Array[Door] = []
	doors_stopped_by_the_player = []
	for powerable in index.every_powerable():
		if powerable is Door:
			if index.door_is_open(powerable, active, perspective, player_cell.z, player_body):
				new_powerables_displayed_as_on[powerable] = true
			else:
				closed_doors.append(powerable)
			if index.is_body_across(powerable, perspective, player_cell.z, player_body):
				doors_stopped_by_the_player.append(powerable)
		elif active.has(powerable):
			new_powerables_displayed_as_on[powerable] = true
	index.closed_doors = closed_doors
	_react_to_what_changed(new_powerables_displayed_as_on)
	beams = _beams_of_the_active_emitters(perspective)
	show_the_beams(perspective, player_cell.z, player_body)


func is_power_out_of_date(perspective: Perspective, player_height: int, player_body: Rect2) -> bool:
	for door in doors_stopped_by_the_player:
		if not index.is_body_across(door, perspective, player_height, player_body):
			return true
	return index.hit_by_lasers(beams, perspective, player_height, player_body) != _hit_by_lasers

func show_the_beams(perspective: Perspective, player_height: int, player_body: Rect2) -> void:
	for beam in beams:
		beam.emitter.show_beam(index.beam_length_with_the_body(beam, perspective, player_height, player_body))

func powerables_displayed_as_on() -> Dictionary[Powerable, bool]:
	return _powerables_displayed_as_on.duplicate()

func _show_power_as(displayed_as_on: Dictionary[Powerable, bool]) -> void:
	var closed_doors: Array[Door] = []
	for powerable in index.every_powerable():
		if powerable is Door and not displayed_as_on.has(powerable):
			closed_doors.append(powerable)
	index.closed_doors = closed_doors
	_react_to_what_changed(displayed_as_on)

func _beams_of_the_active_emitters(perspective: Perspective) -> Array[LevelIndex.Beam]:
	var shining: Array[LevelIndex.Beam] = []
	for powerable in _powerables_displayed_as_on:
		if powerable is LaserEmitter:
			shining.append(index.beam_of(powerable, perspective, maximum_reach()))
	return shining

func _react_to_what_changed(displayed_as_on: Dictionary[Powerable, bool]) -> void:
	var anything_changed := false
	for powerable in index.every_powerable():
		if displayed_as_on.has(powerable) == _powerables_displayed_as_on.has(powerable):
			continue
		anything_changed = true
		if displayed_as_on.has(powerable):
			powerable.turn_on()
		else:
			powerable.turn_off()
	_powerables_displayed_as_on = displayed_as_on
	if anything_changed:
		power_changed.emit()

#==================Avisos en el editor==================

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		warnings.append("The Room must sit at the origin, unrotated and unscaled: the rules only see the cells of its boxes, so moving the Room moves them on screen but not for the rules.")
	var spawn_index := _index_of_the_boxes_in_the_tree()
	var spawn_column := Vector2i(player_spawn_point.x, player_spawn_point.y)
	if not spawn_index.can_player_be_on(player_spawn_point, _starting_perspective()) or spawn_index.has_button_on(spawn_column, _starting_perspective(), player_spawn_point.z):
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
