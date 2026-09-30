# Assay: design and art brief

Assay is the game's name (an assay is the test that measures ore purity;
chosen 2026-09-30). This file describes the game for anyone contributing
to it, including art. Sections are marked **Decided**, **Built** (exists in
code today), or **Open** (not decided; don't treat as final).

## The pitch

A factory-automation game where **you design your own machines**. Instead of
picking from a fixed list of inserters and assemblers, players build machines
from parts (a two-claw inserter moves twice as much but costs more to build and
draws more power). Better ore found deeper in space unlocks better parts,
which unlock better designs, which means rebuilding the factory. Played solo
or in co-op, eventually inside a shared online galaxy.

Comparable games: Factorio, Dyson Sphere Program, shapez, Mindustry. The
difference is the machine designer.

## Pillars

1. **Custom machine design (Decided, core hook).** Machines are assembled from
   parts: claws, arm segments, filters, and more later. A design's parts set
   its stats (speed, reach, power draw) *and* its build recipe, so every
   design choice is a trade-off the factory has to pay for.
2. **Procedural ore that improves with distance (Decided, partly Built).** Ore
   deposits have a purity from 1 to 100. The further from spawn (and later,
   the deeper into space), the purer the ore. Purer ore makes better parts.
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
- **Ore deposits:** circular patches 2–4 tiles in radius, at most one per
  chunk, never overlapping. Each has a kind, an amount left, and a purity.
  A depleted deposit stays on the map with 0 ore.
- **Ore kinds:** Iron, Copper, Coal, Stone.
- **Players:** named characters on the tile grid. They walk one tile per tick
  in 8 directions (diagonals included). Several players can share a world.
- **Items and inventories:** players carry stacks of items: the four ores,
  iron and copper plates, iron gears, and smelters waiting to be placed.
- **Hand mining:** stand on a deposit and `mine`; one ore arrives every few
  ticks until you stop, walk off, or the deposit runs out.
- **Hand crafting:** a fixed recipe table. Batches take their inputs up
  front and finish over ticks while you keep walking or mining.
- **Smelter:** the first building. Crafted from stone, placed on a 2×2
  footprint within reach, fed ore and coal by hand, and it smelts plates on
  its own until its output slot fills or its fuel runs out.

Gameplay today is the first loop described below. Belts, inserters and
drills are next.

## The first loop (Decided 2026-09-30, Built)

Mine stone by hand, craft a smelter, place it, feed it ore and coal, take
plates out, craft gears. The smelter is the first thing that works while the
player is elsewhere, and its stalls (full output, no fuel) are what belts and
inserters will fix. All numbers live in `sim/src/tuning.rs` and
`sim/src/recipe.rs`; they are starting points, not final.

| Rule | Value |
|---|---|
| Hand mining | 1 ore per 4 ticks, standing on the deposit |
| Smelter recipe | 5 stone, 20 ticks by hand |
| Iron gear recipe | 2 iron plate, 5 ticks by hand |
| Smelting | 1 ore → 1 plate, 20 ticks, in a smelter only |
| Coal | 1 coal burns for 80 ticks of smelting (burns only while working) |
| Smelter slots | input 50 ore of one kind, fuel 50 coal, output 50 plates |
| Reach | 3 tiles (diagonals count as 1) to place, fill, empty or pick up |

Deliberately left out of this pass: ore purity and hardness on items and
recipes (**next up**; inventories are stacks so a tier field is a save
migration, not a rewrite), craft queues, power, and any machine beyond the
smelter.

## Planned entities (Decided in concept, not built)

These need art eventually. Rough order they'll be built:

| Entity | Notes for art |
|---|---|
| Smelter (**Built** in sim) | 2×2. Burns coal, ore in, plates out. Needs an idle, working, and stalled look |
| Mining drill | Sits on a deposit and extracts ore over time |
| Conveyor belt | Straight, corner and junction pieces; items ride on it |
| Inserter | **Modular**: base + arm segments + 1 to 4 claws + optional filter. The number of claws and arm length must be visible at a glance |
| Assembler | Turns inputs into outputs (e.g. ore into gears) |
| Chest | Storage |
| Items | Ore of each kind (**Built**), plates and gears (**Built** in sim), then claws, arm segments, sensors |
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

Generated by `art/build.py` into `assets/sprites/` (sheets + `manifest.json`;
`contact.png` is the review sheet).

1. Ground tile, 4 seamless variants (`ground`)
2. Ore deposit tiles for Iron, Copper, Coal and Stone: 4 purity tiers ×
   full/edge, plus depleted (`ore`)
3. Player character: idle and walking, 8 directions (`player`)
4. Spawn marker, 3×3 pad with blinking beacons (`spawn`)
5. Item icons for the four ores (`items`)
6. Mining drill, 2×2, idle + working animation (`drill`), ahead of the sim

## More background

- `../reports/genre-playbook.html` and
  `../reports/Game genre profitability for indies.md`: why this genre, and
  art-light strategies.
- `../docs/sim-core-primer.html`: how the simulation and renderer are split.
