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
art/loudness.py                      # RED today, on purpose: see below
LOUDNESS_MUTE=0     art/loudness.py  # greys everything but ore -> must PASS
LOUDNESS_FAKE_ORE=3 art/loudness.py  # everything IS ore        -> must FAIL
```

It measures three things, and the third exists because the second lied: a
surface's *mean* can clear every ore colour while the pixels it actually
wears sit on top of one. `frame/A` scores 35.7 whole-surface and 10.9 at the
mark. Read B and C together, never B alone.

`loudness.py` exits non-zero on the art as it ships — `player/*` and
`frame/A` are louder than the quietest species, and `frame/A`'s grade glint
wears species3's yellow. That is reported to the Director, not exempted:
`EXEMPT` in that file is empty and an entry needs a reason and a name.

- **The map disc is a second surface with its own floor.** The client draws a
  deposit twice: a textured tile over olive terrain in the world, and a flat
  ~9 px disc over near-black on the schematic map, dimmed continuously by
  purity rather than in three grades. A tile that passes says nothing about a
  disc, so `species_probe.py` now certifies both (check 2b).

  The disc is scored on **hue and chroma only** — on the map, brightness
  *already* means purity, so letting L\* count would let a pure brightness
  ramp pass as six species. Measured at the dimmest disc the client can draw,
  because every brighter purity is slack:

  | purity multiply | 1.00 | 0.80 | 0.70 | 0.60 | **0.55** | 0.50 | 0.33 |
  |---|---|---|---|---|---|---|---|
  | worst pair, 4 observers | 18.5 | 17.5 | 16.0 | 14.0 | **12.5** | 11.5 | 8.0 |

  **0.55 is a measured floor, not a taste** — 0.50 falls under 12. Red lever
  `MAP_FLOOR=0.33` makes the check fail.

  The map uses `species_tints.py` **directly**, as fills. I argued the
  opposite and was wrong: I claimed the tints were multipliers that would
  sink on a dark background, and never measured it. Nothing sinks (the
  dimmest disc clears the background by 34.7), and a table derived from the
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
