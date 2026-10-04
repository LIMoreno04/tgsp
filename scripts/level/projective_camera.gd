@tool
class_name ProjectiveCamera
extends Camera3D

signal perspective_change_started()
signal perspective_change_finished()

const TURN_SECONDS := 0.6
const DISTANCE := 100.0
const MARGIN := 1.15
## Cuánto mira hacia abajo en 3D. Isométrico exacto = 35.26°
const ELEVATION_3D_DEGREES := 30.0

## Las sombras se apagan en 2D
@export var light: DirectionalLight3D

@onready var room: Room = get_parent()

var is_transitioning := false

## Medidos una sola vez, en el primer salto, así el encuadre no cambia cuando se mueven cajas.
var _room_reach: Vector3i
var _room_centre: Vector3

var _from_pose: Basis
var _to_pose: Basis


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	if Engine.is_editor_hint():
		_jump_to.call_deferred(Room.Perspective.ISO_3D)
		return
	room.perspective_manager.perspective_changed.connect(_turn_to)
	_jump_to.call_deferred(room.perspective_manager.starting_perspective)


## 3D: mirando hacia abajo desde la esquina +x +y
## 2D: mirando derecho para abajo, con +x a la derecha y +y para abajo en pantalla.
func _pose_for(perspective: Room.Perspective) -> Basis:
	if Room.is_3d(perspective):
		var elevation := deg_to_rad(ELEVATION_3D_DEGREES)
		var toward_the_room := Vector3(-1, 0, -1).normalized() * cos(elevation) + Vector3.DOWN * sin(elevation)
		return Basis.looking_at(toward_the_room, Vector3.UP)
	return Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)

func _shadow_opacity_for(perspective: Room.Perspective) -> float:
	return 1.0 if Room.is_3d(perspective) else 0.0


func _jump_to(perspective: Room.Perspective) -> void:
	_room_reach = room.maximum_reach()
	_room_centre = room.volumetric_center()
	_frame(_pose_for(perspective))
	if light != null:
		light.shadow_opacity = _shadow_opacity_for(perspective)

func _turn_to(perspective: Room.Perspective) -> void:
	room.perspective_manager.block(self)
	is_transitioning = true
	perspective_change_started.emit()
	_from_pose = basis
	_to_pose = _pose_for(perspective)
	var turn := create_tween().set_parallel()
	turn.tween_method(_frame_between, 0.0, 1.0, TURN_SECONDS)
	if light != null:
		turn.tween_property(light, "shadow_opacity", _shadow_opacity_for(perspective), TURN_SECONDS)
	turn.chain().tween_callback(_finish_turn)

func _frame_between(weight: float) -> void:
	_frame(_from_pose.slerp(_to_pose, weight))

func _finish_turn() -> void:
	is_transitioning = false
	room.perspective_manager.unblock(self)
	perspective_change_finished.emit()


## Mirando desde `pose`, con el cuarto centrado y entero en la pantalla.
func _frame(pose: Basis) -> void:
	basis = pose
	position = _room_centre + pose.z * DISTANCE
	size = _size_to_show_room(pose)

## El alto de la vista que deja ver todo el cuarto, cáscara incluida, desde esa pose.
func _size_to_show_room(pose: Basis) -> float:
	var shell_corner := Vector3(-1, -1, -1)
	var room_box := AABB(shell_corner, GridCoordsProvider.grid_to_godot(_room_reach) - shell_corner)
	var half_width := 0.0
	var half_height := 0.0
	for corner in 8:
		var from_centre := room_box.get_endpoint(corner) - _room_centre
		half_width = maxf(half_width, absf(from_centre.dot(pose.x)))
		half_height = maxf(half_height, absf(from_centre.dot(pose.y)))
	var aspect := get_viewport().get_visible_rect().size.aspect()
	return 2.0 * maxf(half_height, half_width / aspect) * MARGIN
