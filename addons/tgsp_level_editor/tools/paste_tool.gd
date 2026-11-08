@tool
class_name PasteTool
extends LevelEditorTool
## Lo copiado sigue al mouse como fantasma, con su esquina baja en la celda apuntada; un clic lo pone
## como Structures nuevas en la carpeta actual, Esc vuelve a la herramienta de antes. Shift + clic lo pone
## y sigue pegando, para sellar la misma pieza varias veces.

var clip: LevelEdits.Clip
var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()
var _at := Vector3i.ZERO
var _has_target := false


func _init(the_screen: LevelEditorScreen) -> void:
	super(the_screen)
	title = "Paste"
	tooltip = "Click to place the copy."


func build_options(bar: HBoxContainer) -> void:
	caption(bar, "Pasting %d structure%s · click to place · Shift + click to place and keep pasting · Esc to cancel" % [clip.structures.size(), "" if clip.structures.size() == 1 else "s"])


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit
	_has_target = false
	if screen.layer_mode and hit.has_plane_cell:
		_at = hit.plane_cell
		_has_target = true
	elif hit.has_box:
		_at = hit.cell_against
		_has_target = true
	elif hit.has_plane_cell:
		_at = hit.plane_cell
		_has_target = true


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	hover(hit)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		screen.stop_pasting()
		return
	if not _has_target or not edits().can_paste(clip, _at):
		return
	var pasted := edits().paste(clip, _at, screen.current_folder())
	if event.shift_pressed:
		screen.flash("Pasted. Click again for another copy, Esc to stop.")
		return
	screen.stop_pasting()
	var boxes: Array[Box] = []
	for structure in pasted:
		boxes.append_array(structure.boxes())
	screen.select(boxes, [])


func cancel() -> bool:
	screen.stop_pasting.call_deferred()
	return true


func draw(preview: LevelEditorPreview) -> void:
	refusal = ""
	if not _has_target or clip == null:
		return
	var fits := edits().can_paste(clip, _at)
	if not fits:
		refusal = "Something is in the way."
	# Fantasmas de verdad mientras sean pocos y quepan; si no, celdas teñidas, que cuestan menos.
	var as_ghosts := fits and clip.cells.size() <= BoxBrushTool.MOST_GHOSTS
	for structure in clip.structures:
		for box_data: Dictionary in structure["boxes"]:
			var cell: Vector3i = box_data["cell"] + _at
			if as_ghosts:
				var flags: Dictionary[StringName, bool] = {}
				flags.assign(box_data["flags"])
				preview.ghost_box(cell, flags)
			else:
				preview.tint_cell(cell, LevelEditorPreview.BLUE if fits else LevelEditorPreview.RED, 0.0)
			preview.outline_cell(cell, Color(0.3, 0.65, 1.0, 0.8) if fits else Color(1.0, 0.3, 0.25, 0.9), 0.0)
		if as_ghosts:
			for piece_data: Dictionary in structure["pieces"]:
				preview.ghost_piece(LevelEdits.PIECE_SCENE[piece_data["type"]], piece_data["cell"] + _at, piece_data["face"], piece_data["properties"])


func status() -> String:
	return "Paste at %s" % describe(_at) if _has_target else ""


func hint() -> String:
	return "Left: place the copy · Shift + left: place it and keep pasting · Right or Esc: stop"
