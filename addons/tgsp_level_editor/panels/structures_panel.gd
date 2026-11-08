@tool
class_name LevelEditorStructuresPanel
extends VBoxContainer
## Las carpetas y las Structures del Room, como el árbol de la escena sin las cajas. Elige Structures (Ctrl y
## Shift suman, como en el árbol de Godot), los renombra, los esconde en la vista (sin guardar nada) y
## los mueve entre carpetas. La carpeta elegida es donde van las Structures nuevas.

const EYE_COLUMN_BUTTON := 0

var screen: LevelEditorScreen
var tree := Tree.new()
var _where_new_structures_go := Label.new()
## Para volver a mandar las Structures nuevas al Room: el árbol no tiene una fila del Room que elegir.
var _back_to_the_room: Button
var _move_to := MenuButton.new()
var _collapsed: Dictionary[Node, bool] = {}
var _refreshing := false
var _tree_selection_pending := false


func _init(the_screen: LevelEditorScreen) -> void:
	screen = the_screen
	name = "Structures"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var actions := HFlowContainer.new()
	add_child(actions)
	LevelEditorPropertiesPanel._button(actions, "New folder", "A folder in the selected folder (or the Room). Its cell moves everything in it.", _new_folder)
	_move_to.text = "Move to"
	_move_to.tooltip_text = "Move the selected structures or folders into another folder, keeping where they are in the world."
	_move_to.flat = false
	_move_to.about_to_popup.connect(_fill_move_to)
	_move_to.get_popup().id_pressed.connect(_move_into)
	actions.add_child(_move_to)
	LevelEditorPropertiesPanel._button(actions, "Delete", "Delete the selected structures or folders, and everything in them.", _delete)
	var where_row := HBoxContainer.new()
	add_child(where_row)
	_where_new_structures_go.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_where_new_structures_go.modulate = Color(1, 1, 1, 0.7)
	_where_new_structures_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where_row.add_child(_where_new_structures_go)
	_back_to_the_room = LevelEditorPropertiesPanel._button(where_row, "Back to the Room", "New structures go straight under the Room again.", screen.set_current_folder.bind(null))
	tree.columns = 2
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = screen.scaled(240)
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, int(screen.scaled(165)))
	tree.multi_selected.connect(_on_multi_selected)
	tree.item_edited.connect(_on_item_edited)
	# Doble clic (o Enter) en una fila abre su nombre para escribir, sin depender de cómo el Tree decide editar.
	tree.item_activated.connect(_on_item_activated)
	tree.item_collapsed.connect(_on_item_collapsed)
	tree.button_clicked.connect(_on_button_clicked)
	add_child(tree)


func refresh() -> void:
	_refreshing = true
	tree.clear()
	var level_room := screen.room
	if level_room == null:
		_where_new_structures_go.text = ""
		_back_to_the_room.visible = false
		_refreshing = false
		return
	var top := tree.create_item()
	for child in level_room.get_children():
		if child is RoomShell:
			var shell_item := tree.create_item(top)
			shell_item.set_text(0, "Room shell")
			shell_item.set_selectable(0, false)
			shell_item.set_selectable(1, false)
			shell_item.collapsed = _collapsed.get(child, true)
			shell_item.set_metadata(0, child)
			for part in child.get_children():
				if part is Structure:
					_add_structure(shell_item, part, false)
		elif child is GridEntity:
			_add_node(top, child)
	var folder := screen.current_folder()
	_where_new_structures_go.text = "New structures go to: %s" % (folder.name if folder != null else "the Room")
	_back_to_the_room.visible = folder != null
	_refreshing = false
	show_the_selection(false)


func _add_node(parent_item: TreeItem, node: Node) -> void:
	if node is Structure:
		_add_structure(parent_item, node, true)
	elif node is Box:
		_add_structure(parent_item, node, true)
	elif node is GridEntity:
		var item := tree.create_item(parent_item)
		item.set_text(0, node.name)
		item.set_text(1, "folder")
		item.set_editable(0, true)
		item.set_metadata(0, node)
		item.collapsed = _collapsed.get(node, false)
		_add_eye(item, node)
		if screen.current_folder() == node:
			item.set_custom_color(0, Color(0.55, 0.8, 1.0))
		for child in node.get_children():
			if child is GridEntity:
				_add_node(item, child)


func _add_structure(parent_item: TreeItem, node: Node, editable: bool) -> void:
	var item := tree.create_item(parent_item)
	var boxes: Array[Box] = []
	if node is Structure:
		boxes = (node as Structure).boxes()
	else:
		boxes = [node as Box]
	item.set_text(0, node.name if node is Structure else "%s (loose box)" % node.name)
	item.set_text(1, "%s · %d" % [BoxBrush.label_of_structure(boxes), boxes.size()])
	item.set_editable(0, editable)
	item.set_metadata(0, node)
	item.set_icon(0, _shade_swatch(screen.shade_of(node)))
	_add_eye(item, node)


func _add_eye(item: TreeItem, node: Node) -> void:
	var hidden := screen.view.hidden_structures.has(node)
	var hidden_with_its_folder := not hidden and screen.view.is_hidden(node)
	var tooltip := "Show it in the view" if hidden else ("Hidden with its folder" if hidden_with_its_folder else "Hide it in the view (nothing is saved)")
	item.add_button(1, LevelEditorIcons.get_icon("EyeClosed" if hidden or hidden_with_its_folder else "Eye", screen.icon_scale), EYE_COLUMN_BUTTON, false, tooltip)
	if hidden_with_its_folder:
		item.set_button_color(1, item.get_button_count(1) - 1, Color(1, 1, 1, 0.4))


static var _swatches: Dictionary[Color, Texture2D] = {}

static func _shade_swatch(colour: Color) -> Texture2D:
	if _swatches.has(colour):
		return _swatches[colour]
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	var texture := ImageTexture.create_from_image(image)
	_swatches[colour] = texture
	return texture


func _selected_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	var item := tree.get_next_selected(null)
	while item != null:
		if is_instance_valid(item.get_metadata(0)):
			nodes.append(item.get_metadata(0))
		item = tree.get_next_selected(item)
	return nodes


## Un clic manda una señal por cada fila que cambia: se elige una sola vez, después, y así el árbol
## tampoco se rehace dentro de su propia señal.
func _on_multi_selected(_item: TreeItem, _column: int, _selected: bool) -> void:
	if _refreshing or _tree_selection_pending:
		return
	_tree_selection_pending = true
	_select_what_the_tree_marks.call_deferred()


## Una carpeta sola pasa a ser donde van las Structures nuevas; las Structures se eligen en la vista.
func _select_what_the_tree_marks() -> void:
	_tree_selection_pending = false
	var nodes := _selected_nodes()
	if nodes.size() == 1 and not nodes[0] is Structure and not nodes[0] is Box:
		screen.set_current_folder(nodes[0])
		return
	var boxes: Array[Box] = []
	for node in nodes:
		if node is Structure:
			boxes.append_array((node as Structure).boxes())
		elif node is Box:
			boxes.append(node as Box)
	screen.select(boxes, [])


## Sólo marca lo elegido, sin rehacer el árbol: así no se pierde por dónde se estaba mirando. Una
## Structure se marca si está elegida entera: lo marcado es lo que borran y mueven los botones de arriba.
func show_the_selection(scroll_to_it := true) -> void:
	var root_item := tree.get_root()
	if root_item == null:
		return
	_refreshing = true
	tree.deselect_all()
	var first: TreeItem = null
	for item in _all_items(root_item):
		var node: Node = item.get_metadata(0)
		var boxes: Array[Box] = []
		if node is Structure:
			boxes = (node as Structure).boxes()
		elif node is Box:
			boxes = [node as Box]
		if not boxes.is_empty() and boxes.all(screen.is_selected):
			item.select(0)
			if first == null:
				first = item
	if first != null and scroll_to_it:
		tree.scroll_to_item(first)
	_refreshing = false


static func _all_items(item: TreeItem) -> Array[TreeItem]:
	var items: Array[TreeItem] = []
	var child := item.get_first_child()
	while child != null:
		items.append(child)
		items.append_array(_all_items(child))
		child = child.get_next()
	return items


## Devuelve si quedó escribiendo el nombre.
func _on_item_activated() -> bool:
	var item := tree.get_selected()
	return item != null and item.is_editable(0) and tree.edit_selected(true)


func _on_item_edited() -> void:
	var item := tree.get_edited()
	if item == null:
		return
	var node: Node = item.get_metadata(0)
	var new_name := item.get_text(0)
	if new_name != node.name:
		screen.edits.rename(node, new_name)
	# Si el nombre no valía (vacío, o el mismo), la fila vuelve a decir el de verdad.
	refresh.call_deferred()


func _on_item_collapsed(item: TreeItem) -> void:
	if not _refreshing and item.get_metadata(0) != null:
		_collapsed[item.get_metadata(0)] = item.collapsed


func _on_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button: int) -> void:
	if id != EYE_COLUMN_BUTTON:
		return
	var node: Node = item.get_metadata(0)
	if screen.view.hidden_structures.has(node):
		screen.view.hidden_structures.erase(node)
	else:
		screen.view.hidden_structures[node] = true
	screen.view.apply_hiding()
	screen.redraw()
	refresh.call_deferred()


func _new_folder() -> void:
	var parent: Node = screen.current_folder()
	if parent == null:
		parent = screen.room
	var folder := screen.edits.new_folder(parent)
	screen.set_current_folder(folder)


func _folders_in(node: Node, found: Array[Node]) -> void:
	for child in node.get_children():
		if child is GridEntity and not child is Structure and not child is Box:
			found.append(child)
			_folders_in(child, found)


func _fill_move_to() -> void:
	var popup := _move_to.get_popup()
	popup.clear()
	popup.add_item("The Room", 0)
	var folders: Array[Node] = []
	_folders_in(screen.room, folders)
	for i in folders.size():
		popup.add_item(String(screen.room.get_path_to(folders[i])), i + 1)
		popup.set_item_metadata(popup.item_count - 1, folders[i])
	popup.set_item_metadata(0, screen.room)


## Lo que tocan los botones: las filas marcadas, o si no hay ninguna, las Structures de lo elegido.
func _nodes_to_act_on() -> Array[Node]:
	var nodes := _selected_nodes()
	if nodes.is_empty():
		nodes = screen.structures_of(screen.selected_boxes)
	return nodes


func _move_into(id: int) -> void:
	var popup := _move_to.get_popup()
	var target: Node = popup.get_item_metadata(popup.get_item_index(id))
	if target != null:
		screen.edits.move_into(_nodes_to_act_on(), target)


func _delete() -> void:
	var nodes := _nodes_to_act_on()
	if nodes.is_empty():
		screen.flash("Select the structures or folders to delete first.", true)
		return
	if nodes.has(screen.current_folder()):
		screen.set_current_folder(null)
	screen.edits.delete_nodes(nodes, "Delete %s" % (nodes[0].name if nodes.size() == 1 else "%d structures and folders" % nodes.size()))
	screen.forget_freed_selection()
