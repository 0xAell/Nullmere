"""The Tavern, where the city's folk drink, its news is told and its
commanders are sought out, its five levels the tiers of one file, each
within a work's slot and facing +z:
1. an alehouse of daub under thatch, its ale-stake jutting over the door
   with a garland hung from it, a bench and casks by the door;
2. the alehouse grown longer, a trestle table under an awning before it,
   a brewing lean-to with its copper over the fire, casks stacked;
3. a malt kiln beside it, round under its cone, the cowl on its top
   turning in the wind, the tavern's ale on tables in the yard;
4. the tavern rebuilt, stone below and timber jettied out above, a hop
   yard on its poles, a cart of casks;
5. the great tavern: a gallery along its front, a second kiln, lanterns
   strung over the tables and the House's banners at its door.
Close: the doors' boards, the windows' lights, the casks' hoops, the
tankards on the tables, the hops' bines and the kiln's courses. The
garland swings at the first two levels; the cowl turns from the third.

    python Art/blender/tavern.py Art/models/tavern.glb
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
white = material("plain_stone_white", (0.84, 0.84, 0.82))
timber = material("plain_timber", (0.29, 0.21, 0.15))
dark = material("plain_timber_dark", (0.19, 0.14, 0.11))
pale = material("plain_timber_pale", (0.45, 0.37, 0.28))
grey = material("plain_timber_grey", (0.42, 0.39, 0.35))
thatch = material("plain_thatch", (0.47, 0.41, 0.29))
slate = material("plain_slate", (0.23, 0.24, 0.28))
daub = material("plain_daub", (0.61, 0.56, 0.47))
canvas = material("plain_canvas", (0.6, 0.55, 0.45))
ivy = material("foliage_ivy", (0.25, 0.38, 0.18))
iron = material("metal_iron", (0.36, 0.37, 0.4), roughness=0.5, metallic=0.6)
awning_cloth = material("house_awning", (0.78, 0.78, 0.78))
banner = material("cloth_banner", (0.78, 0.78, 0.78))
fire = material("glow_fire", (1.0, 0.68, 0.32))
window = material("glow_candle", (1.0, 0.8, 0.52))

# The garland on the ale-stake at the first two levels; the kiln's cowl
# from the third.
GARLANDS = {1: (0.05, 0.12, 0.08), 2: (0.03, 0.13, 0.07)}
COWLS = {3: (0.17, 0.235, -0.11), 4: (0.18, 0.235, -0.13), 5: (0.18, 0.235, -0.13)}
rig = work_rig([("garland@%d" % level, pivot, (1, 0, 0)) for level, pivot in GARLANDS.items()]
               + [("kiln cowl@%d" % level, pivot, (0, 1, 0)) for level, pivot in COWLS.items()])
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


# MARK: What a tavern keeps

def cask(at_point, lying=False):
    """A cask, standing or lying on its side in a cradle, hooped near."""
    x, y, z = at_point
    if lying:
        far = [rod("cask", (x - 0.022, y + 0.02, z), (x + 0.022, y + 0.02, z), 0.018, pale, sides=7)]
        fine = [rod("hoop", (x + dx - 0.0025, y + 0.02, z), (x + dx + 0.0025, y + 0.02, z), 0.0188, iron, sides=7, caps=(False, False))
                for dx in (-0.012, 0.012)]
        far.append(block("cradle", (x - 0.016, y, z - 0.014), (x + 0.016, y + 0.006, z + 0.014), dark))
    else:
        far = [rings("cask", [(0.016, y), (0.02, y + 0.022), (0.016, y + 0.044)], 7, pale, centre=(x, z))]
        fine = [rings("hoop", [(0.0185, y + h - 0.003), (0.0195, y + h), (0.0185, y + h + 0.003)], 7, iron, centre=(x, z), caps=(False, False))
                for h in (0.008, 0.036)]
    return far, fine


def casks(at_point, count, lying=False):
    far, fine = [], []
    for index in range(count):
        row, layer = index % 3, index // 3
        p = (at_point[0] + (row - 1) * (0.046 if lying else 0.042) + layer * 0.02, at_point[1] + layer * (0.04 if lying else 0.044),
             at_point[2] + (0 if lying else (row % 2) * 0.01))
        a, b = cask(p, lying)
        far += a
        fine += b
    return far, fine


def table(at_point, turn=0.0, tankards=3):
    """A trestle table with its two benches, tankards on it."""
    far = [block("table", (-0.04, 0.032, -0.014), (0.04, 0.037, 0.014), timber)]
    for dz in (-0.03, 0.03):
        far.append(block("bench", (-0.038, 0.018, dz - 0.007), (0.038, 0.022, dz + 0.007), grey))
    fine = []
    for dx in (-0.032, 0.032):
        fine.append(block("trestle", (dx - 0.002, 0.0, -0.012), (dx + 0.002, 0.032, 0.012), dark))
        for dz in (-0.03, 0.03):
            fine.append(block("bench leg", (dx - 0.002, 0.0, dz - 0.005), (dx + 0.002, 0.018, dz + 0.005), dark))
    for k in range(tankards):
        fine.append(rings("tankard", [(0.004, 0.037), (0.004, 0.047), (0.0, 0.047)], 5, pale, centre=(-0.024 + k * 0.022, (k % 2) * 0.006 - 0.003)))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def alehouse(at_point, width, depth, height, wall, roof, turn=0.0, footing=None):
    """The alehouse: a gabled house, its door with a lit window either side,
    a bench by the door."""
    body, close = hall("alehouse", width, depth, height, wall, roof, dark, pitch=0.8, footing=footing)
    far, fine = list(body), list(close)
    face = depth / 2
    far.append(block("door", (-0.014, 0.0, face), (0.014, min(0.065, height - 0.008), face + 0.004), dark))
    for x in (-width * 0.3, width * 0.3):
        far.append(lit("window", (x, height * 0.55, face + 0.002), 0.02, 0.018, 0.0, window))
        fine.append(block("sill", (x - 0.013, height * 0.55 - 0.012, face), (x + 0.013, height * 0.55 - 0.009, face + 0.006), timber))
    for k in range(4):
        fine.append(block("door board", (-0.011 + k * 0.0073 - 0.001, 0.002, face + 0.004), (-0.011 + k * 0.0073 + 0.001, 0.06, face + 0.0055),
                          timber))
    far.append(block("door bench", (width * 0.3 - 0.03, 0.018, face + 0.012), (width * 0.3 + 0.03, 0.023, face + 0.024), grey))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def jettied(at_point, width, depth, low, high, turn=0.0, gallery=False):
    """A house of two storeys, stone below and timber above jettied out over
    the yard, under slate; its door, lit windows above and below, a gallery
    along its front if `gallery`."""
    far, fine = [], []
    jetty = 0.012
    far.append(block("ground storey", (-width / 2, -0.04, -depth / 2), (width / 2, low, depth / 2), pale_stone))
    upper, close = hall("upper storey", width + 0.004, depth + 2 * jetty, high - low, daub, slate, dark, pitch=0.7)
    for obj in upper + close:
        placed(obj, (0, low, 0))
    far += upper
    fine += close
    far.append(block("jetty", (-width / 2 - 0.004, low - 0.008, -depth / 2 - jetty), (width / 2 + 0.004, low, depth / 2 + jetty), dark))
    face = depth / 2
    far.append(block("door", (-0.016, 0.0, face), (0.016, low - 0.01, face + 0.004), dark))
    for x in (-width * 0.32, width * 0.32):
        far.append(lit("window", (x, low * 0.55, face + 0.002), 0.02, 0.022, 0.0, window))
        far.append(lit("upper window", (x, low + (high - low) * 0.5, face + jetty + 0.002), 0.02, 0.022, 0.0, window))
    for k in range(5):
        x = -width / 2 + width * k / 4
        fine.append(block("stud", (x - 0.003, low, face + jetty), (x + 0.003, high, face + jetty + 0.003), dark))
    if gallery:
        far.append(block("gallery floor", (-width / 2, low + 0.004, face + jetty), (width / 2, low + 0.01, face + jetty + 0.03), timber))
        far.append(lath("gallery rail", (-width / 2, low + 0.035, face + jetty + 0.03), (width / 2, low + 0.035, face + jetty + 0.03), 0.004, 0.004,
                        dark))
        for k in range(5):
            x = -width / 2 + width * k / 4
            fine.append(rod("gallery post", (x, low + 0.01, face + jetty + 0.028), (x, low + 0.035, face + jetty + 0.028), 0.002, dark, sides=4))
            far.append(rod("gallery prop", (x, 0.0, face + jetty + 0.028), (x, low + 0.004, face + jetty + 0.028), 0.0028, dark, sides=4))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def kiln(at_point):
    """A malt kiln: round, its wall whitened, under a steep cone; the cowl
    on its top is its own part to turn in the wind."""
    x0, _, z0 = at_point
    body, close = round_house("kiln", 0.045, 0.14, white, slate, stone, dark, rise=0.08, sides=10)
    for obj in body + close:
        placed(obj, (x0, 0, z0))
    far = list(body)
    far.append(block("kiln door", (x0 - 0.01, 0.0, z0 + 0.042), (x0 + 0.01, 0.03, z0 + 0.048), dark))
    far.append(lit("kiln fire", (x0, 0.012, z0 + 0.047), 0.012, 0.01, 0.0, fire, depth=0.006))
    return far, list(close)


def cowl(level):
    """The kiln's white cowl on its top, its vane behind it."""
    x, y, z = COWLS[level]
    pieces = [rings("cowl", [(0.0, y), (0.014, y + 0.004), (0.014, y + 0.03), (0.0, y + 0.036)], 6, white, centre=(x, z), squash=0.8),
              slab("cowl vane", [(x, y + 0.006, z - 0.012), (x, y + 0.03, z - 0.012), (x, y + 0.026, z - 0.036), (x, y + 0.01, z - 0.036)], white,
                   0.003, normal=(1, 0, 0))]
    obj = join(tagged("cowl", level_tags([level])), pieces)
    on(obj, rig, "kiln cowl@%d" % level)


def ale_stake(level):
    """The ale-stake jutting from over the door, its garland of greenery
    hung from its end, its own part to swing."""
    x, y, z = GARLANDS[level]
    frame = [lath("ale-stake", (x, y, z - 0.06), (x, y, z + 0.004), 0.005, 0.005, dark)]
    garland = [rings("garland", [(0.0, y - 0.045), (0.013, y - 0.036), (0.012, y - 0.02), (0.0, y - 0.012)], 6, ivy, centre=(x, z)),
               rod("garland cord", (x, y, z), (x, y - 0.014, z), 0.0008, dark, sides=3, caps=(False, False))]
    obj = join(tagged("garland", level_tags([level])), garland)
    on(obj, rig, "garland@%d" % level)
    return frame


def brewhouse(at_point, turn=0.0):
    """A brewing lean-to: posts and a roof of one slope against a back of
    boards, the copper on its fire, mash tubs."""
    w, d = 0.1, 0.07
    far = [block("brew back", (-w / 2, 0.0, -d / 2), (w / 2, 0.09, -d / 2 + 0.006), grey)]
    for x in (-w / 2, w / 2):
        far.append(rod("brew post", (x, 0.0, d / 2), (x, 0.065, d / 2), 0.003, dark, sides=4))
    far.append(slab("brew roof", [(-w / 2 - 0.01, 0.095, -d / 2), (w / 2 + 0.01, 0.095, -d / 2), (w / 2 + 0.01, 0.06, d / 2 + 0.012),
                                  (-w / 2 - 0.01, 0.06, d / 2 + 0.012)], thatch, 0.006, normal=(0, 1, 0.5)))
    far.append(rings("copper hearth", [(0.022, 0.0), (0.022, 0.016), (0.016, 0.018)], 8, dark_stone, centre=(-0.02, 0.0)))
    far.append(rings("copper", [(0.014, 0.016), (0.02, 0.026), (0.019, 0.036), (0.0, 0.037)], 8, iron, centre=(-0.02, 0.0)))
    far.append(lit("copper fire", (-0.02, 0.008, 0.022), 0.012, 0.008, 0.0, fire, depth=0.004))
    far.append(rings("mash tub", [(0.016, 0.0), (0.018, 0.026), (0.0, 0.024)], 7, pale, centre=(0.025, 0.004)))
    fine = [rings("tub hoop", [(0.0175, 0.017), (0.0185, 0.02)], 7, iron, centre=(0.025, 0.004), caps=(False, False))]
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def awning(at_point, width, depth, high, low, turn=0.0):
    """An awning of the House's cloth on four poles over the tables."""
    far = []
    for dx in (-width / 2, width / 2):
        far.append(rod("awning pole", (dx, 0.0, -depth / 2), (dx, high, -depth / 2), 0.0025, dark, sides=4))
        far.append(rod("awning pole", (dx, 0.0, depth / 2), (dx, low, depth / 2), 0.0025, dark, sides=4))
    far.append(slab("awning", [(-width / 2 - 0.006, high, -depth / 2), (width / 2 + 0.006, high, -depth / 2), (width / 2 + 0.006, low, depth / 2),
                               (-width / 2 - 0.006, low, depth / 2)], awning_cloth, 0.003, normal=(0, 1, (high - low) / depth)))
    for obj in far:
        placed(obj, at_point, turn)
    return far, []


def hop_yard(at_point, rows, cols):
    """Hops climbing their poles on strings, green to the tops."""
    x0, _, z0 = at_point
    far, fine = [], []
    for r in range(rows):
        for c in range(cols):
            x, z = x0 + c * 0.028, z0 + r * 0.03
            far.append(rod("hop pole", (x, 0.0, z), (x, 0.11, z), 0.0018, dark, sides=4))
            far.append(rings("bine", [(0.007, 0.02), (0.009, 0.06), (0.006, 0.1), (0.0, 0.112)], 5, ivy, centre=(x, z), twist=r + c))
    return far, fine


def cart(at_point, turn=0.0):
    """A cart of casks, its wheels solid afar with spokes near, its shafts
    down."""
    pieces = [block("cart bed", (-0.05, 0.028, -0.026), (0.05, 0.036, 0.026), timber)]
    fine = []
    for z in (-0.031, 0.031):
        pieces.append(rod("wheel", (0.0, 0.024, z - 0.003), (0.0, 0.024, z + 0.003), 0.024, dark, sides=10))
        fine.append(lath("spoke", (-0.021, 0.024, z * 1.12), (0.021, 0.024, z * 1.12), 0.004, 0.0015, timber))
        fine.append(lath("spoke", (0.0, 0.003, z * 1.12), (0.0, 0.045, z * 1.12), 0.004, 0.0015, timber))
    for dz in (-0.014, 0.014):
        pieces.append(lath("shaft", (0.05, 0.032, dz), (0.11, 0.004, dz), 0.004, 0.004, dark))
    for dx in (-0.025, 0.022):
        pieces.append(rod("cart cask", (dx - 0.018, 0.054, 0.0), (dx + 0.018, 0.054, 0.0), 0.016, pale, sides=7))
    for obj in pieces + fine:
        placed(obj, at_point, turn)
    return pieces, fine


def lanterns(a, b, count):
    """Lanterns strung on a cord between two poles."""
    far = [rod("lantern pole", (p[0], 0.0, p[2]), (p[0], p[1] + 0.006, p[2]), 0.0022, dark, sides=4) for p in (a, b)]
    fine = [rod("lantern cord", a, b, 0.0007, dark, sides=3, caps=(False, False))]
    for k in range(count):
        t = (k + 1) / (count + 1)
        p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t - 0.01 * math.sin(math.pi * t), a[2] + (b[2] - a[2]) * t)
        far.append(lit("lantern", (p[0], p[1] - 0.006, p[2]), 0.007, 0.01, 0.0, window, depth=0.007))
    return far, fine


# MARK: The levels

# 1. The alehouse, its ale-stake and garland, casks and a bench.
far, fine = gather(alehouse((0.0, 0, -0.06), 0.18, 0.12, 0.075, daub, thatch), casks((0.16, 0, 0.06), 2), table((-0.13, 0, 0.12), turn=0.3))
far += ale_stake(1)
piece("tavern", [1], far, fine)

# 2. Longer, a table under an awning, the brewing lean-to and its copper.
far, fine = gather(alehouse((0.0, 0, -0.08), 0.24, 0.12, 0.08, daub, thatch), brewhouse((-0.2, 0, -0.04), turn=1.2),
                   awning((0.05, 0, 0.14), 0.12, 0.07, 0.085, 0.07), table((0.05, 0, 0.14), tankards=4), casks((0.2, 0, 0.0), 4, lying=True),
                   table((-0.13, 0, 0.15), turn=0.5))
far += ale_stake(2)
piece("tavern", [2], far, fine)

# 3. A malt kiln beside it, its cowl turning; the ale out on the tables.
far, fine = gather(alehouse((-0.05, 0, -0.08), 0.24, 0.12, 0.085, daub, slate, footing=stone), kiln((0.17, 0, -0.11)),
                   brewhouse((-0.22, 0, 0.03), turn=1.3), awning((0.04, 0, 0.15), 0.13, 0.07, 0.085, 0.07), table((0.04, 0, 0.15), tankards=4),
                   table((-0.1, 0, 0.17), turn=0.4), casks((0.2, 0, 0.06), 4, lying=True))
cowl(3)
piece("tavern", [3], far, fine)

# 4. Rebuilt, stone and timber jettied; the hop yard, a cart of casks.
far, fine = gather(jettied((-0.05, 0, -0.09), 0.22, 0.12, 0.09, 0.17), kiln((0.18, 0, -0.13)), hop_yard((-0.25, 0, -0.05), 3, 2),
                   awning((0.02, 0, 0.15), 0.13, 0.07, 0.085, 0.07), table((0.02, 0, 0.15), tankards=4), table((-0.13, 0, 0.16), turn=0.4),
                   cart((0.17, 0, 0.12), turn=-0.6), casks((0.22, 0, -0.02), 3))
cowl(4)
piece("tavern", [4], far, fine)

# 5. The great tavern: a gallery along its front, lanterns over the
#    tables, banners at its door, the brewhouse and casks.
far, fine = gather(jettied((-0.05, 0, -0.1), 0.24, 0.12, 0.09, 0.18, gallery=True), kiln((0.18, 0, -0.13)), hop_yard((-0.26, 0, -0.06), 3, 2),
                   table((0.02, 0, 0.16), tankards=4), table((-0.12, 0, 0.17), turn=0.4), table((0.15, 0, 0.13), turn=-0.5),
                   lanterns((-0.18, 0.11, 0.2), (0.21, 0.11, 0.1), 5), casks((0.23, 0, -0.01), 4, lying=True), brewhouse((-0.24, 0, 0.1), turn=1.3))
for side, x in (("L", -0.1), ("R", 0.0)):
    flag("tavern banner %s@5" % side, (x, 0.08, 0.014), 0.024, 0.055, banner, turn=-math.pi / 2, tail=True)
    far.append(rod("banner rod", (x, 0.08, -0.04), (x, 0.08, 0.016), 0.002, iron, sides=4))
cowl(5)
piece("tavern", [5], far, fine)

# Straw and spilt barley about the yard, at every level.
litter = []
for index in range(12):
    angle = index * 2.39996
    r = 0.12 + 0.16 * ((index * 31) % 13) / 13
    x, z = r * math.cos(angle), r * math.sin(angle)
    litter.append(lath("straw", (x, 0.013, z), (x + 0.016, 0.013, z + 0.007), 0.003, 0.002, thatch if index % 2 == 0 else pale))
join("litter!fine", litter)

# The garland swinging at the first two levels, the cowl turning to the
# wind from the third.
idle(rig, turns=[("garland@%d" % level, (1, 0, 0), lambda u: 0.3 * swing(u)) for level in GARLANDS]
     + [("kiln cowl@%d" % level, (0, 1, 0), lambda u: 0.7 * math.sin(2 * math.pi * u)) for level in COWLS])

finish_building(out_path("Art/models/tavern.glb"), [str(level) for level in LEVELS])
