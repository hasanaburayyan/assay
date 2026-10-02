# Hardness, gear thresholds, and alloys (2026-10-01)

Status: discussion note, not a decision record. Written from a typed
conversation after the ADR 0001 cut-over landed on `minerals-cutover`, to
seed a spoken session. Nothing here is decided; the proposals in
`sim-game/design/properties.md` remain the reference for part rules.

**Amended 2026-10-02 (Maren).** One section below — "Measured 2026-10-02" —
*is* decided: it records the ruling on `HEAD_SPEED_PER_HARDNESS` and the two
worldgen lines that go with it (ASSA-32, taken whole by Wren 08:10). It sits
here rather than in a new note because it answers this note's own point 1.
The rest of the file is still the undecided conversation it was.

## What prompted it

Two implementation calls in the cut-over exposed design gaps:

1. **The starter ladder can only guarantee rung zero.** A drill head made
   from hand-minable ore (hardness ≤ 40) has effective hardness ≤ 32 at
   grade B, so nothing you can make today mines anything you couldn't
   already mine by hand. Rungs beyond zero need either the step factor from
   `properties.md` §6 (a tool reaches ~25% above its own number because ore
   is cracked and impure) or another source of hardness.
2. **Gears were gated on hardness ≥ 20 at grade**, so some seeds' starter
   material could not make a gear at grade B. The founder's view: that gate
   is in the wrong place. A gear is shaped material and should be makeable
   from anything; the requirement belongs on the *schematic that uses it*
   (a drill head needs hardness X, a burner needs heat tolerance Y). This
   matches the "requirements apply at the point of use" principle in
   `properties.md`.

## Measured 2026-10-02: rung zero is the problem, not the rungs above it

Point 1 above asks how the ladder climbs *past* rung zero. Measuring
`HEAD_SPEED_PER_HARDNESS` on ASSA-6 turned up something narrower and worse:
in a large fraction of worlds the demo's **first** pick is slower than bare
hands, so the first thing the player builds is a downgrade. The number
everyone was about to approve — raising the factor from 1 to 2 — does not
fix that, because it is a tail, not a mean. Hands run 4.00 ticks/unit
(`WORK_PER_UNIT` 100 / `HAND_WORK_PER_TICK` 25). A head's rate is its
*effective* hardness × the factor, and the demo's first head is made of the
**starter** species, which `ladder::starter_species` picks as
`rungs(species)[0].first()` — roster order, so effectively at random among
the hand-minable species. Over 2000 seeds at factor 2, that species' grade-B
head loses to hands in **40% of worlds** (worst case 50 ticks/unit, twelve
times slower). Scaling the factor shifts every world together; it cannot
reach the soft tail without making the good worlds trivial.

The fix is in worldgen, not in the rate. Two lines, both measured over the
same 2000 seeds: **(a)** pick the starter as the *hardest* species in rung
zero rather than the first — alone this only drops the loss to 23.9%, so it
is necessary and not sufficient; **(b)** add to the existing starter-ladder
reroll the condition that the starter's grade-B head beats hands **and** the
roster holds at least two hand-minable species (9.2% of rosters hold exactly
one, which makes the assay action decoration in the demo — nothing to
compare). Together they accept 70.9% of seeds: **1.41 attempts on average,
i.e. 0.41 rerolls**, and the first pick then beats hands in *every* world,
worst case 3.85 against the hands' 4.00. Rerolling re-maps seed → world, so
existing saves describe different worlds; that is the cost and it is worth
paying once, now, while the only saved world that matters is a test world.

**What that cost turned out to be, measured when ASSA-35 shipped** (this
paragraph predicted a golden hash move, and that half was wrong): 571 of
1000 seeds do get a different world — 278 a different roster, and 293 the
same roster with the starter species moved, which relocates the two deposits
beside spawn. But **neither golden hash moved.** Seed 42 is one of the 429
unchanged worlds: it already passed both new conditions on the same attempt,
and the first species in its rung zero was already its hardest. No
`SAVE_VERSION` or `PROTOCOL_VERSION` bump either, because no field moved and
a save carries its own roster. "This must move the hash" is a claim to
measure like any other.

Two guards fall out of the measurement and belong in CI. The rate is capped
by `mine_by_hand`/`mine_by_machine` yielding **at most one unit per tick**,
so work above `WORK_PER_UNIT` in a tick is discarded: fail the build if the
maximum *reachable* effective hardness × the factor exceeds `WORK_PER_UNIT`
(the reachable maximum is a grade-**A** head of a base-hardness-40 species,
so effective 40: at factor 2 that is 80, inside the cap; at 3 it is 120 and
the game silently discards a fifth of the head's work. That is why the
ruling is 2 and not 3, and why the guard must read the real reachable
maximum rather than a number someone types). And **reach is never speed**:
`HAND_MINE_MAX_HARDNESS` 40 gates machines as well as hands (`step.rs`), so
nothing in the game mines hardness above 40 regardless of what it is made
of. `ladder.rs`'s comment that "drill heads mine up to their hardness" is a
model the sim does not implement; it is harmless only because
`MIN_STARTER_RUNGS` is 1. Gate a future drill on **effective hardness**, not
on the factor.

Method: 2000 seeds of the standard 6×4-chunk test world, built through
`World::new` and scored in a scratch `sim` integration test against
`rungs()` and `effective(Hardness, Grade::B)`.

These figures and the first pass quoted on ASSA-6 (39%, 72.0% accepted,
"1.39 rerolls") differ in two ways, and only one of them is a mistake.

The reroll figure was mislabelled: 1.39 was the expected number of
*attempts*, i.e. 0.39 rerolls, and the same quantity here is 1.41 attempts /
0.41 rerolls. **And 1.41 is the multiplier on the reroll loop that already
existed, not the total cost.** Measured through the real loop when ASSA-35
landed: 2.47 attempts per world before the two new conditions, **3.44
after**, worst seed 17 → 30 rolls. 2.47 × 1.41 = 3.48, so the figure is
right about what it measures and wrong about what it sounds like.

**The percentages differ by sample size alone.** An earlier revision of this
paragraph blamed the population — 4000 rosters from `worldgen::species_roster`
against 2000 worlds from `World::new` — but those are the same population by
construction: `World::new` *calls* `species_roster` (`world.rs:68`), which is
itself the reroll loop, and the roster does not depend on world size. Checked
rather than argued: the rosters are byte-identical for all of seeds 0..1000,
and scoring the same code by either path gives

| seeds | loses to hands | hardest alone | one minable | both accept |
|---|---|---|---|---|
| 2000 | 40.0% | 23.9% | 9.2% | 70.9% |
| 4000 | 38.9% | 22.4% | 9.5% | 72.0% |

So these figures carry about a point of sampling noise and **should be quoted
as "about 40%", never to a decimal**. What is stable across both samples is
the part the ruling rests on: worst accepted pick **3.85 ticks/unit against
the hands' 4.00**, best 1.56, median 2.08. Neither pass was wrong.

## Where grades stand (built, open to retuning)

Purity 1–39 is C, 40–69 B, 70–100 A. Grades keep 60/80/100% of strength,
hardness, reactivity and conductivity; density and heat tolerance are fixed
per species. These were implementation defaults; the thresholds and
multipliers are single constants in `sim/src/tuning.rs`.

## Real-world note

Smelting makes metal purer, and pure metal is usually *softer*. Hardness in
the real world comes from alloying (carbon in iron → steel), heat treatment
and working, not from purity. Purity reliably buys consistency: fewer
inclusions, fewer places to crack, which maps to strength and reliability.
So "refined is harder" is a game convention. A more faithful split would be:
grade drives strength and reactivity; hardness comes from alloying or
treatment. Not urgent, but it is the hook for alloys.

## Alloys, as a sketch

- An alloy recipe takes refined material of two species and makes a **new
  species** in the world's roster, with a derived sheet, a generated name,
  and a discoverer, exactly like a mined species. Items already carry a
  species id, so nothing structural changes.
- Mix rule candidate: each property is a weighted average of the inputs,
  then one property gets a bonus and one a penalty by which family the pair
  leans toward (hardness up, toughness down, say). The bonus makes alloys
  worth it over the better input; the penalty keeps them from being free.
- It runs in the smelter as a hotter recipe needing both inputs' heat
  tolerance reached, which is a natural ladder rung. Grade carries through,
  worst input wins.
- Alloys are the way to meet a schematic requirement the ground doesn't
  offer, and they give the ladder a real second rung.

## Suggested order

1. Drop the gear hardness threshold now (small change on the branch); keep
   `requires` on recipes for parts that genuinely need it.
2. Build drills as entities with a hardness requirement so the sheet is read
   at the point of use. Decide the step factor at the same time.
3. Then alloys, as above, with their own ADR.

## Questions for the spoken session

- Does the step factor survive, and if so is it one global number or per
  property?
- Should grade keep scaling hardness, or move hardness entirely to alloying
  and treatment?
- Alloy mix rule: averages plus a family bonus/penalty, or something the
  player can read off the two sheets and predict?
- Can alloys be alloyed again (depth limit), and how many species can a
  world's roster grow to before the map, inspector and ladder check need
  rethinking?
- Does rung zero promise a gear-capable material, or is "your first ore is
  too soft, refine it or find another" a fine first lesson? (Moot if the gear
  gate goes.)
