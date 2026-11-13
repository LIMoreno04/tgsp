"""Generate a TGSP level .tscn from a small spec (same node set as scenes/prefabs/level_template.tscn)."""
import zlib

EXT = [
    ('Script', 'uid://rovbkgf8ri0o', 'res://scripts/level/level.gd', '1_level'),
    ('Script', 'uid://c630yislkejxa', 'res://scripts/level/room.gd', '2_room'),
    ('Script', 'uid://cakmikmmduvo3', 'res://scripts/level/room_shell.gd', '3_shell'),
    ('PackedScene', 'uid://d38ctwehqsiio', 'res://scenes/prefabs/structure.tscn', '4_structure'),
    ('PackedScene', 'uid://prbqftumc4bt', 'res://scenes/prefabs/box.tscn', '5_box'),
    ('Script', 'uid://c3lpk6otp7ahb', 'res://scripts/level/perspective_manager.gd', '6_perspective'),
    ('Script', 'uid://34nefn2ovu0c', 'res://scripts/level/projective_camera.gd', '7_camera'),
    ('PackedScene', 'uid://bu0alvofbamij', 'res://scenes/prefabs/colliders_plane.tscn', '8_plane'),
    ('PackedScene', 'uid://khw8mus60h1c', 'res://scenes/prefabs/player.tscn', '9_player'),
    ('PackedScene', None, 'res://scenes/prefabs/snow_particles.tscn', '10_snow'),
    ('Environment', None, 'res://scenes/prefabs/winter_environment.tres', '11_env'),
    ('PackedScene', 'uid://dn8niv2hjstao', 'res://scenes/prefabs/powerables/button.tscn', '12_button'),
    ('PackedScene', 'uid://bfoj6bh1nje5', 'res://scenes/prefabs/powerables/exit_door.tscn', '13_exit'),
    ('PackedScene', 'uid://cg1khe0lncw3c', 'res://scenes/prefabs/powerables/pressure_plate.tscn', '14_plate'),
    ('PackedScene', 'uid://c642hbaofr5wg', 'res://scenes/prefabs/powerables/wire.tscn', '15_wire'),
    ('PackedScene', 'uid://ddydvmksjpvpe', 'res://scenes/prefabs/powerables/door.tscn', '16_door'),
    ('PackedScene', 'uid://cli7rmi42uttb', 'res://scenes/prefabs/powerables/laser_emitter.tscn', '17_emitter'),
    ('PackedScene', 'uid://d1bltup8wtbbj', 'res://scenes/prefabs/powerables/laser_receiver.tscn', '18_receiver'),
]
PREFAB = {'Button': '12_button', 'ExitDoor': '13_exit', 'PressurePlate': '14_plate', 'Wire': '15_wire',
          'Door': '16_door', 'LaserEmitter': '17_emitter', 'LaserReceiver': '18_receiver'}
FACE = {'top': 0, 'bottom': 1, '+x': 2, '-x': 3, '+y': 4, '-y': 5}
EDGE = {'+x': 0, '-x': 1, '+y': 2, '-y': 3}
CONNECT = {'+x': 'connects_pos_x', '-x': 'connects_neg_x', '+y': 'connects_pos_y', '-y': 'connects_neg_y',
           'up': 'connects_up', 'down': 'connects_down'}
HANDLE3 = {'+x': 'movable_3d_pos_x', '-x': 'movable_3d_neg_x', '+y': 'movable_3d_pos_y', '-y': 'movable_3d_neg_y'}
HANDLE2 = {'+x': 'movable_2d_pos_x', '-x': 'movable_2d_neg_x', '+y': 'movable_2d_pos_y', '-y': 'movable_2d_neg_y'}


def uid(*key):
    return zlib.crc32(repr(key).encode()) & 0x7fffffff or 1


def cell_lines(cell):
    x, y, z = cell
    if cell == (0, 0, 0):
        return []
    return [f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, {z}, {y})", f"cell = Vector3i({x}, {y}, {z})"]


def powerable_lines(kind, p):
    lines = []
    if kind == 'ExitDoor' and p.get('next_level'):
        lines.append(f'next_level = "{p["next_level"]}"')
    if kind in ('Door', 'ExitDoor'):
        lines.append(f"edge = {EDGE[p['edge']]}")
        if p.get('always_open'):
            lines.append("always_open = true")
    if kind == 'LaserEmitter' and p.get('always_on'):
        lines.append("always_on = true")
    if p.get('face', 'top') != 'top':
        lines.append(f"face = {FACE[p['face']]}")
    for d in p.get('connects', []):
        lines.append(f"{CONNECT[d]} = true")
    return lines


def box_lines(flags):
    lines = []
    if flags.get('walkable') or flags.get('floor'):
        lines.append("walkable = true")
    if flags.get('wall'):
        lines.append("is_wall = true")
    if flags.get('floor'):
        lines.append("is_floor = true")
    if flags.get('keeps_height'):
        lines.append("keeps_height = true")
    if flags.get('half'):
        lines.append("top_half_only = true")
    for d in flags.get('h3', []):
        lines.append(f"{HANDLE3[d]} = true")
    if flags.get('h2') == 'all':
        lines.append("movable_2d_whole_face = true")
    else:
        for d in flags.get('h2', []):
            lines.append(f"{HANDLE2[d]} = true")
    return lines


def node(name, parent, lines, instance=None, type_=None, extra=''):
    head = f'[node name="{name}"'
    if type_:
        head += f' type="{type_}"'
    head += f' parent="{parent}" unique_id={uid(parent, name)}'
    if extra:
        head += ' ' + extra
    if instance:
        head += f' instance=ExtResource("{instance}")'
    head += ']'
    return "\n".join([head] + lines) + "\n"


def structure(name, parent, cell, dims, boxes, powerables):
    """boxes: {world_cell: flags}; powerables: {world_cell: [(kind, props), ...]}"""
    out = []
    lines = []
    if dims:
        lines.append(f"dimensions = Vector3i({dims[0]}, {dims[1]}, {dims[2]})")
    lines += cell_lines(cell)
    out.append(node(name, parent, lines, '4_structure'))
    path = f"{parent}/{name}"
    for i, (wc, flags) in enumerate(boxes.items()):
        bname = "Box" if i == 0 else f"Box{i + 1}"
        rel = (wc[0] - cell[0], wc[1] - cell[1], wc[2] - cell[2])
        out.append(node(bname, path, cell_lines(rel) + box_lines(flags), '5_box'))
        for kind, p in powerables.get(wc, []):
            out.append(node(p.get('name', kind), f"{path}/{bname}", powerable_lines(kind, p), PREFAB[kind]))
    return "".join(out)


def generate(spec):
    W, H, D = spec['dims']
    out = [f'[gd_scene format=3 uid="{spec["uid"]}"]\n\n']
    for type_, u, path, id_ in EXT:
        u_attr = f' uid="{u}"' if u else ''
        out.append(f'[ext_resource type="{type_}"{u_attr} path="{path}" id="{id_}"]\n')
    out.append("\n")
    out.append(node(spec['name'], None, [], None) if False else f'[node name="{spec["name"]}" type="Node3D" unique_id={uid("root", spec["name"])}]\nscript = ExtResource("1_level")\n\n')
    sx, sy, sz = spec['spawn']
    out.append(f'[node name="Room" type="Node3D" parent="." unique_id={uid("Room")}]\nscript = ExtResource("2_room")\ndimensions = Vector3i({W}, {H}, {D})\nplayer_spawn_point = Vector3i({sx}, {sy}, {sz})\n\n')
    out.append(f'[node name="RoomShell" type="Node3D" parent="Room" unique_id={uid("RoomShell")}]\nscript = ExtResource("3_shell")\n\n')
    pw = spec.get('floor_powerables', {})
    floor = {}
    for x in range(W):
        for y in range(H):
            if (x, y) not in spec.get('holes', []):
                floor[(x, y, -1)] = {'floor': True}
    out.append(structure('Floor', 'Room/RoomShell', (0, 0, -1), (W, H, 1), floor, pw))
    wallx = {(-1, y, z): {'wall': True} for y in range(-1, H) for z in range(-1, D)}
    out.append(structure('WallX', 'Room/RoomShell', (-1, -1, -1), (1, H + 1, D + 1), wallx, {}))
    wally = {(x, -1, z): {'wall': True} for x in range(W) for z in range(-1, D)}
    out.append(structure('WallY', 'Room/RoomShell', (0, -1, -1), (W, 1, D + 1), wally, {}))
    out.append(f'[node name="PerspectiveManager" type="Node" parent="Room" unique_id={uid("PerspectiveManager")}]\nscript = ExtResource("6_perspective")\n\n')
    out.append(f'[node name="ProjectiveCamera" type="Camera3D" parent="Room" unique_id={uid("ProjectiveCamera")} node_paths=PackedStringArray("light")]\n'
               'transform = Transform3D(0.70710677, -0.3535534, 0.61237246, 0, 0.86602545, 0.50000006, -0.70710677, -0.3535534, 0.61237246, 65.23724, 51.500008, 65.23724)\n'
               'projection = 1\ncurrent = true\nsize = 14.637111\nscript = ExtResource("7_camera")\nlight = NodePath("../../Sun")\n\n')
    out.append(f'[node name="CollidersPlane" parent="Room" unique_id={uid("CollidersPlane")} instance=ExtResource("8_plane")]\n\n')
    out.append(f'[node name="Player" parent="Room/CollidersPlane" unique_id={uid("Player")} node_paths=PackedStringArray("camera") instance=ExtResource("9_player")]\ncamera = NodePath("../../ProjectiveCamera")\n\n')
    out.append(f'[node name="SnowParticles" parent="Room" unique_id={uid("SnowParticles")} instance=ExtResource("10_snow")]\n\n')
    for s in spec['structures']:
        cells = list(s['boxes'].keys())
        lo = tuple(min(c[i] for c in cells) for i in range(3))
        hi = tuple(max(c[i] for c in cells) for i in range(3))
        dims = tuple(hi[i] - lo[i] + 1 for i in range(3))
        out.append(structure(s['name'], 'Room', lo, dims, s['boxes'], s.get('powerables', {})))
    out.append(f'[node name="Sun" type="DirectionalLight3D" parent="." unique_id={uid("Sun")}]\n'
               'transform = Transform3D(0.97040796, 0.19780174, -0.13850231, 0.068258576, 0.32547945, 0.9430821, 0.23162296, -0.9246283, 0.30234617, 0, 0, 0)\n'
               'light_color = Color(1, 0.968627, 0.921569, 1)\nlight_energy = 1.15\nshadow_enabled = true\nshadow_blur = 1.5\ndirectional_shadow_blend_splits = true\n\n')
    out.append(f'[node name="WorldEnvironment" type="WorldEnvironment" parent="." unique_id={uid("WorldEnvironment")}]\nenvironment = ExtResource("11_env")\n')
    return "".join(out)


def write(path, spec):
    open(path, "w", encoding="utf-8", newline="\n").write(generate(spec))
    print("wrote", path)
