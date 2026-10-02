# Assay (r2ts)

Read this first, then `sim-game/CLAUDE.md` (code rules) and `sim-game/GAME.md`
(design and art brief) for whatever you're working on.

## What this is

**Assay** is a factory-automation game by r2ts, a two-to-five-person studio
of strong engineers with no dedicated artist. The hook: players **design
their own machines from parts** (a two-claw inserter moves twice as much but
costs more to build and draws more power). Every world generates its own
mineral species with a property sheet, and ore has a **purity** (1–100) that
rounds into a grade; where purity comes from is undecided (the old
"rises with distance from spawn" rule was withdrawn on 2026-09-30, see
`docs/adr/0001`). Purer ore makes better parts, better parts enable better
designs, and the factory gets rebuilt. Played solo or in **co-op**, with a **shared online galaxy** planned
later. Comparable games: Factorio, Dyson Sphere Program, shapez, Mindustry.

The name "Assay" (the test that measures ore purity) was chosen on
2026-09-30 after checking Steam; nothing else on Steam uses it. Trademark and
domain checks are still to do. The repo folder may still be called `r2ts`.

## Two principles that never bend

1. **The simulation is separate from any renderer.** The `sim` crate is
   plain data plus `step()`. It never imports, calls, or knows about a
   renderer, a network, a file, a clock or an engine. Renderers only read
   from it (snapshots and events) and only change it by submitting commands.
   If deleting Godot tomorrow would break a piece of code, that code is in
   the wrong place: rules go in `sim`, everything else is a host.
2. **The game is always playable without a renderer.** Every feature must be
   fully usable headless: through `sim-cli` commands (inspector and `--plain`),
   the relay, and automated tests. Text-mode play is not a stopgap until
   graphics arrive; it is the reference client and the test harness for
   everything that follows. No feature is "done" if it only works with
   graphics.

Every feature, in this order: sim rules and tests → a `sim-cli` command (and
inspector panel if it's state worth seeing) → determinism check → only then
any graphics. See "Adding a feature" in `sim-game/CLAUDE.md`.

## Repo map

| Path | What |
|---|---|
| `sim-game/` | The game: a Rust workspace (see below) plus the art pipeline |
| `sim-game/GAME.md` | Pitch, pillars, what's built, planned entities, art direction. Sections are marked Decided / Built / Open |
| `sim-game/CLAUDE.md` | Code and art rules for agents working in `sim-game` |
| `sim-game/design/` | Design proposals, marked Decided / Open like `GAME.md`. `starting-zone.md`: the guaranteed mineral ladder around spawn. `properties.md`: the material/part/machine properties and rules; every material is procedurally generated, so nothing may name a specific material |
| `sim-game/packaging/` | README files that ship inside the downloadable bundles |
| `docs/sim-core-primer.html` | Teaching page on the sim/renderer split. Published artifact copy exists too |
| `reports/` | Genre/market research: `Game genre profitability for indies.md` (cited report) and `genre-playbook.html` (visual version) |
| `research_notes/` | Raw notes the report was built from |
| `docs/adr/` | Architecture decision records: one accepted decision per file, the binding form of what the design notes and proposals settled. Read the ones touching a feature before building it; see its README for the rules |
| `docs/design-notes/` | Decisions from spoken design sessions (`make talk`). Read the ones relevant to a feature before building it |
| `tools/voice/design_chat.py` | The voice loop: mic → ElevenLabs Scribe → `claude -p` → ElevenLabs speech. Design conversations only; it writes a note on "wrap it up" |
| `Makefile` | `make relay`, `make join HOST=… NAME=…`, `make play`, `make test`, `make ip` |
| `.github/workflows/build.yml` | CI: fmt, clippy, tests; Mac + Windows bundles; releases on `v*` tags |

## Architecture in one paragraph

The simulation (`sim` crate) is a pure library: plain data (`World`) plus
`step(world, inputs, events)`. It knows nothing about rendering, networking,
files, or wall-clock time. Every other program is a **host** that wraps it:
`sim-cli` (terminal inspector / single-player), `sim-relay` (headless
multiplayer host), tests, and later a Godot client. Multiplayer is
**deterministic lockstep**: only inputs travel over the network, every peer
runs the full sim, and state hashes are compared to catch desyncs. This is
why determinism rules are non-negotiable.

### Crates (`sim-game/`)

- **`sim`**: `World` (tick, seed, seeded `Rng`, chunks, `species`,
  `deposits`, `players`, `buildings`), `mineral.rs` (`MineralSpecies` with a
  six-number `Sheet`, `Grade` C/B/A from purity, `effective(property,
  grade)`), `worldgen` (species roster rolled from the seed and rerolled
  until the starter ladder holds; one deposit per 16×16 chunk, pure function
  of seed + chunk; amount grows with distance from spawn, purity is a plain
  seeded roll per ADR 0001; the two chunks beside spawn always hold the
  starter material and a hand-lit fuel), `ladder.rs` (reachable rungs from
  a roster), `command.rs` (`PlayerCommand`: Mine/Craft/Place/Insert/Take/
  Pickup/Assay/Rename/GrantRename/MoveTo/Stop; `SystemCommand`: AddPlayer;
  `Input` wraps them), `step.rs` (apply inputs, then systems in fixed
  order: movement, hand mining, assaying, hand crafting, smelters),
  `item.rs` (`Item` = kind + species + grade, `ItemStack`), `inventory.rs`
  (sorted stacks), `recipe.rs` (fixed table keyed by item kind with property
  thresholds and grade-raising refining; never names a species),
  `building.rs` (`Building` with its material, `Smelter`, `Slot`),
  `tuning.rs` (every rate, cap and threshold), `save.rs` (JSON saves with a
  version), `hash.rs` (FNV-1a state hash), `debug.rs` (ASCII map, tables,
  rough-vs-exact sheet readings).
- **`sim-net`**: wire protocol. `ClientMsg` (Hello/Submit/Hash), `ServerMsg`
  (Welcome/Refused/Tick/Desync), `TickBundle`, length-prefixed JSON framing,
  `PROTOCOL_VERSION`, `saves_dir()`.
- **`sim-relay`**: owns the clock (default 10 ticks/s), orders inputs, runs
  the sim, welcomes joiners with a snapshot, checks hashes every 20 ticks,
  autosaves every 20 ticks, maps accounts → `PlayerId` in
  `world-<seed>.accounts.json`. `auth.rs` has `DevAuthenticator` (trusts the
  name); a Steam ticket verifier goes in the same trait later.
- **`sim-godot`**: GDExtension host (`cdylib` + `rlib`), over `sim` + `sim-net`.
  Exposes one class, `AssaySim`: build a world from a relay `Welcome`, apply a
  `TickBundle` (refused unless it is the next tick), read tick / hash / seed /
  size. Hashes and seeds cross as **hex text**, never numbers. GDScript submits
  and reads; the only way this crate changes a world is `sim::step`.
- **`sim-cli`**: `host.rs` (session, command handlers, local clock/queue or
  online link), `tui.rs` (ratatui inspector: half-block map, world/players/
  inventory/tile/buildings/deposits/inputs panels, scrollable console,
  always-active command line), `net.rs` (join handshake, sender/receiver
  threads), `output.rs` (print vs capture). `--plain` gives the old
  rustyline prompt. `tests/first_plate.rs` plays a fresh world to the first
  gear through the plain prompt; it is the reference play-through.

### Numbers that matter

- Chunk = 16×16 tiles. Test world = 6×4 chunks (96×64 tiles). Spawn = centre
  of the middle chunk.
- Minerals: 6 generated species per world (ADR 0001), each a sheet of six
  1–100 numbers (density, strength, hardness, heat tolerance, reactivity,
  conductivity) and a generated name. No rule or recipe names a species.
  Deposits: one species, radius 2–4, ≤1 per chunk, never overlap, purity
  1–100 → grade C (<40), B (40–69), A (≥70). Grade scales strength,
  hardness, reactivity and conductivity to 60/80/100%; density and heat
  tolerance never scale.
- Items are kind + species + grade (kinds: ore, refined, gear, smelter) and
  stack only when all three match. Typed as `kind[:species[:grade]]`.
- Refining raises grade at a loss: `sort` by hand (3 ore → 1 ore, +1 grade,
  20 ticks) and resmelt in a smelter (3 refined → 1 refined, +1 grade, 40
  ticks). Grade A cannot be refined further.
- Sheets read as 25-wide bands until a player assays a deposit (30 ticks
  standing on it); then exact for the whole world. The first player to mine
  or assay a species is its discoverer and may rename it (letters, digits,
  hyphens, ≤20) or grant rename rights. Renames are player commands.
- Rules in `sim/src/tuning.rs` and `sim/src/recipe.rs`: hand mining needs
  hardness ≤ 40 and yields 1/2/3 ore per 4-tick cycle by grade; smelter = 5
  ore of any species, 2×2, walls = that species' heat tolerance; fuel needs
  effective reactivity ≥ 25, burns 2 ticks per point, lights from cold only
  if its heat tolerance ≤ 30 (hand spark); ore smelts when the fire reaches
  its heat tolerance, 20 ticks per unit; gears need hardness ≥ 20 at grade;
  reach 3 tiles. The starter ladder is judged at grade B.
- Save format `SAVE_VERSION = 10`. Versions 1–8 (named ores) do not load:
  the cut-over had no compatibility shim by decision; v9 never shipped.
- `PROTOCOL_VERSION = 4`. Bump it whenever `World` or a message changes
  shape; the relay refuses mismatched clients.
- Golden determinism hash lives in `sim/tests/determinism.rs`. It changes
  whenever rules change; update it only for intentional changes and say so
  in the commit.

## Decisions already made (don't relitigate without the founders)

- **Genre**: automation/colony sim first; MOBA/MMO rejected (see `reports/`).
- **Engine**: Godot planned for the client, with the sim staying a separate
  Rust crate. Three.js/Unreal rejected. No Godot code exists yet.
- **Multiplayer**: lockstep with a relay now; a galaxy service later (maybe
  SpacetimeDB) that talks to relays, never to the tick. External effects enter
  a world only as tick-stamped system commands and leave only as events.
- **Identity**: in-world `PlayerId` is a slot; global `AccountId` strings
  like `dev:ada` / `steam:…` live in the relay/galaxy layers.
- **Art**: prerendered 3D sprites generated from Blender scripts in
  `sim-game/art/`; never hand-edited. Readability at 1× beats detail. Ore
  kinds distinguishable by shape and colour; purity visible; modular machine
  parts drawn as separate pieces.
- **Generative AI art**: Steam requires disclosure; players react badly.
  Decision recorded in `GAME.md`; don't add AI-generated player-facing art
  without checking there.
- **Saves**: JSON for now (readable while small); binary later. Autosave is
  every 20 ticks (tick-based; switch to time-based before worlds get big).

## Working conventions

- Run everything from `sim-game/` (or use the root `Makefile`).
- `cargo fmt`, `cargo clippy --all-targets -- -D warnings`, `cargo test`
  must all pass; CI enforces them on every push and PR.
- Work on branches and merge via PR once more than one person is active.
- Commit messages: short imperative subject; mention golden-hash or
  protocol/save-version bumps explicitly.
- Under `cargo run`, saves go to `sim-game/saves/`; shipped binaries save
  next to the executable; `R2TS_SAVES_DIR` overrides both.
- Don't touch `sim-game/saves/world-42.json` casually: it's the founders'
  ongoing test world.
- Testing the inspector without a screen: drive it through a pty (see the
  scratch script pattern: spawn with `pty.fork`, send keys, strip ANSI).
- Piped stdin automatically uses the plain prompt, which is how scripted
  end-to-end tests drive `sim-cli`.

## Release / testing bundles

- CI builds `assay-macos.zip` (universal, ad-hoc signed) and
  `assay-windows.zip` (static CRT) on every push to `main`; download from
  the run's Artifacts (login needed) or push a `v*` tag for a public
  GitHub Release.
- Each zip holds `sim-cli`, `sim-relay` **and the Godot client**
  (`Assay.app` / `Assay.exe`, carrying the `sim-godot` library so it runs the
  real rules), exported by the version of Godot pinned in
  `GODOT_VERSION` in the workflow, from `client/export_presets.cfg`. The
  editor and its export templates are anonymous downloads from the public
  godotengine/godot releases: no account, nothing bought. Every exported
  build runs `--headless -- --selfcheck <file>` before it is zipped, because
  an export can succeed and still ship a pack that will not load.
- Mac and Windows testers must use bundles from the same run.
- Testers on other networks reach the relay through Tailscale or a
  forwarded TCP 7777. The relay prints the LAN address on start.
- Local cross-builds: rustup toolchain in `~/.rustup` (Homebrew's cargo lacks
  the extra targets); `cargo xwin build --target x86_64-pc-windows-msvc` for
  Windows; `lipo` for the universal Mac binary.

## Current state and next steps (as of 2026-09-30)

Built: world gen with generated mineral species and a guaranteed starter
ladder (ADR 0001), players walking, JSON saves, relay + client lockstep
co-op verified across Mac and Windows, the terminal inspector, CI bundles,
the art pipeline with first sprites (ground, ore, player, spawn, drill,
items; still drawn for the old four ores), and the first gameplay loop on
top of species and grades: hand mining, item stacks, property-threshold
recipes, and the smelter with heat-capped walls and reactive fuel (see "The
first loop" in `GAME.md`).

ADR 0001 is fully built except what waits on later systems: refining rung
three ("later tech"), sheets that sharpen with better tools (today only the
assay action sharpens them), and ladder rungs beyond zero.

Not built yet, roughly in order: mining drills as entities (which is what
lets hardness progress past hand mining; needs the step-factor decision
that ADR 0001 left open), belts, inserters
(the modular design system), assemblers, items on belts, generated looks
for species, the Godot client, reconnect without restart, client-side
movement prediction, time-based autosave, binary saves, graceful relay
shutdown, Steam auth, galaxy layer.

Known rough edges: the relay loses up to 2 s on Ctrl-C; a dropped client
must restart to rejoin; your own moves wait for the host (~1 tick).

## People

- Hasan Abu-Rayyan (hasanaburayyan21@gmail.com): founder, runs the Mac host.
- A second developer is joining (collaborator on the GitHub repo).
- A friend tests on Windows.
