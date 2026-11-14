@tool
class_name SpawnTool
extends LevelEditorTool
## Dónde empieza el jugador: sobre la tapa apuntada. Verde si puede empezar ahí en la vista con la que
## empieza el nivel (la misma cuenta que el aviso del Room), rojo si no.

var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()


func _init(the_screen: LevelEditorScreen) -> void:
	super(the_screen)
	title = "Spawn"
	tooltip = "Click a top to make the player start standing on it."


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit


func spawn_for(hit: GridPicker.Hit) -> Array[Vector3i]:
	if not hit.has_box or hit.face != Powerable.Face.TOP:
		return []
	return [hit.cell + LevelIndex.GRID_UP]


func can_start_at(cell: Vector3i) -> bool:
	var perspective := screen.starting_perspective()
	return index().can_player_be_on(cell, perspective) and not index().has_button_on(Vector2i(cell.x, cell.y), perspective, cell.z)


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var spawn := spawn_for(hit)
	if spawn.is_empty() or not can_start_at(spawn[0]):
		return
	edits().set_spawn(spawn[0])


func draw(preview: LevelEditorPreview) -> void:
	refusal = ""
	var spawn := spawn_for(_hover_hit)
	if spawn.is_empty():
		if _hover_hit.has_box:
			refusal = "Point at a top."
		return
	var fits := can_start_at(spawn[0])
	if not fits:
		refusal = "The player can't start there in the starting view."
	screen.draw_player_marker(preview, spawn[0], LevelEditorPreview.GREEN if fits else LevelEditorPreview.RED)


func status() -> String:
	var spawn := spawn_for(_hover_hit)
	if spawn.is_empty() or not can_start_at(spawn[0]):
		return ""
	return "Start the player at %s" % describe(spawn[0])


func hint() -> String:
	return "Left: the player starts here"
