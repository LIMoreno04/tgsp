@tool
class_name GridPicker
extends RefCounted
## Qué hay bajo el mouse. Recorre el rayo celda por celda (siempre a la próxima celda en la que entra)
## hasta una caja que se vea. Sólo lee las celdas del índice; nunca la física.

## Qué tan cerca de un borde de la tapa cuenta como ese borde, en celdas.
const EDGE_ZONE := 0.25
const NO_EDGE := -1


class Hit:
	var has_box := false
	var box: Box
	## La celda del mundo de la caja.
	var cell := Vector3i.ZERO
	var face := Powerable.Face.TOP
	var normal := Vector3i(0, 0, 1)
	## Dónde en la cara, de 0 a 1 en cada uno de sus dos ejes (en la tapa, x e y).
	var on_face := Vector2(0.5, 0.5)
	## En la tapa: el borde más cercano (un Box.Facing) si está a menos de EDGE_ZONE, o NO_EDGE.
	var top_edge := NO_EDGE
	## La celda vacía pegada a la cara.
	var cell_against := Vector3i.ZERO
	var distance := INF
	## La celda de la capa (o del plano de respaldo) bajo el mouse.
	var has_plane_cell := false
	var plane_cell := Vector3i.ZERO
	var plane_distance := INF

	func has_anything() -> bool:
		return has_box or has_plane_cell


## `is_visible` dice si una caja se puede apuntar (las ocultas por la capa o por el ojo no).
## `plane_z` es la capa en la que buscar la celda del plano.
static func pick(godot_origin: Vector3, godot_direction: Vector3, cells: Dictionary[Vector3i, Box], is_visible: Callable, bounds_low: Vector3i, bounds_high: Vector3i, plane_z: int) -> Hit:
	var hit := Hit.new()
	var origin := Vector3(godot_origin.x, godot_origin.z, godot_origin.y)
	var direction := Vector3(godot_direction.x, godot_direction.z, godot_direction.y).normalized()
	_find_the_plane_cell(hit, origin, direction, plane_z)
	_walk_to_the_first_box(hit, origin, direction, cells, is_visible, bounds_low, bounds_high)
	return hit


static func _find_the_plane_cell(hit: Hit, origin: Vector3, direction: Vector3, plane_z: int) -> void:
	if absf(direction.z) < 0.000001:
		return
	var distance := (plane_z - origin.z) / direction.z
	if distance < 0.0:
		return
	var point := origin + direction * distance
	hit.has_plane_cell = true
	hit.plane_cell = Vector3i(floori(point.x), floori(point.y), plane_z)
	hit.plane_distance = distance


static func _walk_to_the_first_box(hit: Hit, origin: Vector3, direction: Vector3, cells: Dictionary[Vector3i, Box], is_visible: Callable, bounds_low: Vector3i, bounds_high: Vector3i) -> void:
	var low := Vector3(bounds_low)
	var high := Vector3(bounds_high + Vector3i.ONE)
	var enter := -INF
	var leave := INF
	var entered_on_axis := -1
	for axis in 3:
		if absf(direction[axis]) < 0.000001:
			if origin[axis] < low[axis] or origin[axis] > high[axis]:
				return
			continue
		var near := (low[axis] - origin[axis]) / direction[axis]
		var far := (high[axis] - origin[axis]) / direction[axis]
		if near > far:
			var swap := near
			near = far
			far = swap
		if near > enter:
			enter = near
			entered_on_axis = axis
		leave = minf(leave, far)
	if enter > leave or leave < 0.0:
		return
	if enter < 0.0:
		enter = 0.0
		entered_on_axis = -1

	var start := origin + direction * (enter + 0.0001)
	var cell := Vector3i(floori(start.x), floori(start.y), floori(start.z)).clamp(bounds_low, bounds_high)
	var step := Vector3i(int(signf(direction.x)), int(signf(direction.y)), int(signf(direction.z)))
	var next_crossing := Vector3(INF, INF, INF)
	var crossing_every := Vector3(INF, INF, INF)
	for axis in 3:
		if step[axis] == 0:
			continue
		var boundary := cell[axis] + (1 if step[axis] > 0 else 0)
		next_crossing[axis] = (boundary - origin[axis]) / direction[axis]
		crossing_every[axis] = absf(1.0 / direction[axis])
	var distance_entering := enter

	while _inside(cell, bounds_low, bounds_high):
		var box: Box = cells.get(cell)
		if box != null and is_instance_valid(box) and is_visible.call(box):
			if box.top_half_only:
				if _hit_the_upper_half(hit, box, cell, origin, direction):
					return
			elif entered_on_axis >= 0:
				var normal := Vector3i.ZERO
				normal[entered_on_axis] = -step[entered_on_axis]
				_fill(hit, box, cell, normal, origin + direction * distance_entering, distance_entering)
				return
		var axis := 0
		if next_crossing.y < next_crossing[axis]:
			axis = 1
		if next_crossing.z < next_crossing[axis]:
			axis = 2
		if next_crossing[axis] == INF:
			return
		distance_entering = next_crossing[axis]
		cell[axis] += step[axis]
		next_crossing[axis] += crossing_every[axis]
		entered_on_axis = axis


static func _inside(cell: Vector3i, low: Vector3i, high: Vector3i) -> bool:
	return cell.x >= low.x and cell.y >= low.y and cell.z >= low.z and cell.x <= high.x and cell.y <= high.y and cell.z <= high.z


## Una caja `top_half_only` se dibuja sólo de la mitad para arriba, así que sólo cuenta ahí.
static func _hit_the_upper_half(hit: Hit, box: Box, cell: Vector3i, origin: Vector3, direction: Vector3) -> bool:
	var low := Vector3(cell) + Vector3(0, 0, 0.5)
	var high := Vector3(cell) + Vector3.ONE
	var enter := -INF
	var leave := INF
	var normal := Vector3i.ZERO
	for axis in 3:
		if absf(direction[axis]) < 0.000001:
			if origin[axis] < low[axis] or origin[axis] > high[axis]:
				return false
			continue
		var near := (low[axis] - origin[axis]) / direction[axis]
		var far := (high[axis] - origin[axis]) / direction[axis]
		var near_normal := -1 if direction[axis] > 0 else 1
		if near > far:
			var swap := near
			near = far
			far = swap
		if near > enter:
			enter = near
			normal = Vector3i.ZERO
			normal[axis] = near_normal
		leave = minf(leave, far)
	if enter > leave or leave < 0.0 or normal == Vector3i.ZERO:
		return false
	_fill(hit, box, cell, normal, origin + direction * enter, enter)
	return true


static func _fill(hit: Hit, box: Box, cell: Vector3i, normal: Vector3i, point: Vector3, distance: float) -> void:
	hit.has_box = true
	hit.box = box
	hit.cell = cell
	hit.normal = normal
	hit.face = Powerable.face_toward(normal)
	hit.cell_against = cell + normal
	hit.distance = distance
	var inside := point - Vector3(cell)
	if normal.z != 0:
		hit.on_face = Vector2(inside.x, inside.y)
	elif normal.x != 0:
		hit.on_face = Vector2(inside.y, inside.z)
	else:
		hit.on_face = Vector2(inside.x, inside.z)
	hit.on_face = hit.on_face.clamp(Vector2.ZERO, Vector2.ONE)
	hit.top_edge = NO_EDGE
	if hit.face == Powerable.Face.TOP:
		hit.top_edge = top_edge_near(hit.on_face)


## El borde de la tapa más cercano a ese punto, si está a menos de EDGE_ZONE.
static func top_edge_near(on_top: Vector2) -> int:
	var to_edge: Dictionary[Box.Facing, float] = {
		Box.Facing.POS_X: 1.0 - on_top.x,
		Box.Facing.NEG_X: on_top.x,
		Box.Facing.POS_Y: 1.0 - on_top.y,
		Box.Facing.NEG_Y: on_top.y,
	}
	var nearest: Box.Facing = Box.Facing.POS_X
	for facing: Box.Facing in to_edge:
		if to_edge[facing] < to_edge[nearest]:
			nearest = facing
	return nearest if to_edge[nearest] < EDGE_ZONE else NO_EDGE


## El borde de la tapa más cercano, aunque esté lejos: para las puertas, que siempre van en uno.
static func nearest_top_edge(on_top: Vector2) -> Box.Facing:
	var offset := on_top - Vector2(0.5, 0.5)
	if absf(offset.x) >= absf(offset.y):
		return Box.Facing.POS_X if offset.x > 0.0 else Box.Facing.NEG_X
	return Box.Facing.POS_Y if offset.y > 0.0 else Box.Facing.NEG_Y
