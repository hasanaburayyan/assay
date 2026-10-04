"""Player character: idle and walk cycles in 8 directions.

Rows are named <anim>_<dir>, dir in S, SE, E, NE, N, NW, W, SW (S faces the
camera; the order is a +45 degree turn about z each step). Rendered as a chunky engineer in an orange suit: readable at 32px,
and the colour pairs with the machines.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import rig
from rig import mat

out = rig.args()
DIRS = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
WALK_FRAMES, IDLE_FRAMES = 8, 2

# IDLE WAS 4 FRAMES AT 4FPS AND IT TWITCHED (Maren, ASSA-115 ruling 2).
# 4 frames, 3 distinct, because `sin` at phases 0, pi/2, pi, 3pi/2 gives
# 0, +1, 0, -1 and the two zeroes are the same pose -- so it was really a
# 3-pose cycle with a stutter in it, playing whenever you are not walking,
# which is most of the time you are looking at your own character.
#
# MEASURED AT 32PX, worst consecutive step, before this change: 25-29% of the
# sprite moving on S/SE/SW/N/NE/NW and 16-19% on E/W. (The brief's "53%" is a
# differ-at-ALL count, which scores a one-unit change in one channel as
# motion; these columns threshold at 8.)
#
# NOW 2 POSES AT 2FPS, which is Maren's prescription: "2 distinct poses at
# 2fps with a small delta" rather than "3 at 4fps with a big one".
#
# THE TWO POSES ARE NEUTRAL AND FULL INHALE, not the two extremes, and I tried
# it the other way first. `2*pi*f/n` at two frames draws `sin` 0 and 0 -- the
# same pose twice, an idle that does not move at all -- so the obvious repair
# is to offset a quarter turn and take sin +1 and -1. That renders a mirrored
# LEAN rather than a breath, doubles the travel between consecutive frames,
# and pushed `check_headroom` UP on idle_E and idle_N (4.9 -> 6.0, 4.6 -> 5.4)
# because both frames now hold the arms where the visor and the tank catch
# the key. Stepping pi/2 instead gives sin 0 and +1: one breath in, one out,
# half the travel, and both poses already existed in the old four-frame
# cycle.
#
# THE AMPLITUDE IS HALVED TOO, and this is the half I am least sure of: at
# 32px the figure is about 18px tall, so the old 0.015 bob is about half a
# screen pixel, and ANY sub-pixel shift re-renders every edge. Below about a
# pixel the pixel-change count stops tracking what a player sees and starts
# tracking the resampler, so the honest lever here is the RATE, not the size.
IDLE_STEP = math.pi / 2          # neutral -> full inhale, and back
IDLE_BOB = 0.0075                # was 0.015
IDLE_SWING = 0.03                # was 0.06, the shoulder

r = rig.Rig(samples=48)
r.shadow_catcher()
suit, dark, skin, visor, steel = mat("suit"), mat("gun"), mat("skin"), rig.lamp("visor"), rig.steel()

root = r.empty()
body = r.empty((0, 0, 0.78), root)
with r.group(body):
    r.box((0.46, 0.30, 0.56), (0, 0, 0), suit, bev=0.08)               # torso
    r.box((0.50, 0.10, 0.16), (0, 0, -0.18), dark, bev=0.03)            # belt
    r.box((0.34, 0.16, 0.42), (0, 0.20, 0.02), dark, bev=0.04)          # backpack
    r.cyl(0.05, 0.3, (0.12, 0.28, 0.1), steel, bev=0.01, verts=12)     # tank
    r.box((0.36, 0.36, 0.36), (0, 0, 0.46), skin, bev=0.10)             # head
    r.box((0.42, 0.42, 0.18), (0, 0, 0.60), suit, bev=0.07)             # helmet
    r.box((0.30, 0.05, 0.12), (0, -0.20, 0.47), visor, bev=0.01)        # visor
limbs = {}
for side, x in (("l", -0.32), ("r", 0.32)):
    sh = r.empty((x, 0, 0.22), body)
    with r.group(sh):
        r.box((0.17, 0.17, 0.46), (0, 0, -0.24), suit, bev=0.05)
        r.box((0.19, 0.19, 0.12), (0, 0, -0.50), dark, bev=0.03)        # glove
    hip = r.empty((x * 0.42, 0, -0.30), body)
    with r.group(hip):
        r.box((0.20, 0.20, 0.50), (0, 0, -0.25), dark, bev=0.05)
        r.box((0.22, 0.30, 0.12), (0, -0.04, -0.52), suit, bev=0.03)    # boot
    limbs[side] = (sh, hip)

asset = rig.Asset("player", out, (1, 1), headroom=1.0)
asset.anim("idle", IDLE_FRAMES, 2); asset.anim("walk", WALK_FRAMES, 12)
r.frame(1, 1, headroom=1.0)
SWING = math.radians(38)


def pose(walk_phase=None, idle_phase=None):
    if walk_phase is not None:
        sw = math.sin(walk_phase) * SWING
        limbs["l"][1].rotation_euler = (sw, 0, 0); limbs["r"][1].rotation_euler = (-sw, 0, 0)
        limbs["l"][0].rotation_euler = (-sw * 0.8, 0, 0); limbs["r"][0].rotation_euler = (sw * 0.8, 0, 0)
        # Put the hips back where the rig built them. The idle branch below
        # counter-translates them to keep the boots planted, and the rig is
        # ONE scene posed in place for every frame -- so without this, every
        # walk frame would inherit whatever offset the last idle frame left,
        # and the walk of all eight facings would quietly sit 0.0075 high.
        for s in ("l", "r"):
            limbs[s][1].location.z = -0.30
        body.location.z = 0.78 + 0.035 * abs(math.sin(walk_phase))
    else:
        for s in ("l", "r"):
            limbs[s][1].rotation_euler = (0, 0, 0); limbs[s][0].rotation_euler = (0, 0, 0)
        # THE BOB LIFTS THE TORSO AND LEAVES THE BOOTS ON THE GROUND.
        #
        # `hip` is a CHILD of `body`, so the old `body.location.z` bob raised
        # and lowered the legs and boots with everything else -- a breathing
        # idle whose feet came off the floor. Nobody had looked at what the
        # bob was parented to, including me when I wrote it.
        #
        # It is also the whole reason the per-step pixel count would not come
        # down. I halved the amplitude first and the worst step moved 29% ->
        # 28%, because at 32px this figure is ~18px tall and ANY sub-pixel
        # shift re-renders every edge it touches. The lever is not how FAR the
        # sprite moves, it is HOW MUCH OF IT moves. Pinning the legs takes a
        # third of the silhouette out of the motion and is the correct
        # drawing at the same time.
        bob = IDLE_BOB * math.sin(idle_phase)
        body.location.z = 0.78 + bob
        for s in ("l", "r"):
            limbs[s][0].rotation_euler = (0, (1 if s == "l" else -1)
                                          * IDLE_SWING * math.sin(idle_phase), 0)
            limbs[s][1].location.z = -0.30 - bob   # cancel the bob: feet stay planted


for d, name in enumerate(DIRS):
    root.rotation_euler = (0, 0, math.radians(d * 45))
    for f in range(IDLE_FRAMES):
        pose(idle_phase=IDLE_STEP * f)
        r.render(asset.path(f"idle_{name}", f))
    asset.add(f"idle_{name}", IDLE_FRAMES)
    for f in range(WALK_FRAMES):
        pose(walk_phase=2 * math.pi * f / WALK_FRAMES)
        r.render(asset.path(f"walk_{name}", f))
    asset.add(f"walk_{name}", WALK_FRAMES)
asset.write()
