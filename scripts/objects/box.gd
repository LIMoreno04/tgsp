@tool
class_name Box
extends MeshInstance3D


enum Mobility { STATIC, MOVABLE, MOVABLE_3D, MOVABLE_2D, WALL }

enum Side { POS_X, NEG_X, POS_Y, NEG_Y }

## Qué cara de la pared lleva la textura del piso: la +X o la +Y (de grilla).
enum WallAxis { X, Y }

const SIDE_NORMAL := {
	Side.POS_X: Vector3(1, 0, 0),
	Side.NEG_X: Vector3(-1, 0, 0),
	Side.POS_Y: Vector3(0, 0, 1),
	Side.NEG_Y: Vector3(0, 0, -1),
}

const COLOUR_STATIC := Color(0.26, 0.26, 0.28)
const COLOUR_MOVABLE := Color(0.85, 0.45, 0.08)
const COLOUR_WALKABLE := Color(0.94, 0.94, 0.92)
const COLOUR_BORDER := Color(0.62, 0.62, 0.60)
const WALKABLE_BORDER_WIDTH := 0.04
const WALKABLE_SIDES_DISPLAY := 0.25
const MOVABLE_STRIPE_WIDTH := 0.15
const STRIPE_LIFT := 0.001

static var _material: StandardMaterial3D

var _rebuild_pending := false
@export var structure_id :int:
	set(value):
		structure_id = value
@export var cell := Vector3i.ZERO:
	set(value):
		cell = value
		position = CoordsProvider.grid_to_godot(cell)

@export var walkable := false:
	set(value):
		walkable = value
		_request_rebuild()

@export var mobility := Mobility.STATIC:
	set(value):
		mobility = value
		notify_property_list_changed()
		_request_rebuild()

## Sólo importa en WALL.
@export var wall_axis := WallAxis.X:
	set(value):
		wall_axis = value
		_request_rebuild()

@export_group("Movable sides", "from_")
@export var from_pos_x := false:
	set(value):
		from_pos_x = value
		movable_from[Side.POS_X] = value
		_request_rebuild()
@export var from_neg_x := false:
	set(value):
		from_neg_x = value
		movable_from[Side.NEG_X] = value
		_request_rebuild()
@export var from_pos_y := false:
	set(value):
		from_pos_y = value
		movable_from[Side.POS_Y] = value
		_request_rebuild()
@export var from_neg_y := false:
	set(value):
		from_neg_y = value
		movable_from[Side.NEG_Y] = value
		_request_rebuild()
@export_group("")

var movable_from := {
	Side.POS_X: from_pos_x,
	Side.NEG_X: from_neg_x,
	Side.POS_Y: from_pos_y,
	Side.NEG_Y: from_neg_y,
}

func _validate_property(property: Dictionary) -> void:
	if property.name.begins_with("from_") and !(mobility in [Mobility.MOVABLE_2D, Mobility.MOVABLE_3D]):
		property.usage = PROPERTY_USAGE_NO_EDITOR
	if property.name == "wall_axis" and mobility != Mobility.WALL:
		property.usage = PROPERTY_USAGE_NO_EDITOR

@export var top_half_only := false:
	set(value):
		top_half_only = value
		_request_rebuild()


func _init() -> void:
	set_notify_local_transform(true)
	position = CoordsProvider.grid_to_godot(cell)
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
	material_override = _material
	_request_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		var target :Vector3i = CoordsProvider.godot_to_grid(position)
		if target != cell or not position.is_equal_approx(CoordsProvider.grid_to_godot(target)):
			cell = target


# --- Geometría ---------------------------------------------------------------

## Rebuildear al final del frame por si cambian varias cosas en el mismo frame.
func _request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_pending = false
	var body_colour := COLOUR_MOVABLE if mobility == Mobility.MOVABLE else COLOUR_STATIC
	var top_y := 0.5
	var bottom_y := 0.0 if top_half_only else -0.5
	# Las caras laterales terminan donde empieza la franja blanca de arriba (si hay).
	var side_top_y := top_y - WALKABLE_SIDES_DISPLAY if walkable else top_y
	# Caras de tipo pared: centro blanco y borde gris, igual que el piso.
	var wall_side := Side.POS_X if wall_axis == WallAxis.X else Side.POS_Y

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Caras laterales, color + franja blanca arriba si es caminable
	for side: Side in SIDE_NORMAL:
		var normal: Vector3 = SIDE_NORMAL[side]
		var face_colour := COLOUR_MOVABLE if mobility == Mobility.MOVABLE_3D and movable_from[side] else body_colour
		if walkable:
			var skin_lo := _on_face(Vector3(-0.5, side_top_y, -0.5), normal)
			var skin_hi := _on_face(Vector3(0.5, top_y, 0.5), normal)
			_rect(st, skin_lo, skin_hi, normal, COLOUR_WALKABLE)
		if mobility == Mobility.WALL and side == wall_side:
			continue # se dibuja aparte abajo
		var face_lo := _on_face(Vector3(-0.5, bottom_y, -0.5), normal)
		var face_hi := _on_face(Vector3(0.5, side_top_y, 0.5), normal)
		_rect(st, face_lo, face_hi, normal, face_colour)

	# Caras de tipo pared: centro blanco y borde gris, igual que el piso.
	if mobility == Mobility.WALL:
		var bw := WALKABLE_BORDER_WIDTH
		var lo_y := bottom_y
		var hi_y := side_top_y
		if wall_axis == WallAxis.X:
			# Plano x = 0.5; ancho en z, alto en y.
			_rect(st, Vector3(0.5, lo_y + bw, -0.5 + bw), Vector3(0.5, hi_y - bw, 0.5 - bw), Vector3.RIGHT, COLOUR_WALKABLE)
			_rect(st, Vector3(0.5, lo_y, -0.5), Vector3(0.5, hi_y, -0.5 + bw), Vector3.RIGHT, COLOUR_BORDER)
			_rect(st, Vector3(0.5, lo_y, 0.5 - bw), Vector3(0.5, hi_y, 0.5), Vector3.RIGHT, COLOUR_BORDER)
			_rect(st, Vector3(0.5, lo_y, -0.5 + bw), Vector3(0.5, lo_y + bw, 0.5 - bw), Vector3.RIGHT, COLOUR_BORDER)
			_rect(st, Vector3(0.5, hi_y - bw, -0.5 + bw), Vector3(0.5, hi_y, 0.5 - bw), Vector3.RIGHT, COLOUR_BORDER)
		else:
			# +Y de grilla = +Z de Godot. Plano z = 0.5; ancho en x, alto en y.
			_rect(st, Vector3(-0.5 + bw, lo_y + bw, 0.5), Vector3(0.5 - bw, hi_y - bw, 0.5), Vector3.BACK, COLOUR_WALKABLE)
			_rect(st, Vector3(-0.5, lo_y, 0.5), Vector3(-0.5 + bw, hi_y, 0.5), Vector3.BACK, COLOUR_BORDER)
			_rect(st, Vector3(0.5 - bw, lo_y, 0.5), Vector3(0.5, hi_y, 0.5), Vector3.BACK, COLOUR_BORDER)
			_rect(st, Vector3(-0.5 + bw, lo_y, 0.5), Vector3(0.5 - bw, lo_y + bw, 0.5), Vector3.BACK, COLOUR_BORDER)
			_rect(st, Vector3(-0.5 + bw, hi_y - bw, 0.5), Vector3(0.5 - bw, hi_y, 0.5), Vector3.BACK, COLOUR_BORDER)

	# Cara de arriba.
	if walkable:
		# Centro blanco y borde gris
		var bw := WALKABLE_BORDER_WIDTH
		_rect(st, Vector3(-0.5 + bw, top_y, -0.5 + bw), Vector3(0.5 - bw, top_y, 0.5 - bw), Vector3.UP, COLOUR_WALKABLE)
		_rect(st, Vector3(-0.5, top_y, -0.5), Vector3(-0.5 + bw, top_y, 0.5), Vector3.UP, COLOUR_BORDER)
		_rect(st, Vector3(0.5 - bw, top_y, -0.5), Vector3(0.5, top_y, 0.5), Vector3.UP, COLOUR_BORDER)
		_rect(st, Vector3(-0.5 + bw, top_y, -0.5), Vector3(0.5 - bw, top_y, -0.5 + bw), Vector3.UP, COLOUR_BORDER)
		_rect(st, Vector3(-0.5 + bw, top_y, 0.5 - bw), Vector3(0.5 - bw, top_y, 0.5), Vector3.UP, COLOUR_BORDER)
	else:
		_rect(st, Vector3(-0.5, top_y, -0.5), Vector3(0.5, top_y, 0.5), Vector3.UP, body_colour)


	if mobility == Mobility.MOVABLE_2D:
		var y := top_y + STRIPE_LIFT
		var msw := MOVABLE_STRIPE_WIDTH
		if movable_from[Side.POS_X]:
			_rect(st, Vector3(0.5 - msw, y, -0.5), Vector3(0.5, y, 0.5), Vector3.UP, COLOUR_MOVABLE)
		if movable_from[Side.NEG_X]:
			_rect(st, Vector3(-0.5, y, -0.5), Vector3(-0.5 + msw, y, 0.5), Vector3.UP, COLOUR_MOVABLE)
		if movable_from[Side.POS_Y]: # Y de grilla = Z de Godot
			_rect(st, Vector3(-0.5, y, 0.5 - msw), Vector3(0.5, y, 0.5), Vector3.UP, COLOUR_MOVABLE)
		if movable_from[Side.NEG_Y]:
			_rect(st, Vector3(-0.5, y, -0.5), Vector3(0.5, y, -0.5 + msw), Vector3.UP, COLOUR_MOVABLE)

	# Cara de abajo.
	_rect(st, Vector3(-0.5, bottom_y, -0.5), Vector3(0.5, bottom_y, 0.5), Vector3.DOWN, body_colour)

	mesh = st.commit()


## Rectángulo plano alineado a los ejes, de la esquina `lo` a la esquina `hi` mirando hacia `normal`.
func _rect(st: SurfaceTool, lo: Vector3, hi: Vector3, normal: Vector3, colour: Color) -> void:
	var centre := (lo + hi) / 2.0
	var half_size := (hi - lo) / 2.0 # cuánto se extiende desde el centro en cada eje (0 en el de la normal)

	# Dos direcciones perpendiculares dentro del plano. `height_dir` es "arriba"
	# para quien mira la cara desde afuera, y `width_dir` es su "derecha":
	# el producto cruz da el tercer eje, y con este orden width × height = normal.
	var height_dir := Vector3.FORWARD if normal.y != 0.0 else Vector3.UP # arriba/abajo no pueden usar UP
	var width_dir := height_dir.cross(normal)

	# Las mismas direcciones, pero con el largo real de media arista.
	# dot() lee la componente de half_size en ese eje; abs porque el eje puede ir en negativo.
	var half_width := width_dir * absf(width_dir.dot(half_size))
	var half_height := height_dir * absf(height_dir.dot(half_size))
	if half_width.is_zero_approx() or half_height.is_zero_approx():
		return # sin área: no hay nada que dibujar

	# Esquinas, nombradas según width_dir/height_dir (no según la pantalla).
	var bottom_left := centre - half_width - half_height
	var top_left := centre - half_width + half_height
	var top_right := centre + half_width + half_height
	var bottom_right := centre + half_width - half_height

	# Normal y color valen para todos los vértices que se agreguen después.
	st.set_normal(normal)
	st.set_color(colour)

	# Dos triángulos que comparten la diagonal bottom_left -> top_right.
	# Godot sólo muestra un triángulo desde el lado en que sus vértices van en
	# sentido horario; con width × height = normal, este orden es horario desde afuera.
	st.add_vertex(bottom_left)
	st.add_vertex(top_left)
	st.add_vertex(top_right)

	st.add_vertex(bottom_left)
	st.add_vertex(top_right)
	st.add_vertex(bottom_right)


## Lleva `p` al plano de la cara que mira hacia `n` (a +-0.5 en ese eje).
func _on_face(p: Vector3, n: Vector3) -> Vector3:
	return p * (Vector3.ONE - n.abs()) + n * 0.5
