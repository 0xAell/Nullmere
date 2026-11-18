"""Enough of Blender's mathutils, in plain Python, to run the model scripts dry."""
import math


class Vector:
    __slots__ = ("_v",)

    def __init__(self, values=(0.0, 0.0, 0.0)):
        self._v = [float(x) for x in values]

    # access
    def __len__(self):
        return len(self._v)

    def __iter__(self):
        return iter(self._v)

    def __getitem__(self, i):
        return self._v[i]

    def __setitem__(self, i, value):
        self._v[i] = float(value)

    def _get(i):
        return property(lambda self: self._v[i], lambda self, value: self._v.__setitem__(i, float(value)))

    x, y, z, w = _get(0), _get(1), _get(2), _get(3)

    def copy(self):
        return Vector(self._v)

    def to_tuple(self, precision=None):
        return tuple(self._v if precision is None else (round(x, precision) for x in self._v))

    def to_3d(self):
        return Vector((self._v + [0.0, 0.0, 0.0])[:3])

    def to_4d(self):
        return Vector((self._v + [0.0, 0.0, 0.0])[:3] + [1.0])

    def __repr__(self):
        return "Vector(%s)" % ", ".join("%.4f" % x for x in self._v)

    # arithmetic
    def __add__(self, other):
        return Vector(a + b for a, b in zip(self._v, other))

    __radd__ = __add__

    def __sub__(self, other):
        return Vector(a - b for a, b in zip(self._v, other))

    def __rsub__(self, other):
        return Vector(b - a for a, b in zip(self._v, other))

    def __mul__(self, other):
        if isinstance(other, (int, float)):
            return Vector(a * other for a in self._v)
        return Vector(a * b for a, b in zip(self._v, other))

    def __rmul__(self, other):
        return self.__mul__(other)

    def __truediv__(self, other):
        return Vector(a / other for a in self._v)

    def __neg__(self):
        return Vector(-a for a in self._v)

    def __matmul__(self, other):
        if isinstance(other, Vector):
            return self.dot(other)
        return NotImplemented

    def __eq__(self, other):
        try:
            return len(self) == len(other) and all(abs(a - b) < 1e-9 for a, b in zip(self._v, other))
        except TypeError:
            return False

    def __hash__(self):
        return hash(tuple(round(a, 6) for a in self._v))

    def dot(self, other):
        return sum(a * b for a, b in zip(self._v, other))

    def cross(self, other):
        a, b = self._v, list(other)
        return Vector((a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]))

    @property
    def length(self):
        return math.sqrt(self.dot(self))

    @property
    def length_squared(self):
        return self.dot(self)

    def normalized(self):
        n = self.length
        return Vector(self._v) if n < 1e-12 else self / n

    def normalize(self):
        n = self.length
        if n > 1e-12:
            self._v = [a / n for a in self._v]

    def lerp(self, other, t):
        return self + (Vector(other) - self) * t

    def angle(self, other, fallback=None):
        a, b = self.length, Vector(other).length
        if a < 1e-12 or b < 1e-12:
            return fallback
        return math.acos(max(-1.0, min(1.0, self.dot(other) / (a * b))))

    def rotation_difference(self, other):
        a, b = self.normalized(), Vector(other).normalized()
        axis = a.cross(b)
        d = max(-1.0, min(1.0, a.dot(b)))
        if axis.length < 1e-9:
            if d > 0:
                return Quaternion()
            perp = Vector((1, 0, 0)) if abs(a.x) < 0.9 else Vector((0, 1, 0))
            axis = a.cross(perp)
        return Quaternion(axis.normalized(), math.acos(d))


class Matrix:
    def __init__(self, rows=None):
        if rows is None:
            rows = [[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]
        self.rows = [[float(x) for x in row] for row in rows]

    @property
    def size(self):
        return len(self.rows)

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        return Vector(self.rows[i])

    def __setitem__(self, i, row):
        self.rows[i] = [float(x) for x in row]

    def copy(self):
        return Matrix(self.rows)

    @staticmethod
    def Identity(n):
        return Matrix([[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)])

    @staticmethod
    def Translation(v):
        m = Matrix.Identity(4)
        for i in range(3):
            m.rows[i][3] = float(v[i])
        return m

    @staticmethod
    def Scale(factor, size, axis=None):
        m = Matrix.Identity(size)
        for i in range(min(size, 3)):
            m.rows[i][i] = factor
        return m

    @staticmethod
    def Rotation(angle, size, axis):
        if isinstance(axis, str):
            axis = {"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis.upper()]
        x, y, z = Vector(axis).normalized()
        c, s = math.cos(angle), math.sin(angle)
        t = 1 - c
        r = [[t * x * x + c, t * x * y - s * z, t * x * z + s * y],
             [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
             [t * x * z - s * y, t * y * z + s * x, t * z * z + c]]
        if size == 4:
            return Matrix([r[0] + [0.0], r[1] + [0.0], r[2] + [0.0], [0.0, 0.0, 0.0, 1.0]])
        if size == 2:
            return Matrix([[c, -s], [s, c]])
        return Matrix(r)

    def __matmul__(self, other):
        if isinstance(other, Matrix):
            n = self.size
            o = other if other.size == n else (other.to_4x4() if n == 4 else other.to_3x3())
            return Matrix([[sum(self.rows[i][k] * o.rows[k][j] for k in range(n)) for j in range(n)] for i in range(n)])
        if isinstance(other, Quaternion):
            return self @ other.to_matrix()
        v = list(other)
        n = self.size
        if n == 4 and len(v) == 3:
            h = v + [1.0]
            out = [sum(self.rows[i][k] * h[k] for k in range(4)) for i in range(4)]
            w = out[3] if abs(out[3]) > 1e-12 else 1.0
            return Vector((out[0] / w, out[1] / w, out[2] / w))
        if n == 3 and len(v) == 3:
            return Vector(sum(self.rows[i][k] * v[k] for k in range(3)) for i in range(3))
        return Vector(sum(self.rows[i][k] * v[k] for k in range(n)) for i in range(n))

    def to_3x3(self):
        return Matrix([row[:3] for row in self.rows[:3]])

    def to_4x4(self):
        if self.size == 4:
            return self.copy()
        return Matrix([self.rows[0] + [0.0], self.rows[1] + [0.0], self.rows[2] + [0.0], [0.0, 0.0, 0.0, 1.0]])

    def transposed(self):
        return Matrix([list(col) for col in zip(*self.rows)])

    def inverted(self, fallback=None):
        n = self.size
        a = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(self.rows)]
        for col in range(n):
            pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
            if abs(a[pivot][col]) < 1e-12:
                if fallback is not None:
                    return fallback
                raise ValueError("matrix does not have an inverse")
            a[col], a[pivot] = a[pivot], a[col]
            p = a[col][col]
            a[col] = [x / p for x in a[col]]
            for r in range(n):
                if r != col:
                    f = a[r][col]
                    a[r] = [x - f * y for x, y in zip(a[r], a[col])]
        return Matrix([row[n:] for row in a])

    def invert(self):
        self.rows = self.inverted().rows

    @property
    def translation(self):
        return Vector((self.rows[0][3], self.rows[1][3], self.rows[2][3]))

    @translation.setter
    def translation(self, v):
        for i in range(3):
            self.rows[i][3] = float(v[i])

    def to_quaternion(self):
        m = self.to_3x3().rows
        tr = m[0][0] + m[1][1] + m[2][2]
        if tr > 0:
            s = math.sqrt(tr + 1.0) * 2
            return Quaternion((0.25 * s, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s))
        if m[0][0] > m[1][1] and m[0][0] > m[2][2]:
            s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
            return Quaternion(((m[2][1] - m[1][2]) / s, 0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s))
        if m[1][1] > m[2][2]:
            s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
            return Quaternion(((m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s))
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        return Quaternion(((m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s))

    def to_euler(self, order="XYZ"):
        m = self.to_3x3().rows
        y = math.asin(max(-1.0, min(1.0, -m[2][0])))
        x = math.atan2(m[2][1], m[2][2])
        z = math.atan2(m[1][0], m[0][0])
        return Euler((x, y, z))

    def decompose(self):
        return self.translation, self.to_quaternion(), Vector((1, 1, 1))


class Quaternion:
    def __init__(self, *args):
        if not args:
            self.w, self.x, self.y, self.z = 1.0, 0.0, 0.0, 0.0
        elif len(args) == 2:
            axis, angle = Vector(args[0]).normalized(), args[1]
            s = math.sin(angle / 2)
            self.w, self.x, self.y, self.z = math.cos(angle / 2), axis.x * s, axis.y * s, axis.z * s
        else:
            self.w, self.x, self.y, self.z = (float(v) for v in args[0])

    def __iter__(self):
        return iter((self.w, self.x, self.y, self.z))

    def __getitem__(self, i):
        return (self.w, self.x, self.y, self.z)[i]

    def __neg__(self):
        return Quaternion((-self.w, -self.x, -self.y, -self.z))

    def copy(self):
        return Quaternion(tuple(self))

    def dot(self, other):
        return sum(a * b for a, b in zip(self, other))

    def normalized(self):
        n = math.sqrt(self.dot(self)) or 1.0
        return Quaternion(tuple(a / n for a in self))

    def inverted(self):
        n = self.dot(self) or 1.0
        return Quaternion((self.w / n, -self.x / n, -self.y / n, -self.z / n))

    def conjugated(self):
        return Quaternion((self.w, -self.x, -self.y, -self.z))

    def __matmul__(self, other):
        if isinstance(other, Quaternion):
            w1, x1, y1, z1 = self
            w2, x2, y2, z2 = other
            return Quaternion((w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2, w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
                               w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2, w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2))
        return self.to_matrix() @ other

    def to_matrix(self):
        w, x, y, z = self.normalized()
        return Matrix([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                       [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                       [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])

    def to_euler(self, order="XYZ"):
        return self.to_matrix().to_euler(order)

    def slerp(self, other, t):
        return Quaternion(tuple(a + (b - a) * t for a, b in zip(self, other))).normalized()


class Euler:
    def __init__(self, angles=(0.0, 0.0, 0.0), order="XYZ"):
        self.x, self.y, self.z = (float(a) for a in angles)
        self.order = order

    def __iter__(self):
        return iter((self.x, self.y, self.z))

    def __getitem__(self, i):
        return (self.x, self.y, self.z)[i]

    def copy(self):
        return Euler((self.x, self.y, self.z), self.order)

    def to_matrix(self):
        rx, ry, rz = Matrix.Rotation(self.x, 3, "X"), Matrix.Rotation(self.y, 3, "Y"), Matrix.Rotation(self.z, 3, "Z")
        # Blender's XYZ order applies X first: R = Rz @ Ry @ Rx.
        return rz @ ry @ rx

    def to_quaternion(self):
        return self.to_matrix().to_quaternion()
