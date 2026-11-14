@tool
class_name LevelEdits
extends RefCounted
## El único lugar que cambia un nivel. Cada operación calcula todo primero y después lo anota en la
## historia como una sola acción: instancia los prefabs, los agrega como hijos, les pone dueño y les
## cambia propiedades, como lo haría alguien a mano en Godot.

const BOX_SCENE: PackedScene = preload("res://scenes/prefabs/box.tscn")
const STRUCTURE_SCENE: PackedScene = preload("res://scenes/prefabs/structure.tscn")
const GRID_ENTITY_SCRIPT: Script = preload("res://scripts/core/grid_entity.gd")

## Cada tipo de powerable, por el nombre de su clase.
const PIECE_SCENE: Dictionary[StringName, PackedScene] = {
	&"Wire": preload("res://scenes/prefabs/powerables/wire.tscn"),
	&"ButtonPowerable": preload("res://scenes/prefabs/powerables/button.tscn"),
	&"PressurePlate": preload("res://scenes/prefabs/powerables/pressure_plate.tscn"),
	&"Door": preload("res://scenes/prefabs/powerables/door.tscn"),
	&"ExitDoor": preload("res://scenes/prefabs/powerables/exit_door.tscn"),
	&"LaserEmitter": preload("res://scenes/prefabs/powerables/laser_emitter.tscn"),
	&"LaserReceiver": preload("res://scenes/prefabs/powerables/laser_receiver.tscn"),
}

## Las caras en que va cada tipo.
const PIECE_FACES: Dictionary[StringName, Array] = {
	&"Wire": [Powerable.Face.TOP, Powerable.Face.BOTTOM, Powerable.Face.POS_X, Powerable.Face.NEG_X, Powerable.Face.POS_Y, Powerable.Face.NEG_Y],
	&"ButtonPowerable": [Powerable.Face.TOP, Powerable.Face.POS_X, Powerable.Face.NEG_X, Powerable.Face.POS_Y, Powerable.Face.NEG_Y],
	&"PressurePlate": [Powerable.Face.TOP],
	&"Door": [Powerable.Face.TOP],
	&"ExitDoor": [Powerable.Face.TOP],
	&"LaserEmitter": [Powerable.Face.POS_X, Powerable.Face.NEG_X, Powerable.Face.POS_Y, Powerable.Face.NEG_Y],
	&"LaserReceiver": [Powerable.Face.POS_X, Powerable.Face.NEG_X, Powerable.Face.POS_Y, Powerable.Face.NEG_Y],
}

## Las opciones propias de cada tipo, además de la cara y las direcciones.
const PIECE_OPTIONS: Dictionary[StringName, Array] = {
	&"Wire": [],
	&"ButtonPowerable": [&"switched_on"],
	&"PressurePlate": [],
	&"Door": [&"edge", &"always_open"],
	&"ExitDoor": [&"edge", &"always_open", &"next_level"],
	&"LaserEmitter": [&"always_on"],
	&"LaserReceiver": [],
}

const CONNECTS: Dictionary[Vector3i, StringName] = {
	Vector3i(1, 0, 0): &"connects_pos_x",
	Vector3i(-1, 0, 0): &"connects_neg_x",
	Vector3i(0, 1, 0): &"connects_pos_y",
	Vector3i(0, -1, 0): &"connects_neg_y",
	Vector3i(0, 0, 1): &"connects_up",
	Vector3i(0, 0, -1): &"connects_down",
}

var root: Node
var room: Room
var history: LevelEditorHistory
## Dentro del editor, GEN_EDIT_STATE_INSTANCE, para que lo nuevo se guarde como una instancia puesta
## a mano; fuera del editor no existe.
var edit_state := PackedScene.GEN_EDIT_STATE_DISABLED

var _action_name := ""
var _merge_with_the_last := false
var _do_ops: Array[Array] = []
var _undo_steps: Array[Array] = []
var _keep_while_done: Array[Object] = []
var _keep_while_undone: Array[Object] = []


func _init(level_root: Node, level_room: Room, level_history: LevelEditorHistory) -> void:
	root = level_root
	room = level_room
	history = level_history


#==================Las cajas==================

## Pinta cajas en las celdas libres de `cells`. `extending`: la Structure a la que se suman (Shift), o
## null para uno nuevo en `folder`. Las de piso o pared en el marco de la cáscara van a esa parte.
## Devuelve cuántas cajas puso.
func paint(brush: BoxBrush, cells: Array[Vector3i], extending: Structure, folder: Node) -> int:
	var free: Array[Vector3i] = []
	for cell in cells:
		if not room.index.cells_3D.has(cell) and not free.has(cell):
			free.append(cell)
	if free.is_empty():
		return 0
	var into_the_shell: Dictionary[Structure, Array] = {}
	var into_the_structure: Array[Vector3i] = []
	for cell in free:
		var part := shell_part_at(cell) if brush.is_terrain() else null
		if part != null:
			if not into_the_shell.has(part):
				into_the_shell[part] = []
			into_the_shell[part].append(cell)
		else:
			into_the_structure.append(cell)

	_begin("Paint %d %s box%s" % [free.size(), brush.label(), "" if free.size() == 1 else "es"])
	for part: Structure in into_the_shell:
		var cells_in_part: Array[Vector3i] = []
		cells_in_part.assign(into_the_shell[part])
		for cell in cells_in_part:
			_add_new_box(part, cell - part.world_cell, brush.flags_for(_is_the_top_of_its_column(cell, cells_in_part), {}))
	if not into_the_structure.is_empty():
		_paint_into_a_structure(brush, into_the_structure, extending, folder)
	_commit()
	return free.size()


func _paint_into_a_structure(brush: BoxBrush, cells: Array[Vector3i], extending: Structure, folder: Node) -> void:
	var structure := extending
	var final_cells: Dictionary[Box, Vector3i] = {}
	if structure == null:
		structure = STRUCTURE_SCENE.instantiate(edit_state) as Structure
		structure.name = brush.structure_name()
		var parent := folder if folder != null else room
		var low := _low_corner(cells)
		structure.cell = low - _world_cell_of(parent)
		structure.dimensions = _high_corner(cells) - low + Vector3i.ONE
		_add(structure, parent)
	else:
		for box in structure.boxes():
			final_cells[box] = box.world_cell
	var all_cells: Array[Vector3i] = cells.duplicate()
	all_cells.append_array(final_cells.values())
	var anchor := _low_corner(all_cells)
	if extending != null:
		_anchor(structure, final_cells, anchor, _high_corner(all_cells) - anchor + Vector3i.ONE)
	var structure_cells: Dictionary[Vector3i, bool] = {}
	for cell in all_cells:
		structure_cells[cell] = true
	for cell in cells:
		var flags := brush.flags_for(_is_the_top_of_its_column(cell, cells), _outside_edges(cell, structure_cells))
		_add_new_box(structure, cell - anchor, flags)
	if brush.walkable_tops and extending != null:
		_stop_covered_boxes_being_walkable(structure, cells)


func _add_new_box(parent: Structure, cell: Vector3i, flags: Dictionary[StringName, bool]) -> Box:
	var box := BOX_SCENE.instantiate(edit_state) as Box
	box.cell = cell
	for flag in BoxBrush.BOX_FLAGS:
		box.set(flag, flags[flag])
	_add(box, parent)
	return box


func _is_the_top_of_its_column(cell: Vector3i, cells: Array[Vector3i]) -> bool:
	return not cells.has(cell + LevelIndex.GRID_UP)


func _outside_edges(cell: Vector3i, structure_cells: Dictionary[Vector3i, bool]) -> Dictionary[Box.Facing, bool]:
	var outside: Dictionary[Box.Facing, bool] = {}
	for facing: Box.Facing in Box.FACING_DIRECTION:
		var direction := Box.FACING_DIRECTION[facing]
		outside[facing] = not structure_cells.has(cell + Vector3i(direction.x, direction.y, 0))
	return outside


## Una caja caminable tapada por otra de la misma Structure deja de serlo, como lo dejaría "Mark exposed
## tops walkable".
func _stop_covered_boxes_being_walkable(structure: Structure, painted: Array[Vector3i]) -> void:
	for box in structure.boxes():
		if box.walkable and not box.is_floor and painted.has(box.world_cell + LevelIndex.GRID_UP):
			_set_box_flags(box, {&"walkable": false})


## Borra cajas y powerables. Lo que queda en una Structure se vuelve a anclar; una Structure vacía se borra.
## `keep_the_arms`: los vecinos de un powerable borrado siguen apuntando adonde estaba, para una conexión
## que se arma jugando (una caja con cable que se empuja ahí).
func erase(boxes: Array[Box], pieces: Array[Powerable], keep_the_arms := false) -> void:
	boxes = _live_boxes(boxes)
	pieces = _live_pieces(pieces)
	if boxes.is_empty() and pieces.is_empty():
		return
	var erased_boxes: Dictionary[Box, bool] = {}
	for box in boxes:
		erased_boxes[box] = true
	var lone_pieces: Array[Powerable] = []
	for piece in pieces:
		if not erased_boxes.has(piece.box):
			lone_pieces.append(piece)
	# Los powerables de las cajas borradas se van con ellas, y sus vecinos también dejan de apuntarlos.
	var going_pieces: Array[Powerable] = lone_pieces.duplicate()
	for box in boxes:
		for child in box.get_children():
			if child is Powerable and not going_pieces.has(child):
				going_pieces.append(child)
	var parts := PackedStringArray()
	if not boxes.is_empty():
		parts.append("%d box%s" % [boxes.size(), "" if boxes.size() == 1 else "es"])
	if not lone_pieces.is_empty():
		parts.append("%d piece%s" % [lone_pieces.size(), "" if lone_pieces.size() == 1 else "s"])
	_begin("Erase " + " and ".join(parts))
	if not keep_the_arms:
		_untick_the_neighbours_of(going_pieces, erased_boxes)
	for piece in _in_removal_order(lone_pieces):
		_remove(piece)
	_make_the_boxes_under_walkable(boxes, erased_boxes)
	var touched: Dictionary[Structure, bool] = {}
	for box in boxes:
		var structure := box.get_parent() as Structure
		if structure != null and not is_shell_part(structure):
			touched[structure] = true
	# Una Structure que se queda sin cajas se borra entera, con ellas adentro.
	var emptied: Array[Structure] = []
	for structure: Structure in touched:
		if structure.boxes().all(func(box: Box) -> bool: return erased_boxes.has(box)):
			emptied.append(structure)
	var going_with_their_structure: Dictionary[Box, bool] = {}
	for structure in emptied:
		for box in structure.boxes():
			going_with_their_structure[box] = true
	var removed_alone: Array[Box] = []
	for box in boxes:
		if not going_with_their_structure.has(box):
			removed_alone.append(box)
	for box in _in_removal_order(removed_alone):
		_remove(box)
	for structure in _in_removal_order(emptied):
		_remove(structure)
	for structure: Structure in touched:
		if emptied.has(structure):
			continue
		var remaining: Dictionary[Box, Vector3i] = {}
		for box in structure.boxes():
			if not erased_boxes.has(box):
				remaining[box] = box.world_cell
		_reanchor(structure, remaining)
	_commit()


func _make_the_boxes_under_walkable(boxes: Array[Box], erased: Dictionary[Box, bool]) -> void:
	for box in boxes:
		if not box.walkable or box.is_floor:
			continue
		var below: Box = room.index.cells_3D.get(box.world_cell + LevelIndex.GRID_DOWN)
		if below != null and not erased.has(below) and LevelIndex.same_structure(below, box) and not below.walkable and not below.movable_2d_whole_face:
			_set_box_flags(below, {&"walkable": true})


## Le pone las banderas de la brocha a cajas que ya existen, sin cambiarlas de Structure.
func repaint(boxes: Array[Box], brush: BoxBrush) -> void:
	boxes = _live_boxes(boxes)
	if boxes.is_empty():
		return
	_begin("Repaint %d box%s as %s" % [boxes.size(), "" if boxes.size() == 1 else "es", brush.label()])
	for box in boxes:
		var above: Box = room.index.cells_3D.get(box.world_cell + LevelIndex.GRID_UP)
		var structure_cells: Dictionary[Vector3i, bool] = {}
		for sibling in boxes_of_the_structure_of(box):
			structure_cells[sibling.world_cell] = true
		_set_box_flags(box, brush.flags_for(above == null, _outside_edges(box.world_cell, structure_cells)))
	_commit()


## Cambia banderas de varias cajas a la vez: Properties y Handles.
func set_box_flags(boxes: Array[Box], changes: Dictionary[StringName, bool], action_name: String) -> void:
	boxes = _live_boxes(boxes)
	if boxes.is_empty():
		return
	_begin(action_name)
	for box in boxes:
		_set_box_flags(box, changes)
	_commit()


## Cada caja con sus propios cambios.
func set_flags_per_box(changes_per_box: Dictionary[Box, Dictionary], action_name: String) -> void:
	for box: Box in changes_per_box.keys():
		if not is_in_the_level(box):
			changes_per_box.erase(box)
	if changes_per_box.is_empty():
		return
	_begin(action_name)
	for box: Box in changes_per_box:
		var changes: Dictionary[StringName, bool] = {}
		changes.assign(changes_per_box[box])
		_set_box_flags(box, changes)
	_commit()


func _set_box_flags(box: Box, changes: Dictionary[StringName, bool]) -> void:
	var before := flags_of(box)
	var after := before.duplicate()
	for flag in changes:
		after[flag] = changes[flag]
	if changes.get(&"movable_2d_whole_face", false):
		after[&"walkable"] = false
	if changes.get(&"walkable", false):
		after[&"movable_2d_whole_face"] = false
	if after[&"is_floor"]:
		after[&"walkable"] = true
		after[&"movable_2d_whole_face"] = false
	# El terreno no se mueve: unas asas que quedaran escondidas sólo ensuciarían el archivo.
	if after[&"is_floor"] or after[&"is_wall"]:
		for flag in BoxBrush.BOX_FLAGS:
			if String(flag).begins_with("movable"):
				after[flag] = false
	if after == before:
		return
	var do_ops: Array[Array] = []
	var undo_ops: Array[Array] = []
	for flag in BoxBrush.BOX_FLAGS:
		do_ops.append([box, flag, after[flag]])
		undo_ops.append([box, flag, before[flag]])
	_step(do_ops, undo_ops)


static func flags_of(box: Box) -> Dictionary[StringName, bool]:
	var flags: Dictionary[StringName, bool] = {}
	for flag in BoxBrush.BOX_FLAGS:
		flags[flag] = box.get(flag)
	return flags


#==================Mover y agrupar==================

## Mueve cajas un paso. Una Structure que se mueve entera mueve su nodo; si no, se mueven sus cajas y se
## vuelve a anclar. Devuelve false si el paso cae sobre una caja que no se mueve.
func move(boxes: Array[Box], step: Vector3i, merge_with_the_last := false, verb := "Move") -> bool:
	boxes = _live_boxes(boxes)
	if boxes.is_empty() or step == Vector3i.ZERO or not can_move(boxes, step):
		return false
	var moving: Dictionary[Box, bool] = {}
	for box in boxes:
		moving[box] = true
	var by_structure: Dictionary[Node, Array] = {}
	for box in boxes:
		var parent := box.get_parent()
		if not by_structure.has(parent):
			by_structure[parent] = []
		by_structure[parent].append(box)
	_begin("%s %d box%s" % [verb, boxes.size(), "" if boxes.size() == 1 else "es"], merge_with_the_last)
	for parent: Node in by_structure:
		var structure := parent as Structure
		if structure != null and by_structure[parent].size() == structure.boxes().size():
			_change(structure, &"cell", structure.cell + step)
		elif structure != null:
			var final_cells: Dictionary[Box, Vector3i] = {}
			for box in structure.boxes():
				final_cells[box] = box.world_cell + (step if moving.has(box) else Vector3i.ZERO)
			_reanchor(structure, final_cells)
		else:
			for box: Box in by_structure[parent]:
				_change(box, &"cell", box.cell + step)
	_commit()
	return true


func can_move(boxes: Array[Box], step: Vector3i) -> bool:
	var moving: Dictionary[Box, bool] = {}
	for box in boxes:
		moving[box] = true
	for box in boxes:
		if is_shell_part(box.get_parent()):
			return false
		var occupant: Box = room.index.cells_3D.get(box.world_cell + step)
		if occupant != null and not moving.has(occupant):
			return false
	return true


## Pone las cajas en una Structure nueva. Las Structures que quedan vacías se borran.
func join_into_one_structure(boxes: Array[Box]) -> Structure:
	var movable: Array[Box] = []
	for box in _live_boxes(boxes):
		if not is_shell_part(box.get_parent()):
			movable.append(box)
	if movable.is_empty() or mixes_terrain(movable):
		return null
	var first_structure := movable[0].get_parent()
	var parent := first_structure.get_parent() if first_structure is Structure else first_structure
	var cells: Array[Vector3i] = []
	for box in movable:
		cells.append(box.world_cell)
	var new_structure := STRUCTURE_SCENE.instantiate(edit_state) as Structure
	var kind := BoxBrush.kind_of(movable[0])
	new_structure.name = BoxBrush.STRUCTURE_NAME[kind]
	var low := _low_corner(cells)
	new_structure.cell = low - _world_cell_of(parent)
	new_structure.dimensions = _high_corner(cells) - low + Vector3i.ONE
	_begin("Join %d boxes into one structure" % movable.size())
	_add(new_structure, parent)
	_take_boxes_out_of_their_structures(movable, new_structure, low)
	_commit()
	return new_structure


## Cada caja de las Structures queda en una Structure propia; la primera se queda en la de siempre.
func split_into_one_box_structures(structures: Array[Structure]) -> void:
	var splitting: Array[Structure] = []
	for each_structure in structures:
		if is_in_the_level(each_structure) and not is_shell_part(each_structure) and each_structure.boxes().size() > 1:
			splitting.append(each_structure)
	if splitting.is_empty():
		return
	_begin("Split %d structure%s into one-box structures" % [splitting.size(), "" if splitting.size() == 1 else "s"])
	for each_structure in splitting:
		var boxes := each_structure.boxes()
		var keep := boxes[0]
		for box in boxes.slice(1):
			var alone := STRUCTURE_SCENE.instantiate(edit_state) as Structure
			alone.name = BoxBrush.STRUCTURE_NAME[BoxBrush.kind_of(box)]
			alone.cell = box.world_cell - _world_cell_of(each_structure.get_parent())
			_add(alone, each_structure.get_parent())
			_reparent(box, alone, Vector3i.ZERO)
		_reanchor(each_structure, {keep: keep.world_cell})
	_commit()


func _take_boxes_out_of_their_structures(boxes: Array[Box], into: Structure, into_anchor: Vector3i) -> void:
	var leaving: Dictionary[Box, bool] = {}
	var old_structures: Dictionary[Structure, bool] = {}
	for box in boxes:
		leaving[box] = true
		var old := box.get_parent() as Structure
		if old != null:
			old_structures[old] = true
	for box in _in_removal_order(boxes):
		_reparent(box, into, box.world_cell - into_anchor)
	for old: Structure in old_structures:
		var remaining: Dictionary[Box, Vector3i] = {}
		for box in old.boxes():
			if not leaving.has(box):
				remaining[box] = box.world_cell
		if remaining.is_empty():
			_remove(old)
		else:
			_reanchor(old, remaining)


#==================Structures, carpetas y nombres==================

func rename(node: Node, new_name: String) -> void:
	new_name = new_name.strip_edges().validate_node_name()
	if not is_in_the_level(node) or new_name.is_empty() or new_name == node.name:
		return
	_begin("Rename %s to %s" % [node.name, new_name])
	_change(node, &"name", new_name)
	_commit()


func new_folder(parent: Node) -> Node3D:
	var folder := Node3D.new()
	folder.set_script(GRID_ENTITY_SCRIPT)
	folder.name = "Folder"
	_begin("New folder")
	_add(folder, parent)
	_commit()
	return folder


## A otra carpeta (o al Room), sin que cambie ninguna celda del mundo. Lo que ya está ahí, la carpeta
## misma, lo que la contiene y la cáscara se quedan donde están.
func move_into(nodes: Array[Node], new_parent: Node) -> void:
	var moving: Array[Node] = []
	if not is_in_the_level(new_parent) and new_parent != room:
		return
	for node in nodes:
		if not is_in_the_level(node) or not node is Node3D or node.get_parent() == new_parent or node == new_parent or node.is_ancestor_of(new_parent):
			continue
		if is_shell_part(node) or node is RoomShell:
			continue
		moving.append(node)
	# Lo que está dentro de otra cosa que también se mueve va con ella.
	var outermost: Array[Node] = []
	for node in moving:
		if not moving.any(func(other: Node) -> bool: return other.is_ancestor_of(node)):
			outermost.append(node)
	if outermost.is_empty():
		return
	_begin("Move %s into %s" % [outermost[0].name if outermost.size() == 1 else "%d structures and folders" % outermost.size(), new_parent.name])
	for node in _in_removal_order(outermost):
		_reparent(node as Node3D, new_parent, _world_cell_of(node) - _world_cell_of(new_parent))
	_commit()


func delete_nodes(nodes: Array[Node], action_name: String) -> void:
	var deleting: Array[Node] = []
	for node in nodes:
		if is_in_the_level(node) and not is_shell_part(node) and not node is RoomShell:
			deleting.append(node)
	if deleting.is_empty():
		return
	_begin(action_name)
	for node in _in_removal_order(deleting):
		_remove(node)
	_commit()


#==================Powerables==================

## Pone un powerable en una cara libre, y lo une a los vecinos que ya lo apuntan.
func place_piece(type: StringName, box: Box, face: Powerable.Face, options: Dictionary) -> Powerable:
	if not is_in_the_level(box) or box.powerable_on(face) != null or not PIECE_FACES[type].has(face):
		return null
	var piece := new_piece(type, face, options)
	for direction in directions_toward_pieces_pointing_at(FaceLinks.FaceAt.new(box.world_cell, face), {}):
		piece.set(CONNECTS[direction], true)
	_begin("Place %s" % piece_label(type))
	_add(piece, box)
	_commit()
	return piece


func new_piece(type: StringName, face: Powerable.Face, options: Dictionary) -> Powerable:
	var piece := PIECE_SCENE[type].instantiate(edit_state) as Powerable
	piece.face = face
	for option in options:
		if PIECE_OPTIONS[type].has(option):
			piece.set(option, options[option])
	return piece


## Las direcciones de una cara hacia vecinos que ya la apuntan, en 3D o en 2D. `pending`: caras con
## powerables que todavía no están en el árbol (las de un cable a medio poner).
func directions_toward_pieces_pointing_at(at: FaceLinks.FaceAt, pending: Dictionary[String, Powerable]) -> Array[Vector3i]:
	var directions: Array[Vector3i] = []
	for link in _links_of(at):
		var neighbour := piece_at(link.to, pending)
		if neighbour != null and neighbour.allowed_directions().has(link.direction_there) and not directions.has(link.direction_here):
			directions.append(link.direction_here)
	return directions


## Pone cables en las caras libres del camino y une cada dos caras seguidas por los dos lados.
func lay_wire(path: Array[FaceLinks.FaceAt], perspective: Room.Perspective) -> void:
	if path.is_empty():
		return
	var pending: Dictionary[String, Powerable] = {}
	var new_wires: Array[Powerable] = []
	var boxes_of_new_wires: Array[Box] = []
	for at in path:
		var box: Box = room.index.cells_3D.get(at.cell)
		if box == null or piece_at(at, pending) != null:
			continue
		var wire := new_piece(&"Wire", at.face, {})
		pending[_key(at)] = wire
		new_wires.append(wire)
		boxes_of_new_wires.append(box)
	var ticks: Dictionary[Powerable, Array] = {}
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var directions := FaceLinks.link(a, b, perspective)
		if directions.is_empty():
			continue
		_want_tick(ticks, piece_at(a, pending), directions[0])
		_want_tick(ticks, piece_at(b, pending), directions[1])
	for i in new_wires.size():
		var at := FaceLinks.FaceAt.new(boxes_of_new_wires[i].world_cell, new_wires[i].face)
		for direction in directions_toward_pieces_pointing_at(at, pending):
			_want_tick(ticks, new_wires[i], direction)
	if new_wires.is_empty() and ticks.is_empty():
		return
	_begin("Lay wire across %d face%s" % [path.size(), "" if path.size() == 1 else "s"])
	for i in new_wires.size():
		for direction: Vector3i in ticks.get(new_wires[i], []):
			new_wires[i].set(CONNECTS[direction], true)
		_add(new_wires[i], boxes_of_new_wires[i])
	for piece: Powerable in ticks:
		if new_wires.has(piece):
			continue
		for direction: Vector3i in ticks[piece]:
			_change(piece, CONNECTS[direction], true)
	_commit()


func _want_tick(ticks: Dictionary[Powerable, Array], piece: Powerable, direction: Vector3i) -> void:
	if piece == null or piece.allowed_directions().has(direction):
		return
	if not ticks.has(piece):
		ticks[piece] = []
	if not ticks[piece].has(direction):
		ticks[piece].append(direction)


## Cuando se borra un powerable, sus vecinos dejan de apuntarlo, salvo que esa dirección todavía los
## una a otra cosa en alguna de las dos vistas.
func _untick_the_neighbours_of(pieces: Array[Powerable], erased_boxes: Dictionary[Box, bool]) -> void:
	var going: Dictionary[String, bool] = {}
	for piece in pieces:
		going[_key(face_of(piece))] = true
	var unticked: Dictionary[String, bool] = {}
	for piece in pieces:
		var at := face_of(piece)
		for link in _links_of(at):
			if not piece.allowed_directions().has(link.direction_here):
				continue
			var neighbour := piece_at(link.to, {})
			if neighbour == null or going.has(_key(link.to)) or erased_boxes.has(neighbour.box):
				continue
			if not neighbour.allowed_directions().has(link.direction_there):
				continue
			var key := "%s/%s" % [_key(link.to), link.direction_there]
			if unticked.has(key) or _still_connects_through(neighbour, link.to, link.direction_there, going):
				continue
			unticked[key] = true
			_change(neighbour, CONNECTS[link.direction_there], false)


func _still_connects_through(piece: Powerable, at: FaceLinks.FaceAt, direction: Vector3i, going: Dictionary[String, bool]) -> bool:
	for link in _links_of(at):
		if link.direction_here != direction or going.has(_key(link.to)):
			continue
		var other := piece_at(link.to, {})
		if other != null and other != piece and other.allowed_directions().has(link.direction_there):
			return true
	return false


## Los enlaces de una cara en las dos vistas. En 2D una tapa sólo cuenta si es la de su columna.
func _links_of(at: FaceLinks.FaceAt) -> Array[FaceLinks.Link]:
	var all := FaceLinks.links_in_3d(at, room.index.cells_3D)
	var box: Box = room.index.cells_3D.get(at.cell)
	if at.face == Powerable.Face.TOP and box != null and room.index.top_of(Vector2i(at.cell.x, at.cell.y)) == box:
		all.append_array(FaceLinks.links_in_2d(at, room.index.grid_2D, room.index))
	return all


func set_piece_properties(pieces: Array[Powerable], changes: Dictionary, action_name: String) -> void:
	pieces = _live_pieces(pieces)
	if pieces.is_empty():
		return
	_begin(action_name)
	for piece in pieces:
		for property in changes:
			if property in piece:
				_change(piece, property, changes[property])
	_commit()


func piece_at(at: FaceLinks.FaceAt, pending: Dictionary[String, Powerable]) -> Powerable:
	if pending.has(_key(at)):
		return pending[_key(at)]
	var box: Box = room.index.cells_3D.get(at.cell)
	if box == null:
		return null
	return box.powerable_on(at.face)


func face_of(piece: Powerable) -> FaceLinks.FaceAt:
	return FaceLinks.FaceAt.new(piece.box.world_cell, piece.face)


static func piece_type(piece: Powerable) -> StringName:
	return (piece.get_script() as Script).get_global_name()


static func piece_label(type: StringName) -> String:
	match type:
		&"ButtonPowerable": return "button"
		&"PressurePlate": return "plate"
		&"Door": return "door"
		&"ExitDoor": return "exit"
		&"LaserEmitter": return "laser emitter"
		&"LaserReceiver": return "laser receiver"
	return "wire"


static func _key(at: FaceLinks.FaceAt) -> String:
	return "%s/%d" % [at.cell, at.face]


#==================El nivel==================

func set_room_size(dimensions: Vector3i) -> void:
	if dimensions == room.dimensions or dimensions.x <= 0 or dimensions.y <= 0 or dimensions.z <= 0:
		return
	_begin("Resize the room to %d × %d × %d" % [dimensions.x, dimensions.y, dimensions.z])
	_change(room, &"dimensions", dimensions)
	_commit()


func set_spawn(cell: Vector3i) -> void:
	if cell == room.player_spawn_point:
		return
	_begin("Move the spawn to %s" % cell)
	_change(room, &"player_spawn_point", cell)
	_commit()


func set_starting_perspective(perspective: Room.Perspective) -> void:
	var manager := room.perspective_manager
	if manager == null or manager.starting_perspective == perspective:
		return
	_begin("Start in %s" % ("2D" if Room.is_2d(perspective) else "3D"))
	_change(manager, &"starting_perspective", perspective)
	_commit()


#==================Copiar y pegar==================

## Una copia de Structures como datos, no como nodos: así pegarla es pintar con banderas exactas.
class Clip:
	## Cada Structure: {"name": String, "boxes": [{"cell": Vector3i, "flags": Dictionary}], "pieces": [{"cell", "type", "face", "properties"}]}
	var structures: Array[Dictionary] = []
	## Todas sus celdas, desde su esquina baja.
	var cells: Array[Vector3i] = []

	func is_empty() -> bool:
		return structures.is_empty()


func copy(boxes: Array[Box]) -> Clip:
	var clip := Clip.new()
	boxes = _live_boxes(boxes)
	if boxes.is_empty():
		return clip
	var world_cells: Array[Vector3i] = []
	for box in boxes:
		world_cells.append(box.world_cell)
	var low := _low_corner(world_cells)
	var by_structure: Dictionary[Node, Array] = {}
	for box in boxes:
		var key: Node = box.get_parent() if box.get_parent() is Structure and not is_shell_part(box.get_parent()) else box
		if not by_structure.has(key):
			by_structure[key] = []
		by_structure[key].append(box)
	for key: Node in by_structure:
		var data := {"name": String(key.name) if key is Structure else BoxBrush.STRUCTURE_NAME[BoxBrush.kind_of(key)], "boxes": [], "pieces": []}
		for box: Box in by_structure[key]:
			data["boxes"].append({"cell": box.world_cell - low, "flags": flags_of(box)})
			clip.cells.append(box.world_cell - low)
			for piece in box.powerables():
				data["pieces"].append({"cell": box.world_cell - low, "type": piece_type(piece), "face": piece.face, "properties": properties_of(piece)})
		clip.structures.append(data)
	return clip


static func properties_of(piece: Powerable) -> Dictionary:
	var properties := {}
	for property: StringName in CONNECTS.values():
		properties[property] = piece.get(property)
	for option: StringName in PIECE_OPTIONS[piece_type(piece)]:
		properties[option] = piece.get(option)
	return properties


func can_paste(clip: Clip, at: Vector3i) -> bool:
	for cell in clip.cells:
		if room.index.cells_3D.has(cell + at):
			return false
	return not clip.is_empty()


func paste(clip: Clip, at: Vector3i, folder: Node) -> Array[Structure]:
	var pasted: Array[Structure] = []
	if not can_paste(clip, at):
		return pasted
	var parent := folder if folder != null else room
	_begin("Paste %d structure%s" % [clip.structures.size(), "" if clip.structures.size() == 1 else "s"])
	for data in clip.structures:
		var cells: Array[Vector3i] = []
		for box_data: Dictionary in data["boxes"]:
			cells.append(box_data["cell"] + at)
		var low := _low_corner(cells)
		var new_structure := STRUCTURE_SCENE.instantiate(edit_state) as Structure
		new_structure.name = data["name"]
		new_structure.cell = low - _world_cell_of(parent)
		new_structure.dimensions = _high_corner(cells) - low + Vector3i.ONE
		_add(new_structure, parent)
		var boxes_at: Dictionary[Vector3i, Box] = {}
		for box_data: Dictionary in data["boxes"]:
			var flags: Dictionary[StringName, bool] = {}
			flags.assign(box_data["flags"])
			boxes_at[box_data["cell"]] = _add_new_box(new_structure, box_data["cell"] + at - low, flags)
		for piece_data: Dictionary in data["pieces"]:
			var piece := PIECE_SCENE[piece_data["type"]].instantiate(edit_state) as Powerable
			piece.face = piece_data["face"]
			for property in piece_data["properties"]:
				piece.set(property, piece_data["properties"][property])
			_add(piece, boxes_at[piece_data["cell"]])
		pasted.append(new_structure)
	_commit()
	return pasted


#==================Preguntas sobre el nivel==================

## Si está en el nivel. Lo que un deshacer sacó a mitad de un trazo (el trazo lo tenía guardado) no se
## toca: sacarlo de nuevo, o cambiarlo, rompería la historia.
func is_in_the_level(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and room.is_ancestor_of(node)


func _live_boxes(boxes: Array[Box]) -> Array[Box]:
	var live: Array[Box] = []
	for box in boxes:
		if is_in_the_level(box):
			live.append(box)
	return live


func _live_pieces(pieces: Array[Powerable]) -> Array[Powerable]:
	var live: Array[Powerable] = []
	for piece in pieces:
		if is_in_the_level(piece):
			live.append(piece)
	return live

func shell() -> RoomShell:
	for child in room.get_children():
		if child is RoomShell:
			return child
	return null


func is_shell_part(node: Node) -> bool:
	return node != null and node.get_parent() is RoomShell


## La parte de la cáscara cuyo marco tiene esa celda, como la arma RoomShell, o null.
func shell_part_at(cell: Vector3i) -> Structure:
	var the_shell := shell()
	if the_shell == null:
		return null
	var size := room.dimensions
	if cell.z == -1 and cell.x >= 0 and cell.x < size.x and cell.y >= 0 and cell.y < size.y:
		return the_shell.get_node_or_null(RoomShell.FLOOR) as Structure
	if cell.x == -1 and cell.y >= -1 and cell.y < size.y and cell.z >= -1 and cell.z < size.z:
		return the_shell.get_node_or_null(RoomShell.WALL_X) as Structure
	if cell.y == -1 and cell.x >= 0 and cell.x < size.x and cell.z >= -1 and cell.z < size.z:
		return the_shell.get_node_or_null(RoomShell.WALL_Y) as Structure
	return null


## Las cajas de la Structure de una caja: las de su Structure, o ella sola si está suelta.
func boxes_of_the_structure_of(box: Box) -> Array[Box]:
	var structure := box.get_parent() as Structure
	if structure == null:
		return [box]
	return structure.boxes()


static func mixes_terrain(boxes: Array[Box]) -> bool:
	var terrain := 0
	for box in boxes:
		if box.is_terrain():
			terrain += 1
	return terrain > 0 and terrain < boxes.size()


## Si sumar cajas de ese tipo a la Structure mezclaría terreno con lo que no lo es.
static func would_mix_terrain(structure: Structure, terrain: bool) -> bool:
	if structure == null:
		return false
	for box in structure.boxes():
		if box.is_terrain() != terrain:
			return true
	return false


#==================Los pasos de una acción==================

func _begin(action_name: String, merge_with_the_last := false) -> void:
	_action_name = action_name
	_merge_with_the_last = merge_with_the_last
	_do_ops = []
	_undo_steps = []
	_keep_while_done = []
	_keep_while_undone = []


## Un paso: lo que hace y lo que lo deshace. Cada operación es un Callable o [objeto, propiedad, valor].
func _step(do_ops: Array[Array], undo_ops: Array[Array]) -> void:
	_do_ops.append_array(do_ops)
	_undo_steps.append(undo_ops)


## Hace los pasos en orden y los deshace en el orden inverso, cada uno con sus operaciones en orden.
## Una acción que no cambia nada no llega a la historia.
func _commit() -> void:
	if _do_ops.is_empty():
		_undo_steps = []
		return
	history.create_action(_action_name, _merge_with_the_last)
	for op in _do_ops:
		_send(op, true)
	for i in range(_undo_steps.size() - 1, -1, -1):
		for op: Array in _undo_steps[i]:
			_send(op, false)
	for object in _keep_while_done:
		history.add_do_reference(object)
	for object in _keep_while_undone:
		history.add_undo_reference(object)
	history.commit_action()
	_do_ops = []
	_undo_steps = []


func _send(op: Array, doing: bool) -> void:
	if op.size() == 1:
		if doing:
			history.add_do_method(op[0])
		else:
			history.add_undo_method(op[0])
	elif doing:
		history.add_do_property(op[0], op[1], op[2])
	else:
		history.add_undo_property(op[0], op[1], op[2])


func _change(object: Object, property: StringName, value: Variant) -> void:
	var before: Variant = object.get(property)
	if typeof(before) == typeof(value) and before == value:
		return
	_step([[object, property, value]], [[object, property, before]])


func _add(node: Node, parent: Node) -> void:
	var do_ops: Array[Array] = [[parent.add_child.bind(node, true)]]
	for owned in _nodes_to_own(node):
		do_ops.append([owned.set_owner.bind(root)])
	_step(do_ops, [[parent.remove_child.bind(node)]])
	_keep_while_done.append(node)


func _remove(node: Node) -> void:
	var parent := node.get_parent()
	var undo_ops: Array[Array] = [[parent.add_child.bind(node)], [parent.move_child.bind(node, node.get_index())]]
	for owned in _nodes_owned_with(node):
		undo_ops.append([owned.set_owner.bind(root)])
	_step([[parent.remove_child.bind(node)]], undo_ops)
	_keep_while_undone.append(node)


## A otro padre, con otra celda; vuelve con su nombre, su lugar entre hermanos y su celda de antes.
func _reparent(node: Node3D, new_parent: Node, new_cell: Vector3i) -> void:
	var old_parent := node.get_parent()
	var owned := _nodes_owned_with(node)
	var do_ops: Array[Array] = [[old_parent.remove_child.bind(node)], [new_parent.add_child.bind(node, true)], [node, &"cell", new_cell]]
	var undo_ops: Array[Array] = [[new_parent.remove_child.bind(node)], [old_parent.add_child.bind(node)], [old_parent.move_child.bind(node, node.get_index())], [node, &"name", node.name], [node, &"cell", node.get(&"cell")]]
	for each in owned:
		do_ops.append([each.set_owner.bind(root)])
		undo_ops.append([each.set_owner.bind(root)])
	_step(do_ops, undo_ops)


## Lo que se guarda con un nodo nuevo: él y los nodos del nivel que ya tenga adentro. Lo de adentro de
## una instancia (la Mesh de una caja) es de la instancia, y el dibujo de un powerable no se guarda.
func _nodes_to_own(node: Node) -> Array[Node]:
	var owned: Array[Node] = [node]
	for child in node.get_children():
		if child is GridEntity or child is Powerable:
			owned.append_array(_nodes_to_own(child))
	return owned


## Varios hermanos se sacan del último al primero, así al deshacer cada uno vuelve a su lugar.
func _in_removal_order(nodes: Array) -> Array[Node]:
	var ordered: Array[Node] = []
	ordered.assign(nodes)
	ordered.sort_custom(func(a: Node, b: Node) -> bool: return a.get_index() > b.get_index())
	return ordered


## Lo que hoy se guarda con un nodo: él y los nodos de abajo cuyo dueño es la raíz del nivel.
func _nodes_owned_with(node: Node) -> Array[Node]:
	var owned: Array[Node] = [node]
	for descendant in node.find_children("*", "", true, false):
		if descendant.owner == root:
			owned.append(descendant)
	return owned


## Vuelve a anclar una Structure para que su celda sea la esquina baja de sus cajas y sus dimensiones las
## de su caja envolvente, sin que cambie ninguna celda del mundo.
func _reanchor(structure: Structure, final_cells: Dictionary[Box, Vector3i]) -> void:
	if is_shell_part(structure) or final_cells.is_empty():
		return
	var cells: Array[Vector3i] = []
	cells.assign(final_cells.values())
	var anchor := _low_corner(cells)
	_anchor(structure, final_cells, anchor, _high_corner(cells) - anchor + Vector3i.ONE)


func _anchor(structure: Structure, final_cells: Dictionary[Box, Vector3i], anchor: Vector3i, dimensions: Vector3i) -> void:
	_change(structure, &"cell", anchor - _world_cell_of(structure.get_parent()))
	_change(structure, &"dimensions", dimensions)
	for box: Box in final_cells:
		_change(box, &"cell", final_cells[box] - anchor)


static func _world_cell_of(node: Node) -> Vector3i:
	if node is GridEntity:
		return (node as GridEntity).world_cell
	return Vector3i.ZERO


static func _low_corner(cells: Array[Vector3i]) -> Vector3i:
	var low := cells[0]
	for cell in cells:
		low = low.min(cell)
	return low


static func _high_corner(cells: Array[Vector3i]) -> Vector3i:
	var high := cells[0]
	for cell in cells:
		high = high.max(cell)
	return high
