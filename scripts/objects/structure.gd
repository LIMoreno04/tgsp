@tool
extends GridEntity

enum ShapeMode {PRISM, CUSTOM}

@export var id: int
@export var shape_mode: ShapeMode = ShapeMode.PRISM:
	set(value):
		shape_mode = value
		notify_property_list_changed()
@export var dimensions: Vector3i = Vector3i(1, 1, 1)

@export var shape: Array[Vector3i]
@export var holes: Array[Vector3i]
@export var default_mobility: Box.Mobility = Box.Mobility.STATIC

func _validate_property(property: Dictionary) -> void:
	if property.name == "shape" and shape_mode != ShapeMode.CUSTOM:
		property.usage = PROPERTY_USAGE_NO_EDITOR

	if property.name == "dimensions" and shape_mode != ShapeMode.PRISM:
		property.usage = PROPERTY_USAGE_NO_EDITOR


# ------------------------ Boxes ------------------------------

func build() -> void:
	pass

func delete() -> void:
	pass

func toggle_all_exposed_tops_walkable(make_walkable: bool) -> void:
	pass


func change_default_mobility(new_mobility: Box.Mobility) -> void:
	pass