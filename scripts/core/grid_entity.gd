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


## El Room que la contiene, o null.
func room_above() -> Node3D:
	var ancestor := get_parent()
	while ancestor != null:
		if global_name_of(ancestor) == &"Room":
			return ancestor
		ancestor = ancestor.get_parent()
	return null

## Por qué las reglas no la ven, o "" si la ven. Room.rebuild_index solo entra por GridEntities
## (y por el RoomShell), así que un Node3D cualquiera entre esta y el Room la deja afuera.
func why_the_rules_cannot_see_it() -> String:
	var room := room_above()
	if room == null:
		if _is_edited_on_its_own():
			return ""
		return "Not inside a Room, so the rules skip it: it is drawn, but nothing collides with it or moves it. Put it inside the Room, directly or in a folder with the grid_entity.gd script."
	var ancestor := get_parent()
	while ancestor != room:
		if not (ancestor is GridEntity or global_name_of(ancestor) == &"RoomShell"):
			return "%s, between this and the Room, is not a GridEntity, so the rules skip this: it is drawn, but nothing collides with it or moves it. Give %s the grid_entity.gd script." % [ancestor.name, ancestor.name]
		ancestor = ancestor.get_parent()
	return ""

## Una caja, una Structure o una carpeta abierta como escena propia: el Room está donde se use.
func _is_edited_on_its_own() -> bool:
	if not is_inside_tree():
		return false
	var edited_root := get_tree().edited_scene_root
	return edited_root is GridEntity and (edited_root == self or edited_root.is_ancestor_of(self))

## Para preguntar si un nodo es un Room, un RoomShell o una Structure sin nombrar esas clases:
## room_shell.gd y structure.gd precargan escenas que usan este script, y nombrarlas cerraría un
## ciclo de carga.
static func global_name_of(node: Node) -> StringName:
	if node == null or node.get_script() == null:
		return &""
	return (node.get_script() as Script).get_global_name()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := _warnings_about_its_transform()
	var unseen := why_the_rules_cannot_see_it()
	if unseen != "":
		warnings.append(unseen)
	return warnings

func _warnings_about_its_transform() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not basis.is_equal_approx(Basis.IDENTITY):
		warnings.append("Rotated or scaled: the rules only see its cell, so it plays as if it were neither. Reset its rotation and scale.")
	return warnings


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
	update_configuration_warnings()
