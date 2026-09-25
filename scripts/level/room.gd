@tool
class_name Room
extends Node3D


#==================General=====================
@export var dimensions:Vector3i = Vector3i(5,5,5)

#===============Perspectiva==================
enum Perspective {ISO_3D, TOP_2D}
signal perspective_changed(new_perspective: Perspective)

var current_perspective: Perspective = Perspective.ISO_3D
var blocking_perspective_semaphore := []

func is_3d() -> bool:
	return current_perspective == Perspective.ISO_3D

func is_2d() -> bool:
	return current_perspective == Perspective.TOP_2D

func is_perspective_locked() -> bool:
	return not blocking_perspective_semaphore.is_empty()

func block_perspective(caller_process: Node) -> void:
	if caller_process in blocking_perspective_semaphore:
		return
	blocking_perspective_semaphore.append(caller_process)

func unblock_perspective(caller_process: Node) -> void:
	if caller_process in blocking_perspective_semaphore:
		blocking_perspective_semaphore.erase(caller_process)

func toggle_perspective() -> bool:
	if is_perspective_locked():
		return false
	else:
		current_perspective = Perspective.TOP_2D if current_perspective==Perspective.ISO_3D else Perspective.ISO_3D
		perspective_changed.emit(current_perspective)
		return true

func volumetric_center() -> Vector3:
	return GridCoordsProvider.grid_to_godot(maximum_reach())*(0.5)

#==================estructura del nivel==================
var cells_3D: Dictionary[Vector3i,Box]
var grid_2D: Dictionary[Vector2i,Box]

func add_to_index(box: Box) -> void:
	var cell := box.world_cell
	var projected_cell := Vector2i(cell.x,cell.y)
	
	if cells_3D.has(cell):
		push_error("Two boxes share the cell %s: %s and %s." % [cell, cells_3D[cell].get_path(), box.get_path()])
		return

	cells_3D[cell] = box
	if not grid_2D.has(projected_cell) or grid_2D[projected_cell].world_cell.z < cell.z:
		grid_2D[projected_cell] = box

func maximum_reach() -> Vector3i:
	var x_max := dimensions.x
	var y_max := dimensions.y
	var z_max := dimensions.z
	for occupied_cell: Vector3i in cells_3D:
		x_max = max(x_max, occupied_cell.x + 1)
		y_max = max(y_max, occupied_cell.y + 1)
		z_max = max(z_max, occupied_cell.z + 1) #el +1 porque las coords de grilla empiezan en 0,0,0; y acá busco tamaño, no coords
	return Vector3i(x_max,y_max,z_max)

func same_structure(a: Box,b: Box) -> bool:
	if a.get_parent() is Structure and b.get_parent() is Structure:
		return a.get_parent() == b.get_parent()
	else:
		return a == b

func adjacent_and_connected_to(box: Box)->Array[Box]:
	if is_3d():
		return
	elif is_2d():
		return
	else:
		return



func _box_can_move(box: Box, direction: Vector2i) -> bool:
	if is_3d():
		var target := Vector3i(direction.x, direction.y, box.world_cell.z)
		return not cells_3D.has(target) or same_structure(box,cells_3D[target])
	elif is_2d():
		return not grid_2D.has(direction) or grid_2D[direction].walkable or same_structure(box,grid_2D[direction])
	else:
		assert(false, "Error catastrófico: Perspectiva no definida")
		return false



func _ready() -> void:
	cells_3D.clear()
	grid_2D.clear()
	for child in get_children():
		if child is Box:
			add_to_index(child)
		elif child is Structure:
			for grandchild in child.get_children():
				if grandchild is Box:
					add_to_index(grandchild)
