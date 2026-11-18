"""The Archery Range, where the city's bowmen learn their craft, its five
levels the tiers of one file, each within a work's slot and facing +z, the
butts at the back and the shooting line toward the keep:
1. two straw butts on their frames, a shooting line of pegs, a rack of
   bows and a bench, arrows in the butts;
2. a third butt, a target hung from a gallows that swings when struck, the
   fletcher's lean-to with sheaves of arrows on its bench;
3. a bank of earth behind the butts to catch what flies wide, a stand
   roofed on posts at the shooting line, a straw man to shoot at;
4. the bowyer's workshop of timber, its staves drying on a rack, quivers
   hung on the stand, a fourth butt;
5. a long stand of stone with its gallery under slate, the House's
   banners on it, the judge's seat raised at its end, a fifth butt.
Close: the rings painted on the butts, the arrows standing in them, the
bows' strings, the bench's legs, the stand's rafters and the fletcher's
feathers. The hung target swings at every level but the first, and there
the bows' rack's pennant flies.

    python Art/blender/archery.py Art/models/archery.glb
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
loam = material("plain_earth_loam", (0.15, 0.13, 0.11))
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
madder = material("plain_madder", (0.55, 0.16, 0.12))
linen = material("plain_linen", (0.7, 0.67, 0.6))
leather = material("plain_leather_dark", (0.22, 0.16, 0.12))
moss = material("plain_moss", (0.3, 0.36, 0.2))
iron = material("metal_iron", (0.36, 0.37, 0.4), roughness=0.5, metallic=0.6)
banner = material("cloth_banner", (0.78, 0.78, 0.78))
window = material("glow_candle", (1.0, 0.8, 0.52))

# Where the hung target's gallows holds it, at each level from the second.
GALLOWS = {2: (0.17, 0.12, -0.17), 3: (0.19, 0.12, -0.12), 4: (0.17, 0.12, -0.08), 5: (0.2, 0.12, -0.05)}
rig = work_rig([("hung target@%d" % level, pivot, (1, 0, 0)) for level, pivot in GALLOWS.items()])
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


# MARK: What the range is made of

def butt(at_point, size=0.036):
    """A butt: a round boss of bound straw leant back on its frame, facing
    the shooting line, its rings painted, arrows standing in it."""
    x0, _, z0 = at_point
    lean = 0.18
    centre = (x0, size + 0.02, z0)
    far = [rod("butt leg", (x0 + dx, 0.0, z0 - 0.02), (x0 + dx, size + 0.03, z0 - 0.004), 0.003, dark, sides=4) for dx in (-0.025, 0.025)]
    boss = rings("boss", [(0.0, -0.01), (size, -0.008), (size, 0.008), (0.0, 0.01)], 10, straw)
    far.append(posed(boss, centre, (1, 0, 0), math.pi / 2 - lean))
    fine = []
    for radius, mat, lift in ((size * 0.72, madder, 0.0105), (size * 0.5, linen, 0.0115), (size * 0.24, madder, 0.0125)):
        disc = rings("butt ring", [(0.0, lift - 0.0005), (radius, lift - 0.0005), (radius, lift), (0.0, lift)], 10, mat)
        fine.append(posed(disc, centre, (1, 0, 0), math.pi / 2 - lean))
    for dx, dy in ((0.008, 0.006), (-0.012, -0.004), (0.003, -0.012)):
        fine.append(rod("arrow", (x0 + dx, centre[1] + dy, z0 + 0.008), (x0 + dx * 1.2, centre[1] + dy + 0.008, z0 + 0.05), 0.0011, pale,
                        sides=3, caps=(False, False)))
    return far, fine


def shooting_line(z, x0, x1, count):
    """Pegs along the shooting line, a cord from peg to peg."""
    far, fine = [], []
    for index in range(count):
        x = x0 + (x1 - x0) * index / (count - 1)
        far.append(rod("peg", (x, 0.0, z), (x, 0.022, z), 0.0025, timber, sides=4))
    fine.append(rod("cord", (x0, 0.02, z), (x1, 0.02, z), 0.0008, linen, sides=3, caps=(False, False)))
    return far, fine


def bow_rack(at_point, count, turn=0.0):
    """A rack of bows standing in their notches, a bench before it."""
    far = [lath("rack rail", (-0.05, 0.075, 0.0), (0.05, 0.075, 0.0), 0.006, 0.006, dark),
           lath("rack foot", (-0.05, 0.006, 0.0), (0.05, 0.006, 0.0), 0.008, 0.012, dark)]
    for dx in (-0.05, 0.05):
        far.append(rod("rack post", (dx, 0.0, 0.0), (dx, 0.08, 0.0), 0.003, dark, sides=4))
    fine = []
    for index in range(count):
        x = -0.04 + index * 0.08 / max(count - 1, 1)
        top, low = (x + 0.004, 0.105, 0.002), (x - 0.002, 0.004, 0.004)
        far.append(rod("bow", low, top, 0.0022, pale, sides=4))
        fine.append(rod("bowstring", (low[0] + 0.006, low[1] + 0.006, low[2]), (top[0] + 0.006, top[1] - 0.006, top[2]), 0.0006, linen,
                        sides=3, caps=(False, False)))
    far.append(block("bench", (-0.045, 0.024, 0.026), (0.045, 0.03, 0.04), timber))
    for dx in (-0.038, 0.038):
        fine.append(block("bench leg", (dx - 0.003, 0.0, 0.028), (dx + 0.003, 0.024, 0.038), dark))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def hung_target(level):
    """A target hung from its gallows by two cords, its own part to swing
    when struck; the gallows itself."""
    x, y, z = GALLOWS[level]
    frame = [rod("gallows post", (x - 0.04, 0.0, z), (x - 0.04, y + 0.006, z), 0.003, dark, sides=4),
             rod("gallows post", (x + 0.04, 0.0, z), (x + 0.04, y + 0.006, z), 0.003, dark, sides=4),
             lath("gallows beam", (x - 0.046, y + 0.004, z), (x + 0.046, y + 0.004, z), 0.006, 0.006, timber)]
    disc = rings("hung disc", [(0.0, -0.004), (0.024, -0.004), (0.024, 0.004), (0.0, 0.004)], 10, straw)
    mark = rings("hung mark", [(0.0, 0.0045), (0.012, 0.0045), (0.012, 0.005), (0.0, 0.005)], 10, madder)
    moving = [posed(disc, (x, y - 0.045, z), (1, 0, 0), math.pi / 2), posed(mark, (x, y - 0.045, z), (1, 0, 0), math.pi / 2),
              rod("hung cord", (x - 0.014, y, z), (x - 0.014, y - 0.03, z), 0.0008, linen, sides=3, caps=(False, False)),
              rod("hung cord", (x + 0.014, y, z), (x + 0.014, y - 0.03, z), 0.0008, linen, sides=3, caps=(False, False))]
    obj = join(tagged("hung target", level_tags([level])), moving)
    on(obj, rig, "hung target@%d" % level)
    return frame


def fletcher(at_point, turn=0.0):
    """The fletcher's lean-to: a sloping roof on posts over a bench, sheaves
    of arrows on it, a basket of goose feathers."""
    w, d = 0.11, 0.06
    far = [block("lean back", (-w / 2, 0.0, -d / 2), (w / 2, 0.085, -d / 2 + 0.006), grey)]
    for x in (-w / 2, w / 2):
        far.append(rod("lean post", (x, 0.0, d / 2), (x, 0.06, d / 2), 0.003, dark, sides=4))
    far.append(slab("lean roof", [(-w / 2 - 0.01, 0.09, -d / 2), (w / 2 + 0.01, 0.09, -d / 2), (w / 2 + 0.01, 0.056, d / 2 + 0.012),
                                  (-w / 2 - 0.01, 0.056, d / 2 + 0.012)], thatch, 0.006, normal=(0, 1, 0.55)))
    far.append(block("fletcher bench", (-0.04, 0.028, -0.01), (0.04, 0.034, 0.016), timber))
    fine = []
    for dx in (-0.02, 0.012):
        far.append(rings("sheaf", [(0.006, 0.034), (0.006, 0.07)], 5, pale, centre=(dx, 0.0)))
        fine.append(rings("fletchings", [(0.008, 0.066), (0.0085, 0.072), (0.006, 0.076)], 5, linen, centre=(dx, 0.0), caps=(False, True)))
    far.append(rings("feather basket", [(0.008, 0.0), (0.011, 0.018), (0.0105, 0.02)], 7, straw, centre=(0.035, 0.03), caps=(True, False)))
    fine.append(rings("feathers", [(0.0, 0.016), (0.009, 0.019), (0.0, 0.026)], 7, linen, centre=(0.035, 0.03)))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def bank(radius, start, end, count):
    """A bank of earth along an arc behind the butts, mounds run together
    and turfed over, to catch what flies wide."""
    far, fine = [], []
    for index in range(count):
        a = math.radians(start + (end - start) * index / (count - 1))
        x, z = radius * math.cos(a), -radius * math.sin(a)
        mound = rings("bank", [(0.046, -0.04), (0.046, 0.0), (0.032, 0.036), (0.0, 0.048)], 7, loam, squash=0.6)
        far.append(placed(mound, (x, 0, z), -a + math.pi / 2))
        turf = rings("turf", [(0.033, 0.0355), (0.0, 0.0485)], 7, moss, squash=0.6)
        fine.append(placed(turf, (x, 0, z), -a + math.pi / 2))
    return far, fine


def straw_man(at_point):
    """A straw man on his post to shoot at, a sack for his head."""
    x0, _, z0 = at_point
    far = [rod("straw post", (x0, 0.0, z0), (x0, 0.1, z0), 0.003, dark, sides=4),
           rings("straw body", [(0.012, 0.04), (0.016, 0.06), (0.013, 0.085), (0.0, 0.088)], 6, straw, centre=(x0, z0)),
           rings("straw head", [(0.0, 0.086), (0.01, 0.094), (0.008, 0.104), (0.0, 0.108)], 6, linen, centre=(x0, z0)),
           lath("straw arms", (x0 - 0.026, 0.074, z0), (x0 + 0.026, 0.074, z0), 0.006, 0.006, straw)]
    fine = [rod("arrow", (x0 + 0.004, 0.07, z0 + 0.008), (x0 + 0.006, 0.075, z0 + 0.045), 0.0011, pale, sides=3, caps=(False, False))]
    return far, fine


def stand(at_point, width, depth, height, roof, stone_built=False, gallery=False):
    """The stand at the shooting line: a roof on posts, or a stand of stone
    with a gallery over it, its rafters for the near view."""
    x0, _, z0 = at_point
    far, fine = [], []
    if stone_built:
        far.append(block("stand wall", (x0 - width / 2, -0.04, z0 - depth / 2), (x0 + width / 2, height * 0.45, z0 - depth / 2 + 0.02), stone))
        for k in range(4):
            x = x0 - width / 2 + width * (k + 0.5) / 4
            far.append(block("stand pier", (x - 0.01, 0.0, z0 + depth / 2 - 0.02), (x + 0.01, height, z0 + depth / 2), pale_stone))
    posts = [x0 - width / 2 + width * k / 3 for k in range(4)]
    if not stone_built:
        for x in posts:
            for z in (z0 - depth / 2, z0 + depth / 2):
                far.append(rod("stand post", (x, 0.0, z), (x, height, z), 0.0035, dark, sides=4))
    if gallery:
        far.append(block("gallery", (x0 - width / 2, height * 0.55, z0 - depth / 2), (x0 + width / 2, height * 0.6, z0 + depth / 2), timber))
        far.append(lath("gallery rail", (x0 - width / 2, height * 0.75, z0 + depth / 2), (x0 + width / 2, height * 0.75, z0 + depth / 2), 0.004,
                        0.004, dark))
        for k in range(1, 3):
            x = x0 - width / 2 + width * k / 3
            far.append(lit("gallery window", (x, height * 0.3, z0 - depth / 2 + 0.021), 0.014, 0.022, 0.0, window))
    far.append(gable_roof("stand roof", (x0, z0), depth, width, height, depth * 0.45, roof, overhang=0.012, along="x", thickness=0.005))
    for k in range(int(width / 0.03) + 1):
        x = x0 - width / 2 + k * width / int(width / 0.03)
        fine.append(lath("stand rafter", (x, height - 0.004, z0 - depth / 2 - 0.006), (x, height + depth * 0.45, z0), 0.003, 0.003, dark))
    return far, fine


def workshop(at_point, turn=0.0):
    """The bowyer's workshop: a timber hall under thatch, its door and a lit
    window, staves drying on a rack beside it."""
    body, close = hall("workshop", 0.13, 0.09, 0.075, timber, thatch, dark, pitch=0.75, footing=stone)
    far, fine = list(body), list(close)
    far.append(block("workshop door", (-0.014, 0.0, 0.045), (0.014, 0.06, 0.049), dark))
    far.append(lit("workshop window", (0.04, 0.045, 0.046), 0.018, 0.016, 0.0, window))
    for k in range(5):
        x = 0.08 + k * 0.008
        far.append(rod("stave", (x, 0.0, -0.03 + k * 0.004), (x - 0.006, 0.1, -0.035 + k * 0.004), 0.0018, pale, sides=4))
    far.append(lath("stave rail", (0.074, 0.08, -0.03), (0.12, 0.08, -0.02), 0.004, 0.004, dark))
    for obj in far + fine:
        placed(obj, at_point, turn)
    return far, fine


def quivers(at_point, count):
    """Quivers hung on a rail, arrows showing."""
    x0, _, z0 = at_point
    far = [lath("quiver rail", (x0 - 0.03, 0.06, z0), (x0 + 0.03, 0.06, z0), 0.004, 0.004, dark)]
    fine = []
    for k in range(count):
        x = x0 - 0.02 + k * 0.04 / max(count - 1, 1)
        far.append(rod("quiver", (x, 0.02, z0 + 0.004), (x, 0.058, z0 + 0.004), 0.005, leather, sides=5))
        fine.append(rings("quiver arrows", [(0.004, 0.058), (0.0045, 0.068)], 4, pale, centre=(x, z0 + 0.004)))
    return far, fine


def judge_seat(at_point):
    """The judge's seat raised on its steps at the stand's end, under a
    little canopy."""
    x0, _, z0 = at_point
    far = [block("seat dais", (x0 - 0.025, 0.0, z0 - 0.025), (x0 + 0.025, 0.035, z0 + 0.025), pale_stone),
           block("seat", (x0 - 0.012, 0.035, z0 - 0.012), (x0 + 0.012, 0.05, z0 + 0.008), timber),
           block("seat back", (x0 - 0.012, 0.05, z0 - 0.014), (x0 + 0.012, 0.08, z0 - 0.01), timber)]
    for dx in (-0.02, 0.02):
        far.append(rod("canopy post", (x0 + dx, 0.035, z0 - 0.02), (x0 + dx, 0.1, z0 - 0.02), 0.002, dark, sides=4))
    far.append(slab("canopy", [(x0 - 0.026, 0.1, z0 - 0.026), (x0 + 0.026, 0.1, z0 - 0.026), (x0 + 0.026, 0.094, z0 + 0.01),
                               (x0 - 0.026, 0.094, z0 + 0.01)], banner, 0.003, normal=(0, 1, 0.15)))
    fine = [block("step", (x0 - 0.018, 0.0, z0 + 0.025), (x0 + 0.018, 0.017, z0 + 0.037), stone)]
    return far, fine


# MARK: The levels

# 1. Two butts at the back, the shooting line, a rack of bows and a bench.
far, fine = gather(butt((-0.08, 0, -0.16)), butt((0.08, 0, -0.16)), shooting_line(0.14, -0.15, 0.15, 6),
                   bow_rack((-0.2, 0, 0.06), 3, turn=1.0))
far.append(rod("rack pennant staff", (-0.2, 0.0, -0.02), (-0.2, 0.15, -0.02), 0.0025, dark, sides=4))
flag("rack pennant@1", (-0.2, 0.148, -0.02), 0.035, 0.022, banner, turn=0.3, tail=True)
piece("range", [1], far, fine)

# 2. A third butt, the hung target, the fletcher's lean-to.
far, fine = gather(butt((-0.13, 0, -0.15)), butt((-0.02, 0, -0.17)), butt((0.09, 0, -0.15)), shooting_line(0.14, -0.17, 0.17, 7),
                   bow_rack((-0.21, 0, 0.06), 4, turn=1.0), fletcher((0.2, 0, 0.07), turn=-1.2))
far += hung_target(2)
piece("range", [2], far, fine)

# 3. A bank behind the butts, a roofed stand, a straw man.
far, fine = gather(bank(0.27, 40, 140, 9), butt((-0.13, 0, -0.15)), butt((-0.02, 0, -0.16)), butt((0.08, 0, -0.15)),
                   stand((0.0, 0, 0.17), 0.2, 0.06, 0.08, thatch), straw_man((-0.2, 0, -0.06)), fletcher((0.21, 0, 0.06), turn=-1.2),
                   bow_rack((-0.22, 0, 0.1), 3, turn=1.2))
far += hung_target(3)
piece("range", [3], far, fine)

# 4. The bowyer's workshop, quivers on the stand, a fourth butt.
far, fine = gather(bank(0.27, 40, 140, 9), butt((-0.15, 0, -0.15)), butt((-0.06, 0, -0.17)), butt((0.03, 0, -0.17)), butt((0.12, 0, -0.15)),
                   stand((-0.04, 0, 0.17), 0.18, 0.06, 0.08, slate), workshop((0.175, 0, 0.1), turn=-1.3), straw_man((-0.21, 0, -0.04)),
                   quivers((-0.04, 0, 0.13), 3))
far += hung_target(4)
piece("range", [4], far, fine)

# 5. The long stand of stone with its gallery, banners, the judge's seat,
#    a fifth butt.
far, fine = gather(bank(0.27, 40, 140, 9), butt((-0.17, 0, -0.14)), butt((-0.085, 0, -0.17)), butt((0.0, 0, -0.18)), butt((0.085, 0, -0.17)),
                   butt((0.17, 0, -0.14)), stand((-0.03, 0, 0.17), 0.22, 0.07, 0.11, slate, stone_built=True, gallery=True),
                   judge_seat((0.15, 0, 0.17)), quivers((-0.06, 0, 0.12), 3), straw_man((-0.22, 0, -0.03)),
                   bow_rack((0.22, 0, 0.0), 4, turn=-1.4))
for side, x in (("L", -0.1), ("R", 0.04)):
    far.append(rod("banner rod", (x, 0.09, 0.205), (x, 0.09, 0.225), 0.002, iron, sides=4))
    flag("stand banner %s@5" % side, (x, 0.09, 0.223), 0.022, 0.05, banner, turn=-math.pi / 2, tail=True)
far += hung_target(5)
piece("range", [5], far, fine)

# Spent arrows in the grass and straw blown from the butts, at every level.
litter = []
for index in range(12):
    angle = index * 2.39996
    r = 0.12 + 0.16 * ((index * 31) % 13) / 13
    x, z = r * math.cos(angle), r * math.sin(angle)
    litter.append(lath("spent arrow" if index % 2 == 0 else "straw", (x, 0.013, z), (x + 0.02, 0.013, z + 0.006), 0.002, 0.002,
                       pale if index % 2 == 0 else straw))
join("litter!fine", litter)

# The hung target swinging as it is struck, at every level that has it.
idle(rig, turns=[("hung target@%d" % level, (1, 0, 0), lambda u: 0.35 * swing(u)) for level in GALLOWS])

finish_building(out_path("Art/models/archery.glb"), [str(level) for level in LEVELS])
