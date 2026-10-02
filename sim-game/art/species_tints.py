"""Species tints: one per species index. DATA, not art.

Lives in its own module because both the Blender rig and the plain-python
tools need it, and importing rig.py outside Blender fails on `import bpy`.
That is not hypothetical: the contact sheet's colour-blind check was first
written to import rig, which would have thrown every time and silently
skipped the check - the second time in this one pipeline that a guard quietly
stopped guarding.

ONE TINT PER SPECIES INDEX. A world rolls SPECIES_PER_WORLD (6) species from
its seed and the ore sprite is species-neutral, so a renderer multiplies one
of these over it (Godot `modulate`). Regenerate with art/species_probe.py.

DERIVED, NOT PICKED. The probe sweeps a grid of candidate tints, throws out
everything that sinks into the ground tile FOR ANY of normal / protan /
deutan / tritan vision, then takes the six furthest apart for whichever
observer sees them most alike. Three earlier schemes were measured first:

  - six hues evenly spaced round the wheel: protan sees the closest pair at
    dE 5.7 against a floor of 12. Even spacing optimises for normal vision
    and walks species along the confusion axis.
  - Okabe & Ito's qualitative palette: much better on species (protan 17.7)
    but its green sits on our olive terrain at dE 5.8 for a protan viewer. It
    separates categories from each other on white; "stay off one particular
    olive" is a constraint it was never designed for.
  - lifting that palette toward white: made the terrain collision worse. It
    is a hue problem and lifting only moves luminance.

AND THE SCORE IS HUE/CHROMA, NOT dE76. Scoring the full dE76 produced a muted
table reading 16.3 for the worst observer whose hue separation was 3.7 - six
species that were one family at six brightnesses. The contact sheet showed it
plainly as "a few blues at different brightness" while the number said pass.
Lightness is already spent on TIER, so species may not have it.

THIS TABLE: closest pair by hue/chroma is dE 18.3 (protan), 18.5 (deutan),
20.4 (tritan), 24.8 (normal), floor 12; worst vs terrain dE 10.0, floor 10.

TWO THINGS THAT FALL OUT OF THE METHOD RATHER THAN TASTE, and that art
direction has to live with:
  - NO GREEN, because the terrain is olive.
  - THESE ARE BRIGHT, AND THEY HAVE TO BE. The same derivation with
    saturation capped at 0.50 FAILS (protan hue 10.1, deutan 8.8). A muted,
    earthy species palette is not available while the tint is a multiply over
    a light base. Ore will be the most saturated thing on screen.

DECISION #36 IS RESOLVED: option A. Colour is a slot from the species index,
AND the client draws the species INITIAL on the deposit as a redundant
non-colour read. The glyph is not optional decoration - this table clears the
protan floor by a margin measured in single digits, so colour alone would be
a marginal read for the ~8% of men with a red-green deficiency. The initial
already exists in sim (`debug::species_symbol`, the generated name's first
letter) and `worldgen::generate_name` enforces one distinct initial per
species per world, so the glyph costs no new art and no new sim.

Maren also retired the old "30 degrees apart on the hue wheel" bar with this
decision: Okabe-Ito's sky blue and blue are the SAME hue to 0.1 degrees and
survive CVD precisely because they differ in lightness and saturation
instead. Hue separation in HSV is not perceptual separation. The bar is dE76
under protan/deutan/tritan at true 32px, floor 12.

AND THE LADDER IS CHECKED AGAINST THIS TABLE. `species_probe.py` measures the
closest pair at EVERY grade, because the ore ladder is partly lightness and a
multiply scales species differences by its own factor - so the darkest tile,
grade C, is the worst case. It currently reads 15.8 (protan) at C, 18.0 at B,
19.1 at A. If a future ladder goes darker at the bottom, that check fails
before the art ships.
"""

SPECIES_TINTS = ["#7A29CC", "#FF3333", "#FF80BF", "#FFFF33", "#3333FF", "#509BE6"]
