@tool
class_name LevelEditorLevelPanel
extends VBoxContainer
## Lo del nivel entero: su archivo, el tamaño del cuarto, dónde y en qué vista empieza el jugador, y
## cada salida con a dónde lleva (cada puerta guarda la suya, así que hay caminos que se ramifican).

var screen: LevelEditorScreen


func _init(the_screen: LevelEditorScreen) -> void:
	screen = the_screen
	name = "Level"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var level_room := screen.room
	if level_room == null:
		return
	_heading("File")
	var file := Label.new()
	file.text = screen.level_root.scene_file_path.get_file() if not screen.level_root.scene_file_path.is_empty() else "Not saved yet"
	add_child(file)
	var file_actions := HFlowContainer.new()
	add_child(file_actions)
	LevelEditorPropertiesPanel._button(file_actions, "New level…", "Make a new level from the template.", screen.ask_for_a_new_level)
	LevelEditorPropertiesPanel._button(file_actions, "Play", "Save and play this level.", screen.request_play)
	add_child(HSeparator.new())

	_heading("Room size")
	# Se acomoda en dos renglones si no entra: el panel no se ensancha al abrir esta pestaña.
	var size_row := HFlowContainer.new()
	add_child(size_row)
	var fields: Array[SpinBox] = []
	for axis in 3:
		# Cada letra con su campo, así al pasar al renglón de abajo no se separan.
		var pair := HBoxContainer.new()
		size_row.add_child(pair)
		LevelEditorTool.caption(pair, ["X", "Y", "Z"][axis])
		var field := SpinBox.new()
		field.min_value = 1
		field.max_value = 40
		field.value = level_room.dimensions[axis]
		field.custom_minimum_size.x = screen.scaled(56)
		pair.add_child(field)
		fields.append(field)
	LevelEditorPropertiesPanel._button(size_row, "Apply", "Resize the room. Holes are kept, and undo gives back what a shrink trims.", func() -> void:
		screen.resize_room(Vector3i(int(fields[0].value), int(fields[1].value), int(fields[2].value)))
	)
	add_child(HSeparator.new())

	_heading("Start")
	var spawn_row := HBoxContainer.new()
	add_child(spawn_row)
	var spawn := Label.new()
	spawn.text = "Player at %s" % LevelEditorTool.describe(level_room.player_spawn_point)
	spawn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_row.add_child(spawn)
	LevelEditorPropertiesPanel._button(spawn_row, "Spawn tool", "Click a top in the view to start the player there.", screen.use_tool_named.bind("Spawn"))
	var view_row := HBoxContainer.new()
	add_child(view_row)
	LevelEditorTool.caption(view_row, "Starts in")
	var starting := OptionButton.new()
	starting.add_item("3D", Room.Perspective.ISO_3D)
	starting.add_item("2D", Room.Perspective.TOP_2D)
	starting.selected = 1 if Room.is_2d(screen.starting_perspective()) else 0
	starting.focus_mode = Control.FOCUS_NONE
	starting.disabled = level_room.perspective_manager == null
	starting.item_selected.connect(func(item: int) -> void: screen.edits.set_starting_perspective(starting.get_item_id(item) as Room.Perspective))
	view_row.add_child(starting)
	add_child(HSeparator.new())

	_heading("Exits")
	var exits := screen.exits()
	if exits.is_empty():
		var none := Label.new()
		none.text = "This level has no exit door. Place one with the Exit tool."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.modulate = Color(1, 0.6, 0.5)
		add_child(none)
	for exit in exits:
		_exit_row(exit)


func _heading(text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.add_theme_font_size_override(&"font_size", 15)
	add_child(heading)


func _exit_row(exit: ExitDoor) -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var where := HBoxContainer.new()
	box.add_child(where)
	var place := Label.new()
	var structure := exit.box.get_parent()
	var its_structure := "Room floor" if screen.edits.is_shell_part(structure) else (String(structure.name) if structure is Structure else String(exit.box.name))
	place.text = "%s · %s" % [its_structure, LevelEditorTool.describe(exit.box.world_cell)]
	place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.add_child(place)
	LevelEditorPropertiesPanel._button(where, "Go to", "Select this exit and frame it.", screen.go_to_piece.bind(exit))
	var leads := HBoxContainer.new()
	box.add_child(leads)
	LevelEditorTool.caption(leads, "Leads to")
	leads.add_child(screen.level_picker(exit.next_level, func(path: String) -> void:
		screen.edits.set_piece_properties([exit], {&"next_level": path}, "Exit leads to %s" % (path.get_file() if not path.is_empty() else "a restart"))
	))
	var open := CheckBox.new()
	open.text = "Always open"
	open.tooltip_text = "Open without any power. Careful: an open door isn't drawn in the game."
	open.button_pressed = exit.always_open
	open.focus_mode = Control.FOCUS_NONE
	open.toggled.connect(func(on: bool) -> void: screen.edits.set_piece_properties([exit], {&"always_open": on}, "Exit always open: %s" % ("on" if on else "off")))
	box.add_child(open)
