"""The Storehouse, where the city keeps its grain, timber, stone and moonsalt
against lean months and raiders, its five levels the tiers of one file,
each within a work's slot and facing +z:
1. a store-shed of planks on a stone footing under thatch, its door barred,
   barrels and sacks under a lean-to at its side, planks and logs stacked;
2. a longer store of timber under slate, its loft door and the hoist beam
   over it, a log rack under its own roof, dressed stone and crates;
3. a warehouse of two storeys, stone below and timber above jettied out
   over the yard, great doors and the loading door over them, the old shed
   kept as a lean-to, a handcart;
4. a strongroom of stone beside it under a hip of slate, its door bound in
   iron, a chest of moonsalt open at its step, crates stacked high;
5. the great storehouse: the warehouse lengthened to three bays and
   buttressed, a watch turret at its corner, the House's banners at its
   doors, a wain loading in the yard.
Close: the planks' joints and battens, the doors' boards and straps, the
barrels' hoops, the crates' slats, the rafters' ends, the stone's courses
and odds and ends about the yard. The hoist swings at the loading door as
the stores go up.

    python Art/blender/storehouse.py Art/models/storehouse.glb
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
thatch = material("plain_thatch", (0.47, 0.41, 0.29))
slate = material("plain_slate", (0.23, 0.24, 0.28))
daub = material("plain_daub", (0.61, 0.56, 0.47))
canvas = material("plain_canvas", (0.6, 0.55, 0.45))
linen = material("plain_linen", (0.7, 0.67, 0.6))
iron = material("metal_iron", (0.36, 0.37, 0.4), roughness=0.5, metallic=0.6)
moonsalt = material("crystal_moonsalt", (0.88, 0.91, 0.95), roughness=0.1)
banner = material("cloth_banner", (0.78, 0.78, 0.78))
window = material("glow_candle", (1.0, 0.8, 0.52))

# Where the hoist's arm turns at each level: by the shed's door on its
# gin pole at the first, over the loading door after.
HOISTS = {1: (0.13, 0.15, 0.06), 2: (0.0, 0.2, 0.065), 3: (0.0, 0.215, 0.083), 4: (-0.04, 0.215, 0.083), 5: (-0.03, 0.235, 0.088)}
rig = work_rig([("store hoist@%d" % level, pivot, (0, 1, 0)) for level, pivot in HOISTS.items()])
ground(pad(tagged("pad", []), 0.31, yard), rig)


def piece(name, levels, far, fine=()):
    """A level's pieces joined, far and near."""
    tags = level_tags(levels)
    if far:
        join(tagged(name, tags), list(far))
    if fine:
        join(tagged(name + " close", tags) + "!fine", list(fine))


# MARK: What is kept

def barrel(at_point, turn=0.0):
    """A barrel hooped with iron, the hoops for the near view."""
    x, y, z = at_point
    far = [rings("barrel", [(0.018, y), (0.022, y + 0.024), (0.018, y + 0.048)], 7, pale, centre=(x, z), twist=turn)]
    fine = [rings("hoop", [(0.0205, y + h - 0.003), (0.0215, y + h), (0.0205, y + h + 0.003)], 7, iron, centre=(x, z), twist=turn,
                  caps=(False, False)) for h in (0.009, 0.039)]
    return far, fine


def barrels(at_point, count, turn=0.0):
    """Barrels stood together, a row and some on top."""
    far, fine = [], []
    for index in range(count):
        row, layer = index % 3, index // 3
        p = (at_point[0] + (row - 1) * 0.046 + layer * 0.023, at_point[1] + layer * 0.048, at_point[2] + (row % 2) * 0.012)
        a, b = barrel(p, turn + index * 0.4)
        far += a
        fine += b
    return far, fine


def crate(at_point, size, turn=0.0):
    """A crate of pale boards, its slats and corners for the near view."""
    x, y, z = at_point
    h = size / 2
    far = [block("crate", (x - h, y, z - h), (x + h, y + size, z + h), pale, turn=turn, about=(x, y, z))]
    fine = []
    for dy in (0.15, 0.85):
        fine.append(block("crate slat", (x - h - 0.001, y + size * dy - 0.002, z - h - 0.001), (x + h + 0.001, y + size * dy + 0.002, z + h + 0.001),
                          timber, turn=turn, about=(x, y, z)))
    return far, fine


def crates(at_point, count, size=0.04, turn=0.0):
    """Crates stacked two high, the upper ones set back."""
    far, fine = [], []
    for index in range(count):
        row, layer = index % 3, index // 3
        p = (at_point[0] + (row - 1) * (size + 0.004) + layer * size * 0.5, at_point[1] + layer * size, at_point[2] - layer * 0.006)
        a, b = crate(p, size, turn + (index % 2) * 0.12)
        far += a
        fine += b
    return far, fine


def sacks(at_point, count):
    out = []
    for index in range(count):
        angle = index * 1.9
        p = (at_point[0] + 0.022 * math.cos(angle), at_point[1] + (index // 3) * 0.02, at_point[2] + 0.022 * math.sin(angle))
        out.append(tied_sack("sack", p, 0.02, canvas))
    return out


def planks(at_point, length, layers, turn=0.0):
    """Sawn planks stacked crosswise on two bearers."""
    out = [block("bearer", (-length / 2 + 0.01, 0.0, z - 0.006), (length / 2 - 0.01, 0.008, z + 0.006), dark) for z in (-0.025, 0.025)]
    for layer in range(layers):
        y = 0.008 + layer * 0.01
        shift = (layer % 2) * 0.006
        out.append(block("plank", (-length / 2 + shift, y, -0.035), (length / 2 + shift, y + 0.008, 0.035), pale if layer % 2 == 0 else grey))
    for obj in out:
        placed(obj, at_point, turn)
    return out


def logs(at_point, length, rows, turn=0.0):
    """Logs stacked in a pyramid along x, their sawn ends pale."""
    out = []
    radius = 0.014
    for row in range(rows):
        count = rows - row
        for k in range(count):
            z = (k - (count - 1) / 2) * radius * 2.05
            y = radius + row * radius * 1.75
            out.append(log("log", (-length / 2, y, z), (length / 2, y, z), radius))
    for obj in out:
        placed(obj, at_point, turn)
    return out


def dressed(at_point, count, turn=0.0):
    """Dressed stone in a squared stack, pale and grey as they came."""
    out = []
    for index in range(count):
        row, layer = index % 3, index // 3
        x, y, z = (row - 1) * 0.036, layer * 0.026, (layer % 2) * 0.006
        out.append(block("ashlar", (x - 0.016, y, z - 0.02), (x + 0.016, y + 0.024, z + 0.02), pale_stone if (index * 7) % 3 else stone))
    for obj in out:
        placed(obj, at_point, turn)
    return out


def moonsalt_chest(at_point, turn=0.0):
    """A chest bound in iron, its lid thrown back on the moonsalt it holds."""
    x0, _, z0 = at_point
    far = [block("chest", (-0.026, 0.0, -0.017), (0.026, 0.03, 0.017), dark),
           block("chest lid", (-0.027, 0.03, -0.026), (0.027, 0.034, -0.017), timber)]
    for k, (dx, dz) in enumerate(((-0.012, -0.004), (0.004, 0.003), (0.014, -0.006), (-0.002, -0.008))):
        far.append(rings("moonsalt", [(0.008, 0.026), (0.0, 0.044 + 0.004 * k)], 4, moonsalt, centre=(dx, dz), twist=0.5 * k))
    fine = [block("chest band", (dx - 0.002, -0.001, -0.018), (dx + 0.002, 0.031, 0.018), iron) for dx in (-0.016, 0.016)]
    fine.append(block("hasp", (-0.004, 0.018, 0.017), (0.004, 0.028, 0.019), iron))
    for obj in far + fine:
        placed(obj, (x0, 0, z0), turn)
    return far, fine


def cart_wheel(centre, radius, width):
    """A cart's wheel, solid from afar, its two spokes' boards for the near
    view; its axle along z."""
    x, y, z = centre
    far = [rod("wheel", (x, y, z - width / 2), (x, y, z + width / 2), radius, dark, sides=10),
           rod("hub", (x, y, z - width), (x, y, z + width), radius * 0.25, timber, sides=6)]
    out = 1 if z >= 0 else -1
    fine = [lath("spoke", (x - radius * 0.9, y, z + out * width / 2), (x + radius * 0.9, y, z + out * width / 2), 0.004, 0.0015, timber),
            lath("spoke", (x, y - radius * 0.9, z + out * width / 2), (x, y + radius * 0.9, z + out * width / 2), 0.004, 0.0015, timber)]
    return far, fine


def handcart(at_point, turn=0.0):
    """A two-wheeled handcart, its bed and its handles."""
    pieces = [block("cart bed", (-0.04, 0.03, -0.025), (0.04, 0.038, 0.025), timber),
              block("cart side", (-0.04, 0.038, -0.025), (0.04, 0.052, -0.021), grey),
              block("cart side", (-0.04, 0.038, 0.021), (0.04, 0.052, 0.025), grey)]
    fine = []
    for z in (-0.03, 0.03):
        a, b = cart_wheel((0.0, 0.025, z), 0.025, 0.006)
        pieces += a
        fine += b
    for z in (-0.018, 0.018):
        pieces.append(lath("handle", (0.04, 0.034, z), (0.1, 0.012, z), 0.005, 0.005, dark))
    pieces.append(tied_sack("cart sack", (-0.015, 0.038, 0.0), 0.018, canvas))
    for obj in pieces + fine:
        placed(obj, at_point, turn)
    return pieces, fine


def wain(at_point, turn=0.0):
    """A wain loading in the yard: its bed, four wheels, its shafts and a
    load of crates and a barrel."""
    pieces = [block("wain bed", (-0.06, 0.032, -0.03), (0.06, 0.044, 0.03), timber),
              block("wain rail", (-0.06, 0.044, -0.03), (0.06, 0.06, -0.026), grey),
              block("wain rail", (-0.06, 0.044, 0.026), (0.06, 0.06, 0.03), grey)]
    fine = []
    for x in (-0.042, 0.042):
        for z in (-0.034, 0.034):
            a, b = cart_wheel((x, 0.024, z), 0.024, 0.006)
            pieces += a
            fine += b
    for z in (-0.014, 0.014):
        pieces.append(lath("shaft", (0.06, 0.04, z), (0.13, 0.016, z), 0.005, 0.005, dark))
    pieces.append(block("load", (-0.05, 0.044, -0.022), (-0.012, 0.08, 0.02), pale))
    pieces.append(block("load", (-0.008, 0.044, -0.02), (0.03, 0.074, 0.022), pale))
    pieces.append(rings("load barrel", [(0.016, 0.044), (0.02, 0.064), (0.016, 0.084)], 7, pale, centre=(0.045, 0.0)))
    for obj in pieces + fine:
        placed(obj, at_point, turn)
    return pieces, fine


# MARK: What it is built of

def store_shed(at_point, width, depth, height, wall, roof, footing=None, battens=True):
    """A store of planks under a gable, its ridge along x, its door barred."""
    x0, _, z0 = at_point
    body, close = hall("store", width, depth, height, wall, roof, dark, pitch=0.7, footing=footing)
    for obj in body + close:
        placed(obj, at_point)
    far, fine = list(body), list(close)
    door_w, door_h = 0.05, min(0.085, height - 0.01)
    face = z0 + depth / 2
    far.append(block("door", (x0 - door_w / 2, 0.0, face), (x0 + door_w / 2, door_h, face + 0.004), dark))
    far.append(block("door bar", (x0 - door_w / 2 - 0.008, door_h * 0.55 - 0.003, face + 0.004), (x0 + door_w / 2 + 0.008, door_h * 0.55 + 0.003,
                                                                                                    face + 0.009), timber))
    for x in [-door_w / 2 + 0.006 + k * 0.0095 for k in range(5)]:
        fine.append(block("door board", (x0 + x - 0.0012, 0.002, face + 0.004), (x0 + x + 0.0012, door_h - 0.003, face + 0.006), timber))
    for y in (0.018, door_h - 0.02):
        fine.append(block("strap", (x0 - door_w / 2 + 0.002, y - 0.002, face + 0.0045), (x0 + door_w / 2 - 0.002, y + 0.002, face + 0.0065), iron))
    if battens:
        x = -width / 2 + 0.02
        while x < width / 2 - 0.005:
            if abs(x) > door_w / 2 + 0.006:
                fine.append(block("batten", (x0 + x - 0.0018, 0.0, face), (x0 + x + 0.0018, height, face + 0.003), dark))
            x += 0.024
    return far, fine


def lean_to(low_x, high_x, back_z, front_z, high, low, wall_side, roof):
    """A lean-to against a wall: posts at its open front, a roof of one slope
    falling from the wall at `high` to `low` over the front."""
    far = [rod("lean post", (x, 0.0, front_z), (x, low, front_z), 0.005, dark, sides=4) for x in (low_x, high_x)]
    far.append(slab("lean roof", [(low_x - 0.01, high, back_z), (high_x + 0.01, high, back_z), (high_x + 0.01, low - 0.006, front_z + 0.02),
                                  (low_x - 0.01, low - 0.006, front_z + 0.02)], roof, 0.008, normal=(0, 1, (high - low) / (front_z - back_z + 1e-6))))
    far.append(lath("lean plate", (low_x - 0.008, low, front_z), (high_x + 0.008, low, front_z), 0.008, 0.008, dark))
    return far


def warehouse(at_point, width, depth, low, high, bays=2, buttressed=False):
    """A warehouse of two storeys: stone below with its great doors, timber
    above jettied out over the yard front and back, the loading door in it
    over the doors, a slate gable over all, lit windows."""
    x0, _, z0 = at_point
    jetty = 0.014
    far, fine = [], []
    far.append(block("footing", (x0 - width / 2 - 0.01, -0.08, z0 - depth / 2 - 0.01), (x0 + width / 2 + 0.01, 0.02, z0 + depth / 2 + 0.01),
                     dark_stone))
    far.append(block("ground storey", (x0 - width / 2, -0.04, z0 - depth / 2), (x0 + width / 2, low, z0 + depth / 2), pale_stone))
    # The jetty's joists' ends under the upper storey, front and back.
    upper, close = hall("upper storey", width + 0.004, depth + 2 * jetty, high - low, daub, slate, dark, pitch=0.62)
    for obj in upper + close:
        placed(obj, (x0, low, z0))
    far += upper
    fine += close
    far.append(block("jetty floor", (x0 - width / 2 - 0.004, low - 0.008, z0 - depth / 2 - jetty), (x0 + width / 2 + 0.004, low,
                                                                                                      z0 + depth / 2 + jetty), dark))
    for k in range(int(width / 0.03) + 1):
        x = x0 - width / 2 + 0.008 + k * (width - 0.016) / max(int(width / 0.03), 1)
        for side in (-1, 1):
            fine.append(block("joist", (x - 0.003, low - 0.016, z0 + side * (depth / 2) - 0.004 + (0.0 if side > 0 else -jetty + 0.004)),
                              (x + 0.003, low - 0.008, z0 + side * (depth / 2) + 0.004 + (jetty - 0.004 if side > 0 else 0.0)), dark))
    face = z0 + depth / 2
    # The great doors below; the loading door over them, in the jetty's face.
    far.append(block("great doors", (x0 - 0.035, 0.0, face), (x0 + 0.035, low - 0.012, face + 0.004), dark))
    far.append(block("door arch", (x0 - 0.042, low - 0.016, face - 0.002), (x0 + 0.042, low - 0.008, face + 0.006), stone))
    up = face + jetty
    far.append(block("loading door", (x0 - 0.02, low + 0.012, up), (x0 + 0.02, low + 0.06, up + 0.004), dark))
    for x in [-0.03 + k * 0.01 for k in range(7)]:
        fine.append(block("door board", (x0 + x - 0.0012, 0.003, face + 0.004), (x0 + x + 0.0012, low - 0.015, face + 0.006), timber))
    for y in (0.02, low - 0.035):
        fine.append(block("strap", (x0 - 0.033, y - 0.002, face + 0.0045), (x0 + 0.033, y + 0.002, face + 0.0068), iron))
    # Half-timbering on the upper storey's front: posts and a rail.
    for k in range(bays * 2 + 1):
        x = x0 - width / 2 + width * k / (bays * 2)
        if abs(x - x0) > 0.028:
            fine.append(block("stud", (x - 0.003, low, up), (x + 0.003, high, up + 0.003), dark))
    fine.append(block("rail", (x0 - width / 2, low + (high - low) * 0.5 - 0.003, up), (x0 - 0.024, low + (high - low) * 0.5 + 0.003, up + 0.003), dark))
    fine.append(block("rail", (x0 + 0.024, low + (high - low) * 0.5 - 0.003, up), (x0 + width / 2, low + (high - low) * 0.5 + 0.003, up + 0.003), dark))
    # Windows lit in the upper storey, and slits in the stone below.
    for x in (-width * 0.32, width * 0.32):
        far.append(lit("window", (x0 + x, low + (high - low) * 0.55, up + 0.002), 0.022, 0.026, 0.0, window))
        far.append(block("slit", (x0 + x - 0.004, low * 0.35, face), (x0 + x + 0.004, low * 0.7, face + 0.003), dark))
    # The stone's courses for the near view.
    for y in [0.025 + k * 0.025 for k in range(int((low - 0.02) / 0.025))]:
        for side in (-1, 1):
            fine.append(block("course", (x0 - width / 2 - 0.0015, y - 0.0012, z0 + side * depth / 2 - 0.0015 * (1 if side < 0 else 0)),
                              (x0 + width / 2 + 0.0015, y + 0.0012, z0 + side * depth / 2 + 0.0015 * (1 if side > 0 else 0)), stone))
    if buttressed:
        for x in [x0 - width / 2 + width * k / bays for k in range(bays + 1)]:
            for side in (-1, 1):
                if abs(x - x0) < 0.05 and side > 0:
                    continue
                z = z0 + side * (depth / 2 + 0.01)
                far.append(block("buttress", (x - 0.01, -0.03, z - 0.012), (x + 0.01, low * 0.85, z + 0.012), stone))
    return far, fine


def strongroom(at_point, size, height):
    """A squat strongroom of stone under a hip of slate, its door bound in
    iron and barred, slits for its light."""
    x0, _, z0 = at_point
    h = size / 2
    far = [block("strongroom", (x0 - h, -0.04, z0 - h), (x0 + h, height, z0 + h), stone),
           hip_roof("strongroom roof", (x0, z0), size, size, height, size * 0.45, slate, overhang=0.012, thickness=0.006),
           block("strong door", (x0 - 0.018, 0.0, z0 + h), (x0 + 0.018, 0.06, z0 + h + 0.004), dark)]
    fine = [block("door strap", (x0 - 0.017, y - 0.002, z0 + h + 0.004), (x0 + 0.017, y + 0.002, z0 + h + 0.0065), iron) for y in (0.012, 0.03, 0.048)]
    fine.append(block("door bar", (x0 - 0.026, 0.034, z0 + h + 0.006), (x0 + 0.026, 0.04, z0 + h + 0.011), iron))
    for dx in (-h, h):
        fine.append(block("slit", (x0 + dx - 0.002 * (1 if dx < 0 else -1) - 0.0015, height * 0.55, z0 - 0.004),
                          (x0 + dx + 0.0015, height * 0.85, z0 + 0.004), dark))
    for y in [0.025 + k * 0.024 for k in range(int((height - 0.02) / 0.024))]:
        fine.append(block("course", (x0 - h - 0.0015, y - 0.0012, z0 + h - 0.001), (x0 + h + 0.0015, y + 0.0012, z0 + h + 0.0015), dark_stone))
    return far, fine


def turret(at_point, radius, height):
    """A round watch turret under a cone, a lit loop, a ladder's head showing."""
    x0, _, z0 = at_point
    body, close = round_house("turret", radius, height, pale_stone, slate, stone, iron, rise=radius * 1.8, sides=10)
    for obj in body + close:
        placed(obj, (x0, 0, z0))
    far = list(body)
    far.append(lit("turret loop", (x0, height * 0.72, z0 + radius + 0.001), 0.01, 0.022, 0.0, window))
    return far, list(close)


def gin_pole(at_point):
    """The first level's gin pole: a post braced at its foot by the shed's
    door, the hoist's arm turning on it."""
    x, _, z = at_point
    return [rod("gin pole", (x, 0.0, z), (x, 0.16, z), 0.005, dark, sides=5),
            lath("gin brace", (x - 0.03, 0.0, z), (x, 0.06, z), 0.005, 0.005, timber),
            lath("gin brace", (x, 0.0, z - 0.03), (x, 0.06, z), 0.005, 0.005, timber)]


def hoist(level):
    """The hoist at the loading door: its arm out over the yard, a crate on
    the rope."""
    x, y, z = HOISTS[level]
    reach = 0.06 if level == 1 else 0.07
    pieces = [lath("hoist arm", (x, y, z), (x, y, z + reach), 0.007, 0.007, dark),
              rod("hoist rope", (x, y - 0.004, z + reach - 0.004), (x, y - 0.075, z + reach - 0.004), 0.0016, linen, sides=3),
              block("hoist load", (x - 0.016, y - 0.105, z + reach - 0.02), (x + 0.016, y - 0.075, z + reach + 0.012), pale)]
    obj = join(tagged("hoist", level_tags([level])), pieces)
    on(obj, rig, "store hoist@%d" % level)


# MARK: The levels

# 1. The store-shed, a lean-to of barrels at its side, planks and logs.
far, fine = store_shed((-0.04, 0, -0.06), 0.2, 0.13, 0.1, timber, thatch, footing=stone)
far += lean_to(0.07, 0.17, -0.12, -0.0, 0.11, 0.07, 1, thatch)
more, close = barrels((0.12, 0, -0.07), 3)
far += more + gin_pole((0.13, 0, 0.06)) + sacks((0.08, 0, 0.13), 4)
fine += close
far += planks((-0.19, 0, 0.13), 0.12, 4, turn=0.3) + logs((-0.03, 0, 0.17), 0.12, 2, turn=-0.1)
piece("storehouse", [1], far, fine)

# 2. A longer store under slate, the hoist over its loft door, a log rack
#    under its own roof, dressed stone and crates.
far, fine = store_shed((0.0, 0, -0.08), 0.26, 0.15, 0.13, timber, slate, footing=stone)
far.append(block("loft door", (-0.016, 0.135, -0.005), (0.016, 0.17, -0.001), dark))
far += lean_to(-0.25, -0.15, -0.15, -0.03, 0.12, 0.08, -1, slate)
far += logs((-0.2, 0, -0.09), 0.1, 3, turn=math.pi / 2)
more, close = crates((0.17, 0, 0.12), 4)
far += more + dressed((-0.13, 0, 0.16), 6, turn=0.2) + sacks((0.06, 0, 0.14), 3)
fine += close
more, close = barrels((0.21, 0, -0.03), 3, turn=0.5)
far += more
fine += close
piece("storehouse", [2], far, fine)

# 3. The warehouse of two storeys, the old shed kept as a lean-to.
far, fine = warehouse((0.0, 0, -0.08), 0.26, 0.15, 0.11, 0.2)
far += lean_to(0.13, 0.25, -0.14, -0.02, 0.1, 0.065, 1, thatch)
far += logs((0.19, 0, -0.08), 0.1, 3, turn=math.pi / 2)
more, close = crates((-0.17, 0, 0.12), 5)
far += more + dressed((0.12, 0, 0.16), 6, turn=-0.3) + sacks((0.2, 0, 0.09), 4)
fine += close
more, close = handcart((-0.02, 0, 0.17), turn=0.4)
far += more
fine += close
more, close = barrels((-0.21, 0, -0.01), 4, turn=0.2)
far += more
fine += close
piece("storehouse", [3], far, fine)

# 4. The warehouse and a strongroom beside it, moonsalt at its step.
far, fine = warehouse((-0.04, 0, -0.09), 0.24, 0.14, 0.11, 0.2)
more, close = strongroom((0.2, 0, -0.08), 0.1, 0.1)
far += more
fine += close
more, close = moonsalt_chest((0.2, 0, 0.02), turn=0.15)
far += more
fine += close
more, close = crates((-0.18, 0, 0.12), 6)
far += more
fine += close
more, close = barrels((0.06, 0, 0.13), 5, turn=0.4)
far += more
fine += close
far += dressed((0.2, 0, 0.15), 6, turn=0.4) + logs((-0.04, 0, 0.2), 0.12, 2) + planks((-0.24, 0, -0.02), 0.1, 3, turn=math.pi / 2)
piece("storehouse", [4], far, fine)

# 5. The great storehouse: three bays, buttressed, a watch turret at its
#    corner, banners at its doors, the strongroom and a wain loading.
far, fine = warehouse((-0.03, 0, -0.1), 0.3, 0.15, 0.12, 0.22, bays=3, buttressed=True)
more, close = turret((-0.2, 0, -0.18), 0.04, 0.28)
far += more
fine += close
more, close = strongroom((0.21, 0, -0.06), 0.09, 0.1)
far += more
fine += close
for x in (-0.09, 0.03):
    far.append(rod("banner rod", (x, 0.1, -0.014), (x, 0.1, 0.03), 0.003, iron, sides=4))
    flag("banner %s@5" % ("L" if x > -0.03 else "R"), (x, 0.1, 0.028), 0.03, 0.07, banner, turn=-math.pi / 2, tail=True)
more, close = wain((0.1, 0, 0.17), turn=0.25)
far += more
fine += close
more, close = crates((-0.19, 0, 0.12), 6)
far += more
fine += close
more, close = moonsalt_chest((0.22, 0, 0.04), turn=-0.2)
far += more
fine += close
far += sacks((-0.06, 0, 0.13), 5) + dressed((0.25, 0, 0.13), 3, turn=1.2)
piece("storehouse", [5], far, fine)

for level in LEVELS:
    hoist(level)

# Straw and splinters strewn about the yard, at every level.
litter = []
for index in range(14):
    angle = index * 2.39996
    r = 0.12 + 0.16 * ((index * 31) % 13) / 13
    x, z = r * math.cos(angle), r * math.sin(angle)
    litter.append(lath("splinter", (x, 0.013, z), (x + 0.018, 0.013, z + 0.007), 0.003, 0.002, pale if index % 2 == 0 else thatch))
join("litter!fine", litter)

# Its hoist swinging at the loading door as the stores go up.
idle(rig, turns=[("store hoist@%d" % level, (0, 1, 0), lambda u: 0.5 * swing(u)) for level in LEVELS])

finish_building(out_path("Art/models/storehouse.glb"), [str(level) for level in LEVELS])
