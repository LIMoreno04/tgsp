"""Split a Structure of a TGSP level .tscn: moves the named boxes into new Structures, keeping
world cells, and re-bases every structure touched (cell = lowest corner, dimensions = extent).
Usage:
  python split_structure.py level.tscn STRUCT[=NewName] NEW1=Box3,Box5 [NEW2=Box7 ...]
"""
import sys
sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from merge_structures import parse, prop, set_prop, vec3i, node_info, HEADER


def rebase(structure_block, name, boxes):
    lo = tuple(min(w[i] for _, w in boxes) for i in range(3))
    hi = tuple(max(w[i] for _, w in boxes) for i in range(3))
    set_prop(structure_block, "transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lo[0]}, {lo[2]}, {lo[1]})" if lo != (0, 0, 0) else None)
    set_prop(structure_block, "dimensions", f"Vector3i({hi[0]-lo[0]+1}, {hi[1]-lo[1]+1}, {hi[2]-lo[2]+1})")
    set_prop(structure_block, "cell", f"Vector3i({lo[0]}, {lo[1]}, {lo[2]})" if lo != (0, 0, 0) else None)
    renames = {}
    for i, (b, w) in enumerate(boxes):
        m = HEADER.match(b[0])
        old = f"{m.group(3)}/{m.group(1)}"
        new_box_name = "Box" if i == 0 else f"Box{i + 1}"
        rel = (w[0] - lo[0], w[1] - lo[1], w[2] - lo[2])
        b[0] = f'[node name="{new_box_name}" parent="Room/{name}"{m.group(4)}]'
        set_prop(b, "transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {rel[0]}, {rel[2]}, {rel[1]})" if rel != (0, 0, 0) else None)
        set_prop(b, "cell", f"Vector3i({rel[0]}, {rel[1]}, {rel[2]})" if rel != (0, 0, 0) else None)
        renames[old] = f"Room/{name}/{new_box_name}"
    return renames, lo, hi


def split(path, structure, new_name, pieces):
    text = open(path, encoding="utf-8").read()
    blocks = parse(text)
    sb = next(b for b in blocks if node_info(b) == (structure, "Room"))
    scell = vec3i(prop(sb, "cell"))
    boxes = []
    for b in blocks:
        info = node_info(b)
        if info and info[1] == f"Room/{structure}":
            bc = vec3i(prop(b, "cell"))
            boxes.append((info[0], b, (scell[0] + bc[0], scell[1] + bc[1], scell[2] + bc[2])))
    taken = set()
    renames = {}
    for piece_name, box_names in pieces:
        piece = [(b, w) for n, b, w in boxes if n in box_names]
        assert len(piece) == len(box_names), f"{piece_name}: boxes not found among {[n for n,_,_ in boxes]}"
        taken.update(box_names)
        header = [f'[node name="{piece_name}" parent="Room" instance={sb[0].split("instance=")[1].rstrip("]")}]', ""]
        first = min(blocks.index(b) for b, _ in piece)
        blocks.insert(first, header)
        r, lo, hi = rebase(header, piece_name, piece)
        renames.update(r)
        print(f"{path}: {piece_name} <- {box_names} cell {lo}")
    rest = [(b, w) for n, b, w in boxes if n not in taken]
    final = new_name or structure
    sb[0] = sb[0].replace(f'[node name="{structure}"', f'[node name="{final}"', 1)
    r, lo, hi = rebase(sb, final, rest)
    renames.update(r)
    print(f"{path}: {final} keeps {len(rest)} boxes, cell {lo}")
    for b in blocks:
        info = node_info(b)
        if info and info[1] in renames:
            b[0] = b[0].replace(f'parent="{info[1]}"', f'parent="{renames[info[1]]}"', 1)
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join("\n".join(b) for b in blocks))


if __name__ == "__main__":
    path, structure = sys.argv[1], sys.argv[2]
    new_name = None
    if "=" in structure:
        structure, new_name = structure.split("=", 1)
    pieces = [(arg.split("=")[0], arg.split("=")[1].split(",")) for arg in sys.argv[3:]]
    split(path, structure, new_name, pieces)
