# art

Every sprite in the game is rendered from a Blender script in this folder.
No image is edited by hand. To change the look, edit the script and rebuild.

## Run

```bash
art/build.py             # render everything, pack, write the contact sheet
art/build.py ore head    # only these assets
art/build.py --pack      # skip Blender, repack art/out
```

Needs Blender 5.1+ at `/Applications/Blender.app` (or `BLENDER=/path`), and
`uv` (the script pulls in Pillow itself). A full build takes a few minutes
on the CPU.

**`--pack` REPACKS FROM A LOCAL CACHE, AND THE CACHE CAN BE OLDER THAN THE
ART.** `art/out/` is git-ignored, so it holds whatever *your* machine last
rendered — and a sheet merged from someone else's checkout (or your own
worktree) was never rendered into *this* `out/`. Running `--pack` then
silently rewrites that sheet from the stale render. It happened on 2026-10-02:
a plain `--pack` reverted `frame.png`'s grade-A row to the pre-ASSA-27 yellow
glint, a decision the Director had ruled on, inside a PR about deleting an
unrelated asset. `git status` after a build is not a formality — **if a sheet
you did not touch comes back modified, do not commit it; re-render that asset
(`rm -rf art/out/<name> && art/build.py <name>`) and look again.** Re-rendering
`frame` from the committed scripts reproduced the merged sheet byte for byte,
which is the other half of the story: the pipeline is reproducible, so a
diff you cannot explain is a stale cache, not noise.

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

## The engine cannot reach any of this yet, and that is measured now

```bash
art/check_client_can_see_art.py                  # RED today, on purpose
CLIENT_ROOT=<other dir>  art/…can_see_art.py     # moves the project root -> RED
CLIENT_EXCLUDE='assets/*' art/…can_see_art.py    # filters it out of the bundle -> RED
```

A Godot project's `res://` is its project folder and nothing above it. The
project is `client/`; `build.py` writes sheets to `assets/sprites/`, its
sibling. So no client script can name a sheet, there is not one `.import` file
in the project, and an export would not pack them either. Eleven sheets and
four measured checks, and the game has never drawn a pixel of it.

This check is the finding (**ASSA-34**) kept where it cannot be forgotten, and
it becomes the guard once the layout is fixed. It reads the manifest from
wherever it is — inside the project wins if both exist — so the move needs no
edit here. It is deliberately **not** in CI while it is red.

Note the shape of the mistake, because it is the one this whole folder keeps
making: `[importer_defaults]` in `project.godot` (ASSA-14) is correct and is
waiting for a texture that cannot arrive, and I verified that work by copying a
sprite in **by hand**, which is precisely how I did not notice.

## Machines are overlaid part sprites, and the seams have to show

A machine is never a sprite. It is whole part frames stacked at one position
(`rig.py` rule 2), with the nth repeat of a kind stepped by
`PART_REPEAT_OFFSET` (rule 5), so capacity is something you can count. That is
what `art/assemble.py` builds and judges, at the size the player sees:

```bash
art/assemble.py                   # GREEN; writes assets/sprites/assembled.png
PART_OFFSET=0,0  art/assemble.py  # repeats back on top of each other -> FAIL
HOPPER_LIGHT=1   art/assemble.py  # hopper back at the deck's value   -> FAIL
HOPPER_DARK=1    art/assemble.py  # hopper sunk into its own well     -> FAIL
```

It checks five things. Three were there already: one assembly path builds a
pick and a drill; solid footprint grows with every hopper (a sprite
composited onto itself cannot grow a footprint, which is why that is the
measure and "pixels touched" is not); and a C machine still differs from an A
one once the parts are overlaid. Two are newer, and they are about VALUE:

- **No grade is the odd one out.** The deck-to-hopper and head-to-hopper seams
  are measured as the median dE76 between touching pixels at 1×, per grade,
  for one to three hoppers. A grade may not read at less than **half** the
  strongest grade's seam on the same machine. Shipped on main @2a57a20 that
  ran C 36.9, B 55.1, **A 13.3** — a grade-A chassis blows out neutral
  (Decision #37), so a white deck sat under a steel hopper and the machine
  whose hoppers check 2 had just proved were there was one pale mass
  (ASSA-28). Note that `DISTINCT` **would have passed it**: 13.3 clears 12.
  What makes a seam readable is that it is about as readable as the seams
  beside it, so the bar is a ratio against a sibling, not a floor.
- **The hopper is still an open box.** Fixing the seam means darkening the
  hopper, and far enough down the body falls into its own shadowed well and
  the only silhouette difference in the part set closes up. Gated at *half*
  the part under L\* 35 — not a tuned coefficient, the sentence "a box whose
  interior is most of it is not a box with a hole in it".

The fix was the **hopper's value, not the mark**: narrowing the glint to the
yoke drops `frame`'s own B→A step to 8.6, under `DISTINCT` and barely over the
7.3 of a part whose grade changes nothing in sim, which is the exact failure
the glint rule exists to prevent (Maren, ASSA-28). The hopper is now `grey`
and **the same grey at every grade** — `sim/src/assembly.rs` gives a hopper
Mass from Density and a flat Capacity, and density never scales with grade, so
a grade-A hopper and a grade-C one are the same object to the rules. The
grade dulling was also what made it unaffordable: with it still on, 34.7% of
the C hopper falls under L\* 35 and its gap from the head drops to 7.7.

## Conventions

- 1 Blender unit = 1 tile. +y is north (up on screen). A sprite's footprint
  is centred on the origin.
- **A sprite may overhang its tile, and nothing about the sprite says which
  tile it stands on.** `sim` gives a machine a (1, 1) footprint while a part
  frame is 2 tiles wide, so the sprite overhangs east — the art adapts to the
  sim, never the reverse. The obvious next rule, "then the contact shadow must
  stay inside the occupied tile", was ruled and then withdrawn within the hour
  (ASSA-30, ASSA-38): it cannot be met, because a two-tile body sitting on the
  ground casts a two-tile shadow. Occupancy is sim state the snapshot already
  carries, so the **client** draws it — placement cursor, `building_at` in the
  tile readout — and the sprite stays out of it. Covering a neighbouring
  deposit tile is explicitly fine and wants no guard: ore `amount` is per
  deposit, not per tile. Two machines never share a tile (`step.rs` rejects
  `TileOccupied` on any footprint tile) but adjacent ones overlap on screen;
  draw y then x so the nearer wins.
- **Overlay part sprites with `part_layout.stack`, never plain `over`.**
  Colour composites over, alpha takes the max. Each part carries its own
  contact shadow, so `over` compounds them and a machine's shadow darkens with
  every part bolted on — measured 122 → 167 from one part to four, a gradient
  that reports part count and that nobody chose (ASSA-38). Alpha-max applies
  only below `SHADOW_CEILING`, which is read off the palette's own darkest
  colour, so geometry composites exactly as it always did.
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
