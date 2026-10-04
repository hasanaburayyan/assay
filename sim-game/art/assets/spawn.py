"""Spawn marker: a 3x3 landing pad with a 4-frame beacon blink."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
FRAMES = 4

r = rig.Rig(samples=64)
r.shadow_catcher()
gun, orange, steel = mat("gun"), mat("orange"), rig.steel()

# octagonal plate with a raised rim and inset panel lines
r.cyl(1.42, 0.10, (0, 0, 0.05), gun, bev=0.03, verts=8, rot=(0, 0, math.pi / 8))
r.cyl(1.25, 0.04, (0, 0, 0.12), mat("grey"), bev=0.01, verts=8, rot=(0, 0, math.pi / 8))
for i in range(4):  # hazard chevrons pointing inward on the four sides
    a = i * math.pi / 2
    r.box((0.55, 0.08, 0.02), (1.05 * math.cos(a), 1.05 * math.sin(a), 0.15), orange, bev=0, rot=(0, 0, a + math.pi / 2))
    r.box((0.35, 0.08, 0.02), (0.85 * math.cos(a), 0.85 * math.sin(a), 0.15), orange, bev=0, rot=(0, 0, a + math.pi / 2))
r.cyl(0.45, 0.02, (0, 0, 0.15), orange, bev=0, verts=48)          # centre ring
r.cyl(0.36, 0.02, (0, 0, 0.16), mat("grey"), bev=0, verts=48)
lamps = []
for i in range(4):  # corner beacons
    a = i * math.pi / 2 + math.pi / 4
    x, y = 1.15 * math.cos(a), 1.15 * math.sin(a)
    r.cyl(0.12, 0.22, (x, y, 0.21), steel, bev=0.02, verts=16)
    lamps.append(r.cyl(0.08, 0.06, (x, y, 0.34), rig.lamp("cyan"), bev=0, verts=16))
# THE UNLIT BEACON, AND THIS FILE COULD NOT RENDER AT ALL UNTIL IT WAS FIXED.
# It asked for `iron_dk`, a palette entry deleted in bc6d880 when the art went
# species-neutral -- so `mat()` fell through to its hex path, tried to parse
# "iron_dk" as a colour and died. `spawn.png` has been shipping out of a stale
# `art/out/` ever since, which is the exact hazard CLAUDE.md warns about: a
# `--pack` repacks whatever your machine last rendered. Nothing in CI asked
# whether the sheets could still be MADE (ASSA-115, found by re-rendering).
#
# No new palette name, and never a mineral one again (ADR 0001): a dead lens
# is its own colour gone dark, so it is mixed from the lamp it stops being.
off = mat(rig.mix_hex("cyan", "gun", 0.78))


def lens(t):
    """A lamp `t` of the way from dead to lit. t=0 IS `off` and t=1 IS
    `rig.lamp("cyan")`, by construction -- the endpoints are the two poses
    already on main, so this only adds steps BETWEEN them and does not
    re-style a surface that was approved.

    The base slides along the same mix the dead lens is made from; the EMISSION
    stays cyan at every level, because a dimmer beacon is a weaker light of the
    same colour, not a different-coloured one (`mat`'s own `emit_color` note).
    """
    return mat(rig.mix_hex("cyan", "gun", 0.78 * (1 - t)), emit=6 * t, emit_color="cyan")


# THE BLINK WAS A SQUARE WAVE AND THAT IS WHY IT STROBED (ASSA-115 box 7, Maren:
# "a strobe on a 3x3 landmark"). Keyed `(i + f) % 2`, every lamp flipped the FULL
# range every frame, so frames 0/2 and 1/3 were byte-identical and the sheet was
# 2 distinct poses alternating at 4 fps -- four hard transitions a second. The
# area is small (1.3% of the displayed 96x104 moves by more than 24) which is why
# a pixel count made it look like a sixth of the idle's problem; what reads as a
# flicker is the SHAPE of the transition, not how much of the frame it covers.
# Measured at the displayed size, the worst consecutive step was 154 of 255.
#
# So: same two poses, CROSS-FADED. One diagonal pair runs the ramp below while the
# other runs it shifted by two, which makes frames 0 and 2 exactly the two frames
# that shipped and frames 1 and 3 a new middle where all four lamps sit halfway.
# A triangle instead of a square wave: the same beacon, half the step, and the
# light travels across the pad instead of snapping.
#
# THE MIDDLE IS 0.10, NOT 0.5, AND THAT IS NOT A TYPO. `t` is not linear in
# anything a player sees -- emission is a light that clips, so most of the lamp's
# visible range is spent in the first tenth of `t`. Rendered mean luminance over
# the 223 lamp pixels, measured rather than assumed:
#
#     t     0.00   0.12   0.22   0.32   0.42   0.50   1.00
#     lum   87.2  157.8  172.2  181.4  187.7  192.3  208.5
#
# The midpoint of the two shipped poses is 147.8, which lands at t ~= 0.10. My
# first pass used 0.5 because it reads as "half", and it bought almost nothing:
# the step 1.0 -> 0.5 is 16 luminance and 0.5 -> 0.0 is 105, so the flip was
# still there, just moved. If this ramp ever gains a step, CALIBRATE IT THE SAME
# WAY -- render a few values of t and read the lamp, do not interpolate t.
RAMP = (1.0, 0.10, 0.0, 0.10)

asset = rig.Asset("spawn", out, (3, 3), headroom=0.25)
asset.anim("blink", FRAMES, 4)
r.frame(3, 3, headroom=0.25)
for f in range(FRAMES):
    for i, l in enumerate(lamps):
        t = RAMP[f] if i % 2 == 0 else RAMP[(f + 2) % FRAMES]
        l.data.materials[0] = lens(t)
    r.render(asset.path("pad", f))
asset.add("pad", FRAMES)
asset.write()
