"""Part: the HOPPER. Optional on a planted frame; what the ore falls into.

Third of the three part kinds (note D6: head, frame, hopper). Optional means
the drill has to read as a drill without it, so this piece may add nothing
load-bearing to the silhouette -- it is allowed to be the thing you notice
second.

ITS JOB AT 32 PX IS TO BE A CONTAINER, and a container is an OPEN shape. Every
other part in the set is solid: a taper, a shaft, a block on feet. So the
hopper is the only piece with a hole in it, which is a silhouette difference
rather than a colour one and is the whole reason it can sit on the frame's
deck without reading as more chassis.

Sits WEST of the join, on the deck `frame.py` keeps flat for it. It does not
straddle the origin -- a hopper mounts to the frame, not to the head -- but
it is authored in the same frame and at the same scale, so it composes by
being overlaid like everything else.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()

CX, DECK = -0.60, 0.47     # centred on the frame's deck, standing on its plate


def build(g):
    """One geometry, grade as a parameter (`rig.GRADES`). Shape never varies."""
    r = rig.Rig(samples=64, fill=rig.MACHINE_FILL)
    # NO SHADOW CATCHER, A BOUNCE PLANE INSTEAD: a hopper is MOUNTED and never
    # touches the ground
    # (ASSA-64). It carried the most shadow of the four parts, 2621 pixels per
    # grade frame against the planted frame's 1718. See the same note in
    # `head.py`; the rule is in `art/part_layout.py` and
    # `art/check_part_contract.py` fails if a mounted part ships one again.
    r.bounce()
    gun = mat("gun")
    # GREY, AND THE SAME GREY AT EVERY GRADE. Two changes, one reason, and
    # neither is taste; both are gated by the part-seam and open-box checks in
    # art/assemble.py, which fail on the sheet this replaces.
    #
    # WHY DARKER. Since Decision #37 the grade-A glint blows out NEUTRAL, so a
    # grade-A chassis is a WHITE deck. This part sits on that deck, and in
    # steel it sat 13.3 dE from it at 1x against 36.9 at C and 55.1 at B -- an
    # A drill was one pale mass and you could not count its hoppers, which is
    # the whole job of rule 5. Grey puts that pairing at 36.1, level with the
    # C pairing we already accept. The mark was not the lever (ASSA-28):
    # narrowing the glint drops frame's own B->A step to 8.6, under DISTINCT,
    # and a part whose grade changes a number in sim would then advertise it
    # about as loudly as this one, whose grade changes nothing.
    #
    # WHY FLAT. `graded` mixes toward `gun` by 0.45 at C, and on top of a base
    # this dark that is a second darkening. I rendered the control to find out
    # rather than asserting it, having guessed the numbers wrong first: grey
    # WITH the dulling still on puts 34.7% of the C hopper under L*35 against
    # 15.9% without, and drops its gap from the head to 7.7 dE, under DISTINCT.
    # Flat is what buys the darker base. It is also what sim says: a hopper
    # contributes Mass from Density and a FLAT Capacity (sim/src/assembly.rs,
    # PART_SPECS), and "density never scales with grade" (part_mass). A grade-A
    # hopper and a grade-C hopper are the same object to the rules, so they are
    # the same object here. rig.py already said this part gets no warm mark for
    # that reason; a tone step is the same promise made more quietly, and it
    # was false in the same way.
    body = mat("grey", rough=0.45, metal=0.6)
    brass = rig.graded_accent("brass", g)

    # THE MOUTH: a wide, shallow, OPEN funnel. Built as four leaning walls
    # rather than a cone so the opening stays a hard-edged quadrilateral at
    # size -- a round mouth downsamples into a blob, and a blob is just
    # another solid.
    for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        r.box((0.055 if sx else 0.62, 0.62 if sx else 0.055, 0.42),
              (CX + sx * 0.28, sy * 0.28, DECK + 0.21), body,
              bev=0.02, rot=(sy * 0.32, -sx * 0.32, 0))
    # The dark interior. This is the piece doing the work at 1x: a shadowed
    # well inside a light rim is what says "open" when the walls are two
    # pixels thick.
    r.box((0.44, 0.44, 0.06), (CX, 0, DECK + 0.07), mat("rubber"), bev=0.01)

    # THE THROAT below the mouth, down to the deck: narrow, dark and square so
    # the piece reads as mouth-over-neck rather than as one tapered lump.
    r.box((0.34, 0.34, 0.2), (CX, 0, DECK - 0.07), gun, bev=0.03)
    # A brass band at the throat. THIS BAND IS DELIBERATELY NOT VISIBLE, and
    # that is the point of it -- do not helpfully expose it.
    #
    # The comment here used to claim it was "the same mark the head wears at
    # its collar". It is not. Maren decoded all three hopper frames: every body
    # pixel is hue 210-225, zero warm pixels in any of them. At this camera the
    # throat is occluded by the mouth above it, so graded_accent runs and the
    # result never reaches the sheet. I wrote the intent and then cited it as
    # if it were the render.
    #
    # Left in anyway, because the accident is the right answer. rig.py's rule
    # is that a part wears a visible warm mark IFF its grade changes a number
    # in sim, and a hopper's grade is inert: capacity is flat, mass is size x
    # density, density never scales with grade. A glint here would promise a
    # difference the sim does not have -- the same shape of defect as the
    # handle's, one asset over, and the opposite verdict, for a reason that is
    # about sim and not about pixels.
    #
    # This used to end "so the hopper is tone-only on purpose". It is now
    # NOTHING-only: the tone step went too (see the body above), so `g` reaches
    # no surface the camera can see and the three frames render alike. The row
    # per grade stays, because the client indexes parts by grade and an asset
    # that is missing rows is a special case for every reader of the sheet.
    r.box((0.38, 0.38, 0.05), (CX, 0, DECK - 0.16), brass, bev=0.01)
    return r


asset = rig.part_asset("hopper", out)
for g, gname in enumerate(rig.GRADES):
    r = build(g)
    r.part_window()
    r.render(asset.path(gname)); asset.add(gname, 1)
asset.write()
