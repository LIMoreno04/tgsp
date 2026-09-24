@tool
class_name Structure
extends GridEntity

const BOX_SCENE: PackedScene = preload("res://scenes/prefabs/box.tscn")

@export var dimensions := Vector3i.ONE:
	set(value):
		dimensions = value
		update_configuration_warnings()

@export_tool_button("Fill", "Add") var fill_button := fill
@export_tool_button("Delete excess", "Remove") var trim_button := remove_excess
@export_tool_button("Clear", "Remove") var clear_button := clear
@export_tool_button("Mark exposed tops walkable", "Reload") var mark_tops_button := mark_exposed_tops_walkable
@export_tool_button("Make unwalkable", "Eraser") var make_unwalkable := mark_all_unwalkable


func boxes() -> Array[Box]:
	var result: Array[Box] = []
	for child in get_children():
		if child is Box:
			result.append(child)
	return result


func prism_cells() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for x in dimensions.x:
		for y in dimensions.y:
			for z in dimensions.z:
				result.append(Vector3i(x, y, z))
	return result


func fill() -> void:
	var occupied := _cells_with_a_box()
	for cell_to_fill in prism_cells():
		if occupied.has(cell_to_fill):
			continue
		var box := BOX_SCENE.instantiate() as Box
		box.cell = cell_to_fill
		add_child(box, true)
		box.owner = get_tree().edited_scene_root


func remove_excess() -> void:
	var prism := prism_cells()
	for box in boxes():
		if not prism.has(box.cell):
			_delete(box)


func clear() -> void:
	for box in boxes():
		_delete(box)


func mark_exposed_tops_walkable() -> void:
	var occupied := _cells_with_a_box()
	for box in boxes():
		box.walkable = not occupied.has(box.cell + Vector3i(0,0,1))

func mark_all_unwalkable() -> void:
	for box in boxes():
		box.walkable = false


func _cells_with_a_box() -> Dictionary[Vector3i, bool]:
	var taken: Dictionary[Vector3i, bool] = {}
	for box in boxes():
		taken[box.cell] = true
	return taken


func _delete(box: Box) -> void:
	remove_child(box)
	box.queue_free()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.z <= 0:
		warnings.append("Dimensions must be greater than zero.")
	var seen: Dictionary[Vector3i, bool] = {}
	for box in boxes():
		if seen.has(box.cell):
			warnings.append("Two boxes share the cell %s." % box.cell)
		seen[box.cell] = true
	for child in get_children():
		if child is Structure:
			warnings.append("Structures cannot be nested, but %s is one." % child.name)
	return warnings
