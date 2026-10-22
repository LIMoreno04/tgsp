@tool
class_name LevelEditorHistory
extends RefCounted
## Donde el editor de niveles anota cada cambio para poder deshacerlo. Tiene la forma del UndoRedo de
## Godot y usa uno común; dentro del editor, el host le pone EditorHistory, que manda todo a la
## historia de la escena.

## Después de cada acción, deshacer o rehacer, venga de donde venga.
signal changed

var _undo_redo := UndoRedo.new()


func _init() -> void:
	_undo_redo.version_changed.connect(changed.emit)


func create_action(action_name: String, merge_with_the_last := false) -> void:
	_undo_redo.create_action(action_name, UndoRedo.MERGE_ENDS if merge_with_the_last else UndoRedo.MERGE_DISABLE)

func add_do_method(callable: Callable) -> void:
	_undo_redo.add_do_method(callable)

func add_undo_method(callable: Callable) -> void:
	_undo_redo.add_undo_method(callable)

func add_do_property(object: Object, property: StringName, value: Variant) -> void:
	_undo_redo.add_do_property(object, property, value)

func add_undo_property(object: Object, property: StringName, value: Variant) -> void:
	_undo_redo.add_undo_property(object, property, value)

func add_do_reference(object: Object) -> void:
	_undo_redo.add_do_reference(object)

func add_undo_reference(object: Object) -> void:
	_undo_redo.add_undo_reference(object)

func commit_action() -> void:
	_undo_redo.commit_action()


func undo() -> bool:
	return _undo_redo.undo()

func redo() -> bool:
	return _undo_redo.redo()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_undo_redo):
		_undo_redo.free()
