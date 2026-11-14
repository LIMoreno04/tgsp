extends SceneTree
## Juega el juego entero como un jugador: sólo manda teclas (caminar, E, espacio) y lee el estado
## para saber cuándo soltarlas. Las soluciones están en tools/levels/solutions.txt.
##
##   G --headless --fixed-fps 60 --path . --script tools/levels/playthrough.gd
##   G ... --script tools/levels/playthrough.gd -- level_05 level_06     (sólo esos, cada uno desde cero)
##
## Acciones de una solución, separadas por `;`:
##   T          espacio: cambiar de perspectiva
##   W x y      caminar hasta esa columna, por un camino que el jugador puede hacer
##   G dx dy    caminar contra ese lado y E: agarrar la caja de ese lado
##   P n / L n  empujar / tirar n veces de la caja agarrada
##   R          E: soltar
##   B dx dy    caminar contra ese lado y E: apretar el botón de ese lado
##   N n        esperar n frames
## Un nivel que no termina con su solución se anota como fallado y se salta al siguiente.

const SOLUTIONS_PATH := "res://tools/levels/solutions.txt"
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right"]
const KEY_COMBOS: Array[Array] = [
	[&"move_up"], [&"move_down"], [&"move_left"], [&"move_right"],
	[&"move_up", &"move_left"], [&"move_up", &"move_right"], [&"move_down", &"move_left"], [&"move_down", &"move_right"],
]
const DIRECTION_OF: Dictionary[StringName, Vector2] = {
	&"move_up": Vector2.UP, &"move_down": Vector2.DOWN, &"move_left": Vector2.LEFT, &"move_right": Vector2.RIGHT,
}
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const STEP_TIMEOUT_FRAMES := 90
const LOCK_TIMEOUT_FRAMES := 400

# Sin tipos del juego: un script de --script se compila antes de que existan los autoloads, y
# nombrar aquí una clase del juego la compilaría antes de tiempo. Se cargan al correr.
var level: Node
var player: Node
var room: Node
var game_manager: Script
var box_script: Script
var problem := ""
var results: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game_manager = load("res://scripts/core/game_manager.gd")
	box_script = load("res://scripts/objects/box.gd")
	var solutions := _read_solutions()
	var only := OS.get_cmdline_user_args()
	if only.is_empty():
		game_manager.start_new_game(self) # Lo mismo que el botón "Nueva partida".
		await _play_from_here(solutions, true)
	else:
		for level_name in only:
			change_scene_to_file("res://scenes/levels/%s.tscn" % level_name)
			await _play_from_here(solutions, false)
	print("\n================ RESULT ================")
	for line in results:
		print(line)
	quit()


## Juega el nivel que se está cargando y, si `keeps_going`, los que le siguen hasta los créditos.
func _play_from_here(solutions: Dictionary, keeps_going: bool) -> void:
	while true:
		await _frames(30)
		await _until_the_level_is_ready()
		if not _is_a_level(current_scene):
			results.append("ended at %s" % current_scene.scene_file_path)
			return
		var level_path := current_scene.scene_file_path
		var level_name := level_path.get_file().get_basename()
		_take_the_level()
		var finished := await _play(level_name, solutions.get(level_name, PackedStringArray()))
		if _end_screen() != null:
			results.append("%s: COMPLETED -> end screen" % level_name)
			await _leave_the_end_screen()
			return
		if finished:
			results.append("%s: COMPLETED -> %s" % [level_name, current_scene.scene_file_path.get_file()])
		else:
			results.append("%s: FAILED (%s)" % [level_name, problem])
			var next := _next_level_of(level_path)
			if keeps_going and not next.is_empty():
				change_scene_to_file(next)
		if not keeps_going:
			return
		if not finished and _next_level_of(level_path).is_empty():
			return


func _play(level_name: String, actions: PackedStringArray) -> bool:
	print("\n---- %s: %d actions" % [level_name, actions.size()])
	problem = "no solution written" if actions.is_empty() else ""
	for i in actions.size():
		var words := actions[i].split(" ", false)
		await _until_unlocked()
		var done := await _do(words)
		await _frames(2)
		if _left_the_level():
			return true
		print("  %-10s -> cell %s %s%s" % [actions[i], player.cell(), "2D" if room.perspective_manager.is_2d() else "3D", " holding" if player.grabbed != null else ""])
		if not done:
			problem = "action %d `%s`: %s" % [i + 1, actions[i], problem]
			print("  !! ", problem)
			return false
	for i in 90:
		await physics_frame
		if _left_the_level():
			return true
	if problem.is_empty():
		problem = "the solution ended and the level did not"
	return false


func _do(words: PackedStringArray) -> bool:
	match words[0]:
		"T":
			return await _toggle()
		"W":
			return await _walk_to(Vector2i(int(words[1]), int(words[2])))
		"G":
			await _face(Vector2i(int(words[1]), int(words[2])))
			await _tap(&"grab")
			if player.grabbed == null:
				problem = "nothing was grabbed"
			return player.grabbed != null
		"B":
			await _face(Vector2i(int(words[1]), int(words[2])))
			await _tap(&"grab")
			return true
		"R":
			await _tap(&"grab")
			return player.grabbed == null
		"P", "L":
			for i in (int(words[1]) if words.size() > 1 else 1):
				if not await _step_with_the_box(words[0] == "P"):
					problem = "the box did not move (step %d)" % (i + 1)
					return false
				if _left_the_level():
					return true
			return true
		"N":
			await _frames(int(words[1]))
			return true
	problem = "unknown action"
	return false


#================== Las teclas ==================

func _tap(action: StringName) -> void:
	await _until_unlocked()
	_send(action, true)
	await _frames(2)
	_send(action, false)
	await _frames(2)
	await _until_unlocked()

func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _release_the_move_keys() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)

## Las teclas que, con la cámara como está, llevan hacia esa dirección de la grilla.
func _keys_toward(grid_direction: Vector2) -> Array:
	for combo: Array in KEY_COMBOS:
		var screen := Vector2.ZERO
		for action: StringName in combo:
			screen += DIRECTION_OF[action]
		var on_grid: Vector2 = player._on_grid(player._on_plane(screen.normalized())).normalized()
		if on_grid.dot(grid_direction.normalized()) > 0.99:
			return combo
	return []


func _toggle() -> bool:
	var before: int = room.perspective_manager.current
	await _tap(&"toggle_perspective")
	await _frames(5)
	await _until_unlocked()
	if room.perspective_manager.current == before:
		problem = "the toggle was refused"
		return false
	return true


## Camina un par de frames contra ese lado, como quien se arrima a una caja para mirarla.
func _face(direction: Vector2i) -> void:
	await _until_unlocked()
	for action: StringName in _keys_toward(Vector2(direction)):
		Input.action_press(action)
	await _frames(3)
	_release_the_move_keys()
	await _frames(1)


func _step_with_the_box(forward: bool) -> bool:
	await _until_unlocked()
	if player.grabbed == null:
		return false
	var toward_box := Vector2(room.index.column_of(player.grabbed) - player._column() as Vector2i)
	var before: Vector3i = player.cell()
	for action in MOVE_ACTIONS:
		var along: float = toward_box.dot(player._on_grid(player._on_plane(DIRECTION_OF[action])))
		if (forward and along > 0.3) or (not forward and along < -0.3):
			await _tap(action)
			break
	await _frames(3)
	await _until_unlocked()
	return _left_the_level() or player.cell() != before


#================== Caminar ==================

func _walk_to(column: Vector2i) -> bool:
	var path := _path_to(column)
	if path.is_empty() and player._column() != column:
		problem = "no way to walk from %s to %s" % [player._column(), column]
		return false
	for step: Vector2i in path:
		if not await _walk_to_the_centre_of(step):
			if _left_the_level():
				return true
			problem = "stopped at %s on the way to %s" % [player._column(), column]
			return false
		if _left_the_level():
			return true
	return true

## Mantiene apretadas las teclas que llevan al centro de esa columna, hasta llegar.
func _walk_to_the_centre_of(column: Vector2i) -> bool:
	var target := Vector2(column) + Vector2(0.5, 0.5)
	for frame in STEP_TIMEOUT_FRAMES:
		if _left_the_level():
			return true
		var here := Vector2(player.position.x, player.position.z)
		var left := target - here
		_release_the_move_keys()
		if left.length() < 0.06:
			return true
		var along := Vector2(signf(left.x), 0) if absf(left.x) > absf(left.y) else Vector2(0, signf(left.y))
		for action: StringName in _keys_toward(along):
			Input.action_press(action)
		await physics_frame
	_release_the_move_keys()
	return false

## El camino más corto, de columna en columna, por donde el jugador puede pasar ahora: donde puede
## estar parado, sin cruzar una franja ni una puerta cerrada ni pisar el pedestal de un botón.
func _path_to(target: Vector2i) -> Array[Vector2i]:
	var perspective: int = room.perspective_manager.current
	var height: int = player.cell().z
	var start: Vector2i = player._column()
	var came_from: Dictionary[Vector2i, Vector2i] = {start: start}
	var to_visit: Array[Vector2i] = [start]
	while not to_visit.is_empty() and not came_from.has(target):
		var here: Vector2i = to_visit.pop_front()
		for direction: Vector2i in NEIGHBOURS:
			var there := here + direction
			if came_from.has(there):
				continue
			if not room.index.can_player_be_on(Vector3i(there.x, there.y, height), perspective):
				continue
			if room.index.has_barrier_on(here, box_script.facing_toward(direction), perspective, height):
				continue
			if room.index.has_barrier_on(there, box_script.facing_toward(-direction), perspective, height):
				continue
			if room.index.has_button_on(there, perspective, height):
				continue
			came_from[there] = here
			to_visit.append(there)
	var path: Array[Vector2i] = []
	if not came_from.has(target):
		return path
	var step := target
	while step != start:
		path.push_front(step)
		step = came_from[step]
	return path


#================== El nivel ==================

func _take_the_level() -> void:
	level = current_scene
	room = level.get_node("Room")
	player = level.get_node("Room/CollidersPlane/Player")

func _left_the_level() -> bool:
	return not is_instance_valid(level) or current_scene != level or _end_screen() != null

func _end_screen() -> Node:
	if current_scene == null:
		return null
	for child in current_scene.get_children():
		if child.has_method("go_to_the_menu"):
			return child
	return null

func _is_a_level(scene: Node) -> bool:
	return scene.has_method("is_locked")

func _leave_the_end_screen() -> void:
	await _frames(30)
	var screen := _end_screen()
	print("  end screen: paused=%s, button focused=%s" % [paused, screen.menu_button.has_focus()])
	_send(&"ui_accept", true)
	await _frames(2)
	_send(&"ui_accept", false)
	await _frames(60)
	results.append("after the credits: %s, save at %s" % [current_scene.scene_file_path.get_file(), game_manager.get_saved_level_path().get_file()])

func _next_level_of(level_path: String) -> String:
	var number := level_path.get_file().get_basename().trim_prefix("level_").to_int()
	var next := "res://scenes/levels/level_%02d.tscn" % (number + 1)
	return next if ResourceLoader.exists(next) else ""


func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _until_the_level_is_ready() -> void:
	for i in LOCK_TIMEOUT_FRAMES:
		if current_scene != null and current_scene.is_node_ready():
			return
		await physics_frame

func _until_unlocked() -> void:
	for i in LOCK_TIMEOUT_FRAMES:
		if _left_the_level() or not level.is_locked():
			return
		await physics_frame


func _read_solutions() -> Dictionary:
	var solutions := {}
	var level_name := ""
	for line in FileAccess.get_file_as_string(SOLUTIONS_PATH).split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var text := line
		if line.begins_with("level_") and line.contains(":"):
			level_name = line.get_slice(":", 0)
			text = line.substr(line.find(":") + 1)
			solutions[level_name] = PackedStringArray()
		for action in text.split(";", false):
			if not action.strip_edges().is_empty():
				solutions[level_name].append(action.strip_edges())
	return solutions
