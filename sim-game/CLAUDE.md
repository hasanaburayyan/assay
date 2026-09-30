# sim-game

Read the repo-root `CLAUDE.md` for the big picture, then `GAME.md` for the
game design and art direction. This file is the code and art rulebook.

## Layout

- `sim/`: the simulation core. Game rules only.
- `sim-net/`: wire protocol shared by client and relay.
- `sim-relay/`: headless multiplayer host (owns the clock, orders inputs).
- `sim-cli/`: terminal client. Default is the ratatui inspector (`tui.rs`);
  `--plain` (or piped stdin) gives the line prompt. `host.rs` holds the
  session and every typed command; add new commands there and they work in
  both modes.
- `packaging/`: README files shipped inside the CI bundles.
- `art/`: Blender scripts that render every sprite. `art/build.py` writes
  `assets/sprites/`. `art/out/` is raw render output (git-ignored).
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
- After a build, look at `assets/sprites/contact.png` and judge at the 1×
  size, not zoomed in.
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
