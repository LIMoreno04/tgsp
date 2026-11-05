@tool
extends MeshInstance3D


var box: Box:
	get:
		return get_parent() as Box

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
const FLOOR_HORIZONTAL_SCALE := 1.05
const FLOOR_SNOW_ALBEDO := Color(0.74, 0.80, 0.86)

const FLOOR_MODEL: PackedScene = preload("res://art/boxes/Suelo_nieve_hielo.glb")
const WALL_MODEL: PackedScene = preload("res://art/boxes/Pared_Nieve.glb")
const INTERACTABLE_MODEL: PackedScene = preload("res://art/boxes/Caja_interactuable_Hielo.glb")
const STONE_MODEL: PackedScene = preload("res://art/boxes/Caja_inamovible_Piedra.glb")
const SNOW_MODEL: PackedScene = preload("res://art/boxes/Walkable_Nieve.glb")
const HANDLE_MODEL: PackedScene = preload("res://art/boxes/Handle_Hielo.glb")

static var _floor_meshes: Dictionary[Vector2i, ArrayMesh] = {}
static var _wall_meshes: Dictionary[Vector4i, ArrayMesh] = {}
static var _interactable_meshes: Dictionary[Vector4i, ArrayMesh] = {}
static var _stone_meshes: Dictionary[Vector4i, ArrayMesh] = {}
static var _snow_meshes: Dictionary[bool, ArrayMesh] = {}
static var _handle_meshes: Dictionary[Vector3i, ArrayMesh] = {}
static var _vertex_colour_material: StandardMaterial3D

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
	material_override = null
	if box.is_floor:
		var random := RandomNumberGenerator.new()
		random.seed = hash(box.world_cell)
		mesh = _floor_mesh(box.top_half_only, random.randi_range(0, 3))
		return

	if box.is_wall:
		var wall_random := RandomNumberGenerator.new()
		wall_random.seed = hash(box.world_cell)
		var wall_turns := Vector3i(wall_random.randi_range(0, 3), wall_random.randi_range(0, 3), wall_random.randi_range(0, 3))
		var wall_base := _wall_mesh(box.top_half_only, wall_turns)
		if box.walkable:
			var wall_assembled := ArrayMesh.new()
			_append_mesh(wall_assembled, wall_base)
			_append_mesh(wall_assembled, _snow_mesh(box.top_half_only))
			mesh = wall_assembled
		else:
			mesh = wall_base
		return

	var random := RandomNumberGenerator.new()
	var structure: GridEntity = box.get_parent() if GridEntity.global_name_of(box.get_parent()) == &"Structure" else box
	random.seed = hash(box.name) ^ _seed_of(structure)
	var turns := Vector3i(random.randi_range(0, 3), random.randi_range(0, 3), random.randi_range(0, 3))

	var is_interactable := _is_interactable()
	var base_mesh: ArrayMesh = _interactable_mesh(box.top_half_only, turns) if is_interactable else _stone_mesh(box.top_half_only, turns)

	var has_handles := false
	if is_interactable:
		for facing: Box.Facing in Box.Facing.values():
			if _has_handle_on(facing):
				has_handles = true
				break

	if not has_handles and not box.walkable:
		mesh = base_mesh
		return

	var assembled := ArrayMesh.new()
	_append_mesh(assembled, base_mesh)
	if box.walkable:
		_append_mesh(assembled, _snow_mesh(box.top_half_only))
	if is_interactable:
		for facing: Box.Facing in Box.Facing.values():
			if _has_handle_on(facing):
				_append_mesh(assembled, _handle_mesh(box.top_half_only, box.walkable, facing))
	mesh = assembled


static func _floor_mesh(top_half_only: bool, quarter_turns: int) -> ArrayMesh:
	var key := Vector2i(int(top_half_only), quarter_turns)
	if _floor_meshes.has(key):
		return _floor_meshes[key]
	var root := FLOOR_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var bottom_y := 0.0 if top_half_only else -0.5
	var target_size := Vector3(FLOOR_HORIZONTAL_SCALE, 0.5 - bottom_y, FLOOR_HORIZONTAL_SCALE)
	var target_centre := Vector3(0.0, (0.5 + bottom_y) / 2.0, 0.0)
	var scale_basis := Basis.from_scale(target_size / aabb.size)
	var turn := Basis(Vector3.UP, quarter_turns * PI / 2.0)
	var fit := Transform3D(turn, target_centre) * Transform3D(scale_basis, -(scale_basis * aabb.get_center()))
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		var material := source.surface_get_material(surface).duplicate() as StandardMaterial3D
		if surface == 0:
			material.albedo_color = FLOOR_SNOW_ALBEDO
		st.set_material(material)
		st.commit(assembled)
	root.free()
	_floor_meshes[key] = assembled
	return assembled


func _is_interactable() -> bool:
	if box.movable_3d_from_any_side():
		return true
	for facing: Box.Facing in Box.Facing.values():
		if box.movable_2d_from(facing):
			return true
	return false


func _is_movable_3d_all_sides() -> bool:
	for facing: Box.Facing in Box.Facing.values():
		if not box.movable_3d_from(facing):
			return false
	return true


func _has_handle_on(facing: Box.Facing) -> bool:
	if not box.movable_2d_whole_face and box.movable_2d_from(facing):
		return true
	if box.movable_3d_from(facing) and (box.walkable or not _is_movable_3d_all_sides()):
		return true
	return false


static func _wall_mesh(top_half_only: bool, quarter_turns: Vector3i) -> ArrayMesh:
	var key := Vector4i(int(top_half_only), quarter_turns.x, quarter_turns.y, quarter_turns.z)
	if _wall_meshes.has(key):
		return _wall_meshes[key]
	var root := WALL_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var bottom_y := 0.0 if top_half_only else -0.5
	var target_size := Vector3(1.0, 0.5 - bottom_y, 1.0)
	var target_centre := Vector3(0.0, (0.5 + bottom_y) / 2.0, 0.0)
	var unit_scale := Basis.from_scale(Vector3.ONE / aabb.size)
	var normalize_transform := Transform3D(unit_scale, -(unit_scale * aabb.get_center()))
	var turn := Basis.from_euler(Vector3(quarter_turns) * (PI / 2.0))
	var target_transform := Transform3D(Basis.from_scale(target_size) * turn, target_centre)
	var fit := target_transform * normalize_transform
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		var material := source.surface_get_material(surface).duplicate() as StandardMaterial3D
		material.albedo_color = FLOOR_SNOW_ALBEDO
		st.set_material(material)
		st.commit(assembled)
	root.free()
	_wall_meshes[key] = assembled
	return assembled


static func _interactable_mesh(top_half_only: bool, quarter_turns: Vector3i) -> ArrayMesh:
	var key := Vector4i(int(top_half_only), quarter_turns.x, quarter_turns.y, quarter_turns.z)
	if _interactable_meshes.has(key):
		return _interactable_meshes[key]
	var root := INTERACTABLE_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var bottom_y := 0.0 if top_half_only else -0.5
	var target_size := Vector3(1.0, 0.5 - bottom_y, 1.0)
	var target_centre := Vector3(0.0, (0.5 + bottom_y) / 2.0, 0.0)
	var unit_scale := Basis.from_scale(Vector3.ONE / aabb.size)
	var normalize_transform := Transform3D(unit_scale, -(unit_scale * aabb.get_center()))
	var turn := Basis.from_euler(Vector3(quarter_turns) * (PI / 2.0))
	var target_transform := Transform3D(Basis.from_scale(target_size) * turn, target_centre)
	var fit := target_transform * normalize_transform
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		st.set_material(source.surface_get_material(surface))
		st.commit(assembled)
	root.free()
	_interactable_meshes[key] = assembled
	return assembled


static func _stone_mesh(top_half_only: bool, quarter_turns: Vector3i) -> ArrayMesh:
	var key := Vector4i(int(top_half_only), quarter_turns.x, quarter_turns.y, quarter_turns.z)
	if _stone_meshes.has(key):
		return _stone_meshes[key]
	var root := STONE_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var bottom_y := 0.0 if top_half_only else -0.5
	var target_size := Vector3(1.0, 0.5 - bottom_y, 1.0)
	var target_centre := Vector3(0.0, (0.5 + bottom_y) / 2.0, 0.0)
	var unit_scale := Basis.from_scale(Vector3.ONE / aabb.size)
	var normalize_transform := Transform3D(unit_scale, -(unit_scale * aabb.get_center()))
	var turn := Basis.from_euler(Vector3(quarter_turns) * (PI / 2.0))
	var target_transform := Transform3D(Basis.from_scale(target_size) * turn, target_centre)
	var fit := target_transform * normalize_transform
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		st.set_material(source.surface_get_material(surface))
		st.commit(assembled)
	root.free()
	_stone_meshes[key] = assembled
	return assembled


static func _snow_mesh(top_half_only: bool) -> ArrayMesh:
	if _snow_meshes.has(top_half_only):
		return _snow_meshes[top_half_only]
	var root := SNOW_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var bottom_y := 0.0 if top_half_only else -0.5
	var ref_size := Vector3(2.0, aabb.end.y - (-1.0), 2.0)
	var ref_centre := Vector3(0.0, (-1.0 + aabb.end.y) / 2.0, 0.0)
	var target_size := Vector3(1.02, 0.5 - bottom_y, 1.02)
	var target_centre := Vector3(0.0, (0.5 + bottom_y) / 2.0 + TILE_LIFT, 0.0)
	var scale_vec := target_size / ref_size
	var fit := Transform3D(Basis.from_scale(scale_vec), target_centre - scale_vec * ref_centre)
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		var material := source.surface_get_material(surface).duplicate() as StandardMaterial3D
		material.albedo_color = FLOOR_SNOW_ALBEDO
		st.set_material(material)
		st.commit(assembled)
	root.free()
	_snow_meshes[top_half_only] = assembled
	return assembled


static func _handle_mesh(top_half_only: bool, on_walkable: bool, facing: Box.Facing) -> ArrayMesh:
	var key := Vector3i(int(top_half_only), int(on_walkable), facing)
	if _handle_meshes.has(key):
		return _handle_meshes[key]
	var root := HANDLE_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var bottom_y := 0.0 if top_half_only else -0.5
	var horizontal_scale := 0.58 if on_walkable else 0.501
	var y_lift := 0.022 if on_walkable else 0.0
	var scale_vec := Vector3(horizontal_scale, (0.5 - bottom_y) / 2.0, horizontal_scale)
	var offset := Vector3(0.0, (0.5 + bottom_y) / 2.0 + y_lift, 0.0)
	var base_transform := Transform3D(Basis.from_scale(scale_vec), offset)
	var direction := Box.FACING_DIRECTION[facing]
	var angle := atan2(-direction.y, direction.x)
	var fit := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * base_transform
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		st.set_material(source.surface_get_material(surface))
		st.commit(assembled)
	root.free()
	_handle_meshes[key] = assembled
	return assembled


static func _append_mesh(dest: ArrayMesh, source: Mesh) -> void:
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		dest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		dest.surface_set_material(dest.get_surface_count() - 1, source.surface_get_material(surface))


func _procedural_wall_mesh() -> ArrayMesh:
	var top_y := 0.5
	var bottom_y := 0.0 if box.top_half_only else -0.5
	var side_top_y := top_y - WALKABLE_SIDES_DISPLAY if box.walkable else top_y
	var top_lo := Vector3(-0.5, top_y, -0.5)
	var top_hi := Vector3(0.5, top_y, 0.5)
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
		_bordered_rect(st, face_lo, face_hi, normal)

	if box.walkable:
		_bordered_rect(st, top_lo, top_hi, Vector3.UP)
	else:
		_rect(st, top_lo, top_hi, Vector3.UP, static_colour)

	# Cara de abajo.
	_rect(st, Vector3(-0.5, bottom_y, -0.5), Vector3(0.5, bottom_y, 0.5), Vector3.DOWN, static_colour)

	st.set_material(_material_with_vertex_colours())
	return st.commit()


static func _material_with_vertex_colours() -> StandardMaterial3D:
	if _vertex_colour_material == null:
		_vertex_colour_material = StandardMaterial3D.new()
		_vertex_colour_material.vertex_color_use_as_albedo = true
	return _vertex_colour_material


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
