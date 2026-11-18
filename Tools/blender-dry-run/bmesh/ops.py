"""bmesh.ops, as far as the model scripts reach."""


def recalc_face_normals(bm, faces=None):
    return {}


def remove_doubles(bm, verts=None, dist=1e-6):
    verts = list(verts if verts is not None else bm.verts)
    keep = {}
    grid = {}
    cell = max(dist, 1e-9) * 4
    for v in verts:
        key = tuple(int(c // cell) for c in v.co)
        found = None
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for w in grid.get((key[0] + dx, key[1] + dy, key[2] + dz), ()):
                        if (w.co - v.co).length <= dist:
                            found = w
                            break
                    if found:
                        break
                if found:
                    break
            if found:
                break
        if found is not None:
            keep[id(v)] = found
        else:
            grid.setdefault(key, []).append(v)
    if not keep:
        return {}
    faces = []
    for f in bm.faces:
        ring = []
        for v in f.verts:
            w = keep.get(id(v), v)
            if not ring or ring[-1] is not w:
                ring.append(w)
        while len(ring) > 1 and ring[0] is ring[-1]:
            ring.pop()
        if len(ring) >= 3 and len(set(id(v) for v in ring)) == len(ring):
            f.verts = ring
            faces.append(f)
    bm.faces[:] = faces
    bm.verts[:] = [v for v in bm.verts if id(v) not in keep]
    return {}


def dissolve_degenerate(bm, edges=None, dist=1e-6):
    kept = []
    for f in bm.faces:
        pts = [v.co for v in f.verts]
        area = 0.0
        for i in range(1, len(pts) - 1):
            area += (pts[i] - pts[0]).cross(pts[i + 1] - pts[0]).length / 2
        if area > dist * dist:
            kept.append(f)
    bm.faces[:] = kept
    return {}


def bevel(bm, geom=None, offset=0.0, segments=1, affect="EDGES", clamp_overlap=True, **_):
    # A chamfer adds triangles in Blender; counted roughly: each box's
    # twelve edges and eight corners.
    bm._bevelled = getattr(bm, "_bevelled", 0) + 1
    return {}


def transform(bm, matrix=None, verts=None, space=None):
    for v in verts if verts is not None else bm.verts:
        v.co = matrix @ v.co
    return {}


def translate(bm, vec=None, verts=None):
    for v in verts if verts is not None else bm.verts:
        v.co = v.co + vec
    return {}


def triangulate(bm, faces=None, quad_method=None, ngon_method=None):
    out = []
    targets = set(id(f) for f in (faces if faces is not None else bm.faces))
    from . import BMFace
    for f in bm.faces:
        if id(f) in targets and len(f.verts) > 3:
            for i in range(1, len(f.verts) - 1):
                t = BMFace([f.verts[0], f.verts[i], f.verts[i + 1]])
                t.material_index, t.smooth = f.material_index, f.smooth
                out.append(t)
        else:
            out.append(f)
    bm.faces[:] = out
    return {}


def bisect_plane(bm, geom=None, dist=0.0, plane_co=None, plane_no=None, clear_inner=False, clear_outer=False, **_):
    # Not cut: the dry run keeps the whole piece.
    return {"geom_cut": [], "geom": list(bm.verts) + list(bm.faces)}


def delete(bm, geom=None, context="VERTS"):
    gone = set(id(g) for g in geom or [])
    bm.verts[:] = [v for v in bm.verts if id(v) not in gone]
    bm.faces[:] = [f for f in bm.faces if id(f) not in gone and all(id(v) not in gone for v in f.verts)]
    return {}


def reverse_faces(bm, faces=None):
    for f in faces or []:
        f.verts.reverse()
    return {}


def create_circle(bm, cap_ends=True, segments=8, radius=1.0, matrix=None):
    import math
    ring = [bm.verts.new((radius * math.cos(2 * math.pi * k / segments), radius * math.sin(2 * math.pi * k / segments), 0.0))
            for k in range(segments)]
    if matrix is not None:
        for v in ring:
            v.co = matrix @ v.co
    if cap_ends:
        bm.faces.new(ring)
    return {"verts": ring}
