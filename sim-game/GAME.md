# Assay: design and art brief

Assay is the game's name (an assay is the test that measures ore purity;
chosen 2026-09-30). This file describes the game for anyone contributing
to it, including art. Sections are marked **Decided**, **Built** (exists in
code today), or **Open** (not decided; don't treat as final).

## The pitch

A factory-automation game where **you design your own machines**. Instead of
picking from a fixed list of inserters and assemblers, players build machines
from parts (a two-claw inserter moves twice as much but costs more to build and
draws more power). Every world has its own generated minerals; purer, better
refined ore unlocks better parts, which unlock better designs, which means
rebuilding the factory. Played solo
or in co-op, eventually inside a shared online galaxy.

Comparable games: Factorio, Dyson Sphere Program, shapez, Mindustry. The
difference is the machine designer.

## Pillars

1. **Custom machine design (Decided, core hook).** Machines are assembled from
   parts: claws, arm segments, filters, and more later. A design's parts set
   its stats (speed, reach, power draw) *and* its build recipe, so every
   design choice is a trade-off the factory has to pay for.
2. **Generated minerals with purity (Decided, see `docs/adr/0001`).** Each
   world generates its own mineral species with a property sheet. Deposits
   have a purity from 1 to 100 that rounds into a grade; purer ore makes
   better parts and can be refined. The earlier rule that purity rises with
   distance from spawn was withdrawn on 2026-09-30; purity's source is Open.
3. **Multiple planets (Decided, later).** Each planet has its own generated
   deposits. Travel outward to find better ore.
4. **Macro planning with drones (Decided, later).** Players lay out large
   blueprints; drones build them over time given enough resources. Players'
   own custom machine designs are what drones build.
5. **Co-op multiplayer (Decided, in progress).** Small groups share one
   world. A shared galaxy layer (trading, shipments between players' worlds)
   comes later.

## What exists today (Built)

The simulation runs headless in Rust (`sim/`), with a terminal client
(`sim-cli/`) and a multiplayer host (`sim-relay/`). There is no graphical
client yet; a Godot client is planned.

- **World:** a square tile grid split into 16×16-tile chunks. The test world
  is 6×4 chunks (96×64 tiles). A seed number generates the whole world.
- **Spawn:** the center of the middle chunk. Players start here.
- **Minerals:** every world rolls six species, each with a six-number
  property sheet (density, strength, hardness, heat tolerance, reactivity,
  conductivity) and a generated name. Nothing in the rules names a species.
  The roster is rerolled until the starter ladder is climbable, and the two
  chunks beside spawn always hold the starter material and a fuel that
  lights by hand.
- **Ore deposits:** circular patches 2–4 tiles in radius, at most one per
  chunk, never overlapping. Each has a species, an amount left, and a purity
  that rounds into a grade (C, B, A). A depleted deposit stays on the map
  with 0 ore.
- **Players:** named characters on the tile grid. They walk one tile per tick
  in 8 directions (diagonals included). Several players can share a world.
- **Items and inventories:** every item is one species at one grade: ore,
  refined material, gears, and smelters waiting to be placed. Items stack
  only when kind, species and grade all match.
- **Hand mining:** stand on a deposit of a soft enough species (hardness
  40 or less) and `mine`; each cycle takes one unit from the deposit and
  gives 1, 2 or 3 ore by grade, until you stop, walk off, or it runs out.
- **Hand crafting:** a fixed recipe table keyed by item kind with property
  thresholds (a gear needs hardness 20 at its grade). Output keeps the
  input's species and grade. Batches finish over ticks while you keep
  walking or mining.
- **Smelter:** the first building, crafted from 5 ore of any species. Its
  walls take that species' heat tolerance. Fed ore and any fuel reactive
  enough (a cold fire needs fuel that lights by hand), it refines ore whose
  heat tolerance the fire reaches, on its own, until its output fills or
  the fire goes out. Refined material fed back in comes out a grade better,
  three to one.
- **Assay and naming:** a species reads as rough bands until someone
  assays a deposit of it. Whoever mines or assays it first discovers it
  and may name it, or let others name it.

Gameplay today is the first loop described below. Belts, inserters and
drills are next.

## The first loop (Decided 2026-09-30, Built on generated minerals)

Mine the starter material by hand, craft a smelter from its ore, place it,
feed it ore and the starter fuel, take refined material out, craft gears if
the material is hard enough. The smelter is the first thing that works
while the player is elsewhere, and its stalls (full output, no fuel, fuel
too cool, fuel that won't light from cold) are what belts, inserters and
better materials will fix. All numbers live in `sim/src/tuning.rs` and
`sim/src/recipe.rs`; they are starting points, not final.

| Rule | Value |
|---|---|
| Grades | purity <40 is C, 40–69 B, 70+ A; C/B/A keep 60/80/100% of strength, hardness, reactivity, conductivity |
| Hand mining | species hardness ≤ 40; one cycle per 4 ticks; yield 1/2/3 ore by grade |
| Smelter recipe | 5 ore of any species, 20 ticks by hand; walls = that species' heat tolerance |
| Gear recipe | 2 refined, 5 ticks by hand; needs hardness ≥ 20 at the item's grade |
| Refining | 1 ore → 1 refined, 20 ticks, in a smelter whose fire ≥ the ore's heat tolerance |
| Fuel | effective reactivity ≥ 25; burns 2 ticks per point, only while working; lights from cold only if heat tolerance ≤ 30 |
| Smelter slots | 50 ore, 50 fuel, 50 output, one item each |
| Reach | 3 tiles (diagonals count as 1) to place, fill, empty or pick up |
| Starter ladder | roster rerolled until rung zero exists; starter material and fuel beside spawn at purity ≥ 50 |

| Refining | `sort` by hand: 3 ore → 1 ore one grade up, 20 ticks. Resmelt in a smelter: 3 refined → 1 refined one grade up, 40 ticks. Grade A is the top |
| Assay | 30 ticks standing on a deposit; until then a species' sheet shows 25-wide bands |
| Naming | the first player to mine or assay a species may rename it (letters, digits, hyphens, 20 max) and grant that right to others |

Only rung zero of the ladder can exist until drills (and a decision on the
step factor) let hardness progress. Refining rung three and sheets that
sharpen with better tools wait on later technology.

## Planned entities (Decided in concept, not built)

These need art eventually. Rough order they'll be built:

| Entity | Notes for art |
|---|---|
| Smelter (**Built** in sim) | 2×2. Burns reactive ore, ore in, refined out. Its material is a species, so its look should carry that species' colour. Needs idle, working and stalled looks |
| Mining drill | Sits on a deposit and extracts ore over time |
| Conveyor belt | Straight, corner and junction pieces; items ride on it |
| Inserter | **Modular**: base + arm segments + 1 to 4 claws + optional filter. The number of claws and arm length must be visible at a glance |
| Assembler | Turns inputs into outputs (e.g. ore into gears) |
| Chest | Storage |
| Items | Ore, refined material and gears per species and grade (**Built** in sim; sprites still show the old four ores), then claws, arm segments, sensors |
| Drones | Fly over the factory carrying items to build blueprints |
| Planets | Seen from a galaxy or system map |

## Art direction

### Decided constraints

- **Readability at scale beats detail.** Factories grow to thousands of
  machines and items on screen. Every entity must read clearly when small.
- **Modular machines must look modular.** Since players design machines from
  parts, parts are drawn as separate pieces that combine (base, arm, claws),
  not as one fixed sprite per machine.
- **Ore kinds need to be told apart by shape as well as color**, so they
  work for colorblind players.
- **Ore purity should be visible**, e.g. brighter, glowing, or more
  crystalline as purity rises. Suggested tiers: 1–25, 26–50, 51–75, 76–100.
- **Depleted deposits need their own look** (the terminal map already shows
  them in lowercase).
- **Simple and consistent over detailed.** The team is engineer-heavy. Pick
  a style that stays consistent across many assets and is cheap to extend.
  Abstract or stylized is fine; the genre accepts simple visuals.
- **The Steam capsule image is the one asset that must be high quality.**

### Decided (2026-09-29): prerendered 3D, built from code

- **Style:** clean stylized low-poly, rendered from Blender to 2D sprites.
  Flat saturated colours (no textures), soft shadows, thin dark outlines on
  machines and characters. Comparable: shapez 2, Kenney's 3D kits, with
  more shading. Chosen because lighting and bevels give depth for free,
  every asset shares one camera/light/palette so hundreds stay consistent,
  and the renders can add normal maps and shadow layers later for real-time
  2D lighting in Godot.
- **Camera:** orthographic, tilted 30° from straight down (a slight 3/4
  view), with the frame stretched so a ground tile stays square. Sun from
  the top-left, cool sky fill.
- **Tile size:** 32×32 px on screen at 1× zoom, authored at 64×64 per tile.
  Rendered at 4× that and downscaled.
- **Player direction frames:** 8 directions rendered by rotating the model;
  no mirroring needed.
- **Palette:** orange (`#F08A24`) is the machine/player accent, gunmetal and
  greys for structure, cyan for lights. Ore kinds each get a base, dark and
  glint colour. Full list in `art/rig.py`.
- **Pipeline:** `art/` holds the shared rig and one script per asset. Assets
  are regenerated from code, never edited by hand. See `art/README.md`.
- **Generative AI:** not used for any shipped asset. Sprites are rendered
  from hand-written Blender scripts (with AI coding assistance, which Steam's
  disclosure form exempts). Image generators may be used for internal mood
  boards only. The Steam capsule will be commissioned from a human artist.

### Animation and timing

The simulation runs at a fixed rate (60 ticks per second planned). The
renderer smooths motion between ticks, so animations can use any frame count;
they don't need to line up with ticks.

### Generative AI art

Steam requires games to disclose AI-generated content players can see (the
form was rewritten in January 2026 to cover anything that ships or appears
in store marketing). In a late-2025 survey, most players viewed generative
AI in games negatively, and several indie games were review-bombed over it.
Decision: none in shipped assets (see above).

## First art asset list (matches what's built)

Generated by `art/build.py` into **`client/assets/sprites/`** (sheets +
`manifest.json`). That is inside the Godot project on purpose: `res://` is the
project folder and nothing above it, so a sheet outside it can neither be
loaded nor exported (ASSA-34). Review sheets — `contact.png` and the probe
output — go to `assets/review/`, which stays outside the project so an export
never packs them.

This list is read off `manifest.json`, not remembered. Nine assets:

1. Ground tile, 4 seamless variants (`ground`)
2. Ore deposit tiles, 7 rows: grades C/B/A × 2 variants each, plus depleted
   (`ore`). **Species-neutral and tinted at draw time** — the art names no
   species, and the six per-world tints are data in `art/species_tints.py`
   and `hud.gd` (Decision #36). The old `_edge` variant is gone (ASSA-26).
3. Item icon, one species-neutral ore (`items`)
4. Machine parts, one sheet each at grades C/B/A: `head`, `handle`, `frame`,
   `hopper`. A machine is never its own sprite — it is part frames overlaid
   at one position, so a player can count what it is made of.
5. Spawn marker, 3×3 pad, 4-frame blinking beacons (`spawn`)
6. Player character, idle (4 frames) and walking (8), in 8 directions
   (`player`)

The 2×2 mining drill that used to be item 6 here was **retired** (ASSA-36):
machines are assembled from parts, so a one-piece drill sprite was art for an
entity the game cannot build.

## More background

- `../reports/genre-playbook.html` and
  `../reports/Game genre profitability for indies.md`: why this genre, and
  art-light strategies.
- `../docs/sim-core-primer.html`: how the simulation and renderer are split.
