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

Both are checked by `art/species_probe.py`, which also measures species
separation through protan / deutan / tritan simulation — the old art was
colour-blind-safe by *shape*, and tinting spends that redundancy. Run it
after touching ore art, the palette or the tints:

```bash
uv run --with pillow python art/species_probe.py   # exits non-zero on a regression
PROBE_SPAN=0.1 uv run --with pillow python art/species_probe.py   # must FAIL
```

The second line is not decoration. Two guards in this pipeline have silently
stopped guarding (a colour-blind check grepping for a row name that no
longer existed; a chroma threshold set looser than the defect it existed to
catch), so the probe has a lever that makes its verdict go red on purpose.

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
