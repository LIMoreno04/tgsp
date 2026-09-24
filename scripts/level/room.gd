@tool
class_name Room
extends Node3D


#==================General=====================
@export var dimensions:Vector3i = Vector3i(5,5,5)
@export var camera: ProjectiveCamera
@export var camera_distance: float = 10.0

#===============Perspectiva==================
enum Perspective {ISO_3D, TOP_2D}
signal perspective_changed(new_perspective: Perspective)

var current_perspective: Perspective = Perspective.ISO_3D
var is_perspective_locked := false
var blocking_perspective_semaphore := []

func is_3d() -> bool:
    return current_perspective == Perspective.ISO_3D

func is_2d() -> bool:
    return current_perspective == Perspective.TOP_2D

func block_perspective(caller_process: Node) -> void:
    if caller_process in blocking_perspective_semaphore:
        return
    if not is_perspective_locked:
        is_perspective_locked = true
    blocking_perspective_semaphore.append(caller_process)

func unblock_perspective(caller_process: Node) -> void:
    if caller_process in blocking_perspective_semaphore:
        blocking_perspective_semaphore.erase(caller_process)
    if blocking_perspective_semaphore.is_empty():
        is_perspective_locked = false

func toggle_perspective() -> bool:
    if is_perspective_locked:
        return false
    else:
        current_perspective = Perspective.TOP_2D if current_perspective==Perspective.ISO_3D else Perspective.ISO_3D
        perspective_changed.emit()
        return true

#==================Boxes y estructuras==================
var structure_index: Dictionary[Box,int]

func maximum_reach() -> Vector3i:
    var x_max := dimensions.x
    var y_max := dimensions.y
    var z_max := dimensions.z
    for box: Box in structure_index:
        x_max = max(x_max, box.world_cell.x + 1)
        y_max = max(y_max, box.world_cell.y + 1)
        z_max = max(z_max, box.world_cell.z + 1) #el +1 porque las coords de grilla empiezan en 0,0,0; y acá busco tamaño, no coords
    return Vector3i(x_max,y_max,z_max)


func _ready() -> void:
    var current_index: int = 0
    structure_index.clear()
    for child in get_children():
        if child is Camera3D:
            camera = child

        if child is Box:                                            #Hay que adaptarlo a los demás tipos de grid entities
            current_index += 1
            structure_index[child as Box] = current_index
        elif child is Structure:
            current_index += 1
            for grandchild in child.get_children():
                if grandchild is Box:                               #Lo mismo
                    structure_index[grandchild as Box] = current_index

    camera.look_at((maximum_reach() as Vector3)*(0.5))

