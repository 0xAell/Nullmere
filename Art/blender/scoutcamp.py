"""The Scout Camp, where the city's scouts ride out from to learn what the
land holds and come back to tell it, its five levels the tiers of one file,
each within a work's slot and facing +z:
1. two tents of hide about a fire with a pot hung over it, a lookout post
   with its ladder up to a little platform, saddles on a rail, packs;
2. a hut of logs for the scouts' gear, the lookout a platform on four poles
   railed about, a map table under an awning;
3. a palisade behind the yard, a lean-to stable with its hay rack and
   trough, the lookout roofed in shingle;
4. a lookout tower of stone under a cone, a pennant over it, the scouts'
   lodge of timber, a brazier lit at the tower's foot;
5. a watchtower of stone, crenellated, its fire basket burning on its top,
   the House's banners on the lodge, a dovecote for the messenger birds.
Close: the tents' seams and guy ropes, the ladders' rungs, the logs'
ends, the palisade's lashings, the map on its table and the stones about
the fire. The fire leaps at every level.

    python Art/blender/scoutcamp.py Art/models/scoutcamp.glb
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
earth = material("plain_earth", (0.24, 0.21, 0.18))
stone = material("plain_stone", (0.52, 0.51, 0.49))
dark_stone = material("plain_stone_dark", (0.37, 0.37, 0.38))
pale_stone = material("plain_stone_pale", (0.68, 0.67, 0.64))
timber = material("plain_timber", (0.29, 0.21, 0.15))
dark = material("plain_timber_dark", (0.19, 0.14, 0.11))
pale = material("plain_timber_pale", (0.45, 0.37, 0.28))
grey = material("plain_timber_grey", (0.42, 0.39, 0.35))
bark = material("plain_timber_bark", (0.21, 0.17, 0.14))
thatch = material("plain_thatch", (0.47, 0.41, 0.29))
straw = material("plain_thatch_straw", (0.62, 0.55, 0.36))
slate = material("plain_slate", (0.23, 0.24, 0.28))
hide = material("plain_leather", (0.42, 0.33, 0.24))
leather = material("plain_leather_dark", (0.22, 0.16, 0.12))
canvas = material("plain_canvas", (0.6, 0.55, 0.45))
linen = material("plain_linen", (0.7, 0.67, 0.6))
iron = material("metal_iron", (0.36, 0.37, 0.4), roughness=0.5, metallic=0.6)
banner = material("cloth_banner", (0.78, 0.78, 0.78))
fire = material("glow_fire", (1.0, 0.68, 0.32))
window = material("glow_candle", (1.0, 0.8, 0.52))
water = material("plain_water", (0.23, 0.24, 0.28))

# Where each level's fire burns, and how large: on the ground by the tents
# for the first three, at the tower's foot at the fourth and on its top at
# the fifth.
FIRES = {1: ((0.05, 0.012, 0.1), 0.018), 2: ((0.06, 0.012, 0.13), 0.018), 3: ((0.05, 0.012, 0.15), 0.018),
         4: ((-0.1, 0.07, 0.02), 0.014), 5: ((-0.12, 0.345, -0.12), 0.024)}
rig = work_rig([("camp fire@%d" % level, foot, (0, 1, 0)) for level, (foot, _) in FIRES.items()])
ground(pad(tagged("pad", []), 0.31, yard), rig)


def piece(name, levels, far, fine=()):
    """A level's pieces joined, far and near."""
    tags = level_tags(levels)
    if far:
        join(tagged(name, tags), list(far))
    if fine:
        join(tagged(name + " close", tags) + "!fine", list(fine))


def flame(level):
    """The fire itself, its own part to leap: a body of flame and tongues
    licking up about it."""
    (x, y, z), size = FIRES[level]
    pieces = [rings("flame", [(size * 0.9, y), (size, y + size * 0.3), (size * 0.6, y + size * 0.9), (size * 0.25, y + size * 1.5),
                              (0.0, y + size * 2.1)], 6, fire, centre=(x, z))]
    for index in range(3):
        angle = index * 2.1 + 0.4
        px, _, pz = on_ring(size * 0.55, y, angle)
        pieces.append(rings("tongue", [(size * 0.3, y), (size * 0.15, y + size * 0.7), (0.0, y + size * 1.25)], 4, window,
                            centre=(x + px, z + pz), twist=angle))
    obj = join(tagged("fire", level_tags([level])), pieces)
    on(obj, rig, "camp fire@%d" % level)


# MARK: The camp's makings

def tent(at_point, w, d, h, mat, turn=0.0):
    """A ridge tent of hide on two poles, its back shut and its flaps
    either side of the way in, guyed fore and aft."""
    x0, _, z0 = at_point
    back, front = -d / 2, d / 2
    far = [slab("tent side", [(-w, 0.0, back), (-w, 0.0, front), (0, h, front), (0, h, back)], mat, 0.004, normal=(-1, 1, 0)),
           slab("tent side", [(w, 0.0, front), (w, 0.0, back), (0, h, back), (0, h, front)], mat, 0.004, normal=(1, 1, 0)),
           slab("tent back", [(-w + 0.004, 0.0, back + 0.002), (w - 0.004, 0.0, back + 0.002), (0, h - 0.004, back + 0.002)], mat, 0.003,
                normal=(0, 0, 1))]
    for side in (-1, 1):
        far.append(slab("tent flap", [(side * (w - 0.004), 0.0, front - 0.002), (side * 0.016, 0.0, front - 0.002), (0, h - 0.004, front - 0.002)],
                        mat, 0.003, normal=(0, 0, 1)))
    far.append(rod("tent pole", (0, 0.0, front + 0.004), (0, h + 0.014, front + 0.004), 0.0028, dark, sides=4))
    far.append(rod("tent pole", (0, 0.0, back - 0.004), (0, h + 0.006, back - 0.004), 0.0028, dark, sides=4))
    fine = [rod("guy rope", (0, h + 0.008, front + 0.004), (0, 0.004, front + 0.045), 0.0009, linen, sides=3, caps=(False, False)),
            rod("guy rope", (0, h + 0.004, back - 0.004), (0, 0.004, back - 0.04), 0.0009, linen, sides=3, caps=(False, False)),
            lath("seam", (-w * 0.5, h * 0.5, back - 0.0005), (-w * 0.5, h * 0.5, front + 0.0005), 0.003, 0.003, leather),
            lath("seam", (w * 0.5, h * 0.5, back - 0.0005), (w * 0.5, h * 0.5, front + 0.0005), 0.003, 0.003, leather)]
    for obj in far + fine:
        placed(obj, (x0, 0, z0), turn)
    return far, fine


def hearth(at_point, ring=True, pot=True):
    """The fire's place: a ring of stones, its logs, and a pot hung over it
    from a crossbar on two forked sticks."""
    x0, _, z0 = at_point
    far = [rings("ashes", [(0.03, 0.0), (0.028, 0.006), (0.0, 0.008)], 7, dark_stone, centre=(x0, z0))]
    for index in range(3):
        a = index * 2.1
        far.append(log("firewood", (x0 + 0.022 * math.cos(a), 0.008, z0 + 0.022 * math.sin(a)), (x0 - 0.004 * math.cos(a), 0.016,
                                                                                                 z0 - 0.004 * math.sin(a)), 0.004, sides=4))
    fine = []
    if ring:
        for index in range(8):
            a = index * math.pi / 4
            fine.append(rings("hearth stone", [(0.007, 0.0), (0.006, 0.008), (0.0, 0.01)], 5, stone, centre=(x0 + 0.036 * math.cos(a),
                                                                                                           z0 + 0.036 * math.sin(a))))
    if pot:
        for dx in (-0.034, 0.034):
            far.append(rod("crook", (x0 + dx, 0.0, z0), (x0 + dx, 0.07, z0), 0.0025, timber, sides=4))
        far.append(rod("crossbar", (x0 - 0.038, 0.068, z0), (x0 + 0.038, 0.068, z0), 0.002, timber, sides=4))
        fine.append(rod("pot chain", (x0, 0.067, z0), (x0, 0.05, z0), 0.0008, iron, sides=3, caps=(False, False)))
        far.append(rings("pot", [(0.008, 0.032), (0.013, 0.038), (0.012, 0.05), (0.0, 0.051)], 7, iron, centre=(x0, z0)))
    return far, fine


def saddle_rail(at_point, count, turn=0.0):
    """A rail on two posts, saddles laid over it, their girths hanging."""
    far = [rod("rail post", (x, 0.0, 0.0), (x, 0.05, 0.0), 0.003, dark, sides=4) for x in (-0.05, 0.05)]
    far.append(lath("rail", (-0.056, 0.05, 0.0), (0.056, 0.05, 0.0), 0.006, 0.006, timber))
    fine = []
    for index in range(count):
        x = -0.035 + index * 0.035
        far.append(block("saddle", (x - 0.012, 0.05, -0.014), (x + 0.012, 0.062, 0.014), leather))
        fine.append(block("girth", (x - 0.003, 0.025, -0.0145), (x + 0.003, 0.05, -0.0125), hide))
        fine.append(block("girth", (x - 0.003, 0.025, 0.0125), (x + 0.003, 0.05, 0.0145), hide))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def packs(at_point, count):
    """Packs and bedrolls set down by the tents."""
    out = []
    for index in range(count):
        a = index * 2.2
        x, z = at_point[0] + 0.022 * math.cos(a), at_point[2] + 0.022 * math.sin(a)
        if index % 2 == 0:
            out.append(block("pack", (x - 0.01, 0.0, z - 0.008), (x + 0.01, 0.022, z + 0.008), hide, turn=a, about=(x, 0, z)))
        else:
            out.append(rod("bedroll", (x - 0.014, 0.007, z), (x + 0.014, 0.007, z), 0.007, canvas, sides=6))
    return out


def lookout(at_point, height, roofed=False, four=False):
    """A lookout: a post, or four poles braced, carrying a platform railed
    about, a ladder up to it, under a shingle roof if `roofed`."""
    x0, _, z0 = at_point
    far, fine = [], []
    half = 0.03 if four else 0.022
    corners = [(x0 + dx, z0 + dz) for dx in (-half, half) for dz in (-half, half)] if four else [(x0, z0)]
    for x, z in corners:
        far.append(rod("lookout pole", (x, 0.0, z), (x, height + (0.05 if four else 0.0), z), 0.005 if four else 0.006, bark, sides=5))
    far.append(block("platform", (x0 - half - 0.01, height - 0.006, z0 - half - 0.01), (x0 + half + 0.01, height, z0 + half + 0.01), timber))
    if four:
        for (ax, az), (bx, bz) in (((x0 - half, z0 - half), (x0 + half, z0 - half)), ((x0 + half, z0 - half), (x0 + half, z0 + half)),
                                   ((x0 + half, z0 + half), (x0 - half, z0 + half)), ((x0 - half, z0 + half), (x0 - half, z0 - half))):
            far.append(lath("lookout rail", (ax, height + 0.03, az), (bx, height + 0.03, bz), 0.004, 0.004, dark))
            fine.append(lath("brace", (ax, height * 0.2, az), (bx, height * 0.75, bz), 0.003, 0.003, dark))
    fine += ladder("lookout ladder", (x0, 0.0, z0 + half + 0.04), (x0, height, z0 + half + 0.012), 0.02, int(height / 0.025), timber)
    if roofed:
        far.append(hip_roof("lookout roof", (x0, z0), 2 * half + 0.02, 2 * half + 0.02, height + 0.07, 0.04, slate, overhang=0.012,
                            thickness=0.004))
    return far, fine


def log_hut(at_point, width, depth, height, roof, turn=0.0):
    """A hut of logs laid crosswise at its corners under a pitched roof,
    its door in the front."""
    x0, _, z0 = at_point
    body, close = hall("hut", width, depth, height, timber, roof, dark, pitch=0.8)
    far, fine = list(body), list(close)
    far.append(block("hut door", (-0.016, 0.0, depth / 2), (0.016, height - 0.012, depth / 2 + 0.004), dark))
    # The logs' ends at the corners, one over another.
    for k in range(int(height / 0.018)):
        y = 0.01 + k * 0.018
        for sx in (-1, 1):
            for sz in (-1, 1):
                fine.append(rod("log end", (sx * (width / 2 + 0.008), y, sz * (depth / 2 - 0.004)), (sx * (width / 2 - 0.002), y, sz * (depth / 2 - 0.004)),
                                0.007, pale, sides=5))
    for obj in far + fine:
        placed(obj, (x0, 0, z0), turn)
    return far, fine


def map_table(at_point, turn=0.0):
    """A trestle table under an awning, the map spread on it held down by
    stones, a lantern lit at its corner."""
    far = [block("table top", (-0.04, 0.034, -0.022), (0.04, 0.04, 0.022), timber)]
    for dx in (-0.032, 0.032):
        far.append(lath("trestle", (dx, 0.0, -0.016), (dx, 0.034, 0.0), 0.004, 0.004, dark))
        far.append(lath("trestle", (dx, 0.0, 0.016), (dx, 0.034, 0.0), 0.004, 0.004, dark))
    for dx, dz in ((-0.05, -0.03), (0.05, -0.03), (-0.05, 0.03), (0.05, 0.03)):
        far.append(rod("awning post", (dx, 0.0, dz), (dx, 0.085 - (0.01 if dz > 0 else 0.0), dz), 0.0025, dark, sides=4))
    far.append(slab("awning", [(-0.058, 0.086, -0.036), (0.058, 0.086, -0.036), (0.058, 0.074, 0.038), (-0.058, 0.074, 0.038)], canvas, 0.003,
                    normal=(0, 1, 0.16)))
    fine = [block("map", (-0.03, 0.04, -0.016), (0.026, 0.0415, 0.017), linen)]
    for dx, dz in ((-0.028, -0.014), (0.024, 0.015)):
        fine.append(rings("map stone", [(0.004, 0.0415), (0.0, 0.047)], 4, stone, centre=(dx, dz)))
    far.append(lit("lantern", (0.034, 0.05, -0.016), 0.008, 0.012, 0.0, window, depth=0.008))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def palisade(start_angle, end_angle, radius, count):
    """Sharpened stakes along an arc behind the yard, lashed at their
    middles."""
    far, fine = [], []
    for index in range(count):
        a = start_angle + (end_angle - start_angle) * index / (count - 1)
        x, z = radius * math.cos(a), -radius * math.sin(a)
        top = 0.1 + 0.012 * ((index * 7) % 3)
        far.append(rings("stake", [(0.009, -0.03), (0.009, top), (0.0, top + 0.02)], 5, bark, centre=(x, z), twist=index))
        if index < count - 1:
            b = start_angle + (end_angle - start_angle) * (index + 1) / (count - 1)
            fine.append(rod("lashing", (x, 0.07, z), (radius * math.cos(b), 0.07, -radius * math.sin(b)), 0.0015, linen, sides=3,
                            caps=(False, False)))
    return far, fine


def stable(at_point, turn=0.0):
    """A lean-to stable: posts and a sloping roof against a back wall of
    boards, a hay rack and a trough of water before it."""
    w, d = 0.13, 0.07
    far = [block("stable back", (-w / 2, 0.0, -d / 2), (w / 2, 0.09, -d / 2 + 0.008), grey)]
    for x in (-w / 2, 0.0, w / 2):
        far.append(rod("stable post", (x, 0.0, d / 2), (x, 0.065, d / 2), 0.0035, dark, sides=4))
    far.append(slab("stable roof", [(-w / 2 - 0.01, 0.095, -d / 2), (w / 2 + 0.01, 0.095, -d / 2), (w / 2 + 0.01, 0.06, d / 2 + 0.014),
                                    (-w / 2 - 0.01, 0.06, d / 2 + 0.014)], thatch, 0.006, normal=(0, 1, 0.5)))
    far.append(block("hay rack", (-w / 2 + 0.01, 0.035, -d / 2 + 0.008), (w / 2 - 0.01, 0.06, -d / 2 + 0.03), straw))
    far.append(block("trough", (-0.03, 0.0, d / 2 + 0.02), (0.03, 0.016, d / 2 + 0.036), timber))
    fine = [block("trough water", (-0.027, 0.0, d / 2 + 0.023), (0.027, 0.0165, d / 2 + 0.033), water)]
    for x in (-0.04, -0.02, 0.0, 0.02, 0.04):
        fine.append(lath("rack slat", (x, 0.035, -d / 2 + 0.031), (x, 0.062, -d / 2 + 0.031), 0.003, 0.002, dark))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def tower(at_point, radius, height, crowned=False):
    """A round lookout tower of stone: under a cone, or crenellated about a
    fire basket at its top; a lit loop, its door at the foot."""
    x0, _, z0 = at_point
    far, fine = [], []
    if crowned:
        far.append(rings("tower", [(radius * 1.08, -0.06), (radius, 0.02), (radius, height)], 10, pale_stone, centre=(x0, z0)))
        far.append(rings("tower parapet", [(radius * 1.12, height), (radius * 1.12, height + 0.03), (radius * 0.8, height + 0.03),
                                           (radius * 0.8, height + 0.01)], 10, stone, centre=(x0, z0), caps=(True, False)))
        for index in range(8):
            a = index * math.pi / 4
            px, _, pz = on_ring(radius * 0.97, 0.0, a)
            far.append(block("merlon", (x0 + px - 0.008, height + 0.03, z0 + pz - 0.008), (x0 + px + 0.008, height + 0.05, z0 + pz + 0.008), stone,
                             turn=-a, about=(x0 + px, height + 0.04, z0 + pz)))
        # The fire basket on its post.
        far.append(rod("basket post", (x0, height + 0.01, z0), (x0, height + 0.045, z0), 0.004, iron, sides=4))
        far.append(rings("fire basket", [(0.01, height + 0.04), (0.022, height + 0.05), (0.024, height + 0.062)], 8, iron, caps=(True, False),
                         centre=(x0, z0)))
    else:
        body, close = round_house("tower", radius, height, pale_stone, slate, stone, iron, rise=radius * 1.7, sides=10)
        for obj in body + close:
            placed(obj, (x0, 0, z0))
        far += body
        fine += close
    far.append(lit("tower loop", (x0, height * 0.7, z0 + radius + 0.001), 0.009, 0.02, 0.0, window))
    far.append(block("tower door", (x0 - 0.012, 0.0, z0 + radius - 0.004), (x0 + 0.012, 0.045, z0 + radius + 0.003), dark))
    for k in range(int(height / 0.03)):
        y = 0.03 + k * 0.03
        fine.append(rings("course", [(radius + 0.0012, y - 0.0012), (radius + 0.0012, y + 0.0012)], 10, stone, centre=(x0, z0), caps=(False, False)))
    return far, fine


def dovecote(at_point):
    """A dovecote on its post for the messenger birds."""
    x0, _, z0 = at_point
    far = [rod("dovecote post", (x0, 0, z0), (x0, 0.1, z0), 0.006, dark, sides=6)]
    body, close = round_house("dovecote", 0.03, 0.045, pale_stone, slate, stone, dark, rise=0.035, sides=8)
    for obj in body + close:
        placed(obj, (x0, 0.1, z0))
    far += body
    fine = list(close)
    for index in range(6):
        a = index / 6 * 2 * math.pi
        x, z = x0 + 0.0305 * math.cos(a), z0 - 0.0305 * math.sin(a)
        fine.append(block("hole", (x - 0.004, 0.118, z - 0.002), (x + 0.004, 0.126, z + 0.002), dark, turn=-a - math.pi / 2, about=(x, 0.122, z)))
    return far, fine


def gather(*parts):
    far, fine = [], []
    for a, b in parts:
        far += a
        fine += b
    return far, fine


# MARK: The levels

# 1. Two tents about a fire, a lookout post, saddles and packs.
far, fine = gather(tent((-0.13, 0, -0.06), 0.05, 0.11, 0.07, hide, turn=0.4), tent((0.13, 0, -0.08), 0.05, 0.11, 0.07, hide, turn=-0.3),
                   hearth(FIRES[1][0]), lookout((-0.05, 0, -0.17), 0.14), saddle_rail((0.15, 0, 0.13), 2, turn=-0.5))
far += packs((-0.1, 0, 0.1), 3)
piece("scout camp", [1], far, fine)

# 2. A hut of logs, the lookout on four poles, a map table under an awning.
far, fine = gather(log_hut((0.1, 0, -0.12), 0.14, 0.1, 0.07, thatch, turn=-0.2), tent((-0.16, 0, -0.03), 0.05, 0.11, 0.07, hide, turn=0.5),
                   hearth(FIRES[2][0]), lookout((-0.07, 0, -0.17), 0.17, four=True), map_table((-0.12, 0, 0.15), turn=0.4),
                   saddle_rail((0.2, 0, 0.08), 3, turn=-1.1))
far += packs((0.14, 0, 0.17), 2)
piece("scout camp", [2], far, fine)

# 3. A palisade behind, a lean-to stable, the lookout roofed.
far, fine = gather(log_hut((0.12, 0, -0.1), 0.14, 0.1, 0.075, slate, turn=-0.3), palisade(math.radians(25), math.radians(155), 0.27, 13),
                   hearth(FIRES[3][0]), lookout((-0.04, 0, -0.16), 0.19, roofed=True, four=True), stable((-0.19, 0, -0.02), turn=0.9),
                   map_table((-0.1, 0, 0.17), turn=0.3), saddle_rail((0.21, 0, 0.1), 3, turn=-1.2))
piece("scout camp", [3], far, fine)

# 4. A lookout tower of stone, the scouts' lodge, the brazier at its foot.
far, fine = gather(tower((-0.12, 0, -0.12), 0.05, 0.24), hearth(FIRES[4][0], ring=False, pot=False),
                   log_hut((0.12, 0, -0.1), 0.17, 0.11, 0.085, slate, turn=-0.3), stable((-0.2, 0, 0.09), turn=1.3),
                   map_table((0.02, 0, 0.15), turn=0.1), palisade(math.radians(60), math.radians(150), 0.28, 9),
                   saddle_rail((0.2, 0, 0.11), 3, turn=-1.2))
far.append(rod("brazier", (-0.1, 0.0, 0.02), (-0.1, 0.06, 0.02), 0.004, iron, sides=4))
far.append(rings("brazier bowl", [(0.006, 0.055), (0.018, 0.064), (0.02, 0.072)], 8, iron, caps=(True, False), centre=(-0.1, 0.02)))
flag("tower pennant@4", (-0.12, 0.34, -0.12), 0.04, 0.025, banner, turn=0.4, tail=True)
far.append(rod("pennant staff", (-0.12, 0.31, -0.12), (-0.12, 0.345, -0.12), 0.002, iron, sides=4))
piece("scout camp", [4], far, fine)

# 5. The watchtower crowned with its fire, the lodge with the House's
#    banners, the dovecote.
far, fine = gather(tower((-0.12, 0, -0.12), 0.055, 0.28, crowned=True), log_hut((0.12, 0, -0.1), 0.18, 0.11, 0.09, slate, turn=-0.3),
                   stable((-0.2, 0, 0.1), turn=1.3), map_table((0.02, 0, 0.15), turn=0.1), dovecote((0.21, 0, 0.12)),
                   saddle_rail((0.13, 0, 0.18), 3, turn=-0.6))
for side, dx in (("L", -0.05), ("R", 0.05)):
    x, z = 0.12 + dx * math.cos(-0.3), -0.1 + 0.055 + dx * math.sin(0.3)
    flag("lodge banner %s@5" % side, (x, 0.085, z + 0.01), 0.025, 0.06, banner, turn=-math.pi / 2, tail=True)
piece("scout camp", [5], far, fine)

for level in LEVELS:
    flame(level)

# Trodden ground and kindling about the yard, at every level.
litter = []
for index in range(12):
    angle = index * 2.39996
    r = 0.12 + 0.16 * ((index * 31) % 13) / 13
    x, z = r * math.cos(angle), r * math.sin(angle)
    litter.append(lath("kindling", (x, 0.013, z), (x + 0.016, 0.013, z + 0.008), 0.003, 0.002, bark if index % 2 == 0 else straw))
join("litter!fine", litter)

# The fire leaping, every level's.
idle(rig, stretches=[("camp fire@%d" % level, leaping) for level in LEVELS])

finish_building(out_path("Art/models/scoutcamp.glb"), [str(level) for level in LEVELS])
