@tool
class_name ButtonPowerable
extends Powerable

const TRANSMITS := true


const STAND_WIDTH := 0.45 # >(1-J)
const STAND_HEIGHT := 0.5
## En una pared no hay pedestal: una base corta, sin hitbox.
const WALL_STAND_HEIGHT := 0.08
const BUTTON_RADIUS := 0.1
const BUTTON_HEIGHT := 0.06
const BUTTON_MODEL_DIAMETER := 0.32
const BUTTON_MODEL_HEIGHT := 0.10
const BUTTON_MODEL: PackedScene = preload("res://art/powerables/Boton-Rojo.glb")
const PEDESTAL_MODEL: PackedScene = preload("res://art/powerables/Pedestal_boton_Hielo.glb")

static var _cached_button_mesh: ArrayMesh
static var _cached_stand_meshes: Dictionary[float, ArrayMesh] = {}

## Cómo empieza
@export var switched_on := false

var _light := StandardMaterial3D.new()


func activation_condition(_inputs: Inputs) -> bool:
	return switched_on


func turn_on() -> void:
	_paint(_light, LIT_RED, true)

func turn_off() -> void:
	_paint(_light, DIM_RED, false)


func _build_look() -> void:
	turn_off()
	var stand_height := STAND_HEIGHT if face == Face.TOP else WALL_STAND_HEIGHT
	_add_part(_stand_mesh(stand_height), null, stand_height / 2.0)
	var button := _add_part(_button_mesh(), null, stand_height)
	button.set_surface_override_material(1, _light)


static func _stand_mesh(stand_height: float) -> ArrayMesh:
	if _cached_stand_meshes.has(stand_height):
		return _cached_stand_meshes[stand_height]
	var root := PEDESTAL_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var target_size := Vector3(STAND_WIDTH, stand_height, STAND_WIDTH)
	var basis := Basis.from_scale(target_size / aabb.size)
	var fit := Transform3D(basis, -(basis * aabb.get_center()))
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.deindex()
		st.generate_normals()
		st.set_material(source.surface_get_material(surface))
		st.commit(assembled)
	root.free()
	_cached_stand_meshes[stand_height] = assembled
	return assembled


static func _button_mesh() -> ArrayMesh:
	if _cached_button_mesh != null:
		return _cached_button_mesh
	var root := BUTTON_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var target_size := Vector3(BUTTON_MODEL_DIAMETER, BUTTON_MODEL_HEIGHT, BUTTON_MODEL_DIAMETER)
	var basis := Basis.from_scale(target_size / aabb.size)
	var bottom_centre := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	var fit := Transform3D(basis, -(basis * bottom_centre))
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.set_material(source.surface_get_material(surface))
		st.commit(assembled)
	root.free()
	_cached_button_mesh = assembled
	return _cached_button_mesh


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.hint_string = _faces_hint([Face.TOP, Face.POS_X, Face.NEG_X, Face.POS_Y, Face.NEG_Y])
