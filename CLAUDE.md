# Assay (r2ts)

Read this first, then `sim-game/CLAUDE.md` (code rules) and `sim-game/GAME.md`
(design and art brief) for whatever you're working on.

## What this is

**Assay** is a factory-automation game by r2ts, a two-to-five-person studio
of strong engineers with no dedicated artist. The hook: players **design
their own machines from parts** (a two-claw inserter moves twice as much but
costs more to build and draws more power). Ore has a **purity** (1–100) that
rises with distance from spawn and, later, depth into space. Purer ore makes
better parts, better parts enable better designs, and the factory gets
rebuilt. Played solo or in **co-op**, with a **shared online galaxy** planned
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
| `sim-game/packaging/` | README files that ship inside the downloadable bundles |
| `docs/sim-core-primer.html` | Teaching page on the sim/renderer split. Published artifact copy exists too |
| `reports/` | Genre/market research: `Game genre profitability for indies.md` (cited report) and `genre-playbook.html` (visual version) |
| `research_notes/` | Raw notes the report was built from |
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

- **`sim`**: `World` (tick, seed, seeded `Rng`, chunks, `deposits`,
  `players`, `buildings`), `worldgen` (one deposit per 16×16 chunk, pure
  function of seed + chunk position; purity/amount grow with distance from
  spawn), `command.rs` (`PlayerCommand`: Mine/Craft/Place/Insert/Take/
  Pickup/MoveTo/Stop; `SystemCommand`: AddPlayer; `Input` wraps them),
  `step.rs` (apply inputs, then systems in fixed order: movement, hand
  mining, hand crafting, smelters), `item.rs` (`Item`, `ItemStack`),
  `inventory.rs` (sorted stacks), `recipe.rs` (fixed table, hand or
  smelter), `building.rs` (`Building`, `BuildingKind::Smelter`),
  `tuning.rs` (every rate and cap), `save.rs` (JSON saves with a version and
  migrations), `hash.rs` (FNV-1a state hash), `debug.rs` (ASCII map and
  tables).
- **`sim-net`**: wire protocol. `ClientMsg` (Hello/Submit/Hash), `ServerMsg`
  (Welcome/Refused/Tick/Desync), `TickBundle`, length-prefixed JSON framing,
  `PROTOCOL_VERSION`, `saves_dir()`.
- **`sim-relay`**: owns the clock (default 10 ticks/s), orders inputs, runs
  the sim, welcomes joiners with a snapshot, checks hashes every 20 ticks,
  autosaves every 20 ticks, maps accounts → `PlayerId` in
  `world-<seed>.accounts.json`. `auth.rs` has `DevAuthenticator` (trusts the
  name); a Steam ticket verifier goes in the same trait later.
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
- Ore kinds: Iron, Copper, Coal, Stone. Deposits: radius 2–4, ≤1 per chunk,
  never overlap, purity 1–100.
- Items: iron-ore, copper-ore, coal, stone, iron-plate, copper-plate,
  iron-gear, smelter. Recipes and every rate/cap: `sim/src/recipe.rs` and
  `sim/src/tuning.rs` (hand mining 1 ore/4 ticks; smelter = 5 stone; plate
  = 1 ore, 20 ticks; coal burns 80 ticks; reach 3 tiles; smelter is 2×2).
- Save format `SAVE_VERSION = 8` (v1 world, v2 players, v3 names, v4
  inventories, v5 item stacks, v6 mining, v7 crafting, v8 buildings). Older
  saves migrate on load; v4→v5 reshapes JSON before parsing.
- `PROTOCOL_VERSION = 3`. Bump it whenever `World` or a message changes
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
- Mac and Windows testers must use bundles from the same run.
- Testers on other networks reach the relay through Tailscale or a
  forwarded TCP 7777. The relay prints the LAN address on start.
- Local cross-builds: rustup toolchain in `~/.rustup` (Homebrew's cargo lacks
  the extra targets); `cargo xwin build --target x86_64-pc-windows-msvc` for
  Windows; `lipo` for the universal Mac binary.

## Current state and next steps (as of 2026-09-30)

Built: world gen, players walking, JSON saves with migrations, relay +
client lockstep co-op verified across Mac and Windows, the terminal
inspector, CI bundles, the art pipeline with first sprites (ground, ore,
player, spawn, drill, items), and the first gameplay loop: hand mining,
item stacks, hand crafting from a recipe table, and the smelter as the first
building that works on its own (see "The first loop" in `GAME.md`).

Not built yet, roughly in order: ore purity and hardness on items and
recipes (next), mining drills as entities, belts, inserters (the modular
design system), assemblers, items on belts, the Godot client, reconnect
without restart, client-side movement prediction, time-based autosave,
binary saves, graceful relay shutdown, Steam auth, galaxy layer.

Known rough edges: the relay loses up to 2 s on Ctrl-C; a dropped client
must restart to rejoin; your own moves wait for the host (~1 tick).

## People

- Hasan Abu-Rayyan (hasanaburayyan21@gmail.com): founder, runs the Mac host.
- A second developer is joining (collaborator on the GitHub repo).
- A friend tests on Windows.
