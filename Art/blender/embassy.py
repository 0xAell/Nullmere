"""The Embassy, where the city receives its allies' envoys and sends out its
own, its five levels the tiers of one file, each within a work's slot and
facing +z:
1. a guesthouse of daub under thatch, the House's banner on a pole before
   it, an envoy's tent and a hitching post;
2. a hall of timber on a stone footing, three poles before it flying the
   House's banner and two allies' pennants, a mounting block;
3. the hall in stone under slate, a porch on posts at its door, a basin of
   water in the yard, a fourth pole;
4. a gatehouse arch at the yard's front, its lanterns lit, a guest wing of
   timber beside the hall;
5. a bell tower at the hall's end, its bell swinging, a row of five poles
   flying the House's and its allies' colours.
Close: the doors' boards and the windows' sills, the poles' finials, the
basin's coping, the porch's rafters and the bell's frame. A vane turns on
the hall's ridge at every level, and from the fifth the bell swings.

    python Art/blender/embassy.py Art/models/embassy.glb
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from building import *
from common import *
from works import *

reset()
LEVELS = [1, 2, 3, 4, 5]

yard = material("plain_earth_yard", (0.31, 0.29, 0.25))
stone = material("plain_stone", (0.52, 0.51, 0.49))
dark_stone = material("plain_stone_dark", (0.37, 0.37, 0.38))
pale_stone = material("plain_stone_pale", (0.68, 0.67, 0.64))
ashlar = material("plain_stone_ashlar", (0.8, 0.8, 0.78))
timber = material("plain_timber", (0.29, 0.21, 0.15))
dark = material("plain_timber_dark", (0.19, 0.14, 0.11))
pale = material("plain_timber_pale", (0.45, 0.37, 0.28))
grey = material("plain_timber_grey", (0.42, 0.39, 0.35))
thatch = material("plain_thatch", (0.47, 0.41, 0.29))
slate = material("plain_slate", (0.23, 0.24, 0.28))
daub = material("plain_daub", (0.61, 0.56, 0.47))
canvas = material("plain_canvas", (0.6, 0.55, 0.45))
water = material("plain_water", (0.23, 0.24, 0.28))
iron = material("metal_iron", (0.36, 0.37, 0.4), roughness=0.5, metallic=0.6)
bronze = material("metal_bronze", (0.55, 0.4, 0.2), roughness=0.4, metallic=0.7)
gold = material("metal_gold", (0.8, 0.62, 0.25), roughness=0.35, metallic=0.8)
banner = material("cloth_banner", (0.78, 0.78, 0.78))
# Allies' colours: a madder red, a weld yellow and a sea-wool blue.
madder = material("plain_madder", (0.55, 0.16, 0.12))
weld = material("plain_weld", (0.55, 0.49, 0.27))
seawool = material("plain_seawool", (0.3, 0.4, 0.5))
window = material("glow_candle", (1.0, 0.8, 0.52))

# The vane on the hall's ridge at each level, and the bell at the fifth.
VANES = {1: (0.0, 0.17, -0.09), 2: (0.0, 0.2, -0.1), 3: (0.0, 0.22, -0.1), 4: (-0.04, 0.22, -0.11), 5: (-0.04, 0.23, -0.11)}
BELL = (0.17, 0.25, -0.12)
rig = work_rig([("vane@%d" % level, pivot, (0, 1, 0)) for level, pivot in VANES.items()] + [("bell@5", BELL, (1, 0, 0))])
ground(pad(tagged("pad", []), 0.31, yard), rig)


def piece(name, levels, far, fine=()):
    """A level's pieces joined, far and near."""
    tags = level_tags(levels)
    if far:
        join(tagged(name, tags), list(far))
    if fine:
        join(tagged(name + " close", tags) + "!fine", list(fine))


def gather(*parts):
    far, fine = [], []
    for a, b in parts:
        far += a
        fine += b
    return far, fine


# MARK: What it is built of

def envoys_hall(at_point, width, depth, height, wall, roof, footing=None, turn=0.0, windows=2):
    """The envoys' hall: gabled, its door between lit windows, a sill under
    each, the door's boards."""
    body, close = hall("embassy hall", width, depth, height, wall, roof, dark, pitch=0.8, footing=footing)
    far, fine = list(body), list(close)
    face = depth / 2
    far.append(block("door", (-0.016, 0.0, face), (0.016, min(0.07, height - 0.01), face + 0.004), dark))
    for k in range(windows):
        x = (-1 if k % 2 == 0 else 1) * width * (0.22 + 0.14 * (k // 2))
        far.append(lit("window", (x, height * 0.55, face + 0.002), 0.018, 0.024, 0.0, window))
        fine.append(block("sill", (x - 0.012, height * 0.55 - 0.015, face), (x + 0.012, height * 0.55 - 0.012, face + 0.006), stone))
    for k in range(4):
        fine.append(block("door board", (-0.012 + k * 0.008 - 0.001, 0.002, face + 0.004), (-0.012 + k * 0.008 + 0.001, 0.066, face + 0.0055),
                          timber))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def pole(at_point, height, cloth, name, tail=True):
    """A flagpole in its stone, a gilt finial, its flag flying."""
    x0, _, z0 = at_point
    far = [rings("pole stone", [(0.012, -0.02), (0.011, 0.012), (0.0, 0.016)], 6, stone, centre=(x0, z0)),
           rod("flagpole", (x0, 0.0, z0), (x0, height, z0), 0.0025, dark, sides=5)]
    flag(name, (x0, height - 0.004, z0), 0.04, 0.026, cloth, turn=0.25, tail=tail)
    fine = [rings("finial", [(0.004, height), (0.0, height + 0.012)], 4, gold, centre=(x0, z0))]
    return far, fine


def envoy_tent(at_point, turn=0.0):
    """An envoy's round tent, its cone of canvas on a centre pole, a pennant
    on its top."""
    x0, _, z0 = at_point
    far = [rings("tent", [(0.045, 0.0), (0.045, 0.03), (0.0, 0.08)], 8, canvas, centre=(x0, z0)),
           rod("tent pole", (x0, 0.075, z0), (x0, 0.1, z0), 0.0018, dark, sides=4),
           block("tent door", (x0 - 0.01, 0.0, z0 + 0.04), (x0 + 0.01, 0.026, z0 + 0.0455), dark)]
    return far, []


def hitching(at_point, turn=0.0):
    """A hitching rail on two posts, a mounting block of stone beside it."""
    far = [rod("hitch post", (dx, 0.0, 0.0), (dx, 0.04, 0.0), 0.003, dark, sides=4) for dx in (-0.03, 0.03)]
    far.append(lath("hitch rail", (-0.034, 0.038, 0.0), (0.034, 0.038, 0.0), 0.005, 0.005, timber))
    far.append(block("mounting block", (0.04, 0.0, -0.012), (0.066, 0.016, 0.012), stone))
    far.append(block("mounting step", (0.04, 0.0, 0.012), (0.066, 0.008, 0.022), stone))
    for obj in far:
        placed(obj, at_point, turn)
    return far, []


def porch(at_point, width, depth, height):
    """A porch on four posts before the door, under its own small gable."""
    x0, _, z0 = at_point
    far = []
    for dx in (-width / 2, width / 2):
        far.append(rod("porch post", (x0 + dx, 0.0, z0 + depth), (x0 + dx, height, z0 + depth), 0.003, dark, sides=4))
    far.append(gable_roof("porch roof", (x0, z0 + depth / 2), width + 0.01, depth + 0.01, height, 0.025, slate, overhang=0.006, along="z",
                          thickness=0.004))
    fine = [lath("porch rafter", (x0 - width / 2 + width * k / 3, height, z0), (x0 - width / 2 + width * k / 3, height, z0 + depth), 0.003, 0.003, dark)
            for k in range(4)]
    return far, fine


def basin(at_point, radius):
    """A round basin of stone with water standing in it."""
    x0, _, z0 = at_point
    far = [rings("basin", [(radius, -0.02), (radius, 0.022), (radius - 0.008, 0.022), (radius - 0.008, 0.012)], 12, pale_stone, centre=(x0, z0),
                 caps=(True, False)),
           rings("basin water", [(radius - 0.008, 0.016), (0.0, 0.016)], 12, water, centre=(x0, z0)),
           rings("basin spout", [(0.006, 0.016), (0.004, 0.05), (0.008, 0.055), (0.0, 0.06)], 6, stone, centre=(x0, z0))]
    fine = [rings("coping", [(radius + 0.002, 0.02), (radius + 0.002, 0.026), (radius - 0.01, 0.026), (radius - 0.01, 0.022)], 12, stone,
                  centre=(x0, z0), caps=(False, False))]
    return far, fine


def gatehouse(at_point, width):
    """An arch over the way in: two piers of stone, the lintel and its
    coping, a lantern lit on each pier."""
    x0, _, z0 = at_point
    far = []
    for dx in (-width / 2, width / 2):
        far.append(block("gate pier", (x0 + dx - 0.014, -0.02, z0 - 0.014), (x0 + dx + 0.014, 0.1, z0 + 0.014), ashlar))
        far.append(lit("gate lantern", (x0 + dx, 0.108, z0), 0.009, 0.014, 0.0, window, depth=0.009))
    far.append(block("gate lintel", (x0 - width / 2 - 0.016, 0.1, z0 - 0.016), (x0 + width / 2 + 0.016, 0.122, z0 + 0.016), stone))
    far.append(block("gate coping", (x0 - width / 2 - 0.02, 0.122, z0 - 0.02), (x0 + width / 2 + 0.02, 0.128, z0 + 0.02), dark_stone))
    fine = [block("pier course", (x0 + dx - 0.0155, y - 0.0012, z0 - 0.0155), (x0 + dx + 0.0155, y + 0.0012, z0 + 0.0155), stone)
            for dx in (-width / 2, width / 2) for y in (0.03, 0.06, 0.09)]
    return far, fine


def bell_tower(at_point, height):
    """A square bell tower of ashlar, open at its top under a pyramid of
    slate, its bell hung in the opening."""
    x0, _, z0 = at_point
    s = 0.036
    far = [block("bell tower", (x0 - s, -0.04, z0 - s), (x0 + s, height, z0 + s), ashlar)]
    for dx in (-s, s):
        for dz in (-s, s):
            far.append(block("bell pier", (x0 + dx - 0.007, height, z0 + dz - 0.007), (x0 + dx + 0.007, height + 0.05, z0 + dz + 0.007), ashlar))
    far.append(hip_roof("bell roof", (x0, z0), 2 * s, 2 * s, height + 0.05, 0.05, slate, overhang=0.01, thickness=0.006))
    far.append(lit("tower window", (x0, height * 0.6, z0 + s + 0.001), 0.012, 0.024, 0.0, window))
    fine = [block("bell frame", (x0 - s, height + 0.042, z0 - 0.003), (x0 + s, height + 0.047, z0 + 0.003), dark)]
    for y in (height * 0.33, height * 0.66):
        fine.append(block("string course", (x0 - s - 0.002, y - 0.002, z0 - s - 0.002), (x0 + s + 0.002, y + 0.002, z0 + s + 0.002), stone))
    return far, fine


def vane(level):
    """A vane on the hall's ridge, an arrow and its tail, its own part to
    turn in the wind."""
    x, y, z = VANES[level]
    pieces = [rod("vane spindle", (x, y, z), (x, y + 0.03, z), 0.0012, iron, sides=3),
              lath("vane arrow", (x - 0.018, y + 0.024, z), (x + 0.018, y + 0.024, z), 0.002, 0.002, iron),
              slab("vane tail", [(x - 0.018, y + 0.019, z), (x - 0.03, y + 0.019, z), (x - 0.03, y + 0.029, z), (x - 0.018, y + 0.029, z)], gold,
                   0.0015, normal=(0, 0, 1))]
    obj = join(tagged("vane", level_tags([level])), pieces)
    on(obj, rig, "vane@%d" % level)


def bell():
    """The bell itself, hung in the tower's top, its own part to swing."""
    x, y, z = BELL
    obj = join(tagged("bell", ["5"]), [rings("bell", [(0.0, y - 0.004), (0.006, y - 0.006), (0.009, y - 0.018), (0.013, y - 0.026),
                                                      (0.0, y - 0.026)], 8, bronze, centre=(x, z))])
    on(obj, rig, "bell@5")


# MARK: The levels

# 1. A guesthouse, the House's banner, an envoy's tent.
far, fine = gather(envoys_hall((0.0, 0, -0.09), 0.18, 0.11, 0.08, daub, thatch), pole((-0.06, 0, 0.1), 0.18, banner, "house banner@1"),
                   envoy_tent((0.17, 0, 0.08)), hitching((-0.17, 0, 0.12), turn=0.4))
piece("embassy", [1], far, fine)

# 2. A hall of timber; three poles flying the House's and two allies'.
far, fine = gather(envoys_hall((0.0, 0, -0.1), 0.22, 0.12, 0.09, timber, thatch, footing=stone, windows=4),
                   pole((-0.08, 0, 0.1), 0.2, banner, "house banner@2"), pole((0.0, 0, 0.12), 0.18, madder, "ally pennant red@2"),
                   pole((0.08, 0, 0.1), 0.18, weld, "ally pennant gold@2"), envoy_tent((0.19, 0, 0.1)), hitching((-0.19, 0, 0.1), turn=0.6))
piece("embassy", [2], far, fine)

# 3. The hall in stone; a porch at its door, a basin in the yard.
far, fine = gather(envoys_hall((0.0, 0, -0.1), 0.22, 0.12, 0.1, pale_stone, slate, footing=dark_stone, windows=4), porch((0.0, 0, -0.04), 0.06, 0.035, 0.07),
                   basin((0.0, 0, 0.12), 0.045), pole((-0.12, 0, 0.08), 0.22, banner, "house banner@3"),
                   pole((-0.17, 0, 0.0), 0.19, madder, "ally pennant red@3"), pole((0.12, 0, 0.08), 0.19, weld, "ally pennant gold@3"),
                   pole((0.17, 0, 0.0), 0.19, seawool, "ally pennant blue@3"), hitching((0.17, 0, 0.17), turn=-0.6))
piece("embassy", [3], far, fine)

# 4. A gatehouse at the front, a guest wing beside the hall.
far, fine = gather(envoys_hall((-0.04, 0, -0.11), 0.2, 0.12, 0.1, pale_stone, slate, footing=dark_stone, windows=4),
                   porch((-0.04, 0, -0.05), 0.06, 0.035, 0.07), envoys_hall((0.17, 0, -0.06), 0.1, 0.09, 0.075, timber, slate, turn=-1.4, windows=2),
                   basin((-0.03, 0, 0.08), 0.04), gatehouse((0.0, 0, 0.21), 0.07), pole((-0.16, 0, 0.06), 0.22, banner, "house banner@4"),
                   pole((-0.2, 0, -0.02), 0.19, madder, "ally pennant red@4"), pole((0.11, 0, 0.1), 0.19, weld, "ally pennant gold@4"),
                   pole((0.16, 0, 0.06), 0.19, seawool, "ally pennant blue@4"))
piece("embassy", [4], far, fine)

# 5. The bell tower at the hall's end, a row of five poles.
far, fine = gather(envoys_hall((-0.04, 0, -0.11), 0.2, 0.12, 0.1, pale_stone, slate, footing=dark_stone, windows=4),
                   porch((-0.04, 0, -0.05), 0.06, 0.035, 0.07), bell_tower((0.17, 0, -0.12), 0.2),
                   envoys_hall((0.17, 0, 0.0), 0.09, 0.08, 0.07, timber, slate, turn=-1.4, windows=2), basin((-0.03, 0, 0.08), 0.04),
                   gatehouse((0.0, 0, 0.21), 0.07), pole((-0.18, 0, 0.1), 0.24, banner, "house banner@5"),
                   pole((-0.21, 0, 0.0), 0.2, madder, "ally pennant red@5"), pole((-0.14, 0, 0.16), 0.2, weld, "ally pennant gold@5"),
                   pole((0.12, 0, 0.13), 0.2, seawool, "ally pennant blue@5"), pole((0.18, 0, 0.09), 0.2, banner, "second banner@5"))
piece("embassy", [5], far, fine)

for level in LEVELS:
    vane(level)
bell()

# Petals of straw and the yard's wear, at every level.
litter = []
for index in range(10):
    angle = index * 2.39996
    r = 0.12 + 0.16 * ((index * 31) % 13) / 13
    x, z = r * math.cos(angle), r * math.sin(angle)
    litter.append(lath("straw", (x, 0.013, z), (x + 0.016, 0.013, z + 0.007), 0.003, 0.002, thatch if index % 2 == 0 else pale))
join("litter!fine", litter)

# The vane turning to the wind, the bell swinging at the fifth.
idle(rig, turns=[("vane@%d" % level, (0, 1, 0), lambda u: 0.8 * math.sin(2 * math.pi * u)) for level in LEVELS]
     + [("bell@5", (1, 0, 0), lambda u: 0.5 * math.sin(4 * math.pi * u))])

finish_building(out_path("Art/models/embassy.glb"), [str(level) for level in LEVELS])
