"""Part: the FRAME -- the PLANTED kind (note D6).

The other kind of frame. A head on this is a drill: it stands on the ground
and works on its own, where the held frame is swung by a player. Hoppers bolt
to it, which is why its deck is flat and clear.

HOW IT IS TOLD FROM THE HANDLE, and it is not hue. This is a CHUNKY CHASSIS
on four feet; `handle.py` is a thin shaft. At 32 px that is a solid block
against a one-pixel line -- it survives greyscale and colour-blind
simulation on shape alone. Orange is the second channel, and it is also what
says "machine" in this palette: the drill chassis and the player suit are the
same orange, and nothing a player carries by hand is.

Lies along X, mounts at the origin, body runs WEST. Rules in `rig.py`.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat, LYING, PART_AXIS as AXIS

out = rig.args()


def build(g):
    """One geometry, grade as a parameter (`rig.GRADES`). Shape never varies.

    Orange is this part's warm accent, so it is the one that glints at A --
    on a machine the chassis IS the mark, where the head wears brass."""
    r = rig.Rig(samples=64, fill=rig.MACHINE_FILL)
    r.shadow_catcher()
    gun = mat("gun")
    # THE CHASSIS IS THE MARK, BUT THE WHOLE CHASSIS IS NOT THE GLINT, and
    # that distinction is what ASSA-124 turned out to be about.
    #
    # This deck used to be `graded_accent("orange")`. `graded_accent` is "the
    # ONE WARM MARK a part wears" (rig.py) and at grade A it EMITS neutral
    # white -- Decision #37, a neutral blowout, so that a clipped saturated
    # emitter cannot land on a species hue. The head puts it on a 0.12 box and
    # the handle on a small brass piece. This file put it on the deck, which
    # is the part's biggest mass, so at grade A half the sprite became a white
    # emitter. Measured at 1x, neutral pixels (chroma < 8) per row:
    #
    #     hopper (no glint, by rule)  4.8%  5.5%  5.5%   <- the control
    #     head                        7.3% 6.2% 12.5%
    #     handle                     13.2% 14.7% 27.9%
    #     frame                       8.7%  6.9% 48.6%   <- here
    #
    # Every glinted part loses chroma at A and the loss tracks GLINT AREA, so
    # "grade A is the quietest frame in the game" was never a palette fault.
    # It was this file spending the mark on the chassis.
    #
    # THE RULE THIS RAMP NOW FOLLOWS: the chassis carries grade as COLOUR and
    # the glint carries it as LIGHT, and the two live on different surfaces.
    # The body keeps the standard ladder (dulled -> as drawn, `graded`), so
    # its chroma RISES C < B < A; the glint is a small boss that only grade A
    # lights. Nothing here may out-shout the quietest shipped ore, which is
    # why the chassis is mixed 0.37 toward `gun` before the ladder runs:
    # full `orange` puts grade B at 38.8 against a floor of 35.7, and a
    # quarter was not enough either (B 36.5, A 37.9 -- measured, not guessed).
    chassis = rig.graded(rig.mix_hex("orange", "gun", 0.37), g)
    orange_dk = rig.graded("orange_dk", g)
    steel = rig.graded("steel", g, rough=0.45, metal=0.6)

    # THE YOKE at the join: a collar-sized cradle the head's mount drops into.
    # Sized to read just proud of the head's 0.30 collar when assembled, so
    # the join looks like a join and not like the head floating on a box.
    r.cyl(0.33, 0.16, (-0.17, 0, AXIS), orange_dk, bev=0.03, rot=LYING)
    for sy in (-1, 1):
        r.box((0.12, 0.1, 0.5), (-0.17, sy * 0.3, AXIS - 0.06), chassis, bev=0.03)

    # THE DECK: a flat chassis running west. Flat on top ON PURPOSE -- a
    # hopper bolts down here, and a domed or cluttered deck would make every
    # hopper look like it had landed on the machine rather than been fitted.
    r.box((0.86, 0.72, 0.26), (-0.60, 0, 0.30), chassis, bev=0.06)
    r.box((0.66, 0.52, 0.05), (-0.60, 0, 0.44), gun, bev=0.02)

    # THE GLINT, and it is a boss on the deck plate rather than the deck. Set
    # into the gun panel above, where it has something dark to read against at
    # 1x -- a bright mark on a bright deck is the clip all over again.
    r.box((0.30, 0.13, 0.04), (-0.60, 0, 0.47), rig.graded_accent("orange", g), bev=0.015)

    # FOUR FEET. The whole of "planted" is carried by these: a thing with feet
    # is standing, a thing without is being held. They also lift the deck
    # clear of the ground so the shadow reads as a gap. Maren has accepted
    # that they all but vanish at 1x -- bulk and behaviour carry it there, and
    # the feet are for the 3x sheet.
    for sx in (-1, 1):
        for sy in (-1, 1):
            r.cyl(0.085, 0.3, (-0.60 + sx * 0.3, sy * 0.26, 0.15), gun, bev=0.02, verts=20)
            r.cyl(0.11, 0.05, (-0.60 + sx * 0.3, sy * 0.26, 0.02), steel, bev=0.01, verts=16)

    # A strut from deck to yoke, so the two masses read as one machine.
    r.pipe((-0.34, 0.2, 0.44), (-0.22, 0.12, AXIS + 0.1), 0.05, steel, flanges=False)
    r.pipe((-0.34, -0.2, 0.44), (-0.22, -0.12, AXIS + 0.1), 0.05, steel, flanges=False)
    return r


asset = rig.part_asset("frame", out)
for g, gname in enumerate(rig.GRADES):
    r = build(g)
    r.part_window()
    r.render(asset.path(gname)); asset.add(gname, 1)
asset.write()
