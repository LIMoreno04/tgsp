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
## Más angosto que el borde gris de una baldosa caminable.
const HANDLE_OUTLINE_WIDTH := 0.03
const TILE_LIFT := 0.001
## Por encima de la baldosa y por debajo de las rayas de agarre 2D, que lo tapan.
const HANDLE_OUTLINE_LIFT := 0.0015
const HANDLE_STRIPE_LIFT := 0.002
## Hasta cuánto cambia cada estructura su naranja y su gris.
const MAX_STRUCTURE_TINT_STATIC := 0.10
const MAX_STRUCTURE_TINT_MOVABLE := 0.25

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
	var movable_colour := _tinted(COLOUR_MOVABLE, MAX_STRUCTURE_TINT_MOVABLE)
	var static_colour := _tinted(COLOUR_STATIC, MAX_STRUCTURE_TINT_STATIC)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for facing: Box.Facing in Box.FACING_DIRECTION:
		var direction := Box.FACING_DIRECTION[facing]
		var normal := Vector3(direction.x, 0, direction.y) # y de grilla = z de Godot
		if box.walkable:
			var skin_lo := _on_face(Vector3(-0.5, side_top_y, -0.5), normal)
			var skin_hi := _on_face(Vector3(0.5, top_y, 0.5), normal)
			_rect(st, skin_lo, skin_hi, normal, COLOUR_WALKABLE)
		var face_lo := _on_face(Vector3(-0.5, bottom_y, -0.5), normal)
		var face_hi := _on_face(Vector3(0.5, side_top_y, 0.5), normal)
		if box.is_wall:
			_bordered_rect(st, face_lo, face_hi, normal)
		elif box.movable_3d_from(facing):
			_rect(st, face_lo, face_hi, normal, movable_colour)
		else:
			_rect(st, face_lo, face_hi, normal, static_colour)

	if box.walkable or box.is_floor:
		_bordered_rect(st, top_lo, top_hi, Vector3.UP)
	elif box.movable_2d_from_every_side():
		_rect(st, top_lo, top_hi, Vector3.UP, movable_colour)
	else:
		_rect(st, top_lo, top_hi, Vector3.UP, static_colour)

	if box.movable_3d_from_any_side():
		_add_handle_outline(st, top_y + HANDLE_OUTLINE_LIFT, movable_colour, static_colour)

	var y := top_y + HANDLE_STRIPE_LIFT
	for facing: Box.Facing in Box.FACING_DIRECTION:
		if box.movable_2d_from(facing):
			var stripe := Box.strip_along(facing, MOVABLE_STRIPE_WIDTH)
			var lo := Vector3(stripe.position.x, y, stripe.position.y) # Y de grilla = Z de Godot
			var hi := Vector3(stripe.end.x, y, stripe.end.y)
			_rect(st, lo, hi, Vector3.UP, movable_colour)

	# Cara de abajo.
	_rect(st, Vector3(-0.5, bottom_y, -0.5), Vector3(0.5, bottom_y, 0.5), Vector3.DOWN, static_colour)

	mesh = st.commit()


## Un marco finito alrededor de la tapa, cada borde del color de la cara de abajo: naranja si es
## agarradera 3D, gris si no. Así se ve desde arriba, también en 2D, de qué lados se agarra en 3D.
## Los bordes en y van entre los de x, para que ninguna esquina se dibuje dos veces con dos colores.
func _add_handle_outline(st: SurfaceTool, y: float, movable_colour: Color, static_colour: Color) -> void:
	var colour: Dictionary[Box.Facing, Color] = {}
	for facing: Box.Facing in Box.FACING_DIRECTION:
		colour[facing] = movable_colour if box.movable_3d_from(facing) else static_colour
	var w := HANDLE_OUTLINE_WIDTH
	_rect(st, Vector3(0.5 - w, y, -0.5), Vector3(0.5, y, 0.5), Vector3.UP, colour[Box.Facing.POS_X])
	_rect(st, Vector3(-0.5, y, -0.5), Vector3(-0.5 + w, y, 0.5), Vector3.UP, colour[Box.Facing.NEG_X])
	_rect(st, Vector3(-0.5 + w, y, 0.5 - w), Vector3(0.5 - w, y, 0.5), Vector3.UP, colour[Box.Facing.POS_Y]) # Y de grilla = Z de Godot
	_rect(st, Vector3(-0.5 + w, y, -0.5), Vector3(0.5 - w, y, -0.5 + w), Vector3.UP, colour[Box.Facing.NEG_Y])


func _tinted(colour: Color, tint: float) -> Color:
	var structure: GridEntity = box.get_parent() if GridEntity.global_name_of(box.get_parent()) == &"Structure" else box
	var random := RandomNumberGenerator.new()
	random.seed = _seed_of(structure)
	var channel := random.randi_range(0, 2)
	colour[channel] = clampf(colour[channel] + random.randf_range(-tint, tint), 0.0, 1.0)
	return colour

## Su camino dentro del Room, que no se repite entre carpetas como la posición entre hermanos.
func _seed_of(structure: GridEntity) -> int:
	var room := structure.room_above()
	if room == null:
		return structure.get_index()
	return str(room.get_path_to(structure)).hash()


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
