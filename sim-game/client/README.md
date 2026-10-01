# The Assay client

A Godot 4 client that joins `sim-relay` as a lockstep peer (ASSA-7, step 6 of the
2026-10-01 demo-loop note). It reads world state and submits commands; it holds no
rules. `sim-net/src/lib.rs` is the authority for the wire, and a test reads that
file so this client's `PROTOCOL_VERSION` cannot go stale against it.

    godot --headless --path . --script res://tests/run_tests.gd
    godot --headless --path . --script res://tools/join_probe.gd -- localhost:7777 ada 3
    godot --path .                      # the window: host address, name, Join

## What works today

Join and handshake, the welcome snapshot (species, deposits, players, spawn),
tick bundles counted as they arrive, and the joined snapshot drawn from its own
numbers.

## What it cannot do yet, and why that is a decision and not a gap

A `TickBundle` carries INPUTS, not state. The only way to know the world at tick
N is to run `sim::step` over them, and that is Rust code no line of GDScript may
reimplement (principle 1 in the repo CLAUDE.md). So this client shows the tick it
joined on and nothing newer. Movement, the part menu and placement all wait on one
decision: how the `sim` crate gets into the client (a GDExtension binding is the
candidate) or whether the relay gains a snapshot message. Until then
`AssayNetClient.tick_bundle` is where the sim gets wired in -- never where a
second rules engine grows.
