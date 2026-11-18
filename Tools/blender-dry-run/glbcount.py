"""The triangles of a model made in Blender, each level's (or variant's)
far and near, as finish_building counts them, to set beside what run.py
counts for its script.

    python3 Tools/blender-dry-run/glbcount.py <model.glb> [<variant>...]
"""
import json
import struct
import sys


def drawn(name, tier, variant):
    base = name.replace("!fine", "")
    if "@" not in base:
        return True
    tags = base.split("@")[-1].split(",")
    if variant:
        return variant in tags
    for tag in tags:
        if tag[0].isdigit():
            a, *b = tag.split("-")
            if int(a) <= tier <= int(b[0] if b else a):
                return True
    return False


data = open(sys.argv[1], "rb").read()
length = struct.unpack_from("<I", data, 12)[0]
g = json.loads(data[20:20 + length])
counts = {}
for node in g["nodes"]:
    if "mesh" not in node:
        continue
    mesh = g["meshes"][node["mesh"]]
    tris = sum(g["accessors"][p["indices"]]["count"] // 3 for p in mesh["primitives"])
    counts[node["name"]] = tris
variants = sys.argv[2:] or ["1", "2", "3", "4", "5"]
for v in variants:
    far = sum(t for n, t in counts.items() if not n.endswith("!fine") and drawn(n, 1, v))
    near = sum(t for n, t in counts.items() if drawn(n, 1, v))
    print("%s: %d triangles far, %d near" % (v, far, near))
