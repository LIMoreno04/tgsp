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
	for box in boxes():
		if not _is_in_the_prism(box.cell):
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


## Delete excess y su aviso usan la misma regla, así nunca dicen cosas distintas. Mira los bordes en
## vez de buscar en prism_cells(): cada caja recorrería el prisma entero, y un piso tiene cientos.
func _is_in_the_prism(cell_in_structure: Vector3i) -> bool:
	return cell_in_structure.clamp(Vector3i.ZERO, dimensions - Vector3i.ONE) == cell_in_structure


## Una caja que entra, sale o cambia de lugar entre sus hermanas (Fill, Delete excess, Clear, o a mano
## en el dock: duplicada, borrada, arrastrada) cambia lo que avisa. Sólo en el editor, como el aviso.
func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED and Engine.is_editor_hint():
		update_configuration_warnings()


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
	var outside := boxes().filter(func(box: Box) -> bool: return not _is_in_the_prism(box.cell)).size()
	if outside == 1:
		warnings.append("1 of its boxes lies outside its dimensions, so Delete excess would delete it.")
	elif outside > 1:
		warnings.append("%d of its boxes lie outside its dimensions, so Delete excess would delete them." % outside)
	for child in get_children():
		if child is Structure:
			warnings.append("Structures cannot be nested, but %s is one." % child.name)
	warnings.append_array(super())
	var keeping_height := boxes().filter(func(box: Box) -> bool: return box.keeps_height).size()
	if keeping_height > 0 and keeping_height < boxes().size():
		warnings.append("Only some of its boxes keep their height. One is enough for the whole structure to keep it, so the others probably should too.")
	var terrain := boxes().filter(func(box: Box) -> bool: return box.is_terrain()).size()
	if terrain > 0 and terrain < boxes().size():
		warnings.append("Some of its boxes are terrain (is_wall or is_floor) and some are not. Terrain never moves, so none of this structure can move. Make it two structures.")
	return warnings
