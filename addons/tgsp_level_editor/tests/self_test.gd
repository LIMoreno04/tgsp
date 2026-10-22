@tool
extends RefCounted
## La prueba del editor de niveles, dentro del editor: arma un nivel de prueba con New level, hace
## cada operación con la historia de la escena, la deshace y la rehace, y mira el árbol y el archivo.
## Se corre con: --headless --editor --path . -- --level-editor-self-test
## Con --level-editor-screenshots (sin --headless) además saca capturas de la pestaña.

const SCRATCH_PATH := "res://addons/tgsp_level_editor/tests/_scratch_level.tscn"

var _plugin: EditorPlugin
var _screen: LevelEditorScreen
var _failures := 0
var _passes := 0
var _tree: SceneTree


func run(plugin: EditorPlugin, screen: LevelEditorScreen) -> int:
	_plugin = plugin
	_screen = screen
	_tree = EditorInterface.get_base_control().get_tree()
	# En la ventana el editor tarda en terminar de arrancar; hasta entonces no abre escenas.
	await _frames(120)
	if not OS.get_cmdline_user_args().has("--level-editor-self-test"):
		await _screenshots()
		return 0
	if FileAccess.file_exists(SCRATCH_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))
	await _plugin.call(&"_create_a_new_level", SCRATCH_PATH, Vector3i(8, 6, 3))
	await _frames(5)
	var root := EditorInterface.get_edited_scene_root()
	_check("New level opens the scratch level", root != null and root.scene_file_path == SCRATCH_PATH)
	# Nunca tocar otra escena: todo lo de abajo cambia y guarda la escena abierta.
	if not _on_the_scratch_level():
		print("  ABORT   the scratch level isn't the open scene, so nothing else is tested. Open: %s, edited: %s" % [EditorInterface.get_open_scenes(), root.scene_file_path if root != null else "nothing"])
		_failures += 1
		return await _finish()
	var room := _screen.room
	_check("  its room is 8 × 6 × 3", room.dimensions == Vector3i(8, 6, 3))
	_check("  the spawn is on the middle tile", room.player_spawn_point == Vector3i(4, 3, 0))
	_check("  the shell is complete", room.index.cells_3D.size() == 8 * 6 + 1 * 7 * 4 + 8 * 1 * 4)
	_check("  its UID isn't the template's", _uid_of(SCRATCH_PATH) != _uid_of("res://scenes/prefabs/level_template.tscn"))

	await _test_painting(room)
	await _test_erasing(room)
	await _test_the_shell(room)
	await _test_moving_and_grouping(room)
	await _test_power(room)
	await _test_folders_and_names(room)
	await _test_copy_and_paste(room)
	await _test_the_level(room)
	_test_picking(room)
	await _test_speed(room)
	await _test_real_input(room)
	await _test_undo_and_redo_everything(room)
	await _test_layers_2d_and_lasers(room)
	await _test_changes_from_outside(room)
	await _test_the_panels(room)
	await _test_more_shortcuts_and_tools(room)
	var back_on_the_scratch_level: bool = await _test_the_new_level_dialog()
	if not back_on_the_scratch_level:
		print("  ABORT   couldn't get back to the scratch level, so the saved file isn't tested.")
		_failures += 1
		return await _finish()
	await _test_the_saved_file()
	var failures: int = await _finish()
	if OS.get_cmdline_user_args().has("--level-editor-screenshots"):
		await _screenshots()
	return failures


func _finish() -> int:
	print("LEVEL EDITOR SELF-TEST: %d passed, %d failed" % [_passes, _failures])
	for path in EditorInterface.get_open_scenes():
		if path == SCRATCH_PATH or path == SECOND_SCRATCH_PATH:
			EditorInterface.open_scene_from_path(path)
			await _frames(3)
			EditorInterface.close_scene()
			await _frames(3)
	for path in [SCRATCH_PATH, SECOND_SCRATCH_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return _failures


func _check(label: String, condition: bool) -> void:
	if condition:
		_passes += 1
		print("    ok    ", label)
	else:
		_failures += 1
		print("  FAIL    ", label)


func _frames(count: int) -> void:
	for i in count:
		await _tree.process_frame


func _settle() -> void:
	await _frames(2)


## El giro entre 2D y 3D dura un tiempo de verdad: en una pantalla rápida son muchos cuadros.
func _until_the_turn_ends() -> void:
	for frame in 600:
		await _tree.process_frame
		if not _screen.view.is_turning():
			break
	await _frames(3)


func _undo() -> void:
	_screen.history.undo()
	await _settle()


func _redo() -> void:
	_screen.history.redo()
	await _settle()


static func _uid_of(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_line() if file != null else ""


func _box_at(room: Room, cell: Vector3i) -> Box:
	return room.index.cells_3D.get(cell)


#==================Pintar==================

func _test_painting(room: Room) -> void:
	var edits := _screen.edits
	var brush := BoxBrush.for_kind(BoxBrush.Kind.MOVABLE)
	edits.paint(brush, [Vector3i(1, 1, 0), Vector3i(2, 1, 0)], null, null)
	await _settle()
	var first := _box_at(room, Vector3i(1, 1, 0))
	var group := first.get_parent() as Structure if first != null else null
	_check("Painting two Movable boxes makes one group", group != null and group.boxes().size() == 2 and group.name == "Movable")
	if group == null:
		return
	_check("  anchored at its low corner", group.cell == Vector3i(1, 1, 0) and group.dimensions == Vector3i(2, 1, 1))
	_check("  with the Movable flags", first.movable_3d_pos_x and first.movable_3d_neg_y and first.movable_2d_whole_face and not first.walkable)
	_check("  owned by the level, so saved", group.owner == _screen.level_root and first.owner == _screen.level_root)
	await _undo()
	_check("  undo takes them away", _box_at(room, Vector3i(1, 1, 0)) == null and not is_instance_valid(group.get_parent()))
	await _redo()
	_check("  redo brings back the same nodes", _box_at(room, Vector3i(1, 1, 0)) == first and first.get_parent() == group and group.owner == _screen.level_root)

	edits.paint(brush, [Vector3i(0, 1, 0)], group, null)
	await _settle()
	_check("Shift-extending moves the anchor to the new low corner", group.cell == Vector3i(0, 1, 0) and group.dimensions == Vector3i(3, 1, 1) and group.boxes().size() == 3)
	_check("  without moving any box in the world", _box_at(room, Vector3i(1, 1, 0)) == first and first.cell == Vector3i(1, 0, 0))
	await _undo()
	_check("  undo puts the anchor back", group.cell == Vector3i(1, 1, 0) and first.cell == Vector3i(0, 0, 0) and group.boxes().size() == 2)
	await _redo()

	edits.paint(brush, [Vector3i(1, 1, 0), Vector3i(5, 1, 0)], null, null)
	await _settle()
	_check("Painting skips occupied cells", _box_at(room, Vector3i(5, 1, 0)) != null and _box_at(room, Vector3i(1, 1, 0)) == first)

	var walkable := BoxBrush.for_kind(BoxBrush.Kind.WALKABLE)
	walkable.height = 2
	edits.paint(walkable, [Vector3i(6, 1, 0), Vector3i(6, 1, 1)], null, null)
	await _settle()
	var low := _box_at(room, Vector3i(6, 1, 0))
	var high := _box_at(room, Vector3i(6, 1, 1))
	_check("A Walkable column is walkable only on top", low != null and high != null and not low.walkable and high.walkable)
	var hanging := BoxBrush.for_kind(BoxBrush.Kind.HANGING_PLATFORM)
	hanging.edges_2d[Box.Facing.POS_X] = true
	edits.paint(hanging, [Vector3i(1, 4, 1), Vector3i(2, 4, 1)], null, null)
	await _settle()
	var left := _box_at(room, Vector3i(1, 4, 1))
	var right := _box_at(room, Vector3i(2, 4, 1))
	_check("A Hanging platform keeps its height and draws its top half", left != null and left.keeps_height and left.top_half_only and left.walkable)
	_check("  its 2D edges go only on the outside", right != null and right.movable_2d_pos_x and not left.movable_2d_pos_x)


#==================Borrar==================

func _test_erasing(room: Room) -> void:
	var edits := _screen.edits
	var middle := _box_at(room, Vector3i(1, 1, 0))
	var group := middle.get_parent() as Structure
	var order_before := _names_in_order(group)
	edits.erase([_box_at(room, Vector3i(0, 1, 0))], [])
	await _settle()
	_check("Erasing the low corner re-anchors the group", group.cell == Vector3i(1, 1, 0) and group.boxes().size() == 2 and middle.cell == Vector3i.ZERO)
	await _undo()
	_check("  undo brings it back, in its place in the tree", _names_in_order(group) == order_before and group.cell == Vector3i(0, 1, 0))
	await _redo()
	await _undo()
	var all_boxes := group.boxes()
	edits.erase(all_boxes, [])
	await _settle()
	_check("Erasing a whole group deletes the group", not group.is_inside_tree())
	await _undo()
	_check("  undo brings the group back with its boxes", group.is_inside_tree() and group.boxes().size() == 3 and group.owner == _screen.level_root and all_boxes[0].owner == _screen.level_root)

	var low := _box_at(room, Vector3i(6, 1, 0))
	edits.erase([_box_at(room, Vector3i(6, 1, 1))], [])
	await _settle()
	_check("Erasing a walkable top makes the box under it walkable", low.walkable)
	await _undo()
	_check("  undo makes it unwalkable again", not low.walkable)


static func _names_in_order(node: Node) -> Array[String]:
	var names: Array[String] = []
	for child in node.get_children():
		names.append(child.name)
	return names


#==================La cáscara==================

func _test_the_shell(room: Room) -> void:
	var edits := _screen.edits
	var floor_box := _box_at(room, Vector3i(5, 5, -1))
	var floor_part := floor_box.get_parent()
	edits.erase([floor_box], [])
	await _settle()
	_check("Erasing a shell box leaves a hole", _box_at(room, Vector3i(5, 5, -1)) == null and floor_part.is_inside_tree())
	edits.paint(BoxBrush.for_kind(BoxBrush.Kind.FLOOR), [Vector3i(5, 5, -1)], null, null)
	await _settle()
	var filled := _box_at(room, Vector3i(5, 5, -1))
	_check("A Floor box painted into the hole joins the shell's floor", filled != null and filled.get_parent() == floor_part and filled.is_floor)
	await _undo()
	edits.paint(BoxBrush.for_kind(BoxBrush.Kind.MOVABLE), [Vector3i(5, 5, -1)], null, null)
	await _settle()
	var crate := _box_at(room, Vector3i(5, 5, -1))
	_check("A Movable box in the hole makes its own group", crate != null and crate.get_parent() != floor_part)
	await _undo()
	edits.set_room_size(Vector3i(9, 6, 3))
	await _settle()
	_check("Growing the room keeps the hole", room.dimensions == Vector3i(9, 6, 3) and _box_at(room, Vector3i(5, 5, -1)) == null and _box_at(room, Vector3i(8, 5, -1)) != null)
	await _undo()
	_check("  and undo shrinks it back", room.dimensions == Vector3i(8, 6, 3) and _box_at(room, Vector3i(8, 5, -1)) == null)


#==================Mover y agrupar==================

func _test_moving_and_grouping(room: Room) -> void:
	var edits := _screen.edits
	var corner := _box_at(room, Vector3i(0, 1, 0))
	var group := corner.get_parent() as Structure
	var boxes := group.boxes()
	_check("Moving onto another box is refused", not edits.move(boxes, Vector3i(3, 0, 0)))
	_check("Moving a whole group moves its node", edits.move(boxes, Vector3i(0, 1, 0)))
	await _settle()
	_check("  every box one cell over", _box_at(room, Vector3i(0, 2, 0)) == corner and group.cell == Vector3i(0, 2, 0))
	await _undo()
	_check("  undo moves it back", _box_at(room, Vector3i(0, 1, 0)) == corner)
	edits.move([corner], Vector3i(0, -1, 0))
	await _settle()
	_check("Moving one box of a group re-anchors the group", _box_at(room, Vector3i(0, 0, 0)) == corner and group.cell == Vector3i(0, 0, 0) and group.dimensions == Vector3i(3, 2, 1))
	await _undo()
	var floor_box := _box_at(room, Vector3i(3, 3, -1))
	_check("The shell's boxes don't move", not edits.move([floor_box], Vector3i(0, 0, 1)))

	var lone := _box_at(room, Vector3i(5, 1, 0))
	var lone_group := lone.get_parent()
	var merged := edits.group([corner, lone])
	await _settle()
	_check("Group puts boxes from two groups in one new group", merged != null and corner.get_parent() == merged and lone.get_parent() == merged and not lone_group.is_inside_tree())
	_check("  without moving them", _box_at(room, Vector3i(0, 1, 0)) == corner and _box_at(room, Vector3i(5, 1, 0)) == lone)
	await _undo()
	_check("  undo gives each its group back", corner.get_parent() == group and lone.get_parent() == lone_group and lone_group.is_inside_tree())
	edits.ungroup([group])
	await _settle()
	var parents := {}
	for x in 3:
		parents[_box_at(room, Vector3i(x, 1, 0)).get_parent()] = true
	_check("Ungroup gives each box its own group", group.boxes().size() == 1 and parents.size() == 3)
	await _undo()
	_check("  undo puts them together again", group.boxes().size() == 3)


#==================Powerables==================

func _test_power(room: Room) -> void:
	var edits := _screen.edits
	var button_box := _box_at(room, Vector3i(2, 3, -1))
	var button := edits.place_piece(&"ButtonPowerable", button_box, Powerable.Face.TOP, {&"switched_on": true})
	await _settle()
	_check("Placing a button puts it on the top face", button != null and button.get_parent() == button_box and button.face == Powerable.Face.TOP and button.get(&"switched_on"))
	_check("  owned by the level", button != null and button.owner == _screen.level_root)
	var path: Array[FaceLinks.FaceAt] = []
	for x in [2, 3, 4, 5]:
		path.append(FaceLinks.FaceAt.new(Vector3i(x, 3, -1), Powerable.Face.TOP))
	edits.lay_wire(path, Room.Perspective.ISO_3D)
	await _settle()
	var wire_b := _box_at(room, Vector3i(4, 3, -1)).powerable_on(Powerable.Face.TOP)
	var wire_c := _box_at(room, Vector3i(5, 3, -1)).powerable_on(Powerable.Face.TOP)
	var wire_a := _box_at(room, Vector3i(3, 3, -1)).powerable_on(Powerable.Face.TOP)
	_check("A wire path lays a wire on every free face", wire_a is Wire and wire_b is Wire and wire_c is Wire)
	_check("  and connects the button to the first wire, both ways", room.index.connected_powerables(button, Room.Perspective.ISO_3D).has(wire_a) and room.index.connected_powerables(wire_a, Room.Perspective.ISO_3D).has(button))
	_check("  and each wire to the next", room.index.connected_powerables(wire_a, Room.Perspective.ISO_3D).has(wire_b) and room.index.connected_powerables(wire_b, Room.Perspective.ISO_3D).has(wire_c))
	var door := edits.place_piece(&"Door", _box_at(room, Vector3i(6, 3, -1)), Powerable.Face.TOP, {&"edge": Box.Facing.POS_X})
	await _settle()
	_check("A door placed where a wire's arm points... has no arm toward it yet", door != null and not room.index.connected_powerables(door, Room.Perspective.ISO_3D).has(wire_c))
	await _undo()
	edits.set_piece_properties([wire_c], {&"connects_pos_x": true}, "test")
	await _settle()
	door = edits.place_piece(&"Door", _box_at(room, Vector3i(6, 3, -1)), Powerable.Face.TOP, {&"edge": Box.Facing.POS_X})
	await _settle()
	_check("A door placed where a wire's arm points connects on its own", door != null and room.index.connected_powerables(door, Room.Perspective.ISO_3D).has(wire_c))
	var active := room.index.active_powerables(Room.Perspective.ISO_3D, Vector3i(-50, -50, 0))
	_check("  and the switched-on button powers it", active.has(door))
	edits.erase([], [wire_b])
	await _settle()
	_check("Erasing a wire unticks the arms that pointed at it", not wire_a.connects_pos_x and not wire_c.connects_neg_x)
	_check("  but keeps the others", wire_a.connects_neg_x and wire_c.connects_pos_x)
	await _undo()
	_check("  undo brings the wire and the arms back", is_instance_valid(wire_b) and wire_b.is_inside_tree() and wire_a.connects_pos_x and wire_c.connects_neg_x)
	edits.place_piece(&"PressurePlate", _box_at(room, Vector3i(1, 1, 0)), Powerable.Face.POS_X, {})
	await _settle()
	_check("A plate isn't placed on a side face", _box_at(room, Vector3i(1, 1, 0)).powerable_on(Powerable.Face.POS_X) == null)
	_check("A second piece isn't placed on a taken face", edits.place_piece(&"Wire", button_box, Powerable.Face.TOP, {}) == null)
	_test_face_links(room)


## face_links tiene que decir lo mismo que las reglas: para cada par de caras que une, prender esas
## direcciones hace que connected_powerables las vea unidas.
func _test_face_links(room: Room) -> void:
	var probes: Array[FaceLinks.FaceAt] = [
		FaceLinks.FaceAt.new(Vector3i(1, 1, 0), Powerable.Face.TOP),
		FaceLinks.FaceAt.new(Vector3i(1, 1, 0), Powerable.Face.NEG_Y),
		FaceLinks.FaceAt.new(Vector3i(6, 1, 0), Powerable.Face.POS_Y),
		FaceLinks.FaceAt.new(Vector3i(0, 4, -1), Powerable.Face.TOP),
	]
	var checked := 0
	var agreeing := 0
	for from in probes:
		for link in FaceLinks.links_in_3d(from, room.index.cells_3D):
			var a := Wire.new()
			a.face = from.face
			a.set(LevelEdits.CONNECTS[link.direction_here], true)
			var b := Wire.new()
			b.face = link.to.face
			b.set(LevelEdits.CONNECTS[link.direction_there], true)
			var box_a: Box = room.index.cells_3D[from.cell]
			var box_b: Box = room.index.cells_3D[link.to.cell]
			if box_a.powerable_on(a.face) != null or box_b.powerable_on(b.face) != null or (box_a == box_b and a.face == b.face):
				a.free()
				b.free()
				continue
			box_a.add_child(a)
			box_b.add_child(b)
			checked += 1
			if room.index.connected_powerables(a, Room.Perspective.ISO_3D).has(b) and room.index.connected_powerables(b, Room.Perspective.ISO_3D).has(a):
				agreeing += 1
			else:
				print("      face_links disagrees: %s/%d -> %s/%d" % [from.cell, from.face, link.to.cell, link.to.face])
			box_a.remove_child(a)
			box_b.remove_child(b)
			a.free()
			b.free()
	_check("face_links agrees with connected_powerables (%d of %d links)" % [agreeing, checked], checked > 10 and agreeing == checked)


#==================Carpetas y nombres==================

func _test_folders_and_names(room: Room) -> void:
	var edits := _screen.edits
	var folder := edits.new_folder(room)
	await _settle()
	_check("New folder adds a grid node to the Room", folder.is_inside_tree() and folder is GridEntity and folder.owner == _screen.level_root)
	folder.set(&"cell", Vector3i(10, 0, 0))
	await _settle()
	var box := _box_at(room, Vector3i(6, 1, 0))
	var group := box.get_parent() as Structure
	edits.move_into([group] as Array[Node], folder)
	await _settle()
	_check("Moving a group into a folder keeps it where it is", group.get_parent() == folder and _box_at(room, Vector3i(6, 1, 0)) == box and group.cell == Vector3i(-4, 1, 0))
	await _undo()
	_check("  undo takes it out again", group.get_parent() == room and group.cell == Vector3i(6, 1, 0))
	edits.rename(group, "Tower")
	await _settle()
	_check("Rename renames", group.name == "Tower")
	await _undo()
	_check("  and undo gives the old name back", group.name != "Tower")


#==================Copiar y pegar==================

func _test_copy_and_paste(room: Room) -> void:
	var edits := _screen.edits
	var button_box := _box_at(room, Vector3i(2, 3, -1))
	var crate := _box_at(room, Vector3i(5, 1, 0))
	edits.place_piece(&"LaserEmitter", crate, Powerable.Face.POS_Y, {&"always_on": true})
	await _settle()
	var clip := edits.copy([crate])
	_check("Copy takes the box and its piece", clip.groups.size() == 1 and clip.groups[0]["pieces"].size() == 1)
	_check("A paste onto a box is refused", not edits.can_paste(clip, Vector3i(5, 1, 0)))
	var pasted := edits.paste(clip, Vector3i(5, 4, 0), null)
	await _settle()
	var copy := _box_at(room, Vector3i(5, 4, 0))
	var emitter := copy.powerable_on(Powerable.Face.POS_Y) if copy != null else null
	_check("Paste makes a new group with the same box and piece", pasted.size() == 1 and copy != null and copy.movable_3d_pos_x and emitter is LaserEmitter and emitter.always_on)
	_check("  owned by the level", copy != null and copy.owner == _screen.level_root and emitter != null and emitter.owner == _screen.level_root)
	await _undo()
	_check("  undo takes the paste away", _box_at(room, Vector3i(5, 4, 0)) == null)
	_check("(the button box is untouched)", button_box.powerable_on(Powerable.Face.TOP) is ButtonPowerable)


#==================El nivel==================

func _test_the_level(room: Room) -> void:
	var edits := _screen.edits
	edits.set_spawn(Vector3i(1, 2, 0))
	await _settle()
	_check("Set spawn moves the spawn", room.player_spawn_point == Vector3i(1, 2, 0))
	await _undo()
	_check("  undo moves it back", room.player_spawn_point == Vector3i(4, 3, 0))
	edits.set_starting_perspective(Room.Perspective.TOP_2D)
	await _settle()
	_check("Starting view can be 2D", room.perspective_manager.starting_perspective == Room.Perspective.TOP_2D)
	await _undo()
	var exit := edits.place_piece(&"ExitDoor", _box_at(room, Vector3i(7, 0, -1)), Powerable.Face.TOP, {&"next_level": "res://scenes/levels/test_level.tscn", &"edge": Box.Facing.POS_X})
	await _settle()
	_check("An exit keeps where it leads", exit is ExitDoor and (exit as ExitDoor).next_level == "res://scenes/levels/test_level.tscn")
	_check("  and the Level panel lists it", _screen.exits().has(exit))
	var problems: Array[Array] = _screen._problems.collect()
	var no_exit := problems.any(func(problem: Array) -> bool: return problem[1] == "The level has no exit door.")
	_check("  so Problems doesn't say there's no exit", not no_exit)


#==================Lo que hay bajo el mouse==================

func _test_picking(room: Room) -> void:
	var cells := room.index.cells_3D
	var visible := func(_box: Box) -> bool: return true
	var down := GridPicker.pick(Vector3(3.5, 50, 3.5), Vector3.DOWN, cells, visible, Vector3i(-2, -2, -2), Vector3i(10, 10, 6), 0)
	_check("A ray straight down hits the top of the floor", down.has_box and down.cell == Vector3i(3, 3, -1) and down.face == Powerable.Face.TOP)
	var sideways := GridPicker.pick(Vector3(20, 0.5, 1.5), Vector3.LEFT, cells, visible, Vector3i(-2, -2, -2), Vector3i(25, 10, 6), 0)
	_check("A ray from +x hits the +x side of the first box", sideways.has_box and sideways.cell == Vector3i(6, 1, 0) and sideways.face == Powerable.Face.POS_X)
	var near_edge := GridPicker.pick(Vector3(3.9, 50, 3.5), Vector3.DOWN, cells, visible, Vector3i(-2, -2, -2), Vector3i(10, 10, 6), 0)
	_check("  near the +x edge of a top it says so", near_edge.top_edge == Box.Facing.POS_X)
	var hanging := GridPicker.pick(Vector3(1.5, 1.3, 20), Vector3.FORWARD, cells, visible, Vector3i(-2, -2, -2), Vector3i(10, 25, 6), 0)
	_check("A top-half box is missed below its half", hanging.has_box and hanging.cell != Vector3i(1, 4, 1))
	var hanging_hit := GridPicker.pick(Vector3(1.5, 1.8, 20), Vector3.FORWARD, cells, visible, Vector3i(-2, -2, -2), Vector3i(10, 25, 6), 0)
	_check("  and hit above it", hanging_hit.has_box and hanging_hit.cell == Vector3i(1, 4, 1))


#==================Velocidad==================

## Un trazo grande (400 cajas, más que un nivel entero de los de prueba) y lo que tarda en verse.
func _test_speed(room: Room) -> void:
	var cells: Array[Vector3i] = []
	for x in 20:
		for y in 20:
			cells.append(Vector3i(x - 6, y - 7, 4))
	var start := Time.get_ticks_msec()
	_screen.edits.paint(BoxBrush.for_kind(BoxBrush.Kind.BLOCK), cells, null, null)
	var painted := Time.get_ticks_msec() - start
	await _tree.process_frame
	await _tree.process_frame
	var shown := Time.get_ticks_msec() - start
	print("      painting 400 boxes: %d ms, and refreshed: %d ms" % [painted, shown])
	_check("Painting 400 boxes takes under 2 s, refresh included", shown < 2000 and _box_at(room, Vector3i(0, 0, 4)) != null)
	start = Time.get_ticks_msec()
	await _undo()
	print("      undoing it: %d ms" % (Time.get_ticks_msec() - start))
	_check("  and undo takes them away", _box_at(room, Vector3i(0, 0, 4)) == null)


#==================El mouse y las teclas de verdad==================

## Eventos de verdad por la entrada de la vista: la cámara, el puntero y las teclas, no sólo LevelEdits.
func _test_real_input(room: Room) -> void:
	EditorInterface.set_main_screen_editor("Level")
	await _frames(10)
	var view := _screen.view
	_check("The view has a size to draw in", view.size.x > 100 and view.size.y > 100)
	view.game_view()
	await _frames(3)
	_screen.use_tool(_screen.box_tools[BoxBrush.Kind.MOVABLE_3D])
	_click(view, _top_of(view, Vector3i(3, 0, -1)), MOUSE_BUTTON_LEFT)
	await _settle()
	var clicked := _box_at(room, Vector3i(3, 0, 0))
	_check("A click with a brush paints a box on the top it points at", clicked != null and clicked.movable_3d_pos_x and not clicked.movable_2d_whole_face)
	_drag(view, [_top_of(view, Vector3i(0, 5, -1)), _top_of(view, Vector3i(1, 5, -1)), _top_of(view, Vector3i(2, 5, -1))], MOUSE_BUTTON_LEFT)
	await _settle()
	var a := _box_at(room, Vector3i(0, 5, 0))
	var c := _box_at(room, Vector3i(2, 5, 0))
	_check("A drag paints a row as one group", a != null and c != null and a.get_parent() == c.get_parent() and _box_at(room, Vector3i(1, 5, 0)) != null)
	_click(view, _top_of(view, Vector3i(3, 0, 0)), MOUSE_BUTTON_RIGHT)
	await _settle()
	_check("A right-click erases the box", _box_at(room, Vector3i(3, 0, 0)) == null)
	_key(view, KEY_PLUS)
	_check("+ enters layer mode", _screen.layer_mode)
	_key(view, KEY_PLUS)
	_check("  and + again goes a layer up", _screen.layer == 1)
	_key(view, KEY_ESCAPE)
	_check("Esc leaves layer mode", not _screen.layer_mode)
	_key(view, KEY_2)
	_check("2 picks the Wall brush", _screen.current_tool == _screen.box_tools[BoxBrush.Kind.WALL])
	_key(view, KEY_V)
	_click(view, _top_of(view, Vector3i(1, 5, 0)), MOUSE_BUTTON_LEFT)
	await _settle()
	_check("V and a click select the whole group", _screen.selected_boxes.size() == 3 and _screen.is_selected(a))
	_key(view, KEY_D, true)
	_check("Ctrl + D deselects", _screen.selected_boxes.is_empty())
	_click(view, _top_of(view, Vector3i(1, 5, 0)), MOUSE_BUTTON_LEFT)
	await _settle()
	var before := a.world_cell
	_key(view, KEY_RIGHT)
	await _settle()
	var nudged := a.world_cell - before
	_check("An arrow nudges the selection one cell along the grid", absi(nudged.x) + absi(nudged.y) == 1 and nudged.z == 0 and _box_at(room, a.world_cell) == a)
	_key(view, KEY_DELETE)
	await _settle()
	_check("Delete deletes the selection", not is_instance_valid(a) or not a.is_inside_tree())
	_key(view, KEY_TAB)
	await _until_the_turn_ends()
	_check("Tab switches to 2D", view.is_2d)
	_key(view, KEY_TAB)
	await _until_the_turn_ends()
	_check("  and back to 3D", not view.is_2d)
	view.game_view()
	await _frames(3)
	await _test_every_tool_by_input(room, view)
	await _test_the_editor_shortcuts(room, view)
	await _test_the_camera_by_mouse(view)
	await _test_the_selection_sync(room)
	_screen.use_tool(_screen.box_tools[BoxBrush.Kind.MOVABLE])


func _test_every_tool_by_input(room: Room, view: LevelEditorView) -> void:
	var brush_tool := _screen.box_tools[BoxBrush.Kind.MOVABLE]
	_screen.use_tool(brush_tool)
	brush_tool.brush.shape = BoxBrush.Shape.RECTANGLE
	_drag(view, [_top_of(view, Vector3i(3, 4, -1)), _top_of(view, Vector3i(4, 5, -1))], MOUSE_BUTTON_LEFT)
	await _settle()
	var corner := _box_at(room, Vector3i(3, 4, 0))
	_check("A Rectangle drag paints the whole rectangle as one group", corner != null and corner.get_parent() is Structure and (corner.get_parent() as Structure).boxes().size() == 4)
	_screen.use_tool(brush_tool)
	_check("Reselecting a brush puts its options back", brush_tool.brush.shape == BoxBrush.Shape.PAINT)
	var shift_click := InputEventMouseButton.new()
	shift_click.button_index = MOUSE_BUTTON_LEFT
	shift_click.pressed = true
	shift_click.shift_pressed = true
	shift_click.position = _top_of(view, Vector3i(3, 4, 0))
	view._gui_input(shift_click)
	var shift_release := shift_click.duplicate() as InputEventMouseButton
	shift_release.pressed = false
	view._gui_input(shift_release)
	await _settle()
	var on_top := _box_at(room, Vector3i(3, 4, 1))
	_check("Shift + click on a box extends its group", on_top != null and on_top.get_parent() == corner.get_parent())

	_screen.use_tool_named("Handles")
	var side := view.camera.unproject_position(GridCoordsProvider.grid_to_godot(Vector3i(4, 4, 0)) + Vector3(1.0, 0.5, 0.5))
	var was := (_box_at(room, Vector3i(4, 4, 0)) as Box).movable_3d_pos_x
	_click(view, side, MOUSE_BUTTON_LEFT)
	await _settle()
	_check("Handles: a click on a side face toggles its 3D handle", (_box_at(room, Vector3i(4, 4, 0)) as Box).movable_3d_pos_x != was)

	_screen.use_tool(_screen.tools[BoxBrush.PALETTE.size()])
	# Una columna del borde +x: desde la cámara del juego nada la tapa.
	_drag(view, [_top_of(view, Vector3i(7, 1, -1)), _top_of(view, Vector3i(7, 2, -1)), _top_of(view, Vector3i(7, 3, -1))], MOUSE_BUTTON_LEFT)
	await _settle()
	var w0 := _box_at(room, Vector3i(7, 1, -1)).powerable_on(Powerable.Face.TOP)
	var w2 := _box_at(room, Vector3i(7, 3, -1)).powerable_on(Powerable.Face.TOP)
	_check("Wire: a drag across three tops lays three connected wires", w0 is Wire and w2 is Wire and w0.connects_pos_y and w2.connects_neg_y and room.index.connected_powerables(w0, Room.Perspective.ISO_3D).size() >= 1)

	_screen.use_tool(_screen.piece_tools[&"ButtonPowerable"])
	_click(view, _top_of(view, Vector3i(3, 2, -1)), MOUSE_BUTTON_LEFT)
	await _settle()
	var button := _box_at(room, Vector3i(3, 2, -1)).powerable_on(Powerable.Face.TOP)
	_check("Button: a click puts a button on the top it points at", button is ButtonPowerable)
	_check("  connected to the wire whose arm pointed at it... or not, as the wire has no +x arm", button is ButtonPowerable and not room.index.connected_powerables(button, Room.Perspective.ISO_3D).has(w2))
	_check("  and selected", _screen.selected_pieces.has(button))

	var alt_click := InputEventMouseButton.new()
	alt_click.button_index = MOUSE_BUTTON_LEFT
	alt_click.pressed = true
	alt_click.alt_pressed = true
	alt_click.position = _top_of(view, Vector3i(4, 5, 0))
	view._gui_input(alt_click)
	await _settle()
	_check("Alt + click picks a box's settings into a brush", _screen.current_tool is BoxBrushTool and (_screen.current_tool as BoxBrushTool).brush.kind == BoxBrush.Kind.CUSTOM)

	var block := _screen.box_tools[BoxBrush.Kind.BLOCK]
	_screen.use_tool(block)
	var ctrl_press := InputEventMouseButton.new()
	ctrl_press.button_index = MOUSE_BUTTON_LEFT
	ctrl_press.pressed = true
	ctrl_press.ctrl_pressed = true
	ctrl_press.position = _top_of(view, Vector3i(3, 5, 0))
	view._gui_input(ctrl_press)
	var ctrl_release := ctrl_press.duplicate() as InputEventMouseButton
	ctrl_release.pressed = false
	view._gui_input(ctrl_release)
	await _settle()
	var repainted := _box_at(room, Vector3i(3, 5, 0))
	_check("Ctrl + click repaints a box with the brush", repainted != null and not repainted.movable_3d_pos_x and not repainted.movable_2d_whole_face and repainted.get_parent() == corner.get_parent())

	_screen.use_tool_named("Select")
	var double := InputEventMouseButton.new()
	double.button_index = MOUSE_BUTTON_LEFT
	double.pressed = true
	double.double_click = true
	double.position = _top_of(view, Vector3i(4, 5, 0))
	view._gui_input(double)
	var double_release := double.duplicate() as InputEventMouseButton
	double_release.pressed = false
	double_release.double_click = false
	view._gui_input(double_release)
	await _settle()
	_check("Double-click selects one box", _screen.selected_boxes.size() == 1)
	_click(view, _top_of(view, Vector3i(3, 4, 1)), MOUSE_BUTTON_LEFT)
	await _settle()
	var group_size := _screen.selected_boxes.size()
	var grabbed_before := corner.world_cell
	_drag(view, [_top_of(view, Vector3i(3, 4, 1)), _top_of(view, Vector3i(3, 3, 1))], MOUSE_BUTTON_LEFT)
	await _settle()
	_check("Dragging a selected group moves it", group_size == 5 and corner.world_cell != grabbed_before)
	await _undo()

	_key(view, KEY_C, true)
	_key(view, KEY_V, true)
	_check("Ctrl + C and Ctrl + V start pasting", _screen.current_tool is PasteTool)
	view._mouse_position = _top_of(view, Vector3i(6, 4, -1))
	view._mouse_inside = true
	view._update_the_hover()
	_click(view, _top_of(view, Vector3i(6, 4, -1)), MOUSE_BUTTON_LEFT)
	await _settle()
	view._mouse_inside = false
	_check("  and a click pastes the copy there", _box_at(room, Vector3i(6, 4, 0)) != null and not _screen.current_tool is PasteTool)

	_screen.use_tool_named("Eraser")
	_click(view, _top_of(view, Vector3i(3, 2, -1)), MOUSE_BUTTON_LEFT)
	await _settle()
	_check("Eraser: a click on a face with a piece erases the piece, not the box", _box_at(room, Vector3i(3, 2, -1)) != null and _box_at(room, Vector3i(3, 2, -1)).powerable_on(Powerable.Face.TOP) == null)


## Por la entrada de verdad del editor (Input.parse_input_event), no directo a la vista: Ctrl + Z tiene
## que llegar a Godot, y Ctrl + D quedarse en la vista en vez de duplicar nodos en el dock de escena.
func _test_the_editor_shortcuts(room: Room, view: LevelEditorView) -> void:
	view.grab_focus()
	await _frames(2)
	_check("The view can take the keyboard", view.has_focus())
	var free_cell := Vector3i(0, 0, 2)
	_check("(the cell for this test is free)", _box_at(room, free_cell) == null)
	_screen.edits.paint(BoxBrush.for_kind(BoxBrush.Kind.BLOCK), [free_cell], null, null)
	await _settle()
	var painted := _box_at(room, free_cell)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(painted.get_parent())
	await _frames(2)
	view.grab_focus()
	var groups_before := room.get_child_count()
	_press_for_real(KEY_D, true)
	await _frames(5)
	_check("Ctrl + D in the view doesn't duplicate nodes", room.get_child_count() == groups_before)
	view.grab_focus()
	_press_for_real(KEY_Z, true)
	await _frames(5)
	_check("Ctrl + Z in the view reaches Godot's undo", not painted.is_inside_tree())


func _test_the_camera_by_mouse(view: LevelEditorView) -> void:
	view.game_view()
	await _frames(2)
	var yaw := view.yaw
	_middle_drag(view, Vector2(40, 0), false)
	_check("Middle drag orbits the camera", absf(view.yaw - yaw) > 0.1 and not view.is_game_view)
	var focus := view.focus
	_middle_drag(view, Vector2(30, 20), true)
	_check("Shift + middle drag pans it", view.focus.distance_to(focus) > 0.1)
	var size := view.view_size
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	view._gui_input(wheel)
	_check("The wheel zooms in", view.view_size < size)
	yaw = view.yaw
	_key(view, KEY_Q)
	_check("Q turns the view 90°", is_equal_approx(absf(view.yaw - yaw), PI / 2.0))
	_key(view, KEY_F)
	await _frames(2)
	_check("F frames the room when nothing is selected", view.is_game_view)


func _middle_drag(view: LevelEditorView, by: Vector2, shift: bool) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.shift_pressed = shift
	press.position = view.size * 0.5
	view._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = view.size * 0.5 + by
	motion.relative = by
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	view._gui_input(motion)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	view._gui_input(release)


func _test_the_selection_sync(room: Room) -> void:
	var some_box := _box_at(room, Vector3i(0, 1, 0))
	var group := some_box.get_parent() as Structure
	_screen.select(group.boxes(), [])
	await _frames(3)
	_check("Selecting a group shows its Structure in Godot's selection", EditorInterface.get_selection().get_selected_nodes().has(group))
	var floor_box := _box_at(room, Vector3i(6, 0, -1))
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(floor_box)
	await _frames(3)
	_check("Selecting a box in Godot selects it in the Level tab", _screen.selected_boxes.size() == 1 and _screen.selected_boxes[0] == floor_box)
	_screen.clear_selection()
	await _frames(2)


func _press_for_real(keycode: Key, ctrl: bool) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.ctrl_pressed = ctrl
		event.command_or_control_autoremap = false
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _top_of(view: LevelEditorView, cell: Vector3i) -> Vector2:
	return view.camera.unproject_position(GridCoordsProvider.grid_to_godot(cell) + Vector3(0.5, 1.0, 0.5))


func _click(view: LevelEditorView, at: Vector2, button: MouseButton) -> void:
	_drag(view, [at], button)


func _drag(view: LevelEditorView, points: Array, button: MouseButton) -> void:
	var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = points[0]
	press.button_mask = mask
	view._gui_input(press)
	var last: Vector2 = points[0]
	for point: Vector2 in points.slice(1):
		for step in 4:
			var motion := InputEventMouseMotion.new()
			var position := last.lerp(point, (step + 1) / 4.0)
			motion.position = position
			motion.relative = position - last
			motion.button_mask = mask
			view._gui_input(motion)
		last = point
	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = last
	view._gui_input(release)


func _key(view: LevelEditorView, keycode: Key, ctrl := false, shift := false, alt := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.alt_pressed = alt
	if keycode == KEY_PLUS:
		event.unicode = 43
	elif keycode == KEY_MINUS:
		event.unicode = 45
	view._gui_input(event)


#==================Deshacer y rehacer todo==================

## La prueba más fuerte de la historia: una tanda de ediciones de todo tipo, cada una con su foto de lo
## que se guardaría. Deshacerlas una por una vuelve a cada foto anterior, exacta, y rehacerlas a cada
## foto siguiente; en cada paso el índice dice lo mismo que el árbol.
func _test_undo_and_redo_everything(room: Room) -> void:
	var edits := _screen.edits
	var row := Vector3i(0, 0, 5)
	var bridge := Vector3i(0, 5, 5)
	var steps: Array[Array] = [
		["paint a Movable row", func() -> void: edits.paint(BoxBrush.for_kind(BoxBrush.Kind.MOVABLE), [row, row + Vector3i(1, 0, 0), row + Vector3i(2, 0, 0)], null, null)],
		["paint a Walkable column", func() -> void: edits.paint(_brush_of_height(BoxBrush.Kind.WALKABLE, 2), [Vector3i(4, 0, 5), Vector3i(4, 0, 6)], null, null)],
		["extend the row", func() -> void: edits.paint(BoxBrush.for_kind(BoxBrush.Kind.MOVABLE), [row + Vector3i(0, 1, 0)], _group_at(room, row), null)],
		["erase the middle of the row", func() -> void: edits.erase([_box_at(room, row + Vector3i(1, 0, 0))] as Array[Box], [])],
		["move the row", func() -> void: edits.move(_group_at(room, row).boxes(), Vector3i(0, 2, 0))],
		["nudge it twice (one action)", _nudge_twice.bind(room, row + Vector3i(0, 2, 0))],
		["group boxes of two groups", func() -> void: edits.group([_box_at(room, Vector3i(2, 2, 5)), _box_at(room, Vector3i(4, 0, 6))] as Array[Box])],
		["ungroup it", func() -> void: edits.ungroup([_group_at(room, Vector3i(2, 2, 5))] as Array[Structure])],
		["paint a Block bridge", func() -> void: edits.paint(BoxBrush.for_kind(BoxBrush.Kind.BLOCK), [bridge, bridge + Vector3i(1, 0, 0), bridge + Vector3i(2, 0, 0), bridge + Vector3i(3, 0, 0), bridge + Vector3i(4, 0, 0)], null, null)],
		["place a button", func() -> void: edits.place_piece(&"ButtonPowerable", _box_at(room, bridge), Powerable.Face.TOP, {})],
		["lay a wire from it", func() -> void: edits.lay_wire(_tops_between(bridge, bridge + Vector3i(3, 0, 0)), Room.Perspective.ISO_3D)],
		["place a door where the wire points", func() -> void: edits.place_piece(&"Door", _box_at(room, bridge + Vector3i(4, 0, 0)), Powerable.Face.TOP, {&"edge": Box.Facing.POS_X})],
		["place a laser emitter on a side", func() -> void: edits.place_piece(&"LaserEmitter", _box_at(room, Vector3i(4, 0, 5)), Powerable.Face.POS_Y, {})],
		["erase a wire", func() -> void: edits.erase([], [_box_at(room, bridge + Vector3i(2, 0, 0)).powerable_on(Powerable.Face.TOP)] as Array[Powerable])],
		["erase a wire keeping the arms", func() -> void: edits.erase([], [_box_at(room, bridge + Vector3i(1, 0, 0)).powerable_on(Powerable.Face.TOP)] as Array[Powerable], true)],
		["keep the height", func() -> void: edits.set_box_flags([_box_at(room, bridge)] as Array[Box], {&"keeps_height": true}, "Keeps its height: on")],
		["repaint two boxes", func() -> void: edits.repaint([_box_at(room, bridge + Vector3i(1, 0, 0)), _box_at(room, bridge + Vector3i(2, 0, 0))] as Array[Box], BoxBrush.for_kind(BoxBrush.Kind.MOVABLE))],
		["switch the button on", func() -> void: edits.set_piece_properties([_box_at(room, bridge).powerable_on(Powerable.Face.TOP)] as Array[Powerable], {&"switched_on": true}, "Starts on: on")],
		["move the door to another edge", func() -> void: edits.set_piece_properties([_box_at(room, bridge + Vector3i(4, 0, 0)).powerable_on(Powerable.Face.TOP)] as Array[Powerable], {&"edge": Box.Facing.NEG_Y}, "Move the door")],
		["rename the bridge", func() -> void: edits.rename(_group_at(room, bridge), "Bridge")],
		["make a folder", func() -> void: _chaos_folder = edits.new_folder(room)],
		["move the bridge into it", func() -> void: edits.move_into([_group_at(room, bridge)] as Array[Node], _chaos_folder)],
		["paste a copy of the bridge", func() -> void: edits.paste(edits.copy(_group_at(room, bridge).boxes()), Vector3i(0, 0, 8), null)],
		["grow the room", func() -> void: edits.set_room_size(room.dimensions + Vector3i(1, 1, 0))],
		["shrink the room", func() -> void: edits.set_room_size(room.dimensions - Vector3i(2, 2, 0))],
		["erase a floor box", func() -> void: edits.erase([_box_at(room, Vector3i(2, 2, -1))] as Array[Box], [])],
		["move the spawn", func() -> void: edits.set_spawn(Vector3i(1, 1, 0))],
		["start in 2D", func() -> void: edits.set_starting_perspective(Room.Perspective.TOP_2D)],
		["delete the folder", func() -> void: edits.delete_nodes([_chaos_folder] as Array[Node], "Delete the folder")],
		["erase a box with a piece, emptying its group", func() -> void: edits.erase([_box_at(room, Vector3i(4, 0, 5))] as Array[Box], [])],
	]
	var before: Array[PackedStringArray] = []
	var after: Array[PackedStringArray] = []
	var all_did_something := true
	var index_always_right := true
	var groups_always_hold_their_boxes := true
	for step in steps:
		before.append(_fingerprint())
		(step[1] as Callable).call()
		await _settle()
		after.append(_fingerprint())
		if after.back() == before.back():
			print("      this step changed nothing: ", step[0])
			all_did_something = false
		if not _index_matches_the_tree(room):
			print("      the index is wrong after: ", step[0])
			index_always_right = false
		if not _every_group_holds_its_boxes(room):
			print("      a group holds a box outside its dimensions after: ", step[0])
			groups_always_hold_their_boxes = false
	_check("Every one of %d mixed edits changes the level" % steps.size(), all_did_something)
	# Cuántos de los pasos están hechos ahora: al final se deshacen justo esos, ni uno más.
	var done := steps.size()
	if not all_did_something:
		return
	var undo_matches := true
	for i in range(steps.size() - 1, -1, -1):
		await _undo()
		done -= 1
		if not _same_fingerprint(_fingerprint(), before[i], "undoing " + steps[i][0]):
			undo_matches = false
			break
		if not _index_matches_the_tree(room):
			print("      the index is wrong after undoing: ", steps[i][0])
			index_always_right = false
		if not _every_group_holds_its_boxes(room):
			print("      a group holds a box outside its dimensions after undoing: ", steps[i][0])
			groups_always_hold_their_boxes = false
	_check("  undoing them one by one goes back through every earlier state, exactly", undo_matches)
	var redo_matches := undo_matches
	if undo_matches:
		for i in steps.size():
			await _redo()
			done += 1
			if not _same_fingerprint(_fingerprint(), after[i], "redoing " + steps[i][0]):
				redo_matches = false
				break
			if not _index_matches_the_tree(room):
				print("      the index is wrong after redoing: ", steps[i][0])
				index_always_right = false
	_check("  redoing them goes forward through every later state, exactly", redo_matches)
	_check("  and the index always says what the tree says", index_always_right)
	_check("  and every group, the shell's too, always holds its boxes inside its dimensions (Delete excess would delete nothing)", groups_always_hold_their_boxes)
	for i in done:
		await _undo()
	_check("  (all undone again for the tests that follow)", _same_fingerprint(_fingerprint(), before[0], "the final undo"))


var _chaos_folder: Node3D


func _nudge_twice(room: Room, cell: Vector3i) -> void:
	var boxes := _group_at(room, cell).boxes()
	_screen.edits.move(boxes, Vector3i(1, 0, 0), true, "Nudge")
	_screen.edits.move(boxes, Vector3i(1, 0, 0), true, "Nudge")


func _brush_of_height(kind: BoxBrush.Kind, height: int) -> BoxBrush:
	var brush := BoxBrush.for_kind(kind)
	brush.height = height
	return brush


func _group_at(room: Room, cell: Vector3i) -> Structure:
	var box := _box_at(room, cell)
	return box.get_parent() as Structure if box != null else null


func _tops_between(from: Vector3i, to: Vector3i) -> Array[FaceLinks.FaceAt]:
	var path: Array[FaceLinks.FaceAt] = []
	for x in range(from.x, to.x + 1):
		path.append(FaceLinks.FaceAt.new(Vector3i(x, from.y, from.z), Powerable.Face.TOP))
	return path


## Lo que se guardaría del nivel: cada nodo del nivel con su lugar, su clase y cada propiedad que se
## guarda. Dos fotos iguales son dos archivos iguales.
func _fingerprint() -> PackedStringArray:
	var lines := PackedStringArray()
	_fingerprint_of(_screen.level_root, lines)
	return lines


func _fingerprint_of(node: Node, lines: PackedStringArray) -> void:
	var root := _screen.level_root
	var parts := PackedStringArray([String(root.get_path_to(node)), node.get_class(), str(node.get_index())])
	for property in node.get_property_list():
		if (property.usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var value: Variant = node.get(property.name)
		if value is Resource:
			value = (value as Resource).resource_path
		elif value is Object:
			value = (value as Object).get_class()
		parts.append("%s=%s" % [property.name, var_to_str(value)])
	lines.append(" ".join(parts))
	for child in node.get_children():
		if child.owner == root:
			_fingerprint_of(child, lines)


func _same_fingerprint(now: PackedStringArray, expected: PackedStringArray, doing: String) -> bool:
	if now == expected:
		return true
	print("      different after %s (%d lines now, %d expected)" % [doing, now.size(), expected.size()])
	for i in maxi(now.size(), expected.size()):
		var a := now[i] if i < now.size() else "(nothing)"
		var b := expected[i] if i < expected.size() else "(nothing)"
		if a != b:
			print("        now:      ", a.left(400))
			print("        expected: ", b.left(400))
			break
	return false


func _index_matches_the_tree(room: Room) -> bool:
	var boxes: Array[Box] = []
	_boxes_under(room, boxes)
	if boxes.size() != room.index.cells_3D.size():
		return false
	for box in boxes:
		if room.index.cells_3D.get(box.world_cell) != box:
			return false
	return true


## Toda Structure del nivel, la cáscara también, con sus cajas dentro de sus dimensions: así Delete
## excess, en el Inspector, nunca borra nada que el editor puso.
func _every_group_holds_its_boxes(room: Room) -> bool:
	for node in room.find_children("*", "", true, false):
		var group := node as Structure
		if group == null:
			continue
		for box in group.boxes():
			if not group._is_in_the_prism(box.cell):
				print("        %s: a box at %s, outside %s" % [group.name, box.cell, group.dimensions])
				return false
	return true


func _boxes_under(node: Node, boxes: Array[Box]) -> void:
	for child in node.get_children():
		if child is Box:
			boxes.append(child)
		else:
			_boxes_under(child, boxes)


#==================Capas, 2D y láseres==================

func _test_layers_2d_and_lasers(room: Room) -> void:
	var view := _screen.view
	var edits := _screen.edits
	view.game_view()
	await _frames(3)
	var block_tool := _screen.box_tools[BoxBrush.Kind.BLOCK]
	_screen.use_tool(block_tool)
	_go_to_layer(1)
	_check("Layer mode can be set to layer 1", _screen.layer_mode and _screen.layer == 1)
	var column := _free_column(room)
	var corner := Vector3i(column.x, column.y, 1)
	_check("(a free column near the camera for this test: %s)" % column, column.x >= 0)
	var on_the_plane := view.camera.unproject_position(Vector3(corner.x + 0.5, corner.z, corner.y + 0.5))
	_click(view, on_the_plane, MOUSE_BUTTON_LEFT)
	await _settle()
	_check("In layer mode a click paints on the layer, even in the air", _box_at(room, corner) != null)
	_key(view, KEY_MINUS)
	_check("− goes a layer down", _screen.layer == 0)
	_key(view, KEY_ESCAPE)
	_check("Esc goes back to faces", not _screen.layer_mode)

	_screen.toggle_2d()
	await _until_the_turn_ends()
	_check("Tab-like toggle: the view is in 2D", view.is_2d)
	_click(view, _top_of(view, corner), MOUSE_BUTTON_LEFT)
	await _settle()
	_check("In 2D a click on a column stacks a box on its top", _box_at(room, corner + LevelIndex.GRID_UP) != null)
	var high_top := corner + LevelIndex.GRID_UP
	var low_top := _column_top(room, Vector2i(corner.x, corner.y - 1))
	_check("(the column next to it is lower)", low_top.z < high_top.z)
	_screen.use_tool(_screen.tools[BoxBrush.PALETTE.size()])
	_drag(view, [_top_of(view, high_top), _top_of(view, low_top)], MOUSE_BUTTON_LEFT)
	await _settle()
	var high_wire := _box_at(room, high_top).powerable_on(Powerable.Face.TOP)
	var low_wire := _box_at(room, low_top).powerable_on(Powerable.Face.TOP)
	_check("In 2D a wire drag joins two tops of different heights", high_wire is Wire and low_wire is Wire)
	_check("  connected in 2D", high_wire != null and low_wire != null and room.index.connected_powerables(high_wire, Room.Perspective.TOP_2D).has(low_wire))
	_check("  and not in 3D, where they don't touch", high_wire != null and low_wire != null and not room.index.connected_powerables(high_wire, Room.Perspective.ISO_3D).has(low_wire))
	_screen.use_tool(block_tool)
	_click(view, _top_of(view, corner + LevelIndex.GRID_UP), MOUSE_BUTTON_RIGHT)
	await _settle()
	_check("In 2D a right-click erases the top of the column, with its wire", _box_at(room, high_top) == null and (not is_instance_valid(high_wire) or not high_wire.is_inside_tree()))
	_check("  and the neighbour's arm toward it goes too", is_instance_valid(low_wire) and not low_wire.connects_pos_y)
	_screen.toggle_2d()
	await _until_the_turn_ends()
	_check("And back to 3D", not view.is_2d)

	var left := Vector3i(0, 0, 2)
	var right := Vector3i(3, 0, 2)
	var free := true
	for x in range(left.x, right.x + 1):
		free = free and _box_at(room, Vector3i(x, 0, 2)) == null
	_check("(the laser row is free)", free)
	edits.paint(BoxBrush.for_kind(BoxBrush.Kind.BLOCK), [left], null, null)
	edits.paint(BoxBrush.for_kind(BoxBrush.Kind.BLOCK), [right], null, null)
	await _settle()
	var emitter := edits.place_piece(&"LaserEmitter", _box_at(room, left), Powerable.Face.POS_X, {&"always_on": true}) as LaserEmitter
	var receiver := edits.place_piece(&"LaserReceiver", _box_at(room, right), Powerable.Face.NEG_X, {})
	await _settle()
	var beam := room.index.beam_of(emitter, Room.Perspective.ISO_3D, room.maximum_reach())
	_check("An emitter's beam reaches the receiver facing it", beam.hits == receiver and is_equal_approx(beam.length, 2.0))
	_screen._set_overlay(false, &"show_beams")
	var lines_without := view.overlay_3d._line_points.size()
	_screen._set_overlay(true, &"show_beams")
	_check("  and the Beams overlay draws it", view.overlay_3d._line_points.size() > lines_without)
	edits.paint(BoxBrush.for_kind(BoxBrush.Kind.MOVABLE), [Vector3i(2, 0, 2)], null, null)
	await _settle()
	beam = room.index.beam_of(emitter, Room.Perspective.ISO_3D, room.maximum_reach())
	_check("  and a box in the way stops it", beam.hits == null and is_equal_approx(beam.length, 1.0))
	await _undo()

	var door_tool := _screen.piece_tools[&"Door"]
	_screen.use_tool(door_tool)
	var near_the_y_edge := view.camera.unproject_position(GridCoordsProvider.grid_to_godot(right) + Vector3(0.5, 1.0, 0.92))
	_click(view, near_the_y_edge, MOUSE_BUTTON_LEFT)
	await _settle()
	var door := _box_at(room, right).powerable_on(Powerable.Face.TOP)
	_check("A door goes on the top edge nearest the mouse", door is Door and door.get(&"edge") == Box.Facing.POS_Y)


func _go_to_layer(wanted: int) -> void:
	if not _screen.layer_mode:
		_screen.change_layer(0)
	while _screen.layer < wanted:
		_screen.change_layer(1)
	while _screen.layer > wanted:
		_screen.change_layer(-1)


## Una columna con sólo el piso, de las más cercanas a la cámara del juego (que mira desde +x, +y), con
## la de al lado (hacia −y) también baja.
func _free_column(room: Room) -> Vector2i:
	for y in range(room.dimensions.y - 1, 0, -1):
		for x in range(room.dimensions.x - 1, -1, -1):
			var free := true
			for z in range(0, 4):
				free = free and _box_at(room, Vector3i(x, y, z)) == null
			if free and _column_top(room, Vector2i(x, y - 1)).z < 2:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _column_top(room: Room, column: Vector2i) -> Vector3i:
	var top := Vector3i(column.x, column.y, -100)
	for cell: Vector3i in room.index.cells_3D:
		if cell.x == column.x and cell.y == column.y and cell.z > top.z:
			top = cell
	return top


#==================Lo que cambia por fuera==================

func _test_changes_from_outside(room: Room) -> void:
	var group := _group_at(room, Vector3i(0, 1, 0))
	var free_cell := Vector3i(0, 1, 7)
	_check("(the cell for this test is free)", _box_at(room, free_cell) == null)
	var extra := (load("res://scenes/prefabs/box.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Box
	extra.cell = free_cell - group.world_cell
	group.add_child(extra, true)
	extra.owner = _screen.level_root
	await _settle()
	_check("A box added outside the history (a Structure's Fill) shows up in the index", _box_at(room, free_cell) == extra)
	_screen.select([extra] as Array[Box], [])
	group.remove_child(extra)
	extra.free()
	await _settle()
	_check("  and when it goes, the index and the selection forget it", _box_at(room, free_cell) == null and _screen.selected_boxes.is_empty())
	var box := _box_at(room, Vector3i(0, 1, 0))
	var undo_redo := EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Inspector: move a box")
	undo_redo.add_do_property(box, &"cell", box.cell + Vector3i(0, 0, 6))
	undo_redo.add_undo_property(box, &"cell", box.cell)
	undo_redo.commit_action()
	await _settle()
	_check("A change in the Inspector (Godot's own history) updates the index", _box_at(room, Vector3i(0, 1, 6)) == box and _box_at(room, Vector3i(0, 1, 0)) == null)
	await _undo()
	_check("  and so does its undo", _box_at(room, Vector3i(0, 1, 0)) == box)

	# Lo que se cambia a mano en el dock de escena no pasa por la historia: el aviso del grupo tiene que
	# llegar igual, enseguida (la señal con la que el dock de escena redibuja sus avisos).
	var warned: Array[Node] = []
	var listen := func(node: Node) -> void: warned.append(node)
	_tree.node_configuration_warning_changed.connect(listen)
	var group_of_three := box.get_parent() as Structure
	var cell_before := box.cell
	box.cell = cell_before + Vector3i(0, 0, 4)
	await _settle()
	_check("A box moved out of its group's dimensions by hand makes the group warn at once", warned.has(group_of_three) and _warns(group_of_three, "1 of its boxes lies outside its dimensions"))
	_check("  and Problems lists it", _screen._problems.collect().any(func(problem: Array) -> bool: return problem[0] == group_of_three and String(problem[1]).contains("outside its dimensions")))
	warned.clear()
	box.cell = cell_before
	await _settle()
	_check("  moving it back clears it at once", warned.has(group_of_three) and not _warns(group_of_three, "outside its dimensions"))
	warned.clear()
	# Uno arrastrado desde otro lado, fuera del prisma (un duplicado en la misma celda pasa por el mismo
	# camino, pero el índice del Room avisa con errores en la salida, y la prueba no los quiere).
	var dragged_in := (load("res://scenes/prefabs/box.tscn") as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Box
	dragged_in.cell = Vector3i(0, 0, 5)
	_check("(its cell is free)", _box_at(room, group_of_three.world_cell + dragged_in.cell) == null)
	group_of_three.add_child(dragged_in, true)
	dragged_in.owner = _screen.level_root
	await _settle()
	_check("A box added to a group by hand (dragged in from elsewhere) makes the group warn at once", warned.has(group_of_three) and _warns(group_of_three, "1 of its boxes lies outside its dimensions"))
	warned.clear()
	group_of_three.remove_child(dragged_in)
	dragged_in.free()
	await _settle()
	_check("  and taking it out clears it at once", warned.has(group_of_three) and not _warns(group_of_three, "outside its dimensions"))
	_tree.node_configuration_warning_changed.disconnect(listen)
	_check("(the group is as it was)", group_of_three.boxes().size() == 3 and _box_at(room, Vector3i(0, 1, 0)) == box and _index_matches_the_tree(room))


#==================Los paneles==================

func _test_the_panels(room: Room) -> void:
	var view := _screen.view
	var groups := _screen._groups
	_screen.refresh_panels()
	await _settle()
	var two: Array[TreeItem] = []
	for item in LevelEditorGroupsPanel._all_items(groups.tree.get_root()):
		var node: Node = item.get_metadata(0)
		if node is Structure and not _screen.edits.is_shell_part(node) and two.size() < 2:
			two.append(item)
	var a := two[0].get_metadata(0) as Structure
	var b := two[1].get_metadata(0) as Structure
	groups.tree.deselect_all()
	two[0].select(0)
	two[1].select(0)
	groups._on_multi_selected(two[1], 0, true)
	await _frames(3)
	_check("Groups: selecting two rows selects both groups", _screen.selected_boxes.size() == a.boxes().size() + b.boxes().size())
	var marked := 0
	for item in LevelEditorGroupsPanel._all_items(groups.tree.get_root()):
		if item.is_selected(0):
			marked += 1
	_check("  and both rows stay marked", marked == 2)
	groups._delete()
	await _settle()
	_check("  Delete deletes both", not a.is_inside_tree() and not b.is_inside_tree())
	await _undo()
	_check("  and one undo brings both back", a.is_inside_tree() and b.is_inside_tree())
	var one_box := a.boxes()[0]
	_screen.select([one_box] as Array[Box], [])
	await _settle()
	marked = 0
	for item in LevelEditorGroupsPanel._all_items(groups.tree.get_root()):
		if item.is_selected(0):
			marked += 1
	_check("  a group with only some of its boxes selected isn't marked", a.boxes().size() == 1 or marked == 0)
	_screen.select(a.boxes(), [])
	await _settle()
	groups._fill_move_to()
	var popup := groups._move_to.get_popup()
	var folder_id := -1
	for i in popup.item_count:
		var target: Node = popup.get_item_metadata(i)
		if target != room:
			folder_id = popup.get_item_id(i)
			break
	_check("Move to lists the folders", folder_id >= 0)
	if folder_id >= 0:
		var folder: Node = popup.get_item_metadata(popup.get_item_index(folder_id))
		var cell_before := a.boxes()[0].world_cell
		groups._move_into(folder_id)
		await _settle()
		_check("  and moves the marked group into one, keeping its cells", a.get_parent() == folder and a.boxes()[0].world_cell == cell_before)
		await _undo()

	_screen.use_tool_named("Select")
	var hidden_folder: Node = null
	for child in room.get_children():
		if child is GridEntity and not child is Structure and not child is Box and hidden_folder == null:
			hidden_folder = child
	_check("(a folder to hide)", hidden_folder != null)
	if hidden_folder != null:
		_click_the_eye_of(groups, hidden_folder)
		var up_high := Vector3i(1, 1, 8)
		_screen.edits.paint(BoxBrush.for_kind(BoxBrush.Kind.BLOCK), [up_high], null, hidden_folder)
		await _settle()
		var inside := _box_at(room, up_high)
		_check("A group painted into a hidden folder is hidden too", inside != null and hidden_folder.is_ancestor_of(inside) and not view.is_box_visible(inside))
		_check("  and the mouse goes through it", inside != null and view.pick(_top_of(view, up_high)).box != inside)
		_click_the_eye_of(groups, hidden_folder)
		await _settle()
		_check("  until the folder is shown again", inside != null and view.is_box_visible(inside) and view.pick(_top_of(view, up_high)).box == inside)
		await _undo()
		var folder_row := _row_of(groups, hidden_folder)
		groups.tree.deselect_all()
		folder_row.select(0)
		groups._on_multi_selected(folder_row, 0, true)
		await _frames(3)
		_check("Groups: clicking a folder makes it where new groups go", _screen.current_folder() == hidden_folder and groups._back_to_the_room.visible)
		groups._back_to_the_room.pressed.emit()
		await _settle()
		_check("  and Back to the Room sends them under the Room again", _screen.current_folder() == null and not groups._back_to_the_room.visible)
	var named_row := _row_of(groups, _group_at(room, Vector3i(0, 1, 0)))
	groups.tree.deselect_all()
	named_row.select(0)
	_check("Groups: double-clicking a row opens its name for typing", groups._on_item_activated())
	groups.refresh()
	view.grab_focus()
	await _settle()

	_screen.use_tool_named("Select")
	var props := _screen._properties
	var movable := _group_at(room, Vector3i(0, 1, 0))
	_screen.select(movable.boxes(), [])
	await _settle()
	_toggle_check(props, "Keeps its height", true)
	await _settle()
	_check("Properties: Keeps its height goes to the group", movable.boxes().all(func(each: Box) -> bool: return each.keeps_height))
	await _undo()
	_screen.select([movable.boxes()[0]] as Array[Box], [])
	await _settle()
	_toggle_check(props, "Keeps its height", true)
	await _settle()
	_check("  even with only one of its boxes selected", movable.boxes().all(func(each: Box) -> bool: return each.keeps_height))
	await _undo()
	_screen.select([movable.boxes()[0]] as Array[Box], [])
	await _settle()
	_toggle_check(props, "Floor tile (terrain)", true)
	await _settle()
	_check("  Floor on part of a group is refused, saying why", not movable.boxes()[0].is_floor and _screen._status.text.contains("terrain"))
	_screen.select(movable.boxes(), [])
	await _settle()
	_toggle_check(props, "Floor tile (terrain)", true)
	await _settle()
	var first := movable.boxes()[0]
	_check("  Floor on the whole group makes it floor, with no hidden handles left", first.is_floor and first.walkable and not first.movable_3d_pos_x and not first.movable_2d_whole_face)
	await _undo()
	_check("  and undo gives the handles back", not first.is_floor and first.movable_3d_pos_x)
	_press_button(props, "", "settings of Wall")
	await _settle()
	_check("  a kind button repaints the selection", first.is_wall and movable.boxes().all(func(each: Box) -> bool: return each.is_wall))
	await _undo()
	var wall := BoxBrush.for_kind(BoxBrush.Kind.WALL)
	_screen.repaint_boxes([movable.boxes()[0]] as Array[Box], wall)
	await _settle()
	_check("Repaint: one box of a group can't turn into terrain alone", not movable.boxes()[0].is_wall and _screen._status.text.contains("skipped"))
	var shell_box := _box_at(room, Vector3i(4, 4, -1))
	_screen.repaint_boxes([shell_box] as Array[Box], BoxBrush.for_kind(BoxBrush.Kind.MOVABLE))
	await _settle()
	_check("  the room shell can't stop being terrain", shell_box.is_floor and not shell_box.movable_3d_pos_x)
	_screen.repaint_boxes([shell_box] as Array[Box], wall)
	await _settle()
	_check("  but it can be repainted as another terrain", shell_box.is_wall)
	await _undo()
	var single := _box_at(room, Vector3i(6, 4, -1))
	_check("(the box for the faces test has a free top)", single != null and single.powerable_on(Powerable.Face.TOP) == null)
	_screen.select([single] as Array[Box], [])
	await _settle()
	var add := _add_menu_for(props, "Top")
	_check("  one box shows its faces, each with Add…", add != null)
	if add != null:
		var popup_of_add := add.get_popup()
		for i in popup_of_add.item_count:
			if popup_of_add.get_item_metadata(i) == &"Wire":
				popup_of_add.index_pressed.emit(i)
		await _settle()
		_check("  Add… puts that piece on that face", single.powerable_on(Powerable.Face.TOP) is Wire)
		await _undo()

	var level := _screen._level
	_screen.refresh_panels()
	await _settle()
	var fields: Array[SpinBox] = []
	for field in level.find_children("*", "SpinBox", true, false):
		fields.append(field as SpinBox)
	var size_before := room.dimensions
	fields[0].value = size_before.x + 2
	_press_button(level, "Apply", "")
	await _settle()
	_check("Level: Apply resizes the room", room.dimensions == size_before + Vector3i(2, 0, 0))
	await _undo()
	_check("  and undo gives the old size back", room.dimensions == size_before)

	var problems := _screen._problems.collect()
	var any_node: Node = null
	for problem in problems:
		if problem[0] is Box or problem[0] is Structure:
			any_node = problem[0]
	if any_node != null:
		_screen.show_node(any_node)
		await _settle()
		_check("Problems: Show selects the culprit", not _screen.selected_boxes.is_empty())
	_screen.clear_selection()
	_screen.show_the_help()
	await _frames(2)
	_check("The ? button's help opens", _screen._help.visible)
	_screen._help.hide()
	_screen._fill_the_open_menu()
	_check("Open level lists the levels", _screen._open_menu.get_popup().item_count >= 2)
	view.grab_focus()


func _warns(node: Node, fragment: String) -> bool:
	for warning: String in node.call(&"_get_configuration_warnings"):
		if warning.contains(fragment):
			return true
	return false


func _row_of(groups: LevelEditorGroupsPanel, node: Node) -> TreeItem:
	groups.refresh()
	for item in LevelEditorGroupsPanel._all_items(groups.tree.get_root()):
		if item.get_metadata(0) == node:
			return item
	return null


func _click_the_eye_of(groups: LevelEditorGroupsPanel, node: Node) -> void:
	groups.refresh()
	for item in LevelEditorGroupsPanel._all_items(groups.tree.get_root()):
		if item.get_metadata(0) == node:
			groups._on_button_clicked(item, 1, LevelEditorGroupsPanel.EYE_COLUMN_BUTTON, MOUSE_BUTTON_LEFT)
			return
	print("      no row for ", node.name)


func _toggle_check(panel: Control, starting_with: String, on: bool) -> void:
	for node in panel.find_children("*", "CheckBox", true, false):
		var check := node as CheckBox
		if check.text.begins_with(starting_with):
			check.button_pressed = on
			return
	print("      no check box called ", starting_with)


func _press_button(panel: Control, text: String, tooltip_part: String) -> void:
	for node in panel.find_children("*", "Button", true, false):
		var button := node as Button
		if (text.is_empty() or button.text == text) and (tooltip_part.is_empty() or button.tooltip_text.contains(tooltip_part)):
			button.pressed.emit()
			return
	print("      no button ", text, tooltip_part)


func _add_menu_for(panel: Control, face_text: String) -> MenuButton:
	for node in panel.find_children("*", "MenuButton", true, false):
		var row := node.get_parent()
		var label := row.get_child(0) as Label
		if label != null and label.text == face_text:
			return node as MenuButton
	return null


#==================Más atajos y herramientas==================

func _test_more_shortcuts_and_tools(room: Room) -> void:
	var view := _screen.view
	view.game_view()
	await _frames(3)
	view.grab_focus()
	var one := _box_at(room, Vector3i(0, 1, 0))
	var other := _box_at(room, Vector3i(6, 4, 0))
	_check("(two loose groups for the group keys)", one != null and other != null and one.get_parent() != other.get_parent())
	_screen.select([one, other] as Array[Box], [])
	_key(view, KEY_G, true)
	await _settle()
	_check("Ctrl + G groups the selection", one.get_parent() == other.get_parent())
	_key(view, KEY_G, true, true)
	await _settle()
	_check("Ctrl + Shift + G ungroups it", one.get_parent() != other.get_parent())
	await _undo()
	await _undo()
	_check("  (both undone)", one.get_parent() != other.get_parent() and _box_at(room, Vector3i(0, 1, 0)) == one)

	var group := one.get_parent() as Structure
	_screen.select(group.boxes(), [])
	await _settle()
	_key(view, KEY_F2)
	await _frames(2)
	_check("F2 puts the cursor in the group's name", _screen.group_name_field != null and _screen.group_name_field.has_focus())
	view.grab_focus()
	var before := one.world_cell
	_key(view, KEY_PLUS, false, false, true)
	await _settle()
	_check("Alt + + lifts the selection a layer", one.world_cell == before + LevelIndex.GRID_UP)
	_key(view, KEY_MINUS, false, false, true)
	await _settle()
	_check("  and Alt + − puts it back down", one.world_cell == before)
	await _undo()
	_check("  (one undo for both, since nudges merge)", one.world_cell == before)

	var block_tool := _screen.box_tools[BoxBrush.Kind.BLOCK]
	_screen.use_tool(block_tool)
	block_tool._set_height(3)
	_screen.select(group.boxes(), [])
	_key(view, KEY_C, true)
	_check("Ctrl + C says what it copied", _screen._status.text.begins_with("Copied"))
	_key(view, KEY_V, true)
	_key(view, KEY_ESCAPE)
	await _frames(2)
	_check("Esc while pasting goes back to the brush, keeping its options", _screen.current_tool == block_tool and block_tool.brush.height == 3)
	_screen.clear_selection()
	_key(view, KEY_C, true)
	_check("Ctrl + C with nothing selected says so", _screen._status.text.begins_with("Select something"))

	var wire_tool := _screen.tools[BoxBrush.PALETTE.size()]
	_screen.use_tool(wire_tool)
	var w0 := _box_at(room, Vector3i(7, 1, -1)).powerable_on(Powerable.Face.TOP)
	var w1 := _box_at(room, Vector3i(7, 2, -1)).powerable_on(Powerable.Face.TOP)
	var w2 := _box_at(room, Vector3i(7, 3, -1)).powerable_on(Powerable.Face.TOP)
	_check("(the three wires from before are there)", w0 is Wire and w1 is Wire and w2 is Wire)
	_click_with(view, _top_of(view, Vector3i(7, 2, -1)), MOUSE_BUTTON_RIGHT, true, false, false)
	await _settle()
	_check("Wire: Shift + right-click erases a wire, keeping the arms pointing at it", not w1.is_inside_tree() and w0.connects_pos_y and w2.connects_neg_y)
	await _undo()
	_click(view, _top_of(view, Vector3i(7, 2, -1)), MOUSE_BUTTON_RIGHT)
	await _settle()
	_check("  a plain right-click unticks them", not w1.is_inside_tree() and not w0.connects_pos_y and not w2.connects_neg_y)
	await _undo()

	_screen.use_tool_named("Select")
	_click_with(view, _top_of(view, Vector3i(7, 1, -1)), MOUSE_BUTTON_LEFT, false, true, false)
	await _settle()
	_check("Select: Ctrl + click selects the piece on a face", _screen.selected_pieces.size() == 1 and _screen.selected_pieces[0] == w0 and _screen.selected_boxes.is_empty())
	_click(view, _top_of(view, Vector3i(0, 1, 0)), MOUSE_BUTTON_LEFT)
	await _settle()
	var first_count := _screen.selected_boxes.size()
	_click_with(view, _top_of(view, Vector3i(6, 4, 0)), MOUSE_BUTTON_LEFT, true, false, false)
	await _settle()
	_check("  Shift + click adds a group", _screen.selected_boxes.size() > first_count and _screen.is_selected(other))
	_click_with(view, _top_of(view, Vector3i(6, 4, 0)), MOUSE_BUTTON_LEFT, true, false, false)
	await _settle()
	_check("  and Shift + click on it again takes it out", _screen.selected_boxes.size() == first_count and not _screen.is_selected(other))
	_screen.clear_selection()
	_drag(view, [Vector2(4, 4), view.size * 0.5], MOUSE_BUTTON_LEFT)
	await _settle()
	_check("  a drag from empty space selects with a rectangle", not _screen.selected_boxes.is_empty())
	var floor_tile := Vector3i(-1, -1, -1)
	for y in range(room.dimensions.y - 1, -1, -1):
		for x in range(room.dimensions.x - 1, -1, -1):
			var candidate := Vector3i(x, y, -1)
			if floor_tile.x < 0 and _box_at(room, candidate + LevelIndex.GRID_UP) == null and _top_is_in_sight(view, candidate):
				floor_tile = candidate
	_check("(a floor tile in sight: %s)" % floor_tile, floor_tile.x >= 0)
	_click(view, _top_of(view, floor_tile), MOUSE_BUTTON_LEFT)
	await _settle()
	_check("  a click on the floor selects just that floor box", _screen.selected_boxes.size() == 1 and _screen.selected_boxes[0] == _box_at(room, floor_tile))
	var from_the_floor := _top_of(view, floor_tile)
	var past_a_group := view.cell_on_screen(one.world_cell)
	past_a_group += (past_a_group - from_the_floor).normalized() * 30.0
	_drag(view, [from_the_floor, past_a_group], MOUSE_BUTTON_LEFT)
	await _settle()
	var any_shell := _screen.selected_boxes.any(func(each: Box) -> bool: return _screen.edits.is_shell_part(each.get_parent()))
	_check("  a drag that starts on the floor draws a rectangle instead, and it leaves the shell out", not _screen.selected_boxes.is_empty() and not any_shell)
	_check("  (nothing moved: the floor doesn't)", _box_at(room, floor_tile) != null)
	_screen.select(group.boxes(), [])
	await _settle()
	var lift_from := one.world_cell
	_drag_with_a_key(view, _top_of(view, one.world_cell), _top_of(view, one.world_cell) + Vector2(0, 2), KEY_PLUS)
	await _settle()
	_check("  dragging with + lifts what it moves", one.world_cell.z == lift_from.z + 1)
	await _undo()

	_screen.use_tool_named("Spawn")
	var spawn_tool := _screen.current_tool as SpawnTool
	var tile := Vector3i(-1, -1, -1)
	for y in range(room.dimensions.y - 1, -1, -1):
		for x in range(room.dimensions.x - 1, -1, -1):
			var candidate := Vector3i(x, y, 0)
			if tile.x < 0 and _box_at(room, candidate) == null and _box_at(room, candidate + LevelIndex.GRID_UP) == null and spawn_tool.can_start_at(candidate) and candidate != room.player_spawn_point and _top_is_in_sight(view, candidate + LevelIndex.GRID_DOWN):
				tile = candidate
	_check("(a floor tile where the player can start: %s)" % tile, tile.x >= 0)
	_click(view, _top_of(view, tile + LevelIndex.GRID_DOWN), MOUSE_BUTTON_LEFT)
	await _settle()
	_check("Spawn: a click on a floor tile starts the player there", room.player_spawn_point == tile)
	await _undo()

	var movable_tool := _screen.box_tools[BoxBrush.Kind.MOVABLE]
	_screen.use_tool(movable_tool)
	_screen.use_tool_named("Repaint")
	var repaint_at := _top_of(view, Vector3i(0, 1, 0))
	var to_repaint := view.pick(repaint_at).box
	_set_flags_for_the_test(to_repaint, {&"movable_2d_whole_face": false, &"movable_3d_pos_x": false})
	await _settle()
	_click(view, repaint_at, MOUSE_BUTTON_LEFT)
	await _settle()
	_check("Repaint: a click gives a box the last brush's settings", to_repaint != null and to_repaint.movable_2d_whole_face and to_repaint.movable_3d_pos_x)
	await _undo()
	await _undo()

	_screen.use_tool_named("Handles")
	var side := view.camera.unproject_position(GridCoordsProvider.grid_to_godot(Vector3i(4, 4, 0)) + Vector3(1.0, 0.5, 0.5))
	var hit_there := view.pick(side)
	_check("(the click for Shift + Handles lands on a side of a box that moves)", hit_there.has_box and hit_there.normal.z == 0 and not hit_there.box.is_terrain())
	if hit_there.has_box and hit_there.normal.z == 0:
		var handled := hit_there.box.get_parent() as Structure
		var flag := BoxBrush.SIDE_FLAG_3D[HandlesTool.SIDE_OF_NORMAL[hit_there.normal]]
		var reached: Array[Box] = []
		for each in handled.boxes():
			var beyond := _box_at(room, each.world_cell + hit_there.normal)
			if not each.is_terrain() and (beyond == null or beyond.get_parent() != handled):
				reached.append(each)
		var turning_on: bool = not hit_there.box.get(flag)
		_click_with(view, side, MOUSE_BUTTON_LEFT, true, false, false)
		await _settle()
		_check("Handles: Shift + click sets that side on every box of the group facing out that way (%d)" % reached.size(), reached.all(func(each: Box) -> bool: return each.get(flag) == turning_on))
		await _undo()

	_screen.use_tool(movable_tool)
	_screen.select([one] as Array[Box], [])
	_key(view, KEY_C, true)
	_key(view, KEY_V, true)
	var stamp := Vector3i(-1, -1, -1)
	for y in range(room.dimensions.y - 1, -1, -1):
		for x in range(room.dimensions.x - 1, -1, -1):
			if stamp.x < 0 and _box_at(room, Vector3i(x, y, 0)) == null and _box_at(room, Vector3i(x, y, 1)) == null and _box_at(room, Vector3i(x, y, -1)) != null and _top_is_in_sight(view, Vector3i(x, y, -1)):
				stamp = Vector3i(x, y, 0)
	_check("(a free floor tile to paste on: %s)" % stamp, stamp.x >= 0)
	var stamp_on_screen := _top_of(view, stamp + LevelIndex.GRID_DOWN)
	view._mouse_position = stamp_on_screen
	view._mouse_inside = true
	view._update_the_hover()
	_click_with(view, stamp_on_screen, MOUSE_BUTTON_LEFT, true, false, false)
	await _settle()
	_check("Paste: Shift + click places a copy and keeps pasting", _screen.current_tool is PasteTool and _box_at(room, stamp) != null)
	_key(view, KEY_ESCAPE)
	await _frames(2)
	view._mouse_inside = false
	_check("  and Esc stops", not _screen.current_tool is PasteTool)
	await _undo()
	_check("  (undone)", _box_at(room, stamp) == null)
	_screen.clear_selection()

	var victim := Vector3i(0, 0, 8)
	_screen.edits.paint(BoxBrush.for_kind(BoxBrush.Kind.BLOCK), [victim], null, null)
	await _settle()
	_check("(a box up in the air, in sight, for the next test)", _top_is_in_sight(view, victim))
	_screen.use_tool_named("Eraser")
	var on_the_victim := _top_of(view, victim)
	_press_and_move(view, on_the_victim, on_the_victim + Vector2(1, 1))
	_screen.history.undo()
	await _settle()
	var after_the_undo := _fingerprint()
	_release(view, on_the_victim)
	await _settle()
	view._mouse_inside = false
	_check("Undo in the middle of an eraser stroke: the release erases nothing else, and nothing breaks", _box_at(room, victim) == null and _fingerprint() == after_the_undo)


## Si un clic en el medio de esa tapa le da a esa tapa, y no a algo que la tapa.
func _top_is_in_sight(view: LevelEditorView, cell: Vector3i) -> bool:
	var hit := view.pick(_top_of(view, cell))
	return hit.has_box and hit.cell == cell and hit.face == Powerable.Face.TOP


## Banderas puestas sin pasar por la herramienta, para preparar una prueba (se deshacen con la historia).
func _set_flags_for_the_test(box: Box, flags: Dictionary[StringName, bool]) -> void:
	if box != null:
		_screen.edits.set_box_flags([box] as Array[Box], flags, "Prepare a test")


func _click_with(view: LevelEditorView, at: Vector2, button: MouseButton, shift: bool, ctrl: bool, alt: bool) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = at
		event.shift_pressed = shift
		event.ctrl_pressed = ctrl
		event.alt_pressed = alt
		event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
		view._gui_input(event)


## Aprieta en un punto, se mueve un poco (ya es un arrastre), aprieta una tecla y suelta.
func _drag_with_a_key(view: LevelEditorView, from: Vector2, to: Vector2, keycode: Key) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(press)
	for step in 4:
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, (step + 1) / 4.0) + Vector2(0, 6) * (step + 1) / 4.0
		motion.relative = Vector2(0, 2)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		view._gui_input(motion)
	_key(view, keycode)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	view._gui_input(release)


#==================Un nivel nuevo por el diálogo==================

const SECOND_SCRATCH_NAME := "_scratch_level_2"
const SECOND_SCRATCH_PATH := "res://addons/tgsp_level_editor/tests/_scratch_level_2.tscn"

## Por el diálogo de verdad, en la carpeta de las pruebas: valida el nombre, crea, abre, y se vuelve
## al nivel de prueba con Open. Devuelve si se volvió.
func _test_the_new_level_dialog() -> bool:
	var second_path := SECOND_SCRATCH_PATH
	var folder_before := _screen.levels_folder
	_screen.levels_folder = "res://addons/tgsp_level_editor/tests/"
	_screen.ask_for_a_new_level()
	await _frames(2)
	_check("New level asks for a file name first", _screen._new_level_dialog.visible and _screen._new_level_dialog.get_ok_button().disabled)
	_screen._new_level_name.text = "has spaces"
	_screen._check_the_new_level()
	_check("  refuses a name with spaces", not _screen._new_level_error.text.is_empty())
	_screen._new_level_name.text = SCRATCH_PATH.get_file().get_basename()
	_screen._check_the_new_level()
	_check("  refuses a name that's taken", _screen._new_level_error.text.contains("already"))
	_screen._new_level_name.text = SECOND_SCRATCH_NAME
	_screen._check_the_new_level()
	_check("  takes a good one", _screen._new_level_error.text.is_empty() and not _screen._new_level_dialog.get_ok_button().disabled)
	_screen._new_level_size[0].value = 5
	_screen._new_level_size[1].value = 4
	_screen._new_level_size[2].value = 2
	_screen._new_level_dialog.hide()
	_screen._create_the_new_level()
	var opened := false
	for frame in 700:
		await _tree.process_frame
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == second_path and _screen.level_root == root:
			opened = true
			break
	_screen.levels_folder = folder_before
	_check("  and Create makes the level and opens it", opened)
	if opened:
		_check("  with the size asked for and the player in the middle", _screen.room.dimensions == Vector3i(5, 4, 2) and _screen.room.player_spawn_point == Vector3i(2, 2, 0))
		await _test_switching_scenes_mid_stroke(second_path)
		if EditorInterface.get_edited_scene_root() != null and EditorInterface.get_edited_scene_root().scene_file_path == second_path:
			EditorInterface.close_scene()
			await _frames(5)
	_screen.open_requested.emit(SCRATCH_PATH)
	for frame in 120:
		await _tree.process_frame
		if _on_the_scratch_level():
			break
	if FileAccess.file_exists(second_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(second_path))
	_check("Open goes back to the scratch level", _on_the_scratch_level())
	return _on_the_scratch_level()


## Un trazo empezado en un nivel y soltado en otro (cambió la pestaña de escena) no pinta en ninguno.
func _test_switching_scenes_mid_stroke(second_path: String) -> void:
	_screen.open_requested.emit(SCRATCH_PATH)
	for frame in 120:
		await _tree.process_frame
		if _on_the_scratch_level():
			break
	if not _on_the_scratch_level():
		_check("(back on the scratch level for the scene-switch test)", false)
		return
	var view := _screen.view
	view.game_view()
	await _frames(3)
	var first_level := _fingerprint()
	_screen.use_tool(_screen.box_tools[BoxBrush.Kind.BLOCK])
	var free_top := Vector3i(-1, -1, -1)
	for cell: Vector3i in _screen.room.index.cells_3D:
		if free_top.x < 0 and not _screen.room.index.cells_3D.has(cell + LevelIndex.GRID_UP) and _top_is_in_sight(view, cell):
			free_top = cell
	var from := _top_of(view, free_top)
	_press_and_move(view, from, from + Vector2(30, 10))
	EditorInterface.open_scene_from_path(second_path)
	for frame in 120:
		await _tree.process_frame
		if _screen.level_root != null and _screen.level_root.scene_file_path == second_path:
			break
	var second_level := _fingerprint()
	_release(view, from + Vector2(30, 10))
	await _settle()
	view._mouse_inside = false
	_check("A stroke started in one level and let go in another paints in neither: here", _screen.level_root.scene_file_path == second_path and _fingerprint() == second_level)
	EditorInterface.close_scene()
	await _frames(5)
	_screen.open_requested.emit(SCRATCH_PATH)
	for frame in 120:
		await _tree.process_frame
		if _on_the_scratch_level():
			break
	_check("  and there", _on_the_scratch_level() and _fingerprint() == first_level)


#==================El archivo==================

func _on_the_scratch_level() -> bool:
	var root := EditorInterface.get_edited_scene_root()
	return root != null and root.scene_file_path == SCRATCH_PATH and _screen.level_root == root and _screen.room != null


func _test_the_saved_file() -> void:
	if not _on_the_scratch_level():
		_check("The scratch level is still the open scene before saving", false)
		return
	_screen.toggle_2d()
	await _until_the_turn_ends()
	var light := (_screen.room.get_node(^"ProjectiveCamera") as ProjectiveCamera).light
	_check("The 2D view hides the shadows", light != null and light.shadow_opacity == 0.0)
	if not _on_the_scratch_level():
		return
	var hidden_group := _group_at(_screen.room, Vector3i(0, 1, 0))
	_screen.view.hidden_groups[hidden_group] = true
	_screen.change_layer(0)
	_screen.view.apply_hiding()
	EditorInterface.save_scene()
	await _settle()
	_check("  and puts them back after saving", light != null and light.shadow_opacity == 0.0)
	_check("Hidden groups and layer mode hide boxes while saving...", not (hidden_group.boxes()[0].get_node(^"Mesh") as Node3D).visible)
	_screen.view.hidden_groups.erase(hidden_group)
	_screen.leave_layer_mode()
	_screen.toggle_2d()
	await _until_the_turn_ends()
	_check("  and back in 3D they're on", light != null and light.shadow_opacity == 1.0)
	var text := FileAccess.get_file_as_string(SCRATCH_PATH)
	var editor_boxes := 0
	var with_extra_lines := 0
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].begins_with("[node") and lines[i].contains("instance=ExtResource") and (lines[i].contains("Movable") or lines[i].contains("Walkable") or lines[i].contains("HangingPlatform")):
			editor_boxes += 1
			if lines[i].contains("type=\"Node3D\""):
				with_extra_lines += 1
	_check("The saved level has the editor's boxes as plain instances (%d found)" % editor_boxes, editor_boxes > 0 and with_extra_lines == 0)
	_check("  and no shadow change was saved", not text.contains("shadow_opacity"))
	_check("  ...and none of that hiding was saved", not text.contains("visible = false"))
	if not _on_the_scratch_level():
		return
	_screen.request_play()
	var started := false
	for frame in 300:
		await _tree.process_frame
		if EditorInterface.is_playing_scene():
			started = true
			break
	_check("Play saves and runs the level", started)
	EditorInterface.stop_playing_scene()
	await _frames(10)


#==================Capturas==================

func _screenshots() -> void:
	var folder := OS.get_environment("LEVEL_EDITOR_SHOTS")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("user://level_editor_shots")
	DirAccess.make_dir_recursive_absolute(folder)
	# Sin esto el editor deja de dibujar cuando no pasa nada, y frame_post_draw nunca llega.
	OS.low_processor_usage_mode = false
	EditorInterface.open_scene_from_path("res://scenes/levels/test_level.tscn")
	EditorInterface.set_main_screen_editor("Level")
	await _frames(30)
	var room := _screen.room
	var view := _screen.view
	# Las capturas sólo miran: al final la historia de la escena tiene que seguir igual.
	var scene_history := (_screen.history as EditorHistory)._scene_history
	var version_before := scene_history.get_version()
	view.game_view()
	await _frames(3)

	var free_top := _free_top_near_the_middle(room, view)
	_screen.use_tool(_screen.box_tools[BoxBrush.Kind.MOVABLE])
	await _hover_cell(free_top)
	await _shot(folder, "01_brush_hover")

	_screen.use_tool_named("Select")
	var some_box: Box = room.index.cells_3D.get(Vector3i(1, 10, 0))
	if some_box != null:
		_screen.select([some_box], [])
	_screen._tabs.current_tab = 0
	await _frames(5)
	await _shot(folder, "02_one_box_and_its_faces")

	var piece: Powerable = null
	for each in room.index.every_powerable():
		if each is ButtonPowerable:
			piece = each
			break
	if piece != null:
		_screen.select([], [piece])
	_screen._set_overlay(true, &"show_power")
	_screen.use_tool(_screen.tools[BoxBrush.PALETTE.size()])
	if piece != null:
		await _hover_cell(room.index.cell_of(piece.box))
	await _shot(folder, "03_piece_and_power_overlay")
	_screen._set_overlay(false, &"show_power")

	_screen.use_tool(_screen.box_tools[BoxBrush.Kind.FLOOR])
	_screen.toggle_2d()
	await _until_the_turn_ends()
	_screen._tabs.current_tab = 3
	await _shot(folder, "04_2d_heights_and_problems")
	_screen.use_tool(_screen.box_tools[BoxBrush.Kind.MOVABLE])
	await _hover_cell(free_top)
	await _shot(folder, "05_2d_brush_hover")
	_screen.toggle_2d()
	await _until_the_turn_ends()

	_screen.use_tool_named("Handles")
	await _hover_cell(Vector3i(16, 3, 0))
	await _shot(folder, "06_handles_hover")
	await _hold_shift(true)
	await _shot(folder, "07_handles_with_shift")
	await _hold_shift(false)

	var group := _big_group_in_sight(room, view)
	_screen.use_tool_named("Select")
	if group != null:
		_screen.select(group.boxes(), [])
		_screen._tabs.current_tab = 0
		var other := _big_group_in_sight(room, view, group)
		if other != null:
			await _hover_cell(other.boxes()[0].world_cell)
	await _frames(4)
	await _shot(folder, "08_group_selected_and_another_hovered")

	if group != null:
		var second := _big_group_in_sight(room, view, group)
		if second != null:
			_screen.add_to_selection(second.boxes())
	_screen._tabs.current_tab = 1
	await _frames(4)
	await _shot(folder, "09_groups_panel_two_groups")

	if group != null:
		_screen.select(group.boxes(), [])
		var grab_at := _top_of(view, _highest_box_of(group).world_cell)
		_press_and_move(view, grab_at, grab_at + Vector2(70, 25))
		await _frames(4)
		await _shot(folder, "10_moving_a_group")
		_screen.current_tool.cancel()
		_release(view, grab_at + Vector2(70, 25))
		await _frames(2)

	_screen.clear_selection()
	_press_and_move(view, Vector2(12, 12), view.size * 0.45)
	await _frames(4)
	await _shot(folder, "11_rectangle_select")
	_screen.current_tool.cancel()
	_release(view, view.size * 0.45)
	await _frames(2)

	_screen.use_tool(_screen.tools[BoxBrush.PALETTE.size()])
	var wire_from := free_top + Vector3i(1, 1, 0)
	var wire_to := free_top + Vector3i(-1, -1, 0)
	_press_and_move(view, _top_of(view, wire_from), _top_of(view, wire_to))
	await _frames(4)
	await _shot(folder, "12_laying_wire")
	_screen.current_tool.cancel()
	_release(view, _top_of(view, wire_to))
	await _frames(2)

	_screen.use_tool(_screen.piece_tools[&"Door"])
	view._mouse_position = view.camera.unproject_position(GridCoordsProvider.grid_to_godot(free_top) + Vector3(0.5, 1.0, 0.9))
	view._mouse_inside = true
	view._update_the_hover()
	await _frames(6)
	await _shot(folder, "13_door_ghost_on_an_edge")

	if group != null:
		_screen.use_tool_named("Select")
		_screen.select(group.boxes(), [])
		_screen.copy_selection()
		await _frames(2)
		await _shot(folder, "14_flash_copied")
		_screen.start_pasting()
		await _hover_cell(free_top)
		await _shot(folder, "15_paste_ghost")
		_screen.stop_pasting()
		await _frames(2)

	_screen.use_tool_named("Eraser")
	await _hover_cell(free_top)
	await _shot(folder, "16_eraser_hover")

	_screen.use_tool_named("Spawn")
	await _hover_cell(free_top)
	await _shot(folder, "17_spawn_hover")

	_screen.use_tool(_screen.box_tools[BoxBrush.Kind.MOVABLE])
	_screen.use_tool_named("Repaint")
	await _hover_cell(Vector3i(3, 3, -1))
	await _shot(folder, "18_repaint_refused_on_the_shell")

	_screen.use_tool(_screen.box_tools[BoxBrush.Kind.BLOCK])
	_screen.change_layer(0)
	while _screen.layer < 1:
		_screen.change_layer(1)
	await _hover_cell(free_top)
	await _shot(folder, "19_layer_mode")
	_screen.leave_layer_mode()

	var emitter: Powerable = null
	var exit: Powerable = null
	for each in room.index.every_powerable():
		if each is LaserEmitter and emitter == null:
			emitter = each
		if each is ExitDoor and exit == null:
			exit = each
	_screen.use_tool_named("Select")
	if emitter != null:
		_screen.select([], [emitter])
		view.frame_cells([room.index.cell_of(emitter.box)])
		await _frames(6)
		await _shot(folder, "20_laser_and_its_beam")
	if exit != null:
		_screen.select([], [exit])
		_screen._tabs.current_tab = 0
		view.game_view()
		await _frames(6)
		await _shot(folder, "21_exit_door_properties")
	_screen._tabs.current_tab = 2
	await _frames(4)
	await _shot(folder, "22_level_panel")

	_screen.clear_selection()
	view.toggle_perspective_projection()
	await _frames(6)
	await _shot(folder, "23_perspective_camera")
	view.toggle_perspective_projection()
	view._orbit(Vector2(120, -40))
	await _frames(6)
	await _shot(folder, "24_free_orbit")
	view.game_view()
	await _frames(3)

	_screen.use_tool_named("Select")
	var wire_piece: Powerable = null
	for each in room.index.every_powerable():
		if each is Wire and _top_is_in_sight(view, room.index.cell_of(each.box)) and each.face == Powerable.Face.TOP:
			wire_piece = each
			break
	if wire_piece != null:
		await _hover_cell(room.index.cell_of(wire_piece.box))
		await _hold_ctrl(true)
		await _shot(folder, "25_ctrl_hover_on_a_piece")
		await _hold_ctrl(false)

	_screen.ask_for_a_new_level()
	_screen._new_level_name.text = "level_04"
	_screen._check_the_new_level()
	await _frames(5)
	await _shot(folder, "26_new_level_dialog", _screen._new_level_dialog)
	_screen._new_level_dialog.hide()
	_screen.show_the_help()
	await _frames(5)
	print("    help visible: ", _screen._help.visible)
	await _shot(folder, "27_help", _screen._help)
	_screen._help.hide()

	print("    edits made while taking the shots: %d (must be 0)" % (scene_history.get_version() - version_before))
	EditorInterface.open_scene_from_path("res://scenes/prefabs/box.tscn")
	EditorInterface.set_main_screen_editor("Level")
	await _frames(20)
	await _shot(folder, "28_not_a_level")


## Una tapa libre en un lugar despejado (nada encima de ella ni de sus ocho vecinas), a la vista, lo
## más cerca posible del medio de la vista: ahí los fantasmas se ven enteros.
func _free_top_near_the_middle(room: Room, view: LevelEditorView) -> Vector3i:
	var best := Vector3i.ZERO
	var best_distance := INF
	for cell: Vector3i in room.index.cells_3D:
		if (room.index.cells_3D[cell] as Box).powerable_on(Powerable.Face.TOP) != null:
			continue
		var crowded := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(1, 3):
					crowded = crowded or room.index.cells_3D.has(cell + Vector3i(dx, dy, dz))
		if crowded:
			continue
		var distance := _top_of(view, cell).distance_to(view.size * 0.5)
		if distance < best_distance and _top_is_in_sight(view, cell):
			best = cell
			best_distance = distance
	return best


func _big_group_in_sight(room: Room, view: LevelEditorView, not_this: Structure = null) -> Structure:
	for each in room.find_children("*", "", true, false):
		var group := each as Structure
		if group == null or group == not_this or _screen.edits.is_shell_part(group) or group.boxes().size() < 3:
			continue
		if _top_is_in_sight(view, _highest_box_of(group).world_cell):
			return group
	return null


func _highest_box_of(group: Structure) -> Box:
	var highest := group.boxes()[0]
	for box in group.boxes():
		if box.world_cell.z > highest.world_cell.z:
			highest = box
	return highest


func _press_and_move(view: LevelEditorView, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._mouse_inside = true
	view._gui_input(press)
	for step in 8:
		var motion := InputEventMouseMotion.new()
		motion.position = from.lerp(to, (step + 1) / 8.0)
		motion.relative = (to - from) / 8.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		view._gui_input(motion)


func _release(view: LevelEditorView, at: Vector2) -> void:
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	view._gui_input(release)


func _hold_shift(down: bool) -> void:
	await _hold(KEY_SHIFT, down)


func _hold_ctrl(down: bool) -> void:
	await _hold(KEY_CTRL, down)


## Por la entrada de verdad: así Input.is_key_pressed lo ve, como lo ven los dibujos.
func _hold(keycode: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_screen.redraw()
	await _frames(4)


func _hover_cell(cell: Vector3i) -> void:
	var view := _screen.view
	await _frames(3)
	view._mouse_position = view.camera.unproject_position(GridCoordsProvider.grid_to_godot(cell) + Vector3(0.62, 1.0, 0.5))
	view._mouse_inside = true
	view._update_the_hover()
	await _frames(4)


## `window`: un diálogo es una ventana aparte del sistema, que la captura de la del editor no muestra.
func _shot(folder: String, shot_name: String, window: Window = null) -> void:
	await RenderingServer.frame_post_draw
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(folder.path_join(shot_name + ".png"))
	if window != null and window.visible:
		window.get_texture().get_image().save_png(folder.path_join(shot_name + "_window.png"))
	var view_area := Rect2i(_screen.view.get_global_rect())
	if view_area.has_area():
		image.get_region(view_area).save_png(folder.path_join(shot_name + "_view.png"))
	print("    shot  ", shot_name)
