"""Enough of Blender's bmesh, in plain Python, to run the model scripts dry."""
from mathutils import Vector

from . import ops  # noqa: F401


class BMVert:
    __slots__ = ("co", "index", "link_faces")

    def __init__(self, co):
        self.co = Vector(co).to_3d() if len(co) != 3 else Vector(co)
        self.index = -1
        self.link_faces = []


class BMFace:
    __slots__ = ("verts", "material_index", "smooth")

    def __init__(self, verts):
        self.verts = list(verts)
        self.material_index = 0
        self.smooth = False

    @property
    def normal(self):
        return newell([v.co for v in self.verts])

    def calc_center_median(self):
        return sum((v.co for v in self.verts), Vector((0, 0, 0))) / len(self.verts)


def newell(points):
    n = Vector((0, 0, 0))
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        n = n + Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    return n.normalized()


class _Verts(list):
    def new(self, co=(0.0, 0.0, 0.0), example=None):
        v = BMVert(co)
        self.append(v)
        return v

    def ensure_lookup_table(self):
        pass

    def index_update(self):
        for i, v in enumerate(self):
            v.index = i


class _Faces(list):
    def new(self, verts, example=None):
        verts = list(verts)
        if len(verts) < 3 or len(set(id(v) for v in verts)) != len(verts):
            raise ValueError("faces.new(verts): duplicate or too few vertices")
        f = BMFace(verts)
        self.append(f)
        return f

    def ensure_lookup_table(self):
        pass


class _Edges(list):
    def ensure_lookup_table(self):
        pass


class BMesh:
    def __init__(self):
        self.verts = _Verts()
        self.faces = _Faces()
        self.edges = _Edges()

    def from_mesh(self, mesh):
        self.verts = _Verts()
        self.faces = _Faces()
        made = [self.verts.new(v.co.copy()) for v in mesh.vertices]
        for p in mesh.polygons:
            f = BMFace([made[i] for i in p.vertices])
            f.material_index = p.material_index
            f.smooth = p.use_smooth
            self.faces.append(f)

    def to_mesh(self, mesh):
        index = {id(v): i for i, v in enumerate(self.verts)}
        mesh.set_geometry([v.co.copy() for v in self.verts],
                          [([index[id(v)] for v in f.verts], f.material_index, f.smooth) for f in self.faces])

    def free(self):
        pass

    def normal_update(self):
        pass


def new():
    return BMesh()


class types:
    BMVert = BMVert
    BMFace = BMFace
    BMesh = BMesh
