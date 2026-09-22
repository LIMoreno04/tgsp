@tool
class_name GridEntity
extends Node3D

@export var displacement := Vector3(0.5,0.5,0.5)
@export var cell := Vector3i.ZERO:
	set(value):
		cell = value
		position = CoordsProvider.grid_to_godot(cell) - displacement


func _init() -> void:
	set_notify_local_transform(true)
	position = CoordsProvider.grid_to_godot(cell) - displacement


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		var target :Vector3i = CoordsProvider.godot_to_grid(position + displacement)
		if target != cell or not position.is_equal_approx(CoordsProvider.grid_to_godot(target) - displacement):
			cell = target
