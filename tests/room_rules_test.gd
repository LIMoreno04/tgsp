extends RefCounted

## Todas las reglas del Room. Se corre con `tests/run_tests.gd`.
##
## Cada caso arma una sala desde cero, la usa y la tira. Las salas llevan el RoomShell,
## así que el piso está en z = -1 y las paredes en x = -1 e y = -1, igual que en un nivel.

const ROOM_SIZE := Vector3i(6, 6, 4)

const E := Vector2i(1, 0)
const W := Vector2i(-1, 0)
const D3 := Room.Perspective.ISO_3D
const D2 := Room.Perspective.TOP_2D

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
	staying_connected()
	player_queries()
	grabbing()
	moving_with_a_player()
	colliders()


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

	var r := room([[c(0,0,0)], [c(0,0,1)], [c(1,0,1)]])
	is_true("the push happens even though the rider is dropped", r.try_to_move_grabbed_box(at(r,0,0,0), E, D3))
	is_true("  the platform moved", r.cells_3D.has(c(1,0,0)))
	is_true("  the rider stayed", r.cells_3D.has(c(0,0,1)))
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


func colliders() -> void:
	section("the collision plane")

	var r := room([])
	var plane := r.colliders_plane(0, D3)
	same("the open far edge is solid", plane.get(Vector2i(6,3)), [])
	same("the wall line is solid", plane.get(Vector2i(-1,3)), [])
	same("the near corner is solid", plane.get(Vector2i(-1,-1)), [])
	same("the far corner is solid", plane.get(Vector2i(6,6)), [])
	is_true("nothing beyond the ring", not plane.has(Vector2i(7,3)))
	is_true("open floor needs no collider", not plane.has(Vector2i(3,3)))
	same("high above, every interior column is solid", interior_entries(r.colliders_plane(5, D3)), 36)
	free_room(r)

	r = room([[c(3,3,0)]])
	same("3D: a crate at your height is solid", r.colliders_plane(0, D3).get(Vector2i(3,3)), [])
	same("2D: a non-walkable top is solid", r.colliders_plane(0, D2).get(Vector2i(3,3)), [])
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	is_true("3D: on top of a walkable crate is open", not r.colliders_plane(1, D3).has(Vector2i(3,3)))
	same("3D: but inside it is solid", r.colliders_plane(0, D3).get(Vector2i(3,3)), [])
	is_true("2D: a walkable top is open", not r.colliders_plane(0, D2).has(Vector2i(3,3)))
	free_room(r)

	r = room([[c(3,3,0)]])
	at(r,3,3,0).movable_2d_whole_face = true
	r.rebuild_index()
	same("2D: a whole-face grabbable tile is solid", r.colliders_plane(0, D2).get(Vector2i(3,3)), [])
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	at(r,3,3,0).movable_2d_pos_x = true
	r.rebuild_index()
	same("one stripe, one edge", r.colliders_plane(0, D2).get(Vector2i(3,3)), [Box.Facing.POS_X])
	is_true("3D reports no edges", not r.colliders_plane(1, D3).has(Vector2i(3,3)))
	free_room(r)

	r = room([[c(3,3,0)]], [], [0])
	at(r,3,3,0).movable_2d_pos_x = true
	at(r,3,3,0).movable_2d_neg_y = true
	r.rebuild_index()
	var edges: Array = r.colliders_plane(0, D2).get(Vector2i(3,3))
	same("two stripes, two edges", edges.size(), 2)
	is_true("  both of them", edges.has(Box.Facing.POS_X) and edges.has(Box.Facing.NEG_Y))
	free_room(r)

	# Un agujero se hace con una caja no caminable debajo del piso, así la columna existe.
	r = room([])
	remove_box(r, c(3,3,-1))
	add_boxes(r, "HoleMarker", [c(3,3,-2)], false)
	same("2D: a marked hole is solid", r.colliders_plane(0, D2).get(Vector2i(3,3)), [])
	same("3D: a marked hole is solid", r.colliders_plane(0, D3).get(Vector2i(3,3)), [])
	is_true("  its neighbours stay open", not r.colliders_plane(0, D3).has(Vector2i(3,2)))
	free_room(r)

	r = room([])
	remove_box(r, c(2,2,-1))
	is_true("an unmarked hole is invisible to the plane", not r.colliders_plane(0, D3).has(Vector2i(2,2)))
	free_room(r)


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


func room(groups: Array, wall_groups := [], walkable_groups := []) -> Room:
	var r := Room.new()
	r.name = "Room"
	var shell := RoomShell.new()
	shell.name = "RoomShell"
	r.add_child(shell)
	root.add_child(r)
	r.dimensions = ROOM_SIZE

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
