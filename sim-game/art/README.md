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
  (64 px per tile), packs one sheet per asset into `../client/assets/sprites/`
  with `manifest.json`, and writes `../assets/review/contact.png`.
  **Two destinations, see below.**
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

## Where the output goes, and why it is two places

**Shipped art lives inside the Godot project: `client/assets/sprites/`.** A
Godot project's `res://` is its project folder and nothing above it, so a sheet
anywhere else cannot be loaded by a client script and cannot be packed by an
export. For the pipeline's whole life the sheets were in `assets/sprites/`,
the project's **sibling** — eleven files, a manifest and four measured checks,
and the game had never drawn a pixel of any of it. That is **ASSA-34**;
Marlow ruled the move (option A) and `build.py` writes there now.

**Review output stays outside it: `assets/review/`** — `contact.png`,
`assembled.png`, `species_probe.png`, `loudness.png`, `mock_scene.png`. Both
export presets set `export_filter="all_resources"`, which packs every resource
in the project whether a scene references it or not, so review sheets left
beside the game sheets would ride into every shipped bundle and get a Godot
`.import` sidecar apiece for textures no script will ever load. Measured at the
move: **1.45 MB of review sheets against 680 KB of actual game art**, so the
review output was more than twice the size of the thing it reviews. Verified
absent from an exported pack.

```bash
art/check_client_can_see_art.py                  # GREEN; in CI
CLIENT_ROOT=<other dir>   art/…can_see_art.py    # moves the boundary -> RED
CLIENT_EXCLUDE='assets/*' art/…can_see_art.py    # filtered out of the bundle -> RED
```

The check reads the manifest from wherever it is — inside the project wins if
both exist — and is what fails if the output ever drifts back out. Verified
against a real drift, not only the lever: with the sheets moved back to the old
sibling directory it reports all ten unreachable.

**It has one trap worth knowing**, because the lever still exited non-zero and
I nearly ticked it off. `CLIENT_ROOT` used to be the project directory for
every purpose — the boundary, the manifest search, and where
`export_presets.cfg` is read. Harmless while the manifest lived outside the
client; after the move, forcing the root elsewhere made the search miss the
manifest and the check died with *"no manifest.json"*. Red, but for a missing
file rather than an unreachable sheet, and a lever that reproduces the wrong
cause is not a lever. The project directory and the **boundary** are now two
separate things.

Note the shape of the original mistake, because it is the one this whole folder
keeps making: `[importer_defaults]` in `project.godot` (ASSA-14) was correct and
was waiting for a texture that could not arrive, and I verified that work by
copying a sprite in **by hand**, which is precisely how I did not notice. Now
that real sheets are in the project, all nine `.import` sidecars come out with
`compress/mode=0`, `mipmaps/generate=false`, `detect_3d/compress_to=0`, and all
nine load through `res://` as uncompressed RGBA8 with no mipmaps.

## Do the sheets actually ship? (`art/list_pck.py`)

`check_client_can_see_art.py` reads paths and presets. It does not open a
bundle, so it cannot tell you the art is really in one:

```bash
make client-lib
cd client && godot --headless --import && godot --headless --import
godot --headless --export-pack macOS /tmp/assay.pck     # needs NO templates
cd .. && art/list_pck.py /tmp/assay.pck
```

Not a gate and not in CI — it needs an export to exist. **What arrives is not
what you would guess:** the source `.png` files are *not* in the pack. Godot
ships the imported texture as `.godot/imported/<name>.png-<hash>.ctex`, and
`assets/sprites/<name>.png.import` is the remap that makes
`res://assets/sprites/<name>.png` resolve to it. A pack with no `.png` in it is
correct; a pack with no `.ctex` would be the failure. `manifest.json` ships
verbatim, so the client can read it at runtime.

**The art is in the bundle a player actually gets, not only in a local
export.** Pulled the `assay-windows` artifact from the CI run on `main` and
listed the pack *embedded in `Assay.exe`* (the Windows preset sets
`binary_format/embed_pck=true`, so the pack is appended to the exe with an
`[u64 size][GDPC]` footer at EOF — find it there, then feed those bytes to
`list_pck.py`). All nine imported textures are present and **byte-identical to
a local macOS export**, so the chain Blender → sheet → git → Windows checkout →
Godot import → embedded pack changes no pixel.

Two things that bundle taught me, neither of which I would have guessed:

- **The shipped `manifest.json` is 4349 bytes, not the 3990 in git.** Not
  corruption: the Windows runner checks out text with CRLF, the file has 359
  newlines, and 3990 + 359 = 4349 exactly. Normalised, it is byte-identical to
  the committed copy. JSON parsing does not care, but **do not byte-compare or
  hash the manifest across platforms** and expect a match. Measured on the
  Windows bundle only; I did not check the macOS one.
- The source `.png`s are absent from the shipped pack too, same as locally —
  the `.ctex` plus the `.import` remap is the whole story.

**`.import` sidecars are NOT committed, and that is deliberate** — the root
`.gitignore` ignores them and is right to. Measured three ways on 4.6.1: with
sidecars + cache, with sidecars and no cache, and with neither (what a fresh
clone is), `--export-pack` succeeds and **all 19 sheet-related entries are
byte-identical** in all three packs. The only entries that differ are Godot's
own `uid_cache.bin` and exported-scene cache. The hazard we assumed —
regenerated `uid://`s — does not occur either: deleting every sidecar and the
whole `.godot/` cache and re-importing at a different absolute path reproduces
all nine uids exactly.

## The letter on the disc, and the two things that are not the same question

```bash
art/species_probe.py          # GREEN; gates that a readable letter EXISTS
art/check_glyph_contrast.py   # GREEN since ASSA-39 landed; in CI; asks the ENGINE
```

The probe measured disc against disc and disc against map background for two
days and never once measured the **glyph against the disc it sits on**, so "the
map is green" was green about two of the three things on the map. A letter at
contrast ratio 2.22 shipped under a passing check (**ASSA-39**, **ASSA-44**).

These are two different claims and only one of them is the art's:

- **Can a letter be read here at all?** Mine, because the tints are mine. If
  both glyph colours are unreadable on some disc, no picking rule can rescue
  it. `species_probe.py` gates `max(dark, light)` — the ceiling of any possible
  picker — against **WCAG AA for normal text, 4.5**. Not large text's 3.0:
  `glyph_size` draws down to 10px, so `hud.gd`'s own comment is wrong about its
  own glyph (Maren, ASSA-39). **Worst state is 4.5152, at `#FF80BF` purity 24 —
  a margin of 0.0152, one part in 300.** Said out loud rather than buried: a
  tint change that drops this below 4.5 is a design conversation about the
  tint, never a bound to raise in the file.
- **Does the client PICK the better of the two?** Not mine, and not measurable
  in Python. `check_glyph_contrast.py` runs the client headless, calls
  `AssayHud.deposit_color` and `AssayHud.glyph_color` for all 600 states, and
  scores **what the engine actually returned**. It was written RED -- 226 of 600
  states got the glyph with less contrast than the other option would have had
  -- and **went GREEN without being touched** when Limpet landed option A (#69).
  A check of someone else's code flipping on their change, with no edit of mine,
  is the only self-evidence that kind of check can offer.

  `test_hud.gd` now asserts the same optimality property in GDScript, so that
  half is **deliberately double-covered** and this step is not load-bearing for
  it. Both are in CI. What only this file guards is the readability floor above.

**Why it is built that way, and it is the trap I keep falling into.** The easy
version computes both ratios in Python, takes the better, and asserts that
taking the better takes the better. That passes by construction, measures
nothing, and would stay green if `hud.gd` reverted tomorrow — the same shape as
my map-disc check certifying a disc the client never draws. A tautology is
worse than no check, because it occupies the place where a check should be.
So the optimality claim is only ever made about an answer the engine gave.

```bash
GLYPH_FAKE_THRESHOLD=1 art/check_glyph_contrast.py  # replay the old rule -> FAIL
GLYPH_ONE_SPECIES=3    art/check_glyph_contrast.py  # narrowed sweep -> PASSES
GLYPH_FAKE_LINEAR=1    art/check_glyph_contrast.py  # dead transform -> caught
GLYPH_GODOT_TIMEOUT=0  art/check_glyph_contrast.py  # no answer -> exit 2
```

**Three exit codes, and the third is the point.** `0` green, `1` the client or
the tint table is wrong, `2` **NO VERDICT** -- the engine could not be reached,
so the file refuses to say anything. That is a CI failure, never a quiet pass:
a check that cannot run must not look like a check that ran. It also names the
two causes I have actually hit rather than dumping Godot's output: a missing
`.godot/global_script_class_cache.cfg` (the `class_name AssayHud` is not a
global identifier until a full import writes it -- run `--headless --import`
twice) and a missing binding (`make client-lib`).

The Godot call is **time-bounded**, which it was not at first: I hung this
script for five minutes against a project directory that two stale headless
Godots were already sitting on, and an unbounded `subprocess.run` in CI is a job
that burns its limit and reports nothing. The old code also raised
`SystemExit("...exit 2...")`, which prints that text and exits **1** -- the
message was lying about its own exit code, which is the exact class of thing
this file exists to catch in other people's work.

`GLYPH_ONE_SPECIES=3` is there because **a lever that makes a check pass is
worth having explicitly**: `#FFFF33` is 0 of 100 suboptimal, the one tint the
broken threshold gets right everywhere, so grading only it reports GREEN while
226 states are wrong. And the lever is per-species rather than per-purity
because I guessed wrong first — ASSA-39 found the worst *ratio* mid-range, so I
assumed end-sampling would hide the defect, and wrote that down before
measuring. Purity 1 is suboptimal for three species and purity 100 for two.

**Two instruments that disagree.** The probe first said 4.5120 at `#509BE6`
purity 46 while the engine check said 4.5152 at `#FF80BF` purity 24. Cause:
`dim_v` rounds the disc to 8-bit, which is right everywhere else in that file
(dE cannot see half a code value) and decisive here, where three species sit
within 0.015 of each other at their flip points. `disc_exact` is the float
version, and it reproduces the engine's own `deposit_color` for all 600 states
to **1.1e-5** of a code value against `map_disc`'s **0.5**. The two now agree
exactly, and both match the number Maren derived independently.

## The contract a client needs, and what it gets if nobody ships one

```bash
art/check_part_contract.py                        # GREEN; in CI
FAKE_CONTRACT_OFFSET=8,8 art/check_part_contract.py   # module moved, file stale -> RED
```

The sheets and `manifest.json` tell a renderer how to **slice** frames. Nothing
in them says how to **combine** frames into a machine, and the two rules that
do live in `art/part_layout.py`, which only Python can import. So they ship as
`client/assets/sprites/part_layout.json`, written by `build.py` **from the
module** — `repeat_offset_px`, `shadow_ceiling`, and the prose a number cannot
carry (which order repeats count in, what to use instead of `over`).

**A SIBLING FILE, NOT A BLOCK IN THE MANIFEST**, which is what ASSA-54
originally specified. The manifest's top level is an *asset namespace*:
`check_client_can_see_art.py` does `man[a]["sheet"]` for every key, and the
client's `test_sprites.gd` walks it both ways and fails with *"the manifest
describes `X` and there is no X.png"*. A `part_layout` key would have broken
both on the commit that added it.

**What the naive client gets, measured rather than argued.** A client handed
nine sheets and told to draw the parts blits each frame at one position with
the default operator — which is this pipeline's two red levers
(`PART_OFFSET=0,0`, `STACK_OVER=1`) switched on together. A drill gaining
hoppers, at 1×:

| hoppers | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| footprint gained, **rules** | +117 | +108 | +155 | +192 |
| footprint gained, **naive** | +131 | **+25** | **+17** | **+19** |

| hoppers | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| darkest shadow alpha, **rules** | 122 | 122 | 122 | 122 | 122 |
| darkest shadow alpha, **naive** | 128 | 145 | 181 | 205 | 221 |

25, 17 and 19 px are antialiased edges hardening, not parts: **hoppers two,
three and four are invisible**, and capacity is a real number in sim. Meanwhile
the shadow darkens with every part, which is a gradient nobody chose reporting
a quantity shadow has no business reporting — the glint rule inverted. Picture
at 1×: `shared/assay/part-contract-2026-10-02.png`.

**One thing the engine told me that Python would not have.** Godot's JSON
parser returns every number as a double, so the contract arrives as `14.0`,
`-6.0`, `34.0`. Harmless here — all three are small and exactly representable —
but a client must cast, and this is the same hazard `sim-game/CLAUDE.md`
already records for hashes crossing as hex text. Verified by reading the file
from a headless engine run, not by reading the file in Python.

## The third contract: `ui_theme.json` (ASSA-71)

```bash
art/check_pack_icon_plate.py      # GREEN; in CI (needs Godot)
```

Colours the **client draws that are in no sprite**. One so far: the plate
behind a pack-row icon, `#88986C`, written by `build.py` from `art/ui_theme.py`
as the per-channel median of `ground.png`'s opaque pixels.

**It is derived every build, not written down.** Maren's ruling is that the
plate is *the ground's own colour* — so a stack in the pack row and a rock on
the map are the same object. That is a claim about `ground.png`, not about a
hex: a hex typed anywhere stops being true the morning the ground is
re-rendered, and nobody finds out. A sibling file rather than a manifest key
for exactly the reason `part_layout.json` is one (above).

`check_pack_icon_plate.py` holds **three** sources identical — the sheet's
median recomputed now, the shipped `ui_theme.json`, and the `StyleBoxFlat` the
client really painted (read out of the live scene by `pack_icon_layout.gd`) —
and fails if any GDScript spells the colour as a literal. **Nothing in it names
a colour**, so it goes red the day the ground changes rather than passing
forever. `ui_theme.py` is stdlib-only (the vendored `png_stdlib`) because CI
runs the checks on plain `python3`: one derivation shared by the build and the
check beats a Pillow one and a hand-rolled one that can disagree.

Each arm was proved by mutation rather than assumed:

| mutation | result |
|---|---|
| edit the shipped hex to `#88986D` | RED — *and the engine painted `88986D`*, which is how we know the client reads the file and not a constant |
| `Color8(136, 152, 108)` in `sprites.gd` | RED, with file and line |
| point `UI_THEME` at a missing file | RED — "the client painted NO plate" |

**The offset is in the same authoring pixels as `frame_px`**, so a renderer
scales it by exactly what it scales the frame by: at 1× that is half, `(7, -3)`.

## Machines are overlaid part sprites, and the seams have to show

A machine is never a sprite. It is whole part frames stacked at one position
(`rig.py` rule 2), with the nth repeat of a kind stepped by
`PART_REPEAT_OFFSET` (rule 5), so capacity is something you can count. That is
what `art/assemble.py` builds and judges, at the size the player sees:

```bash
art/assemble.py                       # GREEN; writes assets/review/assembled.png
PART_OFFSET=0,0      art/assemble.py  # repeats back on top of each other -> FAIL
HOPPER_LIGHT=1       art/assemble.py  # hopper back at the deck's value   -> FAIL
HOPPER_DARK=1        art/assemble.py  # hopper sunk into its own well     -> FAIL
STACK_OVER=1         art/assemble.py  # parts stacked with plain `over`   -> FAIL
FAKE_PALETTE_FLOOR=20 art/assemble.py # palette outgrew SHADOW_CEILING    -> FAIL
FAKE_CVD_IDENTITY=1  art/assemble.py  # colour-blind transform is a no-op -> FAIL
```

**Seams are scored as the WORST of four observers** — normal, protan, deutan,
tritan, through the same Machado matrices `species_probe` uses, in linear RGB.
Maren ruled that in after measuring it herself and finding it *passes*: every
seam clears `DISTINCT` under every observer, worst 16.3 dE for a deutan viewer
on head|hopper at grade B. The point is that nothing would have said when it
stopped — a C deck parts from its hopper mostly by HUE, and hue is what a
red-green deficient player loses. Today 15 of 15 seam rows are scored by a
colour-blind observer rather than by normal vision, and if that ever became 0
the honest reading is that the transform died, not that the art got robust;
`FAKE_CVD_IDENTITY=1` is that failure, on purpose.

It checks six things. Three were there already: one assembly path builds a
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
  Colour composites over, alpha takes the max. When this rule was written each
  part carried its own contact shadow, so `over` compounded them and a
  machine's shadow darkened with every part bolted on — measured 122 → 167 from
  one part to four, a gradient that reports part count and that nobody chose
  (ASSA-38). Alpha-max applies only below `SHADOW_CEILING`, which is read off
  the palette's own darkest colour, so geometry composites exactly as it always
  did.
  **ASSA-64 removed the contact shadow from every mounted part**, so today's
  sheets cannot compound one: a Design has exactly one planted frame and the
  frame is the only kind that stands on the ground. The operator stays — it is
  what makes plain `over` correct rather than lucky, and a future
  ground-standing part kind brings the compounding back. Check 4 of
  `check_part_contract.py` is what keeps mounted parts shadowless; the client's
  own witness for this moved for the same reason (see `test_assembly.gd`).
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

## Looking at art the client has already drawn

`pack_icon_layout.gd` + `pack_icon_sheet.py` answer "what does this actually
look like in the game", for the HUD's pack rows (ASSA-57):

```bash
godot --headless --path client --script "$PWD/art/pack_icon_layout.gd" \
  | sed -n 's/^LAYOUT_JSON //p' > /tmp/layout.json
uv run --with pillow python art/pack_icon_sheet.py /tmp/layout.json
# -> assets/review/pack_icons.png
```

The geometry is ASKED OF THE ENGINE, not assumed: the probe instantiates
`main.tscn`, rebuilds the richest pack the offline session really holds, lets
layout run and prints each icon's laid-out rect, atlas region, `modulate` and
row height. `custom_minimum_size` is only a floor — a TextureRect fills its
row vertically, so the drawn scale depends on how many verbs a row has.

NOT A GATE and deliberately thresholdless: it reports a spread (the same ore
icon is 2.01 against the HUD's background in one species slot and 8.02 in
another), and which spread is acceptable is the Director's call.

**Regenerate it from a FRESH layout, never a cached `/tmp/layout.json`.** The
sheet shipped for days saying `Frame` on four part rows while the client said
`Mount` on two of them (ASSA-132) — not because anything read the wrong source,
but because nobody re-ran it after ASSA-103 changed the word. The sheet is the
artefact whose whole job is to be believed, so one that disagrees with the game
is worse than none.

`pack_icon_sheet.py` therefore **stamps the words it drew into the PNG**
(`pack_words.py`, a `tEXt` chunk) and `art/check_pack_row_word.py` — in CI —
asks the live engine for the same words and compares, as well as checking each
part row's word against the catalogue's `is_frame`. If it goes red, regenerate;
that is what rewrites the stamp. The stamp carries the sheet's **words and not
its pixels**, on purpose: a re-rendered sprite would otherwise turn it red while
every word was still true, and a check that cries wolf gets obeyed blind.
