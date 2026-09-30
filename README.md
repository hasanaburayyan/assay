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
cd sim-game
cargo test
cargo run -p sim-cli          # single-player inspector
cargo run -p sim-relay        # host a world
cargo run -p sim-cli -- --connect localhost:7777 --name <name>
```
