class_name LevelHUD
extends CanvasLayer

signal pause_requested()

const SAVE_INDICATOR_DURATION := 1.5

var _fade_overlay: ColorRect
var _souls_banner: Control
var _souls_backdrop: _SoulsBannerBackdrop
var _souls_title_lbl: Label
var _souls_sub_lbl: Label
var _level_small_lbl: Label
var _pause_button: Button
var _save_badge: PanelContainer
var _save_spinner: _SaveSpinnerIcon
var _save_tween: Tween
var _intro_tween: Tween


class _SaveSpinnerIcon extends Control:
	var angle := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		angle = fmod(angle + delta * 6.2, TAU)
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.36
		draw_arc(center, radius, 0.0, TAU, 24, Color(0.56, 0.80, 0.96, 0.25), 2.4, true)
		draw_arc(center, radius, angle, angle + PI * 1.3, 20, Color(0.45, 0.86, 1.0, 0.98), 2.8, true)
		draw_circle(center, 2.2, Color(0.92, 0.98, 1.0, 0.95))


class _SoulsBannerBackdrop extends Control:
	var line_expand := 1.0:
		set(val):
			line_expand = clampf(val, 0.0, 1.0)
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 1.0 or h <= 1.0:
			return

		# Banda horizontal degradada estilo Dark Souls / Elden Ring
		var band_w := w * 0.68
		var left_x := (w - band_w) * 0.5
		var right_x := left_x + band_w
		var mid_x := w * 0.5
		var edge_fade := band_w * 0.28

		var bg_col := Color(0.02, 0.06, 0.12, 0.72)
		var bg_clear := Color(0.02, 0.06, 0.12, 0.0)

		# Tramo izquierdo degradado
		var pts_left := PackedVector2Array([
			Vector2(left_x, 0),
			Vector2(left_x + edge_fade, 0),
			Vector2(left_x + edge_fade, h),
			Vector2(left_x, h)
		])
		var cols_left := PackedColorArray([bg_clear, bg_col, bg_col, bg_clear])
		draw_polygon(pts_left, cols_left)

		# Tramo central sólido traslúcido
		draw_rect(Rect2(left_x + edge_fade, 0, band_w - edge_fade * 2.0, h), bg_col)

		# Tramo derecho degradado
		var pts_right := PackedVector2Array([
			Vector2(right_x - edge_fade, 0),
			Vector2(right_x, 0),
			Vector2(right_x, h),
			Vector2(right_x - edge_fade, h)
		])
		var cols_right := PackedColorArray([bg_col, bg_clear, bg_clear, bg_col])
		draw_polygon(pts_right, cols_right)

		# Líneas horizontales finas arriba y abajo con expansión suave
		var line_half := (band_w * 0.36) * line_expand
		if line_half > 2.0:
			var line_col := Color(0.76, 0.90, 1.0, 0.82)
			var top_y := 6.0
			var bot_y := h - 6.0
			draw_line(Vector2(mid_x - line_half, top_y), Vector2(mid_x + line_half, top_y), line_col, 1.5, true)
			draw_line(Vector2(mid_x - line_half, bot_y), Vector2(mid_x + line_half, bot_y), line_col, 1.5, true)

			# Pequeño rombo central decorativo en la línea superior e inferior
			var d := 3.5
			var diamond_top := PackedVector2Array([
				Vector2(mid_x, top_y - d),
				Vector2(mid_x + d, top_y),
				Vector2(mid_x, top_y + d),
				Vector2(mid_x - d, top_y)
			])
			var diamond_bot := PackedVector2Array([
				Vector2(mid_x, bot_y - d),
				Vector2(mid_x + d, bot_y),
				Vector2(mid_x, bot_y + d),
				Vector2(mid_x - d, bot_y)
			])
			draw_colored_polygon(diamond_top, Color(0.92, 0.97, 1.0, 0.95))
			draw_colored_polygon(diamond_bot, Color(0.92, 0.97, 1.0, 0.95))


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func setup_for_level(level_path: String, play_intro: bool = true) -> void:
	if _souls_title_lbl == null:
		_build_ui()
	var label_text := GameManager.format_level_name(level_path)
	_level_small_lbl.text = label_text
	_souls_title_lbl.text = label_text.to_upper()
	if play_intro:
		play_level_transition()
		show_save_indicator(SAVE_INDICATOR_DURATION)


func play_level_transition() -> void:
	if _fade_overlay == null or _souls_banner == null:
		return
	if is_instance_valid(_intro_tween):
		_intro_tween.kill()

	_fade_overlay.visible = true
	_fade_overlay.modulate.a = 0.82

	_souls_banner.visible = true
	_souls_banner.modulate.a = 0.0
	_souls_banner.scale = Vector2(0.96, 0.96)
	_souls_banner.pivot_offset = _souls_banner.size * 0.5
	_souls_backdrop.line_expand = 0.15

	_intro_tween = create_tween()
	if _intro_tween == null:
		_fade_overlay.visible = false
		_souls_banner.visible = false
		return

	# 1. Fade-in suave de la pantalla al entrar al nivel
	_intro_tween.tween_property(_fade_overlay, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_intro_tween.parallel().tween_property(_souls_banner, "modulate:a", 1.0, 0.55).set_delay(0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_intro_tween.parallel().tween_property(_souls_backdrop, "line_expand", 1.0, 0.75).set_delay(0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro_tween.parallel().tween_property(_souls_banner, "scale", Vector2(1.02, 1.02), 2.1).set_delay(0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# 2. Desvanecer el cartel estilo Souls luego de mostrar la zona
	_intro_tween.tween_property(_souls_banner, "modulate:a", 0.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_intro_tween.tween_callback(func() -> void:
		_fade_overlay.visible = false
		_souls_banner.visible = false
	)


func show_save_indicator(duration: float = SAVE_INDICATOR_DURATION) -> void:
	if _save_badge == null:
		return
	if is_instance_valid(_save_tween):
		_save_tween.kill()

	_save_badge.visible = true
	_save_badge.modulate.a = 0.0

	var fade_in_time := 0.15
	var fade_out_time := 0.25
	var hold_time := maxf(0.1, duration - fade_in_time - fade_out_time)

	_save_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if _save_tween == null:
		return
	_save_tween.tween_property(_save_badge, "modulate:a", 1.0, fade_in_time)
	_save_tween.tween_interval(hold_time)
	_save_tween.tween_property(_save_badge, "modulate:a", 0.0, fade_out_time)
	_save_tween.tween_callback(func() -> void:
		_save_badge.visible = false
	)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 1. Esquina inferior izquierda: indicador pequeño permanente del nivel actual
	var bl_margin := MarginContainer.new()
	bl_margin.name = "BottomLeftMargin"
	bl_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl_margin.grow_horizontal = Control.GROW_DIRECTION_END
	bl_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl_margin.add_theme_constant_override("margin_left", 20)
	bl_margin.add_theme_constant_override("margin_bottom", 18)
	bl_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bl_margin)

	var level_pill := PanelContainer.new()
	level_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0.08, 0.18, 0.30, 0.72)
	pill_style.border_color = Color(0.56, 0.80, 0.96, 0.75)
	pill_style.border_width_left = 2
	pill_style.border_width_top = 2
	pill_style.border_width_right = 2
	pill_style.border_width_bottom = 3
	pill_style.corner_radius_top_left = 10
	pill_style.corner_radius_top_right = 10
	pill_style.corner_radius_bottom_left = 10
	pill_style.corner_radius_bottom_right = 10
	pill_style.content_margin_left = 12
	pill_style.content_margin_right = 12
	pill_style.content_margin_top = 4
	pill_style.content_margin_bottom = 5
	level_pill.add_theme_stylebox_override("panel", pill_style)
	bl_margin.add_child(level_pill)

	_level_small_lbl = Label.new()
	_level_small_lbl.name = "LevelSmallLabel"
	_level_small_lbl.text = "Nivel 1"
	_level_small_lbl.add_theme_font_size_override("font_size", 14)
	_level_small_lbl.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0, 0.95))
	_level_small_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_pill.add_child(_level_small_lbl)

	# 2. Esquina inferior derecha: símbolo de carga/guardado (dura 1.5s)
	var br_margin := MarginContainer.new()
	br_margin.name = "BottomRightMargin"
	br_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	br_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br_margin.add_theme_constant_override("margin_right", 20)
	br_margin.add_theme_constant_override("margin_bottom", 18)
	br_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(br_margin)

	_save_badge = PanelContainer.new()
	_save_badge.name = "SaveIndicator"
	_save_badge.visible = false
	_save_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var save_style := pill_style.duplicate() as StyleBoxFlat
	save_style.bg_color = Color(0.08, 0.18, 0.30, 0.84)
	save_style.content_margin_left = 10
	save_style.content_margin_right = 12
	save_style.content_margin_top = 5
	save_style.content_margin_bottom = 6
	_save_badge.add_theme_stylebox_override("panel", save_style)
	br_margin.add_child(_save_badge)

	var save_hbox := HBoxContainer.new()
	save_hbox.add_theme_constant_override("separation", 8)
	save_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_badge.add_child(save_hbox)

	_save_spinner = _SaveSpinnerIcon.new()
	save_hbox.add_child(_save_spinner)

	var save_lbl := Label.new()
	save_lbl.text = "Guardado"
	save_lbl.add_theme_font_size_override("font_size", 13)
	save_lbl.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 0.95))
	save_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_hbox.add_child(save_lbl)

	# 3. Esquina superior derecha: botón pequeño clickeable de pausa
	var tr_margin := MarginContainer.new()
	tr_margin.name = "TopRightMargin"
	tr_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr_margin.grow_vertical = Control.GROW_DIRECTION_END
	tr_margin.add_theme_constant_override("margin_right", 20)
	tr_margin.add_theme_constant_override("margin_top", 18)
	tr_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(tr_margin)

	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.text = "❚❚"
	_pause_button.tooltip_text = "Pausa (Esc)"
	_pause_button.custom_minimum_size = Vector2(42, 42)
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pause_button.add_theme_font_size_override("font_size", 16)
	_pause_button.add_theme_color_override("font_color", Color(0.14, 0.34, 0.54, 1.0))
	_pause_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_pause_button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var p_normal := StyleBoxFlat.new()
	p_normal.bg_color = Color(0.95, 0.98, 1.0, 0.92)
	p_normal.border_color = Color(0.56, 0.80, 0.96, 1.0)
	p_normal.border_width_left = 2
	p_normal.border_width_top = 2
	p_normal.border_width_right = 2
	p_normal.border_width_bottom = 5
	p_normal.corner_radius_top_left = 11
	p_normal.corner_radius_top_right = 11
	p_normal.corner_radius_bottom_left = 11
	p_normal.corner_radius_bottom_right = 11

	var p_hover := p_normal.duplicate() as StyleBoxFlat
	p_hover.bg_color = Color(0.14, 0.44, 0.72, 1.0)
	p_hover.border_color = Color(0.08, 0.30, 0.54, 1.0)

	var p_pressed := p_hover.duplicate() as StyleBoxFlat
	p_pressed.bg_color = Color(0.10, 0.36, 0.60, 1.0)
	p_pressed.border_width_bottom = 2

	_pause_button.add_theme_stylebox_override("normal", p_normal)
	_pause_button.add_theme_stylebox_override("hover", p_hover)
	_pause_button.add_theme_stylebox_override("pressed", p_pressed)

	_pause_button.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
		pause_requested.emit()
	)
	_pause_button.mouse_entered.connect(func() -> void:
		AudioManager.play_ui_hover()
	)
	tr_margin.add_child(_pause_button)

	# 4. Cartel central estilo Dark Souls al entrar a un nivel
	_souls_banner = Control.new()
	_souls_banner.name = "SoulsBanner"
	_souls_banner.visible = false
	_souls_banner.anchor_left = 0.0
	_souls_banner.anchor_right = 1.0
	_souls_banner.anchor_top = 0.24
	_souls_banner.anchor_bottom = 0.38
	_souls_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_souls_banner)

	_souls_backdrop = _SoulsBannerBackdrop.new()
	_souls_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_souls_banner.add_child(_souls_backdrop)

	var banner_center := CenterContainer.new()
	banner_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_souls_banner.add_child(banner_center)

	var banner_vbox := VBoxContainer.new()
	banner_vbox.add_theme_constant_override("separation", 2)
	banner_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_center.add_child(banner_vbox)

	_souls_sub_lbl = Label.new()
	_souls_sub_lbl.text = "THE GRAMM-SMIDTH PROJECT"
	_souls_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_souls_sub_lbl.add_theme_font_size_override("font_size", 12)
	_souls_sub_lbl.add_theme_color_override("font_color", Color(0.68, 0.84, 0.96, 0.85))
	_souls_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_vbox.add_child(_souls_sub_lbl)

	_souls_title_lbl = Label.new()
	_souls_title_lbl.name = "SoulsTitleLabel"
	_souls_title_lbl.text = "NIVEL 1"
	_souls_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_souls_title_lbl.add_theme_font_size_override("font_size", 38)
	_souls_title_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	_souls_title_lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.10, 0.20, 0.9))
	_souls_title_lbl.add_theme_constant_override("outline_size", 4)
	_souls_title_lbl.add_theme_color_override("font_shadow_color", Color(0.02, 0.05, 0.12, 0.85))
	_souls_title_lbl.add_theme_constant_override("shadow_offset_x", 0)
	_souls_title_lbl.add_theme_constant_override("shadow_offset_y", 3)
	_souls_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_vbox.add_child(_souls_title_lbl)

	# 5. Capa de Fade-In suave a pantalla completa al cambiar de nivel
	_fade_overlay = ColorRect.new()
	_fade_overlay.name = "FadeOverlay"
	_fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.color = Color(0.03, 0.06, 0.12, 1.0)
	_fade_overlay.visible = false
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade_overlay)
