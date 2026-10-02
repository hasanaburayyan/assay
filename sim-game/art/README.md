# art

Every sprite in the game is rendered from a Blender script in this folder.
No image is edited by hand. To change the look, edit the script and rebuild.

## Run

```bash
art/build.py             # render everything, pack, write the contact sheet
art/build.py ore drill   # only these assets
art/build.py --pack      # skip Blender, repack art/out
```

Needs Blender 5.1+ at `/Applications/Blender.app` (or `BLENDER=/path`), and
`uv` (the script pulls in Pillow itself). A full build takes a few minutes
on the CPU.

## Layout

- `rig.py`: everything shared. Palette, materials, camera (orthographic,
  30° tilt, pixel-aspect corrected so tiles are square), sun and sky, the
  Freestyle outline pass, primitive helpers, and the `Asset` manifest
  writer.
- `assets/<name>.py`: one script per asset. Describes shapes and frames
  only. Runs inside Blender, writes `out/<name>/*.png` + `asset.json`.
- `build.py`: runs the asset scripts, downscales 4× to authoring size
  (64 px per tile), packs one sheet per asset into `../assets/sprites/`,
  writes `manifest.json` and `contact.png`.
- `species_tints.py`: the six per-species tints, as data. Kept out of
  `rig.py` because the plain-python tools cannot import `rig` (it needs
  `bpy`). Read that file before changing a colour; the table is derived, not
  chosen, and the comment says what it is derived against.

## Species are a tint, not a sprite

A world rolls six mineral species from its seed and no rule, recipe or
sprite may name one, so **the ore and item art is species-neutral and the
client tints it** with `modulate` (a per-channel multiply). Two consequences
that are easy to undo by accident:

- **Ore tiles are rock-only, with alpha. Never bake the ground into
  anything that gets tinted** — a multiply hits the whole texture, so baked
  terrain gets tinted along with the ore. The client draws the ground tile
  and composites ore over it.
- **The neutral base has to be LIGHT and genuinely hueless.** Multiply
  cannot brighten, so the base's lightness is the budget every species
  spends, and any hue it carries is added to all six.

- **The purity ladder is the sim's: C / B / A**, read out of
  `sim/src/tuning.rs` at build time rather than retyped. The art used to
  split purity into quartiles that crossed no real boundary, putting a
  visible step at purity 50 where nothing happens. A visible mark must
  correspond to a real difference.
- **Grade is carried mostly by COVERAGE, not by value.** Darkening the rock
  to show low purity also shrinks the gap between two species, because the
  tint is a multiply. Count and size are free.

All of these are checked by `art/species_probe.py`, which also measures
species separation through protan / deutan / tritan simulation — the old art was
colour-blind-safe by *shape*, and tinting spends that redundancy. Run it
after touching ore art, the palette or the tints:

```bash
uv run --with pillow python art/species_probe.py   # exits non-zero on a regression
PROBE_SPAN=0.1   art/species_probe.py   # crowds the hues     -> must FAIL
PROBE_SPARSE=0.5 art/species_probe.py   # thins ore coverage  -> must FAIL
MAP_FLOOR=0.33   art/species_probe.py   # over-dims the disc  -> must FAIL
MAP_OPAQUE=1     art/species_probe.py   # the old solid-disc model -> must PASS
```

The second and third lines are not decoration. Two guards in this pipeline
have silently stopped guarding (a colour-blind check grepping for a row name
that no longer existed; a chroma threshold set looser than the defect it
existed to catch), so every check here has a lever that makes its verdict go
red on purpose, and the lever reproduces the CAUSE rather than lowering the
bar — `PROBE_SPARSE` thins coverage, which is how grade C's pop fell to 3.9
in the first place.

- **Ore owns saturation** (rig.py rule 6). Ore is the only fully saturated
  thing in the game; ground, buildings, parts, items and UI chrome all stay
  under the *quietest* shipped species, not under the average of them. This
  is forced rather than chosen: species identity is tint alone, and a muted
  species table is measurably impossible under a multiply, so ore's loudness
  is mandatory and the budget has to fall on everything else.

```bash
art/loudness.py                       # GREEN
LOUDNESS_MUTE=0      art/loudness.py  # greys everything but ore -> must PASS
LOUDNESS_FAKE_ORE=3  art/loudness.py  # everything IS ore        -> must FAIL
LOUDNESS_NO_EXEMPT=1 art/loudness.py  # drops the exemptions     -> must FAIL
```

It measures three things and reports a fourth, and the third exists because
the second lied: a surface's *mean* can clear every ore colour while the
pixels it actually wears sit on top of one. `frame/A` used to score 35.7
whole-surface and 10.9 at the mark. Read B and C together, never B alone.

Both of its original reds are cleared, each the honest way round
(Decision #37). `frame/A` was a **bug in the glint**: `graded_accent` emitted
the part's own accent colour, and an emissive saturated colour slides into
another hue as its channels clip — `#F08A24` landed on `rgb(255,254,89)`,
which is species3's yellow. The A glint now emits neutral, so the blowout
clips to white and no species tint is neutral. `player/*` was ruled **out of
scope**: the budget covers what a player *scans* — ground, machines, ground
items, UI chrome — and an avatar is one humanoid sprite you never search a
field for. That exemption attaches to the **surface**, never to a palette
entry, so a machine can never claim it by wearing the player's orange.
`EXEMPT` entries carry a reason and the name of whoever ruled them, and
`LOUDNESS_NO_EXEMPT=1` proves they are what holds those rows.

Measure **D** reports the same confusion with L\* dropped, through four
observers, and is deliberately **not** a gate: between two species lightness
must not count (grade already spends it), but between a machine and a deposit
it may, because nothing else is spending it.

- **The map disc is a second surface with its own floor.** The client draws a
  deposit twice: a textured tile over olive terrain in the world, and a flat
  ~9 px disc over near-black on the schematic map, dimmed continuously by
  purity rather than in three grades. A tile that passes says nothing about a
  disc, so `species_probe.py` now certifies both (check 2b).

  The disc is scored on **hue and chroma only** — on the map, brightness
  *already* means purity, so letting L\* count would let a pure brightness
  ramp pass as six species. Every constant describing the disc is **read out
  of `client/scripts/hud.gd`**, never retyped here, and the check exits loudly
  if it cannot find one.

  | purity | 1 | **6** | 10 | 20 | 40 | 70 | 100 |
  |---|---|---|---|---|---|---|---|
  | worst pair, 4 observers | 11.6 | **10.8** | 10.9 | 12.0 | 13.5 | 15.5 | 18.5 |

  **This check is RED, and it is red because it used to lie** (ASSA-29). It
  retyped three of the client's constants and got all three wrong, each in
  the direction that measures a brighter disc than the one drawn: the floor
  is 0.525 and not 0.55; the disc is alpha 0.85 over near-black and not
  opaque; and the worst case is **not** at the dimmest disc, because the
  closest pair moves with brightness. Swept properly, the shipped constant
  bottoms out at **10.8 at purity 6** — two species a deutan player cannot
  separate on the surface they use to choose where to walk.

  Clearing it is a client constant, not an art one: `0.65 + 0.35 * purity`
  holds 12.9, at the cost of narrowing the map's brightness range from 1.90:1
  to 1.54:1. Red levers: `MAP_FLOOR=0.33` must fail; `MAP_OPAQUE=1` must
  **pass**, which is what proves the alpha composite is carrying the finding
  rather than the arithmetic.

  The map uses `species_tints.py` **directly**, as fills. I argued the
  opposite and was wrong: I claimed the tints were multipliers that would
  sink on a dark background, and never measured it. Nothing sinks (the
  dimmest disc clears the background by 28.3 as drawn, 34.7 if you model it
  opaque the way this check used to), and a table derived from the
  tinted ore tile is *worse* — the tile's mean carries the rock's dark
  outline and shading, so it starts with less chroma and drops to 10.0 under
  the same dimming. The map is deliberately more chromatic than the world
  because it needs that chroma to survive being dimmed.

## Conventions

- 1 Blender unit = 1 tile. +y is north (up on screen). A sprite's footprint
  is centred on the origin.
- Sheets: one row per sprite (direction, variant or state), one column per
  frame. `manifest.json` gives frame size, footprint in tiles, the anchor
  (where the footprint's top-left corner sits in the frame) and animation
  fps.
- Player directions: `S, SE, E, NE, N, NW, W, SW` (S faces the camera).
- Objects in the `Model` collection get outlines; `Env` (ground, shadow
  catcher, pebbles) does not.
- Review at 1× game size (the small copies on the contact sheet). If it
  doesn't read there, it doesn't matter how it looks zoomed in.

## Adding an asset

1. Copy the closest script in `assets/`. Build shapes with `r.box`,
   `r.cyl`, `r.cone`, `r.rock`, `r.pipe`; use palette names from
   `rig.PALETTE` (add colours there, not inline).
2. Call `r.frame(tiles_w, tiles_h, headroom)` with headroom for anything
   tall (roughly 0.6 × height in units).
3. Render rows with `asset.path(row, frame)` and register them with
   `asset.add`; `asset.anim` records fps.
4. Add the name to `ORDER` in `build.py`, build, check `contact.png`.
