"""bpy.ops, as far as the model scripts reach: each operator a function."""
import math

from mathutils import Vector


def _bpy():
    import bpy
    return bpy


def _selected():
    bpy = _bpy()
    return [o for o in bpy.context.scene.objects if o.selected]


def _added(name, points, faces, location):
    bpy = _bpy()
    for o in bpy.context.scene.objects:
        o.selected = False
    mesh = bpy.data.meshes.new(name)
    mesh.set_geometry([Vector(p) for p in points], [(f, 0, False) for f in faces])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = Vector(location)
    obj.selected = True
    bpy.context.view_layer.objects.active = obj
    return {"FINISHED"}


class _Namespace:
    pass


wm = _Namespace()
object = _Namespace()
mesh = _Namespace()
export_scene = _Namespace()


def read_factory_settings(use_empty=True):
    _bpy()._reset()
    return {"FINISHED"}


wm.read_factory_settings = read_factory_settings


def select_all(action="SELECT"):
    for o in _bpy().context.scene.objects:
        o.selected = action == "SELECT"
    return {"FINISHED"}


def transform_apply(location=True, rotation=True, scale=True, **_):
    for o in _selected():
        o.apply()
    return {"FINISHED"}


def join():
    bpy = _bpy()
    active = bpy.context.view_layer.objects.active
    others = [o for o in _selected() if o is not active and o.type == "MESH"]
    points, faces, mats = [], [], list(active.data.materials)
    am = active.matrix_world.inverted()
    for o in [active] + others:
        m = am @ o.matrix_world if o is not active else None
        base = len(points)
        index = []
        for mat in o.data.materials:
            if mat not in mats:
                mats.append(mat)
            index.append(mats.index(mat))
        points += [(m @ v.co) if m is not None else v.co.copy() for v in o.data.vertices]
        for p in o.data.polygons:
            faces.append(([i + base for i in p.vertices], index[p.material_index] if p.material_index < len(index) else 0, p.use_smooth))
    sway = []
    named = any(o.data.attributes.get("_SWAY") for o in [active] + others)
    if named:
        for o in [active] + others:
            a = o.data.attributes.get("_SWAY")
            sway += [d.value for d in a.data] if a else [0.0] * len(o.data.vertices)
    active.data.set_geometry(points, faces)
    active.data.materials[:] = mats
    if named:
        attr = active.data.attributes.get("_SWAY") or active.data.attributes.new("_SWAY", "FLOAT", "POINT")
        for d, v in zip(attr.data, sway):
            d.value = v
    for o in others:
        bpy.context.scene.collection.objects.unlink(o)
        bpy.data.objects.remove(o)
    return {"FINISHED"}


def mode_set(mode="OBJECT"):
    return {"FINISHED"}


def parent_set(type="OBJECT", **_):
    bpy = _bpy()
    active = bpy.context.view_layer.objects.active
    for o in _selected():
        if o is not active:
            o.parent = active
    return {"FINISHED"}


def modifier_apply(modifier="", **_):
    return {"FINISHED"}


def delete(**_):
    bpy = _bpy()
    for o in _selected():
        bpy.context.scene.collection.objects.unlink(o)
        bpy.data.objects.remove(o)
    return {"FINISHED"}


object.select_all = select_all
object.transform_apply = transform_apply
object.join = join
object.mode_set = mode_set
object.parent_set = parent_set
object.modifier_apply = modifier_apply
object.delete = delete


def primitive_cube_add(size=2.0, location=(0, 0, 0), **_):
    h = size / 2
    pts = [(x, y, z) for z in (-h, h) for y in (-h, h) for x in (-h, h)]
    faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    return _added("Cube", pts, faces, location)


def primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(0, 0, 0), **_):
    pts = [(0, 0, -radius)]
    for r in range(1, ring_count):
        lat = math.pi * r / ring_count - math.pi / 2
        for s in range(segments):
            lon = 2 * math.pi * s / segments
            pts.append((radius * math.cos(lat) * math.cos(lon), radius * math.cos(lat) * math.sin(lon), radius * math.sin(lat)))
    pts.append((0, 0, radius))
    faces = []
    top = len(pts) - 1
    for s in range(segments):
        faces.append((0, 1 + (s + 1) % segments, 1 + s))
    for r in range(ring_count - 2):
        a, b = 1 + r * segments, 1 + (r + 1) * segments
        for s in range(segments):
            n = (s + 1) % segments
            faces.append((a + s, a + n, b + n, b + s))
    last = 1 + (ring_count - 2) * segments
    for s in range(segments):
        faces.append((last + s, last + (s + 1) % segments, top))
    return _added("Sphere", pts, faces, location)


def primitive_cylinder_add(vertices=32, radius=1.0, depth=2.0, location=(0, 0, 0), **_):
    return primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius, depth=depth, location=location, name="Cylinder")


def primitive_cone_add(vertices=32, radius1=1.0, radius2=0.0, depth=2.0, location=(0, 0, 0), name="Cone", **_):
    pts = []
    for z, r in ((-depth / 2, radius1), (depth / 2, radius2)):
        if r > 0:
            pts += [(r * math.cos(2 * math.pi * s / vertices), r * math.sin(2 * math.pi * s / vertices), z) for s in range(vertices)]
        else:
            pts.append((0, 0, z))
    faces = []
    if radius1 > 0 and radius2 > 0:
        for s in range(vertices):
            n = (s + 1) % vertices
            faces.append((s, n, vertices + n, vertices + s))
        faces.append(tuple(reversed(range(vertices))))
        faces.append(tuple(range(vertices, 2 * vertices)))
    elif radius1 > 0:
        for s in range(vertices):
            faces.append((s, (s + 1) % vertices, vertices))
        faces.append(tuple(reversed(range(vertices))))
    else:
        for s in range(vertices):
            faces.append((0, 1 + (s + 1) % vertices, 1 + s))
        faces.append(tuple(range(1, vertices + 1)))
    return _added(name, pts, faces, location)


mesh.primitive_cube_add = primitive_cube_add
mesh.primitive_uv_sphere_add = primitive_uv_sphere_add
mesh.primitive_cylinder_add = primitive_cylinder_add
mesh.primitive_cone_add = primitive_cone_add


def gltf(filepath="", **_):
    _bpy()._write(filepath)
    return {"FINISHED"}


export_scene.gltf = gltf
