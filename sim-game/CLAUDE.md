# sim-game

Read the repo-root `CLAUDE.md` for the big picture, then `GAME.md` for the
game design and art direction. This file is the code and art rulebook.

## Layout

- `sim/`: the simulation core. Game rules only.
- `sim-net/`: wire protocol shared by client and relay.
- `sim-relay/`: headless multiplayer host (owns the clock, orders inputs).
- `sim-godot/`: GDExtension host. Lets the Godot client run the real `sim`
  instead of reimplementing it in GDScript. Owns no rules; `sim/Cargo.toml`
  never grows a `godot` dependency. Hashes and seeds cross into GDScript as
  **hex text**, because Godot parses every JSON number as a double and a `u64`
  hash cannot be spelled in GDScript at all. Build it before opening
  `client/` in Godot (`make client-lib`): the engine aborts with a C++ stack
  trace if the library the `.gdextension` names is missing. Separately, the
  FIRST `godot --headless --import` after `.godot/` is gone crashes on exit
  (signal 11 in `EditorHelp::_gen_extensions_docs`, a Godot bug) having already
  written a complete cache — run it twice, which is what CI does.
- `sim-cli/`: terminal client. Default is the ratatui inspector (`tui.rs`);
  `--plain` (or piped stdin) gives the line prompt. `host.rs` holds the
  session and every typed command; add new commands there and they work in
  both modes.
- `packaging/`: README files shipped inside the CI bundles.
- `art/`: Blender scripts that render every sprite. `art/build.py` writes the
  shipped sheets to `client/assets/sprites/` — INSIDE the Godot project,
  because `res://` does not go up and a sheet outside it can neither be loaded
  nor packed (ASSA-34) — and review sheets to `assets/review/`, which stays
  outside the project so an export never packs them. `art/out/` is raw render
  output (git-ignored).
- `saves/`: world saves (git-ignored).

## Rules for the `sim` crate

- No engine, rendering, network, clock or OS dependencies. Hosts (CLI, relay,
  Godot later) wrap it.
- Deterministic: randomness only from the seeded `Rng`, no wall-clock reads,
  stable iteration order (`Vec`, not `HashMap`), integers for rules.
- The world only changes through `step(world, inputs, events)`.
- Changing the saved layout of `World` means bumping `SAVE_VERSION` and adding
  a migration in `save.rs`.
- `tests/determinism.rs` has a golden hash. Update it only for intentional
  rule changes, and mention it in the commit message.
- Anything a client could send lives in `PlayerCommand`; things only the host
  may do live in `SystemCommand`. Never give clients a way to send the latter.
- Validate commands inside `step`, never in the CLI or relay: every peer runs
  the same validation, which is what makes cheating self-defeating.

## Adding a feature (the order matters)

1. **Rules first, in `sim`.** New state goes on `World` (plain data, `Hash`
   + `Serialize`). New player actions are `PlayerCommand` variants; host-only
   actions are `SystemCommand` variants. Behaviour that runs on its own each
   tick is a system called from `step()` in a fixed position. Report what
   happened with `Event`s. Bump `SAVE_VERSION` + add a migration;
   `PROTOCOL_VERSION` too.
2. **Tests before any UI.** Unit-test the rule, then run `cargo test` and
   update the golden hash if the change is intentional. If the feature has
   randomness, it must come from `world.rng`, and the determinism tests must
   still pass.
3. **Make it playable in text.** Add a command in `sim-cli/src/host.rs`
   (`help` text too) and describe its events in `describe_event`. If it adds
   state worth watching, add or extend an inspector panel in `tui.rs`, which
   only reads `World`. Check it in `--plain` mode as well.
4. **Multiplayer for free.** Because everything goes through `step()`, the
   relay needs no change unless a message shape changed. Verify with two
   clients if the feature touches commands.
5. **Graphics last**, and only as a renderer that reads the same `World`.

Never: read the clock or random numbers outside `world.rng` inside `sim`;
mutate `World` from a host except through `step()`; make a command that only
works from the inspector or a future graphical client.

## Rules for `sim-net` and hosts

- Bump `PROTOCOL_VERSION` whenever `World`, a command, an event or a message
  changes shape. The relay refuses clients on another version.
- Hosts (relay, CLI, Godot later) own clocks, files and sockets. The sim
  never does. Anything from outside a world (joins, future galaxy shipments)
  enters as a `SystemCommand` on a tick; anything leaving is an `Event`.
- Command output in `sim-cli` goes through `output::out!`, not `println!`,
  so the inspector can capture it.

## Rules for `art/`

- Sprites are generated, never hand-edited. Change the script, rebuild.
- Anything that must match across assets (palette, camera, light, outline,
  pixel scale) lives in `art/rig.py`, not in asset scripts.
- After a build, look at `assets/review/contact.png` and judge at the 1×
  size, not zoomed in.
- **Check `git status` after a build.** `art/out/` is git-ignored, so
  `--pack` repacks from whatever your machine last rendered; a sheet merged
  from another checkout will be silently overwritten with your stale render.
  A modified sheet you did not touch means re-render that asset, not commit.
- A sprite may overhang its tile, and says nothing about which tile it stands
  on: occupancy is sim state and the **client** draws it (ASSA-30/38).
- Overlay part sprites with `part_layout.stack` (colour over, alpha max), or
  their contact shadows compound and a machine's shadow reports its part
  count (ASSA-38). Since ASSA-64 only a planted frame carries a contact
  shadow, so today's sheets cannot compound one; the operator is still the
  rule, because it is what makes plain `over` correct rather than lucky.
- A contact shadow means the part STANDS ON THE GROUND. Mounted kinds (read
  out of `sim/src/assembly.rs`: anything whose `PartKind` is not a frame) are
  rendered off the ground with `rig.bounce()`, and CI enforces it (ASSA-64).
- Blender 5.x API differences from what you may remember: `scene.node_tree`
  is gone (`scene.compositing_node_group`); render passes were renamed
  (`Z` → `Depth`); the engine is `BLENDER_EEVEE` (not `_NEXT`); set
  `ImageFormatSettings.media_type` before `file_format`; a fresh view layer
  ships with a Freestyle lineset whose `linestyle` is `None`, remove it
  before adding your own; Cycles GPU setup can hang in `--background`, so
  the rig uses the CPU unless `ART_GPU=1`.

## Commands (run from this folder)

```bash
cargo test
cargo run -p sim-cli
cargo run -p sim-relay
cargo run -p sim-cli -- --connect localhost:7777 --name ada
art/build.py            # render + pack all sprites (needs Blender, uv)
art/build.py ore player # only some assets
art/build.py --pack     # repack without rendering
```
