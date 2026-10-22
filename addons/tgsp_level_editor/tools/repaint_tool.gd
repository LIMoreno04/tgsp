@tool
class_name RepaintTool
extends LevelEditorTool
## Le pone a cajas que ya existen las banderas de la última brocha de cajas, sin cambiarlas de grupo.
## Lo mismo que Ctrl + trazo con una brocha.

var _stroking := false
var _boxes: Array[Box] = []
var _hover_hit: GridPicker.Hit = GridPicker.Hit.new()


func _init(the_screen: LevelEditorScreen) -> void:
	super(the_screen)
	title = "Repaint"
	tooltip = "Give existing boxes the settings of the last box brush, keeping their groups. Ctrl + drag does it from a brush."


func _brush() -> BoxBrush:
	return screen.last_brush()


func build_options(bar: HBoxContainer) -> void:
	caption(bar, "Repaints as: " + _brush().label())


func hover(hit: GridPicker.Hit) -> void:
	_hover_hit = hit


func press(hit: GridPicker.Hit, event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT or not hit.has_box:
		return
	_stroking = true
	_boxes = [hit.box]


func drag(hit: GridPicker.Hit, _event: InputEventMouseMotion) -> void:
	if _stroking and hit.has_box and not _boxes.has(hit.box):
		_boxes.append(hit.box)


func release(_hit: GridPicker.Hit, _event: InputEventMouseButton) -> void:
	if not _stroking:
		return
	_stroking = false
	screen.repaint_boxes(_boxes, _brush())
	_boxes = []


func cancel() -> bool:
	var was := _stroking
	_stroking = false
	_boxes = []
	return was


func draw(preview: LevelEditorPreview) -> void:
	refusal = ""
	var boxes: Array[Box] = []
	if _stroking:
		boxes = _boxes
	elif _hover_hit.has_box:
		boxes = [_hover_hit.box]
	var allowed := screen.boxes_a_repaint_can_take(boxes, _brush())
	for box in boxes:
		if not edits().is_in_the_level(box):
			continue
		var mixes := not allowed.has(box)
		if mixes and edits().is_shell_part(box.get_parent()):
			refusal = "The room shell is terrain: only Floor or Wall can repaint it."
		elif mixes:
			refusal = "A group is either all terrain or holds none."
		preview.tint_cell(index().cell_of(box), LevelEditorPreview.RED if mixes else LevelEditorPreview.BLUE)


func status() -> String:
	if _stroking:
		return "Repaint %d box%s as %s" % [_boxes.size(), "" if _boxes.size() == 1 else "es", _brush().label()]
	return "Repaint as " + _brush().label() if _hover_hit.has_box else ""


func hint() -> String:
	return "Left + drag: repaint the boxes you pass over"
