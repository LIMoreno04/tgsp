@tool
class_name LevelEditorProblemsPanel
extends VBoxContainer
## Cada aviso de los nodos del nivel (los mismos del dock de escena), y uno del editor: el nivel no
## tiene salida. Show elige y encuadra al culpable.

signal count_changed(count: int)

var screen: LevelEditorScreen
var _list := VBoxContainer.new()


func _init(the_screen: LevelEditorScreen) -> void:
	screen = the_screen
	name = "Problems"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_list)


func refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if screen.room == null:
		count_changed.emit(0)
		return
	var problems := collect()
	if problems.is_empty():
		var fine := Label.new()
		fine.text = "No problems found."
		fine.modulate = Color(0.6, 1.0, 0.65)
		_list.add_child(fine)
	for problem in problems:
		var row := HBoxContainer.new()
		_list.add_child(row)
		var text := Label.new()
		text.text = "%s: %s" % [problem[0].name if problem[0] != null else "Level", problem[1]]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size.x = screen.scaled(160)
		row.add_child(text)
		if problem[0] != null:
			LevelEditorPropertiesPanel._button(row, "Show", "Select and frame it.", screen.show_node.bind(problem[0]))
		_list.add_child(HSeparator.new())
	count_changed.emit(problems.size())


## [nodo, mensaje] por cada aviso.
func collect() -> Array[Array]:
	var problems: Array[Array] = []
	_collect_from(screen.room, problems)
	if screen.exits().is_empty():
		problems.append([null, "The level has no exit door."])
	return problems


func _collect_from(node: Node, problems: Array[Array]) -> void:
	var script := node.get_script() as Script
	if script != null and script.is_tool() and node.has_method(&"_get_configuration_warnings"):
		for warning: String in node.call(&"_get_configuration_warnings"):
			problems.append([node, warning])
	for child in node.get_children():
		if child is Node3D and (child.owner == screen.level_root or child == screen.room):
			_collect_from(child, problems)
