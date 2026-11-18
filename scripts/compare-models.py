"""Compares the models made again with those they replace: for each, whether
its bytes are the same, and its nodes, meshes, the points of its meshes and
its actions, before and after. Fails where a model is missing or unreadable,
or has lost every mesh or every action it had: a script that broke in
another Blender, not a model changed on purpose.

    python3 scripts/compare-models.py <folder of the models before> <folder of those after>
"""
import json
import os
import struct
import sys


def summary(path):
    data = open(path, "rb").read()
    magic, _, _ = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise ValueError("not glTF binary")
    length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + length])
    points = sum(gltf["accessors"][primitive["attributes"]["POSITION"]]["count"]
                 for mesh in gltf.get("meshes", []) for primitive in mesh["primitives"])
    return {"bytes": data, "nodes": len(gltf.get("nodes", [])), "meshes": len(gltf.get("meshes", [])), "points": points,
            "actions": sorted(animation.get("name", "") for animation in gltf.get("animations", []))}


def main(before, after):
    failed = 0
    same = 0
    names = sorted(name for name in os.listdir(before) if name.endswith(".glb"))
    for name in names:
        old = summary(os.path.join(before, name))
        try:
            new = summary(os.path.join(after, name))
        except (OSError, ValueError, KeyError) as error:
            print(f"FAIL {name}: {error}")
            failed += 1
            continue
        if new["bytes"] == old["bytes"]:
            same += 1
            print(f"same {name}")
            continue
        lost = (old["meshes"] and not new["meshes"]) or (old["actions"] and not new["actions"])
        print(f"{'FAIL' if lost else 'diff'} {name}: nodes {old['nodes']} -> {new['nodes']}, meshes {old['meshes']} -> {new['meshes']}, "
              f"points {old['points']} -> {new['points']}, actions {len(old['actions'])} -> {len(new['actions'])}"
              + ("" if old["actions"] == new["actions"] else f" (now {', '.join(new['actions'][:8])})"))
        failed += 1 if lost else 0
    print(f"{len(names)} models: {same} the same to the byte, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
