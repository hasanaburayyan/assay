# 0001. Generated mineral species with purity grades

- Status: Accepted
- Date: 2026-09-30
- Source: `docs/design-notes/2026-09-30-generated-minerals.md` and
  `docs/design-notes/2026-09-30-minerals-grade-and-refining.md`; proposals
  in `sim-game/design/properties.md` and `sim-game/design/starting-zone.md`

## Context

Assay's hook is designing machines from parts, and the material a part is
made of should matter. The sim currently ships four real ores (Iron, Copper,
Coal, Stone) with recipes that name them, which cannot support per-planet
minerals or the "assay" fantasy of working out what an unknown ore is good
for. Two drafts proposed generated minerals with property sheets but
disagreed on the sheet and left purity, stacking, refining and migration
open. The sim must stay renderer-free and deterministic, and every feature
must be playable headless.

## Decision

1. Every world generates its own mineral **species**. There is no fixed
   list and nothing in rules, recipes or progression names a specific
   material; requirements are expressed as property thresholds.
2. A species has a fixed sheet of six whole numbers: density, strength,
   hardness, heat tolerance, reactivity, conductivity. Conductivity is
   generated and displayed now but unused by rules until power exists.
3. Deposit purity (1–100) is rounded into **grades** (A, B, C initially).
   Items stack by species and grade. Grade scales strength, hardness,
   reactivity and conductivity, strongly enough that an A-grade part from a
   softer species can beat a C-grade part from a harder one. Density and
   heat tolerance do not scale with grade.
4. Purity raises mining yield as well as product grade. A tiered refining
   process raises grade: first mechanical (time and mass loss), then heat
   and fuel, then later technology.
5. The rule that purity rises with distance from spawn is **withdrawn**.
   Purity's source is open; worldgen drops the distance term.
6. First contact with a deposit shows a rough partial sheet that sharpens
   with better tools or an assay action.
7. A smelter can be built from raw ore of any species; its maximum running
   temperature is capped by its build material's heat tolerance.
8. Worldgen guarantees a climbable starter ladder around spawn with a
   reachability check. Rung zero is hand-gatherable, includes a hand-lit
   fuel, and is abundant rather than renewable.
9. Species get a generated name on discovery. The discoverer may rename it
   at any time and may grant rename rights to others. Renames are player
   commands through the tick.
10. The named-ore code is replaced in **one cut-over**: `OreKind`, ore
    items, named recipes, save version 8 and the golden hash, with save and
    protocol version bumps and no compatibility shim.

## Consequences

- `sim` gains `MineralSpecies`, `Grade`, species-keyed items, property-
  threshold recipes, a refining step, an assay/partial-sheet state, species
  naming with permissions, and a starter-ladder check in worldgen. All of it
  is plain data plus `step()`, shown first through `sim-cli`.
- Save version, protocol version and the golden determinism hash all change;
  `first_plate.rs` is rewritten against a generated species.
- `CLAUDE.md` and `GAME.md` no longer claim purity grows with distance; the
  world test asserting that trend is removed.
- `sim-game/design/properties.md` and `starting-zone.md` stay as discussion
  documents; their unaccepted parts (step factor, leverage rules, keystones)
  remain open.
- Open: purity's source, grade thresholds, refining costs and machines, how
  partial sheets sharpen, species count and density, generated looks and
  names, and whether the step-factor ladder survives alongside grade.
