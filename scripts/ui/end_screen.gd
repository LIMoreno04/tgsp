class_name EndScreen
extends CanvasLayer
## El final del juego: una tarjeta que agradece, los créditos y un botón que vuelve al menú.
## Al entrar al árbol pausa el juego, así el nivel queda quieto detrás.

const TITLE := "¡Gracias por jugar!"
const GAME_NAME := "The Gram-Schmidt Project"
## Cada crédito: el rol y el nombre.
const CREDITS: Array[Array] = [
	["Programador principal", "Ignacio Moreno"],
	["Artista 3D principal", "Lautaro Gelpes"],
	["Diseñador de puzzles y niveles", "Jerónimo De León"],
]
const BACK_TO_MENU := "Volver al menú"

const TEXT_COLOUR := Color(0.16, 0.32, 0.50)
const TITLE_COLOUR := Color(0.12, 0.44, 0.72)
const ROLE_COLOUR := Color(0.24, 0.50, 0.74)
const BUTTON_COLOUR := Color(0.38, 0.76, 0.96)
const BUTTON_HOVER_COLOUR := Color(0.14, 0.44, 0.72)
const BUTTON_BORDER_COLOUR := Color(0.18, 0.54, 0.78)

var menu_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110 # Por encima del menú de pausa.
	_build()
	get_tree().paused = true
	menu_button.grab_focus.call_deferred()


func go_to_the_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GameManager.MAIN_MENU_PATH)


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.14, 0.24, 0.62)
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	card.add_theme_stylebox_override("panel", _card_style())
	centre.add_child(card)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	card.add_child(lines)

	lines.add_child(_label(TITLE, 34, TITLE_COLOUR))
	lines.add_child(_label(GAME_NAME, 16, ROLE_COLOUR))
	lines.add_child(_gap(18))
	for credit in CREDITS:
		lines.add_child(_label(credit[0], 14, ROLE_COLOUR))
		lines.add_child(_label(credit[1], 22, TEXT_COLOUR))
		lines.add_child(_gap(8))
	lines.add_child(_gap(10))

	menu_button = Button.new()
	menu_button.text = BACK_TO_MENU
	menu_button.custom_minimum_size = Vector2(0, 56)
	menu_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	menu_button.add_theme_font_size_override("font_size", 21)
	for colour_name in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		menu_button.add_theme_color_override(colour_name, Color.WHITE)
	menu_button.add_theme_stylebox_override("normal", _button_style(BUTTON_COLOUR))
	for state in ["hover", "pressed", "focus"]:
		menu_button.add_theme_stylebox_override(state, _button_style(BUTTON_HOVER_COLOUR))
	menu_button.pressed.connect(func() -> void:
		AudioManager.play_ui_click()
		go_to_the_menu()
	)
	lines.add_child(menu_button)


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	return gap


## La misma tarjeta que el menú de pausa.
func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.98, 1.0, 0.96)
	style.border_color = Color(0.56, 0.80, 0.96)
	style.set_border_width_all(4)
	style.border_width_bottom = 12
	style.set_corner_radius_all(22)
	style.shadow_color = Color(0.08, 0.20, 0.35, 0.35)
	style.shadow_size = 28
	style.shadow_offset = Vector2(0, 10)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 32
	return style

func _button_style(colour: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = BUTTON_BORDER_COLOUR
	style.set_border_width_all(3)
	style.border_width_bottom = 7
	style.set_corner_radius_all(14)
	style.content_margin_top = 8
	style.content_margin_bottom = 12
	return style
