@tool
class_name PickTool
extends LevelEditorTool
## El cuentagotas: copia en la brocha las banderas exactas de una caja, o en su herramienta las de un
## powerable, y vuelve a esa herramienta. Alt + clic hace lo mismo desde cualquier brocha.

var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()


func _init(the_screen: LevelEditorScreen) -> void:
	super(the_screen)
	title = "Pick"
	tooltip = "Copy a box's exact settings into a brush, or a piece's into its tool. Alt + click does it from any brush."


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		screen.pick_from(hit)


func draw(preview: LevelEditorPreview) -> void:
	if not _hover_hit.has_box:
		return
	var piece := _hover_hit.box.powerable_on(_hover_hit.face)
	if piece != null:
		preview.highlight_face(_hover_hit.cell, _hover_hit.face, LevelEditorPreview.GREEN)
	else:
		preview.outline_cell(_hover_hit.cell, Color(0.3, 0.9, 0.4, 0.95))


func status() -> String:
	return describe_pick(_hover_hit)


static func describe_pick(hit: GridPicker.Hit) -> String:
	if not hit.has_box:
		return ""
	var piece := hit.box.powerable_on(hit.face)
	if piece != null:
		return "Pick: %s" % LevelEdits.piece_label(LevelEdits.piece_type(piece))
	var settings := PackedStringArray()
	if hit.box.walkable:
		settings.append("walkable")
	if hit.box.is_terrain():
		settings.append("terrain")
	if hit.box.movable_3d_from_any_side():
		settings.append("grab in 3D")
	if hit.box.movable_2d_whole_face:
		settings.append("2D whole top")
	for facing: Box.Facing in BoxBrush.EDGE_FLAG_2D:
		if hit.box.get(BoxBrush.EDGE_FLAG_2D[facing]):
			settings.append("2D edge " + FACING_TEXT[facing])
	if hit.box.keeps_height:
		settings.append("keeps height")
	var group := hit.box.get_parent()
	return "Pick: %s box (%s)" % [group.name if group is Structure else "loose", ", ".join(settings) if not settings.is_empty() else "nothing on"]


func hint() -> String:
	return "Left: pick these settings and go back to that tool"
