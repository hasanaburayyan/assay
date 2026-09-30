# Starting zone

Status: **Open**. A proposal for how the area around spawn is generated so
every new world has a climbable progression. Nothing here is built. Sections
use the same markers as `GAME.md`.

## Assumptions

These are the premises the rest of the document builds on.

- **Minerals are procedurally generated.** There is no fixed list; the set of
  possible minerals is effectively unbounded. Each mineral is a set of quality
  values; the proposed list is in `properties.md`.
- **Qualities decide what it takes to use a mineral**, in three steps:
  1. **Extract:** mining it needs a tool that can beat its hardness.
  2. **Process:** refining it needs a machine that can take the heat it
     requires.
  3. **Use:** its qualities decide which parts it is good for. A mineral that
     makes a great drill head may make a poor battery.
- **At least one resource near spawn is hand-gatherable:** the player can
  get it with no tools or machines.

## The ladder

The starting zone is a ladder of minerals. Each rung is a mineral the player
can extract, process and use with parts made from rungs below it. Using that
mineral then produces the parts that open the next rung.

| Rung | What it needs | What it gives |
|---|---|---|
| 0 | Nothing. Gathered by hand. | Materials for the first tools and machines |
| 1 | Parts made from rung 0 | Parts that meet at least one new requirement |
| 2 … N | Parts made from lower rungs | The same, one step further |

Rules for a good ladder:

- **Each rung must need something new.** Climbing should need a better tool,
  a hotter machine, or another new capability, not just more of the same
  material. Otherwise the ladder is flat.
- **The requirements should take turns.** One rung is gated by hardness, the
  next by heat, and so on. The first prototype went drill, then frame, then
  engine, three times over, and this felt right.
- **The next goal should be visible.** Each rung should have at least one
  mineral nearby that the player can see but can't use yet, and can tell
  why. That target is what pulls the player forward.
- **There should be more than one route where possible.** The guarantee is a
  minimum. Extra minerals that give alternative or partial routes make the
  zone feel explored rather than scripted.

## Rung 0: hand-gatherable

**Open:** what "hand-gatherable" means in play. Candidates:

- Loose surface material (rubble, pebbles, deadfall) picked up by walking
  over it or pressing a key.
- A very soft deposit that can be mined without a tool, slowly.
- Salvage from the player's landing site or ship.

Whatever it is, it must never run out for good. If a player can spend all of
rung 0 on the wrong things, the world is soft-locked. It should be either
renewable or plentiful enough that this can't happen in practice.

**Rung 0 must include a fuel that can be lit by hand:** a mineral whose
ignition temperature is below the hand spark temperature (see Reactivity in
`properties.md`). Without it the first furnace can never be lit. It is the
generated replacement for coal, and the same never-run-out rule applies.

## Generation guarantee

World generation has to prove the ladder is climbable, not just hope it is.
Proposed approach:

1. Place rung 0 near spawn, including a hand-lit fuel.
2. Generate candidate minerals and deposits for the starting zone.
3. **Run a reachability check.** Start with the capabilities rung 0 gives.
   Repeatedly add every mineral whose extract and process requirements are
   met, and add the capabilities its best parts would give. Stop when
   nothing new is added.
4. If fewer than N rungs are reachable, fix the zone. Either reroll it, or
   place a **keystone** mineral: one generated to meet exactly the missing
   requirement. The first prototype used keystones, with each ring
   guaranteed one mineral good for drills, one for frames and one for
   engines.

Notes for `sim`:

- The check runs at world generation, so it must follow the `sim` rules:
  seeded `Rng` only, stable iteration order, integer math.
- "Capabilities" can start simple: the best achievable value for each
  requirement (for example, max hardness you can mine and max heat you can
  process). If parts limit each other, the check must take that into
  account. For example, if a frame caps which drills it can carry, a great
  drill mineral is useless until a matching frame mineral is also reachable.
- The check should use part values with a safety margin below their best
  possible roll, so the guarantee holds even with average crafting results.

## Parameters

Placeholders to tune in playtests.

| Parameter | Starting guess | Notes |
|---|---|---|
| Starting zone size | Spawn chunk + the 8 around it | See the deposit-density question below |
| Guaranteed rungs (N) | 4–6 | After N, normal generation takes over |
| Deposits per rung | At least 1 guaranteed, 1–2 optional | Optional ones give alternative routes |
| Ore per guaranteed deposit | Enough for every needed part, ×2 | Margin for mistakes and co-op |
| Visible-but-blocked minerals | At least 1 per rung | The "next goal" |

## Open questions

- **Purity vs qualities.** `GAME.md` gives ore a single purity (1–100) that
  rises with distance. Does purity become the total "budget" a mineral's
  qualities are drawn from, with its kind or profile deciding the split? That
  keeps "better ore further out" and adds "different ore for different
  parts".
- **Deposit density.** Today's rule is at most one deposit per chunk. A 4–6
  rung ladder with alternatives probably needs more than 9 deposits in the
  starting zone. Does the starting zone get its own density rule?
- **Where the ladder ends.** Is the guaranteed ladder only in the starting
  zone, or does every region or planet get one relative to where the player
  arrives with?
- **Co-op.** Several players share one starting zone. Do deposit amounts
  scale with player count, or is sharing the scarce early rungs part of the
  game?
- **Which requirements exist.** Hardness (extract) and heat (process) are the
  clear first two. Candidates for later: density or weight (what a frame can
  carry), conductivity (power parts), reactivity (needs special handling).
- **How much the player is told.** Should a mineral's exact requirements show
  when the player looks at it, or only after they sample it once? Showing
  them makes planning easy; hiding them makes finding out part of the game.
