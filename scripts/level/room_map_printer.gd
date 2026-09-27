@tool
class_name RoomMapPrinter
extends RefCounted
## CLAUDE:
## Dibuja los índices de un Room en el Output, para mirarlos sin abrir el debugger.
## Sólo lee: nunca toca el Room ni las cajas.

const EMPTY_COLOUR := "#5a5a5a"
const COLOURS := {
	"wall": "#7f8fa6",
	"floor": "#a8a8a0",
	"handles": "#e8892a",
	"walkable": "#f2f2ec",
	"plain": "#7fb2e0",
}
## Una letra por Structure. Sin O, o ni l, para que no se confundan con la caja suelta.
const STRUCTURE_LETTERS := "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz"
const LOOSE_LETTER := "o"

var _room: Room


func _init(room: Room) -> void:
	_room = room


## cells_3D en cortes horizontales, del más alto al más bajo. Cada corte tiene x hacia la
## derecha e y hacia abajo, como lo ve la cámara 2D.
func print_cells_3D() -> void:
	if _room.cells_3D.is_empty():
		print_rich("[b]cells_3D[/b] is empty.")
		return
	var corners := _index_corners()
	var lo := corners[0]
	var hi := corners[1]
	var letters := _structure_letters()
	var lines := PackedStringArray()
	lines.append("[b]cells_3D[/b]  %d boxes · x %d..%d · y %d..%d · z %d..%d" % [_room.cells_3D.size(), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
	for z in range(hi.z, lo.z - 1, -1):
		lines.append("[b]z = %d[/b]" % z)
		lines.append(_x_axis(lo.x, hi.x, 3))
		for y in range(lo.y, hi.y + 1):
			var row := _y_label(y)
			for x in range(lo.x, hi.x + 1):
				var box: Box = _room.cells_3D.get(Vector3i(x, y, z))
				row += _cell(box, _letter(box, letters), 3)
			lines.append(row)
	lines.append(_legend(letters))
	print_rich("\n".join(lines))

## grid_2D: la caja de arriba de cada columna, con la letra de su estructura y su z.
func print_grid_2D() -> void:
	if _room.grid_2D.is_empty():
		print_rich("[b]grid_2D[/b] is empty.")
		return
	var corners := _index_corners()
	var lo := corners[0]
	var hi := corners[1]
	var letters := _structure_letters()
	var lines := PackedStringArray()
	lines.append("[b]grid_2D[/b]  %d columns · x %d..%d · y %d..%d · each tile shows its letter and its z" % [_room.grid_2D.size(), lo.x, hi.x, lo.y, hi.y])
	lines.append(_x_axis(lo.x, hi.x, 4))
	for y in range(lo.y, hi.y + 1):
		var row := _y_label(y)
		for x in range(lo.x, hi.x + 1):
			var top: Box = _room.grid_2D.get(Vector2i(x, y))
			var text := "·" if top == null else "%s%d" % [_letter(top, letters), top.world_cell.z]
			row += _cell(top, text, 4)
		lines.append(row)
	lines.append(_legend(letters))
	print_rich("\n".join(lines))


## `text` alineado a la derecha en `width` letras, del color de lo que es la caja, y en
## negrita si se puede pisar.
func _cell(box: Box, text: String, width: int) -> String:
	if box == null:
		return "[color=%s]%s[/color]" % [EMPTY_COLOUR, text.lpad(width)]
	var cell_text := "[color=%s]%s[/color]" % [COLOURS[_kind(box)], text.lpad(width)]
	if box.walkable or box.is_floor:
		cell_text = "[b]%s[/b]" % cell_text
	return cell_text

func _kind(box: Box) -> String:
	if box.is_wall:
		return "wall"
	if box.is_floor:
		return "floor"
	for facing in Box.Facing.values():
		if box.movable_3d_from(facing) or box.movable_2d_from(facing):
			return "handles"
	if box.walkable:
		return "walkable"
	return "plain"

func _letter(box: Box, letters: Dictionary[Node, String]) -> String:
	if box == null:
		return "·"
	return letters.get(box.get_parent(), LOOSE_LETTER)

## Una letra por Structure, en el orden en que aparecen en el índice (el del árbol).
func _structure_letters() -> Dictionary[Node, String]:
	var letters: Dictionary[Node, String] = {}
	for box: Box in _room.cells_3D.values():
		var parent := box.get_parent()
		if parent is Structure and not letters.has(parent):
			var index := letters.size()
			letters[parent] = STRUCTURE_LETTERS[index] if index < STRUCTURE_LETTERS.length() else "?"
	return letters

## La esquina más baja y la más alta de todo lo que hay en cells_3D.
func _index_corners() -> Array[Vector3i]:
	var lo: Vector3i = _room.cells_3D.keys()[0]
	var hi := lo
	for cell: Vector3i in _room.cells_3D:
		lo = lo.min(cell)
		hi = hi.max(cell)
	return [lo, hi]

func _x_axis(from_x: int, to_x: int, width: int) -> String:
	var axis := "  y/x"
	for x in range(from_x, to_x + 1):
		axis += str(x).lpad(width)
	return "[color=%s]%s[/color]" % [EMPTY_COLOUR, axis]

func _y_label(y: int) -> String:
	return "[color=%s]%s[/color]" % [EMPTY_COLOUR, str(y).lpad(5)]

func _legend(letters: Dictionary[Node, String]) -> String:
	var names := PackedStringArray()
	for structure in letters:
		names.append("%s %s" % [letters[structure], _room.get_path_to(structure)])
	if _room.cells_3D.values().any(func(box: Box) -> bool: return box.get_parent() is not Structure):
		names.append("%s loose box" % LOOSE_LETTER)
	var kinds := PackedStringArray()
	for kind in COLOURS:
		kinds.append("[color=%s]%s[/color]" % [COLOURS[kind], kind])
	return "  %s\n  %s · [b]bold[/b] = walkable top" % [" · ".join(names), " ".join(kinds)]
