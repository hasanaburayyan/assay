# Hardness, gear thresholds, and alloys (2026-10-01)

Status: discussion note, not a decision record. Written from a typed
conversation after the ADR 0001 cut-over landed on `minerals-cutover`, to
seed a spoken session. Nothing here is decided; the proposals in
`sim-game/design/properties.md` remain the reference for part rules.

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
