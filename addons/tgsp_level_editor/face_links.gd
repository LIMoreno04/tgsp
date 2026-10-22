@tool
class_name FaceLinks
extends RefCounted
## Qué direcciones unen dos caras: los tres casos de conexión de LevelIndex.connected_powerables leídos
## al revés (de lado, dando la vuelta a un borde, hacia una esquina de adentro), y en 2D las tapas de
## columnas vecinas. Para que el cable que se dibuja conecte exactamente como el juego lo va a leer.


## Una cara de una caja, en celdas del mundo.
class FaceAt:
	var cell: Vector3i
	var face: Powerable.Face

	func _init(at_cell: Vector3i, at_face: Powerable.Face) -> void:
		cell = at_cell
		face = at_face

	func same_as(other: FaceAt) -> bool:
		return other != null and other.cell == cell and other.face == face

	func normal() -> Vector3i:
		return Powerable.FACE_NORMAL[face]


## Una cara vecina y las dos direcciones que las unen: la de esta cara hacia ella, y la de ella de vuelta.
class Link:
	var to: FaceAt
	var direction_here: Vector3i
	var direction_there: Vector3i

	func _init(link_to: FaceAt, here: Vector3i, there: Vector3i) -> void:
		to = link_to
		direction_here = here
		direction_there = there


## Las cuatro direcciones a lo largo de una cara.
static func directions_along(face: Powerable.Face) -> Array[Vector3i]:
	var normal: Vector3i = Powerable.FACE_NORMAL[face]
	var along: Array[Vector3i] = []
	for direction: Vector3i in LevelIndex.NEIGHBOURS_3D:
		if direction != normal and direction != -normal:
			along.append(direction)
	return along


## [dirección en a, dirección en b] si las dos caras se unen en 3D, o [] si no.
static func link_in_3d(a: FaceAt, b: FaceAt) -> Array[Vector3i]:
	var normal_a := a.normal()
	var normal_b := b.normal()
	if normal_b == normal_a:
		var beside := b.cell - a.cell
		if _is_a_unit_step(beside) and _dot(beside, normal_a) == 0:
			return [beside, -beside]
	if b.cell == a.cell and _dot(normal_b, normal_a) == 0:
		return [normal_b, normal_a]
	var toward_the_corner := -normal_b
	if _is_a_unit_step(toward_the_corner) and _dot(toward_the_corner, normal_a) == 0 and b.cell == a.cell + toward_the_corner + normal_a:
		return [toward_the_corner, -normal_a]
	return []


## En 2D se unen las tapas de dos columnas vecinas, sin importar sus alturas.
static func link_in_2d(a: FaceAt, b: FaceAt) -> Array[Vector3i]:
	if a.face != Powerable.Face.TOP or b.face != Powerable.Face.TOP:
		return []
	var beside := Vector3i(b.cell.x - a.cell.x, b.cell.y - a.cell.y, 0)
	if not _is_a_unit_step(beside):
		return []
	return [beside, -beside]


static func link(a: FaceAt, b: FaceAt, perspective: Room.Perspective) -> Array[Vector3i]:
	if Room.is_3d(perspective):
		return link_in_3d(a, b)
	return link_in_2d(a, b)


## Las caras a las que una cara se puede unir en 3D, según las cajas que hay: la misma cara de la caja
## de al lado, otra cara de la propia caja, y la cara que mira de vuelta de la caja de la esquina.
static func links_in_3d(from: FaceAt, cells: Dictionary[Vector3i, Box]) -> Array[Link]:
	var links: Array[Link] = []
	var normal := from.normal()
	for direction in directions_along(from.face):
		if cells.has(from.cell + direction):
			links.append(Link.new(FaceAt.new(from.cell + direction, from.face), direction, -direction))
		links.append(Link.new(FaceAt.new(from.cell, Powerable.face_toward(direction)), direction, normal))
		var corner := from.cell + direction + normal
		if cells.has(corner):
			links.append(Link.new(FaceAt.new(corner, Powerable.face_toward(-direction)), direction, -normal))
	return links


## En 2D, desde una tapa: las tapas de las columnas vecinas.
static func links_in_2d(from: FaceAt, tops: Dictionary[Vector2i, Box], index: LevelIndex) -> Array[Link]:
	var links: Array[Link] = []
	if from.face != Powerable.Face.TOP:
		return links
	for direction_2d: Vector2i in LevelIndex.NEIGHBOURS_2D:
		var column := Vector2i(from.cell.x, from.cell.y) + direction_2d
		var top: Box = tops.get(column)
		if top == null:
			continue
		var direction := Vector3i(direction_2d.x, direction_2d.y, 0)
		links.append(Link.new(FaceAt.new(index.cell_of(top), Powerable.Face.TOP), direction, -direction))
	return links


static func links(from: FaceAt, index: LevelIndex, perspective: Room.Perspective) -> Array[Link]:
	if Room.is_3d(perspective):
		return links_in_3d(from, index.cells_3D)
	return links_in_2d(from, index.grid_2D, index)


## El camino más corto de caras unidas entre dos caras, sin contar `from` y con `to` al final, o [] si
## no hay uno de a lo sumo `longest` pasos. Para cuando el mouse se salta caras.
static func shortest_path(from: FaceAt, to: FaceAt, index: LevelIndex, perspective: Room.Perspective, longest := 8) -> Array[FaceAt]:
	var came_from: Dictionary[String, FaceAt] = {_key(from): null}
	var frontier: Array[FaceAt] = [from]
	for _depth in longest:
		var next_frontier: Array[FaceAt] = []
		for face_at in frontier:
			for each_link in links(face_at, index, perspective):
				var key := _key(each_link.to)
				if came_from.has(key):
					continue
				came_from[key] = face_at
				if each_link.to.same_as(to):
					return _path_back(each_link.to, came_from)
				next_frontier.append(each_link.to)
		frontier = next_frontier
		if frontier.is_empty():
			break
	return []


static func _path_back(last: FaceAt, came_from: Dictionary[String, FaceAt]) -> Array[FaceAt]:
	var path: Array[FaceAt] = []
	var current := last
	while came_from[_key(current)] != null:
		path.push_front(current)
		current = came_from[_key(current)]
	return path


static func _key(face_at: FaceAt) -> String:
	return "%s/%d" % [face_at.cell, face_at.face]


static func _dot(a: Vector3i, b: Vector3i) -> int:
	return a.x * b.x + a.y * b.y + a.z * b.z


static func _is_a_unit_step(step: Vector3i) -> bool:
	return absi(step.x) + absi(step.y) + absi(step.z) == 1
