@tool
class_name StructurePalette
extends RefCounted
## Qué color le toca a cada estructura de un Room, elegido para que dos estructuras que empiezan
## cerca nunca compartan el suyo. Se arma una vez, con las cajas donde el nivel las carga, y no
## cambia cuando se mueven. Una caja suelta es su propia estructura.

## Un color de hielo por estructura, para sus cajas con asas. Sus cajas sin asas son piedra del
## mismo tono, oscura y apagada, con vetas de ese mismo hielo: así una roca y un cajón de hielo
## se ven de la misma estructura aunque no se toquen.
const ICE: Array[Color] = [
	Color(0.29, 0.82, 0.99), # cian glaciar, el del modelo
	Color(0.30, 0.56, 0.98), # azul ártico
	Color(0.36, 0.90, 0.76), # aguamarina
	Color(0.66, 0.58, 0.98), # violeta aurora
	Color(0.95, 0.62, 0.80), # rosa aurora
	Color(0.78, 0.90, 1.00), # escarcha
]
## Las manchas de escarcha del hielo son más claras que el cuerpo.
const ICE_FROST_LIGHTEN := 0.5
## La piedra conserva el tono de su hielo, con esta parte de su saturación y este valor.
const STONE_SATURATION := 0.5
const STONE_VALUE := 0.3

## Dos estructuras a esta distancia de celdas o menos (en cualquier eje) no comparten color.
const NEAR_DISTANCE := 2

## Por el instance id de la estructura: en el editor se borran, y un diccionario tipado no admite
## una clave liberada.
var _index_of: Dictionary[int, int] = {}
var _room: Node3D


func _init(room: Node3D) -> void:
	_room = room
	_assign(_structures_in(room))


## La estructura de una caja: su Structure, o ella misma si está suelta.
static func structure_of(box: Box) -> GridEntity:
	var parent := box.get_parent()
	if GridEntity.global_name_of(parent) == &"Structure":
		return parent
	return box


func index_of(structure: Node) -> int:
	if not _index_of.has(structure.get_instance_id()):
		_assign([structure]) # Una estructura agregada en el editor después de armar la paleta.
	return _index_of[structure.get_instance_id()]

## En el editor las estructuras se borran; sus colores no se reparten más.
func _forget_the_freed() -> void:
	for id in _index_of.keys():
		if instance_from_id(id) == null:
			_index_of.erase(id)

func ice_colour_of(structure: Node) -> Color:
	return ICE[index_of(structure) % ICE.size()]

func stone_colour_of(structure: Node) -> Color:
	return stone_from(ice_colour_of(structure))

static func stone_from(ice: Color) -> Color:
	return Color.from_hsv(ice.h, ice.s * STONE_SATURATION, STONE_VALUE)

static func frost_colour(ice: Color) -> Color:
	return ice.lerp(Color.WHITE, ICE_FROST_LIGHTEN)

## Las vetas de una roca son el hielo de su estructura, apenas apagado para que no parezcan confeti.
static func vein_colour(ice: Color) -> Color:
	return ice.darkened(0.15)


## En orden del árbol, cada estructura toma el primer color que ninguna vecina ya coloreada usa,
## empezando por donde la anterior dejó, así los colores se reparten en vez de repetirse.
func _assign(structures: Array[Node]) -> void:
	_forget_the_freed()
	var cells: Dictionary[int, Array] = {}
	for id in _index_of:
		cells[id] = _world_cells_of(instance_from_id(id) as Node)
	var next_index := _index_of.size()
	for structure in structures:
		var own_cells := _world_cells_of(structure)
		var taken: Dictionary[int, bool] = {}
		for id in _index_of:
			if _are_near(own_cells, cells[id]):
				taken[_index_of[id]] = true
		var chosen := -1
		for attempt in ICE.size():
			var candidate := (next_index + attempt) % ICE.size()
			if not taken.has(candidate):
				chosen = candidate
				break
		if chosen == -1:
			chosen = next_index % ICE.size() # Rodeada por toda la paleta: se repite alguno.
		_index_of[structure.get_instance_id()] = chosen
		cells[structure.get_instance_id()] = own_cells
		next_index = chosen + 1


## Las Structures y las cajas sueltas que no son terreno, hasta donde las reglas las ven.
static func _structures_in(room: Node3D) -> Array[Node]:
	var found: Array[Node] = []
	for child in room.get_children():
		if child is GridEntity:
			_collect_structures(child, found)
	return found

static func _collect_structures(node: Node, into: Array[Node]) -> void:
	var name := GridEntity.global_name_of(node)
	if name == &"Structure" or name == &"Box":
		if not _is_terrain(node):
			into.append(node)
		return
	for child in node.get_children():
		if child is GridEntity:
			_collect_structures(child, into)

## Una estructura es toda terreno o nada, así que con mirar la primera caja alcanza.
static func _is_terrain(structure: Node) -> bool:
	var boxes := _boxes_of(structure)
	return not boxes.is_empty() and boxes[0].is_terrain()

static func _boxes_of(structure: Node) -> Array[Box]:
	var boxes: Array[Box] = []
	if structure is Box:
		boxes.append(structure)
	else:
		for child in structure.get_children():
			if child is Box:
				boxes.append(child)
	return boxes

static func _world_cells_of(structure: Node) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for box in _boxes_of(structure):
		cells.append(box.world_cell)
	return cells

static func _are_near(cells_a: Array[Vector3i], cells_b: Array[Vector3i]) -> bool:
	for a in cells_a:
		for b in cells_b:
			var gap := (a - b).abs()
			if maxi(gap.x, maxi(gap.y, gap.z)) <= NEAR_DISTANCE:
				return true
	return false
