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
const SOLID := Room.ColliderType.SOLID

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
	refusals()
	landing_2d()
	floor_to_floor_2d()
	staying_connected()
	player_queries()
	grabbing()
	moving_with_a_player()
	colliders()
	perspective_toggle()
	colliders_plane_node()
	keeping_the_height()
	structure_warnings()
	folders()


func index() -> void:
	section("the index")

	var r := room([[c(1,1,0)]])
	is_true("a box in a structure is indexed by its world cell", r.cells_3D.has(c(1,1,0)))
	is_true("the shell is indexed too", r.cells_3D.has(c(0,0,-1)))
	same("grid_2D keeps the highest box of the column", r.grid_2D[Vector2i(1,1)], at(r,1,1,0))
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
	is_true("a box under an offset structure lands at cell + parent cell", r.cells_3D.has(c(3,2,1)))
	same("  and world_cell agrees", b.world_cell, c(3,2,1))
	free_room(r)

	r = room([[c(1,1,0)]])
	var moving: Array[Box] = [at(r,1,1,0)]
	var after := r.index.moved(moving, Vector3i(1,0,0))
	is_true("an index after a move has the box at its new cell", after.cells_3D.has(c(2,1,0)) and not after.cells_3D.has(c(1,1,0)))
	is_true("  and the room's own index is untouched", r.cells_3D.has(c(1,1,0)))
	free_room(r)

	r = room([[c(1,1,0)]])
	r.try_to_move_grabbed_box(at(r,1,1,0), E, D3)
	is_true("after a move the old cell is empty", not r.cells_3D.has(c(1,1,0)))
	is_true("  the new cell is filled", r.cells_3D.has(c(2,1,0)))
	same("  and grid_2D followed", r.grid_2D[Vector2i(2,1)], r.cells_3D[c(2,1,0)])
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
		if r.boxes_of_same_structure_connected_to(r.cells_3D[cell], D3).size() != 8:
			all_eight = false
	is_true("every box of the ring sees all eight", all_eight)
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
	is_true("  and the buried half did not move", r.cells_3D.has(c(0,0,0)))
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
	is_true("  and nothing moved", r.cells_3D.has(c(0,0,0)) and r.cells_3D.has(c(0,0,1)))
	free_room(r)

	r = room([[c(0,0,0), c(1,0,0)], [c(1,0,1)], [c(2,0,1)]], [2])
	is_true("a longer platform slides partly out from under it", r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  the platform moved", r.cells_3D.has(c(2,0,0)))
	is_true("  the rider stayed, still resting on the platform", r.cells_3D.has(c(1,0,1)) and r.cells_3D.has(c(1,0,0)))
	is_true("  but not all the way out", not r.try_to_move_grabbed_box(at(r,1,0,0), E, D3))
	free_room(r)

	r = room([[c(0,0,0), c(1,0,0)], [c(1,0,1), c(1,1,1)], [c(0,1,0), c(1,1,0), c(2,1,0), c(2,1,1)]], [2])
	is_true("unloading: a crate also resting on a ledge is caught by the ledge's end", r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  and the platform can leave it on the ledge",
		r.try_to_move_grabbed_box(at(r,1,0,0), E, D3) and r.cells_3D.has(c(1,0,1)) and not r.cells_3D.has(c(1,0,0)))
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
	same("a wall never joins the unit", r.boxes_that_would_move(at(r,0,0,0), E, D3).size(), 2)
	is_true("  so the platform can still be pushed out", r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  and the wall is left floating", r.cells_3D.has(c(0,0,1)))
	free_room(r)


func refusals() -> void:
	section("refusals")

	var r := room([[c(0,0,0)], [c(1,0,0)]])
	is_true("a blocked grabbed structure refuses", not r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  and nothing moved", r.cells_3D.has(c(0,0,0)) and r.cells_3D.has(c(1,0,0)))
	free_room(r)

	r = room([[c(0,0,0), c(1,0,0)], [c(2,0,0)]])
	is_true("blocked past the far end refuses", not r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	free_room(r)

	r = room([[c(0,0,0)], [c(1,0,0)]])
	is_true("2D: a non-walkable landing refuses", not r.try_to_move_grabbed_box(at(r,0,0,0), E, D2))
	free_room(r)

	r = room([[c(5,0,0)]])
	is_true("2D: the void refuses", not r.try_to_move_grabbed_box(at(r,5,0,0), E, D2))
	is_true("  and it stayed", r.cells_3D.has(c(5,0,0)))
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
	is_true("flat ground keeps its height", r.cells_3D.has(c(1,0,0)))
	free_room(r)

	r = room([[c(0,0,0)], [c(1,0,0)]], [], [1])
	r.try_to_move_grabbed_box(at(r,0,0,0), E, D2)
	is_true("it climbs onto a walkable step", r.cells_3D.has(c(1,0,1)))
	is_true("  and the step is untouched", r.cells_3D.has(c(1,0,0)))
	free_room(r)

	r = room([[c(0,0,0), c(0,0,1)], [c(1,0,0)]], [], [1])
	is_true("a two-tall unit climbs", r.try_to_move_grabbed_box(at(r,0,0,1), E, D2))
	is_true("  bottom at z = 1", r.cells_3D.has(c(1,0,1)))
	is_true("  top at z = 2, shape kept", r.cells_3D.has(c(1,0,2)))
	free_room(r)

	r = room([[c(0,0,3)]])
	is_true("a floating tile drops", r.try_to_move_grabbed_box(at(r,0,0,3), E, D2))
	is_true("  onto the floor at z = 0", r.cells_3D.has(c(1,0,0)))
	free_room(r)

	r = room([[c(0,0,0), c(0,1,0)], [c(1,1,0)]], [], [1])
	var before := r.cells_3D.size()
	is_true("a wide unit rises by the most demanding column", r.try_to_move_grabbed_box(at(r,0,0,0), E, D2))
	is_true("  the stepped column landed on top", r.cells_3D.has(c(1,1,1)))
	is_true("  the flat column rose with it", r.cells_3D.has(c(1,0,1)))
	same("  no box lost or duplicated", r.cells_3D.size(), before)
	free_room(r)


func staying_connected() -> void:
	section("a unit may hang over the void, but not float free")

	# El piso va de 0 a 5, así que una caja sola corrida de la última columna no toca nada.
	var r := room([[c(5,2,0)]])
	is_true("a lone box cannot be pushed off the edge", not r.try_to_move_grabbed_box(at(r,5,2,0), E, D3))
	is_true("  and it stayed", r.cells_3D.has(c(5,2,0)))
	free_room(r)

	r = room([[c(3,2,0), c(4,2,0), c(5,2,0)]])
	is_true("a structure may cantilever over the void", r.try_to_move_grabbed_box(at(r,3,2,0), E, D3))
	is_true("  its far end is over the void", r.cells_3D.has(c(6,2,0)))
	is_true("  and its near end still on the floor", r.cells_3D.has(c(4,2,0)))
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0)]])
	is_true("the first push out is fine", r.try_to_move_grabbed_box(at(r,4,2,0), E, D3))
	is_true("the one that would free it is refused", not r.try_to_move_grabbed_box(at(r,5,2,0), E, D3))
	is_true("  so it stayed where it was", r.cells_3D.has(c(5,2,0)) and r.cells_3D.has(c(6,2,0)))
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0)]])
	r.try_to_move_grabbed_box(at(r,4,2,0), E, D3)
	is_true("it can be pulled back toward land", r.try_to_move_grabbed_box(at(r,5,2,0), W, D3))
	is_true("  and is back over the floor", r.cells_3D.has(c(4,2,0)))
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
	is_true("  so it stays", r.cells_3D.has(c(2,2,1)))
	is_true("  but in 3D the crate under it carries it along", r.try_to_move_grabbed_box(at(r,2,2,0), E, D3) and r.cells_3D.has(c(3,2,1)))
	free_room(r)

	r = room([[c(2,2,0)], [c(2,2,1)]], [], [0])
	is_true("a crate on a walkable platform can be pulled off it", r.try_to_move_grabbed_box(at(r,2,2,1), W, D2) and r.cells_3D.has(c(1,2,0)))
	is_true("  and pushed back onto it", r.try_to_move_grabbed_box(at(r,1,2,0), E, D2) and r.cells_3D.has(c(2,2,1)))
	free_room(r)

	r = room([[c(2,2,0)], [c(2,2,1)]], [0])
	is_true("a crate on a wall does not move in 2D", not r.try_to_move_grabbed_box(at(r,2,2,1), W, D2))
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0), c(6,2,0)]])
	is_true("a platform hanging over the void can be pulled back in 2D", r.try_to_move_grabbed_box(at(r,4,2,0), W, D2) and r.cells_3D.has(c(3,2,0)) and r.cells_3D.has(c(5,2,0)))
	is_true("  and pushed out over it again", r.try_to_move_grabbed_box(at(r,3,2,0), E, D2) and r.cells_3D.has(c(6,2,0)))
	is_true("  and further, while a box of it is still over the floor", r.try_to_move_grabbed_box(at(r,4,2,0), E, D2) and r.cells_3D.has(c(7,2,0)))
	is_true("  but not once none would be", not r.try_to_move_grabbed_box(at(r,5,2,0), E, D2) and r.cells_3D.has(c(5,2,0)))
	free_room(r)

	r = room([[c(1,2,0), c(2,2,0), c(3,2,0)]], [], [0])
	remove_box(r, c(4,2,-1))
	is_true("2D: a plank can be pushed out over a hole", r.try_to_move_grabbed_box(at(r,1,2,0), E, D2) and r.cells_3D.has(c(4,2,0)))
	is_true("  and across it, as a bridge", r.try_to_move_grabbed_box(at(r,2,2,0), E, D2) and r.cells_3D.has(c(5,2,0)))
	is_true("  which can be stood on over the hole", r.can_player_be_on(c(4,2,9), D2))
	free_room(r)

	r = room([[c(3,2,0)]])
	remove_box(r, c(4,2,-1))
	is_true("2D: a lone crate cannot be pushed into a hole", not r.try_to_move_grabbed_box(at(r,3,2,0), E, D2) and r.cells_3D.has(c(3,2,0)))
	free_room(r)

	r = room([[c(2,2,0)], [c(3,2,0)]], [], [1])
	remove_box(r, c(3,2,-1))
	is_true("2D: a crate cannot go onto something that is not walkable, hole or not", not r.try_to_move_grabbed_box(at(r,3,2,0), W, D2))
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0)], [c(5,2,1)]], [], [0])
	remove_box(r, c(5,2,-1))
	same("2D: a crate on a plank's tip over a hole hides the tip, so a pull takes only the near box",
		r.boxes_that_would_move(at(r,4,2,0), W, D2).size(), 1)
	is_true("  and is refused: the tip would stay over the hole holding the crate, attached to nothing",
		not r.try_to_move_grabbed_box(at(r,4,2,0), W, D2) and r.cells_3D.has(c(4,2,0)))
	is_true("  the crate can be moved off it, onto the floor beside", r.try_to_move_grabbed_box(at(r,5,2,1), S, D2) and r.cells_3D.has(c(5,3,0)))
	is_true("  and then the plank comes back whole",
		r.try_to_move_grabbed_box(at(r,4,2,0), W, D2) and r.cells_3D.has(c(3,2,0)) and r.cells_3D.has(c(4,2,0)))
	free_room(r)


func player_queries() -> void:
	section("player queries")

	var r := room([])
	is_true("3D: the shell floor can be stood on", r.can_player_be_on(c(2,2,0), D3))
	is_true("  the box below is the floor", r.floor_of(c(2,2,0), D3).is_floor)
	is_true("3D: nothing to stand on in mid air", not r.can_player_be_on(c(2,2,3), D3))
	is_true("3D: outside the room there is nowhere to stand", not r.can_player_be_on(c(9,9,0), D3))
	free_room(r)

	r = room([[c(2,2,0)]])
	is_true("3D: a box in your own cell blocks", not r.can_player_be_on(c(2,2,0), D3))
	is_true("3D: a non-walkable top cannot be stood on", not r.can_player_be_on(c(2,2,1), D3))
	is_true("2D: a non-walkable top cannot be stood on", not r.can_player_be_on(c(2,2,9), D2))
	is_true("something above the cell is occlusion", r.is_occluded(c(2,2,-1)))
	is_true("  nothing above a cell over the box", not r.is_occluded(c(2,2,1)))
	free_room(r)

	r = room([[c(2,2,0)]], [], [0])
	is_true("3D: on top of a walkable box", r.can_player_be_on(c(2,2,1), D3))
	is_true("2D: height is ignored, the top decides", r.can_player_be_on(c(2,2,9), D2))
	free_room(r)

	r = room([[c(2,2,0)]], [], [0])
	at(r,2,2,0).movable_2d_pos_x = true
	r.rebuild_index()
	is_true("2D: a stripe is a barrier on that side", r.has_grab_barrier(Vector2i(2,2), Box.Facing.POS_X, D2))
	is_true("  but not on the others", not r.has_grab_barrier(Vector2i(2,2), Box.Facing.NEG_X, D2))
	is_true("3D: there are no barriers", not r.has_grab_barrier(Vector2i(2,2), Box.Facing.POS_X, D3))
	free_room(r)


func grabbing() -> void:
	section("choosing what to grab")

	var r := room([[c(3,2,0)]])
	handle_3d(at(r,3,2,0), Box.Facing.NEG_X)
	r.rebuild_index()
	same("grabs the crate straight ahead", r.choose_box_to_grab(c(2,2,0), Vector2(1,0), D3), at(r,3,2,0))
	same("  a lone candidate behind is still grabbed", r.choose_box_to_grab(c(2,2,0), Vector2(-1,0), D3), at(r,3,2,0))
	is_true("3D ignores a neighbour below the player", r.choose_box_to_grab(c(2,2,1), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)]])
	handle_3d(at(r,3,2,0), Box.Facing.POS_X)
	r.rebuild_index()
	is_true("a handle on the far face is not grabbable", r.choose_box_to_grab(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)]])
	is_true("a box with no handles is not grabbable", r.choose_box_to_grab(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(3,2,0)], [c(2,3,0)]])
	handle_3d(at(r,3,2,0), Box.Facing.NEG_X)
	handle_3d(at(r,2,3,0), Box.Facing.NEG_Y)
	r.rebuild_index()
	same("facing east picks east", r.choose_box_to_grab(c(2,2,0), Vector2(1,0), D3), at(r,3,2,0))
	same("facing north picks north", r.choose_box_to_grab(c(2,2,0), Vector2(0,1), D3), at(r,2,3,0))
	same("a diagonal ties, and the fixed order settles it",
		r.choose_box_to_grab(c(2,2,0), Vector2(1,1).normalized(), D3), at(r,3,2,0))
	free_room(r)

	r = room([[c(3,2,3)]])
	at(r,3,2,3).movable_2d_neg_x = true
	r.rebuild_index()
	same("2D grabs the neighbouring top", r.choose_box_to_grab(c(2,2,0), Vector2(1,0), D2), at(r,3,2,3))
	is_true("  and the 3D handles are a separate set", r.choose_box_to_grab(c(2,2,0), Vector2(1,0), D3) == null)
	free_room(r)

	r = room([[c(2,2,0)], [c(3,2,0)]], [], [0])
	at(r,2,2,0).movable_2d_pos_x = true
	at(r,3,2,0).movable_2d_neg_x = true
	r.rebuild_index()
	is_true("2D: a stripe on your own tile blocks the grab",
		r.choose_box_to_grab(c(2,2,1), Vector2(1,0), D2) == null)
	at(r,2,2,0).movable_2d_pos_x = false
	r.rebuild_index()
	same("  with the stripe gone it is reachable",
		r.choose_box_to_grab(c(2,2,1), Vector2(1,0), D2), at(r,3,2,0))
	free_room(r)


func moving_with_a_player() -> void:
	section("pushing and pulling with a player")

	var r := room([[c(3,2,0)]])
	is_true("push succeeds", r.move_grabbed_box(at(r,3,2,0), E, c(2,2,0), D3))
	is_true("  the crate moved", r.cells_3D.has(c(4,2,0)))
	is_true("  and vacated the cell the player steps into", not r.cells_3D.has(c(3,2,0)))
	free_room(r)

	r = room([[c(3,2,0)]])
	is_true("pull succeeds", r.move_grabbed_box(at(r,3,2,0), W, c(2,2,0), D3))
	is_true("  the crate arrived where the player was", r.cells_3D.has(c(2,2,0)))
	free_room(r)

	r = room([[c(1,2,0)]])
	is_true("a pull with nothing behind the player is refused",
		not r.move_grabbed_box(at(r,1,2,0), W, c(0,2,0), D3))
	is_true("  and nothing moved", r.cells_3D.has(c(1,2,0)))
	free_room(r)

	r = room([[c(2,2,0), c(3,2,0)]], [], [0])
	is_true("you cannot move what you are standing on",
		not r.move_grabbed_box(at(r,3,2,0), E, c(2,2,1), D3))
	is_true("  and nothing moved", r.cells_3D.has(c(2,2,0)) and r.cells_3D.has(c(3,2,0)))
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
	is_true("  and nothing moved", r.cells_3D.has(c(3,2,1)))
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
	is_true("3D: stripes are no barrier to a step", not r.would_player_cross_a_stripe(c(2,2,1), E, r.index, D3))
	free_room(r)


func colliders() -> void:
	section("the collision plane")

	var r := room([])
	var plane := r.colliders_plane(0, D3)
	same("the open far edge is solid", plane.get(Vector2i(6,3)), [SOLID])
	same("the wall line is solid", plane.get(Vector2i(-1,3)), [SOLID])
	same("the near corner is solid", plane.get(Vector2i(-1,-1)), [SOLID])
	is_true("the far corner is left out, the edges beside it already close it", not plane.has(Vector2i(6,6)))
	is_true("nothing beyond the edge", not plane.has(Vector2i(7,3)))
	is_true("open floor needs no collider", not plane.has(Vector2i(3,3)))
	same("high above, every interior column is solid", interior_entries(r.colliders_plane(5, D3)), 36)
	free_room(r)

	r = room([[c(3,3,0)]])
	same("3D: a crate at your height is solid", r.colliders_plane(0, D3).get(Vector2i(3,3)), [SOLID])
	same("2D: a non-walkable top is solid", r.colliders_plane(0, D2).get(Vector2i(3,3)), [SOLID])
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	is_true("3D: on top of a walkable crate is open", not r.colliders_plane(1, D3).has(Vector2i(3,3)))
	same("3D: but inside it is solid", r.colliders_plane(0, D3).get(Vector2i(3,3)), [SOLID])
	is_true("2D: a walkable top is open", not r.colliders_plane(0, D2).has(Vector2i(3,3)))
	free_room(r)

	r = room([[c(3,3,0)]])
	at(r,3,3,0).movable_2d_whole_face = true
	r.rebuild_index()
	same("2D: a whole-face grabbable tile is solid", r.colliders_plane(0, D2).get(Vector2i(3,3)), [SOLID])
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	at(r,3,3,0).movable_2d_pos_x = true
	r.rebuild_index()
	same("one stripe, one edge", r.colliders_plane(0, D2).get(Vector2i(3,3)), [Room.ColliderType.POS_X])
	is_true("3D reports no edges", not r.colliders_plane(1, D3).has(Vector2i(3,3)))
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	at(r,3,3,0).movable_2d_pos_x = true
	at(r,3,3,0).movable_2d_neg_y = true
	r.rebuild_index()
	var edges: Array = r.colliders_plane(0, D2).get(Vector2i(3,3))
	same("two stripes, two edges", edges.size(), 2)
	is_true("  both of them", edges.has(Room.ColliderType.POS_X) and edges.has(Room.ColliderType.NEG_Y))
	free_room(r)

	r = room([])
	remove_box(r, c(2,2,-1))
	same("3D: a hole in the floor is solid", r.colliders_plane(0, D3).get(Vector2i(2,2)), [SOLID])
	same("2D: a hole in the floor is solid", r.colliders_plane(0, D2).get(Vector2i(2,2)), [SOLID])
	is_true("  its neighbours stay open", not r.colliders_plane(0, D3).has(Vector2i(2,1)))
	free_room(r)

	r = room([])
	remove_box(r, c(3,3,-1))
	add_boxes(r, "UnderTheHole", [c(3,3,-2)], false)
	same("a hole with a non-walkable box under it is solid too", r.colliders_plane(0, D2).get(Vector2i(3,3)), [SOLID])
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0), c(6,2,0)]], [], [0])
	is_true("3D: a platform hanging past the edge can be walked on", not r.colliders_plane(1, D3).has(Vector2i(6,2)))
	same("  the void past its end is solid", r.colliders_plane(1, D3).get(Vector2i(7,2)), [SOLID])
	same("  and the void beside it", r.colliders_plane(1, D3).get(Vector2i(6,3)), [SOLID])
	is_true("2D: the same platform can be walked on", not r.colliders_plane(0, D2).has(Vector2i(6,2)))
	same("  and the void past it is solid", r.colliders_plane(0, D2).get(Vector2i(7,2)), [SOLID])
	free_room(r)

	r = room([[c(4,2,0), c(5,2,0), c(6,2,0)]], [], [0])
	at(r,6,2,0).movable_2d_pos_x = true
	r.rebuild_index()
	plane = r.colliders_plane(0, D2)
	same("a stripe facing the void is an edge", plane.get(Vector2i(6,2)), [Room.ColliderType.POS_X])
	same("  and the void behind the stripe is still solid", plane.get(Vector2i(7,2)), [SOLID])
	free_room(r)

	r = room([], [], [], Vector3i(50, 50, 1))
	plane = r.colliders_plane(0, D3)
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

	r = room([])
	manager = add_perspective_manager(r)
	manager.block(r)
	is_true("nothing toggles while something holds the lock", not manager.toggle(Vector2i(2,2)) and manager.is_3d())
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
	is_true("2D: a stripe becomes its edge collider", plane.has_collider(Vector2i(3,3), Room.ColliderType.POS_X))
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
	is_true("2D: a platform that does not keep its height drops", r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.cells_3D.has(c(0,3,0)))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)]], [], [0])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	is_true("2D: one that keeps it slides along the wall at the same height",
		r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.cells_3D.has(c(0,3,2)) and r.cells_3D.has(c(1,3,2)))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)]], [], [0])
	keep_height(r, [c(1,2,2)])
	is_true("  one ticked box is enough for the whole platform", r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.cells_3D.has(c(0,3,2)))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)], [c(1,3,0), c(1,3,1), c(1,3,2)]], [], [0, 1])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	is_true("2D: a walkable step at its height lifts it, just enough",
		r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.cells_3D.has(c(0,3,3)) and r.cells_3D.has(c(1,3,3)))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)], [c(1,3,2)]], [], [0])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	is_true("2D: something not walkable in its way still refuses", not r.try_to_move_grabbed_box(at(r,0,2,2), S, D2))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)]], [], [0])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	remove_box(r, c(0,3,-1))
	is_true("2D: like in 3D, it slides over a hole while it touches the wall", r.try_to_move_grabbed_box(at(r,0,2,2), S, D2) and r.cells_3D.has(c(0,3,2)))
	free_room(r)

	r = room([[c(5,2,2)]], [], [0])
	keep_height(r, [c(5,2,2)])
	is_true("2D: but not out over the void touching nothing", not r.try_to_move_grabbed_box(at(r,5,2,2), E, D2))
	free_room(r)

	r = room([[c(0,2,2), c(1,2,2)]])
	keep_height(r, [c(0,2,2), c(1,2,2)])
	is_true("3D: it hangs from the wall while sliding along it", r.try_to_move_grabbed_box(at(r,0,2,2), S, D3) and r.cells_3D.has(c(0,3,2)))
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
	is_true("a structure in a folder lands at its cell plus the folder's", r.cells_3D.has(c(4,1,0)))
	is_true("  a loose box two folders deep too", r.cells_3D.has(c(4,4,0)))
	is_true("  a push moves it in the index", r.try_to_move_grabbed_box(at(r,4,1,0), E, D3) and r.cells_3D.has(c(5,1,0)) and not r.cells_3D.has(c(4,1,0)))
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
	is_true("a plain Node3D in the way hides what is in it from the rules", not r.cells_3D.has(c(1,1,0)) and not r.cells_3D.has(c(2,2,0)))
	is_true("  its structures say so", has_warning(s, "Plain, between this and the Room, is not a GridEntity"))
	is_true("  its loose boxes too", has_warning(loose, "is not a GridEntity"))
	is_true("  but a box in a structure leaves it to the structure", not has_warning(s.boxes()[0], "the rules skip"))
	free_room(r)


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


func has_warning(entity: GridEntity, fragment: String) -> bool:
	for warning in entity._get_configuration_warnings():
		if warning.contains(fragment):
			return true
	return false

func keep_height(r: Room, cells: Array) -> void:
	for cell: Vector3i in cells:
		at(r, cell.x, cell.y, cell.z).keeps_height = true


func c(x: int, y: int, z: int) -> Vector3i:
	return Vector3i(x, y, z)

func at(r: Room, x: int, y: int, z: int) -> Box:
	return r.cells_3D[Vector3i(x, y, z)]

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
	var answer := r.colliders_plane(r.perspective_manager.height, r.perspective_manager.current)
	for x in range(-3, ROOM_SIZE.x + 3):
		for y in range(-3, ROOM_SIZE.y + 3):
			var wanted: Array = answer.get(Vector2i(x, y), [])
			for type: Room.ColliderType in Room.ColliderType.values():
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
	var found := r.boxes_of_same_structure_connected_to(r.cells_3D[seed], perspective)
	no_duplicates(label, found)
	same(label, found.size(), expected)
	free_room(r)

func grabbed(label: String, groups: Array, seed: Vector3i, perspective: Room.Perspective, expected: int) -> void:
	var r := room(groups)
	var found := r.boxes_grabbed_along_with(r.cells_3D[seed], perspective)
	no_duplicates(label, found)
	same(label, found.size(), expected)
	free_room(r)

func unit_size(label: String, groups: Array, seed: Vector3i, direction: Vector2i, perspective: Room.Perspective, expected: int) -> void:
	var r := room(groups)
	var found := r.boxes_that_would_move(r.cells_3D[seed], direction, perspective)
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
	var box := r.cells_3D[cell]
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
