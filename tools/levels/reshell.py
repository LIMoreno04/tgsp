"""Rebuild a level's RoomShell so that Room.dimensions covers every terrain box: hand-made floor and
wall Structures that only extend the shell are folded into Floor / WallX / WallY, the Room's
dimensions are set to the real extent, and terrain outside the frame (x < -1 or y < -1) is dropped.
Usage: python reshell.py level.tscn [--dry]
"""
import sys
sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from merge_structures import parse, prop, set_prop, vec3i, node_info, HEADER


def is_set(block, name):
    return prop(block, name) == "true"


def reshell(path, dry):
    blocks = parse(open(path, encoding="utf-8").read())
    room = next(b for b in blocks if node_info(b) == ("Room", "."))
    structures = {}  # path -> (block, cell)
    for b in blocks:
        info = node_info(b)
        if info and info[1] in ("Room", "Room/RoomShell") and 'instance=' in b[0] and "structure.tscn" not in b[0]:
            pass
        if info and info[1] in ("Room", "Room/RoomShell") and prop(b, "dimensions") is not None or (info and info[1] == "Room/RoomShell"):
            structures[f"{info[1]}/{info[0]}"] = (b, vec3i(prop(b, "cell")))
    # every Structure under Room: anything with box children
    boxes = []  # dict(block, path, world, floor, wall, structure_path)
    for b in blocks:
        info = node_info(b)
        if not info:
            continue
        name, parent = info
        if parent in structures or (parent.startswith("Room/") and parent.count("/") == 1 and parent not in ("Room/RoomShell",)):
            if parent not in structures:
                sb = next((x for x in blocks if node_info(x) == (parent.split("/")[1], "Room")), None)
                if sb is None:
                    continue
                structures[parent] = (sb, vec3i(prop(sb, "cell")))
            if "box.tscn" not in b[0] and 'instance=' not in b[0]:
                continue
            sc = structures[parent][1]
            bc = vec3i(prop(b, "cell"))
            boxes.append({"block": b, "path": f"{parent}/{name}", "world": (sc[0] + bc[0], sc[1] + bc[1], sc[2] + bc[2]),
                          "floor": is_set(b, "is_floor"), "wall": is_set(b, "is_wall"), "structure": parent})
    terrain = [x for x in boxes if x["floor"] or x["wall"]]
    W = max(x["world"][0] for x in terrain if x["world"][0] >= 0) + 1
    H = max(x["world"][1] for x in terrain if x["world"][1] >= 0) + 1
    D = max(x["world"][2] for x in terrain if x["wall"] and (x["world"][0] == -1 or x["world"][1] == -1)) + 1
    old_dims = vec3i(prop(room, "dimensions"))
    print(f"{path}: dimensions {old_dims} -> {(W, H, D)}")

    def part_of(w):
        x, y, z = w
        if x < -1 or y < -1 or x >= W or y >= H:
            return "drop"
        if x == -1 and -1 <= z < D:
            return "Room/RoomShell/WallX"
        if y == -1 and -1 <= z < D:
            return "Room/RoomShell/WallY"
        if z == -1 and x >= 0 and y >= 0:
            return "Room/RoomShell/Floor"
        return None

    part_cells = {"Room/RoomShell/Floor": (0, 0, -1), "Room/RoomShell/WallX": (-1, -1, -1), "Room/RoomShell/WallY": (0, -1, -1)}
    part_dims = {"Room/RoomShell/Floor": (W, H, 1), "Room/RoomShell/WallX": (1, H + 1, D + 1), "Room/RoomShell/WallY": (W, 1, D + 1)}
    members = {p: [] for p in part_cells}
    dropped = []
    moved = 0
    for x in terrain:
        p = part_of(x["world"])
        if p == "drop":
            dropped.append(x)
        elif p is not None:
            members[p].append(x)
            if x["structure"] != p:
                moved += 1
    for x in dropped:
        kids = [b for b in blocks if node_info(b) and node_info(b)[1] == x["path"]]
        print(f"   drop {x['path']} at {x['world']}" + (f"  !! carries {len(kids)} children" if kids else ""))
        assert not kids, "a dropped box carries powerables; stop and look"
    for p in members:
        print(f"   {p.split('/')[-1]}: {len(members[p])} boxes")
    print(f"   {moved} boxes folded into the shell, {len(dropped)} dropped")
    if dry:
        return
    renames = {}
    for p, cell in part_cells.items():
        pb = structures[p][0]
        set_prop(pb, "dimensions", f"Vector3i({part_dims[p][0]}, {part_dims[p][1]}, {part_dims[p][2]})")
        set_prop(pb, "transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {cell[0]}, {cell[2]}, {cell[1]})" if cell != (0, 0, 0) else None)
        set_prop(pb, "cell", f"Vector3i({cell[0]}, {cell[1]}, {cell[2]})" if cell != (0, 0, 0) else None)
        for i, x in enumerate(members[p]):
            b = x["block"]
            new_name = "Box" if i == 0 else f"Box{i + 1}"
            rel = tuple(x["world"][k] - cell[k] for k in range(3))
            m = HEADER.match(b[0])
            b[0] = f'[node name="{new_name}" parent="{p}"{m.group(4)}]'
            set_prop(b, "transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {rel[0]}, {rel[2]}, {rel[1]})" if rel != (0, 0, 0) else None)
            set_prop(b, "cell", f"Vector3i({rel[0]}, {rel[1]}, {rel[2]})" if rel != (0, 0, 0) else None)
            renames[x["path"]] = f"{p}/{new_name}"
    for b in blocks:
        info = node_info(b)
        if info and info[1] in renames:
            b[0] = b[0].replace(f'parent="{info[1]}"', f'parent="{renames[info[1]]}"', 1)
    drop_blocks = {id(x["block"]) for x in dropped}
    kept_structures = {x["structure"] for x in boxes if id(x["block"]) not in drop_blocks and x["structure"] not in renames.values() and x["path"] not in renames}
    emptied = [s for s in structures if s.startswith("Room/") and s.count("/") == 1 and s not in kept_structures]
    for s in emptied:
        print(f"   delete emptied {s}")
    blocks = [b for b in blocks if id(b) not in drop_blocks and not (node_info(b) and f"{node_info(b)[1]}/{node_info(b)[0]}" in emptied)]
    set_prop(room, "dimensions", f"Vector3i({W}, {H}, {D})")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join("\n".join(b) for b in blocks))


if __name__ == "__main__":
    reshell(sys.argv[1], "--dry" in sys.argv)
