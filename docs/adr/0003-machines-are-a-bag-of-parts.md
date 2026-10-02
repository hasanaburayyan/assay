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
    heaviest part is always lost — **superseded by amendment A1 below: the
    heaviest part that is NOT the frame** — ties resolved by lowest index in
    the assembly's part order, so two peers cannot disagree, and every other
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
    was head size 1 × effective strength 40 × `PICK_DURABILITY_PER_STRENGTH
    10` = 400 = 20 swings at `PICK_WEAR_PER_SWING 20` — **superseded by
    amendment A2 below: 60 per strength, so 120 swings.**

Testable: an assembly command takes any part list fitting the frame's slots,
and `n` hoppers for `n` in `0..=max` raises capacity and mass monotonically
with no new code (decision 5); two drills differing only in head density have
different mass and a stronger-species frame carries more (decision 10); an
overweight design placed yields no building, a break event naming the lost
part, and fewer parts back (decision 11). The catalogue tests loop over
`PartKind::ALL` and name no kind, so a part kind added later joins them
without being written into them.

## Amendments, 2026-10-01 (before any code was written)

Recorded rather than edited in, so what was decided and who moved it both
stay visible. All five came from the Game Director on ASSA-5 and ASSA-6, two
of them reversing the CEO's earlier default with their agreement. **I checked
the arithmetic in A1, A2 and A5 myself rather than taking it on faith; every
rate below reproduces.**

**A1. The part always lost in a break is the heaviest that is NOT the frame.**
With no non-frame part, the frame is lost. This takes the one-line escape
point 10 set aside and reverses the *which part* half of the CEO's default
(theirs 19:22, accepted by the Game Director 19:43, reversed by them 20:57,
agreed by the CEO 20:58). Everything else in point 10 stands unchanged.

The reason is measured, not aesthetic. Mass is size × density, so at point
12's sizes the frame is the heaviest part of **every same-species design**
(pick 2d > d; drill 5d > d and > 2d) and of roughly three mixed-species
pairings in four. "Heaviest is always lost" was therefore "the frame is
usually lost" — and the frame is the budget-carrying piece, so losing it on a
failure is a punishment spiral rather than a lesson. Properties roll
independently and uniformly over 1–100 (`worldgen.rs`), so P(density > c ×
strength) = 1/2c for c ≥ 1: a same-species pick breaks at **C 42% / B 31% /
A 25%**, and a four-hopper drill at B at ~57%, which is point 12's "mass is
what stops you stacking hoppers" holding at the rate it claimed.

**Corrected 2026-10-01, by the Game Director correcting their own
justification:** the first draft of this paragraph said "every demo design"
and "unless another part's material is more than 2.5× denser", which were
same-species claims wearing mixed-species clothes. Across independent
densities a head out-weighs a held frame at **2×**, in 24.5% of pairings; a
hopper beats a planted frame at 2.5× (19.6%) and a head beats it at 5×
(9.5%). **A1 itself does not move, and why is worth recording:** wherever a
non-frame part is already the heaviest, "heaviest" and "heaviest that is not
the frame" name the same part, so A1 is a no-op there. It bites only where
the frame is heaviest — the clear majority, and every same-species design. The
rule stands on a correct three-quarters rather than a false whole.

**A consequence, so it is not later read as a bug:** a pick has exactly two
parts, so under A1 the head is always the part lost, at any density. That is
intended — the head is size 1, the cheap piece. The mass *lesson* lives in
drills, where which non-frame part is heaviest varies with density: a pick
teaches "it broke", a drill teaches "it was too heavy".

**A2. `PICK_DURABILITY_PER_STRENGTH` 10 → 60, so the pool is 120 swings**
at a grade-B strength-50 head. `PICK_WEAR_PER_SWING` stays 20. Decision 7
parks the hardness ladder, so hands mine everything a pick can and a pick
buys only **time**; 3 refined costs 3 ore plus 60 ticks of smelting, which
20 swings cannot repay. The first number was measured in ore, and ore is not
what a pick gates.

**A3. Mining speed accumulates; it is not integer tick-steps.**
`HAND_MINE_TICKS 4` can only express 4/3/2/1, and decision 8's test needs 60%
and 100% of one species' hardness to differ. So work accrues per tick against
a fixed work-per-unit (hands 25, unit 100, which leaves hands at exactly four
ticks), with the remainder carrying so the average rate is exactly monotone
in effective hardness. Drills read the same curve; decision 7's hand hardness
gate does not move.

**A4. The two off-by-ones differ on purpose.** A break on first use yields
**no** ore from that swing; the swing that empties the durability pool **does**
yield its ore. A break is a design failing, an emptied pool is work finished.

**A5. The bad case has to be visible, not discovered.** At grade B, 21% of
species have density > 2.4 × strength, which gives a **held frame whose own
mass exceeds its own budget**: every pick built on it breaks whatever head is
fitted, and the player is left feeding heads to a frame. Because unassayed
sheets read as 25-wide bands, **mass against frame budget must be shown —
banded before an assay, exact after** — and the inspector panel ASSA-5 adds
is where that lands first. This is also why `FRAME_BUDGET_PER_STRENGTH` stays
3: breaking is the teeth behind assaying.

## Further amendments, 2026-10-01 (while ASSA-5 part 2 was built)

Three more rulings from the Game Director, on ASSA-5. All three settle how the
model is *shown* rather than what it is, which is why none of them touches
`PART_SPECS`: special-casing the catalogue is what point 6 forbids.

**A6. A hopper's grade is inert, and that is intended.** Capacity is flat from
the kind (point 8) and mass is size × density, which never scales with grade, so
C/B/A change a hopper by nothing at all. Its only material decision is
**species: make it light.** That makes hoppers the sink for grade-C refined,
which is otherwise near-dead content. Recorded rather than fixed: if anyone
later scales `HOPPER_CAPACITY` with grade, the junk sink dies and a four-hopper
drill becomes a grade-A tax. Pinned by `a_hoppers_grade_changes_nothing` so it
is not read later as an oversight.

**A7. A planted assembly must not show durability.** The head contributes
`Durability(Strength)` whatever frame it sits on, but decision 12 parks drill
wear, so on a planted machine that number never moves — and **a number that
never moves teaches a mechanic that does not exist**, which is A5's mirror
image. This is one conditional at the display layer, held frames only
(`debug::assembly_readout` and `debug::machine_status`); the catalogue row is
untouched. Reverse by deleting the conditional.

**A8. Mass against budget is shown as a three-state verdict, computed in
`sim`.** A5 said the bad case must be visible; this is what visible means. Two
banded numbers ("mass 153–225, budget 120–240") would leave the player doing
interval arithmetic, which is the same discovery A5 forbids one step removed.
So: **SAFE** when `mass_hi ≤ budget_lo`, **WILL BREAK** when
`mass_lo > budget_hi`, **UNCERTAIN** when they overlap, with the numbers
underneath for anyone who wants them.

Three states and not a percentage because the verdict is then never wrong —
SAFE breaks 0% of the time, WILL BREAK 100% — so a player learns to trust it in
one session, where "62%" is not actionable and invites them to re-derive it.
UNCERTAIN is a real coin flip (50% at grade B) and its only resolution is 30
ticks of assaying, which is what makes this the advertisement for assaying: at
grade B an unassayed design reads 50.0% SAFE, 12.5% WILL BREAK and 37.5%
UNCERTAIN, and 0.125 + 0.375 × 0.50 = 31.25% recovers the same-species pick
break rate of A1 exactly.

Two things this fixes that are easy to get wrong:

- **Map each band *end* through `effective()`**, which integer-divides and then
  floors at 1; scaling a band afterwards disagrees with the sim's own numbers at
  low values. `Property::effective_value` is now the single home of that
  arithmetic and `Sheet::effective` calls it.
- **It lives in `sim`, in the snapshot, not in either client** (repo `CLAUDE.md`
  principle 1: renderers read rules, they do not own them). Two clients
  computing it would eventually disagree.

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
  with decision 8's test); drill wear, parked by decision 12. The other two
  open questions are now answered: A8 settles how a client shows mass against
  budget, and the assembly's home is settled below.

### An assembly's home on `World` (settled by ASSA-5, as point 10 allowed)

**Neither of the two shapes the ADR offered. An assembly lives wherever it
*is*, and that is three places, because an assembly is not one thing over its
life:**

- **Built and not yet used:** `Player::assemblies: Vec<Built>`, where
  `Built { assembly, durability }`. Not an item, so not in the inventory
  (point 1: it holds several species at once).
- **In hand:** `Player::tool: Option<Built>`, the same type. `Equip` and
  `Unequip` **move** the `Built`, they do not rebuild it.
- **Planted:** `BuildingKind::Machine(Machine)`, embedded in `Building`, 1×1 so
  a drill sits on the deposit tile it works.

A separate `Vec<Assembly>` with ids was rejected: nothing needs to name an
assembly that is not in one of those three places, and an id would be a second
identity to keep in step with `BuildingId`. `Equip` and `PlaceAssembly` address
the built list **by index**, resolved when the command is applied, so two
commands in one tick see the list as the earlier one left it — deterministic,
and identical on every peer.

**Durability is established when a machine is *built*, not when it is
equipped.** This is the one non-obvious consequence and it is load-bearing: if
the pool were filled on `Equip`, putting a worn pick down and taking it up again
would refill it, which is a free repair. Pinned by
`putting_a_tool_down_and_taking_it_up_again_keeps_its_wear`. Planting drops the
pool, which is the same rule read from the other side: decision 12 says planted
machines do not wear.

### Two narrowings ASSA-5 made, named rather than left to be found

- **Making a part is instantaneous.** `MakePart` takes `size` refined material
  and returns the part on the same tick. The cost is the material, and the time
  already went into smelting it: this is what makes A2's published arithmetic
  (re-head = 1 refined = 1 ore + 20 ticks, against 3 refined / 60 ticks for a
  fresh pick) true as written. Adding a forging duration would move every one of
  those numbers. If parts should take time, that is a tuning constant and a
  `Player` field, and A2's upkeep ratio needs restating.
- **A held tool's remaining durability is shown exactly, against a banded
  maximum** (`durability 3240/2400-3600`). The pool is live state that visibly
  drains, so banding it would be worse than showing it. But it is
  `size × effective strength × 60`, so an exact pool **leaks the head
  material's effective strength** even before an assay — a hole in A5 of the
  same kind as the one A8 closes. It is not an exploit at today's numbers:
  learning strength this way costs 3 refined (3 ore plus 60 ticks of smelting),
  where an assay costs 30 ticks and reveals the whole sheet. Named here so it is
  a decision and not an oversight.

## Note on status

`Proposed`, not `Accepted`: `docs/adr/README.md` reserves acceptance for the
founders. The decisions recorded here were made by the board in the design
note and by the Game Director on the work items cited above; only the status
line is waiting.
