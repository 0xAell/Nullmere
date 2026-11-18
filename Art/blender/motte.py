"""A young city's keep, before it is raised in stone: a tower of timber on
an earthen motte, the motte ringed with a palisade and its gate at the head
of a stair of logs, the House's pennant over the tower; at the motte's foot
the keeper's hall of timber, its roof in the House's colour, its chimney
smoking (where Holds.youngChimney says), lit windows and its door between
lanterns, logs and a cart by it. The game draws it for a city of the realm
whose Keep stands below the fifth level; from the fifth it is the hold's
keep of stone, and from the twelfth the seat's.

Close: the tower's planks and braces, the gallery's rail and shingles, the
palisade's lashings, the stair's treads, the hall's frame and shutters, the
motte's turf and the stones about its foot.

    python Art/blender/motte.py Art/models/motte.glb
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from building import *
from common import *
from works import hall, log, placed, rock

reset()

earth = material("plain_earth", (0.24, 0.21, 0.18))
moss = material("plain_moss", (0.3, 0.36, 0.2))
dark_stone = material("plain_stone_dark", (0.37, 0.37, 0.38))
stone = material("plain_stone", (0.52, 0.51, 0.49))
timber = material("plain_timber", (0.29, 0.21, 0.15))
beam = material("plain_timber_dark", (0.19, 0.14, 0.11))
pale = material("plain_timber_pale", (0.45, 0.37, 0.28))
grey = material("plain_timber_grey", (0.42, 0.39, 0.35))
bark = material("plain_timber_bark", (0.21, 0.17, 0.14))
thatch = material("plain_thatch", (0.47, 0.41, 0.29))
daub = material("plain_daub", (0.61, 0.56, 0.47))
house = material("house_roof", (0.78, 0.78, 0.78))
banner = material("cloth_banner", (0.78, 0.78, 0.78))
candle = material("glow_candle", (1.0, 0.8, 0.52))
iron = material("metal_iron", (0.36, 0.37, 0.4), roughness=0.5, metallic=0.6)

# The motte: its foot, its top, how high, and where on it the tower stands.
MOTTE = (0.3, 0.17, 0.12)
MIDDLE = -0.07
TOWER_HALF, TOWER = 0.07, 0.36
# The hall at the motte's foot, before it.
HALL = (0.0, 0.0, 0.24)
HALL_W, HALL_D, HALL_H = 0.2, 0.1, 0.075
# The top of the hall's chimney, where its smoke rises (Holds.youngChimney).
FLUE = (0.06, 0.17, 0.235)

far, close = [], []

# MARK: The motte, its palisade and stair

bottom, top, height = MOTTE
far.append(rings("motte", [(bottom + 0.02, -0.3), (bottom, 0.0), ((bottom + top) / 2 + 0.01, height * 0.6), (top, height), (top * 0.94, height + 0.008),
                           (0.0, height + 0.008)], 14, earth, centre=(0.0, MIDDLE), twist=0.1))
close.append(rings("turf", [((bottom + top) / 2 + 0.012, height * 0.58), (top + 0.002, height + 0.001), (top * 0.94, height + 0.0095),
                            (0.0, height + 0.0095)], 14, moss, centre=(0.0, MIDDLE), twist=0.1, caps=(False, False)))
# The palisade about its top, its gate toward the hall.
stakes = 26
for k in range(stakes):
    a = 2 * math.pi * k / stakes
    if abs(math.sin(a) - 1.0) < 0.06 and math.cos(a) * top < 0.03:
        continue
    x, z = top * 0.9 * math.cos(a), MIDDLE + top * 0.9 * math.sin(a)
    tall = 0.055 + 0.008 * ((k * 5) % 3)
    far.append(rings("stake", [(0.008, height - 0.01), (0.008, height + tall), (0.0, height + tall + 0.015)], 5, bark, centre=(x, z), twist=k))
for y in (height + 0.02, height + 0.045):
    close.append(rings("lashing", [(top * 0.9 + 0.0085, y - 0.0015), (top * 0.9 + 0.0085, y + 0.0015)], 26, iron, centre=(0.0, MIDDLE),
                       caps=(False, False)))
gate_z = MIDDLE + top * 0.9
for dx in (-0.024, 0.024):
    far.append(rod("gate post", (dx, height - 0.01, gate_z), (dx, height + 0.085, gate_z), 0.006, beam, sides=5))
far.append(lath("gate lintel", (-0.03, height + 0.082, gate_z), (0.03, height + 0.082, gate_z), 0.01, 0.01, beam))
far.append(block("gate", (-0.019, height, gate_z - 0.004), (0.019, height + 0.06, gate_z + 0.002), timber))
# The stair of logs down the motte's face to the hall.
steps = 7
for k in range(steps):
    t = (k + 0.5) / steps
    z = gate_z + 0.02 + (HALL[2] - HALL_D / 2 - 0.02 - gate_z - 0.02) * t
    y = height * (1 - t) + 0.004
    far.append(log("stair log", (-0.022, y, z), (0.022, y, z), 0.006, sides=5))
for dx in (-0.026, 0.026):
    close.append(lath("stair rail", (dx, height + 0.03, gate_z + 0.02), (dx, 0.03, HALL[2] - HALL_D / 2 - 0.004), 0.004, 0.004, beam))
# Stones about its foot.
for k in range(7):
    a = 0.6 + k * 0.75
    x, z = (bottom + 0.012) * math.cos(a), MIDDLE + (bottom + 0.012) * math.sin(a)
    if z > 0.12:
        continue
    close.append(rock("foot stone", (x, 0.01, z), (0.014, 0.01, 0.012), k, stone, bands=2, sides=5))

# MARK: The tower

t, base = TOWER_HALF, height
far.append(block("tower", (-t, base, MIDDLE - t), (t, base + TOWER * 0.78, MIDDLE + t), timber))
# Its corner posts, a little proud, and braces across its faces.
for x in (-t, t):
    for z in (MIDDLE - t, MIDDLE + t):
        far.append(rod("corner post", (x, base, z), (x, base + TOWER * 0.82, z), 0.006, beam, sides=4))
for side, (ax, az, bx, bz) in enumerate(((-t, MIDDLE + t, t, MIDDLE + t), (-t, MIDDLE - t, t, MIDDLE - t))):
    off = 0.0015 if side == 0 else -0.0015
    close.append(lath("brace", (ax, base + 0.02, az + off), (bx, base + TOWER * 0.4, bz + off), 0.006, 0.004, beam))
    close.append(lath("brace", (bx, base + TOWER * 0.4, bz + off), (ax, base + TOWER * 0.72, az + off), 0.006, 0.004, beam))
# The planks' joints for the near view.
for k in range(1, 7):
    y = base + TOWER * 0.78 * k / 7
    close.append(block("plank", (-t - 0.0012, y - 0.0008, MIDDLE - t - 0.0012), (t + 0.0012, y + 0.0008, MIDDLE + t + 0.0012), grey))
# The gallery jutting out at its top, railed, under a roof of shingles.
g = t + 0.025
gallery = base + TOWER * 0.78
far.append(block("gallery floor", (-g, gallery - 0.006, MIDDLE - g), (g, gallery + 0.002, MIDDLE + g), beam))
for x in (-g, g):
    for z in (MIDDLE - g, MIDDLE + g):
        far.append(rod("gallery post", (x, gallery, z), (x, gallery + 0.06, z), 0.0035, beam, sides=4))
for k in range(4):
    a = (-g, MIDDLE - g), (g, MIDDLE - g), (g, MIDDLE + g), (-g, MIDDLE + g)
    (ax, az), (bx, bz) = a[k], a[(k + 1) % 4]
    far.append(lath("gallery rail", (ax, gallery + 0.026, az), (bx, gallery + 0.026, bz), 0.005, 0.005, timber))
    close.append(lath("gallery board", (ax, gallery + 0.012, az), (bx, gallery + 0.012, bz), 0.004, 0.012, grey))
far.append(hip_roof("tower roof", (0.0, MIDDLE), 2 * g, 2 * g, gallery + 0.06, 0.09, thatch, overhang=0.014, thickness=0.006))
for x, z in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
    close.append(lath("roof rib", (x * (g + 0.012), gallery + 0.06, MIDDLE + z * (g + 0.012)), (0.0, gallery + 0.15, MIDDLE), 0.006, 0.006, beam))
# Lit windows high on the tower, a door at its foot facing the gate.
for facing, (cx, cz) in ((0.0, (0.0, MIDDLE + t)), (math.pi / 2, (t, MIDDLE)), (-math.pi / 2, (-t, MIDDLE)), (math.pi, (0.0, MIDDLE - t))):
    far.append(lit("tower window", faced((cx, base + TOWER * 0.6, cz), facing, 0, 0, 0.002), 0.018, 0.03, facing, candle))
far.append(block("tower door", (-0.016, base, MIDDLE + t), (0.016, base + 0.06, MIDDLE + t + 0.004), beam))
# The House's pennant over it.
pole_top = gallery + 0.2
far.append(rod("pennant pole", (0.0, gallery + 0.14, MIDDLE), (0.0, pole_top, MIDDLE), 0.003, beam, sides=4))
flag("pennant", (0.0, pole_top - 0.004, MIDDLE), 0.07, 0.035, banner, turn=0.3, tail=True)

# MARK: The hall at its foot

hx, _, hz = HALL
body, fine = hall("hall", HALL_W, HALL_D, HALL_H, daub, house, beam, pitch=0.85, footing=dark_stone)
for obj in body + fine:
    placed(obj, HALL)
far += body
close += fine
front = hz + HALL_D / 2
far.append(block("hall door", (hx - 0.014, 0.0, front), (hx + 0.014, 0.06, front + 0.004), beam))
for x in (-0.065, 0.065):
    far.append(lit("hall window", (hx + x, 0.045, front + 0.002), 0.02, 0.022, 0.0, candle))
    close.append(block("shutter", (hx + x - 0.022, 0.034, front + 0.001), (hx + x - 0.012, 0.057, front + 0.004), grey))
    far.append(lit("lantern", (hx + x * 0.45, 0.07, front + 0.012), 0.008, 0.012, 0.0, candle, depth=0.008))
# The hall's framing showing through its daub.
for k in range(5):
    x = hx - HALL_W / 2 + HALL_W * k / 4
    if abs(x - hx) > 0.02:
        close.append(block("stud", (x - 0.003, 0.0, front + 0.0005), (x + 0.003, HALL_H, front + 0.003), beam))
close.append(block("rail", (hx - HALL_W / 2, HALL_H * 0.5 - 0.003, front + 0.0005), (hx - 0.02, HALL_H * 0.5 + 0.003, front + 0.003), beam))
close.append(block("rail", (hx + 0.02, HALL_H * 0.5 - 0.003, front + 0.0005), (hx + HALL_W / 2, HALL_H * 0.5 + 0.003, front + 0.003), beam))
# Its chimney of stone at the gable's end.
cx, cy, cz = FLUE
far.append(block("chimney", (cx - 0.015, 0.0, cz - 0.015), (cx + 0.015, cy, cz + 0.015), stone))
far.append(block("chimney cap", (cx - 0.019, cy - 0.006, cz - 0.019), (cx + 0.019, cy, cz + 0.019), dark_stone))

# MARK: About the yard

for x, z in ((-0.17, 0.2), (-0.2, 0.15)):
    far.append(log("log", (x, 0.008, z - 0.04), (x, 0.008, z + 0.04), 0.008, sides=5))
far.append(log("log", (-0.185, 0.022, 0.135), (-0.185, 0.022, 0.215), 0.008, sides=5))
# A handcart by the hall's flank.
cart = [block("cart bed", (-0.03, 0.03, -0.022), (0.03, 0.038, 0.022), pale),
        rod("cart wheel", (0.0, 0.024, -0.026), (0.0, 0.024, -0.02), 0.024, beam, sides=10),
        rod("cart wheel", (0.0, 0.024, 0.02), (0.0, 0.024, 0.026), 0.024, beam, sides=10),
        lath("cart handle", (0.03, 0.034, -0.014), (0.08, 0.01, -0.014), 0.004, 0.004, beam),
        lath("cart handle", (0.03, 0.034, 0.014), (0.08, 0.01, 0.014), 0.004, 0.004, beam)]
for obj in cart:
    placed(obj, (0.2, 0, 0.16), -0.9)
far += cart

join("young keep", far)
join("young keep close!fine", close)

finish_building(out_path("Art/models/motte.glb"), ["1"])
