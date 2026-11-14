@tool
class_name LaserEmitter
extends Powerable


const TRANSMITS := false

const HOUSING_WIDTH := 0.3
const HOUSING_DEPTH := 0.12
const LENS_RADIUS := 0.08
const LENS_DEPTH := 0.03
const BEAM_RADIUS := 0.035
const BEAM_RED := Color(1.0, 0.04, 0.04)
const BEAM_MODEL: PackedScene = preload("res://art/powerables/Laser-Rojo.glb")

static var _cached_beam_mesh: ArrayMesh

@export var always_on := false

var _lens := StandardMaterial3D.new()
var _beam: MeshInstance3D
var _sparks: GPUParticles3D


func _init() -> void:
	face = Face.POS_X


func activation_condition(inputs: Inputs) -> bool:
	return always_on or Powerable.powered(inputs.active_neighbours)


func turn_on() -> void:
	_paint(_lens, LIT_RED, true)
	_beam.visible = true
	if is_instance_valid(_sparks):
		_sparks.emitting = true

func turn_off() -> void:
	_paint(_lens, DIM_RED, false)
	_beam.visible = false
	if is_instance_valid(_sparks):
		_sparks.emitting = false

## El largo se calcula en levelindex
func show_beam(length: float) -> void:
	_beam.scale.y = maxf(length, 0.001)
	_beam.position = Vector3(GridCoordsProvider.grid_to_godot(normal())) * length / 2.0
	if is_instance_valid(_sparks):
		_sparks.position = Vector3(GridCoordsProvider.grid_to_godot(normal())) * length


func _build_look() -> void:
	var housing := BoxMesh.new()
	housing.size = Vector3(HOUSING_WIDTH, HOUSING_DEPTH, HOUSING_WIDTH)
	_add_part(housing, _material(STAND_GREY), HOUSING_DEPTH / 2.0)
	var lens := CylinderMesh.new()
	lens.top_radius = LENS_RADIUS
	lens.bottom_radius = LENS_RADIUS
	lens.height = LENS_DEPTH
	_add_part(lens, _lens, HOUSING_DEPTH + LENS_DEPTH / 2.0)
	_beam = _add_part(_unit_beam_mesh(), null, 0.0)
	_build_sparks()
	turn_off()


func _build_sparks() -> void:
	if Engine.is_editor_hint():
		return
	_sparks = GPUParticles3D.new()
	_sparks.amount = 8
	_sparks.lifetime = 0.25
	_sparks.explosiveness = 0.5

	var mat := ParticleProcessMaterial.new()
	var normal_dir := Vector3(GridCoordsProvider.grid_to_godot(normal()))
	mat.direction = -normal_dir + Vector3(0, 0.6, 0)
	mat.spread = 50.0
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 2.4
	mat.gravity = Vector3(0, -3.5, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.04
	mat.color = Color(1.0, 0.3, 0.1, 1.0)
	_sparks.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.albedo_color = Color(1.0, 0.4, 0.15, 1.0)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.3, 0.1, 1.0)
	smat.emission_energy_multiplier = 3.0
	quad.material = smat
	_sparks.draw_pass_1 = quad

	_sparks.emitting = false
	add_child(_sparks)


static func _unit_beam_mesh() -> ArrayMesh:
	if _cached_beam_mesh != null:
		return _cached_beam_mesh
	var root := BEAM_MODEL.instantiate()
	var source := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var aabb := source.get_aabb()
	var diameter := BEAM_RADIUS * 2.0
	var target_size := Vector3(diameter, 1.0, diameter)
	var basis := Basis.from_scale(target_size / aabb.size)
	var fit := Transform3D(basis, -(basis * aabb.get_center()))
	var assembled := ArrayMesh.new()
	for surface in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, surface, fit)
		st.set_material(source.surface_get_material(surface))
		st.commit(assembled)
	root.free()
	_cached_beam_mesh = assembled
	return _cached_beam_mesh


func _validate_property(property: Dictionary) -> void:
	super(property)
	if property.name == "face":
		property.hint_string = _faces_hint(SIDE_FACES)
