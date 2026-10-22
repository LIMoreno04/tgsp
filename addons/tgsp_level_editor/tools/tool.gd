@tool
class_name LevelEditorTool
extends RefCounted
## Una herramienta de la paleta. La pantalla le pasa el mouse y le pide qué dibujar y qué decir; la
## herramienta nunca toca nodos: le pide los cambios a LevelEdits.

var screen: LevelEditorScreen
## El texto del botón de la paleta, y su ayuda.
var title := ""
var tooltip := ""
## Si el último dibujo se quejó: lo que la barra de estado dice en rojo.
var refusal := ""


func _init(the_screen: LevelEditorScreen) -> void:
	screen = the_screen


## Al volver a elegirla, sus opciones vuelven a como empiezan (dev).
func reset_options() -> void:
	pass

func build_options(_bar: HBoxContainer) -> void:
	pass

func activate() -> void:
	pass

func deactivate() -> void:
	cancel()


func hover(_hit: GridPicker.Hit) -> void:
	pass

func press(_hit: GridPicker.Hit, _event: InputEventMouseButton) -> void:
	pass

func drag(_hit: GridPicker.Hit, _event: InputEventMouseMotion) -> void:
	pass

func release(_hit: GridPicker.Hit, _event: InputEventMouseButton) -> void:
	pass

## Esc: deja lo que estaba haciendo sin cambiar nada. Devuelve si había algo.
func cancel() -> bool:
	return false

## Teclas propias de la herramienta mientras trabaja (como + y − al mover). Devuelve si la usó.
func key(_event: InputEventKey) -> bool:
	return false


func draw(_preview: LevelEditorPreview) -> void:
	pass

## Lo que la barra de estado dice ahora mismo, además de las pistas.
func status() -> String:
	return ""

## Qué hace cada botón del mouse con esta herramienta.
func hint() -> String:
	return ""

## La capa en la que buscar la celda del plano bajo el mouse cuando no hay modo capa.
func plane_z() -> int:
	return 0


func room() -> Room:
	return screen.room

func index() -> LevelIndex:
	return screen.room.index

func edits() -> LevelEdits:
	return screen.edits


static func describe(cell: Vector3i) -> String:
	return "(%d, %d, %d)" % [cell.x, cell.y, cell.z]


## Las celdas entre dos celdas de la misma capa, sin huecos, para cuando el mouse va rápido.
static func cells_between(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	if steps == 0:
		return [to]
	var last := from
	for i in range(1, steps + 1):
		var weight := float(i) / steps
		var cell := Vector3i(roundi(lerpf(from.x, to.x, weight)), roundi(lerpf(from.y, to.y, weight)), from.z)
		if cell.x != last.x and cell.y != last.y:
			cells.append(Vector3i(cell.x, last.y, from.z))
		cells.append(cell)
		last = cell
	return cells


static func rectangle(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			cells.append(Vector3i(x, y, from.z))
	return cells


## Una fila de botones que se prenden y apagan, para lados y bordes.
static func toggle(bar: Control, text: String, pressed: bool, tooltip_text: String, on_toggled: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = pressed
	button.tooltip_text = tooltip_text
	button.focus_mode = Control.FOCUS_NONE
	button.toggled.connect(on_toggled)
	bar.add_child(button)
	return button


static func caption(bar: Control, text: String) -> Label:
	var each_label := Label.new()
	each_label.text = text
	bar.add_child(each_label)
	return each_label


static func gap(bar: Control) -> void:
	var separator := VSeparator.new()
	bar.add_child(separator)


const FACING_TEXT: Dictionary[Box.Facing, String] = {
	Box.Facing.POS_X: "+x",
	Box.Facing.NEG_X: "−x",
	Box.Facing.POS_Y: "+y",
	Box.Facing.NEG_Y: "−y",
}
