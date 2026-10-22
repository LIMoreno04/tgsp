@tool
class_name BoxBrush
extends RefCounted
## Con qué pinta una brocha de cajas: el tipo, su alto, su forma y las banderas que le pone a cada
## caja. Cada tipo de la paleta empieza con los suyos; Pick hace uno "Custom" copiando una caja.

enum Kind { FLOOR, WALL, BLOCK, WALKABLE, MOVABLE, MOVABLE_3D, MOVABLE_2D, HANGING_PLATFORM, CUSTOM }
enum Shape { PAINT, RECTANGLE }

const PALETTE: Array[Kind] = [Kind.FLOOR, Kind.WALL, Kind.BLOCK, Kind.WALKABLE, Kind.MOVABLE, Kind.MOVABLE_3D, Kind.MOVABLE_2D, Kind.HANGING_PLATFORM]

const LABEL: Dictionary[Kind, String] = {
	Kind.FLOOR: "Floor",
	Kind.WALL: "Wall",
	Kind.BLOCK: "Block",
	Kind.WALKABLE: "Walkable",
	Kind.MOVABLE: "Movable",
	Kind.MOVABLE_3D: "3D movable",
	Kind.MOVABLE_2D: "2D movable",
	Kind.HANGING_PLATFORM: "Hanging platform",
	Kind.CUSTOM: "Custom",
}

## El nombre que Godot le da a un grupo nuevo de ese tipo (y numera si se repite).
const GROUP_NAME: Dictionary[Kind, String] = {
	Kind.FLOOR: "Floor",
	Kind.WALL: "Wall",
	Kind.BLOCK: "Block",
	Kind.WALKABLE: "Walkable",
	Kind.MOVABLE: "Movable",
	Kind.MOVABLE_3D: "Movable3D",
	Kind.MOVABLE_2D: "Movable2D",
	Kind.HANGING_PLATFORM: "HangingPlatform",
	Kind.CUSTOM: "Group",
}

const TOOLTIP: Dictionary[Kind, String] = {
	Kind.FLOOR: "Terrain with a floor tile on top: stood on, never moves.",
	Kind.WALL: "Terrain drawn with wall tiles: never moves.",
	Kind.BLOCK: "A plain box: pillars, roofs, arches, posts. Can't be stood on or grabbed.",
	Kind.WALKABLE: "Its top can be stood on. Give it 2D grab edges to make a platform that moves in 2D.",
	Kind.MOVABLE: "Grabbed from its sides in 3D and from its whole top in 2D.",
	Kind.MOVABLE_3D: "Grabbed from its sides in 3D only.",
	Kind.MOVABLE_2D: "Grabbed from its top in 2D only.",
	Kind.HANGING_PLATFORM: "A walkable platform that keeps its height: it hangs from what it touches. Drawn as its top half.",
	Kind.CUSTOM: "The exact settings of the box you picked.",
}

## Las banderas de una caja, en el orden en que se ponen: is_floor fuerza walkable, y walkable y la
## tapa entera se excluyen, así que el orden decide.
const BOX_FLAGS: Array[StringName] = [
	&"is_wall", &"is_floor", &"keeps_height", &"top_half_only",
	&"movable_3d_pos_x", &"movable_3d_neg_x", &"movable_3d_pos_y", &"movable_3d_neg_y",
	&"movable_2d_pos_x", &"movable_2d_neg_x", &"movable_2d_pos_y", &"movable_2d_neg_y",
	&"movable_2d_whole_face", &"walkable",
]

const SIDE_FLAG_3D: Dictionary[Box.Facing, StringName] = {
	Box.Facing.POS_X: &"movable_3d_pos_x",
	Box.Facing.NEG_X: &"movable_3d_neg_x",
	Box.Facing.POS_Y: &"movable_3d_pos_y",
	Box.Facing.NEG_Y: &"movable_3d_neg_y",
}
const EDGE_FLAG_2D: Dictionary[Box.Facing, StringName] = {
	Box.Facing.POS_X: &"movable_2d_pos_x",
	Box.Facing.NEG_X: &"movable_2d_neg_x",
	Box.Facing.POS_Y: &"movable_2d_pos_y",
	Box.Facing.NEG_Y: &"movable_2d_neg_y",
}

var kind := Kind.BLOCK
var height := 1
var shape := Shape.PAINT

var is_floor := false
var is_wall := false
var keeps_height := false
var top_half_only := false
## Caminable sólo la caja de arriba de cada columna, como deja "Mark exposed tops walkable".
var walkable_tops := false
var sides_3d: Dictionary[Box.Facing, bool] = _no_facings()
var whole_top_2d := false
var edges_2d: Dictionary[Box.Facing, bool] = _no_facings()
## En las plataformas caminables las rayas van sólo por fuera: adentro serían paredes en 2D.
var edges_2d_only_outside := false
## Para Custom: el grupo del que salió, para nombrar los grupos nuevos.
var picked_kind := Kind.CUSTOM


static func for_kind(brush_kind: Kind) -> BoxBrush:
	var brush := BoxBrush.new()
	brush.kind = brush_kind
	match brush_kind:
		Kind.FLOOR:
			brush.is_floor = true
		Kind.WALL:
			brush.is_wall = true
		Kind.WALKABLE:
			brush.walkable_tops = true
			brush.edges_2d_only_outside = true
		Kind.MOVABLE:
			brush.sides_3d = _all_facings()
			brush.whole_top_2d = true
		Kind.MOVABLE_3D:
			brush.sides_3d = _all_facings()
		Kind.MOVABLE_2D:
			brush.whole_top_2d = true
		Kind.HANGING_PLATFORM:
			brush.walkable_tops = true
			brush.keeps_height = true
			brush.top_half_only = true
			brush.edges_2d_only_outside = true
	return brush


static func picked_from(box: Box) -> BoxBrush:
	var brush := BoxBrush.new()
	brush.kind = Kind.CUSTOM
	brush.picked_kind = kind_of(box)
	brush.is_floor = box.is_floor
	brush.is_wall = box.is_wall
	brush.keeps_height = box.keeps_height
	brush.top_half_only = box.top_half_only
	brush.walkable_tops = box.walkable and not box.is_floor
	brush.whole_top_2d = box.movable_2d_whole_face
	for facing: Box.Facing in SIDE_FLAG_3D:
		brush.sides_3d[facing] = box.get(SIDE_FLAG_3D[facing])
		brush.edges_2d[facing] = box.get(EDGE_FLAG_2D[facing])
	brush.edges_2d_only_outside = box.walkable
	return brush


func copy() -> BoxBrush:
	var other := BoxBrush.new()
	for property in [&"kind", &"height", &"shape", &"is_floor", &"is_wall", &"keeps_height", &"top_half_only", &"walkable_tops", &"whole_top_2d", &"edges_2d_only_outside", &"picked_kind"]:
		other.set(property, get(property))
	other.sides_3d = sides_3d.duplicate()
	other.edges_2d = edges_2d.duplicate()
	return other


func label() -> String:
	if kind == Kind.CUSTOM:
		return "Custom (%s)" % LABEL[picked_kind]
	return LABEL[kind]

func group_name() -> String:
	return GROUP_NAME[picked_kind if kind == Kind.CUSTOM else kind]

func is_terrain() -> bool:
	return is_floor or is_wall

## Si la brocha deja tocar sus lados 3D y bordes 2D en la barra de opciones.
func has_handle_options() -> bool:
	return not is_terrain() and kind != Kind.BLOCK


## Las banderas de una caja pintada. `is_column_top`: si queda arriba de su columna en el trazo.
## `outside`: qué bordes de la tapa dan afuera del grupo, para las rayas sólo por fuera.
func flags_for(is_column_top: bool, outside: Dictionary[Box.Facing, bool]) -> Dictionary[StringName, bool]:
	var flags: Dictionary[StringName, bool] = {}
	for flag in BOX_FLAGS:
		flags[flag] = false
	flags[&"is_floor"] = is_floor
	flags[&"is_wall"] = is_wall
	flags[&"keeps_height"] = keeps_height
	flags[&"top_half_only"] = top_half_only
	flags[&"walkable"] = is_floor or (walkable_tops and is_column_top)
	if is_terrain():
		return flags
	for facing: Box.Facing in SIDE_FLAG_3D:
		flags[SIDE_FLAG_3D[facing]] = sides_3d[facing]
		var edge_wanted := edges_2d[facing]
		if edges_2d_only_outside and not outside.get(facing, true):
			edge_wanted = false
		flags[EDGE_FLAG_2D[facing]] = edge_wanted
	flags[&"movable_2d_whole_face"] = whole_top_2d and not flags[&"walkable"]
	return flags


## Lo que una caja parece ser, leído de sus banderas.
static func kind_of(box: Box) -> Kind:
	if box.is_floor:
		return Kind.FLOOR
	if box.is_wall:
		return Kind.WALL
	if box.keeps_height:
		return Kind.HANGING_PLATFORM
	var grabbed_in_3d := box.movable_3d_from_any_side()
	var grabbed_in_2d := box.movable_2d_whole_face
	for facing: Box.Facing in EDGE_FLAG_2D:
		grabbed_in_2d = grabbed_in_2d or box.get(EDGE_FLAG_2D[facing])
	if box.walkable and not grabbed_in_3d:
		return Kind.WALKABLE
	if grabbed_in_3d and grabbed_in_2d:
		return Kind.MOVABLE
	if grabbed_in_3d:
		return Kind.MOVABLE_3D
	if grabbed_in_2d:
		return Kind.MOVABLE_2D
	return Kind.BLOCK


## El tipo de un grupo, o "Mixed" si sus cajas no coinciden. Una columna caminable cuenta como
## Walkable aunque sólo su tapa lo sea.
static func label_of_group(boxes: Array[Box]) -> String:
	var kinds: Dictionary[Kind, bool] = {}
	for box in boxes:
		kinds[kind_of(box)] = true
	if kinds.has(Kind.WALKABLE) and kinds.size() == 2 and kinds.has(Kind.BLOCK):
		return LABEL[Kind.WALKABLE]
	if kinds.size() == 1:
		return LABEL[kinds.keys()[0]]
	if kinds.is_empty():
		return "Empty"
	return "Mixed"


static func _no_facings() -> Dictionary[Box.Facing, bool]:
	return {Box.Facing.POS_X: false, Box.Facing.NEG_X: false, Box.Facing.POS_Y: false, Box.Facing.NEG_Y: false}

static func _all_facings() -> Dictionary[Box.Facing, bool]:
	return {Box.Facing.POS_X: true, Box.Facing.NEG_X: true, Box.Facing.POS_Y: true, Box.Facing.NEG_Y: true}
