@tool
class_name GridEntity
extends Node3D

const SLIDE_SECONDS := 0.12

@export var cell := Vector3i.ZERO:
	set(value):
		cell = value
		_slide_to(GridCoordsProvider.grid_to_godot(cell))

var _slide: Tween

var world_cell: Vector3i:
	get:
		var grid_parent := get_parent() as GridEntity
		if grid_parent == null:
			return cell
		return cell + grid_parent.world_cell


func _slide_to(destination: Vector3) -> void:
	if is_instance_valid(_slide):
		_slide.kill()
	var flat_from := Vector2(position.x, position.z)
	var flat_destination := Vector2(destination.x, destination.z)
	if Engine.is_editor_hint() or not is_inside_tree() or flat_from.is_equal_approx(flat_destination):
		position = destination
		return
	# Hold the higher of the two heights for the whole slide (snapping up now if
	# the destination is higher), then drop to the destination height on landing.
	position.y = maxf(position.y, destination.y)
	_slide = create_tween().set_parallel()
	_slide.tween_property(self, "position:x", destination.x, SLIDE_SECONDS)
	_slide.tween_property(self, "position:z", destination.z, SLIDE_SECONDS)
	_slide.chain().tween_callback(func() -> void: position.y = destination.y)

func _init() -> void:
	set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED or not Engine.is_editor_hint():
		return
	if not position.is_equal_approx(GridCoordsProvider.grid_to_godot(cell)):
		cell = GridCoordsProvider.godot_to_grid(position)
