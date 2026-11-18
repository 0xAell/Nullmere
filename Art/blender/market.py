"""The Market, where the city's goods are bought and sold, its five levels
the tiers of one file, each within a work's slot and facing +z:
1. three stalls under awnings of the House's cloth, crates and baskets of
   what is sold, the weigh-beam on its post;
2. more stalls about a market cross on its steps;
3. a market hall: an open storey on stone piers, stalls in its shade, a
   storey of timber over it;
4. the weighhouse of stone beside it, a cart unloading, more stalls;
5. the hall crowned with a lantern-turret and its bell, the House's
   banners from its eaves, a well for the market folk.
Close: the stalls' boards and what lies on them, the baskets' weave, the
cross's steps, the hall's studs and the beam's pans. The weigh-beam tips
at every level.

    python Art/blender/market.py Art/models/market.glb
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
timber = material("plain_timber", (0.29, 0.21, 0.15))
dark = material("plain_timber_dark", (0.19, 0.14, 0.11))
pale = material("plain_timber_pale", (0.45, 0.37, 0.28))
grey = material("plain_timber_grey", (0.42, 0.39, 0.35))
thatch = material("plain_thatch", (0.47, 0.41, 0.29))
straw = material("plain_thatch_straw", (0.62, 0.55, 0.36))
slate = material("plain_slate", (0.23, 0.24, 0.28))
daub = material("plain_daub", (0.61, 0.56, 0.47))
canvas = material("plain_canvas", (0.6, 0.55, 0.45))
linen = material("plain_linen", (0.7, 0.67, 0.6))
grain = material("foliage_grain", (0.66, 0.6, 0.4))
leaf = material("foliage_ivy", (0.25, 0.38, 0.18))
madder = material("plain_madder", (0.55, 0.16, 0.12))
weld = material("plain_weld", (0.55, 0.49, 0.27))
moonsalt = material("crystal_moonsalt", (0.88, 0.91, 0.95), roughness=0.1)
water = material("plain_water", (0.23, 0.24, 0.28))
iron = material("metal_iron", (0.36, 0.37, 0.4), roughness=0.5, metallic=0.6)
bronze = material("metal_bronze", (0.55, 0.4, 0.2), roughness=0.4, metallic=0.7)
awning_cloth = material("house_awning", (0.78, 0.78, 0.78))
banner = material("cloth_banner", (0.78, 0.78, 0.78))
window = material("glow_candle", (1.0, 0.8, 0.52))

# The weigh-beam's pivot at each level, the beam along x, tipping about z.
BEAMS = {1: (0.16, 0.1, 0.1), 2: (0.19, 0.1, 0.06), 3: (0.2, 0.1, 0.1), 4: (0.06, 0.1, 0.2), 5: (0.07, 0.1, 0.21)}
rig = work_rig([("weigh beam@%d" % level, pivot, (0, 0, 1)) for level, pivot in BEAMS.items()])
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


# MARK: What is sold, and what it is sold from

WARES = [grain, madder, leaf, weld, moonsalt, linen]


def stall(at_point, turn=0.0, wares=0):
    """A stall: its counter of boards on trestles, an awning of the House's
    cloth on four poles over it, what it sells heaped on the counter and in
    baskets before it."""
    w, d = 0.07, 0.04
    far = [block("counter", (-w / 2, 0.03, -d / 2), (w / 2, 0.036, d / 2), timber),
           block("counter front", (-w / 2, 0.006, d / 2 - 0.004), (w / 2, 0.03, d / 2), grey)]
    for dx in (-w / 2 - 0.004, w / 2 + 0.004):
        far.append(rod("stall pole", (dx, 0.0, -d / 2 - 0.006), (dx, 0.085, -d / 2 - 0.006), 0.0022, dark, sides=4))
        far.append(rod("stall pole", (dx, 0.0, d / 2 + 0.012), (dx, 0.07, d / 2 + 0.012), 0.0022, dark, sides=4))
    far.append(slab("stall awning", [(-w / 2 - 0.01, 0.086, -d / 2 - 0.01), (w / 2 + 0.01, 0.086, -d / 2 - 0.01), (w / 2 + 0.01, 0.068, d / 2 + 0.022),
                                     (-w / 2 - 0.01, 0.068, d / 2 + 0.022)], awning_cloth, 0.003, normal=(0, 1, 0.4)))
    fine = []
    for k in range(3):
        mat = WARES[(wares + k) % len(WARES)]
        x = -0.022 + k * 0.022
        far.append(rings("heap", [(0.009, 0.036), (0.006, 0.043), (0.0, 0.046)], 5, mat, centre=(x, 0.0)))
    for k in range(2):
        x = -0.02 + k * 0.04
        far.append(rings("basket", [(0.008, 0.0), (0.011, 0.016), (0.0105, 0.018)], 7, straw, centre=(x, d / 2 + 0.02), caps=(True, False)))
        fine.append(rings("basket fill", [(0.0, 0.014), (0.0098, 0.016), (0.0, 0.02)], 7, WARES[(wares + k + 3) % len(WARES)],
                          centre=(x, d / 2 + 0.02)))
    for dx in (-w / 2 + 0.006, w / 2 - 0.006):
        fine.append(block("trestle", (dx - 0.002, 0.0, -d / 2 + 0.004), (dx + 0.002, 0.03, d / 2 - 0.006), dark))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def crates(at_point, count):
    """Crates set down, some on others."""
    far, fine = [], []
    for k in range(count):
        row, layer = k % 3, k // 3
        x, y, z = at_point[0] + (row - 1) * 0.034 + layer * 0.016, at_point[1] + layer * 0.03, at_point[2] + (row % 2) * 0.008
        far.append(block("crate", (x - 0.015, y, z - 0.015), (x + 0.015, y + 0.03, z + 0.015), pale))
        fine.append(block("crate slat", (x - 0.016, y + 0.024, z - 0.016), (x + 0.016, y + 0.027, z + 0.016), timber))
    return far, fine


def weigh_post(level):
    """The weigh-beam on its post, its pans hung from its ends; the beam and
    pans its own part to tip."""
    x, y, z = BEAMS[level]
    frame = [rod("weigh post", (x, 0.0, z), (x, y + 0.006, z), 0.003, dark, sides=4),
             block("weigh foot", (x - 0.012, 0.0, z - 0.012), (x + 0.012, 0.008, z + 0.012), stone)]
    moving = [lath("weigh beam", (x - 0.04, y, z), (x + 0.04, y, z), 0.003, 0.003, iron)]
    for dx in (-0.036, 0.036):
        moving.append(rod("pan cord", (x + dx, y, z), (x + dx, y - 0.04, z), 0.0006, linen, sides=3, caps=(False, False)))
        moving.append(rings("pan", [(0.0, y - 0.044), (0.012, y - 0.042), (0.013, y - 0.039)], 7, bronze, centre=(x + dx, z), caps=(True, False)))
    moving.append(rings("weighed", [(0.0, y - 0.042), (0.008, y - 0.04), (0.0, y - 0.034)], 5, grain, centre=(x - 0.036, z)))
    obj = join(tagged("weigh beam", level_tags([level])), moving)
    on(obj, rig, "weigh beam@%d" % level)
    return frame


def market_cross(at_point):
    """A market cross on its stepped plinth: an octagonal shaft, a cross head."""
    x0, _, z0 = at_point
    far = [rings("cross step", [(0.04, -0.02), (0.04, 0.012), (0.03, 0.012), (0.03, 0.024), (0.02, 0.024), (0.02, 0.034), (0.0, 0.034)], 8,
                 pale_stone, centre=(x0, z0), twist=math.pi / 8),
           rings("cross shaft", [(0.007, 0.034), (0.005, 0.13)], 8, stone, centre=(x0, z0), twist=math.pi / 8),
           block("cross arm", (x0 - 0.018, 0.112, z0 - 0.004), (x0 + 0.018, 0.12, z0 + 0.004), stone),
           block("cross head", (x0 - 0.004, 0.13, z0 - 0.004), (x0 + 0.004, 0.142, z0 + 0.004), stone)]
    fine = [rings("step edge", [(0.0405, 0.0105), (0.0405, 0.0125)], 8, stone, centre=(x0, z0), twist=math.pi / 8, caps=(False, False))]
    return far, fine


def market_hall(at_point, width, depth, low, high, cupola=False):
    """A market hall: an open storey on piers of stone, a storey of timber
    and daub over it under slate, lit windows; crowned with a lantern-turret
    if `cupola`."""
    x0, _, z0 = at_point
    far, fine = [], []
    piers = 4
    for k in range(piers):
        x = x0 - width / 2 + 0.01 + (width - 0.02) * k / (piers - 1)
        for z in (z0 - depth / 2 + 0.01, z0 + depth / 2 - 0.01):
            far.append(block("pier", (x - 0.008, -0.02, z - 0.008), (x + 0.008, low, z + 0.008), pale_stone))
    far.append(block("hall floor", (x0 - width / 2, 0.0, z0 - depth / 2), (x0 + width / 2, 0.006, z0 + depth / 2), stone))
    upper, close = hall("market hall", width + 0.01, depth + 0.01, high - low, daub, slate, dark, pitch=0.7)
    for obj in upper + close:
        placed(obj, (x0, low, z0))
    far += upper
    fine += close
    far.append(block("hall beam", (x0 - width / 2 - 0.006, low - 0.01, z0 - depth / 2 - 0.006), (x0 + width / 2 + 0.006, low,
                                                                                                 z0 + depth / 2 + 0.006), dark))
    for x in (-width * 0.3, 0.0, width * 0.3):
        far.append(lit("hall window", (x0 + x, low + (high - low) * 0.55, z0 + depth / 2 + 0.008), 0.016, 0.02, 0.0, window))
    for k in range(7):
        x = x0 - width / 2 + width * k / 6
        fine.append(block("stud", (x - 0.0025, low, z0 + depth / 2 + 0.005), (x + 0.0025, high, z0 + depth / 2 + 0.008), dark))
    if cupola:
        ridge = high + (depth + 0.01) * 0.7 / 2
        far.append(block("turret", (x0 - 0.016, ridge - 0.02, z0 - 0.016), (x0 + 0.016, ridge + 0.03, z0 + 0.016), timber))
        far.append(hip_roof("turret roof", (x0, z0), 0.032, 0.032, ridge + 0.03, 0.035, slate, overhang=0.006, thickness=0.003))
        far.append(lit("turret light", (x0, ridge + 0.012, z0 + 0.0165), 0.012, 0.014, 0.0, window, depth=0.004))
        fine.append(rings("turret bell", [(0.0, ridge + 0.02), (0.006, ridge + 0.016), (0.008, ridge + 0.006), (0.0, ridge + 0.006)], 6, bronze,
                          centre=(x0, z0)))
    return far, fine


def weighhouse(at_point, turn=0.0):
    """The weighhouse: a small house of stone under slate, its door and a
    lit window, the city's measures hung by the door."""
    body, close = hall("weighhouse", 0.09, 0.08, 0.075, stone, slate, dark, pitch=0.8, footing=dark_stone)
    far, fine = list(body), list(close)
    far.append(block("weighhouse door", (-0.012, 0.0, 0.04), (0.012, 0.055, 0.044), dark))
    far.append(lit("weighhouse window", (0.028, 0.045, 0.042), 0.014, 0.016, 0.0, window))
    for k in range(3):
        fine.append(rings("measure", [(0.004 + k * 0.001, 0.035), (0.0045 + k * 0.001, 0.045 + k * 0.003)], 5, bronze,
                          centre=(-0.026 + k * 0.009, 0.046)))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def cart(at_point, turn=0.0):
    """A cart set down with its shafts on the ground, sacks and crates on it;
    wheels solid afar, spokes near."""
    pieces = [block("cart bed", (-0.05, 0.028, -0.026), (0.05, 0.036, 0.026), timber)]
    fine = []
    for z in (-0.031, 0.031):
        pieces.append(rod("wheel", (0.0, 0.024, z - 0.003), (0.0, 0.024, z + 0.003), 0.024, dark, sides=10))
        fine.append(lath("spoke", (-0.021, 0.024, z * 1.12), (0.021, 0.024, z * 1.12), 0.004, 0.0015, timber))
        fine.append(lath("spoke", (0.0, 0.003, z * 1.12), (0.0, 0.045, z * 1.12), 0.004, 0.0015, timber))
    for dz in (-0.014, 0.014):
        pieces.append(lath("shaft", (0.05, 0.032, dz), (0.11, 0.004, dz), 0.004, 0.004, dark))
    pieces.append(block("cart crate", (-0.042, 0.036, -0.02), (-0.006, 0.066, 0.02), pale))
    pieces.append(tied_sack("cart sack", (0.02, 0.036, 0.0), 0.02, canvas))
    for obj in pieces + fine:
        placed(obj, at_point, turn)
    return pieces, fine


def well(at_point):
    """A well: its round curb of stone, a frame and roof over it, a bucket on
    the rope."""
    x0, _, z0 = at_point
    far = [rings("well curb", [(0.026, -0.02), (0.026, 0.03), (0.02, 0.03), (0.02, 0.02)], 10, stone, centre=(x0, z0), caps=(True, False)),
           rings("well water", [(0.02, 0.012), (0.0, 0.012)], 10, water, centre=(x0, z0))]
    for dx in (-0.024, 0.024):
        far.append(rod("well post", (x0 + dx, 0.03, z0), (x0 + dx, 0.085, z0), 0.0025, dark, sides=4))
    far.append(gable_roof("well roof", (x0, z0), 0.04, 0.066, 0.083, 0.02, slate, overhang=0.004, along="x", thickness=0.003))
    fine = [rod("windlass", (x0 - 0.024, 0.07, z0), (x0 + 0.024, 0.07, z0), 0.003, timber, sides=5),
            rod("well rope", (x0, 0.068, z0), (x0, 0.045, z0), 0.0007, linen, sides=3, caps=(False, False)),
            rings("well bucket", [(0.006, 0.034), (0.007, 0.046)], 6, timber, centre=(x0, z0))]
    return far, fine


# MARK: The levels

# 1. Three stalls, crates, the weigh-beam.
far, fine = gather(stall((-0.13, 0, -0.1), turn=0.5, wares=0), stall((0.0, 0, -0.15), wares=2), stall((0.13, 0, -0.1), turn=-0.5, wares=4),
                   crates((-0.12, 0, 0.12), 3))
far += weigh_post(1)
piece("market", [1], far, fine)

# 2. Stalls about the market cross.
far, fine = gather(stall((-0.16, 0, -0.06), turn=0.9, wares=0), stall((-0.07, 0, -0.17), turn=0.3, wares=1), stall((0.07, 0, -0.17), turn=-0.3, wares=2),
                   stall((0.16, 0, -0.06), turn=-0.9, wares=3), stall((-0.15, 0, 0.12), turn=2.2, wares=4), market_cross((0.0, 0, 0.0)),
                   crates((0.08, 0, 0.18), 4))
far += weigh_post(2)
piece("market", [2], far, fine)

# 3. The market hall on its piers, stalls in its shade and about it.
far, fine = gather(market_hall((0.0, 0, -0.1), 0.22, 0.11, 0.07, 0.14), stall((-0.05, 0, -0.1), wares=1), stall((0.05, 0, -0.1), wares=3),
                   stall((-0.18, 0, 0.08), turn=1.3, wares=0), stall((-0.06, 0, 0.17), turn=0.3, wares=5), market_cross((0.1, 0, 0.12)),
                   crates((0.21, 0, -0.02), 4))
far += weigh_post(3)
piece("market", [3], far, fine)

# 4. The weighhouse beside it, a cart unloading.
far, fine = gather(market_hall((-0.04, 0, -0.11), 0.2, 0.11, 0.07, 0.14), stall((-0.09, 0, -0.11), wares=1), stall((0.01, 0, -0.11), wares=3),
                   weighhouse((0.19, 0, -0.07), turn=-1.2), stall((-0.2, 0, 0.07), turn=1.3, wares=0), stall((-0.1, 0, 0.17), turn=0.4, wares=5),
                   market_cross((0.15, 0, 0.12)), cart((0.02, 0, 0.13), turn=0.2), crates((0.22, 0, 0.05), 3))
far += weigh_post(4)
piece("market", [4], far, fine)

# 5. The hall crowned, banners from its eaves, a well.
far, fine = gather(market_hall((-0.04, 0, -0.11), 0.22, 0.11, 0.07, 0.15, cupola=True), stall((-0.1, 0, -0.11), wares=1),
                   stall((0.02, 0, -0.11), wares=3), weighhouse((0.2, 0, -0.06), turn=-1.2), stall((-0.21, 0, 0.06), turn=1.3, wares=0),
                   stall((-0.12, 0, 0.17), turn=0.5, wares=5), well((0.16, 0, 0.12)), cart((-0.02, 0, 0.15), turn=0.2), crates((0.23, 0, 0.04), 3))
for side, x in (("L", -0.11), ("R", 0.03)):
    flag("hall banner %s@5" % side, (x, 0.14, -0.045), 0.022, 0.05, banner, turn=-math.pi / 2, tail=True)
piece("market", [5], far, fine)

# Straw, husks and a dropped cabbage leaf or two, at every level.
litter = []
for index in range(12):
    angle = index * 2.39996
    r = 0.12 + 0.16 * ((index * 31) % 13) / 13
    x, z = r * math.cos(angle), r * math.sin(angle)
    litter.append(lath("husk", (x, 0.013, z), (x + 0.014, 0.013, z + 0.006), 0.003, 0.002, straw if index % 3 else leaf))
join("litter!fine", litter)

# The weigh-beam tipping as the goods are weighed.
idle(rig, turns=[("weigh beam@%d" % level, (0, 0, 1), lambda u: 0.25 * math.sin(2 * math.pi * u)) for level in LEVELS])

finish_building(out_path("Art/models/market.glb"), [str(level) for level in LEVELS])
