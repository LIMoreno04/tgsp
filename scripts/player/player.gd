class_name Player
extends CharacterBody3D
## El cuerpo es un collider que camina por el CollidersPlane No tiene altura propia; 
## es la del PerspectiveManager. El modelo es hijo del cuerpo, así que lo sigue en x/z.

signal cell_changed(from: Vector3i, to: Vector3i)

const DIRECTION_OF: Dictionary[StringName, Vector2] = {
	&"move_up": Vector2.UP,
	&"move_down": Vector2.DOWN,
	&"move_left": Vector2.LEFT,
	&"move_right": Vector2.RIGHT,
}
## El centro del cuerpo, a media altura de las celdas del plano.
const HEIGHT_IN_PLANE := 0.5

const STEP_FREQUENCY := 13.0
const WADDLE_TILT := deg_to_rad(6.5)
const BOUNCE_HEIGHT := 0.04
const FORWARD_TILT := deg_to_rad(4.0)
const SQUASH_AMOUNT := 0.05

@export var camera: ProjectiveCamera
@export var walking_speed := 4.0

@onready var plane: CollidersPlane = get_parent()
@onready var room: Room = plane.get_parent()
@onready var perspective_manager: PerspectiveManager = room.perspective_manager
@onready var level: Level = room.get_parent()
@onready var model: Node3D = $Model
@onready var body_anim: Node3D = $Model/Body
@onready var body_shape: BoxShape3D = $CollisionShape3D.shape

## La última dirección en la que caminó, en la grilla. Sólo sirve para elegir con que interactura
var facing := Vector2(0, 1)
var grabbed: Box = null

var _shake: Tween
var _last_cell: Vector3i
var _walk_phase := 0.0
var _idle_phase := 0.0
var _last_position: Vector3
var _step_dust: GPUParticles3D
var _prev_step_idx := 0


func _ready() -> void:
	assert(camera != null, "El jugador necesita la cámara para saber hacia dónde va cada tecla")
	motion_mode = MOTION_MODE_FLOATING
	var spawn := room.player_spawn_point
	position = _centre_of(Vector2i(spawn.x, spawn.y))
	_last_position = position
	_last_cell = cell()
	_setup_step_dust()


func _setup_step_dust() -> void:
	if Engine.is_editor_hint():
		return
	_step_dust = GPUParticles3D.new()
	_step_dust.name = "StepDust"
	_step_dust.amount = 10
	_step_dust.lifetime = 0.35
	_step_dust.explosiveness = 0.7
	_step_dust.emitting = false
	_step_dust.position = Vector3(0, 0.04, 0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.12, 0.02, 0.12)
	mat.direction = Vector3(0, 0.8, 0.3)
	mat.spread = 45.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 0.7
	mat.gravity = Vector3(0, -0.6, 0)
	mat.scale_min = 0.03
	mat.scale_max = 0.06
	mat.color = Color(1.0, 1.0, 1.0, 0.55)
	_step_dust.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.albedo_color = Color(0.95, 0.98, 1.0, 0.6)
	quad.material = smat
	_step_dust.draw_pass_1 = quad

	model.add_child(_step_dust)


func _physics_process(_delta: float) -> void:
	_walk()
	if cell() != _last_cell:
		var from := _last_cell
		_last_cell = cell()
		cell_changed.emit(from, _last_cell)

func _walk() -> void:
	if level.is_locked() or grabbed != null:
		velocity = Vector3.ZERO
		return
	var walking := _on_plane(Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down"))
	velocity = walking * walking_speed
	move_and_slide()
	if walking != Vector3.ZERO:
		facing = _on_grid(walking)

func _process(delta: float) -> void:
	_place_model()
	_animate_character(delta)


func _unhandled_input(event: InputEvent) -> void:
	if level.is_locked():
		return
	if event.is_action_pressed(&"grab"):
		_let_go_or_reach()
	elif event.is_action_pressed(&"toggle_perspective"):
		_toggle_perspective()
	elif grabbed != null:
		for action: StringName in DIRECTION_OF:
			if event.is_action_pressed(action):
				_step_with_grabbed_box(DIRECTION_OF[action])


func cell() -> Vector3i:
	var column := _column()
	return Vector3i(column.x, column.y, perspective_manager.height)

func _column() -> Vector2i:
	var grid := GridCoordsProvider.godot_to_grid(position)
	return Vector2i(grid.x, grid.y)

func _centre_of(column: Vector2i) -> Vector3:
	return GridCoordsProvider.grid_to_godot(Vector3i(column.x, column.y, 0)) + Vector3(0.5, HEIGHT_IN_PLANE, 0.5)


func body_on_grid() -> Rect2:
	var size := Vector2(body_shape.size.x, body_shape.size.z)
	return Rect2(Vector2(position.x, position.z) - size / 2.0, size)


## E
func _let_go_or_reach() -> void:
	if grabbed != null:
		grabbed = null
		return
	var reached := room.index.choose_what_to_interact_with(cell(), facing, perspective_manager.current)
	if reached is ButtonPowerable:
		_press(reached)
	elif reached is Box:
		_grab(reached)
	else:
		_shake_model()


func _grab(box: Box) -> void:
	grabbed = box
	facing = Vector2(room.index.column_of(grabbed) - _column())
	_slide_to(_centre_of(_column()))

func _press(button: ButtonPowerable) -> void:
	var before := level.moment_now()
	facing = Vector2(room.index.column_of(button.box) - _column())
	room.press(button)
	level.remember(before)

## Jugador y caja juntos o ninguno.
func _step_with_grabbed_box(screen_direction: Vector2) -> void:
	var toward_box := room.index.column_of(grabbed) - _column()
	var along_grab := Vector2(toward_box).dot(_on_grid(_on_plane(screen_direction)))
	if is_zero_approx(along_grab):
		return
	var step := toward_box if along_grab > 0 else -toward_box
	var before := level.moment_now()
	if room.move_grabbed_box(grabbed, step, cell(), perspective_manager.current):
		level.remember(before)
		_slide_to(_centre_of(_column() + step))
	else:
		for box in room.index.boxes_grabbed_along_with(grabbed, perspective_manager.current):
			box.shake()

func _toggle_perspective() -> void:
	if grabbed != null:
		_shake_model()
		return
	var before := level.moment_now()
	if perspective_manager.toggle(_column()):
		level.remember(before)
		_slide_to(_centre_of(_column()))
	else:
		_shake_model()

func restore(where: Vector3i, restored_facing: Vector2, restored_grab: Box) -> void:
	facing = restored_facing
	grabbed = restored_grab
	var destination := _centre_of(Vector2i(where.x, where.y))
	if _is_one_grid_step_away(destination):
		_slide_to(destination)
	else:
		position = destination

func _is_one_grid_step_away(destination: Vector3) -> bool:
	var offset := destination - position
	return is_equal_approx(offset.length(), 1.0) and (is_zero_approx(offset.x) or is_zero_approx(offset.z))

func _slide_to(destination: Vector3) -> void:
	level.block(self)
	var slide := create_tween()
	slide.tween_property(self, "position", destination, GridEntity.SLIDE_SECONDS)
	slide.tween_callback(level.unblock.bind(self))


func _on_plane(screen_direction: Vector2) -> Vector3:
	var screen_right := camera.global_basis.x
	var screen_up := camera.global_basis.y
	screen_right.y = 0.0
	screen_up.y = 0.0
	return screen_right.normalized() * screen_direction.x - screen_up.normalized() * screen_direction.y

func _on_grid(on_plane: Vector3) -> Vector2:
	return Vector2(on_plane.x, on_plane.z) # x/z de Godot = x/y de grilla


func _shake_model() -> void:
	if is_instance_valid(_shake):
		_shake.kill()
	_shake = Shake.sideways(model, 0.0)


## En 3D, a la altura del jugador. En 2D, parado sobre el plano, para que ninguna columna lo
## tape. Sólo cambia mientras la cámara mira derecho para abajo, así nunca se ve el salto.
func _place_model() -> void:
	var on_the_plane := perspective_manager.is_2d() and not camera.is_transitioning
	var feet_in_plane := 0.0 if on_the_plane else perspective_manager.height - plane.position.y
	model.position.y = feet_in_plane - position.y
	model.basis = Basis.looking_at(Vector3(facing.x, 0, facing.y))


func _animate_character(delta: float) -> void:
	if not is_instance_valid(body_anim):
		return
	
	var moved_distance := (position - _last_position).length()
	_last_position = position
	
	var is_moving := velocity.length_squared() > 0.01 or (moved_distance > 0.001 and moved_distance < 0.5)
	
	if is_moving:
		_walk_phase += delta * STEP_FREQUENCY
		_idle_phase = 0.0

		# Dispara polvito de nieve en cada paso
		var current_step_idx := int(_walk_phase / PI)
		if current_step_idx > _prev_step_idx:
			_prev_step_idx = current_step_idx
			if is_instance_valid(_step_dust):
				_step_dust.restart()
				_step_dust.emitting = true

		# Balanceo lateral alternando de izquierda a derecha con cada paso (patas amarillas)
		var target_tilt_z := sin(_walk_phase) * WADDLE_TILT
		# Rebote vertical por cada paso
		var bounce_factor := absf(sin(_walk_phase))
		var target_bounce_y := bounce_factor * BOUNCE_HEIGHT
		# Ligera inclinación hacia adelante al avanzar
		var target_lean_x := -FORWARD_TILT
		# Efecto squash & stretch en pisadas
		var squash_y := 1.0 - (1.0 - bounce_factor) * SQUASH_AMOUNT + bounce_factor * (SQUASH_AMOUNT * 0.5)
		var squash_xz := 1.0 / sqrt(squash_y)

		body_anim.position.y = lerp(body_anim.position.y, target_bounce_y, 16.0 * delta)
		body_anim.rotation.z = lerp_angle(body_anim.rotation.z, target_tilt_z, 16.0 * delta)
		body_anim.rotation.x = lerp_angle(body_anim.rotation.x, target_lean_x, 16.0 * delta)
		body_anim.scale = body_anim.scale.lerp(Vector3(squash_xz, squash_y, squash_xz), 16.0 * delta)
	else:
		_walk_phase = 0.0
		_prev_step_idx = 0
		if is_instance_valid(_step_dust) and _step_dust.emitting:
			_step_dust.emitting = false
		_idle_phase += delta * 2.5
		
		# Respiración suave en reposo
		var breath := sin(_idle_phase) * 0.015
		var idle_scale_y := 1.0 + breath
		var idle_scale_xz := 1.0 - breath * 0.5
		
		body_anim.position.y = lerp(body_anim.position.y, 0.0, 10.0 * delta)
		body_anim.rotation.z = lerp_angle(body_anim.rotation.z, 0.0, 10.0 * delta)
		body_anim.rotation.x = lerp_angle(body_anim.rotation.x, 0.0, 10.0 * delta)
		body_anim.scale = body_anim.scale.lerp(Vector3(idle_scale_xz, idle_scale_y, idle_scale_xz), 10.0 * delta)
