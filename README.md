# Assay

r2ts's factory-automation game: design your own machines from parts, chase
purer ore deeper into space, build with friends.

- `sim-game/`: the game. Rust workspace: simulation core, terminal inspector,
  multiplayer relay, and the art pipeline. Start with `sim-game/GAME.md` and
  `sim-game/CLAUDE.md`.
- `docs/`: engineering primers (how the sim and renderer are split).
- `reports/`: genre and market research behind the project.
- `research_notes/`: raw notes the reports were written from.

## Quick start

```bash
make relay                    # host world 42 on port 7777
make join NAME=ada            # connect to localhost (add HOST=ip:7777 for another machine)
make play                     # single-player inspector
make test
```

Without make, from `sim-game/`:

```bash
cargo run -p sim-relay
cargo run -p sim-cli -- --connect localhost:7777 --name <name>
```
