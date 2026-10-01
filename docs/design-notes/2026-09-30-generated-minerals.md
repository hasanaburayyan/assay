# Generated minerals (session in progress, 2026-09-30)

Status: superseded. The session resumed and its decisions are recorded in
`2026-09-30-minerals-grade-and-refining.md` and `docs/adr/0001`. Kept for
history.

## Summary

Assay should not ship a fixed list of real ores (iron, copper, coal, stone).
Instead each world generates its own small roster of invented mineral species,
each defined by a sheet of physical properties the player can read and reason
about. Recipes will care about those properties, not names, which is what
makes per-planet minerals possible when space exploration arrives.

## Decisions

1. Minerals are fully invented, not real elements. No `Iron`/`Copper`/`Coal`
   enum in the long run; the current four `OreKind`s are a stopgap.
2. A mineral is a *species* with a property sheet. The player reads real-ish
   physical numbers on it (density, conductivity, hardness, and similar) and
   uses them to work out what the ore is good for.
3. Species are per-world (later per-planet). A world generates several species
   (working label: X, Y, Z). All deposits of species X share one property
   sheet; deposits differ only by purity and amount, matching current worldgen.
4. Deposits are not individually unique. Two piles of the same species must
   stack and be interchangeable in recipes.
5. Recipes and parts will be expressed as property requirements (for example
   "conductivity at least N" for wire, "hardness at least M" for a gear), not
   as named-ore inputs.
6. Proposed starting property sheet, one number per player decision (not yet
   confirmed by the founder):
   - hardness: gears, tools, drill bits
   - conductivity: wire, circuits
   - density: part weight, power needed to move parts
   - melt point: smelting fuel cost and time
   - energy value: whether the mineral burns as fuel (replaces "coal")
7. The sim stays renderer-free: species and property sheets are plain data in
   the `sim` crate, generated from the world seed, and shown by `sim-cli`
   before any graphics.

## Open questions

- Does purity scale the property numbers (low-purity ore makes a softer gear),
  or does purity only change yield/waste while properties stay fixed per
  species? This was the question on the table when we paused.
- What does the player see on first contact with a new deposit: full sheet,
  nothing until assayed, or a partial sheet that improves with better tools?
- How many species per world, and how are they spread so the early game still
  has a "starter metal" and a "starter fuel" near spawn?
- How are species named and drawn? The art brief wants ore kinds
  distinguishable by shape and colour; generated species need a generated
  look, and a generated or player-given name.
- What replaces stone (the smelter's build material) in a property world?
- Do any properties interact in recipes (for example hardness *and* melt
  point both gate a part), and is there a cap on sheet size to keep it
  readable at a glance?
- Migration: the existing recipe table, items, saves (v8) and the golden hash
  all assume named ores; decide whether to keep a compatibility shim or cut
  over in one go.

## Suggested next steps

1. Resume the conversation and settle the purity question and the first-contact
   question above.
2. Confirm or trim the property sheet to the smallest set that drives distinct
   decisions.
3. Write a one-page spec: `MineralSpecies { id, name, sheet }` in `sim`,
   generated from seed, with deposits referencing a species id.
4. Sketch how three or four existing recipes (plate, gear, smelter) read as
   property thresholds instead of named inputs.
5. Only then plan the migration of `OreKind`, `Item`, recipes, saves and the
   determinism hash.
