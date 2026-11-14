extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _flags(b) -> String:
	var f := PackedStringArray()
	if b.is_floor: f.append("floor")
	elif b.is_wall: f.append("wall")
	if b.walkable and not b.is_floor: f.append("walk")
	if b.keeps_height: f.append("keepH")
	if b.top_half_only: f.append("half")
	var h3 := ""
	if b.movable_3d_pos_x: h3 += "+x "
	if b.movable_3d_neg_x: h3 += "-x "
	if b.movable_3d_pos_y: h3 += "+y "
	if b.movable_3d_neg_y: h3 += "-y "
	if h3 != "": f.append("3D[" + h3.strip_edges() + "]")
	var h2 := ""
	if b.movable_2d_whole_face: h2 = "all"
	else:
		if b.movable_2d_pos_x: h2 += "+x "
		if b.movable_2d_neg_x: h2 += "-x "
		if b.movable_2d_pos_y: h2 += "+y "
		if b.movable_2d_neg_y: h2 += "-y "
	if h2 != "": f.append("2D[" + h2.strip_edges() + "]")
	return " ".join(f)

func _powerable_info(p) -> String:
	var name: String = p.get_script().get_global_name()
	var s := "%s face=%s" % [name, p.get("face")]
	for prop in ["edge", "directions", "allowed_directions", "next_level", "always_open", "switched_on", "direction", "powers", "emits"]:
		var v = p.get(prop)
		if v != null:
			s += " %s=%s" % [prop, v]
	return s

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for level_name in args:
		print("\n==================== %s ====================" % level_name)
		change_scene_to_file("res://scenes/levels/%s.tscn" % level_name)
		await _frames(5)
		var level = current_scene
		var room = level.get_node("Room")
		var pm = room.get_node("PerspectiveManager")
		print("dims=%s spawn=%s start=%s" % [room.dimensions, room.player_spawn_point, pm.starting_perspective])
		var shell = room.get_node("RoomShell")
		for part in shell.get_children():
			var cells := {}
			for b in part.boxes():
				cells[b.cell] = b
			var missing := []
			var odd := []
			for c in part.prism_cells():
				if not cells.has(c):
					missing.append(c + part.cell)
			for b in part.boxes():
				var wc: Vector3i = b.world_cell
				var fl := _flags(b)
				var expected := "floor" if part.name == "Floor" else "wall"
				if fl != expected and not (part.name != "Floor" and fl == "wall walk"):
					odd.append("%s %s" % [wc, fl])
				for p in b.get_children():
					if p.get_script() != null and p.get_script().get_global_name() in ["Wire", "ButtonPowerable", "PressurePlate", "Door", "ExitDoor", "LaserEmitter", "LaserReceiver"]:
						odd.append("%s <- %s" % [wc, _powerable_info(p)])
			print("shell %s cell=%s dims=%s boxes=%d missing=%s" % [part.name, part.cell, part.dimensions, part.boxes().size(), missing])
			for o in odd:
				print("   ", o)
		for node in room.get_children():
			if node == shell or node.get_script() == null:
				continue
			_dump(node, room, "")
		var printer = load("res://scripts/level/room_map_printer.gd").new(room)
		printer.print_cells_3D()
		printer.print_grid_2D()
	quit()

func _dump(node, room, indent: String) -> void:
	var gname: String = node.get_script().get_global_name()
	if gname == "Structure":
		print("%sStructure %s cell=%s dims=%s boxes=%d" % [indent, node.name, node.cell, node.dimensions, node.boxes().size()])
		for b in node.boxes():
			_dump_box(b, indent + "   ")
	elif gname == "Box":
		print("%sLOOSE BOX %s" % [indent, node.name])
		_dump_box(node, indent + "   ")
	elif gname == "GridEntity":
		print("%sFolder %s cell=%s" % [indent, node.name, node.cell])
		for c in node.get_children():
			if c.get_script() != null:
				_dump(c, room, indent + "   ")

func _dump_box(b, indent: String) -> void:
	var line := "%s%s world=%s %s" % [indent, b.name, b.world_cell, _flags(b)]
	print(line)
	for p in b.get_children():
		if p.get_script() != null and p.get_script().get_global_name() in ["Wire", "ButtonPowerable", "PressurePlate", "Door", "ExitDoor", "LaserEmitter", "LaserReceiver"]:
			print(indent + "   <- " + _powerable_info(p))
