@tool
extends Node3D

enum ShapeMode {PRISM, CUSTOM}

@export var id: int
@export var origin_cell: Vector3i = Vector3i.ZERO
@export var shape_mode: ShapeMode = ShapeMode.PRISM
@export var individual_boxes: Dictionary[Vector3i,Box] = {}
@export var holes: Array[Vector3i]


func _init() -> void:
	set_notify_local_transform(true)



func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		var target :Vector3i = CoordsProvider.godot_to_grid(position)
		if target != origin_cell or not position.is_equal_approx(CoordsProvider.grid_to_godot(target)):
			origin_cell = target


func _ready() -> void:
	id = get_instance_id()
