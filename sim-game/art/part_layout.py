"""How parts are placed when a machine is assembled. DATA, not art.

In its own module for the same reason `species_tints.py` is: both the Blender
rig and the plain-python tools need these numbers, and importing `rig.py`
outside Blender dies on `import bpy`.

THE OFFSET RULE (rig.py rule 5)
-------------------------------
rig.py rule 2 says a machine is drawn by overlaying whole part sprites at ONE
frame position. That is right for parts that differ, and it cannot express a
COUNT. Measured in art/assemble.py: a drill's solid footprint at 1x went
1258 -> 1376 -> 1389 px for zero, one and two hoppers. The first hopper added
118 px of new shape and the second added 13, which is antialiased edges
hardening, not a part. The second hopper was invisible.

That matters because capacity is a real number in sim - `MAX_HOPPER_SLOTS`
frames' worth of `HOPPER_CAPACITY` - and the minimal demo's points 5 and 9
both turn on a player seeing that a drill has two. rig.py's own grade-glint
rule says a visible mark must correspond to a real difference; this is the
same rule pointing the other way, and the difference was real while the
picture stayed silent.

So: THE NTH REPEAT OF A PART KIND IS DRAWN AT n * PART_REPEAT_OFFSET, where n
counts from 0 in `Assembly::parts()` order - frame first, then the mounted
parts, which sim documents as "the one canonical order" and every rule that
has to pick a part already walks. Taking the order from sim rather than from
the renderer is what stops two peers drawing the same machine differently.

WHY (14, -6) AND NOT A ROUNDER NUMBER
  Swept, not chosen. Two bounds decided it:
  - Maren's test: the second hopper must add roughly the first's 118 px, not
    13. At (14, -6) it adds 109, which is 92%. Larger steps overshoot - at
    (22, -18) the second adds 267 px, which is not a part sitting on a
    machine, it is a part hanging off one.
  - It has to survive a FULL machine. `MAX_HOPPER_SLOTS` is 4, so the rule is
    judged at four, not at the two the demo happens to use. At (8, -8), which
    scored better on the first bound, the fourth hopper loses 122 px off the
    top of the frame rectangle. At (14, -6) nothing clips and the footprint
    grows 118 / 109 / 160 / 193 - every hopper adds at least 92% of the first.
  Up and to the east, because the frame body runs west and the head works
  east: repeats step back along the machine, the way a row of real hoppers
  would sit.

The frame rectangle is the hard limit. If a part kind ever gets more slots
than fit, the answer is a cap plus a number in the UI (Maren's option 2), not
a smaller offset that makes them invisible again.
"""

# Authoring pixels (TILE_PX 64). The game shows 32 at 1x, so this is a 7 x 3
# step on screen.
PART_REPEAT_OFFSET = (14, -6)
