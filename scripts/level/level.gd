class_name Level
extends Node3D

const SKIP_TIME := 60.0

const UPDATE_POWER_AFTER_PERSPECTIVE_TURN := false
const WINTER_ENVIRONMENT: Environment = preload("res://scenes/prefabs/winter_environment.tres")
const SNOW_PARTICLES_SCENE: PackedScene = preload("res://scenes/prefabs/snow_particles.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://scenes/ui/pause_menu.tscn")

class Moment:
	var box_cells: Dictionary[Box, Vector3i]
	var button_states: Dictionary[ButtonPowerable, bool]
	var powerables_displayed_as_on: Dictionary[Powerable, bool]
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
var _save_pending := false
var _pause_menu: PauseMenu = null
var _hud: LevelHUD = null


func _ready() -> void:
	GameManager.ensure_settings_loaded()
	AudioManager.play_ambient_music()
	_setup_winter_atmosphere()
	_setup_hud()
	room.moved.connect(request_power_update)
	room.buttons_changed.connect(request_power_update)
	player.cell_changed.connect(request_power_update.unbind(2))
	if UPDATE_POWER_AFTER_PERSPECTIVE_TURN:
		player.camera.perspective_change_finished.connect(request_power_update)
	else:
		room.perspective_manager.perspective_changed.connect(request_power_update.unbind(1))
	if GameManager.consume_restore_request(scene_file_path):
		GameManager.restore_level_state(self)
	elif not scene_file_path.is_empty():
		GameManager.save_level_state(self)
	request_power_update()


func _setup_hud() -> void:
	_hud = LevelHUD.new()
	_hud.name = "LevelHUD"
	add_child(_hud)
	_hud.pause_requested.connect(_toggle_pause)
	_hud.setup_for_level(scene_file_path, true)


func _setup_winter_atmosphere() -> void:
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null:
		world_env.environment = WINTER_ENVIRONMENT
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(1.0, 0.968627, 0.921569, 1.0)
		sun.light_energy = 1.15
		sun.shadow_blur = 1.5
		sun.directional_shadow_blend_splits = true
	if room != null and room.get_node_or_null("SnowParticles") == null and get_node_or_null("SnowParticles") == null:
		var snow := SNOW_PARTICLES_SCENE.instantiate() as SnowParticles
		snow.auto_fit_room = false
		add_child(snow)
		snow.fit_to_room(room)

## Lo único que cambia sin avisar es dónde está el cuerpo del jugador: si dejó una puerta que
## sostenía, o entró o salió de un laser, hace falta calcular de nuevo. Los rayos lo siguen en cada frame.
func _physics_process(_delta: float) -> void:
	var perspective := room.perspective_manager.current
	if room.is_power_out_of_date(perspective, player.cell().z, player.body_on_grid()):
		request_power_update()
	room.show_the_beams(perspective, player.cell().z, player.body_on_grid())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_toggle_pause()
		return
	if is_locked() and not _is_playing_an_undo():
		return
	if event.is_action_pressed(&"undo"):
		undo()
	elif event.is_action_pressed(&"restart"):
		GameManager.save_clean_level(scene_file_path)
		get_tree().reload_current_scene()


func _toggle_pause() -> void:
	if _pause_menu != null and _pause_menu.is_open:
		_pause_menu.close()
	else:
		if _pause_menu == null or not is_instance_valid(_pause_menu):
			_pause_menu = PAUSE_MENU_SCENE.instantiate() as PauseMenu
			add_child(_pause_menu)
			if _hud != null and is_instance_valid(_hud):
				_pause_menu.saved.connect(func() -> void: _hud.show_save_indicator())
		_pause_menu.open(self)


#==================Undo==================

func moment_now() -> Moment:
	var moment := Moment.new()
	moment.box_cells = room.box_cells()
	moment.button_states = room.button_states()
	moment.powerables_displayed_as_on = room.powerables_displayed_as_on()
	moment.perspective = room.perspective_manager.current
	moment.height = room.perspective_manager.height
	moment.player_cell = player.cell()
	moment.facing = player.facing
	moment.grabbed = player.grabbed
	return moment

func remember(moment: Moment) -> void:
	_history.append(moment)
	_request_save()


func undo() -> void:
	_finish_every_animation_now()
	if _history.is_empty():
		return
	var moment: Moment = _history.pop_back()
	var turns_back := moment.perspective != room.perspective_manager.current
	room.restore(moment.box_cells, moment.button_states, moment.powerables_displayed_as_on)
	room.perspective_manager.restore(moment.perspective, moment.height)
	player.restore(moment.player_cell, moment.facing, moment.grabbed)
	_hold_the_lock_for(ProjectiveCamera.TURN_SECONDS if turns_back else GridEntity.SLIDE_SECONDS)
	_request_save()


func _request_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	_save_progress.call_deferred()


func _save_progress() -> void:
	_save_pending = false
	GameManager.save_level_state(self)

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
