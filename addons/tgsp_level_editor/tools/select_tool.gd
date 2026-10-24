@tool
class_name SelectTool
extends LevelEditorTool
## Elige: un clic elige la Structure (en la cáscara, sólo la caja), doble clic sólo la caja, Shift suma o
## saca. Arrastrar desde el vacío o desde la cáscara (que no se mueve) elige con un rectángulo, que
## deja la cáscara afuera; arrastrar algo elegido lo mueve por su capa, y + y − lo suben y bajan mientras.

## ON_THE_SHELL: apretado en una caja de la cáscara; soltar sin moverse la elige, moverse hace un rectángulo.
enum Mode { NONE, PRESSED, MOVING, RECTANGLE, ON_THE_SHELL }

## Cuánto tiene que moverse el mouse para que un clic sea un arrastre.
const DRAG_PIXELS := 5.0

var _mode := Mode.NONE
var _press_position := Vector2.ZERO
var _press_hit: GridPicker.Hit
var _move_layer := 0
var _move_from := Vector3i.ZERO
var _step := Vector3i.ZERO
var _lift := 0
var _toggle_on_release: Array[Box] = []
var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()
var _shell_box_pressed: Box
var _adding_on_press := false


func _init(the_screen: LevelEditorScreen) -> void:
	super(the_screen)
	title = "Select"
	tooltip = "Click a structure to select it, double-click a box for just that box, Shift to add. Drag to move; + and − lift it."


func plane_z() -> int:
	return _move_layer + 1 if _mode == Mode.PRESSED or _mode == Mode.MOVING else 0


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit


## Lo que un clic en esa caja elige: su Structure, o ella sola si es de la cáscara o está suelta.
func what_a_click_selects(box: Box) -> Array[Box]:
	var structure := box.get_parent() as Structure
	if structure == null or edits().is_shell_part(structure):
		return [box]
	return structure.boxes()


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.alt_pressed:
		screen.pick_from(hit)
		return
	_press_position = event.position
	_press_hit = hit
	_toggle_on_release = []
	if event.ctrl_pressed and hit.has_box and hit.box.powerable_on(hit.face) != null:
		screen.select([], [hit.box.powerable_on(hit.face)])
		return
	_adding_on_press = event.shift_pressed
	if not hit.has_box:
		if not event.shift_pressed:
			screen.clear_selection()
		_mode = Mode.RECTANGLE
		return
	if edits().is_shell_part(hit.box.get_parent()):
		_shell_box_pressed = hit.box
		_mode = Mode.ON_THE_SHELL
		return
	var clicked: Array = [hit.box] if event.double_click else what_a_click_selects(hit.box)
	var boxes: Array[Box] = []
	boxes.assign(clicked)
	if event.shift_pressed:
		if screen.is_selected(hit.box):
			_toggle_on_release = boxes
		else:
			screen.add_to_selection(boxes)
	elif event.double_click or not screen.is_selected(hit.box):
		screen.select(boxes, [])
	_mode = Mode.PRESSED
	_move_layer = hit.cell.z
	_move_from = hit.cell
	_step = Vector3i.ZERO
	_lift = 0


func drag(hit: GridPicker.Hit, event: InputEventMouseMotion) -> void:
	match _mode:
		Mode.PRESSED:
			if event.position.distance_to(_press_position) >= DRAG_PIXELS:
				_mode = Mode.MOVING
				_toggle_on_release = []
				_follow(hit)
		Mode.MOVING:
			_follow(hit)
		Mode.ON_THE_SHELL:
			if event.position.distance_to(_press_position) >= DRAG_PIXELS:
				if not _adding_on_press:
					screen.clear_selection()
				_mode = Mode.RECTANGLE
				drag(hit, event)
		Mode.RECTANGLE:
			screen.view.marquee = Rect2(_press_position, event.position - _press_position).abs()
			screen.view.redraw_on_top()
			screen.redraw()


func _follow(hit: GridPicker.Hit) -> void:
	if not hit.has_plane_cell:
		return
	var on_layer := hit.plane_cell - Vector3i(0, 0, 1)
	_step = Vector3i(on_layer.x - _move_from.x, on_layer.y - _move_from.y, _lift)


func key(event: InputEventKey) -> bool:
	if _mode != Mode.MOVING:
		return false
	if LevelEditorScreen.is_plus(event):
		_lift += 1
	elif LevelEditorScreen.is_minus(event):
		_lift -= 1
	else:
		return false
	_step.z = _lift
	screen.redraw()
	return true


func release(_hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	match _mode:
		Mode.PRESSED:
			if not _toggle_on_release.is_empty():
				screen.remove_from_selection(_toggle_on_release)
		Mode.MOVING:
			if _step != Vector3i.ZERO and refusal.is_empty():
				edits().move(screen.selected_boxes, _step)
		Mode.RECTANGLE:
			_select_inside(screen.view.marquee, _adding_on_press or event.shift_pressed)
			screen.view.marquee = Rect2()
			screen.view.redraw_on_top()
		Mode.ON_THE_SHELL:
			_click_on_a_shell_box(_shell_box_pressed, _adding_on_press)
	_mode = Mode.NONE
	_toggle_on_release = []
	_shell_box_pressed = null


## Un clic en la cáscara elige sólo esa caja; con Shift la suma o la saca.
func _click_on_a_shell_box(box: Box, adding: bool) -> void:
	if box == null or not is_instance_valid(box):
		return
	if not adding:
		screen.select([box], [])
	elif screen.is_selected(box):
		screen.remove_from_selection([box])
	else:
		screen.add_to_selection([box])


func _select_inside(area: Rect2, adding: bool) -> void:
	if area.size.length() < DRAG_PIXELS:
		return
	var boxes := boxes_inside(area)
	if adding:
		screen.add_to_selection(boxes)
	else:
		screen.select(boxes, [])


## Las Structures (y cajas sueltas) con alguna caja a la vista dentro del rectángulo. La cáscara no: un
## rectángulo y Delete harían agujeros en todo el piso.
func boxes_inside(area: Rect2) -> Array[Box]:
	var chosen: Dictionary[Box, bool] = {}
	for box: Box in index().cells_3D.values():
		if chosen.has(box) or not screen.view.is_box_visible(box) or edits().is_shell_part(box.get_parent()):
			continue
		var cell := index().cell_of(box)
		if screen.view.is_behind_the_camera(cell) or not area.has_point(screen.view.cell_on_screen(cell)):
			continue
		for each in what_a_click_selects(box):
			chosen[each] = true
	var boxes: Array[Box] = []
	boxes.assign(chosen.keys())
	return boxes


func cancel() -> bool:
	var was := _mode != Mode.NONE
	_mode = Mode.NONE
	_shell_box_pressed = null
	_step = Vector3i.ZERO
	screen.view.marquee = Rect2()
	screen.view.redraw_on_top()
	return was


func draw(preview: LevelEditorPreview) -> void:
	refusal = ""
	if _mode == Mode.MOVING:
		var boxes := screen.selected_boxes
		var blocked := not edits().can_move(boxes, _step)
		for box in boxes:
			if edits().is_shell_part(box.get_parent()):
				refusal = "The shell's boxes don't move: erase them and paint new ones."
		if blocked and refusal.is_empty():
			refusal = "Something is in the way."
		for box in boxes:
			if not edits().is_in_the_level(box):
				continue
			var destination := index().cell_of(box) + _step
			preview.tint_cell(destination, LevelEditorPreview.RED if blocked else LevelEditorPreview.BLUE, 0.0)
		return
	if _mode == Mode.RECTANGLE:
		for box in boxes_inside(screen.view.marquee):
			if not screen.is_selected(box):
				preview.outline_cell(index().cell_of(box), Color(0.45, 0.75, 1.0, 0.9))
		return
	if _mode == Mode.NONE and _hover_hit.has_box:
		if Input.is_key_pressed(KEY_CTRL) and _hover_hit.box.powerable_on(_hover_hit.face) != null:
			preview.highlight_face(_hover_hit.cell, _hover_hit.face, Color(1, 1, 1, 0.35))
			return
		for box in what_a_click_selects(_hover_hit.box):
			if not screen.is_selected(box):
				preview.outline_cell(index().cell_of(box), Color(1, 1, 1, 0.45))


func status() -> String:
	if _mode == Mode.RECTANGLE:
		var inside := boxes_inside(screen.view.marquee).size()
		return "%s %d box%s (the room shell stays out)" % ["Add" if _adding_on_press else "Select", inside, "" if inside == 1 else "es"]
	if _mode == Mode.MOVING:
		return "Move %d box%s by %s" % [screen.selected_boxes.size(), "" if screen.selected_boxes.size() == 1 else "es", describe(_step)]
	if _hover_hit.has_box:
		var piece := _hover_hit.box.powerable_on(_hover_hit.face)
		if piece != null and Input.is_key_pressed(KEY_CTRL):
			return "Ctrl + click: select this %s" % LevelEdits.piece_label(LevelEdits.piece_type(piece))
		var structure := _hover_hit.box.get_parent()
		var boxes := what_a_click_selects(_hover_hit.box)
		if edits().is_shell_part(structure):
			return "Room shell: %s box at %s · click: just this box · drag: rectangle" % ["floor" if structure.name == RoomShell.FLOOR else "wall", describe(_hover_hit.cell)]
		if structure is Structure:
			return "%s · %d box%s · %s" % [structure.name, boxes.size(), "" if boxes.size() == 1 else "es", BoxBrush.label_of_structure(boxes)]
		return "Loose box at %s" % describe(_hover_hit.cell)
	return ""


func hint() -> String:
	return "Click: structure · Double-click: box · Ctrl + click: piece · Shift: add · Drag: move (+ − lift) · Drag on the floor: rectangle · Ctrl + D: deselect"
