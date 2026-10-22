@tool
class_name EditorHistory
extends LevelEditorHistory
## La historia del editor de niveles dentro de Godot: cada acción va a la historia de la escena del
## nivel, la misma del Inspector y del dock de escena, así que Ctrl + Z deshace todo junto.

var _manager: EditorUndoRedoManager
var _level_root: Node
var _scene_history: UndoRedo


func _init(manager: EditorUndoRedoManager, level_root: Node) -> void:
	_manager = manager
	_level_root = level_root
	_manager.version_changed.connect(changed.emit)
	_manager.history_changed.connect(changed.emit)
	# Lo que se deshace directo en la historia de la escena no pasa por el manager.
	_scene_history = _manager.get_history_undo_redo(_manager.get_object_history_id(_level_root))
	_scene_history.version_changed.connect(changed.emit)


func create_action(action_name: String, merge_with_the_last := false) -> void:
	_manager.create_action(action_name, UndoRedo.MERGE_ENDS if merge_with_the_last else UndoRedo.MERGE_DISABLE, _level_root)

## EditorUndoRedoManager no toma Callables: quiere el objeto, el nombre del método y los argumentos.
func add_do_method(callable: Callable) -> void:
	_manager.callv(&"add_do_method", [callable.get_object(), callable.get_method()] + callable.get_bound_arguments())

func add_undo_method(callable: Callable) -> void:
	_manager.callv(&"add_undo_method", [callable.get_object(), callable.get_method()] + callable.get_bound_arguments())

func add_do_property(object: Object, property: StringName, value: Variant) -> void:
	_manager.add_do_property(object, property, value)

func add_undo_property(object: Object, property: StringName, value: Variant) -> void:
	_manager.add_undo_property(object, property, value)

func add_do_reference(object: Object) -> void:
	_manager.add_do_reference(object)

func add_undo_reference(object: Object) -> void:
	_manager.add_undo_reference(object)

func commit_action() -> void:
	_manager.commit_action()


func undo() -> bool:
	return _scene_history.undo()

func redo() -> bool:
	return _scene_history.redo()


func disconnect_from_the_editor() -> void:
	if _manager.version_changed.is_connected(changed.emit):
		_manager.version_changed.disconnect(changed.emit)
	if _manager.history_changed.is_connected(changed.emit):
		_manager.history_changed.disconnect(changed.emit)
	if is_instance_valid(_scene_history) and _scene_history.version_changed.is_connected(changed.emit):
		_scene_history.version_changed.disconnect(changed.emit)
