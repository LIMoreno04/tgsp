@tool
class_name LevelEditorIcons
extends RefCounted
## Los íconos de la paleta, como SVG escritos acá: no dependen del tema del editor, así sirven también
## fuera de él. Los tipos de caja son cubitos con los colores con que se dibujan en el juego.

## Grises claros: los íconos van sobre los botones oscuros del editor.
const GREY := "#8a8a93"
const DARK := "#5f5f67"
const WHITE := "#efefeb"
const ORANGE := "#d9731a"
const ORANGE_DARK := "#a8560f"
const RED := "#e0392b"
const GREEN := "#27ad4d"
const LINE := "#d8d8d8"

static var _cache: Dictionary[String, Texture2D] = {}


static func get_icon(icon_name: String, scale := 1.0) -> Texture2D:
	var key := "%s@%s" % [icon_name, scale]
	if _cache.has(key):
		return _cache[key]
	var image := Image.new()
	if image.load_svg_from_string(_svg(icon_name), scale) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func _svg(icon_name: String) -> String:
	var body := ""
	match icon_name:
		"Floor": body = _cube(WHITE, GREY, DARK) + _tile_lines()
		"Wall": body = _cube(WHITE, WHITE, "#cfcfcb") + _wall_lines()
		"Block": body = _cube("#b4b4bc", GREY, DARK)
		"Walkable": body = _cube(WHITE, GREY, DARK)
		"Movable": body = _cube(ORANGE, ORANGE, ORANGE_DARK)
		"3D movable": body = _cube(GREY, ORANGE, ORANGE_DARK)
		"2D movable": body = _cube(ORANGE, GREY, DARK)
		"Hanging platform": body = _half_cube(WHITE, GREY, DARK) + '<line x1="2" y1="3" x2="2" y2="13" stroke="%s" stroke-width="1.5"/>' % LINE
		"Wire": body = '<path d="M3 13 L3 8 L13 8 L13 3" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="1.5 2" stroke-linecap="round"/>' % RED
		"Button": body = '<rect x="4" y="8" width="8" height="6" fill="#8c8c92"/><rect x="6" y="5" width="4" height="3" rx="1" fill="%s"/>' % RED
		"Plate": body = '<path d="M1 11 L8 7.5 L15 11 L8 14.5 Z" fill="#8c8c92"/><path d="M4 11 L8 9 L12 11 L8 13 Z" fill="%s"/>' % RED
		"Door": body = '<rect x="5" y="2" width="6" height="12" fill="%s" stroke="%s" stroke-width="1"/>' % [DARK, LINE]
		"Exit": body = '<rect x="5" y="2" width="6" height="12" fill="%s"/>' % GREEN
		"Laser emitter": body = '<rect x="2" y="5" width="6" height="6" fill="#8c8c92"/><circle cx="8" cy="8" r="2" fill="%s"/><line x1="9" y1="8" x2="15" y2="8" stroke="%s" stroke-width="1.5" stroke-dasharray="2 1.5"/>' % [RED, RED]
		"Laser receiver": body = '<rect x="5" y="3" width="8" height="10" fill="#8c8c92"/><circle cx="9" cy="8" r="3" fill="%s"/><circle cx="9" cy="8" r="1.2" fill="#8c8c92"/>' % RED
		"Select": body = '<path d="M3 2 L3 13 L6 10 L8.5 14.5 L10.5 13.5 L8 9 L12 9 Z" fill="%s"/>' % LINE
		"Pick": body = '<path d="M10 2 L14 6 L12 8 L6 14 L2 14 L2 10 L8 4 Z" fill="none" stroke="%s" stroke-width="1.5"/><path d="M3 13 L3 11 L8 6" stroke="%s" stroke-width="1.5"/>' % [LINE, LINE]
		"Repaint": body = '<rect x="2" y="2" width="10" height="5" rx="1" fill="%s"/><path d="M12 4.5 L14 4.5 L14 9 L8 9 L8 11" fill="none" stroke="%s" stroke-width="1.5"/><rect x="6.5" y="11" width="3" height="4" fill="%s"/>' % [ORANGE, LINE, LINE]
		"Eraser": body = '<path d="M9 2 L14 7 L7 14 L3 14 L1 12 Z" fill="%s"/><path d="M5 6 L10 11" stroke="%s" stroke-width="1.5"/>' % [LINE, DARK]
		"Handles": body = _cube(GREY, ORANGE, DARK) + '<path d="M8 1.5 L14.5 4.8 L8 8 L1.5 4.8 Z" fill="none" stroke="%s" stroke-width="1.5"/>' % ORANGE
		"Spawn": body = '<rect x="5" y="4" width="6" height="10" fill="#3f8cf2"/><rect x="6.5" y="2" width="3" height="3" fill="#f2d84d"/>'
		"TurnLeft": body = '<path d="M12.5 11 A5 5 0 1 0 4.5 4.2" fill="none" stroke="%s" stroke-width="1.6"/><path d="M2.5 2 L5.2 5.6 L1.6 6.4 Z" fill="%s"/>' % [LINE, LINE]
		"TurnRight": body = '<path d="M3.5 11 A5 5 0 1 1 11.5 4.2" fill="none" stroke="%s" stroke-width="1.6"/><path d="M13.5 2 L10.8 5.6 L14.4 6.4 Z" fill="%s"/>' % [LINE, LINE]
		"Eye": body = '<path d="M1 8 Q8 1 15 8 Q8 15 1 8 Z" fill="none" stroke="%s" stroke-width="1.4"/><circle cx="8" cy="8" r="2.4" fill="%s"/>' % [LINE, LINE]
		"EyeClosed": body = '<path d="M1 8 Q8 14 15 8" fill="none" stroke="%s" stroke-width="1.4"/><path d="M3 10 L2 12 M8 11.5 L8 13.5 M13 10 L14 12" stroke="%s" stroke-width="1.2"/>' % [LINE, LINE]
		_: body = '<circle cx="8" cy="8" r="5" fill="%s"/>' % LINE
	return '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">%s</svg>' % body


## Un cubo visto desde arriba en una esquina: la tapa, el lado izquierdo y el derecho.
static func _cube(top: String, left: String, right: String) -> String:
	return ('<path d="M8 1.5 L14.5 4.8 L8 8 L1.5 4.8 Z" fill="%s"/>' % top
		+ '<path d="M1.5 4.8 L8 8 L8 14.5 L1.5 11.2 Z" fill="%s"/>' % left
		+ '<path d="M8 8 L14.5 4.8 L14.5 11.2 L8 14.5 Z" fill="%s"/>' % right)


static func _half_cube(top: String, left: String, right: String) -> String:
	return ('<path d="M8 4.5 L14.5 7.8 L8 11 L1.5 7.8 Z" fill="%s"/>' % top
		+ '<path d="M1.5 7.8 L8 11 L8 14.5 L1.5 11.2 Z" fill="%s"/>' % left
		+ '<path d="M8 11 L14.5 7.8 L14.5 11.2 L8 14.5 Z" fill="%s"/>' % right)


static func _tile_lines() -> String:
	return '<path d="M4.75 3.15 L11.25 6.4 M11.25 3.15 L4.75 6.4" stroke="#9e9e9a" stroke-width="0.6"/>'


static func _wall_lines() -> String:
	return '<path d="M1.5 8 L8 11.2 M8 11.2 L14.5 8 M4.75 6.4 L4.75 12.8 M11.25 6.4 L11.25 12.8" stroke="#9e9e9a" stroke-width="0.6"/>'
