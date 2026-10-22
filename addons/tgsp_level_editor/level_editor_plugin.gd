@tool
extends EditorPlugin
## El host de la pestaña Level dentro del editor de Godot: pone la pantalla, le da el nivel que se
## edita y la historia de su escena, y hace lo que sólo el editor puede hacer: guardar, jugar, abrir,
## crear un nivel, sincronizar la selección con el dock de escena, y devolver las sombras antes de
## guardar. Todo lo demás es del núcleo, que no sabe que existe el editor.

const TEMPLATE_PATH := "res://scenes/prefabs/level_template.tscn"
const SELF_TEST_ARGUMENT := "--level-editor-self-test"

var _screen: LevelEditorScreen
var _history: EditorHistory
var _syncing_selection := false
var _last_sent_to_the_editor: Array[Node] = []


func _enter_tree() -> void:
	_screen = LevelEditorScreen.new(EditorInterface.get_editor_scale())
	_screen.edit_state = PackedScene.GEN_EDIT_STATE_INSTANCE
	EditorInterface.get_editor_main_screen().add_child(_screen)
	_make_visible(false)
	scene_changed.connect(_on_scene_changed)
	_screen.play_requested.connect(_play)
	_screen.open_requested.connect(_open)
	_screen.new_level_requested.connect(_create_a_new_level)
	_screen.selection_changed.connect(_send_the_selection_to_the_editor)
	EditorInterface.get_selection().selection_changed.connect(_take_the_selection_from_the_editor)
	_on_scene_changed(EditorInterface.get_edited_scene_root())
	if OS.get_cmdline_user_args().has(SELF_TEST_ARGUMENT) or OS.get_cmdline_user_args().has("--level-editor-screenshots"):
		_run_the_self_test.call_deferred()


func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(_take_the_selection_from_the_editor):
		EditorInterface.get_selection().selection_changed.disconnect(_take_the_selection_from_the_editor)
	if _history != null:
		_history.disconnect_from_the_editor()
	_screen.view.restore_the_light()
	_screen.view.unhide_everything()
	_screen.queue_free()


func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "Level"

func _get_plugin_icon() -> Texture2D:
	return LevelEditorIcons.get_icon("Movable", EditorInterface.get_editor_scale())


## Al volver a la pestaña también se mira el nivel otra vez: la raíz pudo cambiar sin que cambie la escena.
func _make_visible(visible: bool) -> void:
	if _screen == null:
		return
	_screen.visible = visible
	_screen.view.preview.visible = visible
	_screen.view.overlay_3d.visible = visible
	if visible:
		var root := EditorInterface.get_edited_scene_root()
		if root != _screen.level_root:
			_on_scene_changed(root)
		# Lo que se eligió en el dock de escena mientras la pestaña no estaba se trae.
		_take_the_selection_from_the_editor.call_deferred()
		_screen.view.apply_hiding()
		_screen.view.hide_the_shadows_again_if_2d()
	else:
		_screen.view.restore_the_light()
		_screen.view.unhide_everything()


func _on_scene_changed(root: Node) -> void:
	if _history != null:
		_history.disconnect_from_the_editor()
		_history = null
	if not LevelEditorScreen.is_a_level(root):
		_screen.set_level(null, null)
		return
	_history = EditorHistory.new(get_undo_redo(), root)
	_screen.set_level(root, _history)
	if not _screen.visible:
		_screen.view.unhide_everything()


## Antes de guardar: las sombras vuelven a como estaban, así el cambio del 2D nunca se guarda.
func _apply_changes() -> void:
	if _screen == null:
		return
	_screen.view.restore_the_light()
	_screen.view.hide_the_shadows_again_if_2d.call_deferred()


func _get_state() -> Dictionary:
	if _screen == null or _screen.room == null:
		return {}
	var view := _screen.view
	return {"focus": view.focus, "yaw": view.yaw, "pitch": view.pitch, "size": view.view_size, "game_view": view.is_game_view}


func _set_state(state: Dictionary) -> void:
	if _screen == null or _screen.room == null or state.is_empty() or state.get("game_view", true):
		return
	var view := _screen.view
	view.focus = state.get("focus", view.focus)
	view.yaw = state.get("yaw", view.yaw)
	view.pitch = state.get("pitch", view.pitch)
	view.view_size = state.get("size", view.view_size)
	view.is_game_view = false
	view._place_free_camera()


#==================Lo que pide la pantalla==================

func _play() -> void:
	EditorInterface.save_scene()
	EditorInterface.play_current_scene()


func _open(path: String) -> void:
	EditorInterface.open_scene_from_path(path)
	EditorInterface.set_main_screen_editor("Level")


## Una copia de la plantilla con su propio UID, abierta, del tamaño pedido y con el jugador en el medio.
## Devuelve si quedó abierta.
func _create_a_new_level(path: String, dimensions: Vector3i) -> bool:
	var template := load(TEMPLATE_PATH) as PackedScene
	var instance := template.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	instance.scene_file_path = ""
	instance.name = path.get_file().get_basename().to_pascal_case()
	var packed := PackedScene.new()
	var packing := packed.pack(instance)
	instance.free()
	if packing != OK or ResourceSaver.save(packed, path) != OK:
		push_error("Couldn't create the level at %s." % path)
		return false
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	var root := await _the_open_scene_once_it_is(path)
	if root == null or not LevelEditorScreen.is_a_level(root):
		push_error("The new level at %s didn't open." % path)
		return false
	var room := root.get_node(^"Room") as Room
	room.dimensions = dimensions
	room.player_spawn_point = Vector3i(dimensions.x / 2, dimensions.y / 2, 0)
	EditorInterface.save_scene()
	EditorInterface.set_main_screen_editor("Level")
	_on_scene_changed(root)
	return true


## Abrir una escena puede tardar unos cuadros en la ventana del editor.
func _the_open_scene_once_it_is(path: String) -> Node:
	for frame in 600:
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path == path:
			return root
		await get_tree().process_frame
	return null


#==================La selección, de los dos lados==================

func _send_the_selection_to_the_editor() -> void:
	if _syncing_selection:
		return
	_syncing_selection = true
	var selection := EditorInterface.get_selection()
	selection.clear()
	_last_sent_to_the_editor = _screen.selection_for_the_editor()
	for node in _last_sent_to_the_editor:
		selection.add_node(node)
	_syncing_selection = false


func _take_the_selection_from_the_editor() -> void:
	if _syncing_selection or _screen == null or not _screen.visible:
		return
	var nodes: Array[Node] = []
	nodes.assign(EditorInterface.get_selection().get_selected_nodes())
	if _same_nodes(nodes, _last_sent_to_the_editor):
		return
	_syncing_selection = true
	_screen.select_from_editor(nodes)
	_syncing_selection = false


static func _same_nodes(a: Array[Node], b: Array[Node]) -> bool:
	if a.size() != b.size():
		return false
	for node in a:
		if not b.has(node):
			return false
	return true


#==================La prueba de sí mismo==================

func _run_the_self_test() -> void:
	var test_script := load("res://addons/tgsp_level_editor/tests/self_test.gd") as Script
	var test: Object = test_script.new()
	var failures: int = await test.call(&"run", self, _screen)
	EditorInterface.get_base_control().get_tree().quit(1 if failures > 0 else 0)
