"""mathutils.bvhtree, as far as the model scripts reach: a tree of polygons
a ray is cast against, here every triangle tried at once with numpy."""
import numpy

from . import Vector


class BVHTree:
    def __init__(self, a, e1, e2):
        self.a, self.e1, self.e2 = a, e1, e2

    @staticmethod
    def FromPolygons(vertices, polygons, all_triangles=False, epsilon=0.0):
        points = numpy.array([[c for c in v] for v in vertices], dtype=float)
        tris = []
        for poly in polygons:
            for i in range(1, len(poly) - 1):
                tris.append((poly[0], poly[i], poly[i + 1]))
        tris = numpy.array(tris, dtype=int).reshape(-1, 3)
        a = points[tris[:, 0]]
        return BVHTree(a, points[tris[:, 1]] - a, points[tris[:, 2]] - a)

    def ray_cast(self, origin, direction, distance=1e30):
        """The nearest hit along the ray within `distance`: (location,
        normal, index, distance), or Nones (Möller and Trumbore's test)."""
        o = numpy.array(list(origin), dtype=float)
        d = numpy.array(list(direction), dtype=float)
        norm = numpy.linalg.norm(d)
        if norm == 0:
            return None, None, None, None
        d = d / norm
        p = numpy.cross(d, self.e2)
        det = numpy.einsum("ij,ij->i", self.e1, p)
        ok = numpy.abs(det) > 1e-12
        inv = numpy.where(ok, 1.0 / numpy.where(ok, det, 1.0), 0.0)
        s = o - self.a
        u = numpy.einsum("ij,ij->i", s, p) * inv
        q = numpy.cross(s, self.e1)
        v = (q @ d) * inv
        t = numpy.einsum("ij,ij->i", self.e2, q) * inv
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-9) & (t <= distance)
        if not hit.any():
            return None, None, None, None
        index = int(numpy.argmin(numpy.where(hit, t, numpy.inf)))
        at = o + d * t[index]
        n = numpy.cross(self.e1[index], self.e2[index])
        n = n / (numpy.linalg.norm(n) or 1.0)
        return Vector(at), Vector(n), index, float(t[index])
