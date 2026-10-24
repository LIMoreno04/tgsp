@tool
class_name BoxBrushTool
extends LevelEditorTool
## Pinta cajas de un tipo. Un trazo hace una Structure nueva; con Shift al empezar sobre una caja, suma a la
## Structure de esa caja. El botón derecho borra cajas; Ctrl + trazo les pone las banderas de la brocha.

enum Stroke { NONE, PAINT, ERASE, REPAINT }

## Más que esto y el trazo se dibuja como prismas en vez de fantasmas.
const MOST_GHOSTS := 64

var kind := BoxBrush.Kind.BLOCK
var brush: BoxBrush = BoxBrush.for_kind(BoxBrush.Kind.BLOCK)

var _stroke := Stroke.NONE
var _stroke_layer := 0
var _start := Vector3i.ZERO
var _last := Vector3i.ZERO
var _base_cells: Array[Vector3i] = []
var _extending: Structure
var _boxes: Array[Box] = []
var _hover_target := Vector3i.ZERO
var _hover_has_target := false
var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()


func _init(the_screen: LevelEditorScreen, brush_kind: BoxBrush.Kind) -> void:
	super(the_screen)
	kind = brush_kind
	title = BoxBrush.LABEL[kind]
	tooltip = BoxBrush.TOOLTIP[kind]
	reset_options()


func reset_options() -> void:
	brush = BoxBrush.for_kind(kind)


func use_brush(picked: BoxBrush) -> void:
	brush = picked.copy()


#==================Las opciones==================

var _whole_top_button: Button
var _edge_buttons: Dictionary[Box.Facing, Button] = {}


func build_options(bar: HBoxContainer) -> void:
	caption(bar, brush.label())
	gap(bar)
	caption(bar, "Height")
	var height := SpinBox.new()
	height.min_value = 1
	height.max_value = 20
	height.value = brush.height
	height.focus_mode = Control.FOCUS_NONE
	height.get_line_edit().focus_mode = Control.FOCUS_CLICK
	height.tooltip_text = "Each cell of the stroke gets a column this tall, upward."
	height.value_changed.connect(_set_height)
	bar.add_child(height)
	var shape := OptionButton.new()
	shape.add_item("Paint", BoxBrush.Shape.PAINT)
	shape.add_item("Rectangle", BoxBrush.Shape.RECTANGLE)
	shape.selected = brush.shape
	shape.focus_mode = Control.FOCUS_NONE
	shape.tooltip_text = "Paint: every cell the mouse passes over. Rectangle: from corner to corner."
	shape.item_selected.connect(_set_shape)
	bar.add_child(shape)
	_whole_top_button = null
	_edge_buttons.clear()
	if not brush.has_handle_options():
		return
	var walkable_kind := brush.walkable_tops or brush.edges_2d_only_outside
	if not walkable_kind:
		gap(bar)
		caption(bar, "Grab in 3D")
		for facing: Box.Facing in FACING_TEXT:
			toggle(bar, FACING_TEXT[facing], brush.sides_3d[facing], "Grab its %s side in 3D" % FACING_TEXT[facing], _set_side_3d.bind(facing))
	gap(bar)
	caption(bar, "Grab in 2D" + (" (outer edges)" if walkable_kind else ""))
	if not walkable_kind:
		_whole_top_button = toggle(bar, "Whole top", brush.whole_top_2d, "Grab its whole top in 2D", _set_whole_top)
	for facing: Box.Facing in FACING_TEXT:
		_edge_buttons[facing] = toggle(bar, FACING_TEXT[facing], brush.edges_2d[facing], "Grab its %s edge in 2D" % FACING_TEXT[facing], _set_edge_2d.bind(facing))


func _set_height(value: float) -> void:
	brush.height = int(value)
	screen.redraw()

func _set_shape(id: int) -> void:
	brush.shape = id as BoxBrush.Shape
	screen.redraw()

func _set_side_3d(on: bool, facing: Box.Facing) -> void:
	brush.sides_3d[facing] = on
	screen.redraw()

## La tapa entera y los bordes se excluyen, como en las banderas de la caja.
func _set_whole_top(on: bool) -> void:
	brush.whole_top_2d = on
	if on:
		for facing: Box.Facing in _edge_buttons:
			brush.edges_2d[facing] = false
			_edge_buttons[facing].set_pressed_no_signal(false)
	screen.redraw()

func _set_edge_2d(on: bool, facing: Box.Facing) -> void:
	brush.edges_2d[facing] = on
	if on and _whole_top_button != null:
		brush.whole_top_2d = false
		_whole_top_button.set_pressed_no_signal(false)
	screen.redraw()


#==================El mouse==================

func plane_z() -> int:
	if _stroke == Stroke.PAINT:
		return _stroke_layer
	if _stroke == Stroke.ERASE or _stroke == Stroke.REPAINT:
		return _stroke_layer + 1
	return 0


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit
	_hover_has_target = false
	var target := target_of(hit)
	if target.size() == 1:
		_hover_target = target[0]
		_hover_has_target = true


## La celda donde iría la próxima caja: la de la capa en modo capa, si no la pegada a la cara.
func target_of(hit: GridPicker.Hit) -> Array[Vector3i]:
	if screen.layer_mode:
		if hit.has_box and hit.cell.z == screen.layer and hit.distance <= hit.plane_distance:
			return [hit.cell]
		if hit.has_plane_cell:
			return [hit.plane_cell]
		return []
	if hit.has_box:
		return [hit.cell_against]
	if hit.has_plane_cell:
		return [hit.plane_cell]
	return []


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not hit.has_box:
			return
		_stroke = Stroke.ERASE
		_stroke_layer = hit.cell.z
		_boxes = [hit.box]
		return
	if event.alt_pressed:
		screen.pick_from(hit)
		return
	if event.ctrl_pressed:
		if not hit.has_box:
			return
		_stroke = Stroke.REPAINT
		_stroke_layer = hit.cell.z
		_boxes = [hit.box]
		return
	var target := target_of(hit)
	if target.is_empty():
		return
	_stroke = Stroke.PAINT
	_start = target[0]
	_last = _start
	_stroke_layer = _start.z
	_base_cells = [_start]
	_extending = structure_extended_by(hit) if event.shift_pressed else null


func drag(hit: GridPicker.Hit, _event: InputEventMouseMotion) -> void:
	match _stroke:
		Stroke.PAINT:
			if not hit.has_plane_cell:
				return
			var cell := Vector3i(hit.plane_cell.x, hit.plane_cell.y, _stroke_layer)
			if brush.shape == BoxBrush.Shape.RECTANGLE:
				_base_cells = rectangle(_start, cell)
			elif cell != _last:
				for each in cells_between(_last, cell):
					if not _base_cells.has(each):
						_base_cells.append(each)
			_last = cell
		Stroke.ERASE, Stroke.REPAINT:
			var box := _box_on_the_stroke_layer(hit)
			if box != null and not _boxes.has(box):
				_boxes.append(box)


## La Structure que Shift extendería desde ahí: la de la caja apuntada, salvo la cáscara o una caja suelta.
func structure_extended_by(hit: GridPicker.Hit) -> Structure:
	if not hit.has_box:
		return null
	var structure := hit.box.get_parent() as Structure
	if structure == null or edits().is_shell_part(structure):
		return null
	return structure


func _box_on_the_stroke_layer(hit: GridPicker.Hit) -> Box:
	if hit.has_box and hit.cell.z == _stroke_layer:
		return hit.box
	if hit.has_plane_cell:
		return index().cells_3D.get(hit.plane_cell - Vector3i(0, 0, 1))
	return null


func release(_hit: GridPicker.Hit, _event: InputEventMouseButton) -> void:
	match _stroke:
		Stroke.PAINT:
			if refusal.is_empty():
				edits().paint(brush, stroke_cells(), _extending, screen.current_folder())
		Stroke.ERASE:
			edits().erase(_boxes, [])
			screen.forget_freed_selection()
		Stroke.REPAINT:
			screen.repaint_boxes(_boxes, brush)
	_stroke = Stroke.NONE
	_boxes = []
	_base_cells = []


func cancel() -> bool:
	var was_stroking := _stroke != Stroke.NONE
	_stroke = Stroke.NONE
	_boxes = []
	_base_cells = []
	return was_stroking


## Las celdas del trazo, con su columna del alto de la brocha.
func stroke_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for base in _base_cells:
		for up in brush.height:
			cells.append(base + Vector3i(0, 0, up))
	return cells


#==================Lo que se ve==================

func draw(preview: LevelEditorPreview) -> void:
	refusal = ""
	match _stroke:
		Stroke.NONE:
			_draw_the_hover(preview)
		Stroke.PAINT:
			_draw_the_stroke(preview, stroke_cells())
		Stroke.ERASE:
			for box in _boxes:
				if edits().is_in_the_level(box):
					preview.tint_cell(index().cell_of(box), LevelEditorPreview.RED)
		Stroke.REPAINT:
			var allowed := screen.boxes_a_repaint_can_take(_boxes, brush)
			for box in _boxes:
				if edits().is_in_the_level(box):
					preview.tint_cell(index().cell_of(box), LevelEditorPreview.BLUE if allowed.has(box) else LevelEditorPreview.RED)


func _draw_the_hover(preview: LevelEditorPreview) -> void:
	if not _hover_has_target:
		return
	if _hover_hit.has_box and not screen.layer_mode:
		preview.highlight_face(_hover_hit.cell, _hover_hit.face, LevelEditorPreview.BLUE)
	var cells: Array[Vector3i] = []
	for up in brush.height:
		cells.append(_hover_target + Vector3i(0, 0, up))
	var extending: Structure = structure_extended_by(_hover_hit) if Input.is_key_pressed(KEY_SHIFT) else null
	if extending != null and LevelEdits.would_mix_terrain(extending, brush.is_terrain()):
		refusal = "A structure is either all terrain or holds none: make it a structure of its own."
	_draw_the_stroke(preview, cells)


func _draw_the_stroke(preview: LevelEditorPreview, cells: Array[Vector3i]) -> void:
	var extending := _extending if _stroke == Stroke.PAINT else null
	if extending != null and LevelEdits.would_mix_terrain(extending, brush.is_terrain()):
		refusal = "A structure is either all terrain or holds none: make it a structure of its own."
	var free: Array[Vector3i] = []
	for cell in cells:
		if index().cells_3D.has(cell):
			preview.outline_cell(cell, LevelEditorPreview.RED)
		else:
			free.append(cell)
	if not refusal.is_empty():
		for cell in free:
			preview.tint_cell(cell, LevelEditorPreview.RED)
		return
	if free.size() > MOST_GHOSTS:
		for cell in free:
			preview.tint_cell(cell, LevelEditorPreview.BLUE, 0.0)
		return
	for cell in free:
		preview.ghost_box(cell, brush.flags_for(not cells.has(cell + LevelIndex.GRID_UP), _outside_in(cell, cells)))
		preview.outline_cell(cell, Color(0.3, 0.65, 1.0, 0.8), 0.0)


func _outside_in(cell: Vector3i, cells: Array[Vector3i]) -> Dictionary[Box.Facing, bool]:
	var outside: Dictionary[Box.Facing, bool] = {}
	for facing: Box.Facing in Box.FACING_DIRECTION:
		var direction := Box.FACING_DIRECTION[facing]
		outside[facing] = not cells.has(cell + Vector3i(direction.x, direction.y, 0))
	return outside


func status() -> String:
	match _stroke:
		Stroke.PAINT:
			var cells := stroke_cells()
			var occupied := cells.filter(func(cell: Vector3i) -> bool: return index().cells_3D.has(cell)).size()
			var text := "%d box%s" % [cells.size() - occupied, "" if cells.size() - occupied == 1 else "es"]
			if occupied > 0:
				text += " · %d skipped (occupied)" % occupied
			if brush.shape == BoxBrush.Shape.RECTANGLE:
				var low := _start.min(_last)
				var high := _start.max(_last)
				text += " · %d × %d" % [high.x - low.x + 1, high.y - low.y + 1]
			text += " · extends " + String(_extending.name) if _extending != null else " · new structure"
			return text
		Stroke.ERASE:
			return "Erase %d box%s" % [_boxes.size(), "" if _boxes.size() == 1 else "es"]
		Stroke.REPAINT:
			return "Repaint %d box%s as %s" % [_boxes.size(), "" if _boxes.size() == 1 else "es", brush.label()]
	if not _hover_has_target:
		return ""
	var where := "%s at %s" % [brush.label(), describe(_hover_target)]
	if index().cells_3D.has(_hover_target):
		return where + " · occupied"
	var extending := structure_extended_by(_hover_hit) if Input.is_key_pressed(KEY_SHIFT) else null
	if extending != null:
		return where + " · extends " + String(extending.name)
	if brush.is_terrain() and edits().shell_part_at(_hover_target) != null:
		return where + " · joins the shell"
	return where + " · new structure"


func hint() -> String:
	return "Left: place · Shift + left: extend that structure · Right: erase · Ctrl + drag: repaint · Alt + click: pick"
