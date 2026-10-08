class_name Level
extends Node3D

const SKIP_TIME := 60.0

const UPDATE_POWER_AFTER_PERSPECTIVE_TURN := false

class Moment:
	var box_cells: Dictionary[Box, Vector3i]
	var button_states: Dictionary[ButtonPowerable, bool]
	var perspective: Room.Perspective
	var height: int
	var player_cell: Vector3i
	var facing: Vector2
	var grabbed: Box

@onready var room: Room = $Room
@onready var player: Player = $Room/CollidersPlane/Player

var _history: Array[Moment] = []
var _blockers := []
var _power_update_pending := false


func _ready() -> void:
	room.moved.connect(request_power_update)
	room.buttons_changed.connect(request_power_update)
	player.cell_changed.connect(request_power_update.unbind(2))
	if UPDATE_POWER_AFTER_PERSPECTIVE_TURN:
		player.camera.perspective_change_finished.connect(request_power_update)
	else:
		room.perspective_manager.perspective_changed.connect(request_power_update.unbind(1))
	request_power_update()

## Sólo mientras el cuerpo cruza una puerta: si dejó de cruzarla, puede que se tenga que cerrar.
func _physics_process(_delta: float) -> void:
	for door in room.doors_stopped_by_the_player:
		if not room.index.is_body_across(door, room.perspective_manager.current, player.cell().z, player.body_on_grid()):
			request_power_update()
			return


func _unhandled_input(event: InputEvent) -> void:
	if is_locked() and not _is_playing_an_undo():
		return
	if event.is_action_pressed(&"undo"):
		undo()
	elif event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()


#==================Undo==================

func moment_now() -> Moment:
	var moment := Moment.new()
	moment.box_cells = room.box_cells()
	moment.button_states = room.button_states()
	moment.perspective = room.perspective_manager.current
	moment.height = room.perspective_manager.height
	moment.player_cell = player.cell()
	moment.facing = player.facing
	moment.grabbed = player.grabbed
	return moment

func remember(moment: Moment) -> void:
	_history.append(moment)


func undo() -> void:
	_finish_every_animation_now()
	if _history.is_empty():
		return
	var moment: Moment = _history.pop_back()
	var turns_back := moment.perspective != room.perspective_manager.current
	room.restore(moment.box_cells, moment.button_states)
	room.perspective_manager.restore(moment.perspective, moment.height)
	player.restore(moment.player_cell, moment.facing, moment.grabbed)
	_hold_the_lock_for(ProjectiveCamera.TURN_SECONDS if turns_back else GridEntity.SLIDE_SECONDS)

func _finish_every_animation_now() -> void:
	for animation in get_tree().get_processed_tweens():
		animation.custom_step(SKIP_TIME)

func _hold_the_lock_for(seconds: float) -> void:
	block(self)
	var playback := create_tween()
	playback.tween_interval(seconds)
	playback.tween_callback(unblock.bind(self))

func _is_playing_an_undo() -> bool:
	return _blockers.has(self)


#==================Powerables==================

func request_power_update() -> void:
	if _power_update_pending:
		return
	_power_update_pending = true
	_update_power.call_deferred()

func _update_power() -> void:
	_power_update_pending = false
	room.update_power(room.perspective_manager.current, player.cell(), player.body_on_grid())


#==================Input lock==================

func block(blocker: Node) -> void:
	if not _blockers.has(blocker):
		_blockers.append(blocker)

func unblock(blocker: Node) -> void:
	_blockers.erase(blocker)


func is_locked() -> bool:
	var blocking_list := []
	for blocker in _blockers:
		if is_instance_valid(blocker):
			blocking_list.append(blocker)
	_blockers = blocking_list
	return not _blockers.is_empty()
