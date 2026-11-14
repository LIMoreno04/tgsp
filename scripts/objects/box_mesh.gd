@tool
extends MeshInstance3D
## Dibuja una caja a partir de sus propios flags, y de su estructura: las cajas de una misma
## estructura que se tocan cara a cara se funden en un solo bloque (los biseles de la unión
## desaparecen), y cada estructura tiene su color de la paleta.
## Una caja es de roca, y cada flag le pone lo suyo: hielo en cada cara lateral con agarre 3D, una
## franja de hielo sobre cada borde de la tapa con agarre 2D (la tapa entera si es toda agarre 2D)
## y una capa de nieve si se puede caminar.


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
## La franja de agarre 2D: hielo sobre el borde de la tapa, que cuelga un poco por el lado. Va en
## tramos de distinto ancho y distinto largo, como termina la nieve, para que no corte en línea recta.
const STRIPE_SEGMENTS := 6
const STRIPE_THICKNESS := 0.015
## Cuánto sale de la caja lo que cuelga. Sobre una tapa de nieve, más, para pasar por fuera de la
## nieve que cae por el lado, que sale 0.08.
const STRIPE_HANG_OUT := 0.02
const STRIPE_HANG_OUT_OVER_SNOW := 0.09
## Lo que se le suma a MOVABLE_STRIPE_WIDTH en cada tramo.
const STRIPE_WIDTH_STEPS: Array[float] = [-0.03, 0.0, 0.03]
## Cuánto cuelga cada tramo, como fracción del alto de la caja.
const STRIPE_HANG_LENGTHS: Array[float] = [0.10, 0.16, 0.22]
const STRIPE_VARIANTS := 4
## Hasta dónde es plana una cara de los modelos de caja antes de empezar el bisel, como fracción
## de la mitad de su tamaño.
const BOX_FLAT_PART := 0.865
## Donde una cara de hielo se encuentra con una de roca, la roca entra un poco en la de hielo, en
## dientes de distinto largo (fracciones del tamaño de la caja; 0 es sin diente), para que el borde
## no sea una línea recta. Siempre dentro de la cara de hielo: en la otra se leería como un agarre.
const ROCK_TEETH_PER_EDGE := 6
const ROCK_TEETH_LENGTHS: Array[float] = [0.0, 0.03, 0.06]
const ROCK_TEETH_LIFT := 0.002

## Los seis lados de una caja, en direcciones de grilla. En una máscara de lados, el bit i es el lado i.
const SIDES: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const HORIZONTAL_SIDES := 0b001111
const SIDE_UP := 0b010000
const SIDE_DOWN := 0b100000
const EVERY_SIDE := 0b111111
## Para _fitted_copy: copiar el modelo entero, sin elegir entre hielo y roca.
const WHOLE_MODEL := -1

const FLOOR_MODEL: PackedScene = preload("res://art/boxes/Suelo_nieve_hielo.glb")
const WALL_MODEL: PackedScene = preload("res://art/boxes/Pared_Nieve.glb")
const INTERACTABLE_MODEL: PackedScene = preload("res://art/boxes/Caja_interactuable_Hielo.glb")
const STONE_MODEL: PackedScene = preload("res://art/boxes/Caja_inamovible_Piedra.glb")
const SNOW_MODEL: PackedScene = preload("res://art/boxes/Walkable_Nieve.glb")

static var _floor_meshes: Dictionary[Vector2i, ArrayMesh] = {}
static var _wall_meshes: Dictionary[Vector4i, ArrayMesh] = {}
static var _body_meshes: Dictionary[Array, ArrayMesh] = {}
static var _snow_meshes: Dictionary[Vector2i, ArrayMesh] = {}
static var _stripe_meshes: Dictionary[Array, ArrayMesh] = {}
static var _rock_teeth_meshes: Dictionary[Array, ArrayMesh] = {}
static var _unit_cube := BoxMesh.new()
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
	box.appearance_changed.connect(_request_fusion_check) # El terreno no se funde, y eso también es un flag.
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
	return _fused_sides_shown & _side_toward(facing) != 0

## El lado de SIDES hacia donde mira `facing`, como máscara.
static func _side_toward(facing: Box.Facing) -> int:
	var direction := Box.FACING_DIRECTION[facing]
	return 1 << SIDES.find(Vector3i(direction.x, direction.y, 0))


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

	var stripe_variant := random.randi_range(0, STRIPE_VARIANTS - 1)

	var fused := _fused_sides_shown
	if box.top_half_only:
		fused &= ~SIDE_DOWN # Media caja no llega a tocar a la de abajo.
	# Los lados que no se ven: no deciden de qué es el bisel que los une con otro.
	var unseen := fused | SIDE_DOWN
	if box.walkable:
		unseen |= SIDE_UP

	var assembled := ArrayMesh.new()
	_append_mesh(assembled, _body_mesh(box.top_half_only, turns, fused, _ice_sides(), unseen))
	_append_mesh(assembled, _rock_teeth_mesh(box.top_half_only, _ice_sides(), unseen, stripe_variant))
	if box.walkable:
		_append_mesh(assembled, _snow_mesh(box.top_half_only, fused & HORIZONTAL_SIDES))
	for facing: Box.Facing in Box.Facing.values():
		if _has_stripe_on(facing):
			_append_mesh(assembled, _stripe_mesh(box.top_half_only, box.walkable, facing, _is_fused_toward(facing), (stripe_variant + facing) % STRIPE_VARIANTS))
	mesh = assembled
	_paint_with_the_colour_of(structure)


## El hielo y su escarcha, la roca y sus vetas, del color de su estructura.
func _paint_with_the_colour_of(structure: GridEntity) -> void:
	var ice := _ice_colour_of(structure)
	var ice_materials := _materials_of(INTERACTABLE_MODEL)
	var stone_materials := _materials_of(STONE_MODEL)
	var colours: Dictionary[Material, Color] = {
		ice_materials[0]: ice,
		ice_materials[1]: StructurePalette.frost_colour(ice),
		stone_materials[0]: StructurePalette.stone_from(ice),
		stone_materials[1]: StructurePalette.vein_colour(ice),
	}
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if colours.has(material):
			set_surface_override_material(surface, _coloured(material, colours[material]))
		else:
			set_surface_override_material(surface, null)

func _ice_colour_of(structure: GridEntity) -> Color:
	var room := structure.room_above()
	if room == null:
		return StructurePalette.ICE[0]
	var palette: StructurePalette = room.get(&"structure_palette")
	return palette.ice_colour_of(structure)

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


## Una máscara de SIDES: las caras de hielo. Cada cara lateral con agarre 3D, y la tapa si toda ella
## es agarre 2D.
func _ice_sides() -> int:
	var sides := 0
	for facing: Box.Facing in Box.Facing.values():
		if box.movable_3d_from(facing):
			sides |= _side_toward(facing)
	if box.movable_2d_from_every_side():
		sides |= SIDE_UP
	return sides


## Una tapa que es toda agarre 2D ya es de hielo entera. En un lado fundido no hay de dónde agarrar,
## y la franja sólo importa sobre una tapa caminable, donde en 2D es una barrera entre las dos baldosas.
func _has_stripe_on(facing: Box.Facing) -> bool:
	if box.movable_2d_whole_face or not box.movable_2d_from(facing):
		return false
	return box.walkable or not _is_fused_toward(facing)


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


## El cuerpo de una caja: de roca, con las caras de `ice_sides` de hielo. Los dos modelos tienen la
## misma forma, así que cada triángulo se toma de uno o del otro.
static func _body_mesh(top_half_only: bool, quarter_turns: Vector3i, fused_sides: int, ice_sides: int, unseen_sides: int) -> ArrayMesh:
	var key := [top_half_only, quarter_turns, fused_sides, ice_sides, unseen_sides]
	if _body_meshes.has(key):
		return _body_meshes[key]
	var bottom_y := 0.0 if top_half_only else -0.5
	var depths := Vector3(BOX_BEVEL_DEPTH, BOX_BEVEL_DEPTH * (0.5 - bottom_y), BOX_BEVEL_DEPTH)
	var assembled := ArrayMesh.new()
	for model: PackedScene in [STONE_MODEL, INTERACTABLE_MODEL]:
		var source := _source_mesh_of(model)
		var fit := _fit_of_a_box_model(source.get_aabb(), top_half_only, quarter_turns)
		_append_mesh(assembled, _fitted_copy(source, fit, _materials_of(model), fused_sides, bottom_y, depths, ice_sides, unseen_sides, model == INTERACTABLE_MODEL))
	_body_meshes[key] = assembled
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


## La franja de agarre 2D de un borde, hecha de tramos: cada uno es una losa sobre la tapa, que
## también rellena el bisel, y un trozo que cuelga por la cara lateral. `variant` elige los anchos y
## los largos. En un lado fundido termina en la unión y no cuelga.
static func _stripe_mesh(top_half_only: bool, on_snow: bool, facing: Box.Facing, is_fused: bool, variant: int) -> ArrayMesh:
	var key := [top_half_only, on_snow, facing, is_fused, variant]
	if _stripe_meshes.has(key):
		return _stripe_meshes[key]
	var height := 0.5 if top_half_only else 1.0
	var hang_out := 0.0
	var past_the_ends := 0.0
	if not is_fused:
		hang_out = STRIPE_HANG_OUT_OVER_SNOW if on_snow else STRIPE_HANG_OUT
		past_the_ends = STRIPE_HANG_OUT
	var slab_top := 0.5 + STRIPE_THICKNESS
	var slab_bottom := 0.5 - BOX_BEVEL_DEPTH * height
	var segment_length := (1.0 + 2.0 * past_the_ends) / STRIPE_SEGMENTS
	# Se arma mirando hacia +x y se gira hacia su lado.
	var direction := Box.FACING_DIRECTION[facing]
	var turn := Basis(Vector3.UP, atan2(-direction.y, direction.x))
	var random := RandomNumberGenerator.new()
	random.seed = hash(variant)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in STRIPE_SEGMENTS:
		var from := -0.5 - past_the_ends + segment * segment_length
		var to := from + segment_length
		var width := MOVABLE_STRIPE_WIDTH + STRIPE_WIDTH_STEPS[random.randi() % STRIPE_WIDTH_STEPS.size()]
		var hang := STRIPE_HANG_LENGTHS[random.randi() % STRIPE_HANG_LENGTHS.size()] * height
		_add_cuboid(st, Vector3(0.5 - width, slab_bottom, from), Vector3(0.5 + hang_out, slab_top, to), turn)
		if not is_fused:
			_add_cuboid(st, Vector3(0.5, 0.5 - hang, from), Vector3(0.5 + hang_out, slab_bottom, to), turn)
	st.set_material(_materials_of(INTERACTABLE_MODEL)[0]) # Sin generate_normals: las del cubo ya son planas, y suavizadas parecerían almohadones.
	var assembled := st.commit()
	_stripe_meshes[key] = assembled
	return assembled

## Los dientes de roca de una caja: por cada cara de hielo, a lo largo de cada borde que comparte
## con una cara de roca que se ve, unas placas finas de roca apoyadas sobre la cara de hielo, desde
## donde empieza el bisel (que ahí ya es de roca) hacia adentro.
static func _rock_teeth_mesh(top_half_only: bool, ice_sides: int, unseen_sides: int, variant: int) -> ArrayMesh:
	var key := [top_half_only, ice_sides, unseen_sides, variant]
	if _rock_teeth_meshes.has(key):
		return _rock_teeth_meshes[key]
	var bottom_y := 0.0 if top_half_only else -0.5
	var centre := Vector3(0.0, (0.5 + bottom_y) / 2.0, 0.0)
	var half_size := Vector3(0.5, (0.5 - bottom_y) / 2.0, 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var teeth := 0
	for ice in SIDES.size():
		if ice_sides & (1 << ice) == 0 or unseen_sides & (1 << ice) != 0:
			continue
		for rock in SIDES.size():
			if (ice_sides | unseen_sides) & (1 << rock) != 0 or SIDES[rock] == SIDES[ice] or SIDES[rock] == -SIDES[ice]:
				continue
			# Tres ejes: hacia afuera de la cara de hielo, hacia la cara de roca y a lo largo del borde.
			var outward := GridCoordsProvider.grid_to_godot(SIDES[ice])
			var toward_the_rock := GridCoordsProvider.grid_to_godot(SIDES[rock])
			var along := outward.cross(toward_the_rock)
			var on_the_face := centre + outward * absf(outward.dot(half_size))
			var where_the_bevel_starts := toward_the_rock * absf(toward_the_rock.dot(half_size)) * BOX_FLAT_PART
			var half_edge := along * absf(along.dot(half_size)) * BOX_FLAT_PART
			var random := RandomNumberGenerator.new()
			random.seed = hash([variant, ice, rock])
			for tooth in ROCK_TEETH_PER_EDGE:
				var length := ROCK_TEETH_LENGTHS[random.randi() % ROCK_TEETH_LENGTHS.size()] * 2.0 * absf(toward_the_rock.dot(half_size))
				if length == 0.0:
					continue
				var from := -1.0 + 2.0 * tooth / ROCK_TEETH_PER_EDGE
				var to := -1.0 + 2.0 * (tooth + 1) / ROCK_TEETH_PER_EDGE
				var one_corner := on_the_face + where_the_bevel_starts - toward_the_rock * length + half_edge * from
				var other_corner := on_the_face + outward * ROCK_TEETH_LIFT + where_the_bevel_starts + half_edge * to
				_add_cuboid(st, one_corner.min(other_corner), one_corner.max(other_corner), Basis.IDENTITY)
				teeth += 1
	var assembled := ArrayMesh.new()
	if teeth > 0:
		st.set_material(_materials_of(STONE_MODEL)[0])
		st.commit(assembled)
	_rock_teeth_meshes[key] = assembled
	return assembled

## Un prisma alineado a los ejes, de la esquina `lo` a la esquina `hi`, girado por `turn`.
static func _add_cuboid(st: SurfaceTool, lo: Vector3, hi: Vector3, turn: Basis) -> void:
	st.append_from(_unit_cube, 0, Transform3D(turn * Basis.from_scale(hi - lo), turn * ((lo + hi) / 2.0)))


## Copia `source` llevada por `fit`, con `materials` por superficie. En cada lado fundido, lo que
## está a menos de `depths` (por eje) del borde se aplana contra el plano de la unión, así las caras
## vecinas siguen planas de una caja a la otra. La cara que queda sobre ese plano no se copia, porque
## la caja vecina la tapa; tampoco los triángulos que el aplanado dejó sin área.
## Con `ice_sides` (una máscara de SIDES) sólo se copia la parte del modelo que va de hielo, o la que
## no, según `the_part_in_ice`: así una caja se arma con un modelo para cada parte.
static func _fitted_copy(source: Mesh, fit: Transform3D, materials: Array, fused_sides: int, bottom_y: float, depths: Vector3, ice_sides := WHOLE_MODEL, unseen_sides := 0, the_part_in_ice := false) -> ArrayMesh:
	var seams := _seams(fused_sides, bottom_y)
	var every_side := _seams(EVERY_SIDE, bottom_y)
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
				corners.append(fit * vertices[indices[first + k]])
			if ice_sides != WHOLE_MODEL and _is_drawn_in_ice(corners, every_side, depths, ice_sides, unseen_sides) != the_part_in_ice:
				continue
			for k in 3:
				corners[k] = _flattened_onto_the_seams(corners[k], seams, depths)
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

## Un triángulo de una cara es de hielo si lo es esa cara. Uno de un bisel, si lo son todas las caras
## que el bisel une, sin contar las que no se ven.
static func _is_drawn_in_ice(corners: Array[Vector3], every_side: Array[Vector3], depths: Vector3, ice_sides: int, unseen_sides: int) -> bool:
	var sides := _sides_of_a_triangle(corners, every_side, depths) & ~unseen_sides
	return sides != 0 and sides & ~ice_sides == 0

## Una máscara de SIDES: la cara sobre la que está el triángulo o, si es de un bisel, las que une.
## `every_side` son los seis lados como planos, en el orden de SIDES.
static func _sides_of_a_triangle(corners: Array[Vector3], every_side: Array[Vector3], depths: Vector3) -> int:
	var centre := (corners[0] + corners[1] + corners[2]) / 3.0
	var near := 0
	for i in every_side.size():
		var axis := int(every_side[i].x)
		var sign := every_side[i].y
		var extent := every_side[i].z
		if is_equal_approx(corners[0][axis], extent) and is_equal_approx(corners[1][axis], extent) and is_equal_approx(corners[2][axis], extent):
			return 1 << i
		if centre[axis] * sign >= extent * sign - depths[axis]:
			near |= 1 << i
	return near

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
