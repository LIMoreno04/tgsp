@tool
class_name GridEntity
extends Node3D

@export var cell := Vector3i.ZERO:
	set(value):
		cell = value
		position = CoordsProvider.grid_to_godot(cell)


var world_cell: Vector3i:
	get:
		var grid_parent := get_parent() as GridEntity
		if grid_parent == null:
			return cell
		return cell + grid_parent.world_cell


func _init() -> void:
	set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED or not Engine.is_editor_hint():
		return
	if not position.is_equal_approx(CoordsProvider.grid_to_godot(cell)):
		cell = CoordsProvider.godot_to_grid(position)
