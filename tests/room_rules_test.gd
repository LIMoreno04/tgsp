extends RefCounted

## Todas las reglas del Room. Se corre con `tests/run_tests.gd`.
##
## Cada caso arma una sala desde cero, la usa y la tira. Las salas llevan el RoomShell,
## así que el piso está en z = -1 y las paredes en x = -1 e y = -1, igual que en un nivel.

const ROOM_SIZE := Vector3i(6, 6, 4)

const E := Vector2i(1, 0)
const W := Vector2i(-1, 0)
const S := Vector2i(0, 1)
const D3 := Room.Perspective.ISO_3D
const D2 := Room.Perspective.TOP_2D
const SOLID := LevelIndex.ColliderType.SOLID

## Las casillas de las direcciones de un powerable.
const POS_X := &"connects_pos_x"
const NEG_X := &"connects_neg_x"
const POS_Y := &"connects_pos_y"
const NEG_Y := &"connects_neg_y"
const UP := &"connects_up"
const DOWN := &"connects_down"
const TOP := Powerable.Face.TOP
const FACE_POS_X := Powerable.Face.POS_X
const FACE_NEG_X := Powerable.Face.NEG_X
## Un jugador lejos de todo, para preguntar por la energía sin que apriete nada.
const NOBODY := Vector3i(-50, -50, 0)
const NO_BODY := Rect2(-50, -50, 0.6, 0.6)

var root: Node
var passed := 0
var failed := 0
var _failures: Array[String] = []


func run(tree_root: Node) -> void:
	root = tree_root
	index()
	connectivity()
	grabbed_structure_2d()
	riders_3d()
	terrain()
	floors_and_terrain_flags()
	refusals()
	landing_2d()
	floor_to_floor_2d()
	staying_connected()
	player_queries()
	grabbing()
	moving_with_a_player()
	colliders()
	perspective_toggle()
	restoring_for_undo()
	colliders_plane_node()
	keeping_the_height()
	structure_warnings()
	room_warnings()
	folders()
	powerables_on_faces()
	connections_in_3d()
	connections_in_2d()
	pressing()
	activity()
	the_four_use_cases()
	running_power()
	doors()
	doors_in_the_move_rules()
	doors_and_the_player()
	buttons()
	button_pedestals()
	wall_buttons()
	where_a_beam_goes()
	lasers_in_power()
	beams_and_the_player()
	a_door_held_by_its_own_laser()


func index() -> void:
	section("the index")

	var r := room([[c(1,1,0)]])
	is_true("a box in a structure is indexed by its world cell", r.index.cells_3D.has(c(1,1,0)))
	is_true("the shell is indexed too", r.index.cells_3D.has(c(0,0,-1)))
	same("grid_2D keeps the highest box of the column", r.index.grid_2D[Vector2i(1,1)], at(r,1,1,0))
	free_room(r)

	r = room([])
	var s := Structure.new()
	s.name = "Offset"
	s.cell = c(2,2,1)
	r.add_child(s)
	var b := Structure.BOX_SCENE.instantiate() as Box
	b.cell = c(1,0,0)
	s.add_child(b)
	r.rebuild_index()
	is_true("a box under an offset structure lands at cell + parent cell", r.index.cells_3D.has(c(3,2,1)))
	same("  and world_cell agrees", b.world_cell, c(3,2,1))
	free_room(r)

	r = room([[c(1,1,0)]])
	var moving: Array[Box] = [at(r,1,1,0)]
	var after := r.index.moved(moving, Vector3i(1,0,0))
	is_true("an index after a move has the box at its new cell", after.cells_3D.has(c(2,1,0)) and not after.cells_3D.has(c(1,1,0)))
	is_true("  and the room's own index is untouched", r.index.cells_3D.has(c(1,1,0)))
	free_room(r)

	r = room([[c(1,1,0)]])
	r.try_to_move_grabbed_box(at(r,1,1,0), E, D3)
	is_true("after a move the old cell is empty", not r.index.cells_3D.has(c(1,1,0)))
	is_true("  the new cell is filled", r.index.cells_3D.has(c(2,1,0)))
	same("  and grid_2D followed", r.index.grid_2D[Vector2i(2,1)], r.index.cells_3D[c(2,1,0)])
	free_room(r)


func connectivity() -> void:
	section("connectivity")

	connected("a line of four", [[c(0,0,0), c(1,0,0), c(2,0,0), c(3,0,0)]], c(0,0,0), D3, 4)
	connected("a closed ring of eight", [ring()], c(0,0,0), D3, 8)
	connected("a fork", [[c(0,0,0), c(1,0,0), c(2,0,0), c(1,1,0), c(1,2,0)]], c(0,0,0), D3, 5)
	connected("a 2x2x2 cube", [cube()], c(0,0,0), D3, 8)
	connected("a vertical column, so grid z is up", [[c(0,0,0), c(0,0,1), c(0,0,2)]], c(0,0,0), D3, 3)
	connected("two disconnected islands of one structure", [[c(0,0,0), c(1,0,0), c(4,0,0)]], c(0,0,0), D3, 2)
	connected("a horizontal diagonal does not connect", [[c(0,0,0), c(1,1,0)]], c(0,0,0), D3, 1)
	connected("a diagonal in z does not connect", [[c(0,0,0), c(1,0,1)]], c(0,0,0), D3, 1)
	connected("it stops at a structure seam", [[c(0,0,0), c(1,0,0)], [c(2,0,0), c(3,0,0)]], c(0,0,0), D3, 2)
	connected("2D walks tops, so a cube is four tiles", [cube()], c(0,0,1), D2, 4)
	connected("2D: a strip cut by a foreign box, near side", [[c(0,0,0), c(1,0,0), c(2,0,0), c(3,0,0)], [c(2,0,1)]], c(0,0,0), D2, 2)
	connected("2D: the same strip from the far side", [[c(0,0,0), c(1,0,0), c(2,0,0), c(3,0,0)], [c(2,0,1)]], c(3,0,0), D2, 1)
	connected("2D: tiles touching at different heights are one", [[c(0,0,0), c(1,0,3)]], c(0,0,0), D2, 2)

	var r := room([ring()])
	var all_eight := true
	for cell: Vector3i in ring():
		if r.index.boxes_of_same_structure_connected_to(r.index.cells_3D[cell], D3).size() != 8:
			all_eight = false
	is_true("every box of the ring sees all eight", all_eight)
	free_room(r)

	r = room([], [], [], Vector3i(50, 50, 1))
	same("a 50x50 floor is one piece, past where a recursive walk broke the stack",
		r.index.boxes_of_same_structure_connected_to(at(r,0,0,-1), D3).size(), 2500)
	free_room(r)


func grabbed_structure_2d() -> void:
	section("2D: the grabbed structure reaches down its own columns")

	grabbed("a three-tall pillar comes whole", [[c(0,0,0), c(0,0,1), c(0,0,2)]], c(0,0,2), D2, 3)
	grabbed("a foreign box cuts the descent", [[c(0,0,0), c(0,0,2)], [c(0,0,1)]], c(0,0,2), D2, 1)
	grabbed("a gap does not cut it", [[c(0,0,0), c(0,0,2)]], c(0,0,2), D2, 2)
	grabbed("a foreign box underneath is not taken", [[c(0,0,1)], [c(0,0,0)]], c(0,0,1), D2, 1)
	grabbed("nothing above is taken in 2D", [[c(0,0,0)], [c(0,0,1)]], c(0,0,0), D2, 1)
	grabbed("THE SPLIT: the buried half stays", [[c(0,0,0), c(1,0,0)], [c(0,0,1)]], c(1,0,0), D2, 1)
	grabbed("two tiles each reach down their own column", [[c(0,0,0), c(0,0,1), c(1,0,1)]], c(0,0,1), D2, 3)
	grabbed("3D takes only the connected structure", [[c(0,0,0), c(0,0,1), c(0,0,2)]], c(0,0,2), D3, 3)

	var r := room([[c(0,0,0), c(1,0,0)], [c(0,0,1)]])
	is_true("pushing the exposed half works", r.try_to_move_grabbed_box(at(r,1,0,0), E, D2))
	is_true("  and the buried half did not move", r.index.cells_3D.has(c(0,0,0)))
	free_room(r)


func riders_3d() -> void:
	section("3D: riders come if they can, stay if they cannot")

	unit_size("a crate on a platform rides", [[c(0,0,0), c(1,0,0)], [c(0,0,1)]], c(0,0,0), E, D3, 3)
	unit_size("one box of contact is enough, the pillar is left behind",
		[[c(0,0,0), c(1,0,0)], [c(3,0,0)], [c(1,0,1), c(2,0,1), c(3,0,1)]], c(0,0,0), E, D3, 5)
	unit_size("a clear tower rides all the way up",
		[[c(0,0,0)], [c(0,0,1)], [c(0,0,2)], [c(0,0,3)]], c(0,0,0), E, D3, 4)
	unit_size("a blocked rider is dropped", [[c(0,0,0)], [c(0,0,1)], [c(1,0,1)]], c(0,0,0), E, D3, 1)
	unit_size("what sat on the dropped rider is dropped too",
		[[c(0,0,0)], [c(0,0,1)], [c(1,0,1)], [c(0,0,2)]], c(0,0,0), E, D3, 1)
	unit_size("a rider blocked only by another rider still comes, one pass later",
		[[c(0,0,0), c(1,0,0)], [c(0,0,1)], [c(1,0,1)]], c(0,0,0), E, D3, 4)
	unit_size("a box underneath never joins", [[c(0,0,1)], [c(0,0,0)]], c(0,0,1), E, D3, 1)
	unit_size("a structure floating elsewhere never joins", [[c(0,0,0)], [c(4,4,2)]], c(0,0,0), E, D3, 1)
	unit_size("nothing on top is taken in 2D", [[c(0,0,0)], [c(0,0,1)]], c(0,0,0), E, D2, 1)

	var r := room([[c(0,0,0)], [c(0,0,1)], [c(1,0,1)]], [2])
	is_true("a platform may not slide out from under a blocked rider and leave it floating",
		not r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  and nothing moved", r.index.cells_3D.has(c(0,0,0)) and r.index.cells_3D.has(c(0,0,1)))
	free_room(r)

	r = room([[c(0,0,0), c(1,0,0)], [c(1,0,1)], [c(2,0,1)]], [2])
	is_true("a longer platform slides partly out from under it", r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  the platform moved", r.index.cells_3D.has(c(2,0,0)))
	is_true("  the rider stayed, still resting on the platform", r.index.cells_3D.has(c(1,0,1)) and r.index.cells_3D.has(c(1,0,0)))
	is_true("  but not all the way out", not r.try_to_move_grabbed_box(at(r,1,0,0), E, D3))
	free_room(r)

	r = room([[c(0,0,0), c(1,0,0)], [c(1,0,1), c(1,1,1)], [c(0,1,0), c(1,1,0), c(2,1,0), c(2,1,1)]], [2])
	is_true("unloading: a crate also resting on a ledge is caught by the ledge's end", r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  and the platform can leave it on the ledge",
		r.try_to_move_grabbed_box(at(r,1,0,0), E, D3) and r.index.cells_3D.has(c(1,0,1)) and not r.index.cells_3D.has(c(1,0,0)))
	free_room(r)


func terrain() -> void:
	section("terrain never moves")

	var r := room([[c(0,0,0)]], [0])
	is_true("grabbing a wall is refused", not r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	free_room(r)

	r = room([])
	is_true("grabbing a floor box is refused", not r.try_to_move_grabbed_box(at(r,2,2,-1), E, D2))
	free_room(r)

	r = room([[c(0,0,0), c(1,0,0)]])
	add_boxes(r, "Wall", [c(0,0,1)], true)
	same("a wall never joins the unit", r.index.boxes_that_would_move(at(r,0,0,0), E, D3).size(), 2)
	is_true("  so the platform can still be pushed out", r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  and the wall is left floating", r.index.cells_3D.has(c(0,0,1)))
	free_room(r)


func floors_and_terrain_flags() -> void:
	section("a floor is always walkable, and terrain has no handles")

	var floor_box := Structure.BOX_SCENE.instantiate() as Box
	floor_box.is_floor = true
	floor_box.walkable = false
	is_true("unchecking walkable on a floor does nothing", floor_box.walkable)
	var saved := PackedScene.new()
	saved.pack(floor_box)
	var loaded := saved.instantiate() as Box
	is_true("  and the floor is still walkable once saved and loaded", loaded.walkable)
	floor_box.free()
	loaded.free()

	var r := room([[c(3,2,0)]], [0])
	at(r,3,2,0).movable_3d_neg_x = true
	at(r,3,2,0).movable_2d_neg_x = true
	r.rebuild_index()
	is_true("a wall left with a 3D handle from before cannot be grabbed", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3) == null)
	is_true("  nor with a 2D one", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D2) == null)
	free_room(r)

	r = room([])
	at(r,2,2,-1).movable_2d_pos_x = true
	r.rebuild_index()
	is_true("a floor left with a 2D handle is no barrier", not r.index.has_stripe_on(Vector2i(2,2), Box.Facing.POS_X, D2))
	is_true("  and gets no edge collider", not r.index.colliders_plane(0, D2).has(Vector2i(2,2)))
	free_room(r)


func refusals() -> void:
	section("refusals")

	var r := room([[c(0,0,0)], [c(1,0,0)]])
	is_true("a blocked grabbed structure refuses", not r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  and nothing moved", r.index.cells_3D.has(c(0,0,0)) and r.index.cells_3D.has(c(1,0,0)))
	free_room(r)

	r = room([[c(0,0,0), c(1,0,0)], [c(2,0,0)]])
	is_true("blocked past the far end refuses", not r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	free_room(r)

	r = room([[c(0,0,0)], [c(1,0,0)]])
	is_true("2D: a non-walkable landing refuses", not r.try_to_move_grabbed_box(at(r,0,0,0), E, D2))
	free_room(r)

	r = room([[c(5,0,0)]])
	is_true("2D: the void refuses", not r.try_to_move_grabbed_box(at(r,5,0,0), E, D2))
	is_true("  and it stayed", r.index.cells_3D.has(c(5,0,0)))
	free_room(r)

	r = room([[c(0,0,0)], [c(1,0,0)]])
	at(r,1,0,0).movable_3d_neg_x = true
	r.rebuild_index()
	is_true("a unit cannot push another unit", not r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	free_room(r)


func landing_2d() -> void:
	section("2D landing: one rigid offset for the whole unit")

	var r := room([[c(0,0,0)]])
	r.try_to_move_grabbed_box(at(r,0,0,0), E, D2)
	is_true("flat ground keeps its height", r.index.cells_3D.has(c(1,0,0)))
	free_room(r)

	r = room([[c(0,0,0)], [c(1,0,0)]], [], [1])
	r.try_to_move_grabbed_box(at(r,0,0,0), E, D2)
	is_true("it climbs onto a walkable step", r.index.cells_3D.has(c(1,0,1)))
	is_true("  and the step is untouched", r.index.cells_3D.has(c(1,0,0)))
	free_room(r)

	r = room([[c(0,0,0), c(0,0,1)], [c(1,0,0)]], [], [1])
	is_true("a two-tall unit climbs", r.try_to_move_grabbed_box(at(r,0,0,1), E, D2))
	is_true("  bottom at z = 1", r.index.cells_3D.has(c(1,0,1)))
	is_true("  top at z = 2, shape kept", r.index.cells_3D.has(c(1,0,2)))
	free_room(r)

	r = room([[c(0,0,3)]])
	is_true("a floating tile drops", r.try_to_move_grabbed_box(at(r,0,0,3), E, D2))
	is_true("  onto the floor at z = 0", r.index.cells_3D.has(c(1,0,0)))
	free_room(r)

	r = room([[c(0,0,0), c(0,1,0)], [c(1,1,0)]], [], [1])
	var before := r.index.cells_3D.size()
	is_true("a wide unit rises by the most demanding column", r.try_to_move_grabbed_box(at(r,0,0,0), E, D2))
	is_true("  the stepped column landed on top", r.index.cells_3D.has(c(1,1,1)))
	is_true("  the flat column rose with it", r.index.cells_3D.has(c(1,0,1)))
	same("  no box lost or duplicated", r.index.cells_3D.size(), before)
	free_room(r)


func staying_connected() -> void:
	section("a unit may hang over the void, but not float free")

	# El piso va de 0 a 5, así que una caja sola corrida de la última columna no toca nada.
	var r := room([[c(5,2,0)]])
	is_true("a lone box cannot be pushed off the edge", not r.try_to_move_grabbed_box(at(r,5,2,0), E, D3))
	is_true("  and it stayed", r.index.cells_3D.has(c(5,2,0)))
	free_room(r)

	r = room([[c(3,2,0), c(4,2,0), c(5,2,0)]])
	is_true("a structure may cantilever over the void", r.try_to_move_grabbed_box(at(r,3,2,0), E, D3))
	is_true("  its far end is over the void", r.index.cells_3D.has(c(6,2,0)))
	is_true("  and its near end still on the floor", r.index.cells_3D.has(c(4,2,0)))
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0)]])
	is_true("the first push out is fine", r.try_to_move_grabbed_box(at(r,4,2,0), E, D3))
	is_true("the one that would free it is refused", not r.try_to_move_grabbed_box(at(r,5,2,0), E, D3))
	is_true("  so it stayed where it was", r.index.cells_3D.has(c(5,2,0)) and r.index.cells_3D.has(c(6,2,0)))
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0)]])
	r.try_to_move_grabbed_box(at(r,4,2,0), E, D3)
	is_true("it can be pulled back toward land", r.try_to_move_grabbed_box(at(r,5,2,0), W, D3))
	is_true("  and is back over the floor", r.index.cells_3D.has(c(4,2,0)))
	free_room(r)

	r = room([[c(0,0,0)]])
	is_true("an ordinary push on the floor is unaffected", r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	free_room(r)

	r = room([[c(3,3,0)], [c(3,3,1)]])
	is_true("a lone box cannot be slid off its pedestal", not r.try_to_move_grabbed_box(at(r,3,3,1), E, D3))
	free_room(r)

	r = room([[c(3,3,0), c(4,3,0)], [c(3,3,1), c(4,3,1)]])
	is_true("a wide stack still overlapping its support may slide", r.try_to_move_grabbed_box(at(r,3,3,1), E, D3))
	free_room(r)

	r = room([[c(0,0,0)]])
	is_true("2D moves are unaffected", r.try_to_move_grabbed_box(at(r,0,0,0), E, D2))
	free_room(r)

	r = room([[c(5,2,0), c(6,2,0)], [c(5,3,0)]])
	is_true("touching something sideways is not resting on it", not r.try_to_move_grabbed_box(at(r,5,3,0), E, D3))
	free_room(r)


func floor_to_floor_2d() -> void:
	section("2D: from floor to floor")

	var r := room([[c(2,2,0)], [c(2,2,1)]])
	is_true("a crate on another crate cannot be pulled off it", not r.try_to_move_grabbed_box(at(r,2,2,1), W, D2))
	is_true("  nor pushed off it", not r.try_to_move_grabbed_box(at(r,2,2,1), E, D2))
	is_true("  so it stays", r.index.cells_3D.has(c(2,2,1)))
	is_true("  but in 3D the crate under it carries it along", r.try_to_move_grabbed_box(at(r,2,2,0), E, D3) and r.index.cells_3D.has(c(3,2,1)))
	free_room(r)

	r = room([[c(2,2,0)], [c(2,2,1)]], [], [0])
	is_true("a crate on a walkable platform can be pulled off it", r.try_to_move_grabbed_box(at(r,2,2,1), W, D2) and r.index.cells_3D.has(c(1,2,0)))
	is_true("  and pushed back onto it", r.try_to_move_grabbed_box(at(r,1,2,0), E, D2) and r.index.cells_3D.has(c(2,2,1)))
	free_room(r)

	r = room([[c(2,2,0)], [c(2,2,1)]], [0])
	is_true("a crate on a wall does not move in 2D", not r.try_to_move_grabbed_box(at(r,2,2,1), W, D2))
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0), c(6,2,0)]])
	is_true("a platform hanging over the void can be pulled back in 2D", r.try_to_move_grabbed_box(at(r,4,2,0), W, D2) and r.index.cells_3D.has(c(3,2,0)) and r.index.cells_3D.has(c(5,2,0)))
	is_true("  and pushed out over it again", r.try_to_move_grabbed_box(at(r,3,2,0), E, D2) and r.index.cells_3D.has(c(6,2,0)))
	is_true("  and further, while a box of it is still over the floor", r.try_to_move_grabbed_box(at(r,4,2,0), E, D2) and r.index.cells_3D.has(c(7,2,0)))
	is_true("  but not once none would be", not r.try_to_move_grabbed_box(at(r,5,2,0), E, D2) and r.index.cells_3D.has(c(5,2,0)))
	free_room(r)

	r = room([[c(1,2,0), c(2,2,0), c(3,2,0)]], [], [0])
	remove_box(r, c(4,2,-1))
	is_true("2D: a plank can be pushed out over a hole", r.try_to_move_grabbed_box(at(r,1,2,0), E, D2) and r.index.cells_3D.has(c(4,2,0)))
	is_true("  and across it, as a bridge", r.try_to_move_grabbed_box(at(r,2,2,0), E, D2) and r.index.cells_3D.has(c(5,2,0)))
	is_true("  which can be stood on over the hole", r.index.can_player_be_on(c(4,2,9), D2))
	free_room(r)

	r = room([[c(3,2,0)]])
	remove_box(r, c(4,2,-1))
	is_true("2D: a lone crate cannot be pushed into a hole", not r.try_to_move_grabbed_box(at(r,3,2,0), E, D2) and r.index.cells_3D.has(c(3,2,0)))
	free_room(r)

	r = room([[c(2,2,0)], [c(3,2,0)]], [], [1])
	remove_box(r, c(3,2,-1))
	is_true("2D: a crate cannot go onto something that is not walkable, hole or not", not r.try_to_move_grabbed_box(at(r,3,2,0), W, D2))
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0)], [c(5,2,1)]], [], [0])
	remove_box(r, c(5,2,-1))
	same("2D: a crate on a plank's tip over a hole hides the tip, so a pull takes only the near box",
		r.index.boxes_that_would_move(at(r,4,2,0), W, D2).size(), 1)
	is_true("  and is refused: the tip would stay over the hole holding the crate, attached to nothing",
		not r.try_to_move_grabbed_box(at(r,4,2,0), W, D2) and r.index.cells_3D.has(c(4,2,0)))
	is_true("  the crate can be moved off it, onto the floor beside", r.try_to_move_grabbed_box(at(r,5,2,1), S, D2) and r.index.cells_3D.has(c(5,3,0)))
	is_true("  and then the plank comes back whole",
		r.try_to_move_grabbed_box(at(r,4,2,0), W, D2) and r.index.cells_3D.has(c(3,2,0)) and r.index.cells_3D.has(c(4,2,0)))
	free_room(r)


func player_queries() -> void:
	section("player queries")

	var r := room([])
	is_true("3D: the shell floor can be stood on", r.index.can_player_be_on(c(2,2,0), D3))
	is_true("  the box below is the floor", r.index.floor_of(c(2,2,0), D3).is_floor)
	is_true("3D: nothing to stand on in mid air", not r.index.can_player_be_on(c(2,2,3), D3))
	is_true("3D: outside the room there is nowhere to stand", not r.index.can_player_be_on(c(9,9,0), D3))
	free_room(r)

	r = room([[c(2,2,0)]])
	is_true("3D: a box in your own cell blocks", not r.index.can_player_be_on(c(2,2,0), D3))
	is_true("3D: a non-walkable top cannot be stood on", not r.index.can_player_be_on(c(2,2,1), D3))
	is_true("2D: a non-walkable top cannot be stood on", not r.index.can_player_be_on(c(2,2,9), D2))
	is_true("something above the cell is occlusion", r.index.is_occluded(c(2,2,-1)))
	is_true("  nothing above a cell over the box", not r.index.is_occluded(c(2,2,1)))
	free_room(r)

	r = room([[c(2,2,0)]], [], [0])
	is_true("3D: on top of a walkable box", r.index.can_player_be_on(c(2,2,1), D3))
	is_true("2D: height is ignored, the top decides", r.index.can_player_be_on(c(2,2,9), D2))
	free_room(r)

	r = room([[c(2,2,0)]], [], [0])
	at(r,2,2,0).movable_2d_pos_x = true
	r.rebuild_index()
	is_true("2D: a stripe is a barrier on that side", r.index.has_stripe_on(Vector2i(2,2), Box.Facing.POS_X, D2))
	is_true("  but not on the others", not r.index.has_stripe_on(Vector2i(2,2), Box.Facing.NEG_X, D2))
	is_true("3D: there are no barriers", not r.index.has_stripe_on(Vector2i(2,2), Box.Facing.POS_X, D3))
	free_room(r)


func grabbing() -> void:
	section("choosing what to grab")

	var r := room([[c(3,2,0)]])
	handle_3d(at(r,3,2,0), Box.Facing.NEG_X)
	r.rebuild_index()
	same("grabs the crate straight ahead", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3), at(r,3,2,0))
	same("  a lone candidate behind is still grabbed", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(-1,0), D3), at(r,3,2,0))
	is_true("3D ignores a neighbour below the player", r.index.choose_what_to_interact_with(c(2,2,1), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)]])
	handle_3d(at(r,3,2,0), Box.Facing.POS_X)
	r.rebuild_index()
	is_true("a handle on the far face is not grabbable", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)]])
	is_true("a box with no handles is not grabbable", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)], [c(2,3,0)]])
	handle_3d(at(r,3,2,0), Box.Facing.NEG_X)
	handle_3d(at(r,2,3,0), Box.Facing.NEG_Y)
	r.rebuild_index()
	same("facing east picks east", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3), at(r,3,2,0))
	same("facing north picks north", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(0,1), D3), at(r,2,3,0))
	same("a diagonal ties, and the fixed order settles it",
		r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,1).normalized(), D3), at(r,3,2,0))
	free_room(r)

	r = room([[c(3,2,3)]])
	at(r,3,2,3).movable_2d_neg_x = true
	r.rebuild_index()
	same("2D grabs the neighbouring top", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D2), at(r,3,2,3))
	is_true("  and the 3D handles are a separate set", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(2,2,0)], [c(3,2,0)]], [], [0])
	at(r,2,2,0).movable_2d_pos_x = true
	at(r,3,2,0).movable_2d_neg_x = true
	r.rebuild_index()
	is_true("2D: a stripe on your own tile blocks the grab",
		r.index.choose_what_to_interact_with(c(2,2,1), Vector2(1,0), D2) == null)
	at(r,2,2,0).movable_2d_pos_x = false
	r.rebuild_index()
	same("  with the stripe gone it is reachable",
		r.index.choose_what_to_interact_with(c(2,2,1), Vector2(1,0), D2), at(r,3,2,0))
	free_room(r)


func moving_with_a_player() -> void:
	section("pushing and pulling with a player")

	var r := room([[c(3,2,0)]])
	is_true("push succeeds", r.move_grabbed_box(at(r,3,2,0), E, c(2,2,0), D3))
	is_true("  the crate moved", r.index.cells_3D.has(c(4,2,0)))
	is_true("  and vacated the cell the player steps into", not r.index.cells_3D.has(c(3,2,0)))
	free_room(r)

	r = room([[c(3,2,0)]])
	is_true("pull succeeds", r.move_grabbed_box(at(r,3,2,0), W, c(2,2,0), D3))
	is_true("  the crate arrived where the player was", r.index.cells_3D.has(c(2,2,0)))
	free_room(r)

	r = room([[c(1,2,0)]])
	is_true("a pull with nothing behind the player is refused",
		not r.move_grabbed_box(at(r,1,2,0), W, c(0,2,0), D3))
	is_true("  and nothing moved", r.index.cells_3D.has(c(1,2,0)))
	free_room(r)

	r = room([[c(2,2,0), c(3,2,0)]], [], [0])
	is_true("you cannot move what you are standing on",
		not r.move_grabbed_box(at(r,3,2,0), E, c(2,2,1), D3))
	is_true("  and nothing moved", r.index.cells_3D.has(c(2,2,0)) and r.index.cells_3D.has(c(3,2,0)))
	free_room(r)

	r = room([[c(2,2,0), c(3,2,0)], [c(2,2,1)]], [], [1])
	is_true("nor a rider you are standing on",
		not r.move_grabbed_box(at(r,3,2,0), E, c(2,2,2), D3))
	free_room(r)

	r = room([[c(3,2,0)], [c(4,2,0)]])
	is_true("the ordinary rules still apply", not r.move_grabbed_box(at(r,3,2,0), E, c(2,2,0), D3))
	free_room(r)

	r = room([[c(3,2,0)]])
	is_true("2D: push succeeds", r.move_grabbed_box(at(r,3,2,0), E, c(2,2,0), D2))
	free_room(r)

	r = room([[c(3,2,0)], [c(3,2,1)]], [], [0])
	at(r,3,2,0).movable_2d_neg_x = true
	r.rebuild_index()
	is_true("2D: a push may not step the player over the stripe it uncovers",
		not r.move_grabbed_box(at(r,3,2,1), E, c(2,2,0), D2))
	is_true("  and nothing moved", r.index.cells_3D.has(c(3,2,1)))
	free_room(r)

	r = room([[c(3,2,0)], [c(3,2,1)]], [], [0])
	at(r,3,2,0).movable_2d_pos_y = true
	r.rebuild_index()
	is_true("  a stripe on another side of that tile is no barrier", r.move_grabbed_box(at(r,3,2,1), E, c(2,2,0), D2))
	free_room(r)

	r = room([[c(2,2,0)], [c(3,2,0)]], [], [0])
	at(r,2,2,0).movable_2d_neg_x = true
	r.rebuild_index()
	is_true("2D: a pull may not step the player back over their own tile's stripe",
		not r.move_grabbed_box(at(r,3,2,0), W, c(2,2,1), D2))
	at(r,2,2,0).movable_2d_neg_x = false
	r.rebuild_index()
	is_true("  without the stripe it may", r.move_grabbed_box(at(r,3,2,0), W, c(2,2,1), D2))
	free_room(r)

	r = room([[c(3,2,0)], [c(3,2,1)]], [], [0])
	at(r,3,2,0).movable_2d_neg_x = true
	r.rebuild_index()
	is_true("3D: stripes are no barrier to a step", not r.index.would_player_cross_a_barrier(c(2,2,1), E, r.index, D3))
	free_room(r)


func colliders() -> void:
	section("the collision plane")

	var r := room([])
	var plane := r.index.colliders_plane(0, D3)
	same("the open far edge is solid", plane.get(Vector2i(6,3)), [SOLID])
	same("the wall line is solid", plane.get(Vector2i(-1,3)), [SOLID])
	same("the near corner is solid", plane.get(Vector2i(-1,-1)), [SOLID])
	is_true("the far corner is left out, the edges beside it already close it", not plane.has(Vector2i(6,6)))
	is_true("nothing beyond the edge", not plane.has(Vector2i(7,3)))
	is_true("open floor needs no collider", not plane.has(Vector2i(3,3)))
	same("high above, every interior column is solid", interior_entries(r.index.colliders_plane(5, D3)), 36)
	free_room(r)

	r = room([[c(3,3,0)]])
	same("3D: a crate at your height is solid", r.index.colliders_plane(0, D3).get(Vector2i(3,3)), [SOLID])
	same("2D: a non-walkable top is solid", r.index.colliders_plane(0, D2).get(Vector2i(3,3)), [SOLID])
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	is_true("3D: on top of a walkable crate is open", not r.index.colliders_plane(1, D3).has(Vector2i(3,3)))
	same("3D: but inside it is solid", r.index.colliders_plane(0, D3).get(Vector2i(3,3)), [SOLID])
	is_true("2D: a walkable top is open", not r.index.colliders_plane(0, D2).has(Vector2i(3,3)))
	free_room(r)

	r = room([[c(3,3,0)]])
	at(r,3,3,0).movable_2d_whole_face = true
	r.rebuild_index()
	same("2D: a whole-face grabbable tile is solid", r.index.colliders_plane(0, D2).get(Vector2i(3,3)), [SOLID])
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	at(r,3,3,0).movable_2d_pos_x = true
	r.rebuild_index()
	same("one stripe, one edge", r.index.colliders_plane(0, D2).get(Vector2i(3,3)), [LevelIndex.ColliderType.POS_X])
	is_true("3D reports no edges", not r.index.colliders_plane(1, D3).has(Vector2i(3,3)))
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	at(r,3,3,0).movable_2d_pos_x = true
	at(r,3,3,0).movable_2d_neg_y = true
	r.rebuild_index()
	var edges: Array = r.index.colliders_plane(0, D2).get(Vector2i(3,3))
	same("two stripes, two edges", edges.size(), 2)
	is_true("  both of them", edges.has(LevelIndex.ColliderType.POS_X) and edges.has(LevelIndex.ColliderType.NEG_Y))
	free_room(r)

	r = room([])
	remove_box(r, c(2,2,-1))
	same("3D: a hole in the floor is solid", r.index.colliders_plane(0, D3).get(Vector2i(2,2)), [SOLID])
	same("2D: a hole in the floor is solid", r.index.colliders_plane(0, D2).get(Vector2i(2,2)), [SOLID])
	is_true("  its neighbours stay open", not r.index.colliders_plane(0, D3).has(Vector2i(2,1)))
	free_room(r)

	r = room([])
	remove_box(r, c(3,3,-1))
	add_boxes(r, "UnderTheHole", [c(3,3,-2)], false)
	same("a hole with a non-walkable box under it is solid too", r.index.colliders_plane(0, D2).get(Vector2i(3,3)), [SOLID])
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0), c(6,2,0)]], [], [0])
	is_true("3D: a platform hanging past the edge can be walked on", not r.index.colliders_plane(1, D3).has(Vector2i(6,2)))
	same("  the void past its end is solid", r.index.colliders_plane(1, D3).get(Vector2i(7,2)), [SOLID])
	same("  and the void beside it", r.index.colliders_plane(1, D3).get(Vector2i(6,3)), [SOLID])
	is_true("2D: the same platform can be walked on", not r.index.colliders_plane(0, D2).has(Vector2i(6,2)))
	same("  and the void past it is solid", r.index.colliders_plane(0, D2).get(Vector2i(7,2)), [SOLID])
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0), c(6,2,0)]], [], [0])
	at(r,6,2,0).movable_2d_pos_x = true
	r.rebuild_index()
	plane = r.index.colliders_plane(0, D2)
	same("a stripe facing the void is an edge", plane.get(Vector2i(6,2)), [LevelIndex.ColliderType.POS_X])
	same("  and the void behind the stripe is still solid", plane.get(Vector2i(7,2)), [SOLID])
	free_room(r)

	r = room([], [], [], Vector3i(50, 50, 1))
	plane = r.index.colliders_plane(0, D3)
	same("a 50x50 floor, past where the old flood overflowed, is closed on its far side", plane.get(Vector2i(50,49)), [SOLID])
	same("  and its whole rim is there: two walls and two open sides", plane.size(), 51 + 50 + 50 + 50)
	free_room(r)


func perspective_toggle() -> void:
	section("toggling the perspective")

	var r := room([[c(3,3,0)]], [], [0])
	var manager := add_perspective_manager(r)
	same("the starting height is the spawn point's", manager.height, r.player_spawn_point.z)
	is_true("3D to 2D with nothing overhead", manager.toggle(Vector2i(2,2)) and manager.is_2d())
	is_true("2D to 3D is always allowed", manager.toggle(Vector2i(3,3)) and manager.is_3d())
	same("  and lands on top of the column, here the crate", manager.height, 1)
	free_room(r)

	r = room([[c(2,2,1)]])
	manager = add_perspective_manager(r)
	is_true("3D to 2D is refused with a box overhead", not manager.toggle(Vector2i(2,2)))
	is_true("  and nothing changed", manager.is_3d() and manager.height == 0)
	free_room(r)



func restoring_for_undo() -> void:
	section("restoring for undo")

	var r := room([[c(3,2,0)]])
	var before := r.box_cells()
	r.try_to_move_grabbed_box(at(r,3,2,0), E, D3)
	var announced := [0]
	r.moved.connect(func() -> void: announced[0] += 1)
	r.restore(before, r.button_states(), r.powerables_displayed_as_on())
	is_true("restoring the cells puts a pushed box back", r.index.cells_3D.has(c(3,2,0)) and not r.index.cells_3D.has(c(4,2,0)))
	same("  and the room announces it, so the collision plane follows", announced[0], 1)
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	var manager := add_perspective_manager(r)
	manager.toggle(Vector2i(3,3))
	manager.toggle(Vector2i(3,3))
	var turns := [0]
	manager.perspective_changed.connect(func(_perspective: Room.Perspective) -> void: turns[0] += 1)
	manager.restore(D2, 0)
	is_true("restoring the perspective goes back to 2D and the old height", manager.is_2d() and manager.height == 0)
	same("  and announces it, so the camera turns back", turns[0], 1)
	manager.restore(D2, 0)
	same("restoring the same perspective announces nothing", turns[0], 1)
	free_room(r)


func colliders_plane_node() -> void:
	section("the collision plane node")

	var r := room([[c(3,3,0)]])
	add_perspective_manager(r)
	var plane := add_colliders_plane(r)
	plane.rebuild()
	same("it sits one cell above everything", plane.position.y, float(r.maximum_reach().z + 1))
	is_true("a SOLID column gets the solid collider", plane.has_collider(Vector2i(3,3), SOLID))
	is_true("open floor gets none", not plane.has_collider(Vector2i(2,2), SOLID))
	is_true("it has exactly the colliders colliders_plane asks for", plane_matches_its_room(plane, r))

	var announced := [0]
	r.moved.connect(func() -> void: announced[0] += 1)
	r.try_to_move_grabbed_box(at(r,3,3,0), E, D3)
	same("the room announces a move", announced[0], 1)
	plane.rebuild()
	is_true("  and the rebuilt plane follows it", plane.has_collider(Vector2i(4,3), SOLID) and not plane.has_collider(Vector2i(3,3), SOLID))
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	at(r,3,3,0).movable_2d_pos_x = true
	r.rebuild_index()
	var manager := add_perspective_manager(r)
	plane = add_colliders_plane(r)
	manager.toggle(Vector2i(2,2))
	plane.rebuild()
	is_true("2D: a stripe becomes its edge collider", plane.has_collider(Vector2i(3,3), LevelIndex.ColliderType.POS_X))
	is_true("  and nothing else changes", plane_matches_its_room(plane, r))
	free_room(r)

	r = room([[c(1,1,0), c(1,1,1), c(1,1,2), c(1,1,3), c(1,1,4)]])
	add_perspective_manager(r)
	plane = add_colliders_plane(r)
	plane.rebuild()
	same("a pillar taller than the room lifts the plane above it", plane.position.y, 6.0)
	free_room(r)


func keeping_the_height() -> void:
	section("boxes that keep their height")

	var r := room([[c(0,2,2), c(1,2,2)]], [], [0])
	is_true("2D: a platform that does not keep its height drops", r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.index.cells_3D.has(c(0,3,0)))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)]], [], [0])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	is_true("2D: one that keeps it slides along the wall at the same height",
		r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.index.cells_3D.has(c(0,3,2)) and r.index.cells_3D.has(c(1,3,2)))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)]], [], [0])
	keep_height(r, [c(1,2,2)])
	is_true("  one ticked box is enough for the whole platform", r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.index.cells_3D.has(c(0,3,2)))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)], [c(1,3,0), c(1,3,1), c(1,3,2)]], [], [0, 1])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	is_true("2D: a walkable step at its height lifts it, just enough",
		r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.index.cells_3D.has(c(0,3,3)) and r.index.cells_3D.has(c(1,3,3)))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)], [c(1,3,2)]], [], [0])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	is_true("2D: something not walkable in its way still refuses", not r.try_to_move_grabbed_box(at(r,0,2,2), S, D2))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)]], [], [0])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	remove_box(r, c(0,3,-1))
	is_true("2D: like in 3D, it slides over a hole while it touches the wall", r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.index.cells_3D.has(c(0,3,2)))
	free_room(r)

	r = room([[c(5,2,2)]], [], [0])
	keep_height(r, [c(5,2,2)])
	is_true("2D: but not out over the void touching nothing", not r.try_to_move_grabbed_box(at(r,5,2,2), E, D2))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)]])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	is_true("3D: it hangs from the wall while sliding along it", r.try_to_move_grabbed_box(at(r,0,2,2), S, D3) and r.index.cells_3D.has(c(0,3,2)))
	is_true("  but not once it would touch nothing", not r.try_to_move_grabbed_box(at(r,0,3,2), E, D3))
	free_room(r)


func structure_warnings() -> void:
	section("structure warnings")

	var outside := Structure.new()
	root.add_child(outside)
	is_true("a structure outside a Room says so", has_warning(outside, "Not inside a Room"))
	root.remove_child(outside)
	outside.free()

	var r := room([[c(0,2,2), c(1,2,2)]])
	var platform := at(r,0,2,2).get_parent() as Structure
	is_true("one inside a Room does not", not has_warning(platform, "the rules skip"))
	is_true("  and neither does a shell part", not has_warning(r.get_node("RoomShell/Floor") as Structure, "the rules skip"))
	at(r,1,2,2).keeps_height = true
	is_true("only some boxes keeping their height is flagged", has_warning(platform, "Only some of its boxes"))
	at(r,0,2,2).keeps_height = true
	is_true("  all of them is not", not has_warning(platform, "Only some of its boxes"))
	is_true("a structure without terrain says nothing about it", not has_warning(platform, "terrain"))
	at(r,1,2,2).is_wall = true
	is_true("  one mixing terrain with other boxes says so", has_warning(platform, "Some of its boxes are terrain"))
	free_room(r)

	r = room([[c(1,1,0)]])
	is_true("an unrotated box says nothing about its transform", not has_warning(at(r,1,1,0), "Rotated or scaled"))
	at(r,1,1,0).rotation = Vector3(0, PI / 2, 0)
	is_true("a rotated box says so, even inside a structure", has_warning(at(r,1,1,0), "Rotated or scaled"))
	var crate := at(r,1,1,0).get_parent() as Structure
	crate.scale = Vector3(2, 2, 2)
	is_true("  and so does a scaled structure", has_warning(crate, "Rotated or scaled"))
	free_room(r)


func room_warnings() -> void:
	section("room warnings")

	var r := room([])
	is_true("a room at the origin, with a spawn point on the floor, has nothing to say", r._get_configuration_warnings().is_empty())
	r.position = Vector3(1, 0, 0)
	is_true("a room moved off the origin says so", has_warning(r, "must sit at the origin"))
	free_room(r)

	r = room([[c(2,2,0)]], [], [0])
	r.player_spawn_point = c(2,2,0)
	is_true("a spawn point inside a box says so", has_warning(r, "cannot stand at player_spawn_point"))
	var manager := add_perspective_manager(r)
	manager.starting_perspective = D2
	is_true("  unless the level starts in 2D, where the box's walkable top is all that counts",
		not has_warning(r, "cannot stand at player_spawn_point"))
	free_room(r)


func folders() -> void:
	section("folders")

	var r := room([])
	var folder := add_folder(r, "Folder", c(3,0,0))
	var s := add_structure(folder, "InAFolder", c(1,1,0), [c(0,0,0)])
	var deeper := add_folder(folder, "Deeper", c(0,0,0))
	var loose := Structure.BOX_SCENE.instantiate() as Box
	loose.cell = c(1,4,0)
	deeper.add_child(loose)
	r.rebuild_index()
	is_true("a structure in a folder lands at its cell plus the folder's", r.index.cells_3D.has(c(4,1,0)))
	is_true("  a loose box two folders deep too", r.index.cells_3D.has(c(4,4,0)))
	is_true("  a push moves it in the index", r.try_to_move_grabbed_box(at(r,4,1,0), E, D3) and r.index.cells_3D.has(c(5,1,0)) and not r.index.cells_3D.has(c(4,1,0)))
	is_true("  and none of them warns", not has_warning(s, "the rules skip") and not has_warning(loose, "the rules skip") and not has_warning(folder, "the rules skip"))
	free_room(r)

	r = room([])
	var plain := Node3D.new()
	plain.name = "Plain"
	r.add_child(plain)
	s = add_structure(plain, "Hidden", c(1,1,0), [c(0,0,0)])
	loose = Structure.BOX_SCENE.instantiate() as Box
	loose.cell = c(2,2,0)
	plain.add_child(loose)
	r.rebuild_index()
	is_true("a plain Node3D in the way hides what is in it from the rules", not r.index.cells_3D.has(c(1,1,0)) and not r.index.cells_3D.has(c(2,2,0)))
	is_true("  its structures say so", has_warning(s, "Plain, between this and the Room, is not a GridEntity"))
	is_true("  its loose boxes too", has_warning(loose, "is not a GridEntity"))
	is_true("  but a box in a structure leaves it to the structure", not has_warning(s.boxes()[0], "the rules skip"))
	free_room(r)


func powerables_on_faces() -> void:
	section("powerables on the faces of a box")

	var r := room([[c(2,2,0)]])
	var on_top := wire(r, c(2,2,0), TOP, [POS_X])
	var on_side := wire(r, c(2,2,0), FACE_POS_X, [UP])
	same("a box answers what is on each face", at(r,2,2,0).powerable_on(TOP), on_top)
	same("  and lists one per face", at(r,2,2,0).powerables().size(), 2)
	var second := wire(r, c(2,2,0), TOP, [NEG_X])
	same("with two on one face, the first counts", at(r,2,2,0).powerable_on(TOP), on_top)
	same("  and only it is listed", at(r,2,2,0).powerables().size(), 2)
	is_true("  the second warns", has_warning(second, "already on this face"))
	is_true("  the first does not", not has_warning(on_top, "already on this face"))
	is_true("  nor does one alone on its face", not has_warning(on_side, "already on this face"))
	free_room(r)

	var loose := Wire.new()
	root.add_child(loose)
	is_true("a powerable outside a box warns", has_warning(loose, "must be a child of a Box"))
	root.remove_child(loose)
	loose.free()

	r = room([[c(2,2,0)]])
	var stale := wire(r, c(2,2,0), TOP, [POS_X, UP])
	same("a direction along its face's normal never counts, even ticked", stale.allowed_directions(), [Vector3i(1, 0, 0)])
	is_true("  and the inspector hides those two",
		hidden_in_inspector(stale, "connects_up") and hidden_in_inspector(stale, "connects_down") and not hidden_in_inspector(stale, "connects_pos_x"))
	var side := wire(r, c(2,2,0), FACE_NEG_X, [])
	is_true("  on a side face it hides the two along x", hidden_in_inspector(side, "connects_neg_x") and not hidden_in_inspector(side, "connects_up"))
	is_true("plates and doors have no face to choose",
		hidden_in_inspector(plate(r, c(3,3,-1), []), "face") and hidden_in_inspector(door(r, c(4,4,-1), Box.Facing.POS_X, []), "face"))
	same("buttons offer the top and the four sides", faces_offered(button(r, c(5,5,-1), [], false)), "TOP:0,POS_X:2,NEG_X:3,POS_Y:4,NEG_Y:5")
	free_room(r)


func connections_in_3d() -> void:
	section("3D: how powerables connect")

	var r := room([])
	var a := wire(r, c(1,2,-1), TOP, [POS_X])
	var b := wire(r, c(2,2,-1), TOP, [NEG_X])
	is_true("flat: two neighbouring tops", connects(r, a, b, D3))
	free_room(r)

	r = room([])
	a = wire(r, c(1,2,-1), TOP, [POS_X])
	b = wire(r, c(2,2,-1), TOP, [POS_Y])
	is_true("both sides must allow the edge they share", not connects(r, a, b, D3) and r.index.connected_powerables(a, D3).is_empty())
	free_room(r)

	r = room([[c(2,2,0)]])
	var on_top := wire(r, c(2,2,0), TOP, [POS_X])
	var on_side := wire(r, c(2,2,0), FACE_POS_X, [UP, DOWN])
	var on_floor := wire(r, c(3,2,-1), TOP, [NEG_X])
	is_true("over an outer edge: a top and a side of the same box", connects(r, on_top, on_side, D3))
	is_true("into an inner corner: a side and the floor at its foot", connects(r, on_side, on_floor, D3))
	add_boxes(r, "OnTop", [c(2,2,1)], false)
	is_true("  a box on top does not cut the outer edge, seen from either side", connects(r, on_top, on_side, D3))
	add_boxes(r, "Beside", [c(3,2,1)], false)
	is_true("  nor does one beside it", connects(r, on_top, on_side, D3))
	free_room(r)

	r = room([[c(2,2,0)]])
	var floor_wire := wire(r, c(1,2,-1), TOP, [POS_X])
	var under_the_box := wire(r, c(2,2,-1), TOP, [NEG_X])
	var up_the_box := wire(r, c(2,2,0), FACE_NEG_X, [DOWN])
	var found := r.index.connected_powerables(floor_wire, D3)
	is_true("one direction can reach two: the top hidden under a box, and the face going up it",
		found.has(under_the_box) and found.has(up_the_box) and found.size() == 2)
	is_true("  a covered face still works", connects(r, floor_wire, under_the_box, D3))
	free_room(r)


func connections_in_2d() -> void:
	section("2D: what can be seen from above")

	var r := room([[c(2,2,2)]])
	var low := wire(r, c(1,2,-1), TOP, [POS_X])
	var high := wire(r, c(2,2,2), TOP, [NEG_X])
	is_true("tops connect whatever their heights", connects(r, low, high, D2))
	is_true("  which they do not in 3D", not connects(r, low, high, D3))
	free_room(r)

	r = room([[c(2,2,0)]])
	var under := wire(r, c(2,2,-1), TOP, [NEG_X])
	var beside := wire(r, c(1,2,-1), TOP, [POS_X])
	is_true("a wire under a box does not exist", not r.index.is_powerable_considered(under, D2) and not connects(r, beside, under, D2))
	free_room(r)

	# Una pared de tres, con cables en la cara que da a -x, sobre el piso.
	r = room([[c(2,2,0), c(2,2,1), c(2,2,2)], [c(2,3,0), c(2,3,1), c(2,3,2)]])
	var on_the_floor := wire(r, c(1,2,-1), TOP, [POS_X])
	var low_on_the_wall := wire(r, c(2,2,0), FACE_NEG_X, [DOWN])
	var high_on_the_wall := wire(r, c(2,2,2), FACE_NEG_X, [UP, POS_Y])
	var on_top_of_the_wall := wire(r, c(2,2,2), TOP, [NEG_X])
	var along_the_wall := wire(r, c(2,3,1), FACE_NEG_X, [NEG_Y])
	is_true("a wire on a wall over a lower column exists in 2D", r.index.is_powerable_considered(low_on_the_wall, D2))
	is_true("  and meets the floor in front, as an inner corner seen from above", connects(r, low_on_the_wall, on_the_floor, D2))
	is_true("  up the wall, it meets the top of its own column", connects(r, high_on_the_wall, on_top_of_the_wall, D2))
	is_true("  along the wall, the next column's wire, whatever their heights", connects(r, high_on_the_wall, along_the_wall, D2))
	is_true("  which in 3D are a cell apart", not connects(r, high_on_the_wall, along_the_wall, D3))
	add_boxes(r, "Overhang", [c(1,2,3)], false)
	is_true("a wire on a wall under an overhang does not exist in 2D", not r.index.is_powerable_considered(low_on_the_wall, D2))
	free_room(r)

	r = room([[c(2,2,3)]])
	var covered := plate(r, c(2,2,-1), [NEG_X])
	var next_to_it := wire(r, c(1,2,-1), TOP, [POS_X])
	is_true("a plate under a box still takes part", r.index.is_powerable_considered(covered, D2))
	is_true("  and connects to the tops beside it", connects(r, covered, next_to_it, D2))
	free_room(r)


func pressing() -> void:
	section("what presses a plate")

	var r := room([])
	var p := plate(r, c(2,2,-1), [])
	is_true("3D: the player standing on it", r.index.is_pressed(p, D3, c(2,2,0)))
	is_true("  not the player beside it", not r.index.is_pressed(p, D3, c(1,2,0)))
	is_true("  nor high above it", not r.index.is_pressed(p, D3, c(2,2,3)))
	is_true("2D: the player on its tile, whatever the height", r.index.is_pressed(p, D2, c(2,2,7)))
	is_true("  nothing at all", not r.index.is_pressed(p, D2, NOBODY))
	add_boxes(r, "Resting", [c(2,2,0)], false)
	is_true("3D: a box resting on it", r.index.is_pressed(p, D3, NOBODY))
	free_room(r)

	r = room([[c(2,2,3)]])
	p = plate(r, c(2,2,-1), [])
	is_true("3D: a box high above does not press it", not r.index.is_pressed(p, D3, NOBODY))
	is_true("2D: it does, since height does not exist there", r.index.is_pressed(p, D2, NOBODY))
	free_room(r)

	r = room([[c(2,2,0)]])
	var on_a_side := wire(r, c(2,2,0), FACE_POS_X, [])
	is_true("a face other than the top is never pressed", not r.index.is_pressed(on_a_side, D3, c(3,2,0)))
	free_room(r)


func activity() -> void:
	section("which powerables are active")

	var r := room([])
	var source := button(r, c(0,2,-1), [POS_X], true)
	var first := wire(r, c(1,2,-1), TOP, [NEG_X, POS_X])
	var second := wire(r, c(2,2,-1), TOP, [NEG_X, POS_X])
	var end := door(r, c(3,2,-1), Box.Facing.POS_Y, [NEG_X, POS_X])
	var past_the_door := wire(r, c(4,2,-1), TOP, [NEG_X])
	var active := r.index.active_powerables(D3, NOBODY)
	is_true("a switched-on button powers a chain of wires", active.has(source) and active.has(first) and active.has(second))
	is_true("  and the door at its end", active.has(end))
	is_true("  which passes nothing on", not active.has(past_the_door))
	source.switched_on = false
	is_true("switched off, nothing is active", r.index.active_powerables(D3, NOBODY).is_empty())
	free_room(r)

	r = room([])
	var start := button(r, c(0,1,-1), [POS_X], false)
	var loop: Array[Powerable] = [
		wire(r, c(1,1,-1), TOP, [NEG_X, POS_X, POS_Y]),
		wire(r, c(2,1,-1), TOP, [NEG_X, POS_Y]),
		wire(r, c(2,2,-1), TOP, [NEG_X, NEG_Y]),
		wire(r, c(1,2,-1), TOP, [POS_X, NEG_Y]),
	]
	is_true("a loop of wires never powers itself", r.index.active_powerables(D3, NOBODY).is_empty())
	start.switched_on = true
	same("  a button lights all of it", count_active(r, loop, D3), 4)
	start.switched_on = false
	same("  and switched off again, nothing in it stays on", count_active(r, loop, D3), 0)
	free_room(r)

	r = room([])
	button(r, c(1,2,-1), [POS_X], true)
	var switched_off := button(r, c(2,2,-1), [NEG_X, POS_X], false)
	var pressed_by_nobody := plate(r, c(3,2,-1), [NEG_X])
	active = r.index.active_powerables(D3, NOBODY)
	is_true("a signal never switches a button on", not active.has(switched_off))
	is_true("  nor presses a plate", not active.has(pressed_by_nobody))
	free_room(r)

	r = room([[c(2,2,0)]])
	var hidden := button(r, c(2,2,-1), [POS_X], true)
	is_true("a switched-on button under a box is active in 3D", is_active(r, hidden, D3))
	is_true("  but does not exist in 2D", not is_active(r, hidden, D2))
	free_room(r)


func the_four_use_cases() -> void:
	section("the four use cases")

	# Un pilar con cables en las tapas al pie de cada lado y uno encima, ninguno por sus paredes.
	var r := room([[c(2,2,0), c(2,2,1), c(2,2,2)]])
	button(r, c(0,2,-1), [POS_X], true)
	var before_the_pillar := wire(r, c(1,2,-1), TOP, [NEG_X, POS_X])
	var over_the_pillar := wire(r, c(2,2,2), TOP, [NEG_X, POS_X])
	var past_the_pillar := wire(r, c(3,2,-1), TOP, [NEG_X, POS_X])
	is_true("1. 3D: the signal stops at the foot of the pillar",
		is_active(r, before_the_pillar, D3) and not is_active(r, over_the_pillar, D3) and not is_active(r, past_the_pillar, D3))
	is_true("   2D: it goes across the pillar's top", is_active(r, over_the_pillar, D2) and is_active(r, past_the_pillar, D2))
	free_room(r)

	# Un cable recto con un techo muy por encima de una de sus baldosas.
	r = room([[c(2,2,3)]])
	button(r, c(0,2,-1), [POS_X], true)
	var line: Array[Powerable] = []
	for x in range(1, 5):
		line.append(wire(r, c(x,2,-1), TOP, [NEG_X, POS_X]))
	same("2. 3D: the whole line is powered", count_active(r, line, D3), 4)
	is_true("   2D: only up to the roof", is_active(r, line[0], D2) and not is_active(r, line[1], D2) and not is_active(r, line[2], D2) and not is_active(r, line[3], D2))
	free_room(r)

	# Una placa con un techo muy por encima, y cables saliendo de ella que el techo no tapa.
	r = room([[c(2,2,3)]])
	plate(r, c(2,2,-1), [NEG_X, POS_X])
	var left := wire(r, c(1,2,-1), TOP, [POS_X])
	var right := wire(r, c(3,2,-1), TOP, [NEG_X])
	is_true("3. 3D: the wires light only while the plate is pressed",
		not is_active(r, left, D3) and is_active(r, left, D3, c(2,2,0)) and is_active(r, right, D3, c(2,2,0)))
	is_true("   2D: at once, because the roof is now on the plate", is_active(r, left, D2) and is_active(r, right, D2))
	free_room(r)

	r = room([[c(1,2,0)]])
	plate(r, c(2,2,-1), [POS_X])
	var lit_by_the_crate := wire(r, c(3,2,-1), TOP, [NEG_X])
	r.try_to_move_grabbed_box(at(r,1,2,0), E, D2)
	is_true("   a crate pushed onto a plate in 2D presses it in both views", is_active(r, lit_by_the_crate, D2) and is_active(r, lit_by_the_crate, D3))
	free_room(r)

	# Un cable con un tramo en una caja que se mueve.
	r = room([[c(0,2,0)], [c(1,2,0)], [c(2,2,0)], [c(3,2,0)]])
	button(r, c(0,2,0), [POS_X], true)
	wire(r, c(1,2,0), TOP, [NEG_X, POS_X])
	var moving := wire(r, c(2,2,0), TOP, [NEG_X, POS_X])
	var at_the_end := wire(r, c(3,2,0), TOP, [NEG_X])
	is_true("4. the line is whole", is_active(r, at_the_end, D3) and is_active(r, at_the_end, D2))
	r.try_to_move_grabbed_box(at(r,2,2,0), S, D3)
	is_true("   pushing a piece out breaks it", not is_active(r, moving, D3) and not is_active(r, at_the_end, D3) and not is_active(r, at_the_end, D2))
	r.try_to_move_grabbed_box(at(r,2,3,0), Vector2i(0,-1), D2)
	is_true("   pushing it back mends it", is_active(r, moving, D3) and is_active(r, at_the_end, D3) and is_active(r, at_the_end, D2))
	free_room(r)

	# Dos cajas puentean un hueco del cable del piso: en 3D subiendo y bajando por sus caras.
	r = room([[c(2,2,0)], [c(3,2,0)]])
	button(r, c(0,2,-1), [POS_X], true)
	wire(r, c(1,2,-1), TOP, [NEG_X, POS_X])
	wire(r, c(2,2,0), FACE_NEG_X, [DOWN, UP])
	wire(r, c(2,2,0), TOP, [NEG_X, POS_X])
	wire(r, c(3,2,0), TOP, [NEG_X, POS_X])
	wire(r, c(3,2,0), FACE_POS_X, [UP, DOWN])
	var past_the_bridge := wire(r, c(4,2,-1), TOP, [NEG_X])
	is_true("   crates with wires on their tops and outer sides bridge a gap in both views",
		is_active(r, past_the_bridge, D3) and is_active(r, past_the_bridge, D2))
	r.try_to_move_grabbed_box(at(r,2,2,0), S, D3)
	is_true("   pushing one out breaks the bridge", not is_active(r, past_the_bridge, D3) and not is_active(r, past_the_bridge, D2))
	free_room(r)

	r = room([[c(2,2,0)]])
	button(r, c(0,2,-1), [POS_X], true)
	wire(r, c(1,2,-1), TOP, [NEG_X, POS_X])
	wire(r, c(2,2,0), TOP, [NEG_X, POS_X])
	past_the_bridge = wire(r, c(3,2,-1), TOP, [NEG_X])
	is_true("   a crate with a wire on its top only bridges in 2D", not is_active(r, past_the_bridge, D3) and is_active(r, past_the_bridge, D2))
	free_room(r)


func running_power() -> void:
	section("the room works power out and reacts")

	var r := room([])
	var b := button(r, c(1,2,-1), [POS_X], false)
	var w := wire(r, c(2,2,-1), TOP, [NEG_X, POS_X])
	var d := door(r, c(3,2,-1), Box.Facing.POS_Y, [NEG_X])
	var changes := [0]
	r.power_changed.connect(func() -> void: changes[0] += 1)
	r.update_power(D3, NOBODY, NO_BODY)
	same("with nothing on, nothing is announced", changes[0], 0)
	is_true("  and the door is drawn closed", d._slab.visible)
	r.press(b)
	r.update_power(D3, NOBODY, NO_BODY)
	same("a change is announced once", changes[0], 1)
	is_true("  the wire lights up", w._dots.albedo_color == Wire.LIT_RED)
	is_true("  and the open door is not drawn", not d._slab.visible)
	r.update_power(D3, NOBODY, NO_BODY)
	same("working it out again with nothing new announces nothing", changes[0], 1)
	r.press(b)
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("switched off, the wire goes dark and the door closes", w._dots.albedo_color == Wire.DARK and d._slab.visible)
	free_room(r)


func doors() -> void:
	section("doors open, closed and held open")

	var r := room([])
	var d := door(r, c(3,2,-1), Box.Facing.NEG_X, [POS_X])
	var b := button(r, c(4,2,-1), [NEG_X], false)
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("an unpowered door is closed, and the index knows it", r.index.closed_doors.has(d))
	b.switched_on = true
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("a powered one is open", not r.index.closed_doors.has(d))
	b.switched_on = false
	d.always_open = true
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("one authored always open needs no signal", not r.index.closed_doors.has(d))
	free_room(r)

	r = room([[c(3,2,0)]])
	d = door(r, c(3,2,-1), Box.Facing.NEG_X, [])
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("a box in its cell holds it open", not r.index.closed_doors.has(d))
	free_room(r)

	r = room([])
	d = door(r, c(3,2,-1), Box.Facing.NEG_X, [])
	var across_the_edge := Rect2(2.7, 2.2, 0.6, 0.6)
	r.update_power(D3, c(3,2,0), across_the_edge)
	is_true("the player's body across its edge holds it open", not r.index.closed_doors.has(d))
	is_true("  and the room keeps checking it", r.doors_stopped_by_the_player.has(d))
	r.update_power(D3, c(3,2,2), across_the_edge)
	is_true("  but not from another height", r.index.closed_doors.has(d) and r.doors_stopped_by_the_player.is_empty())
	r.update_power(D3, c(3,2,0), Rect2(3.2, 2.2, 0.6, 0.6))
	is_true("  it closes once the body is clear", r.index.closed_doors.has(d) and r.doors_stopped_by_the_player.is_empty())
	free_room(r)

	r = room([])
	d = door(r, c(3,2,-1), Box.Facing.NEG_X, [])
	r.rebuild_index()
	r.update_power(D3, NOBODY, NO_BODY)
	r.rebuild_index()
	is_true("rebuilding the index keeps the closed doors", r.index.closed_doors.has(d))
	free_room(r)


func doors_in_the_move_rules() -> void:
	section("a closed door keeps every box out of its cell")

	var r := room([[c(4,2,0)]])
	var d := door(r, c(3,2,-1), Box.Facing.NEG_X, [])
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("a box cannot be pushed in", not r.try_to_move_grabbed_box(at(r,4,2,0), W, D3))
	d.always_open = true
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("  but into an open one it can", r.try_to_move_grabbed_box(at(r,4,2,0), W, D3))
	d.always_open = false
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("  and then holds it open", not r.index.closed_doors.has(d))
	free_room(r)

	# Plataforma, pilar, un jinete apoyado en los dos, y una caja con una puerta al lado del pilar.
	r = room([[c(4,2,0)], [c(3,2,0)], [c(3,2,1), c(4,2,1)], [c(3,3,0)]])
	d = door(r, c(3,3,0), Box.Facing.POS_Y, [])
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("a rider that would enter it stays behind", r.try_to_move_grabbed_box(at(r,4,2,0), S, D3))
	is_true("  the platform moved and the rider did not", r.index.cells_3D.has(c(4,3,0)) and r.index.cells_3D.has(c(3,2,1)) and r.index.cells_3D.has(c(4,2,1)))
	free_room(r)

	r = room([[c(4,2,0)], [c(3,2,0)], [c(3,2,1), c(4,2,1)], [c(3,3,0)]])
	d = door(r, c(3,3,0), Box.Facing.POS_Y, [])
	d.always_open = true
	r.update_power(D3, NOBODY, NO_BODY)
	r.try_to_move_grabbed_box(at(r,4,2,0), S, D3)
	is_true("  with the door open it comes along", r.index.cells_3D.has(c(3,3,1)) and r.index.cells_3D.has(c(4,3,1)))
	free_room(r)

	r = room([[c(2,2,0)], [c(3,2,1)]])
	d = door(r, c(2,2,0), Box.Facing.POS_X, [])
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("a door's own box may not carry its cell under a box", not r.try_to_move_grabbed_box(at(r,2,2,0), E, D3))
	d.always_open = true
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("  unless the door is open", r.try_to_move_grabbed_box(at(r,2,2,0), E, D3))
	free_room(r)

	r = room([[c(2,2,0)], [c(3,2,0)]], [], [1])
	d = door(r, c(3,2,0), Box.Facing.NEG_X, [])
	r.update_power(D2, NOBODY, NO_BODY)
	is_true("2D: a box may not land in a closed doorway", not r.try_to_move_grabbed_box(at(r,2,2,0), E, D2))
	d.always_open = true
	r.update_power(D2, NOBODY, NO_BODY)
	is_true("  but may in an open one", r.try_to_move_grabbed_box(at(r,2,2,0), E, D2) and r.index.cells_3D.has(c(3,2,1)))
	free_room(r)

	r = room([[c(1,2,0), c(1,3,0)]])
	plate(r, c(2,2,-1), [POS_Y])
	d = door(r, c(2,3,-1), Box.Facing.NEG_X, [NEG_Y])
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("moves judge doors as before: one the move itself would open still blocks it",
		not r.try_to_move_grabbed_box(at(r,1,2,0), E, D3))
	free_room(r)


func doors_and_the_player() -> void:
	section("a closed door is a wall for the player")

	var r := room([])
	var d := door(r, c(3,2,-1), Box.Facing.NEG_X, [])
	r.update_power(D3, NOBODY, NO_BODY)
	same("3D: at the player's level it is an edge collider", r.index.colliders_plane(0, D3).get(Vector2i(3,2)), [LevelIndex.ColliderType.NEG_X])
	same("2D: on a top, too", r.index.colliders_plane(0, D2).get(Vector2i(3,2)), [LevelIndex.ColliderType.NEG_X])
	d.always_open = true
	r.update_power(D3, NOBODY, NO_BODY)
	is_true("  open, it is not", not r.index.colliders_plane(0, D3).has(Vector2i(3,2)))
	free_room(r)

	r = room([[c(3,2,3)]], [], [0])
	d = door(r, c(3,2,-1), Box.Facing.NEG_X, [])
	r.update_power(D2, NOBODY, NO_BODY)
	is_true("2D: hidden under a box, it is not there at all", not r.index.colliders_plane(0, D2).has(Vector2i(3,2)))
	free_room(r)

	r = room([[c(4,2,0)]])
	d = door(r, c(3,2,-1), Box.Facing.POS_X, [])
	r.update_power(D3, c(3,2,0), body_in(Vector2i(3,2)))
	is_true("a push may not step the player across a closed door", not r.move_grabbed_box(at(r,4,2,0), E, c(3,2,0), D3))
	free_room(r)

	r = room([[c(4,2,0)]])
	d = door(r, c(2,2,-1), Box.Facing.POS_X, [])
	r.update_power(D3, c(3,2,0), body_in(Vector2i(3,2)))
	is_true("a pull may not step the player back across one", not r.move_grabbed_box(at(r,4,2,0), W, c(3,2,0), D3))
	d.always_open = true
	r.update_power(D3, c(3,2,0), body_in(Vector2i(3,2)))
	is_true("  open, it may", r.move_grabbed_box(at(r,4,2,0), W, c(3,2,0), D3))
	free_room(r)

	r = room([[c(4,2,0)]])
	handle_3d(at(r,4,2,0), Box.Facing.NEG_X)
	d = door(r, c(3,2,-1), Box.Facing.POS_X, [])
	r.update_power(D3, c(3,2,0), body_in(Vector2i(3,2)))
	is_true("E does not reach through a closed door on the player's own edge", r.index.choose_what_to_interact_with(c(3,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)]], [], [0])
	at(r,3,2,0).movable_2d_neg_x = true
	d = door(r, c(3,2,0), Box.Facing.NEG_X, [])
	r.update_power(D2, c(2,2,0), body_in(Vector2i(2,2)))
	is_true("2D: nor through one on the far side of the edge", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D2) == null)
	d.always_open = true
	r.update_power(D2, c(2,2,0), body_in(Vector2i(2,2)))
	same("  open, it does", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D2), at(r,3,2,0))
	free_room(r)


func buttons() -> void:
	section("buttons on E")

	var r := room([])
	var b := button(r, c(3,2,-1), [], false)
	same("3D: a button on top of the floor beside the player", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3), b)
	add_boxes(r, "OnIt", [c(3,2,0)], false)
	is_true("  but not with a box on it", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,2)]])
	b = button(r, c(3,2,2), [], false)
	same("2D: a button on the neighbouring top, whatever its height", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D2), b)
	is_true("3D: one high above the player is out of reach", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)]], [], [0])
	at(r,3,2,0).movable_2d_neg_x = true
	b = button(r, c(3,2,0), [], false)
	same("2D: a button wins over a handle on the edge of its tile", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D2), b)
	free_room(r)

	r = room([[c(2,3,0)]])
	handle_3d(at(r,2,3,0), Box.Facing.NEG_Y)
	b = button(r, c(3,2,-1), [], false)
	same("buttons and handles are ranked together by facing", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(0,1), D3), at(r,2,3,0))
	same("  and the one faced wins", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3), b)
	free_room(r)

	r = room([])
	b = button(r, c(3,2,-1), [POS_X], false)
	var w := wire(r, c(4,2,-1), TOP, [NEG_X])
	var announced := [0]
	r.buttons_changed.connect(func() -> void: announced[0] += 1)
	var before := r.button_states()
	r.press(b)
	is_true("a press switches it on, and the room announces it", b.switched_on and announced[0] == 1)
	is_true("  so its wire is powered", is_active(r, w, D3))
	r.press(b)
	is_true("another press switches it off", not b.switched_on and not is_active(r, w, D3))
	r.press(b)
	r.restore(r.box_cells(), before, r.powerables_displayed_as_on())
	is_true("restoring puts it back as it was", not b.switched_on)
	same("  and announces it", announced[0], 4)
	free_room(r)


func button_pedestals() -> void:
	section("a button's pedestal is in the player's way")

	var r := room([])
	button(r, c(3,2,-1), [], false)
	same("3D: at the player's level it is an obstacle in the middle of its tile", r.index.colliders_plane(0, D3).get(Vector2i(3,2)), [LevelIndex.ColliderType.BUTTON])
	same("2D: on a top, too", r.index.colliders_plane(0, D2).get(Vector2i(3,2)), [LevelIndex.ColliderType.BUTTON])
	free_room(r)

	r = room([[c(3,2,1)]], [], [0])
	button(r, c(3,2,-1), [], false)
	is_true("3D: standing on a platform above it, it is not in the way", not r.index.colliders_plane(2, D3).has(Vector2i(3,2)))
	is_true("2D: hidden under a box, it is not there at all", not r.index.colliders_plane(0, D2).has(Vector2i(3,2)))
	free_room(r)

	r = room([[c(4,2,0)]])
	button(r, c(2,2,-1), [], false)
	is_true("a pull may not step the player back onto a button's tile", not r.move_grabbed_box(at(r,4,2,0), W, c(3,2,0), D3))
	free_room(r)

	r = room([])
	button(r, c(2,2,-1), [], false)
	is_true("a spawn point on a button's tile is flagged", has_warning(r, "cannot stand at player_spawn_point"))
	free_room(r)


func wall_buttons() -> void:
	section("buttons on walls")

	var r := room([[c(3,2,0), c(3,2,1)]])
	var b := button(r, c(3,2,0), [], false, FACE_NEG_X)
	same("3D: a button on the face of the box beside, looking at the player", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3), b)
	same("2D: the same button, seen from above over the player's tile", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D2), b)
	var higher := button(r, c(3,2,1), [], false, FACE_NEG_X)
	same("3D: one a level up is out of reach", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3), b)
	same("2D: with several in the column, the highest: it covers the others", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D2), higher)
	is_true("it has no hitbox: the tile in front stays free", not r.index.colliders_plane(0, D3).has(Vector2i(2,2)))
	free_room(r)

	r = room([[c(3,2,0)]])
	button(r, c(3,2,0), [], false, Powerable.Face.NEG_Y)
	is_true("one on another face of that box is not reached", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)]])
	handle_3d(at(r,3,2,0), Box.Facing.NEG_X)
	b = button(r, c(3,2,0), [], false, FACE_NEG_X)
	same("a button wins over a handle on its face", r.index.choose_what_to_interact_with(c(2,2,0), Vector2(1,0), D3), b)
	free_room(r)

	r = room([[c(3,2,0), c(3,2,1)], [c(2,2,0)]], [], [1])
	button(r, c(3,2,0), [], false, FACE_NEG_X)
	is_true("2D: not when the player's column covers it", r.index.choose_what_to_interact_with(c(2,2,1), Vector2(1,0), D2) == null)
	free_room(r)

	r = room([[c(3,2,0), c(3,3,0)]])
	button(r, c(3,2,0), [POS_Y], true, FACE_NEG_X)
	var w := wire(r, c(3,3,0), FACE_NEG_X, [NEG_Y])
	is_true("switched on, it powers the wall wire beside it", is_active(r, w, D3))
	is_true("  in 2D too, both seen from above", is_active(r, w, D2))
	free_room(r)


func where_a_beam_goes() -> void:
	section("lasers: where a beam goes")

	var r := room([[c(1,2,0)], [c(4,2,0)]])
	var e := emitter(r, c(1,2,0), FACE_POS_X, [], true)
	var target := receiver(r, c(4,2,0), FACE_NEG_X, [])
	settle(r, D3)
	same("a beam runs out of its face until the first box", r.beams[0].length, 2.0)
	same("  and hits what is on that box's face", r.beams[0].hits, target)
	is_true("  which makes a receiver active", is_active(r, target, D3, NOBODY, r.index.hit_by_lasers(r.beams, D3, 0, NO_BODY)))
	is_true("an emitter passes no power to its wires", not e.TRANSMITS)
	add_boxes(r, "InTheWay", [c(3,2,0)], false)
	settle(r, D3)
	is_true("a box pushed into it stops it there", r.beams[0].length == 1.0 and r.beams[0].hits == null)
	free_room(r)

	r = room([[c(1,2,0), c(1,2,1), c(1,2,2)], [c(3,2,0)], [c(5,2,0), c(5,2,1), c(5,2,2)]])
	emitter(r, c(1,2,2), FACE_POS_X, [], true)
	target = receiver(r, c(5,2,2), FACE_NEG_X, [])
	settle(r, D3)
	is_true("a beam high up passes over lower boxes", r.beams[0].hits == target)
	settle(r, D2)
	is_true("  in 2D too: nothing covers it from above", r.beams[0].hits == target)
	free_room(r)

	# El arco: un dintel muy por encima del camino del rayo.
	r = room([[c(1,2,0)], [c(5,2,0)], [c(3,2,2)]])
	emitter(r, c(1,2,0), FACE_POS_X, [], true)
	target = receiver(r, c(5,2,0), FACE_NEG_X, [])
	settle(r, D3)
	is_true("3D: a beam passes under an arch", r.beams[0].hits == target)
	settle(r, D2)
	is_true("2D: the arch's top covers it and stops it", r.beams[0].length == 1.0 and r.beams[0].hits == null)
	free_room(r)

	r = room([[c(1,2,0)], [c(2,2,2)]])
	var hidden := emitter(r, c(1,2,0), FACE_POS_X, [], true)
	is_true("2D: an emitter whose face is covered from above does not exist", not r.index.is_powerable_considered(hidden, D2))
	free_room(r)

	r = room([[c(1,2,0)], [c(5,2,0)]])
	emitter(r, c(1,2,0), FACE_POS_X, [], true)
	receiver(r, c(5,2,0), FACE_NEG_X, [])
	var across := door(r, c(3,2,-1), Box.Facing.NEG_X, [])
	settle(r, D3)
	same("a closed door standing across its path stops it at its strip", r.beams[0].length, 1.0)
	across.always_open = true
	settle(r, D3)
	same("  an open one lets it through", r.beams[0].length, 3.0)
	across.always_open = false
	across.edge = Box.Facing.POS_Y
	settle(r, D3)
	same("  and a closed one along the side of its path does not touch it", r.beams[0].length, 3.0)
	free_room(r)

	r = room([[c(1,2,0)], [c(5,2,0)]])
	emitter(r, c(1,2,0), FACE_POS_X, [], true)
	button(r, c(3,2,-1), [], false)
	settle(r, D3)
	same("a button's pedestal stops it", r.beams[0].length, 1.0 + (1.0 - ButtonPowerable.STAND_WIDTH) / 2.0)
	free_room(r)

	r = room([[c(1,2,0)]])
	emitter(r, c(1,2,0), FACE_POS_X, [], true)
	settle(r, D3)
	same("with nothing in the way it stops at its longest", r.beams[0].length, float(LevelIndex.MIN_BEAM_LENGTH))
	free_room(r)


func lasers_in_power() -> void:
	section("lasers: emitters and receivers in power")

	# Un botón alimenta un emisor; su rayo llega a un receptor cableado a una puerta fuera del camino.
	var r := room([[c(1,2,0)], [c(4,2,0)]])
	var b := button(r, c(2,1,-1), [POS_Y], false)
	wire(r, c(2,2,-1), TOP, [NEG_X, NEG_Y])
	var e := emitter(r, c(1,2,0), FACE_POS_X, [DOWN], false)
	receiver(r, c(4,2,0), FACE_NEG_X, [DOWN])
	wire(r, c(3,2,-1), TOP, [POS_X, POS_Y])
	var d := door(r, c(3,3,-1), Box.Facing.POS_X, [NEG_Y])
	settle(r, D3)
	is_true("an emitter that is not always on needs power", r.beams.is_empty() and r.index.closed_doors.has(d))
	b.switched_on = true
	settle(r, D3)
	is_true("  powered, it shines", r.beams.size() == 1 and r.beams[0].emitter == e)
	is_true("  and the receiver it hits passes the signal on to its wires: the door opens", not r.index.closed_doors.has(d))
	free_room(r)

	r = room([[c(1,2,0)]])
	var on_a_side := emitter(r, c(1,2,0), FACE_POS_X, [], true)
	same("emitters only offer the four sides", faces_offered(on_a_side), "POS_X:2,NEG_X:3,POS_Y:4,NEG_Y:5")
	same("  and so do receivers", faces_offered(receiver(r, c(1,2,0), FACE_NEG_X, [])), "POS_X:2,NEG_X:3,POS_Y:4,NEG_Y:5")
	free_room(r)


func beams_and_the_player() -> void:
	section("lasers: the player's body")

	var r := room([[c(1,2,0)], [c(5,2,0)]])
	emitter(r, c(1,2,0), FACE_POS_X, [], true)
	var target := receiver(r, c(5,2,0), FACE_NEG_X, [])
	settle(r, D3)
	var beam: LevelIndex.Beam = r.beams[0]
	is_true("3D: the body at the beam's height cuts it at its near edge", is_equal_approx(r.index.beam_length_with_the_body(beam, D3, 0, body_in(Vector2i(3,2))), 1.2))
	is_true("  and the receiver is not hit", not r.index.hit_by_lasers(r.beams, D3, 0, body_in(Vector2i(3,2))).has(target))
	same("  at another height it does not", r.index.beam_length_with_the_body(beam, D3, 2, body_in(Vector2i(3,2))), beam.length)
	same("  nor beside the beam's line", r.index.beam_length_with_the_body(beam, D3, 0, body_in(Vector2i(3,3))), beam.length)
	is_true("the room notices when the body steps into a beam", r.is_power_out_of_date(D3, 0, body_in(Vector2i(3,2))))
	is_true("  and not while nothing changes", not r.is_power_out_of_date(D3, 0, NO_BODY))
	settle(r, D2)
	is_true("2D: the body cuts it at any height", is_equal_approx(r.index.beam_length_with_the_body(r.beams[0], D2, 7, body_in(Vector2i(3,2))), 1.2))
	free_room(r)


func a_door_held_by_its_own_laser() -> void:
	section("lasers: a door held open by its own laser")

	# Un emisor, una puerta atravesada en el camino, y detrás un receptor que alimenta la puerta. Un
	# botón es la otra manera de abrirla.
	var r := room([[c(0,2,0)], [c(4,2,0)]])
	emitter(r, c(0,2,0), FACE_POS_X, [], true)
	var target := receiver(r, c(4,2,0), FACE_NEG_X, [DOWN])
	wire(r, c(3,2,-1), TOP, [NEG_X, POS_X])
	var d := door(r, c(2,2,-1), Box.Facing.NEG_X, [POS_X, NEG_Y])
	var b := button(r, c(2,1,-1), [POS_Y], false)
	settle(r, D3)
	is_true("closed, the door stops the laser", r.index.closed_doors.has(d) and not is_active(r, target, D3, NOBODY, r.index.hit_by_lasers(r.beams, D3, 0, NO_BODY)))
	b.switched_on = true
	settle(r, D3)
	is_true("the button opens it, and the laser comes through to the receiver", not r.index.closed_doors.has(d) and r.beams[0].hits == target)
	b.switched_on = false
	settle(r, D3)
	is_true("  the button off, the laser holds it open", not r.index.closed_doors.has(d))
	settle(r, D3, c(1,2,0), body_in(Vector2i(1,2)))
	is_true("stepping into the laser closes it", r.index.closed_doors.has(d))
	settle(r, D3)
	is_true("  and stepping out leaves it closed: the door stops the laser again", r.index.closed_doors.has(d))
	free_room(r)

	r = room([[c(0,2,0)], [c(4,2,0)]])
	emitter(r, c(0,2,0), FACE_POS_X, [], true)
	receiver(r, c(4,2,0), FACE_NEG_X, [DOWN])
	wire(r, c(3,2,-1), TOP, [NEG_X, POS_X])
	d = door(r, c(2,2,-1), Box.Facing.NEG_X, [POS_X, NEG_Y])
	b = button(r, c(2,1,-1), [POS_Y], false)
	settle(r, D3)
	var buttons_before := r.button_states()
	var power_before := r.powerables_displayed_as_on()
	b.switched_on = true
	settle(r, D3)
	b.switched_on = false
	settle(r, D3)
	r.restore(r.box_cells(), buttons_before, power_before)
	is_true("restoring a moment before it opened shows it closed at once", r.index.closed_doors.has(d) and not r.powerables_displayed_as_on().has(d))
	settle(r, D3)
	is_true("  and the laser does not hold it: it stays closed", r.index.closed_doors.has(d))
	free_room(r)


func emitter(r: Room, cell: Vector3i, face: Powerable.Face, directions: Array, always_on: bool) -> LaserEmitter:
	var new_emitter := LaserEmitter.new()
	new_emitter.always_on = always_on
	return put(r, cell, new_emitter, face, directions) as LaserEmitter

func receiver(r: Room, cell: Vector3i, face: Powerable.Face, directions: Array) -> LaserReceiver:
	return put(r, cell, LaserReceiver.new(), face, directions) as LaserReceiver

## Calcula hasta que nada quede pendiente, como el Level lo hace frame a frame.
func settle(r: Room, perspective: Room.Perspective, player_cell := NOBODY, player_body := NO_BODY) -> void:
	for attempt in 5:
		r.update_power(perspective, player_cell, player_body)
		if not r.is_power_out_of_date(perspective, player_cell.z, player_body):
			return
	fail("power did not settle")

## Las caras que el inspector ofrece para `face`.
func faces_offered(powerable: Powerable) -> String:
	for property in powerable.get_property_list():
		if property.name == "face":
			return property.hint_string
	return ""


func wire(r: Room, cell: Vector3i, face: Powerable.Face, directions: Array) -> Wire:
	return put(r, cell, Wire.new(), face, directions) as Wire

func plate(r: Room, cell: Vector3i, directions: Array) -> PressurePlate:
	return put(r, cell, PressurePlate.new(), TOP, directions) as PressurePlate

func button(r: Room, cell: Vector3i, directions: Array, switched_on: bool, face := TOP) -> ButtonPowerable:
	var new_button := ButtonPowerable.new()
	new_button.switched_on = switched_on
	return put(r, cell, new_button, face, directions) as ButtonPowerable

func door(r: Room, cell: Vector3i, edge: Box.Facing, directions: Array) -> Door:
	var new_door := Door.new()
	new_door.edge = edge
	return put(r, cell, new_door, TOP, directions) as Door

func put(r: Room, cell: Vector3i, powerable: Powerable, face: Powerable.Face, directions: Array) -> Powerable:
	powerable.face = face
	for checkbox: StringName in directions:
		powerable.set(checkbox, true)
	at(r, cell.x, cell.y, cell.z).add_child(powerable)
	return powerable

func is_active(r: Room, powerable: Powerable, perspective: Room.Perspective, player_cell := NOBODY, hit_by_lasers: Dictionary[Powerable, bool] = {}) -> bool:
	return r.index.active_powerables(perspective, player_cell, hit_by_lasers).has(powerable)

func count_active(r: Room, powerables: Array[Powerable], perspective: Room.Perspective) -> int:
	var active := r.index.active_powerables(perspective, NOBODY)
	return powerables.filter(func(powerable: Powerable) -> bool: return active.has(powerable)).size()

## Los dos lados se ven: una conexión que va en un solo sentido es un error.
func connects(r: Room, a: Powerable, b: Powerable, perspective: Room.Perspective) -> bool:
	return r.index.connected_powerables(a, perspective).has(b) and r.index.connected_powerables(b, perspective).has(a)

## El cuerpo del jugador centrado en esa columna, visto desde arriba.
func body_in(column: Vector2i) -> Rect2:
	return Rect2(Vector2(column) + Vector2(0.2, 0.2), Vector2(0.6, 0.6))

func hidden_in_inspector(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if property.name == property_name:
			return property.usage & PROPERTY_USAGE_EDITOR == 0
	return true


func add_folder(parent: Node, folder_name: String, cell: Vector3i) -> GridEntity:
	var folder := GridEntity.new()
	folder.name = folder_name
	folder.cell = cell
	parent.add_child(folder)
	return folder

func add_structure(parent: Node, structure_name: String, cell: Vector3i, box_cells: Array) -> Structure:
	var s := Structure.new()
	s.name = structure_name
	s.cell = cell
	parent.add_child(s)
	for box_cell: Vector3i in box_cells:
		var b := Structure.BOX_SCENE.instantiate() as Box
		b.cell = box_cell
		s.add_child(b)
	return s


func has_warning(node: Node, fragment: String) -> bool:
	for warning in node._get_configuration_warnings():
		if warning.contains(fragment):
			return true
	return false

func keep_height(r: Room, cells: Array) -> void:
	for cell: Vector3i in cells:
		at(r, cell.x, cell.y, cell.z).keeps_height = true


func c(x: int, y: int, z: int) -> Vector3i:
	return Vector3i(x, y, z)

func at(r: Room, x: int, y: int, z: int) -> Box:
	return r.index.cells_3D[Vector3i(x, y, z)]

func ring() -> Array:
	return [c(0,0,0), c(1,0,0), c(2,0,0), c(2,1,0), c(2,2,0), c(1,2,0), c(0,2,0), c(0,1,0)]

func cube() -> Array:
	return [c(0,0,0), c(1,0,0), c(0,1,0), c(1,1,0), c(0,0,1), c(1,0,1), c(0,1,1), c(1,1,1)]

func handle_3d(box: Box, face: Box.Facing) -> void:
	match face:
		Box.Facing.POS_X: box.movable_3d_pos_x = true
		Box.Facing.NEG_X: box.movable_3d_neg_x = true
		Box.Facing.POS_Y: box.movable_3d_pos_y = true
		Box.Facing.NEG_Y: box.movable_3d_neg_y = true

func add_perspective_manager(r: Room) -> PerspectiveManager:
	var manager := PerspectiveManager.new()
	manager.name = "PerspectiveManager"
	r.add_child(manager)
	return manager

func add_colliders_plane(r: Room) -> CollidersPlane:
	var plane := CollidersPlane.new()
	r.add_child(plane)
	return plane

## Cada columna tiene justo los colliders que pide colliders_plane, y ninguna otra tiene alguno.
func plane_matches_its_room(plane: CollidersPlane, r: Room) -> bool:
	var answer := r.index.colliders_plane(r.perspective_manager.height, r.perspective_manager.current)
	for x in range(-3, ROOM_SIZE.x + 3):
		for y in range(-3, ROOM_SIZE.y + 3):
			var wanted: Array = answer.get(Vector2i(x, y), [])
			for type: LevelIndex.ColliderType in LevelIndex.ColliderType.values():
				if plane.has_collider(Vector2i(x, y), type) != wanted.has(type):
					return false
	return true

func interior_entries(plane: Dictionary) -> int:
	var count := 0
	for x in ROOM_SIZE.x:
		for y in ROOM_SIZE.y:
			if plane.has(Vector2i(x, y)):
				count += 1
	return count

## Un duplicado en una lista devuelta tiene que ser una falla, no un acierto silencioso.
func no_duplicates(label: String, boxes: Array[Box]) -> void:
	var seen := {}
	for box in boxes:
		seen[box] = true
	if seen.size() != boxes.size():
		fail("%s: %d duplicates in the returned list" % [label, boxes.size() - seen.size()])

func connected(label: String, groups: Array, seed: Vector3i, perspective: Room.Perspective, expected: int) -> void:
	var r := room(groups)
	var found := r.index.boxes_of_same_structure_connected_to(r.index.cells_3D[seed], perspective)
	no_duplicates(label, found)
	same(label, found.size(), expected)
	free_room(r)

func grabbed(label: String, groups: Array, seed: Vector3i, perspective: Room.Perspective, expected: int) -> void:
	var r := room(groups)
	var found := r.index.boxes_grabbed_along_with(r.index.cells_3D[seed], perspective)
	no_duplicates(label, found)
	same(label, found.size(), expected)
	free_room(r)

func unit_size(label: String, groups: Array, seed: Vector3i, direction: Vector2i, perspective: Room.Perspective, expected: int) -> void:
	var r := room(groups)
	var found := r.index.boxes_that_would_move(r.index.cells_3D[seed], direction, perspective)
	no_duplicates(label, found)
	same(label, found.size(), expected)
	free_room(r)


func room(groups: Array, wall_groups := [], walkable_groups := [], size := ROOM_SIZE) -> Room:
	var r := Room.new()
	r.name = "Room"
	var shell := RoomShell.new()
	shell.name = "RoomShell"
	r.add_child(shell)
	root.add_child(r)
	r.dimensions = size

	for i in range(groups.size()):
		var s := Structure.new()
		s.name = "S%d" % i
		r.add_child(s)
		for cell: Vector3i in groups[i]:
			var b := Structure.BOX_SCENE.instantiate() as Box
			b.cell = cell
			b.is_wall = i in wall_groups
			b.walkable = i in walkable_groups
			s.add_child(b)

	r.rebuild_index()
	return r

func add_boxes(r: Room, group_name: String, cells: Array, walls: bool) -> void:
	var s := Structure.new()
	s.name = group_name
	r.add_child(s)
	for cell: Vector3i in cells:
		var b := Structure.BOX_SCENE.instantiate() as Box
		b.cell = cell
		b.is_wall = walls
		s.add_child(b)
	r.rebuild_index()

func remove_box(r: Room, cell: Vector3i) -> void:
	var box := r.index.cells_3D[cell]
	box.get_parent().remove_child(box)
	box.queue_free()
	r.rebuild_index()

func free_room(r: Room) -> void:
	root.remove_child(r)
	r.free()


func section(title: String) -> void:
	print("\n  %s" % title)

func same(label: String, got: Variant, want: Variant) -> void:
	if got == want:
		pass_case(label, got)
	else:
		fail("%s — got %s, want %s" % [label, got, want])

func is_true(label: String, got: bool) -> void:
	if got:
		pass_case(label, true)
	else:
		fail("%s — expected true" % label)

func pass_case(label: String, got: Variant) -> void:
	passed += 1
	print("    ok    %-60s %s" % [label, got])

func fail(message: String) -> void:
	failed += 1
	_failures.append(message)
	print("    FAIL  %s" % message)

func failures() -> Array[String]:
	return _failures
