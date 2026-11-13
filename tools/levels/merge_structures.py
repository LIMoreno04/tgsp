"""Merge Structure nodes of a TGSP level .tscn: moves every box of the sources under the target,
keeping world cells, and deletes the sources. Usage:
  python merge_structures.py level.tscn TARGET[=NewName] SRC1 SRC2 ...
"""
import re, sys

HEADER = re.compile(r'^\[node name="([^"]+)"(?: type="([^"]+)")? parent="([^"]+)"(.*)\]$')


def parse(text):
    lines = text.split("\n")
    blocks = []  # [header_line_index, [lines]]
    current = None
    for line in lines:
        if line.startswith("["):
            current = [line]
            blocks.append(current)
        else:
            if current is None:
                current = [line]
                blocks.append(current)
            else:
                current.append(line)
    return blocks


def prop(block, name):
    for line in block[1:]:
        if line.startswith(name + " = "):
            return line[len(name) + 3:]
    return None


def set_prop(block, name, value):
    for i, line in enumerate(block[1:], 1):
        if line.startswith(name + " = "):
            if value is None:
                del block[i]
            else:
                block[i] = f"{name} = {value}"
            return
    if value is None:
        return
    # insert after the header, before the trailing blank line
    insert_at = len(block)
    while insert_at > 1 and block[insert_at - 1].strip() == "":
        insert_at -= 1
    block.insert(insert_at, f"{name} = {value}")


def vec3i(s):
    if s is None:
        return (0, 0, 0)
    m = re.match(r"Vector3i\((-?\d+), (-?\d+), (-?\d+)\)", s)
    return tuple(int(v) for v in m.groups())


def node_info(block):
    m = HEADER.match(block[0])
    if not m:
        return None
    return m.group(1), m.group(3)


def merge(path, target, new_name, sources):
    text = open(path, encoding="utf-8").read()
    blocks = parse(text)
    structures = {target: None}
    for s in sources:
        structures[s] = None
    for b in blocks:
        info = node_info(b)
        if info and info[1] == "Room" and info[0] in structures:
            structures[info[0]] = b
    missing = [n for n, b in structures.items() if b is None]
    assert not missing, f"not found under Room: {missing}"
    cells = {n: vec3i(prop(b, "cell")) for n, b in structures.items()}

    boxes = []  # (block, world_cell, old_path)
    for b in blocks:
        info = node_info(b)
        if not info:
            continue
        name, parent = info
        if parent.startswith("Room/") and parent[5:] in structures and "/" not in parent[5:]:
            sc = cells[parent[5:]]
            bc = vec3i(prop(b, "cell"))
            boxes.append((b, (sc[0] + bc[0], sc[1] + bc[1], sc[2] + bc[2]), f"{parent}/{name}"))
    assert boxes, "no boxes"
    lo = tuple(min(w[i] for _, w, _ in boxes) for i in range(3))
    hi = tuple(max(w[i] for _, w, _ in boxes) for i in range(3))
    final_name = new_name or target
    tb = structures[target]
    tb[0] = tb[0].replace(f'[node name="{target}"', f'[node name="{final_name}"', 1)
    set_prop(tb, "transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lo[0]}, {lo[2]}, {lo[1]})" if lo != (0, 0, 0) else None)
    set_prop(tb, "dimensions", f"Vector3i({hi[0]-lo[0]+1}, {hi[1]-lo[1]+1}, {hi[2]-lo[2]+1})")
    set_prop(tb, "cell", f"Vector3i({lo[0]}, {lo[1]}, {lo[2]})" if lo != (0, 0, 0) else None)

    renames = {}
    for i, (b, w, old_path) in enumerate(boxes):
        new_box_name = "Box" if i == 0 else f"Box{i + 1}"
        rel = (w[0] - lo[0], w[1] - lo[1], w[2] - lo[2])
        m = HEADER.match(b[0])
        b[0] = f'[node name="{new_box_name}" parent="Room/{final_name}"{m.group(4)}]'
        set_prop(b, "transform", f"Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {rel[0]}, {rel[2]}, {rel[1]})" if rel != (0, 0, 0) else None)
        set_prop(b, "cell", f"Vector3i({rel[0]}, {rel[1]}, {rel[2]})" if rel != (0, 0, 0) else None)
        renames[old_path] = f"Room/{final_name}/{new_box_name}"
    # children of boxes (powerables)
    for b in blocks:
        info = node_info(b)
        if not info:
            continue
        name, parent = info
        if parent in renames:
            b[0] = b[0].replace(f'parent="{parent}"', f'parent="{renames[parent]}"', 1)
        elif parent.startswith("Room/") and parent.count("/") >= 2 and parent.split("/")[1] in structures and parent.split("/")[1] != target:
            raise SystemExit(f"unexpected deep child {name} under {parent}")
    # delete source structure headers
    blocks = [b for b in blocks if not (node_info(b) and node_info(b)[1] == "Room" and node_info(b)[0] in sources)]
    # a child must come after its parent in the file: put the target right before its first box
    blocks.remove(tb)
    first_box = min(blocks.index(b) for b, _, _ in boxes)
    blocks.insert(first_box, tb)
    out = "\n".join("\n".join(b) for b in blocks)
    open(path, "w", encoding="utf-8", newline="\n").write(out)
    print(f"{path}: {final_name} <- {sources}: {len(boxes)} boxes, cell {lo}, dims {tuple(h-l+1 for h,l in zip(hi,lo))}")


if __name__ == "__main__":
    path = sys.argv[1]
    target = sys.argv[2]
    new_name = None
    if "=" in target:
        target, new_name = target.split("=", 1)
    merge(path, target, new_name, sys.argv[3:])
