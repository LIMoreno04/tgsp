@tool
extends MeshInstance3D
## Dibuja una caja a partir de sus propios flags, y de su estructura: las cajas de una misma
## estructura que se tocan cara a cara se funden en un solo bloque (los biseles de la unión
## desaparecen), y cada estructura tiene su color de la paleta.


var box: Box:
	get:
		return get_parent() as Box

const MOVABLE_STRIPE_WIDTH := 0.15
const TILE_LIFT := 0.001
const FLOOR_HORIZONTAL_SCALE := 1.05
const FLOOR_SNOW_ALBEDO := Color(0.74, 0.80, 0.86)
## Las paredes son hielo azulado, no nieve, para que desde arriba una pared no parezca piso.
const WALL_ICE_ALBEDO := Color(0.60, 0.71, 0.85)
const SNOW_CAP_HORIZONTAL_SCALE := 1.02
## Qué tan hondo entra el bisel de los modelos de caja, como fracción de su tamaño.
const BOX_BEVEL_DEPTH := 0.075
## Hasta dónde llega la meseta de la tapa de nieve antes de redondearse y caer por los lados.
const SNOW_CAP_LIP_DEPTH := 0.02
const SEAM_EPSILON := 0.0001

## Los seis lados de una caja, en direcciones de grilla. En una máscara de lados, el bit i es el lado i.
const SIDES: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const HORIZONTAL_SIDES := 0b001111
const SIDE_UP := 0b010000
const SIDE_DOWN := 0b100000

const FLOOR_MODEL: PackedScene = preload("res://art/boxes/Suelo_nieve_hielo.glb")
const WALL_MODEL: PackedScene = preload("res://art/boxes/Pared_Nieve.glb")
const INTERACTABLE_MODEL: PackedScene = preload("res://art/boxes/Caja_interactuable_Hielo.glb")
const STONE_MODEL: PackedScene = preload("res://art/boxes/Caja_inamovible_Piedra.glb")
const SNOW_MODEL: PackedScene = preload("res://art/boxes/Walkable_Nieve.glb")
const HANDLE_MODEL: PackedScene = preload("res://art/boxes/Handle_Hielo.glb")

static var _floor_meshes: Dictionary[Vector2i, ArrayMesh] = {}
static var _wall_meshes: Dictionary[Vector4i, ArrayMesh] = {}
static var _interactable_meshes: Dictionary[Array, ArrayMesh] = {}
static var _stone_meshes: Dictionary[Array, ArrayMesh] = {}
static var _snow_meshes: Dictionary[Vector2i, ArrayMesh] = {}
static var _handle_meshes: Dictionary[Vector3i, ArrayMesh] = {}
## Los materiales de cada modelo, tomados una vez: todas las copias los comparten, y así una
## superficie dice de qué modelo y de qué parte es (0 el cuerpo, 1 el detalle).
static var _model_materials: Dictionary[PackedScene, Array] = {}
static var _model_meshes: Dictionary[PackedScene, Mesh] = {}
static var _coloured_materials: Dictionary[Material, Dictionary] = {}

var _rebuild_pending := false
var _fusion_check_pending := false
## Los lados que tocan una caja de la misma estructura, como se dibujan ahora y como deberían.
## Difieren mientras una unión espera a que termine el deslizamiento.
var _fused_sides_shown := 0
var _fused_sides_wanted := 0


func _ready() -> void:
	box.appearance_changed.connect(_request_rebuild)
	_fused_sides_wanted = _sides_touching_the_same_structure()
	_fused_sides_shown = _fused_sides_wanted
	_request_rebuild()

## La caja puede cambiar de estructura en el editor, así que se escucha a la de cada entrada al árbol.
func _enter_tree() -> void:
	var structure := box.get_parent()
	if GridEntity.global_name_of(structure) == &"Structure":
		structure.layout_changed.connect(_request_fusion_check)

func _exit_tree() -> void:
	var structure := box.get_parent()
	if GridEntity.global_name_of(structure) == &"Structure" and structure.layout_changed.is_connected(_request_fusion_check):
		structure.layout_changed.disconnect(_request_fusion_check)


# --- Fusión ---------------------------------------------------------------

## Al final del frame, para ver juntas todas las cajas que un movimiento cambió de celda.
func _request_fusion_check() -> void:
	if _fusion_check_pending:
		return
	_fusion_check_pending = true
	_check_fusion.call_deferred()

## Una grieta se abre apenas empieza el deslizamiento; una unión espera a que termine.
func _check_fusion() -> void:
	_fusion_check_pending = false
	if not is_inside_tree():
		return
	_fused_sides_wanted = _sides_touching_the_same_structure()
	if _fused_sides_wanted == _fused_sides_shown:
		return
	if Engine.is_editor_hint():
		_show_fused_sides(_fused_sides_wanted)
		return
	_show_fused_sides(_fused_sides_shown & _fused_sides_wanted)
	var wanted := _fused_sides_wanted
	get_tree().create_timer(GridEntity.SLIDE_SECONDS).timeout.connect(func() -> void:
		if is_inside_tree() and _fused_sides_wanted == wanted:
			_show_fused_sides(wanted)
	)

func _show_fused_sides(sides: int) -> void:
	if sides == _fused_sides_shown:
		return
	_fused_sides_shown = sides
	_request_rebuild()


## Una máscara de SIDES. Misma estructura y cara con cara, igual que lo que se mueve junto en 3D.
func _sides_touching_the_same_structure() -> int:
	var structure := box.get_parent()
	if GridEntity.global_name_of(structure) != &"Structure" or box.is_terrain():
		return 0
	var occupied: Dictionary[Vector3i, bool] = {}
	for sibling in structure.get_children():
		if sibling is Box:
			occupied[sibling.cell] = true
	var sides := 0
	for i in SIDES.size():
		if occupied.has(box.cell + SIDES[i]):
			sides |= 1 << i
	return sides

func _is_fused_toward(facing: Box.Facing) -> bool:
	var direction := Box.FACING_DIRECTION[facing]
	return _fused_sides_shown & (1 << SIDES.find(Vector3i(direction.x, direction.y, 0))) != 0


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

	var structure := StructurePalette.structure_of(box)
	var random := RandomNumberGenerator.new()
	random.seed = hash(box.name) ^ _seed_of(structure)
	var turns := Vector3i(random.randi_range(0, 3), random.randi_range(0, 3), random.randi_range(0, 3))

	var is_interactable := _is_interactable()
	var fused := _fused_sides_shown
	if box.top_half_only:
		fused &= ~SIDE_DOWN # Media caja no llega a tocar a la de abajo.
	var base_mesh: ArrayMesh = _interactable_mesh(box.top_half_only, turns, fused) if is_interactable else _stone_mesh(box.top_half_only, turns, fused)

	var assembled := ArrayMesh.new()
	_append_mesh(assembled, base_mesh)
	if box.walkable:
		_append_mesh(assembled, _snow_mesh(box.top_half_only, fused & HORIZONTAL_SIDES))
	if is_interactable:
		for facing: Box.Facing in Box.Facing.values():
			if _has_handle_on(facing) and not _is_fused_toward(facing):
				_append_mesh(assembled, _handle_mesh(box.top_half_only, box.walkable, facing))
	mesh = assembled
	_paint_with_the_colour_of(structure, is_interactable)


## El cuerpo y el detalle (escarcha o vetas) de la caja y de sus asas, del color de su estructura.
func _paint_with_the_colour_of(structure: GridEntity, is_interactable: bool) -> void:
	var ice := _ice_colour_of(structure)
	var body := ice if is_interactable else StructurePalette.stone_from(ice)
	var detail := StructurePalette.frost_colour(ice) if is_interactable else StructurePalette.vein_colour(ice)
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		match _part_drawn_by(material):
			&"body":
				set_surface_override_material(surface, _coloured(material, body))
			&"detail":
				set_surface_override_material(surface, _coloured(material, detail))
			_:
				set_surface_override_material(surface, null)

func _ice_colour_of(structure: GridEntity) -> Color:
	var room := structure.room_above()
	if room == null:
		return StructurePalette.ICE[0]
	var palette: StructurePalette = room.get(&"structure_palette")
	return palette.ice_colour_of(structure)

static func _part_drawn_by(material: Material) -> StringName:
	for model in [INTERACTABLE_MODEL, STONE_MODEL, HANDLE_MODEL]:
		var materials := _materials_of(model)
		if material == materials[0]:
			return &"body"
		if material == materials[1]:
			return &"detail"
	return &""

static func _coloured(base: Material, colour: Color) -> StandardMaterial3D:
	if not _coloured_materials.has(base):
		_coloured_materials[base] = {}
	var by_colour: Dictionary = _coloured_materials[base]
	if not by_colour.has(colour):
		var material := base.duplicate() as StandardMaterial3D
		material.albedo_color = colour
		by_colour[colour] = material
	return by_colour[colour]


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
	var fit := _fit_of_a_box_model(source.get_aabb(), top_half_only, quarter_turns)
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		var material := source.surface_get_material(surface).duplicate() as StandardMaterial3D
		material.albedo_color = WALL_ICE_ALBEDO
		st.set_material(material)
		st.commit(assembled)
	root.free()
	_wall_meshes[key] = assembled
	return assembled


static func _interactable_mesh(top_half_only: bool, quarter_turns: Vector3i, fused_sides := 0) -> ArrayMesh:
	return _box_model_mesh(INTERACTABLE_MODEL, _interactable_meshes, top_half_only, quarter_turns, fused_sides)

static func _stone_mesh(top_half_only: bool, quarter_turns: Vector3i, fused_sides := 0) -> ArrayMesh:
	return _box_model_mesh(STONE_MODEL, _stone_meshes, top_half_only, quarter_turns, fused_sides)

static func _box_model_mesh(model: PackedScene, cache: Dictionary[Array, ArrayMesh], top_half_only: bool, quarter_turns: Vector3i, fused_sides: int) -> ArrayMesh:
	var key := [top_half_only, quarter_turns, fused_sides]
	if cache.has(key):
		return cache[key]
	var source := _source_mesh_of(model)
	var fit := _fit_of_a_box_model(source.get_aabb(), top_half_only, quarter_turns)
	var bottom_y := 0.0 if top_half_only else -0.5
	var depths := Vector3(BOX_BEVEL_DEPTH, BOX_BEVEL_DEPTH * (0.5 - bottom_y), BOX_BEVEL_DEPTH)
	var assembled := _fitted_copy(source, fit, _materials_of(model), fused_sides, bottom_y, depths)
	cache[key] = assembled
	return assembled

## Lleva un modelo de caja (un cubo de 2 de lado centrado en el origen) a la celda: 1 de lado, o la
## mitad de arriba, girado en cuartos de vuelta para que no se repitan los detalles.
static func _fit_of_a_box_model(aabb: AABB, top_half_only: bool, quarter_turns: Vector3i) -> Transform3D:
	var bottom_y := 0.0 if top_half_only else -0.5
	var target_size := Vector3(1.0, 0.5 - bottom_y, 1.0)
	var target_centre := Vector3(0.0, (0.5 + bottom_y) / 2.0, 0.0)
	var unit_scale := Basis.from_scale(Vector3.ONE / aabb.size)
	var normalize_transform := Transform3D(unit_scale, -(unit_scale * aabb.get_center()))
	var turn := Basis.from_euler(Vector3(quarter_turns) * (PI / 2.0))
	var target_transform := Transform3D(Basis.from_scale(target_size) * turn, target_centre)
	return target_transform * normalize_transform


static func _snow_mesh(top_half_only: bool, fused_sides := 0) -> ArrayMesh:
	var key := Vector2i(int(top_half_only), fused_sides)
	if _snow_meshes.has(key):
		return _snow_meshes[key]
	var source := _source_mesh_of(SNOW_MODEL)
	var aabb := source.get_aabb()
	var bottom_y := 0.0 if top_half_only else -0.5
	var ref_size := Vector3(2.0, aabb.end.y - (-1.0), 2.0)
	var ref_centre := Vector3(0.0, (-1.0 + aabb.end.y) / 2.0, 0.0)
	var target_size := Vector3(SNOW_CAP_HORIZONTAL_SCALE, 0.5 - bottom_y, SNOW_CAP_HORIZONTAL_SCALE)
	var target_centre := Vector3(0.0, (0.5 + bottom_y) / 2.0 + TILE_LIFT, 0.0)
	var scale_vec := target_size / ref_size
	var fit := Transform3D(Basis.from_scale(scale_vec), target_centre - scale_vec * ref_centre)
	var materials: Array[Material] = []
	for surface in source.get_surface_count():
		var material := source.surface_get_material(surface).duplicate() as StandardMaterial3D
		material.albedo_color = FLOOR_SNOW_ALBEDO
		materials.append(material)
	var depths := Vector3(SNOW_CAP_LIP_DEPTH, 0.0, SNOW_CAP_LIP_DEPTH)
	var assembled := _fitted_copy(source, fit, materials, fused_sides & HORIZONTAL_SIDES, bottom_y, depths)
	_snow_meshes[key] = assembled
	return assembled


static func _handle_mesh(top_half_only: bool, on_walkable: bool, facing: Box.Facing) -> ArrayMesh:
	var key := Vector3i(int(top_half_only), int(on_walkable), facing)
	if _handle_meshes.has(key):
		return _handle_meshes[key]
	var source := _source_mesh_of(HANDLE_MODEL)
	var bottom_y := 0.0 if top_half_only else -0.5
	var horizontal_scale := 0.585 if on_walkable else 0.56
	var y_lift := 0.022 if on_walkable else 0.012
	var scale_vec := Vector3(horizontal_scale, (0.5 - bottom_y) / 2.0, horizontal_scale)
	var offset := Vector3(0.0, (0.5 + bottom_y) / 2.0 + y_lift, 0.0)
	var base_transform := Transform3D(Basis.from_scale(scale_vec), offset)
	var direction := Box.FACING_DIRECTION[facing]
	var angle := atan2(-direction.y, direction.x)
	var fit := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * base_transform
	var materials := _materials_of(HANDLE_MODEL)
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		st.set_material(materials[surface])
		st.commit(assembled)
	_handle_meshes[key] = assembled
	return assembled


## Copia `source` llevada por `fit`, con `materials` por superficie. En cada lado fundido, lo que
## está a menos de `depths` (por eje) del borde se aplana contra el plano de la unión, así las caras
## vecinas siguen planas de una caja a la otra. La cara que queda sobre ese plano no se copia, porque
## la caja vecina la tapa; tampoco los triángulos que el aplanado dejó sin área.
static func _fitted_copy(source: Mesh, fit: Transform3D, materials: Array, fused_sides: int, bottom_y: float, depths: Vector3) -> ArrayMesh:
	var seams := _seams(fused_sides, bottom_y)
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var triangles := 0
		for first in range(0, indices.size(), 3):
			var corners: Array[Vector3] = []
			for k in 3:
				corners.append(_flattened_onto_the_seams(fit * vertices[indices[first + k]], seams, depths))
			if _has_no_area(corners) or _lies_on_a_seam(corners, seams):
				continue
			for corner in corners:
				st.add_vertex(corner)
			triangles += 1
		if triangles == 0:
			continue
		st.generate_normals()
		st.set_material(materials[surface])
		st.commit(assembled)
	return assembled

## Cada lado fundido como un plano: el eje (0 x, 1 y, 2 z), el signo hacia afuera y dónde está.
static func _seams(fused_sides: int, bottom_y: float) -> Array[Vector3]:
	var seams: Array[Vector3] = []
	for i in SIDES.size():
		if fused_sides & (1 << i) == 0:
			continue
		var outward := GridCoordsProvider.grid_to_godot(SIDES[i])
		var axis := 0
		while outward[axis] == 0.0:
			axis += 1
		var sign := signf(outward[axis])
		var extent := bottom_y if SIDES[i] == Vector3i(0, 0, -1) else 0.5 * sign
		seams.append(Vector3(axis, sign, extent))
	return seams

static func _flattened_onto_the_seams(vertex: Vector3, seams: Array[Vector3], depths: Vector3) -> Vector3:
	for seam in seams:
		var axis := int(seam.x)
		var sign := seam.y
		var extent := seam.z
		if vertex[axis] * sign >= extent * sign - depths[axis] - SEAM_EPSILON:
			vertex[axis] = extent
	return vertex

static func _has_no_area(corners: Array[Vector3]) -> bool:
	return (corners[1] - corners[0]).cross(corners[2] - corners[0]).length_squared() < SEAM_EPSILON * SEAM_EPSILON

static func _lies_on_a_seam(corners: Array[Vector3], seams: Array[Vector3]) -> bool:
	for seam in seams:
		var axis := int(seam.x)
		var on_it := true
		for corner in corners:
			if not is_equal_approx(corner[axis], seam.z):
				on_it = false
				break
		if on_it:
			return true
	return false


static func _materials_of(model: PackedScene) -> Array:
	if not _model_materials.has(model):
		var source := _source_mesh_of(model)
		var materials: Array[Material] = []
		for surface in source.get_surface_count():
			materials.append(source.surface_get_material(surface))
		_model_materials[model] = materials
	return _model_materials[model]

## La malla de un modelo, sacada de su escena una sola vez.
static func _source_mesh_of(model: PackedScene) -> Mesh:
	if not _model_meshes.has(model):
		var root := model.instantiate()
		_model_meshes[model] = (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		root.free()
	return _model_meshes[model]


static func _append_mesh(dest: ArrayMesh, source: Mesh) -> void:
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		dest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		dest.surface_set_material(dest.get_surface_count() - 1, source.surface_get_material(surface))


## Su camino dentro del Room, que no se repite entre carpetas como la posición entre hermanos.
func _seed_of(structure: GridEntity) -> int:
	var room := structure.room_above()
	if room == null:
		return structure.get_index()
	return str(room.get_path_to(structure)).hash()
