# The Assay client

A Godot 4 client that joins `sim-relay` as a lockstep peer (ASSA-7, step 6 of the
2026-10-01 demo-loop note). It reads world state and submits commands; it holds no
rules. `sim-net/src/lib.rs` is the authority for the wire, and a test reads that
file so this client's `PROTOCOL_VERSION` cannot go stale against it.

**Build the sim binding before you open or run anything here:** `make client-lib`
from the repo root. The client loads the real `sim` through a GDExtension, and
Godot aborts with a C++ stack trace if the library named in `sim.gdextension` is
not in `bin/`. The first `--import` after `.godot/` is gone also crashes on exit
in Godot's own doc generation, having already written a complete cache — run it
twice, which is what CI does.

    godot --headless --path . --script res://tests/run_tests.gd
    godot --headless --path . --script res://tools/join_probe.gd -- localhost:7777 ada 3
    godot --headless --path . --script res://tools/lockstep_probe.gd \
        -- localhost:7777 ada 45 walk
    godot --path .                      # the window: host address, name, Join

## What works today

Join and handshake, the welcome snapshot, and then the part that makes this a peer
rather than a viewer: every tick bundle is applied through the real Rust `sim`, the
world is drawn at the tick the sim is actually on, a state hash is reported to the
relay every 20 ticks, and clicking a tile submits `MoveTo`.

Measured against a real relay on 2026-10-01 (`lockstep_probe.gd`): three Godot
clients joined one relay at tick 568, applied 60 bundles each, and all three
reported the identical hash `a39c3182418f0c06` at tick 628 with no desync. In walk
mode one client submitted `MoveTo` and the sim walked it from (56, 40) to (60, 40).
And the check is not vacuous: made to report a deliberately wrong hash, it was
caught — `DESYNC: badhash reported 0000000000003039 for tick 3900, host has
96de8486c066984d`.

## The two rules this client lives by

**No GDScript may run a game rule.** A `TickBundle` carries INPUTS, not state, so
the world at tick N exists only once something runs `sim::step` — and that is the
`sim-godot` GDExtension, reached only through `AssaySimHost`. Nothing here
predicts, interpolates or recomputes a stat. A position on screen is a position
the sim is on; a player's `target` is drawn as a line to where the sim is walking
them, never as a frame of motion we invented.

**The sim is fed the message's bytes, never a parsed Dictionary.** Godot's JSON
turns every number into a double, so by the time a `Welcome` is a Dictionary its
`u64` seed is already wrong. Every signal carries the raw text alongside the
Dictionary: the text goes to the sim, the Dictionary goes on screen. The same trap
runs the other way — a `ClientMsg::Hash` carries a `u64` and GDScript's integers
are signed, so that one message is written in Rust and only framed here.

## Not here yet

**Sprites.** Reconnect used to be listed here too, out of scope by Decision 3 —
"a dropped client restarts to rejoin". It is not out of scope; it works, and
nobody built it (ASSA-177). A drop leaves the stage `DEAD`, `_join_address`
permits a join at `DEAD`, and the relay hands a returning account its own
`PlayerId` back, so one press of Join puts you in the same slot in a running
world. Measured by `tools/reconnect_probe.gd`, which kills a real relay under a
real session: after a host restart you lose the ticks since its last autosave,
and after the socket alone dies with the host still up you lose nothing.

Still not here: a *silent* drop (the client notices a socket that CLOSES, and
keeps no clock of its own on a link that merely goes quiet) and recovery from a
desync, which leaves you joined and really does need a restart.

The part menu and placement used to be listed here as waiting on ASSA-5. They
landed: the bench panel reads `AssaySim.designs_of`, and the probe assembles,
equips and plants through the same `PlayerCommand`s `sim-cli` uses.

Sprites are **blocked on a scale**, and this file has named the wrong blocker
twice. Not the art: that stopped being true at ASSA-19/20, when ore art became
species-neutral and tintable with `AssayHud.SPECIES_TINTS`. Not the path
either: that was ASSA-34, and `art/build.py` writes to `assets/sprites/` inside
this project now, with `tests/test_sprites.gd` proving from inside the engine
that all nine images load through `res://` and match the grid `manifest.json`
claims, and `art/check_client_can_see_art.py` holding the path in CI.

What is in the way is ASSA-46: `AssayHud.map_cell` draws the whole 96×64 world
beside the HUD, so a tile is **9 px** while a frame of art is **64 px**.
Drawing today's images on today's map is a 7× downscale, which the art
direction rules out. Either the client gets a camera at 1× or sprites go only
where the scale suits them — a design call, not an engineering one.
