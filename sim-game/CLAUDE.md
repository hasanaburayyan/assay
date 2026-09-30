# sim-game

Read `GAME.md` first: it describes the game, what's built, and the art
direction.

## Layout

- `sim/`: the simulation core. Game rules only.
- `sim-net/`: wire protocol shared by client and relay.
- `sim-relay/`: headless multiplayer host (owns the clock, orders inputs).
- `sim-cli/`: terminal client, single-player or `--connect` to a relay.
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
  rule changes.

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
