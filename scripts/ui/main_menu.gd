class_name MainMenu
extends Node3D

const BOX_MESH := preload("res://scripts/objects/box_mesh.gd")
const WINTER_ENV: Environment = preload("res://scenes/prefabs/winter_environment.tres")
const SNOW_SCENE: PackedScene = preload("res://scenes/prefabs/snow_particles.tscn")
const WALKABLE_NIEVE: PackedScene = preload("res://art/boxes/Walkable_Nieve.glb")
const SUELO_NIEVE: PackedScene = preload("res://art/boxes/Suelo_nieve_hielo.glb")
const CAJA_HIELO: PackedScene = preload("res://art/boxes/Caja_interactuable_Hielo.glb")
const PARED_NIEVE: PackedScene = preload("res://art/boxes/Pared_Nieve.glb")
const CUBO_AGUA: PackedScene = preload("res://art/boxes/Cubo_Agua.glb")
const GRAMM_MODEL: PackedScene = preload("res://art/player/Personaje_gramm.glb")
const DOOR_MODEL: PackedScene = preload("res://art/powerables/Puerta_madera.glb")
const BUTTON_MODEL: PackedScene = preload("res://art/powerables/Pedestal_boton_Hielo.glb")
const BUTTON_TOP_MODEL: PackedScene = preload("res://art/powerables/Boton-Rojo.glb")

const WATER_WAVE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.18, 0.56, 0.78, 0.88);
uniform float roughness : hint_range(0.0, 1.0) = 0.15;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float wave_speed = 2.2;
uniform float wave_freq_x = 1.5707963;
uniform float wave_freq_z = 1.5707963;
uniform float wave_height = 0.045;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (VERTEX.y > 0.1) {
		float w1 = sin(world_pos.x * wave_freq_x + TIME * wave_speed);
		float w2 = cos(world_pos.z * wave_freq_z + TIME * (wave_speed * 0.85));
		float w3 = sin((world_pos.x + world_pos.z) * 1.1 + TIME * (wave_speed * 1.15)) * 0.5;
		VERTEX.y += (w1 + w2 + w3) * (wave_height * 0.45);
	}
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
"""

var new_game_button: Button
var load_game_button: Button
var options_button: Button
var quit_button: Button

var fullscreen_button: Button
var windowed_button: Button
var borderless_button: Button
var volume_slider: HSlider
var volume_value_label: Label
var back_button: Button

var _main_view: Control
var _options_view: Control
var _card_panel: PanelContainer
var _camera: Camera3D
var _camera_base_pos: Vector3
var _diorama_root: Node3D
var _penguin_pivot: Node3D
var _penguin_body: Node3D
var _left_flipper: MeshInstance3D
var _right_flipper: MeshInstance3D
var _anim_time := 0.0
var _wave_timer := 0.0


func _ready() -> void:
	GameManager.ensure_settings_loaded()
	AudioManager.play_ambient_music()
	_build_3d_diorama()
	_build_ui()
	_refresh_load_button()
	_refresh_options_ui()


func _process(delta: float) -> void:
	_anim_time += delta
	if _wave_timer > 0.0:
		_wave_timer = maxf(0.0, _wave_timer - delta)

	if is_instance_valid(_camera):
		var bob_y := sin(_anim_time * 1.2) * 0.06
		var sway_x := cos(_anim_time * 0.8) * 0.08
		_camera.position = _camera_base_pos + Vector3(sway_x, bob_y, -sway_x * 0.5)

	if is_instance_valid(_penguin_body):
		var breath := sin(_anim_time * 2.8) * 0.022
		_penguin_body.scale = Vector3(1.0 - breath * 0.5, 1.0 + breath, 1.0 - breath * 0.5)
		_penguin_body.rotation.z = sin(_anim_time * 1.4) * deg_to_rad(2.2)

	if is_instance_valid(_left_flipper) and is_instance_valid(_right_flipper):
		var idle_flap := (sin(_anim_time * 2.8) * 0.5 + 0.5) * deg_to_rad(5.0)
		_left_flipper.rotation = _left_flipper.rotation.lerp(Vector3(-idle_flap, 0.0, sin(_anim_time * 1.6) * deg_to_rad(6.0)), 10.0 * delta)
		if _wave_timer > 0.0:
			var wave_angle := deg_to_rad(85.0) + sin(_anim_time * 14.0) * deg_to_rad(18.0)
			_right_flipper.rotation = _right_flipper.rotation.lerp(Vector3(deg_to_rad(12.0), deg_to_rad(10.0), wave_angle), 16.0 * delta)
		else:
			_right_flipper.rotation = _right_flipper.rotation.lerp(Vector3(idle_flap, 0.0, -sin(_anim_time * 1.6) * deg_to_rad(6.0)), 10.0 * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and is_instance_valid(_options_view) and _options_view.visible:
		_show_main_view()
		get_viewport().set_input_as_handled()


#==================3D Low-Poly Cute Diorama==================

func _build_3d_diorama() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = WINTER_ENV
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(
		Vector3(0.970408, 0.068259, 0.231623),
		Vector3(0.197802, 0.325479, -0.924628),
		Vector3(-0.138502, 0.943082, 0.302346),
		Vector3.ZERO
	)
	sun.light_color = Color(1.0, 0.968627, 0.921569, 1.0)
	sun.light_energy = 1.18
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	_diorama_root = Node3D.new()
	_diorama_root.name = "Diorama"
	add_child(_diorama_root)

	var floor_mesh := _extract_scaled_mesh(SUELO_NIEVE, Vector3.ZERO)
	var ice_mesh: ArrayMesh = BOX_MESH._interactable_mesh(false, Vector3i.ZERO)
	var snow_box_mesh := _extract_snow_box_mesh()
	var wall_mesh := _extract_wall_mesh()
	var water_mesh := _extract_water_mesh()

	# Base de agua animada coordinada alrededor de la isla (7x7 en y = -1.5)
	for x in range(-2, 6):
		for z in range(-2, 6):
			var w := MeshInstance3D.new()
			w.mesh = water_mesh
			w.position = Vector3(x + 0.5, -1.5, z + 0.5)
			_diorama_root.add_child(w)

	# Piso de nieve 5x5 en y = -0.5
	for x in range(0, 5):
		for z in range(0, 5):
			var tile := MeshInstance3D.new()
			tile.mesh = floor_mesh
			tile.position = Vector3(x + 0.5, -0.5, z + 0.5)
			_diorama_root.add_child(tile)

	# Paredes bajas decorativas de nieve en el borde trasero (x = -1 y z = -1)
	for x in range(-1, 5):
		for h in range(-1, 2):
			var w := MeshInstance3D.new()
			w.mesh = wall_mesh
			w.position = Vector3(x + 0.5, h + 0.5, -0.5)
			_diorama_root.add_child(w)
	for z in range(0, 5):
		for h in range(-1, 2):
			var w := MeshInstance3D.new()
			w.mesh = wall_mesh
			w.position = Vector3(-0.5, h + 0.5, z + 0.5)
			_diorama_root.add_child(w)

	# Bloques decorativos de hielo y nieve en la isla
	var deco_blocks := [
		{"pos": Vector3i(1, 0, 1), "mesh": ice_mesh},
		{"pos": Vector3i(1, 1, 1), "mesh": snow_box_mesh},
		{"pos": Vector3i(2, 0, 1), "mesh": snow_box_mesh},
		{"pos": Vector3i(0, 0, 2), "mesh": snow_box_mesh},
		{"pos": Vector3i(3, 0, 0), "mesh": ice_mesh},
	]
	for entry: Dictionary in deco_blocks:
		var cell: Vector3i = entry["pos"]
		var blk := MeshInstance3D.new()
		blk.mesh = entry["mesh"]
		blk.position = Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5)
		_diorama_root.add_child(blk)

	# Botón rojo cute sobre su pedestal de hielo
	var btn_inst := BUTTON_MODEL.instantiate() as Node3D
	btn_inst.position = Vector3(3.5, 0.25, 2.5)
	btn_inst.scale = Vector3(0.28, 0.28, 0.28)
	_diorama_root.add_child(btn_inst)

	var btn_top := BUTTON_TOP_MODEL.instantiate() as Node3D
	btn_top.position = Vector3(3.5, 0.56, 2.5)
	btn_top.scale = Vector3(0.18, 0.18, 0.18)
	_diorama_root.add_child(btn_top)

	# Puerta de salida verde en el fondo de la isla
	var door_inst := DOOR_MODEL.instantiate() as Node3D
	door_inst.position = Vector3(4.5, 0.35, 1.5)
	door_inst.scale = Vector3(0.35, 0.35, 0.35)
	door_inst.rotation.y = PI * 0.5
	_diorama_root.add_child(door_inst)

	# Personaje Gramm en el centro-frente de la isla
	_penguin_pivot = Node3D.new()
	_penguin_pivot.name = "PenguinPivot"
	_penguin_pivot.position = Vector3(2.5, 0.0, 3.2)
	# Mirando hacia la cámara isométrica (+X / +Z)
	_penguin_pivot.basis = Basis.looking_at(Vector3(1.0, 0.0, 1.0).normalized())
	_diorama_root.add_child(_penguin_pivot)

	_penguin_body = Node3D.new()
	_penguin_body.name = "Body"
	_penguin_pivot.add_child(_penguin_body)

	var gramm := GRAMM_MODEL.instantiate() as Node3D
	gramm.name = "Personaje_gramm"
	gramm.transform = Transform3D(
		Vector3(0.0, 0.0, -0.42),
		Vector3(0.0, 0.42, 0.0),
		Vector3(0.42, 0.0, 0.0),
		Vector3(0.0, 0.44, 0.0)
	)
	_penguin_body.add_child(gramm)
	_setup_diorama_flippers(gramm)

	# Partículas de nieve cayendo sobre el diorama
	var snow := SNOW_SCENE.instantiate() as SnowParticles
	snow.auto_fit_room = false
	snow.position = Vector3(2.5, 6.0, 2.5)
	_diorama_root.add_child(snow)

	# Cámara ortogonal isométrica encuadrando la isla a la derecha y dejando aire a la izquierda para el menú
	_camera = Camera3D.new()
	_camera.name = "MenuCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 7.4
	var cam_basis := Basis(
		Vector3(0.70710677, 0.0, -0.70710677),
		Vector3(-0.3535534, 0.86602545, -0.3535534),
		Vector3(0.61237246, 0.50000006, 0.61237246)
	)
	# Desplazamos el centro de cámara hacia la izquierda de la isla para que la isla luzca a la derecha
	var focus := Vector3(1.2, 0.8, 3.2)
	_camera_base_pos = focus + cam_basis.z * 20.0
	_camera.transform = Transform3D(cam_basis, _camera_base_pos)
	_camera.current = true
	add_child(_camera)


func _setup_diorama_flippers(gramm: Node3D) -> void:
	var cube := gramm.get_node_or_null("Cube") as MeshInstance3D
	if cube == null or cube.mesh == null:
		return
	var source := cube.mesh
	var cube_scale := cube.scale
	var body_mesh := ArrayMesh.new()
	var left_mesh := ArrayMesh.new()
	var right_mesh := ArrayMesh.new()

	for surface in source.get_surface_count():
		var orig_mat := source.surface_get_material(surface)
		var mat: StandardMaterial3D = orig_mat.duplicate() if orig_mat else null
		if mat != null:
			# Estilo opaco y rasposo sin brillos ni reflejos
			mat.roughness = 0.98
			mat.metallic = 0.0
			mat.metallic_specular = 0.0
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY

		var arrays := source.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV and arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

		var st_body := SurfaceTool.new()
		var st_left := SurfaceTool.new()
		var st_right := SurfaceTool.new()
		st_body.begin(Mesh.PRIMITIVE_TRIANGLES)
		st_left.begin(Mesh.PRIMITIVE_TRIANGLES)
		st_right.begin(Mesh.PRIMITIVE_TRIANGLES)
		var has_body := false
		var has_left := false
		var has_right := false

		for t in range(0, indices.size(), 3):
			var i0 := indices[t]
			var i1 := indices[t + 1]
			var i2 := indices[t + 2]
			var v0 := verts[i0]
			var v1 := verts[i1]
			var v2 := verts[i2]
			if Player._is_left_flipper_vertex(v0) and Player._is_left_flipper_vertex(v1) and Player._is_left_flipper_vertex(v2):
				has_left = true
				for idx in [i0, i1, i2]:
					if normals.size() > idx:
						st_left.set_normal(normals[idx])
					if uvs.size() > idx:
						st_left.set_uv(uvs[idx])
					if colors.size() > idx:
						st_left.set_color(colors[idx])
					st_left.add_vertex(verts[idx] * cube_scale - Player.LEFT_SHOULDER_PIVOT)
			elif Player._is_right_flipper_vertex(v0) and Player._is_right_flipper_vertex(v1) and Player._is_right_flipper_vertex(v2):
				has_right = true
				for idx in [i0, i1, i2]:
					if normals.size() > idx:
						st_right.set_normal(normals[idx])
					if uvs.size() > idx:
						st_right.set_uv(uvs[idx])
					if colors.size() > idx:
						st_right.set_color(colors[idx])
					st_right.add_vertex(verts[idx] * cube_scale - Player.RIGHT_SHOULDER_PIVOT)
			else:
				has_body = true
				for idx in [i0, i1, i2]:
					if normals.size() > idx:
						st_body.set_normal(normals[idx])
					if uvs.size() > idx:
						st_body.set_uv(uvs[idx])
					if colors.size() > idx:
						st_body.set_color(colors[idx])
					st_body.add_vertex(verts[idx])

		if has_body:
			st_body.index()
			st_body.set_material(mat)
			st_body.commit(body_mesh)
		if has_left:
			st_left.index()
			st_left.set_material(mat)
			st_left.commit(left_mesh)
		if has_right:
			st_right.index()
			st_right.set_material(mat)
			st_right.commit(right_mesh)

	cube.mesh = body_mesh

	# Pico (Cube_001): aplicar también material opaco manteniendo las normales originales
	var beak := gramm.get_node_or_null("Cube_001") as MeshInstance3D
	if beak != null and beak.mesh != null:
		var beak_mesh := ArrayMesh.new()
		for s in beak.mesh.get_surface_count():
			var b_orig := beak.mesh.surface_get_material(s)
			var b_mat: StandardMaterial3D = b_orig.duplicate() if b_orig else null
			if b_mat != null:
				b_mat.roughness = 0.98
				b_mat.metallic = 0.0
				b_mat.metallic_specular = 0.0
				b_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				b_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
			var st_beak := SurfaceTool.new()
			st_beak.append_from(beak.mesh, s, Transform3D.IDENTITY)
			st_beak.set_material(b_mat)
			st_beak.commit(beak_mesh)
		beak.mesh = beak_mesh

	_left_flipper = MeshInstance3D.new()
	_left_flipper.mesh = left_mesh
	_left_flipper.position = Player.LEFT_SHOULDER_PIVOT
	gramm.add_child(_left_flipper)

	_right_flipper = MeshInstance3D.new()
	_right_flipper.mesh = right_mesh
	_right_flipper.position = Player.RIGHT_SHOULDER_PIVOT
	gramm.add_child(_right_flipper)
	_wave_timer = 1.4


func _extract_scaled_mesh(scene: PackedScene, offset: Vector3) -> ArrayMesh:
	var root := scene.instantiate()
	var mesh_inst := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source := mesh_inst.mesh
	var aabb := source.get_aabb()
	var scale_vec := Vector3.ONE / aabb.size
	var center_offset := -(aabb.position + aabb.size * 0.5) * scale_vec + offset
	var xform := Transform3D(Basis.from_scale(scale_vec), center_offset)
	var out := ArrayMesh.new()
	for s in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, s, xform)
		st.set_material(source.surface_get_material(s))
		st.commit(out)
	root.free()
	return out


func _extract_snow_box_mesh() -> ArrayMesh:
	var out := ArrayMesh.new()
	BOX_MESH._append_mesh(out, BOX_MESH._interactable_mesh(false, Vector3i.ZERO))
	BOX_MESH._append_mesh(out, BOX_MESH._snow_mesh(false))
	return out


func _extract_wall_mesh() -> ArrayMesh:
	var snow_root := WALKABLE_NIEVE.instantiate()
	var snow_mesh := (snow_root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var snow_mat := snow_mesh.surface_get_material(0)
	snow_root.free()

	var root := PARED_NIEVE.instantiate()
	var mesh_inst := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source := mesh_inst.mesh
	var aabb := source.get_aabb()
	var scale_vec := Vector3.ONE / aabb.size
	var center_offset := -(aabb.position + aabb.size * 0.5) * scale_vec
	var xform := Transform3D(Basis.from_scale(scale_vec), center_offset)
	var out := ArrayMesh.new()
	for s in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, s, xform)
		st.set_material(snow_mat if s == 0 else source.surface_get_material(s))
		st.commit(out)
	root.free()
	return out


func _extract_water_mesh() -> ArrayMesh:
	var root := CUBO_AGUA.instantiate()
	var mesh_inst := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source := mesh_inst.mesh
	var aabb := source.get_aabb()
	var scale_vec := Vector3.ONE / aabb.size
	var center_offset := -(aabb.position + aabb.size * 0.5) * scale_vec
	var xform := Transform3D(Basis.from_scale(scale_vec), center_offset)

	var shader := Shader.new()
	shader.code = WATER_WAVE_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = shader

	var out := ArrayMesh.new()
	for s in source.get_surface_count():
		var st := SurfaceTool.new()
		st.append_from(source, s, xform)
		st.set_material(smat)
		st.commit(out)
	root.free()
	return out


#==================Low-Poly Cute UI==================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MenuCanvas"
	add_child(layer)

	var root_ctrl := Control.new()
	root_ctrl.name = "Root"
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root_ctrl)

	# Contenedor lateral izquierdo centrado verticalmente para dejar lucir el diorama 3D a la derecha
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_right", 96)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 56)
	root_ctrl.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(hbox)

	var left_center := CenterContainer.new()
	left_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(left_center)

	# Tarjeta principal estilo bloque de nieve/hielo low-poly cute
	_card_panel = PanelContainer.new()
	_card_panel.custom_minimum_size = Vector2(540, 0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.95, 0.98, 1.0, 0.94)
	card_style.border_color = Color(0.56, 0.80, 0.96, 1.0)
	card_style.border_width_left = 4
	card_style.border_width_top = 4
	card_style.border_width_right = 4
	card_style.border_width_bottom = 12
	card_style.corner_radius_top_left = 24
	card_style.corner_radius_top_right = 24
	card_style.corner_radius_bottom_left = 24
	card_style.corner_radius_bottom_right = 24
	card_style.shadow_color = Color(0.10, 0.25, 0.42, 0.22)
	card_style.shadow_size = 24
	card_style.shadow_offset = Vector2(0, 10)
	card_style.content_margin_left = 40
	card_style.content_margin_right = 40
	card_style.content_margin_top = 36
	card_style.content_margin_bottom = 38
	_card_panel.add_theme_stylebox_override("panel", card_style)
	left_center.add_child(_card_panel)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 24)
	_card_panel.add_child(card_vbox)

	# Encabezado simplificado: nieve del menú y texto en hielo debajo
	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 0)
	card_vbox.add_child(header_vbox)

	# Capa de nieve blanca en el borde superior
	var snow_cap := PanelContainer.new()
	snow_cap.custom_minimum_size = Vector2(0, 16)
	var cap_style := StyleBoxFlat.new()
	cap_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	cap_style.border_color = Color(0.82, 0.91, 0.98, 1.0)
	cap_style.border_width_bottom = 2
	cap_style.corner_radius_top_left = 18
	cap_style.corner_radius_top_right = 18
	cap_style.corner_radius_bottom_left = 4
	cap_style.corner_radius_bottom_right = 4
	snow_cap.add_theme_stylebox_override("panel", cap_style)
	header_vbox.add_child(snow_cap)

	# Bloque de hielo traslúcido debajo de la nieve con el texto tallado
	var ice_panel := PanelContainer.new()
	var ice_style := StyleBoxFlat.new()
	ice_style.bg_color = Color(0.86, 0.94, 0.99, 0.75)
	ice_style.border_color = Color(0.62, 0.84, 0.96, 0.9)
	ice_style.border_width_left = 3
	ice_style.border_width_right = 3
	ice_style.border_width_bottom = 5
	ice_style.corner_radius_bottom_left = 18
	ice_style.corner_radius_bottom_right = 18
	ice_style.content_margin_top = 10
	ice_style.content_margin_bottom = 12
	ice_style.content_margin_left = 16
	ice_style.content_margin_right = 16
	ice_panel.add_theme_stylebox_override("panel", ice_style)
	header_vbox.add_child(ice_panel)

	# Texto escrito como hielo debajo de la nieve del menú
	var title_lbl := Label.new()
	title_lbl.text = "The Gramm-Smidth Project"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 30)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.44, 0.72, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color(0.92, 0.97, 1.0, 1.0))
	title_lbl.add_theme_constant_override("outline_size", 2)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.68, 0.88, 1.0, 0.9))
	title_lbl.add_theme_constant_override("shadow_offset_x", 0)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	ice_panel.add_child(title_lbl)

	# Vista 1: Los 4 botones principales en el orden pedido
	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainView"
	main_vbox.add_theme_constant_override("separation", 14)
	card_vbox.add_child(main_vbox)
	_main_view = main_vbox

	# 1. Nueva partida (Celeste con hover a celeste más oscuro)
	new_game_button = _create_cute_button(
		"Nueva partida",
		Color(0.38, 0.76, 0.96, 1.0),
		Color(0.18, 0.54, 0.78, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	new_game_button.pressed.connect(_on_new_game_pressed)
	main_vbox.add_child(new_game_button)

	# 2. Cargar partida (Blanco con hover a celeste más oscuro)
	load_game_button = _create_cute_button(
		"Cargar partida",
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.74, 0.84, 0.92, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(0.16, 0.32, 0.50, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	load_game_button.pressed.connect(_on_load_game_pressed)
	main_vbox.add_child(load_game_button)

	# 3. Opciones (Blanco con hover a celeste más oscuro)
	options_button = _create_cute_button(
		"Opciones",
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.74, 0.84, 0.92, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(0.16, 0.32, 0.50, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	options_button.pressed.connect(_show_options_view)
	main_vbox.add_child(options_button)

	# 4. Salir (Queda rojo/coral como antes)
	quit_button = _create_cute_button(
		"Salir",
		Color(0.96, 0.44, 0.48, 1.0),
		Color(0.75, 0.26, 0.31, 1.0),
		Color(0.99, 0.52, 0.55, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.80, 0.30, 0.35, 1.0)
	)
	quit_button.pressed.connect(_on_quit_pressed)
	main_vbox.add_child(quit_button)

	# Vista 2: Menú de Opciones
	var options_vbox := VBoxContainer.new()
	options_vbox.name = "OptionsView"
	options_vbox.visible = false
	options_vbox.add_theme_constant_override("separation", 18)
	card_vbox.add_child(options_vbox)
	_options_view = options_vbox

	var options_title := Label.new()
	options_title.text = "OPCIONES"
	options_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_title.add_theme_font_size_override("font_size", 24)
	options_title.add_theme_color_override("font_color", Color(0.14, 0.30, 0.48, 1.0))
	options_vbox.add_child(options_title)

	# Sección Pantalla
	var screen_box := VBoxContainer.new()
	screen_box.add_theme_constant_override("separation", 10)
	options_vbox.add_child(screen_box)

	var screen_lbl := Label.new()
	screen_lbl.text = "Modo de pantalla"
	screen_lbl.add_theme_font_size_override("font_size", 18)
	screen_lbl.add_theme_color_override("font_color", Color(0.22, 0.38, 0.55, 1.0))
	screen_box.add_child(screen_lbl)

	fullscreen_button = _create_mode_button("Pantalla completa", GameManager.ScreenMode.FULLSCREEN)
	screen_box.add_child(fullscreen_button)

	windowed_button = _create_mode_button("Ventana", GameManager.ScreenMode.WINDOWED)
	screen_box.add_child(windowed_button)

	borderless_button = _create_mode_button("Completa en ventana", GameManager.ScreenMode.BORDERLESS_FULLSCREEN)
	screen_box.add_child(borderless_button)

	# Sección Volumen (preparada para el volumen del juego)
	var volume_box := VBoxContainer.new()
	volume_box.add_theme_constant_override("separation", 8)
	options_vbox.add_child(volume_box)

	var vol_header := HBoxContainer.new()
	volume_box.add_child(vol_header)

	var vol_lbl := Label.new()
	vol_lbl.text = "Volumen del juego"
	vol_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_lbl.add_theme_font_size_override("font_size", 18)
	vol_lbl.add_theme_color_override("font_color", Color(0.22, 0.38, 0.55, 1.0))
	vol_header.add_child(vol_lbl)

	volume_value_label = Label.new()
	volume_value_label.text = "80%"
	volume_value_label.add_theme_font_size_override("font_size", 18)
	volume_value_label.add_theme_color_override("font_color", Color(0.16, 0.54, 0.84, 1.0))
	vol_header.add_child(volume_value_label)

	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.custom_minimum_size = Vector2(0, 32)
	_style_volume_slider(volume_slider)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_box.add_child(volume_slider)

	# Botón Volver (Blanco con hover a celeste más oscuro)
	back_button = _create_cute_button(
		"Volver",
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.74, 0.84, 0.92, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(0.16, 0.32, 0.50, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	back_button.pressed.connect(_show_main_view)
	options_vbox.add_child(back_button)


func _create_cute_button(
	text_str: String,
	bg: Color,
	bevel: Color,
	hover_bg: Color,
	text_col: Color,
	hover_text_col: Color = Color.WHITE,
	hover_bevel: Color = Color(0, 0, 0, 0)
) -> Button:
	var btn := Button.new()
	btn.text = text_str
	btn.custom_minimum_size = Vector2(0, 62)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 23)
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", hover_text_col)
	btn.add_theme_color_override("font_focus_color", hover_text_col)
	btn.add_theme_color_override("font_pressed_color", hover_text_col)
	btn.add_theme_color_override("font_disabled_color", Color(0.60, 0.70, 0.80, 0.85))

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = bevel
	normal.border_width_left = 3
	normal.border_width_top = 3
	normal.border_width_right = 3
	normal.border_width_bottom = 8
	normal.corner_radius_top_left = 16
	normal.corner_radius_top_right = 16
	normal.corner_radius_bottom_left = 16
	normal.corner_radius_bottom_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 14

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_bg
	if hover_bevel.a > 0.0:
		hover.border_color = hover_bevel
	hover.border_width_bottom = 9

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = hover_bg.darkened(0.08)
	pressed.border_width_bottom = 4
	pressed.content_margin_top = 14
	pressed.content_margin_bottom = 10

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.92, 0.94, 0.96, 0.75)
	disabled.border_color = Color(0.82, 0.88, 0.92, 0.85)
	disabled.border_width_bottom = 5

	var focus := hover.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.11, 0.24, 0.40, 1.0)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", focus)

	btn.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
	)
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			AudioManager.play_ui_hover()
			_wave_timer = 0.55
	)
	return btn


func _create_mode_button(label_text: String, mode: GameManager.ScreenMode) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, 50)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 19)
	btn.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
		GameManager.set_screen_mode(mode)
		_refresh_options_ui()
		_wave_timer = 0.55
	)
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			AudioManager.play_ui_hover()
	)
	return btn


func _apply_mode_button_style(btn: Button, is_selected: bool) -> void:
	if not is_instance_valid(btn):
		return
	var bg := Color(0.38, 0.76, 0.96, 1.0) if is_selected else Color(1.0, 1.0, 1.0, 1.0)
	var bevel := Color(0.18, 0.54, 0.78, 1.0) if is_selected else Color(0.74, 0.84, 0.92, 1.0)
	var txt_col := Color(1.0, 1.0, 1.0, 1.0) if is_selected else Color(0.16, 0.32, 0.50, 1.0)
	var hover_bg := Color(0.14, 0.44, 0.72, 1.0)
	var hover_bevel := Color(0.08, 0.30, 0.54, 1.0)

	btn.add_theme_color_override("font_color", txt_col)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = bevel
	normal.border_width_left = 3
	normal.border_width_top = 3
	normal.border_width_right = 3
	normal.border_width_bottom = 6
	normal.corner_radius_top_left = 14
	normal.corner_radius_top_right = 14
	normal.corner_radius_bottom_left = 14
	normal.corner_radius_bottom_right = 14

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_bg
	hover.border_color = hover_bevel

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("focus", hover)


func _style_volume_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.80, 0.90, 0.98, 1.0)
	track.border_color = Color(0.62, 0.78, 0.92, 1.0)
	track.border_width_bottom = 3
	track.corner_radius_top_left = 8
	track.corner_radius_top_right = 8
	track.corner_radius_bottom_left = 8
	track.corner_radius_bottom_right = 8
	track.content_margin_top = 6
	track.content_margin_bottom = 6

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.22, 0.68, 0.96, 1.0)
	fill.border_color = Color(0.11, 0.48, 0.75, 1.0)
	fill.border_width_bottom = 3
	fill.corner_radius_top_left = 8
	fill.corner_radius_top_right = 8
	fill.corner_radius_bottom_left = 8
	fill.corner_radius_bottom_right = 8
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6

	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


func _refresh_load_button() -> void:
	if not is_instance_valid(load_game_button):
		return
	var can_load := GameManager.has_save()
	load_game_button.disabled = not can_load
	load_game_button.focus_mode = Control.FOCUS_ALL if can_load else Control.FOCUS_NONE
	load_game_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can_load else Control.CURSOR_FORBIDDEN
	if can_load:
		var level_label := GameManager.get_saved_level_label()
		load_game_button.text = "Cargar partida (%s)" % level_label if not level_label.is_empty() else "Cargar partida"
	else:
		load_game_button.text = "Cargar partida"


func _refresh_options_ui() -> void:
	var current_mode := GameManager.get_screen_mode()
	_apply_mode_button_style(fullscreen_button, current_mode == GameManager.ScreenMode.FULLSCREEN)
	_apply_mode_button_style(windowed_button, current_mode == GameManager.ScreenMode.WINDOWED)
	_apply_mode_button_style(borderless_button, current_mode == GameManager.ScreenMode.BORDERLESS_FULLSCREEN)

	if is_instance_valid(volume_slider):
		var pct := roundi(GameManager.get_master_volume() * 100.0)
		volume_slider.set_value_no_signal(pct)
		if is_instance_valid(volume_value_label):
			volume_value_label.text = "%d%%" % pct


func _show_options_view() -> void:
	_refresh_options_ui()
	_main_view.visible = false
	_options_view.visible = true
	_wave_timer = 0.65
	if is_instance_valid(fullscreen_button):
		fullscreen_button.grab_focus()


func _show_main_view() -> void:
	_refresh_load_button()
	_options_view.visible = false
	_main_view.visible = true
	_wave_timer = 0.65
	if is_instance_valid(new_game_button):
		new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	GameManager.start_new_game(get_tree())


func _on_load_game_pressed() -> void:
	if GameManager.has_save():
		GameManager.load_saved_game(get_tree())


func _on_volume_changed(value: float) -> void:
	GameManager.set_master_volume(value / 100.0)
	if is_instance_valid(volume_value_label):
		volume_value_label.text = "%d%%" % roundi(value)


func _on_quit_pressed() -> void:
	get_tree().quit()
