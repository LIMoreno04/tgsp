class_name PauseMenu
extends CanvasLayer

signal resumed()
signal saved()
signal exited()

var level: Level = null
var is_open := false

var _dim_overlay: ColorRect
var _card_panel: PanelContainer
var _main_view: VBoxContainer
var _options_view: VBoxContainer
var _controls_view: VBoxContainer
var _level_name_lbl: Label
var _status_lbl: Label
var _resume_button: Button
var _save_button: Button
var _options_button: Button
var _quit_button: Button
var _controls_button: Button
var _back_button: Button
var _controls_back_button: Button
var _fullscreen_button: Button
var _windowed_button: Button
var _borderless_button: Button
var _volume_slider: HSlider
var _volume_value_lbl: Label
var _status_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	if _card_panel == null:
		_build_ui()


func open(for_level: Level) -> void:
	level = for_level
	if _card_panel == null:
		_build_ui()
	is_open = true
	visible = true
	var tree := get_tree() if is_inside_tree() else (level.get_tree() if level != null else null)
	if tree != null:
		tree.paused = true

	if _status_lbl != null:
		_status_lbl.modulate.a = 0.0

	_show_main_view()
	_update_level_label()
	_refresh_options_ui()

	# Animación de apertura pop low-poly
	_dim_overlay.modulate.a = 0.0
	_card_panel.scale = Vector2(0.92, 0.92)
	_card_panel.pivot_offset = _card_panel.size * 0.5

	var tween := create_tween()
	if tween != null:
		tween = tween.set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(_dim_overlay, "modulate:a", 1.0, 0.16)
		tween.tween_property(_card_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if _resume_button != null:
		_resume_button.grab_focus.call_deferred()


func close() -> void:
	if not is_open:
		return
	is_open = false
	var tree := get_tree() if is_inside_tree() else (level.get_tree() if level != null else null)
	if tree != null:
		tree.paused = false

	var tween := create_tween()
	if tween != null:
		tween = tween.set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(_dim_overlay, "modulate:a", 0.0, 0.14)
		tween.tween_property(_card_panel, "scale", Vector2(0.92, 0.92), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.finished.connect(func() -> void:
			visible = false
			resumed.emit()
		)
	else:
		visible = false
		resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _controls_view != null and _controls_view.visible:
			_show_options_view()
		elif _options_view.visible:
			_show_main_view()
		else:
			close()


func _build_ui() -> void:
	# Contenedor raíz a pantalla completa
	var root_ctrl := Control.new()
	root_ctrl.name = "Root"
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root_ctrl)

	# Fondo oscuro/azulado con efecto de desenfoque/overlay
	_dim_overlay = ColorRect.new()
	_dim_overlay.name = "DimOverlay"
	_dim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_overlay.color = Color(0.06, 0.14, 0.24, 0.62)
	root_ctrl.add_child(_dim_overlay)

	# Centro de la pantalla
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	# Tarjeta principal idéntica al estilo de menú principal
	_card_panel = PanelContainer.new()
	_card_panel.custom_minimum_size = Vector2(460, 0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.95, 0.98, 1.0, 0.96)
	card_style.border_color = Color(0.56, 0.80, 0.96, 1.0)
	card_style.border_width_left = 4
	card_style.border_width_top = 4
	card_style.border_width_right = 4
	card_style.border_width_bottom = 12
	card_style.corner_radius_top_left = 22
	card_style.corner_radius_top_right = 22
	card_style.corner_radius_bottom_left = 22
	card_style.corner_radius_bottom_right = 22
	card_style.shadow_color = Color(0.08, 0.20, 0.35, 0.35)
	card_style.shadow_size = 28
	card_style.shadow_offset = Vector2(0, 10)
	card_style.content_margin_left = 36
	card_style.content_margin_right = 36
	card_style.content_margin_top = 28
	card_style.content_margin_bottom = 32
	_card_panel.add_theme_stylebox_override("panel", card_style)
	center.add_child(_card_panel)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 20)
	_card_panel.add_child(card_vbox)

	# Encabezado: nieve arriba y caja de hielo con "PAUSA"
	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 0)
	card_vbox.add_child(header_vbox)

	# Capa de nieve blanca
	var snow_cap := PanelContainer.new()
	snow_cap.custom_minimum_size = Vector2(0, 14)
	var cap_style := StyleBoxFlat.new()
	cap_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	cap_style.border_color = Color(0.82, 0.91, 0.98, 1.0)
	cap_style.border_width_bottom = 2
	cap_style.corner_radius_top_left = 16
	cap_style.corner_radius_top_right = 16
	cap_style.corner_radius_bottom_left = 4
	cap_style.corner_radius_bottom_right = 4
	snow_cap.add_theme_stylebox_override("panel", cap_style)
	header_vbox.add_child(snow_cap)

	# Bloque de hielo traslúcido
	var ice_panel := PanelContainer.new()
	var ice_style := StyleBoxFlat.new()
	ice_style.bg_color = Color(0.86, 0.94, 0.99, 0.78)
	ice_style.border_color = Color(0.62, 0.84, 0.96, 0.95)
	ice_style.border_width_left = 3
	ice_style.border_width_right = 3
	ice_style.border_width_bottom = 5
	ice_style.corner_radius_bottom_left = 16
	ice_style.corner_radius_bottom_right = 16
	ice_style.content_margin_top = 8
	ice_style.content_margin_bottom = 10
	ice_style.content_margin_left = 16
	ice_style.content_margin_right = 16
	ice_panel.add_theme_stylebox_override("panel", ice_style)
	header_vbox.add_child(ice_panel)

	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	ice_panel.add_child(title_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "PAUSA"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.44, 0.72, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color(0.92, 0.97, 1.0, 1.0))
	title_lbl.add_theme_constant_override("outline_size", 2)
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.68, 0.88, 1.0, 0.9))
	title_lbl.add_theme_constant_override("shadow_offset_x", 0)
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	title_vbox.add_child(title_lbl)

	_level_name_lbl = Label.new()
	_level_name_lbl.text = "The Gramm-Smidth Project"
	_level_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_name_lbl.add_theme_font_size_override("font_size", 14)
	_level_name_lbl.add_theme_color_override("font_color", Color(0.24, 0.50, 0.74, 0.88))
	title_vbox.add_child(_level_name_lbl)

	# Vista Principal de Pausa
	_main_view = VBoxContainer.new()
	_main_view.name = "MainView"
	_main_view.add_theme_constant_override("separation", 12)
	card_vbox.add_child(_main_view)

	# 1. Reanudar (Celeste)
	_resume_button = _create_cute_button(
		"Reanudar",
		Color(0.38, 0.76, 0.96, 1.0),
		Color(0.18, 0.54, 0.78, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	_resume_button.pressed.connect(close)
	_main_view.add_child(_resume_button)

	# 2. Guardar partida (Blanco con hover celeste oscuro)
	_save_button = _create_cute_button(
		"Guardar partida",
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.74, 0.84, 0.92, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(0.16, 0.32, 0.50, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	_save_button.pressed.connect(_on_save_pressed)
	_main_view.add_child(_save_button)

	# 3. Opciones (Blanco con hover celeste oscuro)
	_options_button = _create_cute_button(
		"Opciones",
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.74, 0.84, 0.92, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(0.16, 0.32, 0.50, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	_options_button.pressed.connect(_show_options_view)
	_main_view.add_child(_options_button)

	# 4. Salir (Rojo/coral)
	_quit_button = _create_cute_button(
		"Salir",
		Color(0.96, 0.44, 0.48, 1.0),
		Color(0.75, 0.26, 0.31, 1.0),
		Color(0.99, 0.52, 0.55, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.80, 0.30, 0.35, 1.0)
	)
	_quit_button.pressed.connect(_on_quit_pressed)
	_main_view.add_child(_quit_button)

	# Mensaje de retroalimentación de guardado
	_status_lbl = Label.new()
	_status_lbl.text = "✓ ¡Partida guardada con éxito!"
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 15)
	_status_lbl.add_theme_color_override("font_color", Color(0.12, 0.62, 0.42, 1.0))
	_status_lbl.modulate.a = 0.0
	_main_view.add_child(_status_lbl)

	# Vista de Opciones
	_options_view = VBoxContainer.new()
	_options_view.name = "OptionsView"
	_options_view.visible = false
	_options_view.add_theme_constant_override("separation", 16)
	card_vbox.add_child(_options_view)

	var options_title := Label.new()
	options_title.text = "OPCIONES"
	options_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_title.add_theme_font_size_override("font_size", 22)
	options_title.add_theme_color_override("font_color", Color(0.14, 0.30, 0.48, 1.0))
	_options_view.add_child(options_title)

	# Sección Pantalla
	var screen_box := VBoxContainer.new()
	screen_box.add_theme_constant_override("separation", 8)
	_options_view.add_child(screen_box)

	var screen_lbl := Label.new()
	screen_lbl.text = "Modo de pantalla"
	screen_lbl.add_theme_font_size_override("font_size", 16)
	screen_lbl.add_theme_color_override("font_color", Color(0.22, 0.38, 0.55, 1.0))
	screen_box.add_child(screen_lbl)

	_fullscreen_button = _create_mode_button("Pantalla completa", GameManager.ScreenMode.FULLSCREEN)
	screen_box.add_child(_fullscreen_button)

	_windowed_button = _create_mode_button("Ventana", GameManager.ScreenMode.WINDOWED)
	screen_box.add_child(_windowed_button)

	_borderless_button = _create_mode_button("Completa en ventana", GameManager.ScreenMode.BORDERLESS_FULLSCREEN)
	screen_box.add_child(_borderless_button)

	# Sección Volumen
	var volume_box := VBoxContainer.new()
	volume_box.add_theme_constant_override("separation", 6)
	_options_view.add_child(volume_box)

	var vol_hdr := HBoxContainer.new()
	volume_box.add_child(vol_hdr)

	var vol_lbl := Label.new()
	vol_lbl.text = "Volumen general"
	vol_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_lbl.add_theme_font_size_override("font_size", 16)
	vol_lbl.add_theme_color_override("font_color", Color(0.22, 0.38, 0.55, 1.0))
	vol_hdr.add_child(vol_lbl)

	_volume_value_lbl = Label.new()
	_volume_value_lbl.text = "100%"
	_volume_value_lbl.add_theme_font_size_override("font_size", 16)
	_volume_value_lbl.add_theme_color_override("font_color", Color(0.14, 0.44, 0.72, 1.0))
	vol_hdr.add_child(_volume_value_lbl)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = 1.0
	_volume_slider.custom_minimum_size = Vector2(0, 24)
	_volume_slider.value_changed.connect(func(val: float) -> void:
		GameManager.set_master_volume(val)
		_volume_value_lbl.text = "%d%%" % int(round(val * 100.0))
	)
	volume_box.add_child(_volume_slider)

	# Botón Controles
	_controls_button = _create_cute_button(
		"Controles",
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.74, 0.84, 0.92, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(0.16, 0.32, 0.50, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	_controls_button.custom_minimum_size = Vector2(0, 48)
	_controls_button.pressed.connect(_show_controls_view)
	_options_view.add_child(_controls_button)

	# Botón Volver
	_back_button = _create_cute_button(
		"Volver",
		Color(0.38, 0.76, 0.96, 1.0),
		Color(0.18, 0.54, 0.78, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	_back_button.custom_minimum_size = Vector2(0, 48)
	_back_button.pressed.connect(_show_main_view)
	_options_view.add_child(_back_button)

	# Vista de Controles
	_controls_view = VBoxContainer.new()
	_controls_view.name = "ControlsView"
	_controls_view.visible = false
	_controls_view.add_theme_constant_override("separation", 10)
	card_vbox.add_child(_controls_view)

	var controls_title := Label.new()
	controls_title.text = "CONTROLES"
	controls_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_title.add_theme_font_size_override("font_size", 22)
	controls_title.add_theme_color_override("font_color", Color(0.14, 0.30, 0.48, 1.0))
	_controls_view.add_child(controls_title)

	var controls_list := VBoxContainer.new()
	controls_list.add_theme_constant_override("separation", 6)
	_controls_view.add_child(controls_list)

	var bindings := [
		["W A S D / ↑↓←→", "Moverse"],
		["E", "Agarrar / Interactuar"],
		["Espacio", "Vista 2D / 3D"],
		["Z", "Deshacer"],
		["R", "Reiniciar nivel"],
		["Esc", "Pausa"],
	]
	for entry: Array in bindings:
		controls_list.add_child(_create_control_row(str(entry[0]), str(entry[1])))

	_controls_back_button = _create_cute_button(
		"Volver",
		Color(0.38, 0.76, 0.96, 1.0),
		Color(0.18, 0.54, 0.78, 1.0),
		Color(0.14, 0.44, 0.72, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(0.08, 0.30, 0.54, 1.0)
	)
	_controls_back_button.custom_minimum_size = Vector2(0, 48)
	_controls_back_button.pressed.connect(_show_options_view)
	_controls_view.add_child(_controls_back_button)


func _update_level_label() -> void:
	if _level_name_lbl == null:
		return
	if level != null and not level.scene_file_path.is_empty():
		var file := level.scene_file_path.get_file().get_basename()
		if file.begins_with("level_"):
			var num := file.trim_prefix("level_").to_int()
			if num > 0:
				_level_name_lbl.text = "Nivel %d" % num
				return
		_level_name_lbl.text = file.capitalize()
	else:
		_level_name_lbl.text = "The Gramm-Smidth Project"


func _on_save_pressed() -> void:
	if level != null:
		GameManager.save_level_state(level)
	saved.emit()
	_show_status("✓ ¡Partida guardada con éxito!")


func _on_quit_pressed() -> void:
	if level != null:
		GameManager.save_level_state(level)
	is_open = false
	var tree := get_tree() if is_inside_tree() else (level.get_tree() if level != null else null)
	if tree != null:
		tree.paused = false
	exited.emit()
	if tree != null:
		tree.change_scene_to_file(GameManager.MAIN_MENU_PATH)


func _show_main_view() -> void:
	_main_view.visible = true
	_options_view.visible = false
	if _controls_view != null:
		_controls_view.visible = false
	_resume_button.grab_focus.call_deferred()


func _show_options_view() -> void:
	_main_view.visible = false
	if _controls_view != null:
		_controls_view.visible = false
	_options_view.visible = true
	_refresh_options_ui()
	_back_button.grab_focus.call_deferred()


func _show_controls_view() -> void:
	_main_view.visible = false
	_options_view.visible = false
	if _controls_view != null:
		_controls_view.visible = true
	if _controls_back_button != null:
		_controls_back_button.grab_focus.call_deferred()


func _create_control_row(keys_text: String, action_text: String) -> Control:
	var row_panel := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.88, 0.95, 0.99, 0.72)
	row_style.border_color = Color(0.68, 0.85, 0.96, 0.9)
	row_style.border_width_left = 2
	row_style.border_width_top = 2
	row_style.border_width_right = 2
	row_style.border_width_bottom = 4
	row_style.corner_radius_top_left = 10
	row_style.corner_radius_top_right = 10
	row_style.corner_radius_bottom_left = 10
	row_style.corner_radius_bottom_right = 10
	row_style.content_margin_left = 12
	row_style.content_margin_right = 14
	row_style.content_margin_top = 5
	row_style.content_margin_bottom = 6
	row_panel.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row_panel.add_child(hbox)

	var key_badge := PanelContainer.new()
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	key_style.border_color = Color(0.56, 0.78, 0.92, 1.0)
	key_style.border_width_left = 2
	key_style.border_width_top = 2
	key_style.border_width_right = 2
	key_style.border_width_bottom = 4
	key_style.corner_radius_top_left = 7
	key_style.corner_radius_top_right = 7
	key_style.corner_radius_bottom_left = 7
	key_style.corner_radius_bottom_right = 7
	key_style.content_margin_left = 10
	key_style.content_margin_right = 10
	key_style.content_margin_top = 3
	key_style.content_margin_bottom = 4
	key_badge.add_theme_stylebox_override("panel", key_style)
	hbox.add_child(key_badge)

	var key_lbl := Label.new()
	key_lbl.text = keys_text
	key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_lbl.add_theme_font_size_override("font_size", 14)
	key_lbl.add_theme_color_override("font_color", Color(0.12, 0.36, 0.62, 1.0))
	key_badge.add_child(key_lbl)

	var action_lbl := Label.new()
	action_lbl.text = action_text
	action_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	action_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_lbl.add_theme_font_size_override("font_size", 15)
	action_lbl.add_theme_color_override("font_color", Color(0.16, 0.32, 0.50, 1.0))
	hbox.add_child(action_lbl)

	return row_panel


func _show_status(text_msg: String) -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = text_msg
	if is_instance_valid(_status_tween):
		_status_tween.kill()

	_status_lbl.modulate.a = 0.0
	_status_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_status_tween.tween_property(_status_lbl, "modulate:a", 1.0, 0.18)
	_status_tween.tween_interval(2.2)
	_status_tween.tween_property(_status_lbl, "modulate:a", 0.0, 0.35)


func _refresh_options_ui() -> void:
	var mode := GameManager.get_screen_mode()
	_apply_mode_button_style(_fullscreen_button, mode == GameManager.ScreenMode.FULLSCREEN)
	_apply_mode_button_style(_windowed_button, mode == GameManager.ScreenMode.WINDOWED)
	_apply_mode_button_style(_borderless_button, mode == GameManager.ScreenMode.BORDERLESS_FULLSCREEN)

	var vol := GameManager.get_master_volume()
	if not _volume_slider.has_focus():
		_volume_slider.value = vol
	_volume_value_lbl.text = "%d%%" % int(round(vol * 100.0))


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
	btn.custom_minimum_size = Vector2(0, 56)
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 21)
	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", hover_text_col)
	btn.add_theme_color_override("font_focus_color", hover_text_col)
	btn.add_theme_color_override("font_pressed_color", hover_text_col)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = bevel
	normal.border_width_left = 3
	normal.border_width_top = 3
	normal.border_width_right = 3
	normal.border_width_bottom = 7
	normal.corner_radius_top_left = 14
	normal.corner_radius_top_right = 14
	normal.corner_radius_bottom_left = 14
	normal.corner_radius_bottom_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 12

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_bg
	if hover_bevel.a > 0.0:
		hover.border_color = hover_bevel
	hover.border_width_bottom = 8

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = hover_bg.darkened(0.08)
	pressed.border_width_bottom = 4
	pressed.content_margin_top = 12
	pressed.content_margin_bottom = 8

	var focus := hover.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.11, 0.24, 0.40, 1.0)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)

	btn.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
	)
	btn.mouse_entered.connect(func() -> void:
		if not btn.disabled:
			AudioManager.play_ui_hover()
	)
	return btn


func _create_mode_button(label_text: String, mode: GameManager.ScreenMode) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, 44)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
		GameManager.set_screen_mode(mode)
		_refresh_options_ui()
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
	var hover_txt := Color.WHITE

	btn.add_theme_color_override("font_color", txt_col)
	btn.add_theme_color_override("font_hover_color", hover_txt)
	btn.add_theme_color_override("font_pressed_color", hover_txt)

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_color = bevel
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 5
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 8

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_bg
	hover.border_width_bottom = 6

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.border_width_bottom = 3

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
