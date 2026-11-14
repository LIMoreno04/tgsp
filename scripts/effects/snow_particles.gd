class_name SnowParticles
extends GPUParticles3D

@export var auto_fit_room: bool = true


func _ready() -> void:
	_ensure_resources()
	if not auto_fit_room:
		return
	var room: Room = get_parent() as Room
	if room == null:
		var current_node := get_parent()
		while current_node != null and not (current_node is Room):
			current_node = current_node.get_parent()
		room = current_node as Room
	if room != null:
		fit_to_room(room)


func _ensure_resources() -> void:
	if process_material == null:
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(10, 1, 10)
		mat.direction = Vector3(0.2, -1.0, 0.15).normalized()
		mat.spread = 20.0
		mat.initial_velocity_min = 0.8
		mat.initial_velocity_max = 1.4
		mat.gravity = Vector3(0, -0.4, 0)
		mat.scale_min = 0.04
		mat.scale_max = 0.08
		mat.color = Color(1.0, 1.0, 1.0, 0.8)
		process_material = mat
		amount = 120
		lifetime = 6.0
		preprocess = 5.0

	if draw_pass_1 == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
		var grad_tex := GradientTexture2D.new()
		grad_tex.gradient = gradient
		grad_tex.fill = GradientTexture2D.FILL_RADIAL
		grad_tex.fill_from = Vector2(0.5, 0.5)
		grad_tex.fill_to = Vector2(0.5, 0.0)
		grad_tex.width = 32
		grad_tex.height = 32

		var quad := QuadMesh.new()
		quad.size = Vector2(0.09, 0.09)
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		smat.albedo_texture = grad_tex
		smat.albedo_color = Color(0.92, 0.96, 1.0, 0.85)
		quad.material = smat
		draw_pass_1 = quad


func fit_to_room(room: Room) -> void:
	var size_x := float(room.dimensions.x)
	var size_z := float(room.dimensions.y)
	var height := float(room.dimensions.z)

	# Se posiciona centrado en X/Z y por encima de la altura del cuarto
	position = Vector3(size_x / 2.0, height + 3.0, size_z / 2.0)

	if process_material is ParticleProcessMaterial:
		var mat := process_material as ParticleProcessMaterial
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(size_x / 2.0 + 2.0, 1.0, size_z / 2.0 + 2.0)

		# Cantidad de copos proporcional al tamaño del nivel, manteniendo rendimiento muy ligero
		var area := size_x * size_z
		amount = clampi(int(area * 0.4), 50, 250)
