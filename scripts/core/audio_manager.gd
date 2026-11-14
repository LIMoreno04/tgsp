extends Node

const STREAM_AMBIENT: AudioStream = preload("res://audio/ambient_winter.ogg")
const STREAM_UI_CLICK: AudioStream = preload("res://audio/ui_click_creamy.wav")
const STREAM_UI_HOVER: AudioStream = preload("res://audio/menu_hover.ogg")
const STREAM_STEP_1: AudioStream = preload("res://audio/penguin_step_1.wav")
const STREAM_STEP_2: AudioStream = preload("res://audio/penguin_step_2.wav")
const STREAM_STEP_3: AudioStream = preload("res://audio/penguin_step_3.wav")
const STREAM_GRAB: AudioStream = preload("res://audio/grab_object.ogg")
const STREAM_DRAG: AudioStream = preload("res://audio/box_drag.wav")
const STREAM_BUTTON: AudioStream = preload("res://audio/button_press.ogg")
const STREAM_PRESSURE_PLATE: AudioStream = preload("res://audio/plate_press.ogg")
const STREAM_DOOR_OPEN: AudioStream = preload("res://audio/door_open_cute.wav")
const STREAM_PERSPECTIVE: AudioStream = preload("res://audio/perspective_switch.wav")

const STEP_STREAMS: Array[AudioStream] = [STREAM_STEP_1, STREAM_STEP_2, STREAM_STEP_3]

static var _instance: Node = null

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_pool_size := 12
var _next_sfx_idx := 0
var _last_step_stream_idx := -1


func _init() -> void:
	_instance = self


func _ready() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_players()


func _setup_audio_players() -> void:
	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.name = "MusicPlayer"
		_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_music_player.bus = &"Master"
		_music_player.volume_db = -6.0
		add_child(_music_player)
		_music_player.finished.connect(func() -> void:
			if _music_player != null and _music_player.stream != null:
				_music_player.play()
		)

	if _sfx_players.is_empty():
		for i in range(_sfx_pool_size):
			var p := AudioStreamPlayer.new()
			p.name = "SFXPlayer_%d" % i
			p.process_mode = Node.PROCESS_MODE_ALWAYS
			p.bus = &"Master"
			add_child(p)
			_sfx_players.append(p)


static func ensure_ready() -> Node:
	if is_instance_valid(_instance):
		return _instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var existing := tree.root.get_node_or_null("AudioManager")
		if is_instance_valid(existing):
			_instance = existing
			return _instance
		var script := load("res://scripts/core/audio_manager.gd") as GDScript
		if script != null:
			var inst: Node = script.new()
			inst.name = "AudioManager"
			if tree.root.is_node_ready():
				tree.root.add_child(inst)
			else:
				tree.root.add_child.call_deferred(inst)
			_instance = inst
			return _instance
	return null


#==================Ambient / Music==================

static func play_ambient_music(volume_db: float = -6.0) -> void:
	var mgr := ensure_ready()
	if mgr == null:
		return
	var player: AudioStreamPlayer = mgr.get("_music_player")
	if player == null:
		return
	if player.playing and player.stream == STREAM_AMBIENT:
		return
	player.stream = STREAM_AMBIENT
	player.volume_db = volume_db
	player.play()


static func stop_ambient_music() -> void:
	var mgr := ensure_ready()
	if mgr == null:
		return
	var player: AudioStreamPlayer = mgr.get("_music_player")
	if player != null:
		player.stop()


#==================SFX Helpers==================

static func play_sfx(stream: AudioStream, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var mgr := ensure_ready()
	if mgr == null or stream == null:
		return
	var player := mgr._get_available_sfx_player() as AudioStreamPlayer
	if player == null:
		return
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	player.play()


func _get_available_sfx_player() -> AudioStreamPlayer:
	if _sfx_players.is_empty():
		_setup_audio_players()
	for p in _sfx_players:
		if not p.playing:
			return p
	if _sfx_players.is_empty():
		return null
	var player := _sfx_players[_next_sfx_idx]
	_next_sfx_idx = (_next_sfx_idx + 1) % _sfx_players.size()
	return player


#==================Specific Sound Triggers==================

## 1. Botón de menús: blocky o creamy y lowpoly
static func play_ui_click() -> void:
	play_sfx(STREAM_UI_CLICK, randf_range(0.96, 1.04), -2.0)


## Hover sutil en botones
static func play_ui_hover() -> void:
	play_sfx(STREAM_UI_HOVER, randf_range(0.98, 1.02), -12.0)


## 2. Pasos del personaje: pisadas leves y suaves de pingüino (waddle / flipper tap)
static func play_penguin_step() -> void:
	var mgr := ensure_ready()
	if mgr == null:
		return
	var last_idx: int = mgr.get("_last_step_stream_idx")
	var idx := randi() % STEP_STREAMS.size()
	if idx == last_idx:
		idx = (idx + 1) % STEP_STREAMS.size()
	mgr.set("_last_step_stream_idx", idx)
	var stream := STEP_STREAMS[idx]
	play_sfx(stream, randf_range(0.94, 1.06), -16.0)


## 3. Agarre de objetos (cajas)
static func play_grab() -> void:
	play_sfx(STREAM_GRAB, randf_range(0.95, 1.05), -1.0)


## 4. Arrastre de objetos por el hielo/suelo (leve y sutil fricción)
static func play_drag() -> void:
	play_sfx(STREAM_DRAG, randf_range(0.96, 1.04), -14.0)


## 5. Activación de botones
static func play_button() -> void:
	play_sfx(STREAM_BUTTON, 1.0, 0.0)


## 6. Activación de placas de presión
static func play_pressure_plate() -> void:
	play_sfx(STREAM_PRESSURE_PLATE, randf_range(0.96, 1.04), -1.0)


## 7. Apertura de puertas: desbloqueo y deslizamiento con armonía dulce
static func play_door_open() -> void:
	play_sfx(STREAM_DOOR_OPEN, randf_range(0.98, 1.02), -2.0)


## 8. Cambio de perspectiva (2D <-> 3D): suspiro dimensional sutil, ligero y suave
static func play_perspective_toggle() -> void:
	play_sfx(STREAM_PERSPECTIVE, randf_range(0.98, 1.02), -16.0)
