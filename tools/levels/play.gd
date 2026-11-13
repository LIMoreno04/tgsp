extends SceneTree
## Juega un nivel con el jugador real: --  <level> <out.png> <acciones...>
## acciones: at,x,y  face,dx,dy  E  push  pull  toggle  walk,x,y  doors  shot

var level
var player
var room

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)

func _step(forward: bool) -> void:
	if player.grabbed == null:
		print("  !! nothing grabbed")
		return
	var toward: Vector2i = room.index.column_of(player.grabbed) - player._column()
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var along: float = Vector2(toward).dot(player._on_grid(player._on_plane(d)))
		if (forward and along > 0.5) or (not forward and along < -0.5):
			player._step_with_grabbed_box(d)
			return
	print("  !! no screen direction for step")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var level_name: String = args[0]
	var out: String = args[1]
	change_scene_to_file("res://scenes/levels/%s.tscn" % level_name)
	await _frames(60)
	level = current_scene
	room = level.get_node("Room")
	player = level.get_node("Room/CollidersPlane/Player")
	var hud = level.get_node_or_null("LevelHUD")
	if hud: hud.visible = false
	for action in args.slice(2):
		var p := action.split(",")
		match p[0]:
			"at", "walk":
				player.position = player._centre_of(Vector2i(int(p[1]), int(p[2])))
				await _frames(12)
			"face":
				player.facing = Vector2(float(p[1]), float(p[2]))
			"E":
				player._let_go_or_reach()
				await _frames(15)
			"push":
				_step(true); await _frames(18)
			"pull":
				_step(false); await _frames(18)
			"toggle":
				player._toggle_perspective(); await _frames(60)
			"shot":
				await _shot(out)
			"doors":
				var closed := []
				for d in room.index.closed_doors: closed.append(str(d.get_path()).get_file() + "@" + str(room.index.cell_of(d.box)))
				print("  closed doors: ", closed)
		var scene_now := current_scene.scene_file_path if current_scene else "none"
		print("%-12s -> player %s grabbed=%s persp=%s scene=%s" % [action, player.cell() if is_instance_valid(player) else "?", (player.grabbed != null) if is_instance_valid(player) else "?", room.perspective_manager.current if is_instance_valid(room) else "?", scene_now.get_file()])
		if not scene_now.ends_with(level_name + ".tscn"):
			print("LEVEL FINISHED -> ", scene_now)
			break
	quit()
