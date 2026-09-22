class_name CoordsProvider
extends RefCounted

static func godot_to_grid(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x),
		floori(position.z),
		floori(position.y)
	)

static func grid_to_godot(position: Vector3i) -> Vector3:
	return Vector3(
		position.x,
		position.z,
		position.y
	) +  Vector3(0.5,0.5,0.5)
