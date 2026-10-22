@tool
class_name PieceTool
extends LevelEditorTool
## Pone un powerable de un tipo en la cara apuntada: botón, placa, puerta, salida, emisor o receptor.
## Las puertas van en el borde de la tapa más cercano al mouse. Una cara ocupada se elige con un clic;
## el botón derecho borra el powerable de la cara.

const TITLE: Dictionary[StringName, String] = {
	&"ButtonPowerable": "Button",
	&"PressurePlate": "Plate",
	&"Door": "Door",
	&"ExitDoor": "Exit",
	&"LaserEmitter": "Laser emitter",
	&"LaserReceiver": "Laser receiver",
}
const TOOLTIPS: Dictionary[StringName, String] = {
	&"ButtonPowerable": "A button, on a top (on a pedestal) or on a side (on a short stand). E switches it.",
	&"PressurePlate": "A plate on a top: on while something stands on it.",
	&"Door": "A door on an edge of a top: open while powered.",
	&"ExitDoor": "The green exit door: crossing it open ends the level.",
	&"LaserEmitter": "A laser emitter on a side: shines while powered, or always.",
	&"LaserReceiver": "A laser receiver on a side: on while a beam ends on it.",
}

var type: StringName
var options := {}
var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()


func _init(the_screen: LevelEditorScreen, piece_type: StringName) -> void:
	super(the_screen)
	type = piece_type
	title = TITLE[type]
	tooltip = TOOLTIPS[type]
	reset_options()


func reset_options() -> void:
	options = {}
	match type:
		&"ButtonPowerable":
			options[&"switched_on"] = false
		&"Door":
			options[&"always_open"] = false
		&"ExitDoor":
			options[&"always_open"] = false
			options[&"next_level"] = ""
		&"LaserEmitter":
			options[&"always_on"] = false


func use_options(picked: Dictionary) -> void:
	reset_options()
	for option in picked:
		if options.has(option):
			options[option] = picked[option]


func build_options(bar: HBoxContainer) -> void:
	caption(bar, title)
	gap(bar)
	match type:
		&"ButtonPowerable":
			toggle(bar, "Starts on", options[&"switched_on"], "The level starts with this button switched on.", _set_option.bind(&"switched_on"))
		&"Door":
			toggle(bar, "Always open", options[&"always_open"], "Open without any power.", _set_option.bind(&"always_open"))
		&"ExitDoor":
			toggle(bar, "Always open", options[&"always_open"], "Open without any power. Careful: an open door isn't drawn in the game.", _set_option.bind(&"always_open"))
			caption(bar, "Leads to")
			bar.add_child(screen.level_picker(options[&"next_level"], _set_next_level))
		&"LaserEmitter":
			toggle(bar, "Always on", options[&"always_on"], "Shines without any power.", _set_option.bind(&"always_on"))
		_:
			caption(bar, "Goes on a top face" if type == &"PressurePlate" else "Goes on a side face")


func _set_option(on: bool, option: StringName) -> void:
	options[option] = on
	screen.redraw()

func _set_next_level(path: String) -> void:
	options[&"next_level"] = path


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit


## Si no puede ir en la cara apuntada, por qué.
func refusal_for(hit: GridPicker.Hit) -> String:
	if not hit.has_box or hit.box.powerable_on(hit.face) != null:
		return ""
	var faces: Array = LevelEdits.PIECE_FACES[type]
	if faces.has(hit.face):
		return ""
	if not faces.has(Powerable.Face.TOP):
		return "%ss only go on side faces%s" % [title, ": switch to 3D to point at one" if screen.view.is_2d else ""]
	if faces.size() == 1:
		return "%ss only go on top faces" % title
	return "A %s can't go on a bottom face" % title.to_lower()


func _options_here(hit: GridPicker.Hit) -> Dictionary:
	var here := options.duplicate()
	if type == &"Door" or type == &"ExitDoor":
		here[&"edge"] = GridPicker.nearest_top_edge(hit.on_face)
	return here


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.alt_pressed:
		screen.pick_from(hit)
		return
	if not hit.has_box:
		return
	var existing := hit.box.powerable_on(hit.face)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if existing != null:
			edits().erase([], [existing])
			screen.forget_freed_selection()
		return
	if existing != null:
		screen.select([], [existing])
		return
	if not refusal_for(hit).is_empty():
		return
	var placed := edits().place_piece(type, hit.box, hit.face, _options_here(hit))
	if placed != null:
		screen.select([], [placed])


func draw(preview: LevelEditorPreview) -> void:
	refusal = refusal_for(_hover_hit)
	if not _hover_hit.has_box:
		return
	var existing := _hover_hit.box.powerable_on(_hover_hit.face)
	if existing != null:
		preview.highlight_face(_hover_hit.cell, _hover_hit.face, Color(1, 1, 1, 0.3))
		return
	if not refusal.is_empty():
		preview.highlight_face(_hover_hit.cell, _hover_hit.face, LevelEditorPreview.RED)
		return
	var here := _options_here(_hover_hit)
	for direction in edits().directions_toward_pieces_pointing_at(FaceLinks.FaceAt.new(_hover_hit.cell, _hover_hit.face), {}):
		here[LevelEdits.CONNECTS[direction]] = true
	if here.has(&"edge"):
		preview.highlight_top_strip(_hover_hit.cell, here[&"edge"], 0.15, LevelEditorPreview.BLUE)
	else:
		preview.highlight_face(_hover_hit.cell, _hover_hit.face, Color(0.25, 0.6, 1.0, 0.18))
	preview.ghost_piece(LevelEdits.PIECE_SCENE[type], _hover_hit.cell, _hover_hit.face, here)


func status() -> String:
	if not _hover_hit.has_box:
		return ""
	var existing := _hover_hit.box.powerable_on(_hover_hit.face)
	if existing != null:
		return "Click: select this %s · Right-click: erase it" % LevelEdits.piece_label(LevelEdits.piece_type(existing))
	if not refusal_for(_hover_hit).is_empty():
		return ""
	var face_name := LevelEditorPropertiesPanel._face_name(_hover_hit.face).to_lower()
	var text := "%s on the %s of %s" % [title, face_name, describe(_hover_hit.cell)]
	if type == &"Door" or type == &"ExitDoor":
		text = "%s on the %s edge of %s" % [title, FACING_TEXT[GridPicker.nearest_top_edge(_hover_hit.on_face)], describe(_hover_hit.cell)]
		if index().cells_3D.has(_hover_hit.cell + LevelIndex.GRID_UP):
			text += " · a box stands in its cell, so it will be held open"
	var arms := edits().directions_toward_pieces_pointing_at(FaceLinks.FaceAt.new(_hover_hit.cell, _hover_hit.face), {}).size()
	if arms > 0:
		text += " · connects to the %d neighbour%s pointing at it" % [arms, "" if arms == 1 else "s"]
	return text


func hint() -> String:
	return "Left: place · Click a piece: select it · Right: erase the piece on that face · Alt + click: pick"
