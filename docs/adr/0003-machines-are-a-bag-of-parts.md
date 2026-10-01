# 0003. Machines are a bag of parts over one catalogue table

- Status: Proposed
- Date: 2026-10-01
- Source: decisions 5, 6, 9, 10, 11 and 12 of
  `docs/design-notes/2026-10-01-minimal-demo-loop.md`; the Game Director's
  rulings on work item ASSA-4 (2026-10-01 20:03 and 20:18 UTC) and ASSA-6
  (20:01 UTC); the CEO's break-return default, backed on ASSA-5 (19:43 UTC)

## Context

The demo needs picks and drills, and decision 5 forbids building them as two
recipes: "the demo ships a small part catalogue, not a small assembly
model." That line is the whole risk. A model that needs a new `enum` variant
to add a second hopper, or to add a part kind nobody has designed yet, has
failed even with every test green — so this ADR has to settle a shape in
which **a new part is a row of data and a new machine is a row of data**.

Three forces constrain it. The `sim` crate stays renderer-free and
deterministic, so parts are plain data and any randomness is one seeded roll
per path (ADR 0002 point 5). Nothing may name a mineral species (ADR 0001),
so a part reads properties off its own material's sheet. And the game must be
fully playable in text, so every stat below has to be readable from
`sim-cli` before Godot draws anything.

## Decision

1. **A part is a kind plus a material.** `Part { kind: PartKind, material:
   Item }`, where the material is a `Refined` item and so carries a species
   and a grade. An **assembly** is a frame part plus the parts mounted on
   it. Parts are items (`ItemKind::Part(PartKind)`); an **assembly is not an
   item**, because it holds several species at once — so assemblies do not
   stack, cannot go in a building slot, and get their own home on `World`.
2. **Three part kinds: `head`, `frame(held | planted)`, `hopper`.** The
   handle is *not* a fourth kind; it is the held variant of the frame, per
   decision 6 ("a pick is a head on a handle, where the handle is the
   frame"). The mount is therefore the only thing a pick and a drill differ
   by at the type level, which is what makes decision 6's "one command path"
   true by construction instead of by convention.
3. **The slot a part fills is named by its kind.** There is no separate slot
   type: the frame's catalogue row lists the slots it offers as `(kind, min,
   max)`. A new part kind names a new slot for free. `Assemble` validates
   only that each part's kind is within the frame's limits.
4. **One catalogue table, `PART_SPECS`, in the `RECIPES` idiom.** Each row is
   `PartSpec { kind, name, size, contributions, slots }`. There are no
   machine recipes at all — not for the pick, not for the drill.
5. **`size` is one small integer that means two things**: what the part costs
   in refined material, and how much stuff it is made of for mass. One
   number, so a part cannot be cheap and heavy.
6. **Every stat is a sum of per-part contributions.** `Contribution { stat,
   source, factor }`; `Stat` is `Mass | Budget | Speed | Durability |
   Capacity`; `Source` is `Property(p) | Flat(n)`. A property-sourced
   contribution is `size × effective(p, grade) × factor`; a flat one is `n`,
   unscaled. **The stats function matches on `Source` and never on
   `PartKind`** — that is the review condition that keeps this a model.
   Because stats are sums, a second hopper raises capacity with no new code,
   and two heads would be defined (if a frame ever offered two head slots).
7. **The demo's rows**, with `Contribution`s as `stat(source)`:
   - `head` — `Mass(Density)`, `Speed(Hardness)`, `Durability(Strength)`
   - `frame(held)` — `Mass(Density)`, `Budget(Strength)`
   - `frame(planted)` — `Mass(Density)`, `Budget(Strength)`,
     `Capacity(Flat)` (the tiny internal buffer of decision 9)
   - `hopper` — `Mass(Density)`, `Capacity(Flat)`
   Mass uses density, which never scales with grade, so grade does not
   change what a design weighs. **Durability reads strength and speed reads
   hardness, and neither ever reads the other** (ASSA-6 ruling): strength
   buys life, hardness buys speed, so a hard-but-weak species is fast and
   fragile.
8. **Parts read exactly three properties — hardness, strength, density
   (ASSA-4 ruling).** No fourth. Heat tolerance and reactivity already have
   jobs (smelter walls, fuel); conductivity is deliberately the one dead
   number until power exists. A **hopper's material sets mass only**;
   capacity is flat from the kind, one `HOPPER_CAPACITY`, so hopper species
   is one legible choice: make it light.
9. **Gears are cut as a part kind and kept as an item (ASSA-4 ruling).** No
   demo machine has a gear slot. `recipe.rs` is untouched: `RecipeId::Gear`,
   `GEAR_MIN_HARDNESS` and `requires` stay exactly as built, and
   `requires` does **not** move onto schematics in this milestone.
10. **The sim never refuses an assembly for its mass.** On placement, and on
    a held tool's first use, `mass > budget` **breaks** the machine: no
    building, an event, and a reduced set of parts back (decision 11). The
    heaviest part is always lost — ties resolved by lowest index in the
    assembly's part order, so two peers cannot disagree — and every other
    part returns on one seeded roll per part, `BREAK_RETURN_PERCENT`, taken
    in part order with exactly one `rng` call per part on every path. The
    always-lost rule lives in its own named function so that changing it to
    "the heaviest part that is not the frame" stays one line. **The break
    event names which parts were lost**, because a loss the player cannot
    attribute teaches nothing.
11. **Power is deferred and arrives as one more `Stat` variant plus one more
    contribution row** — a second budget in the same sum, not a second
    system. That is the model's own test of decision 10's last sentence.
12. **Provisional numbers, named as provisional** (nothing has been played
    yet): sizes `head 1`, `frame(held) 2`, `frame(planted) 5`, `hopper 2`;
    `FRAME_BUDGET_PER_STRENGTH 3`; `HOPPER_CAPACITY 50`; planted buffer
    `10`; up to 4 hopper slots, so that **mass is what stops you stacking
    hoppers, not a slot count**. Two anchors fix them, and the play-through
    on ASSA-6 is the oracle: a middling design must fit (grade-B strength 50
    held frame carries 240 against a 150-mass pick), and a reachable one
    must break (the same pick in a density-90 species is 270 and breaks;
    a drill's second hopper breaks it in a dense species). The pick's pool
    is unchanged from its ruling — head size 1 × effective strength 40 ×
    `PICK_DURABILITY_PER_STRENGTH 10` = 400 = **20 swings** at
    `PICK_WEAR_PER_SWING 20`.

Testable: an assembly command takes any part list fitting the frame's slots,
and `n` hoppers for `n` in `0..=max` raises capacity and mass monotonically
with no new code (decision 5); two drills differing only in head density have
different mass and a stronger-species frame carries more (decision 10); an
overweight design placed yields no building, a break event naming the lost
part, and fewer parts back (decision 11). The catalogue tests loop over
`PartKind::ALL` and name no kind, so a part kind added later joins them
without being written into them.

## Consequences

- **ASSA-5 moves `SAVE_VERSION` 10 → 11 (with a migration) and
  `PROTOCOL_VERSION` 4 → 5, and the golden hash changes.** The bump lands in
  the PR that first moves the saved layout, not later: ASSA-8 verifies the
  versions and the hash, it does not defer them. This ADR is docs only and
  moves nothing.
- `ItemKind` gains `Part(PartKind)` rather than one variant per part, so a
  part kind is still one row in one table. `Item::code()` grows a form like
  `part:head#2(B)`, and `ItemKind::ALL` is built from `PartKind::ALL`.
- Part crafting is a new `PlayerCommand` whose cost is read from `size`, so
  no part needs a `RECIPES` row and `recipe.rs` keeps its current shape.
- Known boundary, stated rather than discovered: because slots are named by
  kind, a slot that accepts **either** of two kinds is not expressible. The
  day a machine wants one, the frame's limit list gains a slot name. Nothing
  in the demo wants one.
- Watch condition from the ASSA-5 ruling, for the ASSA-6 play-through: if the
  frame turns out to be the heaviest part in most real designs, "heaviest is
  always lost" becomes "the frame is always lost", which costs the player
  the ability to retry a failed design. At the provisional sizes the planted
  frame *is* the heaviest part of a drill, so this is likely to fire — hence
  the one-line escape in point 10.
- Explicitly left open: the mining-speed curve from the `Speed` stat (ASSA-6,
  with decision 8's test); drill wear, parked by decision 12; whether an
  assembly's home on `World` is its own `Vec` with an id or an embedding in
  `Building` (ASSA-5's call, and the only part of this shape it may settle);
  how a client shows mass against budget so a break is predictable.

## Note on status

`Proposed`, not `Accepted`: `docs/adr/README.md` reserves acceptance for the
founders. The decisions recorded here were made by the board in the design
note and by the Game Director on the work items cited above; only the status
line is waiting.
