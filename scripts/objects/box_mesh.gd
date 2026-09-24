@tool
extends MeshInstance3D


@onready var box: Box = get_parent()

const COLOUR_STATIC := Color(0.26, 0.26, 0.28)
const COLOUR_MOVABLE := Color(0.85, 0.45, 0.08)
const COLOUR_WALKABLE := Color(0.94, 0.94, 0.92)
const COLOUR_BORDER := Color(0.62, 0.62, 0.60)
const WALKABLE_BORDER_WIDTH := 0.04
const WALKABLE_SIDES_DISPLAY := 0.25
const MOVABLE_STRIPE_WIDTH := 0.15
const TILE_LIFT := 0.001
const HANDLE_STRIPE_LIFT := 0.002

var _rebuild_pending := false


func _ready() -> void:
	box.appearance_changed.connect(_request_rebuild)
	_request_rebuild()


# --- Geometría ---------------------------------------------------------------

## Rebuildear al final del frame por si cambian varias cosas en el mismo frame.
func _request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_pending = false
	var top_y := 0.5
	var bottom_y := 0.0 if box.top_half_only else -0.5
	# Las caras laterales terminan donde empieza la franja blanca de arriba (si hay).
	var side_top_y := top_y - WALKABLE_SIDES_DISPLAY if box.walkable else top_y
	var top_lo := Vector3(-0.5, top_y, -0.5)
	var top_hi := Vector3(0.5, top_y, 0.5)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for facing: Box.Facing in Box.FACING_NORMAL:
		var normal: Vector3 = Box.FACING_NORMAL[facing]
		if box.walkable:
			var skin_lo := _on_face(Vector3(-0.5, side_top_y, -0.5), normal)
			var skin_hi := _on_face(Vector3(0.5, top_y, 0.5), normal)
			_rect(st, skin_lo, skin_hi, normal, COLOUR_WALKABLE)
		var face_lo := _on_face(Vector3(-0.5, bottom_y, -0.5), normal)
		var face_hi := _on_face(Vector3(0.5, side_top_y, 0.5), normal)
		if box.is_wall:
			_bordered_rect(st, face_lo, face_hi, normal)
		elif box.movable_3d_from(facing):
			_rect(st, face_lo, face_hi, normal, COLOUR_MOVABLE)
		else:
			_rect(st, face_lo, face_hi, normal, COLOUR_STATIC)

	if box.walkable or box.is_floor:
		_bordered_rect(st, top_lo, top_hi, Vector3.UP)
	elif box.movable_2d_whole_face:
		_rect(st, top_lo, top_hi, Vector3.UP, COLOUR_MOVABLE)
	else:
		_rect(st, top_lo, top_hi, Vector3.UP, COLOUR_STATIC)

	var y := top_y + HANDLE_STRIPE_LIFT
	var msw := MOVABLE_STRIPE_WIDTH
	if box.movable_2d_from(Box.Facing.POS_X):
		_rect(st, Vector3(0.5 - msw, y, -0.5), Vector3(0.5, y, 0.5), Vector3.UP, COLOUR_MOVABLE)
	if box.movable_2d_from(Box.Facing.NEG_X):
		_rect(st, Vector3(-0.5, y, -0.5), Vector3(-0.5 + msw, y, 0.5), Vector3.UP, COLOUR_MOVABLE)
	if box.movable_2d_from(Box.Facing.POS_Y): # Y de grilla = Z de Godot
		_rect(st, Vector3(-0.5, y, 0.5 - msw), Vector3(0.5, y, 0.5), Vector3.UP, COLOUR_MOVABLE)
	if box.movable_2d_from(Box.Facing.NEG_Y):
		_rect(st, Vector3(-0.5, y, -0.5), Vector3(0.5, y, -0.5 + msw), Vector3.UP, COLOUR_MOVABLE)

	# Cara de abajo.
	_rect(st, Vector3(-0.5, bottom_y, -0.5), Vector3(0.5, bottom_y, 0.5), Vector3.DOWN, COLOUR_STATIC)

	mesh = st.commit()


func _bordered_rect(st: SurfaceTool, lo: Vector3, hi: Vector3, normal: Vector3) -> void:
	var inset := (Vector3.ONE - normal.abs()) * WALKABLE_BORDER_WIDTH
	var lift := normal * TILE_LIFT
	_rect(st, lo, hi, normal, COLOUR_BORDER)
	_rect(st, lo + inset + lift, hi - inset + lift, normal, COLOUR_WALKABLE)


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
