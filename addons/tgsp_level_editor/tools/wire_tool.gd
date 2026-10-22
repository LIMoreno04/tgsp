@tool
class_name WireTool
extends LevelEditorTool
## Dibuja cables arrastrando por las caras: cada cara libre del camino recibe un cable, y cada dos caras
## seguidas quedan unidas por los dos lados, también un botón o una puerta al final. Si el mouse se
## salta caras, se completa el camino más corto. El botón derecho borra cables.

const MOST_FACES_BETWEEN := 8

var _path: Array[FaceLinks.FaceAt] = []
var _erasing := false
## Shift al borrar: los vecinos siguen apuntando ahí, para una conexión que se arma jugando.
var _keeping_the_arms := false
var _pieces_to_erase: Array[Powerable] = []
var _pressed_on_a_piece: Powerable
var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()
## Si el mouse está en una cara a la que el cable no llega desde su punta.
var _out_of_reach := false


func _init(the_screen: LevelEditorScreen) -> void:
	super(the_screen)
	title = "Wire"
	tooltip = "Drag across faces to lay wire. Each two faces in a row get connected on both sides, pieces at the ends included."


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit


func _face_of(hit: GridPicker.Hit) -> FaceLinks.FaceAt:
	return FaceLinks.FaceAt.new(hit.cell, hit.face)


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.alt_pressed:
		screen.pick_from(hit)
		return
	if not hit.has_box:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_erasing = true
		_keeping_the_arms = event.shift_pressed
		_pieces_to_erase = []
		_take_wire(hit)
		return
	_path = [_face_of(hit)]
	_out_of_reach = false
	_pressed_on_a_piece = hit.box.powerable_on(hit.face)


func drag(hit: GridPicker.Hit, _event: InputEventMouseMotion) -> void:
	if not hit.has_box:
		return
	if _erasing:
		_take_wire(hit)
		return
	if _path.is_empty():
		return
	var here := _face_of(hit)
	var last := _path[_path.size() - 1]
	if here.same_as(last):
		return
	if _path.size() >= 2 and here.same_as(_path[_path.size() - 2]):
		_path.pop_back()
		return
	if not FaceLinks.link(last, here, screen.perspective()).is_empty():
		_path.append(here)
		_out_of_reach = false
		return
	var between := FaceLinks.shortest_path(last, here, index(), screen.perspective(), MOST_FACES_BETWEEN)
	_path.append_array(between)
	_out_of_reach = between.is_empty()


func _take_wire(hit: GridPicker.Hit) -> void:
	var piece := hit.box.powerable_on(hit.face)
	if piece is Wire and not _pieces_to_erase.has(piece):
		_pieces_to_erase.append(piece)


func release(_hit: GridPicker.Hit, _event: InputEventMouseButton) -> void:
	if _erasing:
		_erasing = false
		edits().erase([], _pieces_to_erase, _keeping_the_arms)
		_pieces_to_erase = []
		screen.forget_freed_selection()
		return
	if _path.is_empty():
		return
	if _path.size() == 1 and _pressed_on_a_piece != null:
		screen.select([], [_pressed_on_a_piece])
	else:
		edits().lay_wire(_path, screen.perspective())
	_path = []
	_out_of_reach = false
	_pressed_on_a_piece = null


func cancel() -> bool:
	var was := not _path.is_empty() or _erasing
	_path = []
	_out_of_reach = false
	_erasing = false
	_pieces_to_erase = []
	return was


func draw(preview: LevelEditorPreview) -> void:
	refusal = "Wire can't get there from its end in this view: go back toward it." if _out_of_reach and not _path.is_empty() else ""
	if _erasing:
		for piece in _pieces_to_erase:
			if edits().is_in_the_level(piece):
				preview.highlight_face(index().cell_of(piece.box), piece.face, LevelEditorPreview.RED)
		return
	var path: Array = _path if not _path.is_empty() else ([_face_of(_hover_hit)] if _hover_hit.has_box else [])
	var directions := _directions_along(path)
	for i in path.size():
		var at: FaceLinks.FaceAt = path[i]
		preview.highlight_face(at.cell, at.face, LevelEditorPreview.BLUE)
		var existing := edits().piece_at(at, {})
		var options := {}
		for direction: Vector3i in directions[i]:
			options[LevelEdits.CONNECTS[direction]] = true
		if existing == null:
			preview.ghost_piece(LevelEdits.PIECE_SCENE[&"Wire"], at.cell, at.face, options)
		_draw_arms(preview, at, directions[i])


## Las direcciones que va a tener cada cara del camino.
func _directions_along(path: Array) -> Array[Array]:
	var directions: Array[Array] = []
	for i in path.size():
		directions.append([])
	for i in range(1, path.size()):
		var link := FaceLinks.link(path[i - 1], path[i], screen.perspective())
		if link.is_empty():
			continue
		directions[i - 1].append(link[0])
		directions[i].append(link[1])
	if path.size() == 1:
		for direction in edits().directions_toward_pieces_pointing_at(path[0], {}):
			directions[0].append(direction)
	return directions


func _draw_arms(preview: LevelEditorPreview, at: FaceLinks.FaceAt, directions: Array) -> void:
	var centre := Vector3(at.cell) + Vector3(0.5, 0.5, 0.5) + Vector3(at.normal()) * 0.52
	for direction: Vector3i in directions:
		preview.line(centre, centre + Vector3(direction) * 0.5, Color(1.0, 0.25, 0.2, 0.95))


func status() -> String:
	if _erasing:
		return "Erase %d wire%s%s" % [_pieces_to_erase.size(), "" if _pieces_to_erase.size() == 1 else "s", ", keeping the arms that point at them" if _keeping_the_arms else ""]
	if not _path.is_empty():
		var pieces := PackedStringArray()
		for at in _path:
			var piece := edits().piece_at(at, {})
			if piece != null and not piece is Wire:
				pieces.append(LevelEdits.piece_label(LevelEdits.piece_type(piece)))
		var text := "Wire across %d face%s" % [_path.size(), "" if _path.size() == 1 else "s"]
		if not pieces.is_empty():
			text += " · connects " + " and ".join(pieces)
		return text
	if _hover_hit.has_box:
		var piece := _hover_hit.box.powerable_on(_hover_hit.face)
		if piece != null:
			return "Click: select this %s · Drag: connect it" % LevelEdits.piece_label(LevelEdits.piece_type(piece))
		return "Wire on the %s of %s" % [LevelEditorPropertiesPanel._face_name(_hover_hit.face).to_lower(), describe(_hover_hit.cell)]
	return ""


func hint() -> String:
	return "Left + drag: lay wire across faces · Click a piece: select it · Right + drag: erase wires (Shift: keep the arms pointing at them)"
