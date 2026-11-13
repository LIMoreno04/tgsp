extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	for level_name in args.slice(1):
		change_scene_to_file("res://scenes/levels/%s.tscn" % level_name)
		await _frames(90)
		var level := current_scene
		var hud := level.get_node_or_null("LevelHUD")
		if hud: hud.visible = false
		for c in (hud.get_children() if hud else []):
			if c is CanvasItem: c.visible = false
		await _frames(5)
		await _shot("%s/%s_3d.png" % [out, level_name])
		var player = level.get_node("Room/CollidersPlane/Player")
		player._toggle_perspective()
		await _frames(80)
		await _shot("%s/%s_2d.png" % [out, level_name])
	quit()
