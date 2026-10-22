@tool
class_name HandlesTool
extends LevelEditorTool
## Prende y apaga agarraderas apuntándolas: una cara lateral es su agarradera 3D, cerca de un borde de
## la tapa es esa agarradera 2D, el medio de la tapa es la tapa entera. Shift: en todo el grupo,
## sobre los lados que dan afuera. El botón derecho apaga.

enum Target { NOTHING, SIDE_3D, EDGE_2D, WHOLE_TOP }

const SIDE_OF_NORMAL: Dictionary[Vector3i, Box.Facing] = {
	Vector3i(1, 0, 0): Box.Facing.POS_X,
	Vector3i(-1, 0, 0): Box.Facing.NEG_X,
	Vector3i(0, 1, 0): Box.Facing.POS_Y,
	Vector3i(0, -1, 0): Box.Facing.NEG_Y,
}

var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()


func _init(the_screen: LevelEditorScreen) -> void:
	super(the_screen)
	title = "Handles"
	tooltip = "Click a side face for its 3D handle, near a top edge for that 2D handle, the middle of a top for the whole top. Shift: the whole group."


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit


func target_of(hit: GridPicker.Hit) -> Target:
	if not hit.has_box:
		return Target.NOTHING
	if SIDE_OF_NORMAL.has(hit.normal):
		return Target.SIDE_3D
	if hit.face == Powerable.Face.TOP:
		return Target.WHOLE_TOP if hit.top_edge == GridPicker.NO_EDGE else Target.EDGE_2D
	return Target.NOTHING


## La bandera que se tocaría, y si queda prendida.
func change_for(hit: GridPicker.Hit, box: Box, turning_off: bool) -> Dictionary[StringName, bool]:
	var changes: Dictionary[StringName, bool] = {}
	match target_of(hit):
		Target.SIDE_3D:
			var flag := BoxBrush.SIDE_FLAG_3D[SIDE_OF_NORMAL[hit.normal]]
			changes[flag] = false if turning_off else not box.get(flag)
		Target.EDGE_2D:
			var facing: Box.Facing = hit.top_edge
			var flag := BoxBrush.EDGE_FLAG_2D[facing]
			if box.movable_2d_whole_face:
				# La tapa entera se vuelve los cuatro bordes menos el apuntado.
				changes[&"movable_2d_whole_face"] = false
				for each: Box.Facing in BoxBrush.EDGE_FLAG_2D:
					changes[BoxBrush.EDGE_FLAG_2D[each]] = each != facing
			else:
				changes[flag] = false if turning_off else not box.get(flag)
		Target.WHOLE_TOP:
			changes[&"movable_2d_whole_face"] = false if turning_off else not box.movable_2d_whole_face
	return changes


func refusal_for(hit: GridPicker.Hit) -> String:
	if not hit.has_box:
		return ""
	if hit.box.is_terrain():
		return "Terrain never moves, so its handles do nothing."
	if target_of(hit) == Target.WHOLE_TOP and hit.box.walkable and not hit.box.movable_2d_whole_face:
		return "A walkable top can't be grabbed whole: pick its edges instead."
	if target_of(hit) == Target.NOTHING:
		return "Bottom faces have no handles."
	return ""


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.alt_pressed:
		screen.pick_from(hit)
		return
	if not hit.has_box or not refusal_for(hit).is_empty():
		return
	var turning_off := event.button_index == MOUSE_BUTTON_RIGHT
	var boxes := _boxes_reached(hit, event.shift_pressed)
	var changes_per_box: Dictionary[Box, Dictionary] = {}
	var reference := change_for(hit, hit.box, turning_off)
	for box in boxes:
		var changes: Dictionary[StringName, bool] = {}
		for flag in reference:
			changes[flag] = reference[flag]
		changes_per_box[box] = changes
	edits().set_flags_per_box(changes_per_box, _describe_change(hit, reference))


## Con Shift, todas las cajas del grupo cuyo mismo lado o borde da afuera del grupo.
func _boxes_reached(hit: GridPicker.Hit, whole_group: bool) -> Array[Box]:
	if not whole_group:
		return [hit.box]
	var group := edits().boxes_of_group_of(hit.box)
	var cells: Dictionary[Vector3i, bool] = {}
	for box in group:
		cells[box.world_cell] = true
	var outward := hit.normal
	if target_of(hit) == Target.EDGE_2D:
		var direction := Box.FACING_DIRECTION[hit.top_edge as Box.Facing]
		outward = Vector3i(direction.x, direction.y, 0)
	var reached: Array[Box] = []
	for box in group:
		if box.is_terrain():
			continue
		if target_of(hit) == Target.WHOLE_TOP or target_of(hit) == Target.EDGE_2D:
			if cells.has(box.world_cell + LevelIndex.GRID_UP):
				continue
		if outward.z == 0 and cells.has(box.world_cell + outward):
			continue
		reached.append(box)
	return reached


func _describe_change(hit: GridPicker.Hit, changes: Dictionary[StringName, bool]) -> String:
	match target_of(hit):
		Target.SIDE_3D:
			return "%s 3D handle %s" % ["Turn on" if changes.values()[0] else "Turn off", FACING_TEXT[SIDE_OF_NORMAL[hit.normal]]]
		Target.EDGE_2D:
			return "Toggle 2D handle %s" % FACING_TEXT[hit.top_edge as Box.Facing]
	return "%s 2D whole top" % ("Turn on" if changes.get(&"movable_2d_whole_face", false) else "Turn off")


func draw(preview: LevelEditorPreview) -> void:
	refusal = refusal_for(_hover_hit)
	if not _hover_hit.has_box:
		return
	var colour := LevelEditorPreview.RED if not refusal.is_empty() else LevelEditorPreview.ORANGE
	var boxes: Array = _boxes_reached(_hover_hit, Input.is_key_pressed(KEY_SHIFT)) if refusal.is_empty() else [_hover_hit.box]
	# Un clic le pone a todas lo que le haría a la apuntada: el dibujo muestra eso mismo.
	var turning_on := change_for(_hover_hit, _hover_hit.box, false).values().has(true)
	for box: Box in boxes:
		var cell := index().cell_of(box)
		var shown := colour if turning_on or not refusal.is_empty() else Color(0.35, 0.35, 0.38, 0.7)
		match target_of(_hover_hit):
			Target.SIDE_3D:
				preview.highlight_face(cell, _hover_hit.face, shown)
			Target.EDGE_2D:
				preview.highlight_top_strip(cell, _hover_hit.top_edge as Box.Facing, 0.15, shown)
			Target.WHOLE_TOP:
				preview.highlight_top_middle(cell, shown)
			Target.NOTHING:
				preview.highlight_face(cell, _hover_hit.face, LevelEditorPreview.RED)


func status() -> String:
	if not _hover_hit.has_box or not refusal_for(_hover_hit).is_empty():
		return ""
	var changes := change_for(_hover_hit, _hover_hit.box, false)
	match target_of(_hover_hit):
		Target.SIDE_3D:
			return "3D handle %s: %s" % [FACING_TEXT[SIDE_OF_NORMAL[_hover_hit.normal]], "off → on" if changes.values()[0] else "on → off"]
		Target.EDGE_2D:
			return "2D handle %s: %s" % [FACING_TEXT[_hover_hit.top_edge as Box.Facing], "off → on" if changes.get(BoxBrush.EDGE_FLAG_2D[_hover_hit.top_edge as Box.Facing], false) else "on → off"]
		Target.WHOLE_TOP:
			return "2D whole top: %s" % ("off → on" if changes[&"movable_2d_whole_face"] else "on → off")
	return ""


func hint() -> String:
	return "Left: toggle · Right: turn off · Shift: the whole group · Side face: 3D · Top edge: 2D · Middle of the top: whole top"
