@tool
class_name EraserTool
extends LevelEditorTool
## Borra lo que está arriba bajo el mouse: el powerable de la cara apuntada si hay uno, si no la caja.
## Un trazo borra a lo largo de su capa.

var _stroking := false
var _stroke_layer := 0
var _boxes: Array[Box] = []
var _pieces: Array[Powerable] = []
var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()


func _init(the_screen: LevelEditorScreen) -> void:
	super(the_screen)
	title = "Eraser"
	tooltip = "Erase what's under the mouse: the piece on the face you point at, or else the box. Drag to erase more."


func plane_z() -> int:
	return _stroke_layer + 1 if _stroking else 0


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit


func press(hit: GridPicker.Hit, _event: InputEventMouseButton) -> void:
	if not hit.has_box:
		return
	_stroking = true
	_stroke_layer = hit.cell.z
	_boxes = []
	_pieces = []
	_take(hit)


func drag(hit: GridPicker.Hit, _event: InputEventMouseMotion) -> void:
	if _stroking:
		_take(hit)


func _take(hit: GridPicker.Hit) -> void:
	if not hit.has_box:
		return
	var piece := hit.box.powerable_on(hit.face)
	if piece != null:
		if not _pieces.has(piece):
			_pieces.append(piece)
		return
	if hit.cell.z != _stroke_layer:
		return
	if not _boxes.has(hit.box):
		_boxes.append(hit.box)


func release(_hit: GridPicker.Hit, _event: InputEventMouseButton) -> void:
	if not _stroking:
		return
	_stroking = false
	edits().erase(_boxes, _pieces)
	_boxes = []
	_pieces = []
	screen.forget_freed_selection()


func cancel() -> bool:
	var was := _stroking
	_stroking = false
	_boxes = []
	_pieces = []
	return was


func draw(preview: LevelEditorPreview) -> void:
	if _stroking:
		# Un deshacer a mitad del trazo pudo sacar algo de lo juntado: eso ya no se dibuja.
		for box in _boxes:
			if edits().is_in_the_level(box):
				preview.tint_cell(index().cell_of(box), LevelEditorPreview.RED)
		for piece in _pieces:
			if edits().is_in_the_level(piece):
				preview.highlight_face(index().cell_of(piece.box), piece.face, LevelEditorPreview.RED)
		return
	if not _hover_hit.has_box:
		return
	if _hover_hit.box.powerable_on(_hover_hit.face) != null:
		preview.highlight_face(_hover_hit.cell, _hover_hit.face, LevelEditorPreview.RED)
	else:
		preview.tint_cell(_hover_hit.cell, LevelEditorPreview.RED)


func status() -> String:
	if _stroking:
		return "Erase %d box%s and %d piece%s" % [_boxes.size(), "" if _boxes.size() == 1 else "es", _pieces.size(), "" if _pieces.size() == 1 else "s"]
	if not _hover_hit.has_box:
		return ""
	var piece := _hover_hit.box.powerable_on(_hover_hit.face)
	if piece != null:
		return "Erase the %s on this face" % LevelEdits.piece_label(LevelEdits.piece_type(piece))
	if edits().is_shell_part(_hover_hit.box.get_parent()):
		return "Make a hole in the room shell at %s (undo, or a Floor or Wall box, fills it)" % describe(_hover_hit.cell)
	return "Erase the box at %s" % describe(_hover_hit.cell)


func hint() -> String:
	return "Left or right: erase · Drag: erase along the layer"
