"""Enough of Blender's bpy, in plain Python, to run the model scripts dry:
meshes are kept, transforms applied, objects joined, and the scene written
out as JSON (each mesh's points in Blender's axes, its faces and materials)
where Blender would write glTF."""
import json
import math

from mathutils import Euler, Matrix, Quaternion, Vector

from . import ops  # noqa: F401
from . import app  # noqa: F401


# MARK: Meshes

class MeshVertex:
    __slots__ = ("co", "index", "groups")

    def __init__(self, co, index):
        self.co = co
        self.index = index
        self.groups = []


class MeshPolygon:
    __slots__ = ("vertices", "material_index", "use_smooth", "_mesh", "index")

    def __init__(self, mesh, vertices, material_index, smooth, index):
        self._mesh = mesh
        self.vertices = list(vertices)
        self.material_index = material_index
        self.use_smooth = smooth
        self.index = index

    @property
    def loop_total(self):
        return len(self.vertices)

    @property
    def normal(self):
        from bmesh import newell
        return newell([self._mesh.vertices[i].co for i in self.vertices])

    @property
    def center(self):
        pts = [self._mesh.vertices[i].co for i in self.vertices]
        return sum(pts, Vector((0, 0, 0))) / len(pts)

    @property
    def area(self):
        pts = [self._mesh.vertices[i].co for i in self.vertices]
        return sum((pts[i] - pts[0]).cross(pts[i + 1] - pts[0]).length / 2 for i in range(1, len(pts) - 1))


class AttributeValue:
    __slots__ = ("value", "vector", "color")

    def __init__(self):
        self.value = 0.0
        self.vector = (0.0, 0.0, 0.0)
        self.color = (1.0, 1.0, 1.0, 1.0)


class Attribute:
    def __init__(self, name, kind, domain, count):
        self.name, self.data_type, self.domain = name, kind, domain
        self.data = [AttributeValue() for _ in range(count)]


class Attributes(dict):
    def __init__(self, mesh):
        super().__init__()
        self._mesh = mesh

    def new(self, name, kind, domain):
        a = Attribute(name, kind, domain, len(self._mesh.vertices))
        self[name] = a
        return a

    def get(self, name, default=None):
        return dict.get(self, name, default)


class Materials(list):
    def append(self, m):
        list.append(self, m)

    def clear(self):
        del self[:]


class Mesh:
    def __init__(self, name):
        self.name = name
        self.vertices = []
        self.polygons = []
        self.materials = Materials()
        self.attributes = Attributes(self)
        self.users = 1

    def set_geometry(self, points, faces):
        self.vertices = [MeshVertex(Vector(p), i) for i, p in enumerate(points)]
        self.polygons = [MeshPolygon(self, f, m, s, i) for i, (f, m, s) in enumerate(faces)]
        for a in self.attributes.values():
            a.data = (a.data + [AttributeValue() for _ in range(len(self.vertices))])[:len(self.vertices)]

    def transform(self, matrix):
        for v in self.vertices:
            v.co = matrix @ v.co

    def update(self):
        pass

    def copy(self):
        m = Mesh(self.name)
        m.set_geometry([v.co for v in self.vertices], [(p.vertices, p.material_index, p.use_smooth) for p in self.polygons])
        m.materials.extend(self.materials)
        return m


# MARK: Armatures

class EditBone:
    def __init__(self, name):
        self.name = name
        self.head = Vector((0, 0, 0))
        self.tail = Vector((0, 0, 1))
        self.roll = 0.0
        self.parent = None
        self.use_connect = False
        self.use_deform = True

    @property
    def children(self):
        return [b for b in getattr(self, "_bones", {}).values() if b.parent is self]

    @property
    def children_recursive(self):
        out = []
        for child in self.children:
            out += [child] + child.children_recursive
        return out

    @property
    def length(self):
        return (Vector(self.tail) - Vector(self.head)).length

    @property
    def matrix_local(self):
        y = (Vector(self.tail) - Vector(self.head)).normalized()
        q = Vector((0, 1, 0)).rotation_difference(y).to_matrix().to_4x4()
        q.translation = self.head
        return q


class EditBones(dict):
    def new(self, name):
        b = EditBone(name)
        b._bones = self
        self[name] = b
        return b

    def remove(self, bone):
        for other in self.values():
            if other.parent is bone:
                other.parent = None
        self.pop(bone.name, None)

    def get(self, name, default=None):
        return dict.get(self, name, default)

    def __iter__(self):
        return iter(self.values())


class Armature:
    def __init__(self, name):
        self.name = name
        self.edit_bones = EditBones()
        self.users = 1

    @property
    def bones(self):
        return self.edit_bones


class PoseBone:
    def __init__(self, bone):
        self.name = bone.name
        self.bone = bone
        self.rotation_mode = "QUATERNION"
        self.rotation_quaternion = Quaternion()
        self.rotation_euler = Euler()
        self.location = Vector((0, 0, 0))
        self.scale = Vector((1, 1, 1))
        self.keys = 0

    def keyframe_insert(self, path, frame=0, index=-1, **_):
        self.keys += 1
        return True

    @property
    def matrix(self):
        return self.bone.matrix_local


class Pose:
    def __init__(self, armature):
        self._armature = armature
        self._bones = {}

    @property
    def bones(self):
        for name, b in self._armature.edit_bones.items():
            if name not in self._bones:
                self._bones[name] = PoseBone(b)
        return _PoseBones(self._bones)


class _PoseBones(dict):
    def __iter__(self):
        return iter(self.values())


# MARK: Animation

class Action:
    def __init__(self, name):
        self.name = name
        self.fcurves = []
        self.frame_range = (0, 0)


class Strip:
    def __init__(self, name, start, action):
        self.name, self.action, self.frame_start = name, action, start


class Strips(list):
    def new(self, name, start, action):
        s = Strip(name, start, action)
        self.append(s)
        return s


class Track:
    def __init__(self):
        self.name = ""
        self.strips = Strips()
        self.mute = False


class Tracks(list):
    def new(self, prev=None):
        t = Track()
        self.append(t)
        return t


class AnimationData:
    def __init__(self):
        self.action = None
        self.nla_tracks = Tracks()


# MARK: Objects

class VertexElement:
    __slots__ = ("group", "weight")

    def __init__(self, group, weight):
        self.group, self.weight = group, weight


class VertexGroup:
    def __init__(self, name, index, owner=None):
        self.name, self.index, self.owner = name, index, owner

    def add(self, indices, weight, mode):
        mesh = getattr(self.owner, "data", None)
        if not isinstance(mesh, Mesh):
            return
        for i in indices:
            if i >= len(mesh.vertices):
                continue
            groups = mesh.vertices[i].groups
            found = next((g for g in groups if g.group == self.index), None)
            if found is None:
                groups.append(VertexElement(self.index, weight))
            elif mode == "ADD":
                found.weight += weight
            else:
                found.weight = weight

    def weight(self, index):
        for g in self.owner.data.vertices[index].groups:
            if g.group == self.index:
                return g.weight
        raise RuntimeError("not in the group")


class VertexGroups(list):
    def __init__(self, owner=None):
        super().__init__()
        self.owner = owner
        self._next = 0

    def new(self, name="Group"):
        g = VertexGroup(name, self._next, self.owner)
        self._next += 1
        self.append(g)
        return g

    def remove(self, group):
        if group in self:
            list.remove(self, group)
        mesh = getattr(self.owner, "data", None)
        if isinstance(mesh, Mesh):
            for v in mesh.vertices:
                v.groups = [g for g in v.groups if g.group != group.index]

    def get(self, name, default=None):
        for g in self:
            if g.name == name:
                return g
        return default


class Modifier:
    def __init__(self, name, kind):
        self.name, self.type = name, kind
        self.object = None


class Modifiers(list):
    def new(self, name, kind):
        m = Modifier(name, kind)
        self.append(m)
        return m


class Object:
    def __init__(self, name, data):
        self._name = None
        self.data = data
        self.type = "MESH" if isinstance(data, Mesh) else "ARMATURE" if isinstance(data, Armature) else "EMPTY"
        self.location = Vector((0, 0, 0))
        self.rotation_euler = Euler()
        self.rotation_mode = "XYZ"
        self.scale = Vector((1, 1, 1))
        self._world = None
        self.parent = None
        self.parent_type = "OBJECT"
        self.parent_bone = ""
        self.vertex_groups = VertexGroups(self)
        self.modifiers = Modifiers()
        self.selected = False
        self.animation_data = None
        self.hide_viewport = False
        self.hide_render = False
        self.pose = Pose(data) if isinstance(data, Armature) else None
        self.name = name

    @property
    def name(self):
        return self._name

    @name.setter
    def name(self, value):
        if value == self._name:
            return
        taken = {o._name for o in data.objects if o is not self}
        if value in taken:
            k = 1
            while "%s.%03d" % (value, k) in taken:
                k += 1
            value = "%s.%03d" % (value, k)
        self._name = value

    @property
    def matrix_world(self):
        if self._world is not None:
            return self._world.copy()
        r = Euler(tuple(self.rotation_euler)).to_matrix().to_4x4()
        s = Matrix.Identity(4)
        for i in range(3):
            s.rows[i][i] = self.scale[i]
        return Matrix.Translation(self.location) @ r @ s

    @matrix_world.setter
    def matrix_world(self, m):
        self._world = Matrix(m.rows if isinstance(m, Matrix) else m)

    @property
    def matrix_basis(self):
        return self.matrix_world

    def select_set(self, state):
        self.selected = bool(state)

    def select_get(self):
        return self.selected

    def animation_data_create(self):
        if self.animation_data is None:
            self.animation_data = AnimationData()
        return self.animation_data

    def apply(self):
        """Its transform applied to its mesh."""
        m = self.matrix_world
        if isinstance(self.data, Mesh):
            self.data.transform(m)
        self._world = None
        self.location = Vector((0, 0, 0))
        self.rotation_euler = Euler()
        self.scale = Vector((1, 1, 1))


class Collection(list):
    def link(self, obj):
        if obj not in self:
            self.append(obj)
        data.objects.append_unique(obj)

    def unlink(self, obj):
        if obj in self:
            self.remove(obj)


# MARK: bpy.data

class _Datablocks(list):
    def __init__(self, make):
        super().__init__()
        self._make = make

    def new(self, name, *args, **kwargs):
        made = self._make(name, *args, **kwargs)
        self.append(made)
        return made

    def get(self, name, default=None):
        for d in self:
            if getattr(d, "name", None) == name:
                return d
        return default

    def remove(self, item, **_):
        if item in self:
            list.remove(self, item)

    def append_unique(self, item):
        if item not in self:
            self.append(item)

    def __getitem__(self, key):
        if isinstance(key, str):
            found = self.get(key)
            if found is None:
                raise KeyError(key)
            return found
        return list.__getitem__(self, key)

    def __contains__(self, key):
        if isinstance(key, str):
            return self.get(key) is not None
        return list.__contains__(self, key)


class _Socket:
    def __init__(self):
        self.default_value = (1.0, 1.0, 1.0, 1.0)


class _Node:
    def __init__(self):
        self.inputs = {"Base Color": _Socket(), "Roughness": _Socket(), "Metallic": _Socket(), "Emission Color": _Socket(),
                       "Emission Strength": _Socket(), "Alpha": _Socket()}


class _Nodes(dict):
    def get(self, name, default=None):
        return dict.get(self, name, default) or _Node()


class _Tree:
    def __init__(self):
        self.nodes = _Nodes({"Principled BSDF": _Node()})
        self.links = []


class Material:
    def __init__(self, name):
        self.name = name
        self.use_nodes = False
        self.node_tree = _Tree()
        self.diffuse_color = (1.0, 1.0, 1.0, 1.0)
        self.users = 1


class _Data:
    def __init__(self):
        self.meshes = _Datablocks(Mesh)
        self.objects = _Datablocks(lambda name, d: Object(name, d))
        self.materials = _Datablocks(Material)
        self.armatures = _Datablocks(Armature)
        self.actions = _Datablocks(Action)
        self.collections = _Datablocks(lambda name: Collection())


data = _Data()


# MARK: bpy.context

class _Render:
    fps = 24
    resolution_x = 1920
    resolution_y = 1080


class Scene:
    def __init__(self):
        self.collection = _SceneCollection()
        self.render = _Render()
        self.frame_start = 1
        self.frame_end = 250
        self.frame_current = 0

    @property
    def objects(self):
        return list(self.collection.objects)

    def frame_set(self, frame):
        self.frame_current = frame


class _SceneCollection:
    def __init__(self):
        self.objects = Collection()
        self.children = []


class _LayerObjects:
    def __init__(self):
        self.active = None


class _ViewLayer:
    def __init__(self):
        self.objects = _LayerObjects()

    def update(self):
        pass


class _Context:
    def __init__(self):
        self.scene = Scene()
        self.view_layer = _ViewLayer()

    @property
    def active_object(self):
        return self.view_layer.objects.active

    @property
    def object(self):
        return self.view_layer.objects.active

    @property
    def selected_objects(self):
        return [o for o in self.scene.objects if o.selected]


context = _Context()


def _reset():
    global data, context
    data.__init__()
    context.__init__()


def _write(path):
    """The scene written out as Blender would: here, as JSON."""
    out = {"meshes": [], "materials": {}}
    for obj in context.scene.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        m = obj.matrix_world
        points = [m @ v.co for v in mesh.vertices]
        sway = mesh.attributes.get("_SWAY")
        names = [mat.name if mat else "" for mat in mesh.materials]
        for mat in mesh.materials:
            if mat is not None:
                out["materials"][mat.name] = list(mat.diffuse_color)
        out["meshes"].append({
            "name": obj.name,
            "parent": obj.parent.name if obj.parent else None,
            "bone": obj.parent_bone if obj.parent_type == "BONE" else None,
            "points": [[round(c, 5) for c in p] for p in points],
            "faces": [[p.vertices, names[p.material_index] if p.material_index < len(names) else ""] for p in mesh.polygons],
            "sway": [round(a.value, 3) for a in sway.data] if sway else None,
        })
    with open(path, "w") as f:
        json.dump(out, f)
