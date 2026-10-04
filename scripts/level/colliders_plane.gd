class_name CollidersPlane
extends Node3D
## LevelIndex.colliders_plane hecho colliders de verdad. Una capa (un GridMap) por cada ColliderType.

const BOX_MESH := preload("res://scripts/objects/box_mesh.gd")
## Del mismo ancho que la raya visual
const EDGE_THICKNESS: float = BOX_MESH.MOVABLE_STRIPE_WIDTH
const ONLY_ITEM := 0

## Para depurar (F3): el plano en rosa, cada collider como el cuadrado que es en azul y el cuerpo
## del jugador en verde, leídos de los colliders mismos en cada frame. Se dibuja apenas encima de
## las celdas del plano, así desde arriba también tapa al modelo y se ve todo.
const DEBUG_HEIGHT := 1.0
## El rosa multiplica lo que tiene abajo en vez de mezclarse: el piso iluminado pasa de 1.0, y un
## rosa mezclado por encima seguía saliendo blanco.
const DEBUG_PLANE_COLOUR := Color(1.0, 0.6, 0.85)
const DEBUG_COLLIDER_COLOUR := Color(0.2, 0.45, 1.0, 0.6)
const DEBUG_BODY_COLOUR := Color(0.2, 1.0, 0.4, 0.7)

@onready var room: Room = get_parent()

var _layers: Dictionary[LevelIndex.ColliderType, GridMap] = {}
var _rebuild_pending := false

var _debug_mesh := ImmediateMesh.new()
var _debug_view := MeshInstance3D.new()
var _debug_plane_material := _debug_material(DEBUG_PLANE_COLOUR, BaseMaterial3D.BLEND_MODE_MUL)
var _debug_collider_material := _debug_material(DEBUG_COLLIDER_COLOUR)
var _debug_body_material := _debug_material(DEBUG_BODY_COLOUR)


func _ready() -> void:
	for type: LevelIndex.ColliderType in LevelIndex.ColliderType.values():
		_layers[type] = _create_layer(type)
	room.moved.connect(request_rebuild)
	room.perspective_manager.perspective_changed.connect(request_rebuild.unbind(1))
	request_rebuild()
	_debug_view.name = "DebugView"
	_debug_view.mesh = _debug_mesh
	_debug_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_view.visible = false
	add_child(_debug_view)


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed(&"toggle_collision_debug"):
		_debug_view.visible = not _debug_view.visible

func _process(_delta: float) -> void:
	if _debug_view.visible:
		_draw_debug_view()


func request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	rebuild.call_deferred()

func rebuild() -> void:
	_rebuild_pending = false
	position.y = room.maximum_reach().z + 1
	for layer: GridMap in _layers.values():
		layer.clear()
	var perspective_manager := room.perspective_manager
	var colliders := room.index.colliders_plane(perspective_manager.height, perspective_manager.current)
	for column: Vector2i in colliders:
		for type: LevelIndex.ColliderType in colliders[column]:
			_layers[type].set_cell_item(_cell_of(column), ONLY_ITEM)


func has_collider(column: Vector2i, type: LevelIndex.ColliderType) -> bool:
	return _layers[type].get_cell_item(_cell_of(column)) == ONLY_ITEM


func _cell_of(column: Vector2i) -> Vector3i:
	return GridCoordsProvider.grid_to_godot(Vector3i(column.x, column.y, 0))


func _create_layer(type: LevelIndex.ColliderType) -> GridMap:
	var layer := GridMap.new()
	layer.name = LevelIndex.ColliderType.keys()[type]
	layer.cell_size = Vector3.ONE
	layer.mesh_library = MeshLibrary.new()
	layer.mesh_library.create_item(ONLY_ITEM)
	layer.mesh_library.set_item_shapes(ONLY_ITEM, _shape_of(type))
	add_child(layer)
	return layer


func _shape_of(type: LevelIndex.ColliderType) -> Array:
	var wall_along_x := Vector3(EDGE_THICKNESS, 1, 1)
	var wall_along_y := Vector3(1, 1, EDGE_THICKNESS) # y de grilla = z de Godot
	var to_the_edge := 0.5 - EDGE_THICKNESS / 2.0
	match type:
		LevelIndex.ColliderType.POS_X: return _box(wall_along_x, Vector3(to_the_edge, 0, 0))
		LevelIndex.ColliderType.NEG_X: return _box(wall_along_x, Vector3(-to_the_edge, 0, 0))
		LevelIndex.ColliderType.POS_Y: return _box(wall_along_y, Vector3(0, 0, to_the_edge))
		LevelIndex.ColliderType.NEG_Y: return _box(wall_along_y, Vector3(0, 0, -to_the_edge))
		LevelIndex.ColliderType.SOLID: return _box(Vector3.ONE, Vector3.ZERO)
	assert(false, "Error CATASTRÓFICO: ColliderType sin forma")
	return []

func _box(size: Vector3, offset: Vector3) -> Array:
	var shape := BoxShape3D.new()
	shape.size = size
	return [shape, Transform3D(Basis(), offset)]


func _draw_debug_view() -> void:
	_debug_mesh.clear_surfaces()
	var walls: Array[Rect2] = []
	for layer: GridMap in _layers.values():
		var item_shapes := layer.mesh_library.get_item_shapes(ONLY_ITEM)
		var shape: BoxShape3D = item_shapes[0]
		var offset: Vector3 = (item_shapes[1] as Transform3D).origin
		for cell in layer.get_used_cells():
			walls.append(_seen_from_above(layer.map_to_local(cell) + offset, shape.size))
	if walls.is_empty():
		return
	var whole_plane := walls[0]
	for wall in walls:
		whole_plane = whole_plane.merge(wall)
	_draw_rects([whole_plane], DEBUG_HEIGHT + 0.01, _debug_plane_material)
	_draw_rects(walls, DEBUG_HEIGHT + 0.02, _debug_collider_material)
	_draw_rects(_bodies_seen_from_above(), DEBUG_HEIGHT + 0.03, _debug_body_material)

## Los cuerpos que se mueven en el plano (el del jugador), con sus formas de caja.
func _bodies_seen_from_above() -> Array[Rect2]:
	var footprints: Array[Rect2] = []
	for body in get_children():
		if body is CollisionObject3D:
			for part in body.get_children():
				if part is CollisionShape3D and part.shape is BoxShape3D:
					footprints.append(_seen_from_above(body.position + part.position, part.shape.size))
	return footprints

## Una caja vista desde arriba: su rectángulo en x y z de Godot.
func _seen_from_above(centre: Vector3, size: Vector3) -> Rect2:
	return Rect2(centre.x - size.x / 2.0, centre.z - size.z / 2.0, size.x, size.z)

func _draw_rects(rects: Array[Rect2], height: float, material: Material) -> void:
	if rects.is_empty():
		return
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for rect in rects:
		var near_left := Vector3(rect.position.x, height, rect.position.y)
		var near_right := Vector3(rect.end.x, height, rect.position.y)
		var far_right := Vector3(rect.end.x, height, rect.end.y)
		var far_left := Vector3(rect.position.x, height, rect.end.y)
		for corner in [near_left, near_right, far_right, near_left, far_right, far_left]:
			_debug_mesh.surface_add_vertex(corner)
	_debug_mesh.surface_end()

static func _debug_material(colour: Color, blend := BaseMaterial3D.BLEND_MODE_MIX) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = blend
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = colour
	return material
