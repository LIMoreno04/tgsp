@tool
class_name LevelEditorScreen
extends VBoxContainer
## Toda la pestaña Level: la barra de arriba, la paleta, la barra de opciones de la herramienta, la
## vista, los paneles de la derecha y la barra de estado. Guarda lo que se está editando (la selección,
## la capa, la herramienta) y no sabe nada del editor de Godot: lo que sólo el editor puede hacer
## (guardar, jugar, abrir, crear un nivel) lo pide con señales, y el host lo hace.

signal play_requested
signal open_requested(path: String)
signal new_level_requested(path: String, dimensions: Vector3i)
signal selection_changed

const BOX_MESH := preload("res://scripts/objects/box_mesh.gd")
const KIND_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
const FLASH_MILLISECONDS := 2500
## El acento del editor de Godot, para la herramienta elegida en la paleta.
const CHOSEN_TOOL_COLOR := Color(0.44, 0.73, 0.98)
## Las teclas que siguen valiendo si se dejan apretadas; las demás sólo cuentan una vez.
const REPEATING_KEYS: Array[Key] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]

var level_root: Node
var room: Room
var edits: LevelEdits
var history: LevelEditorHistory
var levels_folder := "res://scenes/levels/"
## El host lo pone en PackedScene.GEN_EDIT_STATE_INSTANCE dentro del editor.
var edit_state := PackedScene.GEN_EDIT_STATE_DISABLED
var icon_scale := 1.0

var view := LevelEditorView.new()
var layer_mode := false
var layer := 0
var _last_layer := 0

var selected_boxes: Array[Box] = []
var selected_pieces: Array[Powerable] = []
var _selected: Dictionary[Box, bool] = {}
var _current_folder: Node
var group_name_field: LineEdit

var show_power := false
var show_beams := true
var show_heights := true

var tools: Array[LevelEditorTool] = []
var box_tools: Dictionary[BoxBrush.Kind, BoxBrushTool] = {}
var piece_tools: Dictionary[StringName, PieceTool] = {}
var current_tool: LevelEditorTool
var _last_box_tool: BoxBrushTool
var _paste_tool: PasteTool
var _tool_before_pasting: LevelEditorTool
var clipboard: LevelEdits.Clip

var _hit: GridPicker.Hit = GridPicker.Hit.new()
var _palette_buttons: Dictionary[LevelEditorTool, Button] = {}
var _palette_group := ButtonGroup.new()
var _options_bar := HBoxContainer.new()
var _status := Label.new()
var _hint := Label.new()
var _file_label := Label.new()
var _layer_label := Label.new()
var _2d_button := Button.new()
var _perspective_button := Button.new()
var _open_menu := MenuButton.new()
var _tabs := TabContainer.new()
var _properties: LevelEditorPropertiesPanel
var _groups: LevelEditorGroupsPanel
var _level: LevelEditorLevelPanel
var _problems: LevelEditorProblemsPanel
var _body := HSplitContainer.new()
var _no_level := CenterContainer.new()
var _no_level_list := ItemList.new()
var _new_level_dialog := ConfirmationDialog.new()
var _new_level_name := LineEdit.new()
var _new_level_size: Array[SpinBox] = []
var _new_level_error := Label.new()
var _help := AcceptDialog.new()
var _refresh_pending := false
var _redraw_pending := false
## Un aviso corto en la barra de estado ("Copied 3 boxes"), que dura un momento aunque se redibuje.
var _flash_text := ""
var _flash_is_a_refusal := false
var _flash_until := 0
var _leave_layer_button: Button
## Lo que avisa el árbol cuando algo cambia sin pasar por la historia (los botones de una Structure).
var _watched_tree: SceneTree


## `editor_scale`: la escala del editor (EditorInterface.get_editor_scale()); los íconos y los anchos
## fijos la siguen, así en una pantalla grande no quedan chicos al lado del resto.
func _init(editor_scale := 1.0) -> void:
	icon_scale = editor_scale
	name = "LevelEditor"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.screen = self
	_make_the_tools()
	_build()


func _make_the_tools() -> void:
	for kind in BoxBrush.PALETTE:
		var brush_tool := BoxBrushTool.new(self, kind)
		box_tools[kind] = brush_tool
		tools.append(brush_tool)
	tools.append(WireTool.new(self))
	for type: StringName in [&"ButtonPowerable", &"PressurePlate", &"Door", &"ExitDoor", &"LaserEmitter", &"LaserReceiver"]:
		var piece_tool := PieceTool.new(self, type)
		piece_tools[type] = piece_tool
		tools.append(piece_tool)
	for each in [SelectTool.new(self), PickTool.new(self), RepaintTool.new(self), EraserTool.new(self), HandlesTool.new(self), SpawnTool.new(self)]:
		tools.append(each)
	_last_box_tool = box_tools[BoxBrush.Kind.BLOCK]
	_paste_tool = PasteTool.new(self)


#==================Armar la pantalla==================

func _build() -> void:
	add_child(_build_the_toolbar())
	_options_bar.custom_minimum_size.y = scaled(34)
	var options_panel := PanelContainer.new()
	options_panel.add_child(_options_bar)
	add_child(options_panel)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_body.add_child(_build_the_palette())
	var right := HSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(right)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(scaled(320), scaled(240))
	var view_holder := Control.new()
	view_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view_holder.clip_contents = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_holder.add_child(view)
	_no_level.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_holder.add_child(_build_the_no_level_panel())
	right.add_child(view_holder)
	_tabs.custom_minimum_size.x = scaled(360)
	# El ancho es el de la pestaña más ancha, siempre: cambiar de pestaña no corre la vista.
	_tabs.use_hidden_tabs_for_min_size = true
	right.add_child(_tabs)
	_properties = LevelEditorPropertiesPanel.new(self)
	_groups = LevelEditorGroupsPanel.new(self)
	_level = LevelEditorLevelPanel.new(self)
	_problems = LevelEditorProblemsPanel.new(self)
	_problems.count_changed.connect(func(count: int) -> void: _tabs.set_tab_title(3, "Problems (%d)" % count if count > 0 else "Problems"))
	for panel: Control in [_properties, _groups, _level, _problems]:
		var scroll := ScrollContainer.new()
		scroll.name = panel.name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(panel)
		_tabs.add_child(scroll)
	var status_bar := HBoxContainer.new()
	# Lo que no entra termina en "…", y el texto entero queda en el tooltip.
	for label: Label in [_status, _hint]:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	_hint.size_flags_stretch_ratio = 1.5
	_hint.modulate = Color(1, 1, 1, 0.6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_bar.add_child(_status)
	status_bar.add_child(_hint)
	add_child(status_bar)
	_build_the_new_level_dialog()
	_build_the_help()
	view.camera_changed.connect(_on_camera_changed)


func _build_the_toolbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	_button(bar, "New level…", "Make a new level from the template.", ask_for_a_new_level)
	_open_menu.text = "Open level"
	_open_menu.flat = false
	_open_menu.tooltip_text = "Open one of the levels in %s." % levels_folder
	_open_menu.about_to_popup.connect(_fill_the_open_menu)
	_open_menu.get_popup().index_pressed.connect(func(index: int) -> void: open_requested.emit(_open_menu.get_popup().get_item_metadata(index)))
	bar.add_child(_open_menu)
	bar.add_child(_file_label)
	bar.add_child(VSeparator.new())
	_button(bar, "Game view", "Put the camera exactly where the game's camera would be.", _on_game_view)
	_2d_button.text = "2D"
	_2d_button.toggle_mode = true
	_2d_button.tooltip_text = "Switch between the game's 3D and 2D views (Tab)."
	_2d_button.focus_mode = Control.FOCUS_NONE
	_2d_button.toggled.connect(func(_on: bool) -> void: toggle_2d())
	bar.add_child(_2d_button)
	_perspective_button.text = "Perspective"
	_perspective_button.toggle_mode = true
	_perspective_button.tooltip_text = "Free view with perspective instead of orthographic, like the game."
	_perspective_button.focus_mode = Control.FOCUS_NONE
	_perspective_button.toggled.connect(func(_on: bool) -> void: view.toggle_perspective_projection())
	bar.add_child(_perspective_button)
	_button(bar, "", "Turn the view 90° (Q).", view.turn_90.bind(false)).icon = LevelEditorIcons.get_icon("TurnLeft", icon_scale)
	_button(bar, "", "Turn the view 90° the other way (E).", view.turn_90.bind(true)).icon = LevelEditorIcons.get_icon("TurnRight", icon_scale)
	bar.add_child(VSeparator.new())
	_layer_label.text = "Faces"
	_layer_label.custom_minimum_size.x = scaled(56)
	_layer_label.tooltip_text = "Faces: a new box goes against the face you point at. Layer n: on layer n, with everything above hidden."
	_layer_label.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.add_child(_layer_label)
	_button(bar, "−", "Layer down (−). The first press enters layer mode.", change_layer.bind(-1))
	_button(bar, "+", "Layer up (+). The first press enters layer mode.", change_layer.bind(1))
	_leave_layer_button = _button(bar, "Back to faces", "Leave layer mode (Esc).", leave_layer_mode)
	_leave_layer_button.visible = false
	bar.add_child(VSeparator.new())
	_overlay_toggle(bar, "Power", show_power, "Lines between connected pieces, by the rules of the current view. Hover a piece to light up everything it connects to.", _set_overlay.bind(&"show_power"))
	_overlay_toggle(bar, "Beams", show_beams, "Where each laser emitter's beam goes, with every door open.", _set_overlay.bind(&"show_beams"))
	_overlay_toggle(bar, "Heights", show_heights, "In 2D, each column's top height.", _set_overlay.bind(&"show_heights"))
	_button(bar, "?", "Keys and mouse.", show_the_help)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var play := _button(bar, "▶ Play", "Save and play this level (like F6).", request_play)
	play.add_theme_color_override(&"font_color", Color(0.55, 0.9, 0.55))
	return bar


func scaled(pixels: float) -> float:
	return pixels * icon_scale


func show_the_help() -> void:
	_help.popup_centered(Vector2i(int(scaled(680)), int(scaled(600))))


func _set_overlay(on: bool, overlay: StringName) -> void:
	set(overlay, on)
	rebuild_overlays()
	redraw()


static func _button(bar: Control, text: String, tooltip: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	bar.add_child(button)
	return button


func _overlay_toggle(bar: Control, text: String, on: bool, tooltip: String, toggled: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = on
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(toggled)
	bar.add_child(button)


func _build_the_palette() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = scaled(168)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_section(column, "Build")
	for kind in BoxBrush.PALETTE:
		_palette_button(column, box_tools[kind], "%d" % (BoxBrush.PALETTE.find(kind) + 1))
	_section(column, "Power")
	_palette_button(column, tools[BoxBrush.PALETTE.size()], "W")
	for type: StringName in piece_tools:
		_palette_button(column, piece_tools[type], "")
	_section(column, "Edit")
	for each in tools:
		if each is SelectTool or each is PickTool or each is RepaintTool or each is EraserTool or each is HandlesTool or each is SpawnTool:
			var key := "V" if each is SelectTool else ("H" if each is HandlesTool else "")
			_palette_button(column, each, key)
	return scroll


func _section(column: VBoxContainer, text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.modulate = Color(1, 1, 1, 0.55)
	column.add_child(heading)


func _palette_button(column: VBoxContainer, palette_tool: LevelEditorTool, key: String) -> void:
	var button := Button.new()
	button.text = palette_tool.title
	button.icon = LevelEditorIcons.get_icon(palette_tool.title, icon_scale)
	button.toggle_mode = true
	button.button_group = _palette_group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = palette_tool.tooltip + ("\nKey: %s" % key if not key.is_empty() else "")
	button.focus_mode = Control.FOCUS_NONE
	# Los íconos son los colores de las cosas: el tema del editor no los tiñe. El elegido se ve por el texto.
	for state: StringName in [&"icon_pressed_color", &"icon_hover_pressed_color", &"icon_hover_color", &"icon_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	for state: StringName in [&"font_pressed_color", &"font_hover_pressed_color"]:
		button.add_theme_color_override(state, CHOSEN_TOOL_COLOR)
	button.pressed.connect(use_tool.bind(palette_tool))
	column.add_child(button)
	_palette_buttons[palette_tool] = button


func _build_the_no_level_panel() -> Control:
	var panel := PanelContainer.new()
	_no_level.add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(scaled(360), 0)
	panel.add_child(column)
	var message := Label.new()
	message.text = "This scene isn't a level.\nA level has the level script on its root and a Room."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(message)
	_button(column, "New level…", "Make a new level from the template.", ask_for_a_new_level)
	var open := Label.new()
	open.text = "Or open one (double-click):"
	column.add_child(open)
	_no_level_list.custom_minimum_size.y = scaled(180)
	_no_level_list.item_activated.connect(func(index: int) -> void: open_requested.emit(_no_level_list.get_item_metadata(index)))
	column.add_child(_no_level_list)
	return _no_level


func _build_the_new_level_dialog() -> void:
	_new_level_dialog.title = "New level"
	_new_level_dialog.ok_button_text = "Create"
	var column := VBoxContainer.new()
	_new_level_dialog.add_child(column)
	var name_row := HBoxContainer.new()
	column.add_child(name_row)
	LevelEditorTool.caption(name_row, "File name")
	_new_level_name.placeholder_text = "level_04"
	_new_level_name.custom_minimum_size.x = scaled(220)
	_new_level_name.text_changed.connect(func(_text: String) -> void: _check_the_new_level())
	name_row.add_child(_new_level_name)
	var size_row := HBoxContainer.new()
	column.add_child(size_row)
	LevelEditorTool.caption(size_row, "Room size")
	for axis in 3:
		var field := SpinBox.new()
		field.min_value = 1
		field.max_value = 40
		field.value = [12, 9, 3][axis]
		field.prefix = ["X", "Y", "Z"][axis]
		size_row.add_child(field)
		_new_level_size.append(field)
	_new_level_error.modulate = Color(1, 0.55, 0.5)
	column.add_child(_new_level_error)
	_new_level_dialog.confirmed.connect(_create_the_new_level)
	# Enter en el nombre crea, como el botón (y como él, no hace nada si el nombre no sirve).
	_new_level_dialog.register_text_enter(_new_level_name)
	add_child(_new_level_dialog)


func _build_the_help() -> void:
	_help.title = "Level tab: keys and mouse"
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(scaled(640), scaled(520))
	text.text = HELP_TEXT
	_help.add_child(text)
	add_child(_help)


const HELP_TEXT := """[b]Everywhere[/b]
Left button: use the tool. Right button: erase what the tool places (Handles: turn off).
Middle drag: orbit (in 2D, pan) · Shift + middle drag: pan · Wheel: zoom toward the mouse.
Game view: the camera exactly where the game's would be · Tab: 2D or 3D · Q, E: turn 90° · F: frame the selection.
Holding Shift, Ctrl or Alt shows at once what a click would do.

[b]Box brushes (1 to 8)[/b]
Click to place against the face you point at; drag to paint (or a rectangle). One stroke makes one new group.
Shift at the start of a stroke on a box: extend that box's group · Ctrl + drag: repaint · Alt + click: pick a box's or a piece's settings.
+ and −: layer mode, where new boxes go on that layer and everything above it is hidden · Esc: back to faces.

[b]Select (V)[/b]
Click: a group (on the room shell, one box) · Double-click: one box · Ctrl + click: the piece on a face · Shift: add or take out.
Drag on empty space or on the floor: a rectangle. It leaves the room shell out.
Drag a selection to move it (+ and − lift it meanwhile) · Arrows: nudge it along the grid · Alt + + and Alt + −: up and down.
Ctrl + D: deselect · Delete or Backspace: delete · Ctrl + G: group · Ctrl + Shift + G: ungroup · F2: rename the group.
Ctrl + C, Ctrl + V: copy and paste. A ghost follows the mouse: click to place, Shift + click to place and keep pasting, Esc to stop.

[b]Power[/b]
Wire (W): drag across faces; each two faces in a row get connected both ways. Right-drag erases wires and the arms that pointed at them (Shift + right-drag keeps the arms).
Pieces: click a face. Doors and the exit go on the edge of the top nearest the mouse. A new piece connects to the neighbours already pointing at it. Click a piece to select it.

[b]Other tools[/b]
Handles (H): a side face is its 3D handle, near a top edge that 2D handle, the middle of a top the whole top · Shift: the whole group.
Pick: a box's settings into a brush · Repaint: the last brush's settings onto boxes · Eraser: the piece on a face, or else the box · Spawn: where the player starts.

[b]Panels[/b]
Groups: Ctrl or Shift + click picks several rows; the eye hides a group in this view only (nothing is saved).
Problems: everything Godot warns about in the level, with Show to find it.

[b]Godot's own[/b]
Ctrl + Z, Ctrl + Shift + Z, Ctrl + S, F5 and F6: undo, redo, save, run."""


#==================El nivel==================

## El host lo llama cuando cambia la escena editada. `root` es null si no es un nivel.
func set_level(root: Node, level_history: LevelEditorHistory) -> void:
	if history != null and history.changed.is_connected(_on_history_changed):
		history.changed.disconnect(_on_history_changed)
	if current_tool != null:
		current_tool.cancel()
	# Lo que cada herramienta tenía bajo el mouse era del nivel de antes.
	_hit = GridPicker.Hit.new()
	for each in tools:
		each.hover(_hit)
	_paste_tool.hover(_hit)
	view.unhide_everything()
	view.hidden_groups.clear()
	selected_boxes = []
	selected_pieces = []
	_selected.clear()
	_current_folder = null
	layer_mode = false
	level_root = root
	room = root.get_node(^"Room") as Room if root != null else null
	history = level_history
	edits = null
	if room != null:
		room.rebuild_index()
		edits = LevelEdits.new(root, room, history)
		edits.edit_state = edit_state
		history.changed.connect(_on_history_changed)
	_watch_the_tree(root.get_tree() if root != null and root.is_inside_tree() else null)
	view.set_room(room)
	_no_level.visible = room == null
	view.visible = room != null
	_fill_the_level_list()
	_file_label.text = _file_name()
	if room != null:
		view.reset_camera()
		if current_tool == null:
			use_tool(box_tools[BoxBrush.Kind.FLOOR])
		_refresh_everything()
	else:
		for panel: Control in [_properties, _groups, _level, _problems]:
			panel.call(&"refresh")
		view.preview.clear()
		view.overlay_3d.clear()
	_update_the_layer_label()


func _file_name() -> String:
	if level_root == null:
		return ""
	if level_root.scene_file_path.is_empty():
		return "  %s (not saved)" % level_root.name
	return "  " + level_root.scene_file_path.get_file()


static func is_a_level(root: Node) -> bool:
	return root is Level and root.get_node_or_null(^"Room") is Room


func _watch_the_tree(tree: SceneTree) -> void:
	if _watched_tree != null and is_instance_valid(_watched_tree):
		if _watched_tree.node_added.is_connected(_on_a_node_came_or_went):
			_watched_tree.node_added.disconnect(_on_a_node_came_or_went)
			_watched_tree.node_removed.disconnect(_on_a_node_came_or_went)
	_watched_tree = tree
	if tree != null:
		tree.node_added.connect(_on_a_node_came_or_went)
		tree.node_removed.connect(_on_a_node_came_or_went)


## Una caja o un powerable que entra o sale del nivel por fuera de la historia (Fill, Clear) también
## cambia el índice.
func _on_a_node_came_or_went(node: Node) -> void:
	if room == null or not is_instance_valid(room) or _refresh_pending:
		return
	if (node is Box or node is Powerable or node is Structure) and room.is_ancestor_of(node):
		_on_history_changed()


func _on_history_changed() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	_refresh_everything.call_deferred()


func _refresh_everything() -> void:
	_refresh_pending = false
	if room == null or not is_instance_valid(room):
		return
	room.rebuild_index()
	forget_freed_selection(false, false)
	view.refresh_bounds()
	view.apply_hiding()
	view.repick()
	refresh_panels()
	rebuild_overlays()
	_file_label.text = _file_name()
	redraw()


func refresh_panels() -> void:
	if room == null:
		return
	_properties.refresh()
	_groups.refresh()
	_level.refresh()
	_problems.refresh()


func _fill_the_level_list() -> void:
	_no_level_list.clear()
	for path in level_paths():
		_no_level_list.add_item(path.get_file())
		_no_level_list.set_item_metadata(_no_level_list.item_count - 1, path)


func level_paths() -> Array[String]:
	var paths: Array[String] = []
	var folder := DirAccess.open(levels_folder)
	if folder == null:
		return paths
	for file in folder.get_files():
		if file.ends_with(".tscn"):
			paths.append(levels_folder.path_join(file))
	paths.sort()
	return paths


func _fill_the_open_menu() -> void:
	var popup := _open_menu.get_popup()
	popup.clear()
	for path in level_paths():
		popup.add_item(path.get_file())
		popup.set_item_metadata(popup.item_count - 1, path)


## Una lista de los niveles, más "Restart this level", para a dónde lleva una salida.
func level_picker(current: String, on_picked: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	picker.fit_to_longest_item = false
	picker.custom_minimum_size.x = scaled(150)
	picker.add_item("Restart this level")
	picker.set_item_metadata(0, "")
	for path in level_paths():
		picker.add_item(path.get_file().get_basename())
		picker.set_item_metadata(picker.item_count - 1, path)
		if path == current:
			picker.selected = picker.item_count - 1
	if not current.is_empty() and picker.selected <= 0 and not level_paths().has(current):
		picker.add_item(current.get_file().get_basename() + " (missing)")
		picker.set_item_metadata(picker.item_count - 1, current)
		picker.selected = picker.item_count - 1
	picker.item_selected.connect(func(index: int) -> void: on_picked.call(picker.get_item_metadata(index)))
	return picker


func ask_for_a_new_level() -> void:
	_new_level_name.text = ""
	_check_the_new_level()
	_new_level_dialog.popup_centered(Vector2i(int(scaled(460)), int(scaled(160))))
	_new_level_name.grab_focus()


func _new_level_path() -> String:
	return levels_folder.path_join(_new_level_name.text.strip_edges() + ".tscn")


func _check_the_new_level() -> void:
	var file_name := _new_level_name.text.strip_edges()
	var problem := ""
	if file_name.is_empty():
		problem = "Give it a file name."
	elif not file_name.is_valid_filename() or file_name.contains(" ") or file_name.contains("."):
		problem = "Use letters, numbers and underscores."
	elif FileAccess.file_exists(_new_level_path()):
		problem = "There is already a level with that name."
	_new_level_error.text = problem
	_new_level_dialog.get_ok_button().disabled = not problem.is_empty()


func _create_the_new_level() -> void:
	_check_the_new_level()
	if not _new_level_error.text.is_empty():
		return
	new_level_requested.emit(_new_level_path(), Vector3i(int(_new_level_size[0].value), int(_new_level_size[1].value), int(_new_level_size[2].value)))


func request_play() -> void:
	play_requested.emit()


func exits() -> Array[ExitDoor]:
	var found: Array[ExitDoor] = []
	if room == null:
		return found
	for piece in room.index.every_powerable():
		if piece is ExitDoor:
			found.append(piece)
	return found


func starting_perspective() -> Room.Perspective:
	if room == null or room.perspective_manager == null:
		return Room.Perspective.ISO_3D
	return room.perspective_manager.starting_perspective


func perspective() -> Room.Perspective:
	return Room.Perspective.TOP_2D if view.is_2d else Room.Perspective.ISO_3D


#==================Herramientas==================

## Al elegir una herramienta sus opciones vuelven a como empiezan (dev), salvo al volver de pegar.
func use_tool(new_tool: LevelEditorTool, reset := true) -> void:
	if current_tool != null:
		current_tool.deactivate()
	# Un aviso era sobre lo de antes: con otra herramienta se ve lo suyo.
	_flash_until = 0
	current_tool = new_tool
	if new_tool is BoxBrushTool:
		_last_box_tool = new_tool
	if reset:
		new_tool.reset_options()
	new_tool.activate()
	# Lo que la herramienta vio la última vez que se usó puede ya no existir: mira lo de ahora.
	if room != null:
		view.repick()
	_show_the_options()
	# Sin señal, el ButtonGroup no suelta a los demás: se sueltan acá.
	for each_tool: LevelEditorTool in _palette_buttons:
		_palette_buttons[each_tool].set_pressed_no_signal(each_tool == new_tool)
	redraw()


func use_tool_named(tool_title: String) -> void:
	for each in tools:
		if each.title == tool_title:
			use_tool(each)
			return


func _show_the_options() -> void:
	for child in _options_bar.get_children():
		_options_bar.remove_child(child)
		child.queue_free()
	if current_tool != null:
		current_tool.build_options(_options_bar)


func last_brush() -> BoxBrush:
	return _last_box_tool.brush


## El cuentagotas: las banderas de una caja a la brocha de su tipo, o las opciones de un powerable a
## su herramienta.
func pick_from(hit: GridPicker.Hit) -> void:
	if not hit.has_box:
		return
	var piece := hit.box.powerable_on(hit.face)
	if piece != null:
		var type := LevelEdits.piece_type(piece)
		if type == &"Wire":
			use_tool(tools[BoxBrush.PALETTE.size()])
			return
		var piece_tool := piece_tools[type]
		use_tool(piece_tool)
		piece_tool.use_options(LevelEdits.properties_of(piece))
		_show_the_options()
		return
	var picked := BoxBrush.picked_from(hit.box)
	var brush_tool := box_tools.get(BoxBrush.kind_of(hit.box), box_tools[BoxBrush.Kind.BLOCK]) as BoxBrushTool
	use_tool(brush_tool)
	brush_tool.use_brush(picked)
	_show_the_options()


func add_piece_from_properties(box: Box, face: Powerable.Face, type: StringName) -> void:
	var placed := edits.place_piece(type, box, face, piece_tools[type].options if piece_tools.has(type) else {})
	if placed != null:
		select([], [placed])


func erase_piece(piece: Powerable) -> void:
	edits.erase([], [piece])
	forget_freed_selection()


#==================El mouse y las teclas==================

func plane_for_picking() -> int:
	if layer_mode:
		return layer
	if current_tool != null:
		return current_tool.plane_z()
	return 0


func on_hover(hit: GridPicker.Hit) -> void:
	_hit = hit
	if current_tool != null:
		current_tool.hover(hit)
	redraw()


func on_press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	_hit = hit
	if current_tool != null:
		current_tool.hover(hit)
		current_tool.press(hit, event)
	redraw()


func on_drag(hit: GridPicker.Hit, event: InputEventMouseMotion) -> void:
	if current_tool != null:
		current_tool.drag(hit, event)
	redraw()


func on_release(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if current_tool != null:
		current_tool.release(hit, event)
	redraw()


static func is_plus(event: InputEventKey) -> bool:
	return event.keycode in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD] or event.unicode == 43


static func is_minus(event: InputEventKey) -> bool:
	return event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT] or event.unicode == 45


## Las teclas de la vista. Devuelve si la usó; las que no (Ctrl + Z, Ctrl + S, F5, F6) siguen hacia
## Godot.
func on_key(event: InputEventKey) -> bool:
	if room == null:
		return false
	if event.echo and not REPEATING_KEYS.has(event.keycode) and not is_plus(event) and not is_minus(event):
		var ctrl_held := event.ctrl_pressed or event.meta_pressed
		return not (ctrl_held and event.keycode in [KEY_Z, KEY_Y, KEY_S])
	if current_tool != null and current_tool.key(event):
		return true
	var ctrl := event.ctrl_pressed or event.meta_pressed
	if ctrl and event.keycode == KEY_Z:
		return false
	if is_plus(event) or is_minus(event):
		if event.alt_pressed:
			nudge(Vector3i(0, 0, 1 if is_plus(event) else -1))
		else:
			change_layer(1 if is_plus(event) else -1)
		return true
	match event.keycode:
		KEY_TAB:
			toggle_2d()
		KEY_Q:
			view.turn_90(false)
		KEY_E:
			view.turn_90(true)
		KEY_F:
			frame_selection()
		KEY_ESCAPE:
			if current_tool != null and current_tool.cancel():
				pass
			elif layer_mode:
				leave_layer_mode()
		KEY_D:
			if not ctrl:
				return false
			clear_selection()
		KEY_C:
			if not ctrl:
				return false
			copy_selection()
		KEY_V:
			if ctrl:
				start_pasting()
			else:
				use_tool_named("Select")
		KEY_G:
			if not ctrl:
				return false
			if event.shift_pressed:
				ungroup_selection()
			else:
				group_selection()
		KEY_DELETE, KEY_BACKSPACE:
			delete_selection()
		KEY_F2:
			rename_the_selected_group()
		KEY_H:
			use_tool_named("Handles")
		KEY_W:
			use_tool(tools[BoxBrush.PALETTE.size()])
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			var on_screen := {KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT}
			nudge(view.grid_direction_for_screen(on_screen[event.keycode]))
		_:
			var kind_key := KIND_KEYS.find(event.keycode)
			if kind_key < 0 or ctrl:
				return false
			use_tool(box_tools[BoxBrush.PALETTE[kind_key]])
	redraw()
	return true


func toggle_2d() -> void:
	if room == null:
		return
	view.toggle_2d()
	_2d_button.set_pressed_no_signal(view.is_2d)
	rebuild_overlays()
	redraw()


func _on_game_view() -> void:
	view.game_view()
	_perspective_button.set_pressed_no_signal(false)


func _on_camera_changed() -> void:
	_perspective_button.set_pressed_no_signal(view.is_perspective)


func change_layer(by: int) -> void:
	if room == null:
		return
	if not layer_mode:
		layer_mode = true
		layer = _last_layer
	else:
		layer = clampi(layer + by, -1, room.maximum_reach().z)
	_last_layer = layer
	view.apply_hiding()
	_update_the_layer_label()
	redraw()


func leave_layer_mode() -> void:
	layer_mode = false
	view.apply_hiding()
	_update_the_layer_label()
	redraw()


func _update_the_layer_label() -> void:
	_layer_label.text = "Layer %d" % layer if layer_mode else "Faces"
	if _leave_layer_button != null:
		_leave_layer_button.visible = layer_mode


func frame_selection() -> void:
	var cells: Array[Vector3i] = []
	for box in selected_boxes:
		cells.append(room.index.cell_of(box))
	for piece in selected_pieces:
		cells.append(room.index.cell_of(piece.box))
	if cells.is_empty():
		view.game_view()
	else:
		view.frame_cells(cells)


#==================La selección==================

func select(boxes: Array[Box], pieces: Array[Powerable]) -> void:
	selected_boxes = boxes.duplicate()
	selected_pieces = pieces.duplicate()
	_remember_the_selection()


func add_to_selection(boxes: Array[Box]) -> void:
	for box in boxes:
		if not _selected.has(box):
			selected_boxes.append(box)
	selected_pieces = []
	_remember_the_selection()


func remove_from_selection(boxes: Array[Box]) -> void:
	var removing: Dictionary[Box, bool] = {}
	for box in boxes:
		removing[box] = true
	var kept: Array[Box] = []
	for box in selected_boxes:
		if not removing.has(box):
			kept.append(box)
	selected_boxes = kept
	_remember_the_selection()


func clear_selection() -> void:
	select([], [])


## Si la caja está en el nivel tal como lo ve el índice (no borrada, ni guardada para deshacer).
func is_in_the_level(box: Box) -> bool:
	return box.is_inside_tree() and room.index.cells_3D.get(box.world_cell) == box


func is_selected(box: Box) -> bool:
	return _selected.has(box)


## Saca de la selección lo que se borró (o se deshizo).
func forget_freed_selection(announce := true, refresh_the_panels := true) -> void:
	var boxes: Array[Box] = []
	for box in selected_boxes:
		if is_instance_valid(box) and box.is_inside_tree() and is_in_the_level(box):
			boxes.append(box)
	var pieces: Array[Powerable] = []
	for piece in selected_pieces:
		if is_instance_valid(piece) and piece.is_inside_tree() and piece.box != null:
			pieces.append(piece)
	var changed := boxes.size() != selected_boxes.size() or pieces.size() != selected_pieces.size()
	selected_boxes = boxes
	selected_pieces = pieces
	if changed or announce:
		_remember_the_selection(announce, refresh_the_panels)


func _remember_the_selection(announce := true, refresh_the_panels := true) -> void:
	_selected.clear()
	for box in selected_boxes:
		_selected[box] = true
	if refresh_the_panels and not _refresh_pending and room != null:
		_properties.refresh()
		_groups.show_the_selection()
	if announce:
		selection_changed.emit()
	redraw()


## Lo que el dock de escena eligió, traído a la selección de acá.
func select_from_editor(nodes: Array[Node]) -> void:
	if room == null:
		return
	var boxes: Array[Box] = []
	var pieces: Array[Powerable] = []
	for node in nodes:
		if not is_instance_valid(node) or not room.is_ancestor_of(node):
			continue
		if node is Box:
			boxes.append(node)
		elif node is Structure:
			boxes.append_array((node as Structure).boxes())
		elif node is Powerable:
			pieces.append(node)
	if boxes.is_empty() and pieces.is_empty():
		return
	selected_boxes = boxes
	selected_pieces = pieces
	_remember_the_selection(false)


## Los nodos que la selección le muestra al editor: las cajas elegidas, o sus grupos si son muchas.
func selection_for_the_editor() -> Array[Node]:
	var nodes: Array[Node] = []
	if not selected_pieces.is_empty():
		nodes.assign(selected_pieces)
		return nodes
	if selection_is_whole_groups():
		for group in groups_of(selected_boxes):
			nodes.append(group)
	else:
		nodes.assign(selected_boxes.slice(0, 50))
	return nodes


## Los grupos de esas cajas: sus Structures, o la caja misma si está suelta.
func groups_of(boxes: Array[Box]) -> Array[Node]:
	var found: Array[Node] = []
	for box in boxes:
		var group: Node = box.get_parent() if box.get_parent() is Structure else box
		if not found.has(group):
			found.append(group)
	return found


## Si lo elegido son grupos enteros (no la cáscara).
func selection_is_whole_groups() -> bool:
	if selected_boxes.is_empty():
		return false
	for group in groups_of(selected_boxes):
		if group is Structure:
			if edits.is_shell_part(group):
				return false
			for box in (group as Structure).boxes():
				if not _selected.has(box):
					return false
	return true


func current_folder() -> Node:
	if _current_folder != null and is_instance_valid(_current_folder) and room != null and room.is_ancestor_of(_current_folder):
		return _current_folder
	return null


func set_current_folder(folder: Node) -> void:
	_current_folder = folder
	_groups.refresh()
	redraw()


func show_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is Box:
		select([node as Box], [])
	elif node is Structure:
		select((node as Structure).boxes(), [])
	elif node is Powerable:
		select([], [node as Powerable])
	frame_selection()


func go_to_piece(piece: Powerable) -> void:
	show_node(piece)


#==================Lo que se hace con la selección==================

func nudge(step: Vector3i) -> void:
	if selected_boxes.is_empty():
		return
	if not edits.move(selected_boxes, step, true, "Nudge"):
		flash("Can't move there: something is in the way, or the shell's boxes are selected.", true)


func delete_selection() -> void:
	if selected_boxes.is_empty() and selected_pieces.is_empty():
		return
	edits.erase(selected_boxes, selected_pieces)
	forget_freed_selection()


func group_selection() -> void:
	if selected_boxes.is_empty():
		return
	if LevelEdits.mixes_terrain(selected_boxes):
		flash("A group is either all terrain or holds none: these can't be one group.", true)
		return
	var new_group := edits.group(selected_boxes)
	if new_group != null:
		_select_the_group.call_deferred(new_group)
	else:
		flash("The shell's boxes can't be grouped.", true)


func _select_the_group(group: Structure) -> void:
	if is_instance_valid(group):
		select(group.boxes(), [])


func ungroup_selection() -> void:
	var groups: Array[Structure] = []
	for group in groups_of(selected_boxes):
		if group is Structure:
			groups.append(group)
	edits.ungroup(groups)


func rename_the_selected_group() -> void:
	_tabs.current_tab = 0
	if group_name_field != null and is_instance_valid(group_name_field):
		group_name_field.grab_focus()
		group_name_field.select_all()


func copy_selection() -> void:
	if selected_boxes.is_empty():
		flash("Select something to copy first.", true)
		return
	clipboard = edits.copy(selected_boxes)
	flash("Copied %d box%s. Ctrl + V to paste." % [selected_boxes.size(), "" if selected_boxes.size() == 1 else "es"])


func start_pasting() -> void:
	if clipboard == null or clipboard.is_empty():
		flash("Nothing copied yet: select something and press Ctrl + C.", true)
		return
	if current_tool != _paste_tool:
		_tool_before_pasting = current_tool
	_paste_tool.clip = clipboard
	_flash_until = 0
	if current_tool != null:
		current_tool.deactivate()
	current_tool = _paste_tool
	_show_the_options()
	redraw()


## Cambia el tamaño del cuarto y avisa si quedan cajas afuera: el marco no las toca, pero en el juego
## quedan fuera del cuarto.
func resize_room(dimensions: Vector3i) -> void:
	if room == null:
		return
	edits.set_room_size(dimensions)
	var outside := 0
	for box: Box in room.index.cells_3D.values():
		var cell := box.world_cell
		var inside := cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < dimensions.x and cell.y < dimensions.y and cell.z < dimensions.z
		if not inside and not edits.is_shell_part(box.get_parent()):
			outside += 1
	if outside > 0:
		flash("%d box%s now stand%s outside the room." % [outside, "" if outside == 1 else "es", "s" if outside == 1 else ""], true)


func stop_pasting() -> void:
	use_tool(_tool_before_pasting if _tool_before_pasting != null else tools[0], false)


func repaint_selection(brush: BoxBrush) -> void:
	repaint_boxes(selected_boxes, brush)


## Repinta esas cajas con la brocha, salvo las que no puede (boxes_a_repaint_can_take), y avisa cuántas
## quedaron afuera. Lo usan Repaint, Ctrl + trazo y los botones de tipo de Properties.
func repaint_boxes(boxes: Array[Box], brush: BoxBrush) -> void:
	var allowed := boxes_a_repaint_can_take(boxes, brush)
	var skipped := boxes.size() - allowed.size()
	if skipped > 0:
		flash("%d box%s skipped: a group is either all terrain or holds none, and the room shell is terrain." % [skipped, "" if skipped == 1 else "es"], true)
	edits.repaint(allowed, brush)


## Un grupo es todo terreno o nada de terreno: una caja sólo cambia de lado si su grupo entero va con
## ella. La cáscara es terreno siempre: sólo Floor o Wall la repintan.
func boxes_a_repaint_can_take(boxes: Array[Box], brush: BoxBrush) -> Array[Box]:
	var repainting: Dictionary[Box, bool] = {}
	for box in boxes:
		repainting[box] = true
	var allowed: Array[Box] = []
	for box in boxes:
		if not edits.is_in_the_level(box):
			continue
		var group := box.get_parent() as Structure
		if group != null and edits.is_shell_part(group):
			if brush.is_terrain():
				allowed.append(box)
			continue
		var whole_group := group == null or group.boxes().all(func(each: Box) -> bool: return repainting.has(each))
		if whole_group or not LevelEdits.would_mix_terrain(group, brush.is_terrain()):
			allowed.append(box)
	return allowed


## Si prender o apagar is_floor o is_wall en esas cajas dejaría un grupo mezclando terreno.
func would_split_terrain(boxes: Array[Box], flag: StringName, on: bool) -> bool:
	var changing: Dictionary[Box, bool] = {}
	for box in boxes:
		changing[box] = true
	for group in groups_of(boxes):
		if not group is Structure:
			continue
		var terrain := 0
		var all_boxes := (group as Structure).boxes()
		for box in all_boxes:
			var floor_after: bool = on if changing.has(box) and flag == &"is_floor" else box.is_floor
			var wall_after: bool = on if changing.has(box) and flag == &"is_wall" else box.is_wall
			if floor_after or wall_after:
				terrain += 1
		if terrain > 0 and terrain < all_boxes.size():
			return true
	return false


func _the_selected_group() -> Structure:
	var groups := groups_of(selected_boxes)
	if groups.size() == 1 and groups[0] is Structure:
		return groups[0]
	return null


func mark_exposed_tops_walkable() -> void:
	var group := _the_selected_group()
	if group == null:
		return
	var cells: Dictionary[Vector3i, bool] = {}
	for box in group.boxes():
		cells[box.world_cell] = true
	var changes: Dictionary[Box, Dictionary] = {}
	for box in group.boxes():
		changes[box] = {&"walkable": not cells.has(box.world_cell + LevelIndex.GRID_UP)}
	edits.set_flags_per_box(changes, "Mark exposed tops walkable")


func make_unwalkable() -> void:
	var group := _the_selected_group()
	if group == null:
		return
	edits.set_box_flags(group.boxes(), {&"walkable": false}, "Make unwalkable")


func grab_every_outer_side() -> void:
	_grab_the_outside(true)


func grab_every_outer_edge() -> void:
	_grab_the_outside(false)


func _grab_the_outside(sides_in_3d: bool) -> void:
	var group := _the_selected_group()
	if group == null:
		return
	var cells: Dictionary[Vector3i, bool] = {}
	for box in group.boxes():
		cells[box.world_cell] = true
	var changes: Dictionary[Box, Dictionary] = {}
	for box in group.boxes():
		if box.is_terrain():
			continue
		if not sides_in_3d and cells.has(box.world_cell + LevelIndex.GRID_UP):
			continue
		var box_changes := {}
		for facing: Box.Facing in Box.FACING_DIRECTION:
			var direction := Box.FACING_DIRECTION[facing]
			if not cells.has(box.world_cell + Vector3i(direction.x, direction.y, 0)):
				box_changes[BoxBrush.SIDE_FLAG_3D[facing] if sides_in_3d else BoxBrush.EDGE_FLAG_2D[facing]] = true
		if not box_changes.is_empty():
			changes[box] = box_changes
	edits.set_flags_per_box(changes, "Grab every outer side" if sides_in_3d else "Grab every outer edge")


#==================Lo que se ve==================

## Se dibuja una vez por cuadro aunque se pida muchas.
func redraw() -> void:
	if _redraw_pending:
		return
	_redraw_pending = true
	_redraw_now.call_deferred()


func _redraw_now() -> void:
	_redraw_pending = false
	if room == null or not is_instance_valid(room):
		view.preview.clear()
		return
	if _hit.has_box and (not is_instance_valid(_hit.box) or room.index.cells_3D.get(_hit.cell) != _hit.box):
		view.repick()
	var preview := view.preview
	preview.begin()
	_draw_the_selection(preview)
	if layer_mode:
		_draw_the_layer(preview)
	if show_power:
		_draw_the_network_under_the_mouse(preview)
	if current_tool != null:
		current_tool.draw(preview)
	preview.finish()
	_update_the_status()


func _draw_the_selection(preview: LevelEditorPreview) -> void:
	var outline := Color(1.0, 0.85, 0.3, 0.95)
	for box in selected_boxes:
		if is_instance_valid(box) and is_in_the_level(box):
			preview.outline_cell(room.index.cell_of(box), outline, 0.03)
	for piece in selected_pieces:
		if is_instance_valid(piece) and piece.box != null:
			preview.highlight_face(room.index.cell_of(piece.box), piece.face, Color(1.0, 0.85, 0.3, 0.45))
			preview.outline_face(room.index.cell_of(piece.box), piece.face, outline)


func _draw_the_layer(preview: LevelEditorPreview) -> void:
	var size := room.dimensions
	var colour := Color(0.4, 0.7, 1.0, 0.35)
	for x in range(-1, size.x + 1):
		preview.line(Vector3(x, -1, layer), Vector3(x, size.y, layer), colour)
	for y in range(-1, size.y + 1):
		preview.line(Vector3(-1, y, layer), Vector3(size.x, y, layer), colour)


func _draw_the_network_under_the_mouse(preview: LevelEditorPreview) -> void:
	if not _hit.has_box:
		return
	var piece := _hit.box.powerable_on(_hit.face)
	if piece == null:
		return
	var network: Dictionary[Powerable, bool] = {piece: true}
	var to_visit: Array[Powerable] = [piece]
	while not to_visit.is_empty():
		var current: Powerable = to_visit.pop_back()
		for neighbour in room.index.connected_powerables(current, perspective()):
			if not network.has(neighbour):
				network[neighbour] = true
				to_visit.append(neighbour)
	for member: Powerable in network:
		preview.highlight_face(room.index.cell_of(member.box), member.face, Color(1.0, 0.3, 0.2, 0.4))


## Un aviso corto que se ve un momento en la barra de estado.
func flash(text: String, is_a_refusal := false) -> void:
	_flash_text = text
	_flash_is_a_refusal = is_a_refusal
	_flash_until = Time.get_ticks_msec() + FLASH_MILLISECONDS
	_update_the_status()
	if is_inside_tree():
		get_tree().create_timer(FLASH_MILLISECONDS / 1000.0 + 0.05).timeout.connect(_update_the_status)


func _update_the_status() -> void:
	if current_tool == null:
		return
	var text := current_tool.status()
	var refusal := current_tool.refusal
	# Un aviso responde a lo que se acaba de hacer: mientras dura, va antes que lo de bajo el mouse.
	if Time.get_ticks_msec() < _flash_until and not _flash_text.is_empty():
		_status.text = _flash_text
		_status.modulate = Color(1, 0.55, 0.5) if _flash_is_a_refusal else Color(0.6, 1.0, 0.65)
	elif not refusal.is_empty():
		_status.text = refusal
		_status.modulate = Color(1, 0.55, 0.5)
	else:
		_status.text = text if not text.is_empty() else _describe_the_hover()
		_status.modulate = Color.WHITE
	var folder := current_folder()
	_hint.text = current_tool.hint() + ("   ·   new groups go to %s" % folder.name if folder != null else "")
	_hint.tooltip_text = _hint.text
	_status.tooltip_text = _status.text


func _describe_the_hover() -> String:
	if not _hit.has_box or not is_instance_valid(_hit.box):
		return ""
	var group := _hit.box.get_parent()
	var where := LevelEditorTool.describe(_hit.cell)
	return "%s · %s" % [group.name if group is Structure else "loose box", where]


## Lo que se ve siempre: las puertas aunque estén abiertas, el jugador, y lo que se pidió en la barra.
func rebuild_overlays() -> void:
	var overlay := view.overlay_3d
	overlay.begin()
	if room == null or not is_instance_valid(room):
		overlay.finish()
		return
	draw_player_marker(overlay, room.player_spawn_point, Color(0.25, 0.55, 0.95, 0.55))
	for piece in room.index.every_powerable():
		if piece is Door:
			_outline_the_door(overlay, piece as Door)
	if show_power:
		_draw_the_connections(overlay)
	if show_beams:
		_draw_the_beams(overlay)
	if show_heights and view.is_2d:
		# La cáscara es lo de siempre (el piso abajo, las paredes del alto del cuarto): sólo se marca lo demás.
		for column: Vector2i in room.index.grid_2D:
			var top_box: Box = room.index.grid_2D[column]
			var top := room.index.cell_of(top_box)
			if top.z >= 0 and not edits.is_shell_part(top_box.get_parent()):
				overlay.label(Vector3(column.x + 0.5, column.y + 0.5, top.z + 1.05), str(top.z), Color(1, 0.95, 0.6), 110)
	overlay.finish()


func draw_player_marker(preview: LevelEditorPreview, cell: Vector3i, colour: Color) -> void:
	preview.tint_volume(Vector3(cell) + Vector3(0.2, 0.2, 0.0), Vector3(0.6, 0.6, 0.9), colour)


func _outline_the_door(overlay: LevelEditorPreview, door: Door) -> void:
	var cell := room.index.cell_of(door.box) + LevelIndex.GRID_UP
	var strip := Box.strip_along(door.edge, Door.THICKNESS)
	var low := Vector3(cell.x + 0.5 + strip.position.x, cell.y + 0.5 + strip.position.y, cell.z)
	var high := Vector3(cell.x + 0.5 + strip.end.x, cell.y + 0.5 + strip.end.y, cell.z + Door.HEIGHT)
	overlay.outline_box(low, high, Color(0.3, 0.95, 0.45, 0.9) if door is ExitDoor else Color(0.85, 0.85, 0.9, 0.7))


func _draw_the_connections(overlay: LevelEditorPreview) -> void:
	var drawn: Dictionary[String, bool] = {}
	for piece in room.index.every_powerable():
		for neighbour in room.index.connected_powerables(piece, perspective()):
			var key := "%d-%d" % [mini(piece.get_instance_id(), neighbour.get_instance_id()), maxi(piece.get_instance_id(), neighbour.get_instance_id())]
			if drawn.has(key):
				continue
			drawn[key] = true
			overlay.line(_face_centre(piece), _face_centre(neighbour), Color(1.0, 0.85, 0.2, 0.9))


func _face_centre(piece: Powerable) -> Vector3:
	return Vector3(room.index.cell_of(piece.box)) + Vector3(0.5, 0.5, 0.5) + Vector3(piece.normal()) * 0.56


func _draw_the_beams(overlay: LevelEditorPreview) -> void:
	for piece in room.index.every_powerable():
		if not piece is LaserEmitter:
			continue
		var beam := room.index.beam_of(piece as LaserEmitter, perspective(), room.maximum_reach())
		var start := Vector3(beam.start.x, beam.start.y, beam.height + 0.5)
		var end := start + Vector3(beam.direction.x, beam.direction.y, 0) * beam.length
		overlay.dashed_line(start, end, Color(1.0, 0.15, 0.1, 0.9))
		if beam.hits != null:
			overlay.highlight_face(room.index.cell_of(beam.hits.box), beam.hits.face, Color(1.0, 0.2, 0.15, 0.45))


## La sombra del grupo, como la dibuja su caja: el naranja si se agarra, el gris si no.
func shade_of(node: Node) -> Color:
	var box: Box = null
	if node is Structure and not (node as Structure).boxes().is_empty():
		box = (node as Structure).boxes()[0]
	elif node is Box:
		box = node
	if box == null:
		return Color(0.4, 0.4, 0.42)
	if box.is_terrain():
		return Color(0.92, 0.92, 0.9)
	var mesh := box.get_node_or_null(^"Mesh")
	var movable := box.movable_3d_from_any_side() or box.movable_2d_whole_face
	var base := BOX_MESH.COLOUR_MOVABLE if movable else BOX_MESH.COLOUR_STATIC
	var tint := BOX_MESH.MAX_STRUCTURE_TINT_MOVABLE if movable else BOX_MESH.MAX_STRUCTURE_TINT_STATIC
	if mesh != null and mesh.has_method(&"_tinted"):
		return mesh.call(&"_tinted", base, tint)
	return base
