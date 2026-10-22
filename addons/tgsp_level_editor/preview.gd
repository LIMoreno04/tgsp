@tool
class_name LevelEditorPreview
extends Node3D
## Lo que se dibuja para ver qué va a pasar: fantasmas (los prefabs de verdad, translúcidos),
## celdas teñidas, caras y franjas resaltadas, contornos, líneas y textos. Vive bajo el SubViewport de
## la vista, nunca en el nivel, así que nunca se guarda. Todo en coordenadas de la grilla.
##
## Se usa así: begin(), lo que haga falta, finish(). Lo que no se pidió entre los dos se esconde.

const GHOST_TRANSPARENCY := 0.45
const BOX_SCENE: PackedScene = preload("res://scenes/prefabs/box.tscn")

const BLUE := Color(0.25, 0.6, 1.0, 0.35)
const RED := Color(1.0, 0.2, 0.15, 0.55)
const GREEN := Color(0.3, 0.9, 0.4, 0.4)
const ORANGE := Color(0.95, 0.5, 0.1, 0.6)
const WHITE := Color(1, 1, 1, 0.9)

var _cubes := MultiMeshInstance3D.new()
var _faces := MultiMeshInstance3D.new()
var _lines := MeshInstance3D.new()
var _line_mesh := ImmediateMesh.new()

var _cube_transforms: Array[Transform3D] = []
var _cube_colors: Array[Color] = []
var _face_transforms: Array[Transform3D] = []
var _face_colors: Array[Color] = []
var _line_points: PackedVector3Array = []
var _line_colors: PackedColorArray = []

## Fantasmas de cajas por banderas, y de powerables por cómo son; se reusan entre cuadros.
var _ghost_boxes: Dictionary[String, Array] = {}
var _ghost_boxes_used: Dictionary[String, int] = {}
var _ghost_pieces: Dictionary[String, Node3D] = {}
var _ghost_pieces_used: Dictionary[String, bool] = {}
var _labels: Array[Label3D] = []
var _labels_used := 0


func _init() -> void:
	_cubes.multimesh = _new_multimesh(_unit_cube())
	_cubes.material_override = _flat_material(false)
	_cubes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cubes)
	_faces.multimesh = _new_multimesh(_unit_square())
	_faces.material_override = _flat_material(false)
	_faces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_faces)
	_lines.mesh = _line_mesh
	_lines.material_override = _flat_material(true)
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)


func begin() -> void:
	_cube_transforms.clear()
	_cube_colors.clear()
	_face_transforms.clear()
	_face_colors.clear()
	_line_points.clear()
	_line_colors.clear()
	_ghost_boxes_used.clear()
	_ghost_pieces_used.clear()
	_labels_used = 0


func finish() -> void:
	_fill_multimesh(_cubes.multimesh, _cube_transforms, _cube_colors)
	_fill_multimesh(_faces.multimesh, _face_transforms, _face_colors)
	_line_mesh.clear_surfaces()
	if not _line_points.is_empty():
		_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in _line_points.size():
			_line_mesh.surface_set_color(_line_colors[i])
			_line_mesh.surface_add_vertex(_line_points[i])
		_line_mesh.surface_end()
	for key in _ghost_boxes:
		var pool: Array = _ghost_boxes[key]
		for i in pool.size():
			(pool[i] as Node3D).visible = i < _ghost_boxes_used.get(key, 0)
	for key in _ghost_pieces.keys():
		var holder: Node3D = _ghost_pieces[key]
		holder.visible = _ghost_pieces_used.has(key)
		if not holder.visible and _ghost_pieces.size() > 48:
			_ghost_pieces.erase(key)
			holder.queue_free()
	for i in _labels.size():
		_labels[i].visible = i < _labels_used


func clear() -> void:
	begin()
	finish()


#==================Lo que se puede dibujar==================

## Una celda teñida: un cubo apenas más grande que la caja.
func tint_cell(cell: Vector3i, color: Color, grow := 0.03) -> void:
	var basis := Basis.from_scale(Vector3.ONE * (1.0 + grow * 2.0))
	_cube_transforms.append(Transform3D(basis, _centre_of(cell)))
	_cube_colors.append(color)


## Un volumen cualquiera, desde su esquina baja, en celdas: el fantasma del jugador.
func tint_volume(low: Vector3, volume_size: Vector3, color: Color) -> void:
	var centre := _to_godot(low + volume_size * 0.5)
	_cube_transforms.append(Transform3D(Basis.from_scale(Vector3(volume_size.x, volume_size.z, volume_size.y)), centre))
	_cube_colors.append(color)


## Un prisma teñido de una esquina a la otra, para trazos grandes.
func tint_prism(low: Vector3i, high: Vector3i, color: Color) -> void:
	var size := Vector3(high - low + Vector3i.ONE)
	var godot_size := Vector3(size.x, size.z, size.y)
	var centre := _to_godot(Vector3(low) + size * 0.5)
	_cube_transforms.append(Transform3D(Basis.from_scale(godot_size * 1.01), centre))
	_cube_colors.append(color)


## Una cara entera de la caja de esa celda, apenas despegada.
func highlight_face(cell: Vector3i, face: Powerable.Face, color: Color) -> void:
	_face_rect(cell, face, Rect2(Vector2(-0.5, -0.5), Vector2.ONE), color)


## Una franja a lo largo de un borde de la tapa: las rayas 2D y las puertas.
func highlight_top_strip(cell: Vector3i, facing: Box.Facing, width: float, color: Color) -> void:
	_face_rect(cell, Powerable.Face.TOP, Box.strip_along(facing, width), color)


## La parte del medio de la tapa, sin los bordes.
func highlight_top_middle(cell: Vector3i, color: Color) -> void:
	var margin := GridPicker.EDGE_ZONE
	_face_rect(cell, Powerable.Face.TOP, Rect2(Vector2(-0.5 + margin, -0.5 + margin), Vector2.ONE * (1.0 - 2.0 * margin)), color)


## El borde de una cara, por encima de todo: se ve aunque algo la tape.
func outline_face(cell: Vector3i, face: Powerable.Face, color: Color) -> void:
	var normal := Vector3(Powerable.FACE_NORMAL[face])
	var centre := Vector3(cell) + Vector3.ONE * 0.5 + normal * 0.51
	var across: Array[Vector3] = []
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.UP]:
		if absf(axis.dot(normal)) < 0.5:
			across.append(axis * 0.5)
	var corners: Array[Vector3] = [centre - across[0] - across[1], centre + across[0] - across[1], centre + across[0] + across[1], centre - across[0] + across[1]]
	for i in 4:
		line(corners[i], corners[(i + 1) % 4], color)


## Las doce aristas de la celda.
func outline_cell(cell: Vector3i, color: Color, grow := 0.02) -> void:
	var low := Vector3(cell) - Vector3.ONE * grow
	var high := Vector3(cell) + Vector3.ONE * (1.0 + grow)
	outline_box(low, high, color)


func outline_box(low: Vector3, high: Vector3, color: Color) -> void:
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(Vector3(high.x if i & 1 else low.x, high.y if i & 2 else low.y, high.z if i & 4 else low.z))
	for pair in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		line(corners[pair[0]], corners[pair[1]], color)


## Una línea entre dos puntos de la grilla.
func line(from: Vector3, to: Vector3, color: Color) -> void:
	_line_points.append(_to_godot(from))
	_line_points.append(_to_godot(to))
	_line_colors.append(color)
	_line_colors.append(color)


## Una línea cortada, como la de un rayo láser.
func dashed_line(from: Vector3, to: Vector3, color: Color, dash := 0.25) -> void:
	var length := from.distance_to(to)
	var steps := maxi(1, int(length / dash))
	for i in range(0, steps, 2):
		line(from.lerp(to, float(i) / steps), from.lerp(to, minf(1.0, float(i + 1) / steps)), color)


func label(at: Vector3, text: String, color := WHITE, size := 48) -> void:
	if _labels_used >= _labels.size():
		var new_label := Label3D.new()
		new_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		new_label.no_depth_test = true
		new_label.pixel_size = 0.004
		new_label.outline_size = 12
		new_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(new_label)
		_labels.append(new_label)
	var each_label := _labels[_labels_used]
	_labels_used += 1
	each_label.text = text
	each_label.modulate = color
	each_label.font_size = size
	each_label.outline_size = maxi(8, size / 6)
	each_label.position = _to_godot(at)


## Un fantasma de la caja que se va a poner: el prefab de verdad, con esas banderas, translúcido.
func ghost_box(cell: Vector3i, flags: Dictionary[StringName, bool]) -> void:
	var key := str(flags)
	if not _ghost_boxes.has(key):
		_ghost_boxes[key] = []
	var pool: Array = _ghost_boxes[key]
	var used: int = _ghost_boxes_used.get(key, 0)
	if used >= pool.size():
		var box := BOX_SCENE.instantiate() as Box
		for flag in BoxBrush.BOX_FLAGS:
			box.set(flag, flags[flag])
		add_child(box)
		var mesh := box.get_node("Mesh") as GeometryInstance3D
		mesh.transparency = GHOST_TRANSPARENCY
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pool.append(box)
	var ghost := pool[used] as Box
	ghost.cell = cell
	_ghost_boxes_used[key] = used + 1


## Un fantasma del powerable que se va a poner, con su dibujo de verdad, en la cara de esa celda.
func ghost_piece(scene: PackedScene, cell: Vector3i, face: Powerable.Face, options: Dictionary) -> void:
	var key := "%s|%s|%d|%s" % [scene.resource_path, cell, face, str(options)]
	_ghost_pieces_used[key] = true
	if _ghost_pieces.has(key):
		return
	var holder := Node3D.new()
	holder.position = GridCoordsProvider.grid_to_godot(cell)
	add_child(holder)
	var piece := scene.instantiate() as Powerable
	piece.face = face
	for option in options:
		piece.set(option, options[option])
	holder.add_child(piece)
	_ghost_pieces[key] = holder
	_make_ghostly.call_deferred(holder)


func _make_ghostly(holder: Node3D) -> void:
	if not is_instance_valid(holder):
		return
	for part in holder.find_children("*", "GeometryInstance3D", true, false):
		(part as GeometryInstance3D).transparency = GHOST_TRANSPARENCY
		(part as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


#==================Por dentro==================

func _face_rect(cell: Vector3i, face: Powerable.Face, on_face: Rect2, color: Color) -> void:
	var normal := Vector3(GridCoordsProvider.grid_to_godot(Powerable.FACE_NORMAL[face]))
	var rotation_degrees: Vector3 = Powerable.FACE_ROTATIONS[face]
	var basis := Basis.from_euler(rotation_degrees * PI / 180.0, EULER_ORDER_YXZ)
	var centre := _centre_of(cell) + normal * 0.505
	var along := basis * Vector3(on_face.get_center().x, 0, on_face.get_center().y)
	var scaled := basis * Basis.from_scale(Vector3(on_face.size.x, 1, on_face.size.y))
	_face_transforms.append(Transform3D(scaled, centre + along))
	_face_colors.append(color)


static func _centre_of(cell: Vector3i) -> Vector3:
	return GridCoordsProvider.grid_to_godot(cell) + Vector3(0.5, 0.5, 0.5)


static func _to_godot(grid_point: Vector3) -> Vector3:
	return Vector3(grid_point.x, grid_point.z, grid_point.y)


static func _new_multimesh(mesh: Mesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	return multimesh


static func _fill_multimesh(multimesh: MultiMesh, transforms: Array[Transform3D], colors: Array[Color]) -> void:
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colors[i])


static func _unit_cube() -> Mesh:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	return cube


## Un cuadrado acostado, de lado 1, mirando hacia arriba: como una tapa, que FACE_ROTATIONS lleva a
## cualquier cara.
static func _unit_square() -> Mesh:
	var square := PlaneMesh.new()
	square.size = Vector2.ONE
	return square


static func _flat_material(on_top: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = on_top
	material.render_priority = 2 if on_top else 1
	return material
