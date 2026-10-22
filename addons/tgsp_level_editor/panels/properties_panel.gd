@tool
class_name LevelEditorPropertiesPanel
extends VBoxContainer
## Lo que está elegido, en palabras: las banderas de las cajas, lo del grupo entero y lo de un
## powerable. Con varias cosas elegidas, un valor que no coincide dice "mixed" y un cambio va a todas.

var screen: LevelEditorScreen

const FLAG_TEXT: Array[Array] = [
	[&"walkable", "Can be stood on", "Its top is a tile the player can stand on."],
	[&"is_floor", "Floor tile (terrain)", "Terrain drawn with a floor tile on top: always walkable, never moves."],
	[&"is_wall", "Wall tiles (terrain)", "Terrain drawn with wall tiles: never moves."],
	[&"keeps_height", "Keeps its height", "In 2D it never drops onto lower ground, and it is held by touching anything, like a shelf. It goes to the whole group: one box is enough for all of it."],
	[&"top_half_only", "Draw top half only", "Only a drawing detail: to the rules it is a whole cell."],
]

const DIRECTION_TEXT: Dictionary[Vector3i, String] = {
	Vector3i(1, 0, 0): "+x", Vector3i(-1, 0, 0): "−x",
	Vector3i(0, 1, 0): "+y", Vector3i(0, -1, 0): "−y",
	Vector3i(0, 0, 1): "up", Vector3i(0, 0, -1): "down",
}


func _init(the_screen: LevelEditorScreen) -> void:
	screen = the_screen
	name = "Properties"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if screen.room == null:
		return
	if not screen.selected_pieces.is_empty():
		_show_pieces(screen.selected_pieces)
	elif not screen.selected_boxes.is_empty():
		_show_boxes(screen.selected_boxes)
	else:
		_note("Nothing selected. Use Select (V) and click a group, or a power tool and click a piece.")


func _note(text: String) -> Label:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.7)
	add_child(note)
	return note


func _heading(text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.add_theme_font_size_override(&"font_size", 15)
	add_child(heading)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	add_child(row)
	return row


static func _button(row: Control, text: String, tooltip: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	row.add_child(button)
	return button


#==================Cajas==================

func _show_boxes(boxes: Array[Box]) -> void:
	var groups := screen.groups_of(boxes)
	var whole_groups := screen.selection_is_whole_groups()
	if whole_groups and groups.size() == 1 and groups[0] is Structure:
		_show_group(groups[0] as Structure)
	else:
		_heading("%d box%s" % [boxes.size(), "" if boxes.size() == 1 else "es"])
		if groups.size() == 1 and groups[0] is Structure:
			_note("In %s" % groups[0].name)
		elif groups.size() > 1:
			_note("In %d groups" % groups.size())
	add_child(HSeparator.new())
	_heading("Kind")
	var kinds := HFlowContainer.new()
	add_child(kinds)
	for kind in BoxBrush.PALETTE:
		var button := _button(kinds, "", "Give the selected boxes the settings of %s (a repaint)." % BoxBrush.LABEL[kind], _repaint_as.bind(kind))
		button.icon = LevelEditorIcons.get_icon(BoxBrush.LABEL[kind], screen.icon_scale)
	add_child(HSeparator.new())
	_heading("Settings")
	for each in FLAG_TEXT:
		var flag: StringName = each[0]
		var values := _values_of(boxes, flag)
		var check := CheckBox.new()
		check.text = each[1] + (" (mixed)" if values.size() > 1 else "")
		check.tooltip_text = each[2]
		check.button_pressed = values.size() == 1 and values.has(true)
		check.focus_mode = Control.FOCUS_NONE
		if flag == &"walkable" and _all(boxes, &"is_floor"):
			check.disabled = true
			check.tooltip_text += " A floor is always walkable."
		check.toggled.connect(_set_flag.bind(flag))
		add_child(check)
	var any_movable := boxes.any(func(box: Box) -> bool: return not box.is_terrain())
	if not any_movable:
		_note("Terrain never moves, so it has no handles.")
		_show_faces_if_one(boxes)
		return
	_heading("Grab in 3D from")
	var sides := _row()
	for facing: Box.Facing in BoxBrush.SIDE_FLAG_3D:
		_flag_toggle(sides, boxes, LevelEditorTool.FACING_TEXT[facing], BoxBrush.SIDE_FLAG_3D[facing], "Its %s side is a handle in 3D." % LevelEditorTool.FACING_TEXT[facing])
	_heading("Grab in 2D from")
	var edges := _row()
	_flag_toggle(edges, boxes, "Whole top", &"movable_2d_whole_face", "Its whole top is a handle in 2D. Not on a walkable box: pick its edges.")
	for facing: Box.Facing in BoxBrush.EDGE_FLAG_2D:
		_flag_toggle(edges, boxes, LevelEditorTool.FACING_TEXT[facing], BoxBrush.EDGE_FLAG_2D[facing], "Its %s top edge is a handle in 2D (an orange stripe; a wall for the player in 2D)." % LevelEditorTool.FACING_TEXT[facing])
	_note("Directions are the grid's: the compass in the view shows +x and +y.")
	_show_faces_if_one(boxes)


func _flag_toggle(row: HBoxContainer, boxes: Array[Box], text: String, flag: StringName, tooltip: String) -> void:
	var values := _values_of(boxes, flag)
	var button := Button.new()
	button.text = text + ("*" if values.size() > 1 else "")
	button.toggle_mode = true
	button.button_pressed = values.size() == 1 and values.has(true)
	button.tooltip_text = tooltip + (" (* mixed)" if values.size() > 1 else "")
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(_set_flag.bind(flag))
	row.add_child(button)


static func _values_of(boxes: Array[Box], flag: StringName) -> Dictionary:
	var values := {}
	for box in boxes:
		values[box.get(flag)] = true
	return values


static func _all(boxes: Array[Box], flag: StringName) -> bool:
	for box in boxes:
		if not box.get(flag):
			return false
	return true


func _set_flag(on: bool, flag: StringName) -> void:
	var boxes: Array[Box] = []
	for box in screen.selected_boxes:
		if flag == &"movable_2d_whole_face" and on and box.walkable:
			continue
		if flag.begins_with("movable") and box.is_terrain():
			continue
		boxes.append(box)
	if flag == &"keeps_height":
		boxes = _boxes_of_their_groups(boxes)
	if (flag == &"is_floor" or flag == &"is_wall") and screen.would_split_terrain(boxes, flag, on):
		screen.flash("A group is either all terrain or holds none: select the whole group, or group these boxes on their own first.", true)
		refresh()
		return
	screen.edits.set_box_flags(boxes, {flag: on}, "%s: %s" % [flag_label(flag), "on" if on else "off"])


## Una Structure mantiene la altura con que una sola caja la mantenga: la bandera va al grupo entero.
func _boxes_of_their_groups(boxes: Array[Box]) -> Array[Box]:
	var all_of_them: Dictionary[Box, bool] = {}
	for box in boxes:
		all_of_them[box] = true
		var group := box.get_parent() as Structure
		if group != null and not screen.edits.is_shell_part(group):
			for sibling in group.boxes():
				all_of_them[sibling] = true
	var result: Array[Box] = []
	result.assign(all_of_them.keys())
	return result


## Cómo se llama una bandera para quien diseña, en la historia y en los avisos.
static func flag_label(flag: StringName) -> String:
	for each in FLAG_TEXT:
		if each[0] == flag:
			return each[1]
	for facing: Box.Facing in BoxBrush.SIDE_FLAG_3D:
		if BoxBrush.SIDE_FLAG_3D[facing] == flag:
			return "3D handle " + LevelEditorTool.FACING_TEXT[facing]
		if BoxBrush.EDGE_FLAG_2D[facing] == flag:
			return "2D handle " + LevelEditorTool.FACING_TEXT[facing]
	if flag == &"movable_2d_whole_face":
		return "2D whole top"
	return String(flag)


func _repaint_as(kind: BoxBrush.Kind) -> void:
	screen.repaint_selection(BoxBrush.for_kind(kind))


func _show_group(group: Structure) -> void:
	_heading("Group")
	var name_row := _row()
	var name_edit := LineEdit.new()
	name_edit.text = group.name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.tooltip_text = "Rename the group (F2). A new name gives it a new shade."
	name_edit.text_submitted.connect(func(text: String) -> void: screen.edits.rename(group, text))
	name_edit.focus_exited.connect(func() -> void:
		if is_instance_valid(group) and is_instance_valid(name_edit) and name_edit.text != group.name:
			screen.edits.rename(group, name_edit.text)
	)
	name_row.add_child(name_edit)
	screen.group_name_field = name_edit
	var shade := ColorRect.new()
	shade.custom_minimum_size = Vector2(screen.scaled(18), screen.scaled(18))
	shade.color = screen.shade_of(group)
	name_row.add_child(shade)
	var boxes := group.boxes()
	_note("%d box%s · %s" % [boxes.size(), "" if boxes.size() == 1 else "es", BoxBrush.label_of_group(boxes)])
	var actions := HFlowContainer.new()
	add_child(actions)
	_button(actions, "Exposed tops walkable", "Walkable where no box of the group sits on top.", screen.mark_exposed_tops_walkable)
	_button(actions, "Make unwalkable", "No box of the group can be stood on.", screen.make_unwalkable)
	_button(actions, "Grab every outer side (3D)", "A 3D handle on every side of the group that faces out.", screen.grab_every_outer_side)
	_button(actions, "Grab every outer edge (2D)", "A 2D handle on every top edge of the group that faces out.", screen.grab_every_outer_edge)
	if boxes.size() > 1:
		_button(actions, "Ungroup", "Every box gets a group of its own (Ctrl + Shift + G).", screen.ungroup_selection)


func _show_faces_if_one(boxes: Array[Box]) -> void:
	if boxes.size() != 1:
		if boxes.size() > 1 and not screen.selection_is_whole_groups():
			var actions := _row()
			_button(actions, "Group", "Put the selected boxes in one new group (Ctrl + G).", screen.group_selection)
		return
	var box := boxes[0]
	add_child(HSeparator.new())
	_heading("Faces of the box at %s" % LevelEditorTool.describe(box.world_cell))
	for face: Powerable.Face in Powerable.Face.values():
		var row := _row()
		var face_label := Label.new()
		face_label.text = _face_name(face)
		face_label.custom_minimum_size.x = screen.scaled(72)
		row.add_child(face_label)
		var piece := box.powerable_on(face)
		if piece != null:
			var what := Label.new()
			what.text = "%s %s" % [LevelEdits.piece_label(LevelEdits.piece_type(piece)), _directions_text(piece)]
			what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(what)
			_button(row, "Select", "Show this piece's settings.", screen.select.bind([] as Array[Box], [piece] as Array[Powerable]))
			_button(row, "Remove", "Erase this piece.", screen.erase_piece.bind(piece))
		else:
			var add := MenuButton.new()
			add.text = "Add…"
			add.flat = false
			add.tooltip_text = "Put a piece on this face."
			add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for type: StringName in LevelEdits.PIECE_FACES:
				if LevelEdits.PIECE_FACES[type].has(face):
					add.get_popup().add_item(LevelEdits.piece_label(type).capitalize())
					add.get_popup().set_item_metadata(add.get_popup().item_count - 1, type)
			add.get_popup().index_pressed.connect(func(index: int) -> void: screen.add_piece_from_properties(box, face, add.get_popup().get_item_metadata(index)))
			row.add_child(add)


static func _face_name(face: Powerable.Face) -> String:
	match face:
		Powerable.Face.TOP: return "Top"
		Powerable.Face.BOTTOM: return "Bottom"
		Powerable.Face.POS_X: return "+x side"
		Powerable.Face.NEG_X: return "−x side"
		Powerable.Face.POS_Y: return "+y side"
	return "−y side"


static func _directions_text(piece: Powerable) -> String:
	var parts := PackedStringArray()
	for direction in piece.allowed_directions():
		parts.append(DIRECTION_TEXT[direction])
	return "(%s)" % (", ".join(parts) if not parts.is_empty() else "no connections")


#==================Powerables==================

func _show_pieces(pieces: Array[Powerable]) -> void:
	if pieces.size() > 1:
		_heading("%d pieces" % pieces.size())
		_note("Select just one to see its settings.")
		var several := _row()
		_button(several, "Erase them", "Erase every selected piece (Delete).", screen.delete_selection)
		return
	var piece := pieces[0]
	var type := LevelEdits.piece_type(piece)
	_heading(LevelEdits.piece_label(type).capitalize())
	_note("On the %s of the box at %s" % [_face_name(piece.face).to_lower(), LevelEditorTool.describe(piece.box.world_cell)])
	var faces: Array = LevelEdits.PIECE_FACES[type]
	if faces.size() > 1:
		var face_row := _row()
		LevelEditorTool.caption(face_row, "Face")
		var face_option := OptionButton.new()
		face_option.focus_mode = Control.FOCUS_NONE
		for face: Powerable.Face in faces:
			face_option.add_item(_face_name(face), face)
			if face == piece.face:
				face_option.selected = face_option.item_count - 1
		face_option.item_selected.connect(func(item: int) -> void:
			var face := face_option.get_item_id(item) as Powerable.Face
			if piece.box.powerable_on(face) == null:
				screen.edits.set_piece_properties([piece], _changes_to_move(piece, face), "Move the %s to another face" % LevelEdits.piece_label(type))
			else:
				screen.flash("That face already has a piece.", true)
				screen.refresh_panels()
		)
		face_row.add_child(face_option)
	_heading("Connects toward")
	var directions := _row()
	for direction in FaceLinks.directions_along(piece.face):
		var property: StringName = LevelEdits.CONNECTS[direction]
		var button := Button.new()
		button.text = DIRECTION_TEXT[direction]
		button.toggle_mode = true
		button.button_pressed = piece.get(property)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Connect through the %s edge of this face." % DIRECTION_TEXT[direction]
		button.toggled.connect(func(on: bool) -> void: screen.edits.set_piece_properties([piece], {property: on}, "Connect %s %s" % [DIRECTION_TEXT[direction], "on" if on else "off"]))
		directions.add_child(button)
	match type:
		&"ButtonPowerable":
			_piece_check(piece, &"switched_on", "Starts on", "The level starts with this button switched on.")
		&"Door":
			_edge_option(piece)
			_piece_check(piece, &"always_open", "Always open", "Open without any power.")
		&"ExitDoor":
			_edge_option(piece)
			_piece_check(piece, &"always_open", "Always open", "Open without any power. Careful: an open door isn't drawn in the game.")
			var row := _row()
			LevelEditorTool.caption(row, "Leads to")
			row.add_child(screen.level_picker(piece.next_level, func(path: String) -> void: screen.edits.set_piece_properties([piece], {&"next_level": path}, "Exit leads to %s" % (path.get_file() if not path.is_empty() else "a restart"))))
		&"LaserEmitter":
			_piece_check(piece, &"always_on", "Always on", "Shines without any power.")
	var actions := _row()
	_button(actions, "Erase", "Erase this piece.", screen.erase_piece.bind(piece))
	_button(actions, "Select its box", "Select the box it sits on.", screen.select.bind([piece.box] as Array[Box], [] as Array[Powerable]))


## Al cambiar de cara, las direcciones que ya no van por ella se apagan: el inspector las esconde y
## nadie las vería prendidas.
static func _changes_to_move(piece: Powerable, face: Powerable.Face) -> Dictionary:
	var changes := {&"face": face}
	var along := FaceLinks.directions_along(face)
	for direction: Vector3i in LevelEdits.CONNECTS:
		if not along.has(direction) and piece.get(LevelEdits.CONNECTS[direction]):
			changes[LevelEdits.CONNECTS[direction]] = false
	return changes


func _piece_check(piece: Powerable, property: StringName, text: String, tooltip: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.tooltip_text = tooltip
	check.button_pressed = piece.get(property)
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void: screen.edits.set_piece_properties([piece], {property: on}, "%s: %s" % [text, "on" if on else "off"]))
	add_child(check)


func _edge_option(piece: Powerable) -> void:
	var row := _row()
	LevelEditorTool.caption(row, "Edge")
	var edge := OptionButton.new()
	edge.focus_mode = Control.FOCUS_NONE
	for facing: Box.Facing in LevelEditorTool.FACING_TEXT:
		edge.add_item(LevelEditorTool.FACING_TEXT[facing], facing)
		if facing == piece.get(&"edge"):
			edge.selected = edge.item_count - 1
	edge.item_selected.connect(func(item: int) -> void: screen.edits.set_piece_properties([piece], {&"edge": edge.get_item_id(item)}, "Move the door to the %s edge" % edge.get_item_text(item)))
	row.add_child(edge)
