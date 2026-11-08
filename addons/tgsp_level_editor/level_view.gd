@tool
class_name LevelEditorView
extends Control
## La vista del nivel: un SubViewport con su propia cámara, que dentro del editor comparte el mundo 3D
## del editor y así dibuja el nivel abierto tal cual. Mueve la cámara, esconde lo que está por encima
## de la capa, averigua qué hay bajo el mouse y le pasa el mouse y las teclas a la herramienta.

signal camera_changed

const ORBIT_SPEED := 0.008
const ZOOM_STEP := 1.12
const DISTANCE := ProjectiveCamera.DISTANCE
const SMALLEST_SIZE := 2.0
const BIGGEST_SIZE := 300.0
## F con una caja sola: unas nueve celdas de alto en la pantalla.
const SMALLEST_FRAMED_SIZE := 9.0
const ELEVATION_3D := ProjectiveCamera.ELEVATION_3D_DEGREES * PI / 180.0
## El rincón +x +y desde el que mira el juego.
const GAME_YAW := PI / 4.0

var screen: LevelEditorScreen

var viewport := SubViewport.new()
var camera := Camera3D.new()
var preview := LevelEditorPreview.new()
var overlay_3d := LevelEditorPreview.new()

var _container := SubViewportContainer.new()
var _drawing := Control.new()

var room: Room
var is_2d := false
var is_game_view := true
var is_perspective := false
## Donde mira la cámara libre, en coordenadas de Godot.
var focus := Vector3.ZERO
var yaw := GAME_YAW
var pitch := ELEVATION_3D
var view_size := 20.0
## La vista 3D a la que vuelve Tab.
var _3d_was_game_view := true

## Las cajas escondidas por la capa o por el ojo del panel de Structures.
var hidden_structures: Dictionary[Node, bool] = {}
var _hidden_boxes: Dictionary[Box, bool] = {}
var _bounds_low := Vector3i(-2, -2, -2)
var _bounds_high := Vector3i(10, 10, 10)

var _orbiting := false
var _panning := false
var _turn: Tween
var _light: DirectionalLight3D
var _light_opacity_before := -1.0
var last_hit: GridPicker.Hit = GridPicker.Hit.new()
## El rectángulo de Select mientras se arrastra, en coordenadas de la vista.
var marquee := Rect2()
var _mouse_position := Vector2.ZERO
var _mouse_inside := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_2X
	_container.add_child(viewport)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 1000.0
	camera.current = true
	viewport.add_child(camera)
	viewport.add_child(overlay_3d)
	viewport.add_child(preview)
	_drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drawing.draw.connect(_draw_on_top)
	add_child(_drawing)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)


## Toma el teclado al entrar el mouse, salvo que se esté escribiendo en un campo de texto.
func _on_mouse_entered() -> void:
	_mouse_inside = true
	var focused := get_viewport().gui_get_focus_owner()
	if not (focused is LineEdit or focused is TextEdit):
		grab_focus()

func _on_mouse_exited() -> void:
	_mouse_inside = false
	_show_nothing_under_the_mouse()


#==================El nivel==================

func set_room(new_room: Room) -> void:
	restore_the_light()
	unhide_everything()
	room = new_room
	_light = null
	if room != null:
		var level_camera := room.get_node_or_null(^"ProjectiveCamera") as ProjectiveCamera
		if level_camera != null:
			_light = level_camera.light
		refresh_bounds()
	if is_2d:
		_hide_the_shadows()


func refresh_bounds() -> void:
	if room == null:
		return
	var low := Vector3i(-1, -1, -1)
	var high := room.dimensions
	for cell: Vector3i in room.index.cells_3D:
		low = low.min(cell)
		high = high.max(cell)
	_bounds_low = low - Vector3i.ONE
	_bounds_high = high + Vector3i.ONE


#==================La cámara==================

func reset_camera() -> void:
	is_2d = false
	is_game_view = true
	_3d_was_game_view = true
	yaw = GAME_YAW
	pitch = ELEVATION_3D
	if room != null:
		focus = room.volumetric_center()
	game_view()


## Donde estaría la cámara del juego, en la vista actual, encuadrada como la encuadra el juego al
## empezar, para la proporción de la ventana del juego.
func game_view() -> void:
	if room == null:
		return
	_stop_turning()
	is_game_view = true
	is_perspective = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var perspective := Room.Perspective.TOP_2D if is_2d else Room.Perspective.ISO_3D
	ProjectiveCamera.frame(camera, ProjectiveCamera.pose_for(perspective), room.maximum_reach(), room.volumetric_center(), game_aspect())
	camera.size *= maxf(1.0, game_aspect() / _aspect())
	focus = room.volumetric_center()
	view_size = camera.size
	if not is_2d:
		yaw = GAME_YAW
		pitch = ELEVATION_3D
	_after_camera_moved()


static func game_aspect() -> float:
	var width: float = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var height: float = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	return width / height


func _aspect() -> float:
	var area := size
	if area.y <= 0.0:
		return game_aspect()
	return area.x / area.y


func toggle_2d() -> void:
	if room == null:
		return
	var from_basis := camera.basis
	var from_focus := focus
	var from_size := view_size
	if is_2d:
		is_2d = false
		restore_the_light()
		if _3d_was_game_view:
			game_view()
		else:
			is_game_view = false
			_place_free_camera()
	else:
		_3d_was_game_view = is_game_view
		is_2d = true
		_hide_the_shadows()
		if is_game_view:
			game_view()
		else:
			_place_free_camera()
	_animate_from(from_basis, from_focus, from_size)


func _animate_from(from_basis: Basis, from_focus: Vector3, from_size: float) -> void:
	var to_basis := camera.basis
	var to_focus := focus
	var to_size := camera.size
	var to_projection := camera.projection
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_stop_turning()
	_turn = create_tween()
	_turn.tween_method(_turn_step.bind(from_basis, to_basis, from_focus, to_focus, from_size, to_size), 0.0, 1.0, ProjectiveCamera.TURN_SECONDS)
	_turn.tween_callback(_finish_turning.bind(to_projection))


func _turn_step(weight: float, from_basis: Basis, to_basis: Basis, from_focus: Vector3, to_focus: Vector3, from_size: float, to_size: float) -> void:
	camera.basis = from_basis.slerp(to_basis, weight)
	camera.position = from_focus.lerp(to_focus, weight) + camera.basis.z * DISTANCE
	camera.size = lerpf(from_size, to_size, weight)
	_drawing.queue_redraw()


func _finish_turning(projection: Camera3D.ProjectionType) -> void:
	camera.projection = projection
	_after_camera_moved()


func _stop_turning() -> void:
	if is_instance_valid(_turn) and _turn.is_running():
		_turn.kill()


func toggle_perspective_projection() -> void:
	if is_2d:
		return
	is_perspective = not is_perspective
	is_game_view = false
	_place_free_camera()


func turn_90(clockwise: bool) -> void:
	if is_2d:
		return
	yaw += -PI / 2.0 if clockwise else PI / 2.0
	is_game_view = false
	_place_free_camera()


func _place_free_camera() -> void:
	_stop_turning()
	if is_2d:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.basis = ProjectiveCamera.pose_for(Room.Perspective.TOP_2D)
		camera.position = focus + camera.basis.z * DISTANCE
		camera.size = view_size
	else:
		var back := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
		camera.basis = Basis.looking_at(-back, Vector3.UP)
		if is_perspective:
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = 40.0
			camera.position = focus + back * (view_size / (2.0 * tan(deg_to_rad(20.0))))
		else:
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.position = focus + back * DISTANCE
			camera.size = view_size
	_after_camera_moved()


func _after_camera_moved() -> void:
	_drawing.queue_redraw()
	camera_changed.emit()
	if _mouse_inside:
		_update_the_hover()


func frame_cells(cells: Array[Vector3i]) -> void:
	if cells.is_empty() or room == null:
		return
	var low := cells[0]
	var high := cells[0]
	for cell in cells:
		low = low.min(cell)
		high = high.max(cell)
	var centre := Vector3(low + high + Vector3i.ONE) * 0.5
	focus = Vector3(centre.x, centre.z, centre.y)
	var extent := Vector3(high - low + Vector3i.ONE).length()
	# Con algo de alrededor: una caja sola, de cerquísima, no dice dónde está.
	view_size = clampf(extent * 1.6, SMALLEST_FRAMED_SIZE, BIGGEST_SIZE)
	is_game_view = false
	_place_free_camera()


func _orbit(by: Vector2) -> void:
	yaw -= by.x * ORBIT_SPEED
	pitch = clampf(pitch + by.y * ORBIT_SPEED, 0.05, PI / 2.0 - 0.01)
	is_game_view = false
	_place_free_camera()


func _pan(by: Vector2) -> void:
	var units_per_pixel := camera.size / maxf(size.y, 1.0)
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		units_per_pixel = view_size / maxf(size.y, 1.0)
	focus += (-camera.basis.x * by.x + camera.basis.y * by.y) * units_per_pixel
	is_game_view = false
	_place_free_camera()


## Acerca o aleja hacia lo que está bajo el mouse: ese punto queda quieto en la pantalla.
func _zoom(closer: bool) -> void:
	if is_game_view:
		focus = camera.position - camera.basis.z * DISTANCE
		if not is_2d:
			var back := camera.basis.z
			pitch = asin(clampf(back.y, -1.0, 1.0))
			yaw = atan2(back.x, back.z)
	is_game_view = false
	var under_the_mouse := camera.project_position(_mouse_position, camera.position.distance_to(focus))
	view_size = clampf(view_size / ZOOM_STEP if closer else view_size * ZOOM_STEP, SMALLEST_SIZE, BIGGEST_SIZE)
	_place_free_camera()
	focus += under_the_mouse - camera.project_position(_mouse_position, camera.position.distance_to(focus))
	_place_free_camera()


func _on_resized() -> void:
	if is_game_view and room != null:
		game_view()
	_drawing.queue_redraw()


#==================Las sombras en 2D==================

## En 2D no hay sombras, como en el juego. Se vuelven a poner antes de guardar, así nunca se guarda
## el cambio.
func _hide_the_shadows() -> void:
	if _light == null or not is_instance_valid(_light):
		return
	if _light_opacity_before < 0.0:
		_light_opacity_before = _light.shadow_opacity
	_light.shadow_opacity = 0.0


func restore_the_light() -> void:
	if _light != null and is_instance_valid(_light) and _light_opacity_before >= 0.0:
		_light.shadow_opacity = _light_opacity_before
	_light_opacity_before = -1.0


func hide_the_shadows_again_if_2d() -> void:
	if is_2d and is_visible_in_tree():
		_hide_the_shadows()


#==================Lo que se ve==================

## Esconde las cajas por encima de la capa y las de las Structures con el ojo cerrado. Sólo esconde su
## Mesh y el dibujo de sus powerables, que nunca se guardan.
func apply_hiding() -> void:
	if room == null:
		return
	var should_hide: Dictionary[Box, bool] = {}
	for box: Box in room.index.cells_3D.values():
		if not is_box_visible(box):
			should_hide[box] = true
	for box: Box in _hidden_boxes:
		if is_instance_valid(box) and not should_hide.has(box):
			_show_box(box, true)
	for box: Box in should_hide:
		_show_box(box, false)
	_hidden_boxes = should_hide


func unhide_everything() -> void:
	for box: Box in _hidden_boxes:
		if is_instance_valid(box):
			_show_box(box, true)
	_hidden_boxes.clear()


func is_box_visible(box: Box) -> bool:
	if screen != null and screen.layer_mode and room.index.cell_of(box).z > screen.layer:
		return false
	return not is_hidden(box)


## Escondido él, su Structure o alguna carpeta de las que lo contienen: lo que se pinte después en una
## carpeta escondida también queda escondido.
func is_hidden(node: Node) -> bool:
	while node != null and node != room:
		if hidden_structures.has(node):
			return true
		node = node.get_parent()
	return false


static func _show_box(box: Box, shown: bool) -> void:
	var mesh := box.get_node_or_null(^"Mesh") as Node3D
	if mesh != null:
		mesh.visible = shown
	for piece in box.powerables():
		for part in piece.get_children():
			if part is Node3D:
				(part as Node3D).visible = shown


#==================El mouse==================

func pick(at: Vector2) -> GridPicker.Hit:
	if room == null:
		return GridPicker.Hit.new()
	var origin := camera.project_ray_origin(at)
	var direction := camera.project_ray_normal(at)
	var plane_z := screen.plane_for_picking() if screen != null else 0
	return GridPicker.pick(origin, direction, room.index.cells_3D, is_box_visible, _bounds_low, _bounds_high, plane_z)


func _update_the_hover() -> void:
	last_hit = pick(_mouse_position)
	if screen != null:
		screen.on_hover(last_hit)


## Después de un cambio, lo que estaba bajo el mouse puede no existir más: se vuelve a buscar.
func repick() -> void:
	if _mouse_inside:
		_update_the_hover()
	else:
		_show_nothing_under_the_mouse()


func _show_nothing_under_the_mouse() -> void:
	last_hit = GridPicker.Hit.new()
	if screen != null:
		screen.on_hover(last_hit)


func _gui_input(event: InputEvent) -> void:
	if room == null or screen == null:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_mouse_position = motion.position
		if _orbiting:
			_orbit(motion.relative)
		elif _panning:
			_pan(motion.relative)
		else:
			_update_the_hover()
			if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
				screen.on_drag(last_hit, motion)
		accept_event()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		_mouse_position = button.position
		grab_focus()
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom(button.button_index == MOUSE_BUTTON_WHEEL_UP)
			MOUSE_BUTTON_MIDDLE:
				var pans := button.shift_pressed or is_2d
				_panning = button.pressed and pans
				_orbiting = button.pressed and not pans
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				last_hit = pick(_mouse_position)
				if button.pressed:
					screen.on_press(last_hit, button)
				else:
					screen.on_release(last_hit, button)
		accept_event()
	elif event is InputEventKey:
		var key := event as InputEventKey
		# Shift, Ctrl y Alt cambian lo que haría un clic: el dibujo lo muestra sin mover el mouse.
		if key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
			screen.redraw()
		if key.is_pressed() and screen.on_key(key):
			accept_event()


func _draw_on_top() -> void:
	if room == null:
		return
	_draw_the_compass()
	if is_game_view and not is_turning():
		_draw_the_game_frame()
	if marquee.has_area():
		_drawing.draw_rect(marquee, Color(0.4, 0.7, 1.0, 0.15))
		_drawing.draw_rect(marquee, Color(0.4, 0.7, 1.0, 0.9), false, 1.0)


func is_turning() -> bool:
	return is_instance_valid(_turn) and _turn.is_running()


## Hacia dónde apuntan +x y +y de la grilla en la pantalla, para leer los lados y los bordes.
func _draw_the_compass() -> void:
	var scale := screen.icon_scale if screen != null else 1.0
	var centre := Vector2(46 * scale, size.y - 46 * scale)
	var font := get_theme_default_font()
	var axes := {"+x": Vector3(1, 0, 0), "+y": Vector3(0, 0, 1)}
	var colours := {"+x": Color(1.0, 0.45, 0.4), "+y": Color(0.45, 0.85, 0.5)}
	# Oscuro y con borde: tiene que leerse igual sobre el piso blanco que sobre el fondo.
	_drawing.draw_circle(centre, 36 * scale, Color(0.08, 0.08, 0.1, 0.75))
	_drawing.draw_circle(centre, 36 * scale, Color(1, 1, 1, 0.25), false, 1.0, true)
	for axis_name: String in axes:
		var on_screen := Vector2(camera.basis.x.dot(axes[axis_name]), -camera.basis.y.dot(axes[axis_name]))
		if on_screen.length() < 0.05:
			continue
		var tip := centre + on_screen.normalized() * 24 * scale * minf(1.0, on_screen.length() * 1.4)
		_drawing.draw_line(centre, tip, colours[axis_name], 3.0 * scale, true)
		_drawing.draw_string(font, tip + (tip - centre).normalized() * 5 * scale - Vector2(8, -5) * scale, axis_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * scale), colours[axis_name])


## Lo que el jugador vería: el encuadre del juego, con lo de afuera oscurecido.
func _draw_the_game_frame() -> void:
	var game := game_aspect()
	var mine := _aspect()
	var frame_size := Vector2(size.y * game, size.y) if mine >= game else Vector2(size.x, size.x / game)
	var frame := Rect2((size - frame_size) * 0.5, frame_size)
	var shade := Color(0, 0, 0, 0.35)
	_drawing.draw_rect(Rect2(0, 0, size.x, frame.position.y), shade)
	_drawing.draw_rect(Rect2(0, frame.end.y, size.x, size.y - frame.end.y), shade)
	_drawing.draw_rect(Rect2(0, frame.position.y, frame.position.x, frame.size.y), shade)
	_drawing.draw_rect(Rect2(frame.end.x, frame.position.y, size.x - frame.end.x, frame.size.y), shade)
	_drawing.draw_rect(frame, Color(1, 1, 1, 0.25), false, 1.0)


func redraw_on_top() -> void:
	_drawing.queue_redraw()


## La dirección de la grilla más parecida a una dirección de la pantalla, para las flechas.
func grid_direction_for_screen(screen_direction: Vector2) -> Vector3i:
	var best := Vector3i(1, 0, 0)
	var best_alignment := -INF
	for direction: Vector2i in LevelIndex.NEIGHBOURS_2D:
		var world := Vector3(direction.x, 0, direction.y)
		var on_screen := Vector2(camera.basis.x.dot(world), -camera.basis.y.dot(world))
		if on_screen.length() < 0.01:
			continue
		var alignment := on_screen.normalized().dot(screen_direction.normalized())
		if alignment > best_alignment:
			best_alignment = alignment
			best = Vector3i(direction.x, direction.y, 0)
	return best


## Una celda proyectada en la pantalla, para elegir con un rectángulo.
func cell_on_screen(cell: Vector3i) -> Vector2:
	return camera.unproject_position(GridCoordsProvider.grid_to_godot(cell) + Vector3(0.5, 0.5, 0.5))


func is_behind_the_camera(cell: Vector3i) -> bool:
	return camera.is_position_behind(GridCoordsProvider.grid_to_godot(cell) + Vector3(0.5, 0.5, 0.5))
