@tool
class_name Door
extends Powerable


const TRANSMITS := false

const BOX_MESH := preload("res://scripts/objects/box_mesh.gd")

const THICKNESS: float = BOX_MESH.MOVABLE_STRIPE_WIDTH
const HEIGHT := 1.0
const COLOUR := Color(0.2, 0.2, 0.22)
const EXIT_GREEN := Color(0.15, 0.68, 0.3)

const DOOR_MODEL: PackedScene = preload("res://art/powerables/Puerta_madera.glb")

static var _cached_door_mesh: ArrayMesh
static var _cached_exit_door_mesh: ArrayMesh

@export var edge := Box.Facing.POS_X:
	set(value):
		edge = value
		_request_redraw()

@export var always_open := false

var _slab: MeshInstance3D
var _door_leaf: MeshInstance3D
var _tween: Tween
var _is_open := false
var _ready_for_audio := false


func _ready() -> void:
	super()
	_ready_for_audio = true


func activation_condition(inputs: Inputs) -> bool:
	return Powerable.powered(inputs.active_neighbours)


func turn_on() -> void:
	var was_open := _is_open
	_is_open = true
	if _slab != null:
		_slab.visible = false
	if _door_leaf != null:
		_rotate_to(_closed_angle() + PI / 2.0)
	if not Engine.is_editor_hint() and is_inside_tree() and not was_open and _ready_for_audio:
		AudioManager.play_door_open()

func turn_off() -> void:
	_is_open = false
	if _slab != null:
		_slab.visible = true
	if _door_leaf != null:
		_rotate_to(_closed_angle())


func _rotate_to(target_angle: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if is_inside_tree() and not Engine.is_editor_hint():
		_tween = create_tween()
		_tween.tween_property(_door_leaf, "rotation:y", target_angle, 0.15)
	else:
		_door_leaf.rotation.y = target_angle


func _colour() -> Color:
	return COLOUR

func _is_exit() -> bool:
	return false


func _closed_angle() -> float:
	var dir := Vector3(Box.FACING_DIRECTION[edge].x, 0.0, Box.FACING_DIRECTION[edge].y)
	var along_edge := Vector3(-dir.z, 0.0, dir.x)
	return atan2(-along_edge.z, along_edge.x)


func _build_look() -> void:
	_slab = MeshInstance3D.new()
	add_child(_slab)

	var strip := Box.strip_along(edge, THICKNESS)
	var dir := Vector3(Box.FACING_DIRECTION[edge].x, 0.0, Box.FACING_DIRECTION[edge].y)
	var along_edge := Vector3(-dir.z, 0.0, dir.x)
	var hinge_pos := Vector3(strip.get_center().x, 0.0, strip.get_center().y) - along_edge * 0.5

	_door_leaf = MeshInstance3D.new()
	_door_leaf.mesh = _door_mesh(_is_exit())
	_door_leaf.position = hinge_pos
	_door_leaf.rotation.y = _closed_angle()
	add_child(_door_leaf)

	if always_open:
		turn_on()
	else:
		turn_off()


static func _door_mesh(is_exit: bool) -> ArrayMesh:
	if is_exit and _cached_exit_door_mesh != null:
		return _cached_exit_door_mesh
	if not is_exit and _cached_door_mesh != null:
		return _cached_door_mesh
	var root := DOOR_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var scale_vec := Vector3(0.5, HEIGHT / 2.806839, THICKNESS / 2.536)
	var offset := Vector3(0.5, -scale_vec.y * (-1.00519), 0.0)
	var fit := Transform3D(Basis.from_scale(scale_vec), offset)
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		var mat := source.surface_get_material(surface).duplicate() as StandardMaterial3D
		if surface == 1 and is_exit:
			mat.albedo_color = EXIT_GREEN
		st.set_material(mat)
		st.commit(assembled)
	root.free()
	if is_exit:
		_cached_exit_door_mesh = assembled
	else:
		_cached_door_mesh = assembled
	return assembled


func _exit_tree() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.usage = PROPERTY_USAGE_NO_EDITOR
