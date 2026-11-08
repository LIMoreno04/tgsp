class_name GameManager
extends RefCounted

enum ScreenMode {
	WINDOWED = 0,
	BORDERLESS_FULLSCREEN = 1,
	FULLSCREEN = 2,
}

const SAVE_PATH := "user://savegame.cfg"
const SETTINGS_PATH := "user://settings.cfg"
const FIRST_LEVEL_PATH := "res://scenes/levels/level_01.tscn"
const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"

static var _settings_initialized := false
static var _pending_restore_level := ""


static func ensure_settings_loaded() -> void:
	if _settings_initialized:
		return
	_settings_initialized = true
	var mode := get_screen_mode()
	var volume := get_master_volume()
	_apply_screen_mode(mode)
	_apply_master_volume(volume)


static func has_save() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	var level_path := str(cfg.get_value("save", "level_path", ""))
	return not level_path.is_empty() and ResourceLoader.exists(level_path)


static func get_saved_level_path() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return ""
	return str(cfg.get_value("save", "level_path", ""))


static func get_saved_level_label() -> String:
	var path := get_saved_level_path()
	if path.is_empty():
		return ""
	var file := path.get_file().get_basename()
	if file.begins_with("level_"):
		var num := file.trim_prefix("level_").to_int()
		if num > 0:
			return "Nivel %d" % num
	return file.capitalize()


static func start_new_game(tree: SceneTree) -> void:
	_pending_restore_level = ""
	save_clean_level(FIRST_LEVEL_PATH)
	tree.change_scene_to_file(FIRST_LEVEL_PATH)


static func load_saved_game(tree: SceneTree) -> void:
	if not has_save():
		return
	var level_path := get_saved_level_path()
	_pending_restore_level = level_path
	tree.change_scene_to_file(level_path)


static func save_clean_level(level_path: String) -> void:
	if level_path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("save", "level_path", level_path)
	cfg.set_value("save", "has_mid_level_state", false)
	cfg.save(SAVE_PATH)


static func save_level_state(level: Level) -> void:
	if level == null or level.scene_file_path.is_empty():
		return
	if not is_instance_valid(level.room) or not is_instance_valid(level.player):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("save", "level_path", level.scene_file_path)
	cfg.set_value("save", "has_mid_level_state", true)
	cfg.set_value("state", "perspective", int(level.room.perspective_manager.current))
	cfg.set_value("state", "height", level.room.perspective_manager.height)
	cfg.set_value("state", "player_cell", level.player.cell())
	cfg.set_value("state", "facing", level.player.facing)

	var box_cells: Dictionary = {}
	for box: Box in level.room.box_cells():
		box_cells[str(level.room.get_path_to(box))] = box.cell
	cfg.set_value("state", "box_cells", box_cells)

	var button_states: Dictionary = {}
	for button: ButtonPowerable in level.room.button_states():
		button_states[str(level.room.get_path_to(button))] = button.switched_on
	cfg.set_value("state", "button_states", button_states)

	var powerables_on: Dictionary = {}
	for powerable: Powerable in level.room.powerables_displayed_as_on():
		powerables_on[str(level.room.get_path_to(powerable))] = true
	cfg.set_value("state", "powerables_on", powerables_on)

	cfg.save(SAVE_PATH)


static func consume_restore_request(level_path: String) -> bool:
	if _pending_restore_level == level_path and not level_path.is_empty():
		_pending_restore_level = ""
		return true
	return false


static func restore_level_state(level: Level) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if str(cfg.get_value("save", "level_path", "")) != level.scene_file_path:
		return
	if not bool(cfg.get_value("save", "has_mid_level_state", false)):
		return

	var room := level.room
	var saved_box_paths: Dictionary = cfg.get_value("state", "box_cells", {})
	var saved_button_paths: Dictionary = cfg.get_value("state", "button_states", {})
	var saved_power_paths: Dictionary = cfg.get_value("state", "powerables_on", {})

	var box_cells: Dictionary[Box, Vector3i] = {}
	for path_str: String in saved_box_paths:
		var box := room.get_node_or_null(NodePath(path_str)) as Box
		if box != null:
			box_cells[box] = saved_box_paths[path_str]

	var button_states: Dictionary[ButtonPowerable, bool] = {}
	for path_str: String in saved_button_paths:
		var button := room.get_node_or_null(NodePath(path_str)) as ButtonPowerable
		if button != null:
			button_states[button] = bool(saved_button_paths[path_str])

	var powerables_on: Dictionary[Powerable, bool] = {}
	for path_str: String in saved_power_paths:
		var powerable := room.get_node_or_null(NodePath(path_str)) as Powerable
		if powerable != null:
			powerables_on[powerable] = true

	if not box_cells.is_empty():
		room.restore(box_cells, button_states, powerables_on)

	var perspective := int(cfg.get_value("state", "perspective", int(room.perspective_manager.current))) as Room.Perspective
	var height := int(cfg.get_value("state", "height", room.perspective_manager.height))
	room.perspective_manager.restore(perspective, height)

	var player_cell: Vector3i = cfg.get_value("state", "player_cell", level.player.cell())
	var facing: Vector2 = cfg.get_value("state", "facing", level.player.facing)
	level.player.restore(player_cell, facing, null)
	level.player._place_model()
	level.request_power_update()


static func get_screen_mode() -> ScreenMode:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ScreenMode.WINDOWED
	var mode := int(cfg.get_value("display", "screen_mode", int(ScreenMode.WINDOWED)))
	return clampi(mode, 0, 2) as ScreenMode


static func set_screen_mode(mode: ScreenMode) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "screen_mode", int(mode))
	cfg.save(SETTINGS_PATH)
	_apply_screen_mode(mode)


static func _apply_screen_mode(mode: ScreenMode) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match mode:
		ScreenMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		ScreenMode.BORDERLESS_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		ScreenMode.FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


static func get_master_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return 0.8
	return clampf(float(cfg.get_value("audio", "master_volume", 0.8)), 0.0, 1.0)


static func set_master_volume(volume: float) -> void:
	var clamped := clampf(volume, 0.0, 1.0)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "master_volume", clamped)
	cfg.save(SETTINGS_PATH)
	_apply_master_volume(clamped)


static func _apply_master_volume(volume: float) -> void:
	var bus_idx := 0
	if AudioServer.bus_count > 0:
		AudioServer.set_bus_mute(bus_idx, volume <= 0.001)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(volume, 0.0001)))

