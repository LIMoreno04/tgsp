@tool
class_name ProjectiveCamera
extends Camera3D

enum Perspective {ISO_3D, TOP_2D}

signal perspective_change_started(new_perspective: Perspective)
signal perspective_change_finished(new_perspective: Perspective)

var room: Room

var current_perspective: Perspective = Perspective.ISO_3D:
    get:
        return current_perspective
var is_transitioning := false
var is_locked := false

func is_3d() -> bool:
    return current_perspective == Perspective.ISO_3D


func is_2d() -> bool:
    return current_perspective == Perspective.TOP_2D



func toggle_perspective() -> bool:
    if is_transitioning or is_locked:
        return false
    else:
        perspective_change_started.emit()
        current_perspective = Perspective.TOP_2D if current_perspective==Perspective.ISO_3D else Perspective.ISO_3D
        is_transitioning = true
        return true

