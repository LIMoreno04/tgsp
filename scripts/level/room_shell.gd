@tool
class_name RoomShell
extends Node3D


const STRUCTURE_SCENE: PackedScene = preload("res://scenes/prefabs/structure.tscn")
const WATER_MODEL: PackedScene = preload("res://art/boxes/Cubo_Agua.glb")

const FLOOR := "Floor"
const WALL_X := "WallX" # la pared en x = -1; se queda con la columna de la esquina (-1, -1)
const WALL_Y := "WallY" # la pared en y = -1
const WATER_Z := -2

static var _water_unit_mesh: ArrayMesh
static var _water_shader_material: ShaderMaterial

## Lo que un achique le sacó al marco en una celda: la caja, con sus ediciones y sus powerables, o
## null si la celda era un agujero.
class Trimmed:
	var box: Box
	## La cáscara no ve la historia de deshacer del editor: si el cuarto vuelve justo al tamaño que
	## tenía antes del achique, lo toma por deshacerlo y devuelve lo recortado tal cual.
	var room_size_before: Vector3i
	## Fuera del árbol pierden el owner, y sin owner no se guardan.
	var saved_nodes: Array[Node] = []
	## Su lugar entre las cajas de su parte, para que deshacer deje el archivo igual que antes.
	var index_in_part := 0

@onready var room: Room = get_parent()

## Por celda del mundo, el recorte más reciente al final. Sólo en memoria, como la historia de
## deshacer, y se libera con la cáscara.
var _trimmed: Dictionary[Vector3i, Array] = {}
var _room_size_laid_out: Vector3i
var _water_instances: MultiMeshInstance3D

func on_dimensions_change():
	var frame_before := _frame_laid_out_last_time()
	for part_name in [FLOOR, WALL_X, WALL_Y]:
		if _part(part_name) == null:
			_create_part(part_name)
	_lay_out()
	_fill_part(_part(FLOOR), &"is_floor", frame_before)
	_fill_part(_part(WALL_X), &"is_wall", frame_before)
	_fill_part(_part(WALL_Y), &"is_wall", frame_before)
	_trim_what_fell_outside(frame_before)
	_room_size_laid_out = room.dimensions
	_rebuild_water()
	update_configuration_warnings()

func _init() -> void:
	set_notify_local_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		update_configuration_warnings()
	elif what == NOTIFICATION_PREDELETE:
		for trimmed_here: Array in _trimmed.values():
			for trimmed: Trimmed in trimmed_here:
				if is_instance_valid(trimmed.box):
					trimmed.box.free()

func _ready() -> void:
	_room_size_laid_out = room.dimensions
	room.dimensions_changed.connect(on_dimensions_change)
	_rebuild_water()
	_rebuild_water.call_deferred()


func _lay_out() -> void:
	_place(FLOOR, Vector3i(0, 0, -1), Vector3i(room.dimensions.x, room.dimensions.y, 1))
	_place(WALL_X, Vector3i(-1, -1, -1), Vector3i(1, room.dimensions.y + 1, room.dimensions.z + 1))
	_place(WALL_Y, Vector3i(0, -1, -1), Vector3i(room.dimensions.x, 1, room.dimensions.z + 1))


func _place(part_name: String, first_cell: Vector3i, size: Vector3i) -> void:
	var part := _part(part_name)
	if part == null:
		return
	part.cell = first_cell
	part.dimensions = size


## El único registro del marco anterior es el `cell` y las `dimensions` que _lay_out le dejó a cada
## parte, que se guardan con la escena. Una parte que todavía no existe no tenía marco, así que una
## cáscara nueva se llena entera.
func _frame_laid_out_last_time() -> Dictionary[Vector3i, bool]:
	var frame: Dictionary[Vector3i, bool] = {}
	for part_name in [FLOOR, WALL_X, WALL_Y]:
		var part := _part(part_name)
		if part == null:
			continue
		for cell_in_part in part.prism_cells():
			frame[part.cell + cell_in_part] = true
	return frame


## Sólo las celdas nuevas del marco: una celda que ya estaba en él y no tiene caja es un agujero
## hecho a propósito. Una celda nueva recibe lo que un achique le recortó si el cuarto volvió al
## tamaño de antes de ese achique, y si no una caja nueva, marcada como piso o pared.
func _fill_part(part: Structure, flag: StringName, frame_before: Dictionary[Vector3i, bool]) -> void:
	var occupied: Dictionary[Vector3i, bool] = {}
	for box in part.boxes():
		occupied[box.cell] = true
	var coming_back: Array[Trimmed] = []
	var new_cells: Array[Vector3i] = []
	for cell_in_part in part.prism_cells():
		var world_cell := part.cell + cell_in_part
		if occupied.has(cell_in_part) or frame_before.has(world_cell):
			continue
		var trimmed := _take_trimmed_for_this_size(world_cell)
		if trimmed != null:
			coming_back.append(trimmed)
		else:
			new_cells.append(cell_in_part)
	# Cada una vuelve a su lugar de antes; de la primera a la última, así ninguna corre a otra.
	coming_back.sort_custom(func(a: Trimmed, b: Trimmed) -> bool: return a.index_in_part < b.index_in_part)
	for trimmed in coming_back:
		_put_back(trimmed, part)
	for cell_in_part in new_cells:
		var box := Structure.BOX_SCENE.instantiate() as Box
		box.cell = cell_in_part
		part.add_child(box, true)
		box.owner = get_tree().edited_scene_root
		box.set(flag, true)


func _take_trimmed_for_this_size(world_cell: Vector3i) -> Trimmed:
	var trimmed_here: Array = _trimmed.get(world_cell, [])
	for i in range(trimmed_here.size() - 1, -1, -1):
		var trimmed: Trimmed = trimmed_here[i]
		if trimmed.room_size_before == room.dimensions:
			trimmed_here.remove_at(i)
			return trimmed
	return null


func _put_back(trimmed: Trimmed, part: Structure) -> void:
	if trimmed.box == null:
		return
	part.add_child(trimmed.box, true)
	part.move_child(trimmed.box, mini(trimmed.index_in_part, part.get_child_count() - 1))
	for node in trimmed.saved_nodes:
		node.owner = get_tree().edited_scene_root


## No se borra: se guarda, agujeros incluidos, por si se deshace el achique.
func _trim_what_fell_outside(frame_before: Dictionary[Vector3i, bool]) -> void:
	var trimmed_boxes_at: Dictionary[Vector3i, bool] = {}
	for part_name in [FLOOR, WALL_X, WALL_Y]:
		var part := _part(part_name)
		var prism := part.prism_cells()
		# Los lugares se miran antes de sacar ninguna: sacar una corre a las de después.
		var falling: Dictionary[Box, int] = {}
		for box in part.boxes():
			if not prism.has(box.cell):
				falling[box] = box.get_index()
		for box: Box in falling:
			trimmed_boxes_at[part.cell + box.cell] = true
			_keep_trimmed(part.cell + box.cell, box, falling[box])
	var frame_now := _frame_laid_out_last_time()
	for world_cell in frame_before:
		if not frame_now.has(world_cell) and not trimmed_boxes_at.has(world_cell):
			_keep_trimmed(world_cell, null)


func _keep_trimmed(world_cell: Vector3i, box: Box, index_in_part := 0) -> void:
	var trimmed := Trimmed.new()
	trimmed.box = box
	trimmed.room_size_before = _room_size_laid_out
	trimmed.index_in_part = index_in_part
	if box != null:
		trimmed.saved_nodes = _nodes_saved_with(box)
		box.get_parent().remove_child(box)
	if not _trimmed.has(world_cell):
		_trimmed[world_cell] = []
	_trimmed[world_cell].append(trimmed)


func _nodes_saved_with(box: Box) -> Array[Node]:
	var saved: Array[Node] = []
	if box.owner == null:
		return saved
	saved.append(box)
	for node in box.find_children("*", "", true, false):
		if node.owner == box.owner:
			saved.append(node)
	return saved


func _part(part_name: String) -> Structure:
	return get_node_or_null(part_name) as Structure


func _create_part(part_name: String) -> void:
	var part := STRUCTURE_SCENE.instantiate() as Structure
	part.name = part_name
	add_child(part)
	part.owner = get_tree().edited_scene_root


func _rebuild_water() -> void:
	if room == null or room.dimensions.x <= 0 or room.dimensions.y <= 0:
		return
	if _water_instances == null:
		_water_instances = MultiMeshInstance3D.new()
		_water_instances.name = "WaterBase"
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _get_water_unit_mesh()
		_water_instances.multimesh = multimesh
		_water_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Nodo interno para no aparecer en get_children() ni guardarse en el .tscn.
		add_child(_water_instances, false, Node.INTERNAL_MODE_BACK)

	var bounds := _calculate_water_bounds()
	var x_start := bounds.position.x
	var x_end := bounds.position.x + bounds.size.x
	var y_start := bounds.position.y
	var y_end := bounds.position.y + bounds.size.y
	var width := bounds.size.x
	var length := bounds.size.y
	var multimesh := _water_instances.multimesh
	multimesh.instance_count = width * length
	var idx := 0
	for x in range(x_start, x_end):
		for y in range(y_start, y_end):
			var pos := GridCoordsProvider.grid_to_godot(Vector3i(x, y, WATER_Z)) + Vector3(0.5, 0.5, 0.5)
			multimesh.set_instance_transform(idx, Transform3D(Basis.IDENTITY, pos))
			idx += 1


func _calculate_water_bounds() -> Rect2i:
	var x_min := -2
	var x_max := room.dimensions.x + 1
	var y_min := -2
	var y_max := room.dimensions.y + 1

	if room != null:
		if room.index != null and not room.index.cells_3D.is_empty():
			for cell: Vector3i in room.index.cells_3D:
				x_min = mini(x_min, cell.x - 2)
				y_min = mini(y_min, cell.y - 2)
				x_max = maxi(x_max, cell.x + 2)
				y_max = maxi(y_max, cell.y + 2)
		for child in room.get_children():
			if child is Structure:
				x_min = mini(x_min, child.cell.x - 2)
				y_min = mini(y_min, child.cell.y - 2)
				x_max = maxi(x_max, child.cell.x + child.dimensions.x + 1)
				y_max = maxi(y_max, child.cell.y + child.dimensions.y + 1)
				for box in child.boxes():
					var wc: Vector3i = child.cell + box.cell
					x_min = mini(x_min, wc.x - 2)
					y_min = mini(y_min, wc.y - 2)
					x_max = maxi(x_max, wc.x + 2)
					y_max = maxi(y_max, wc.y + 2)
			elif child is Box:
				x_min = mini(x_min, child.world_cell.x - 2)
				y_min = mini(y_min, child.world_cell.y - 2)
				x_max = maxi(x_max, child.world_cell.x + 2)
				y_max = maxi(y_max, child.world_cell.y + 2)

	return Rect2i(x_min, y_min, x_max - x_min + 1, y_max - y_min + 1)


static func _get_water_unit_mesh() -> ArrayMesh:
	if _water_unit_mesh != null:
		return _water_unit_mesh
	var root := WATER_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var unit_scale := Basis.from_scale(Vector3.ONE / aabb.size)
	var fit := Transform3D(unit_scale, -(unit_scale * aabb.get_center()))
	var assembled := ArrayMesh.new()
	var base_mat := source.surface_get_material(0) as StandardMaterial3D
	var water_mat := _get_water_shader_material(base_mat)
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.set_material(water_mat)
		st.commit(assembled)
	root.free()
	_water_unit_mesh = assembled
	return _water_unit_mesh


static func _get_water_shader_material(base_mat: StandardMaterial3D) -> ShaderMaterial:
	if _water_shader_material != null:
		return _water_shader_material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.0, 0.6057, 0.9063, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.25;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float wave_height = 0.22;
uniform float wave_half_width = 0.75;
uniform float wave_narrowness = 2.6;
uniform float wave_speed = 0.9;
uniform vec2 wave_origin = vec2(-5.0, -4.0);

varying float v_wave_ratio;

float wave_at(vec2 p, float t) {
	float period = wave_half_width * 2.0;
	float dist = length(p - wave_origin);
	float u = mod(dist - t * wave_speed, period) - wave_half_width;
	float x = u * wave_narrowness;
	float edge = wave_half_width * wave_narrowness;
	float bell = exp(-x * x) - exp(-edge * edge);
	float norm = 1.0 - exp(-edge * edge);
	return wave_height * (bell / norm);
}

void vertex() {
	v_wave_ratio = 0.0;
	if (VERTEX.y > 0.0) {
		vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
		float h = wave_at(world_xz, TIME);
		VERTEX.y += h - wave_height;
		if (NORMAL.y > 0.5) {
			v_wave_ratio = h / max(wave_height, 0.001);
			float eps = 0.02;
			float hx = wave_at(world_xz + vec2(eps, 0.0), TIME) - h;
			float hz = wave_at(world_xz + vec2(0.0, eps), TIME) - h;
			NORMAL = normalize(vec3(-hx / eps, 1.0, -hz / eps));
		}
	}
}

void fragment() {
	ALBEDO = mix(albedo.rgb, min(albedo.rgb * 1.28 + vec3(0.06, 0.10, 0.12), vec3(1.0)), v_wave_ratio * 0.55);
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if base_mat != null:
		mat.set_shader_parameter("albedo", base_mat.albedo_color)
		mat.set_shader_parameter("roughness", base_mat.roughness)
		mat.set_shader_parameter("metallic", base_mat.metallic)
	_water_shader_material = mat
	return _water_shader_material


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if room.dimensions.x <= 0 or room.dimensions.y <= 0 or room.dimensions.z <= 0:
		warnings.append("Dimensions must be greater than zero.")
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		warnings.append("The shell must sit at the origin: world_cell does not see this node's transform.")
	return warnings
