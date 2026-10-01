# The minimal co-op demo: parts, picks, drills and a Godot build (2026-10-01)

Status: decision record from a spoken session. Sets the target for the next
stretch of work: a small co-op demo that three or four friends can download
and play without a terminal. Follows `2026-10-01-hardness-gears-and-alloys.md`
(a discussion note) and the ADR 0001 cut-over. Where this note and the
discussion notes or `sim-game/design/properties.md` disagree, this note wins.

## Summary

The next milestone is a minimal multiplayer demo, delivered as a Godot client
built by CI for Mac and Windows, that friends join over the existing relay
and play for twenty minutes or so. Its loop is: mine slowly by hand, smelt and
sort, then assemble a pick and a drill from parts whose materials set speed,
capacity, durability and mass, with placement as the moment a design either
works or breaks. The modular assembly system is built generally in the sim
from the start (any parts, not fixed recipes), tools are tiny machines in the
same system, and purity gains a tunable "core quality" baseline in place of
the withdrawn distance rule.

## Decisions

1. **The next milestone is a downloadable co-op demo, not more inspector
   features.** The inspector stays the reference client and test harness,
   but it is not what friends receive. Test: a friend with no terminal can
   download a build, enter a host address and play.
2. **The demo client is the first Godot build.** It is a lockstep peer of the
   relay exactly like `sim-cli` is today: it reads snapshots and events and
   submits commands. Every system below must be fully playable through
   `sim-cli` before Godot draws it, per the two principles in `CLAUDE.md`.
   Test: the whole demo loop can be played to completion with `--plain`.
3. **The demo is multiplayer over the existing relay, any player count.**
   Reconnect is not part of the demo; a dropped client restarts to rejoin.
   Test: three or more Godot clients and the relay keep matching hashes
   through a full demo session.
4. **CI ships the Godot client for Mac and Windows.** The GitHub Actions
   workflow exports the Godot project for both platforms alongside the
   existing `sim-cli` and relay bundles. This is part of the definition of
   done for the demo. Test: a push to `main` produces downloadable Mac and
   Windows Godot artifacts from one run.
5. **Machines are assembled from parts in the sim from day one.** A machine is
   a bag of parts; each part has a kind, the slot it fills, its own material
   (species and grade), and a rule for how it contributes to the machine's
   stats. There are no fixed "plain drill" and "hopper drill" recipes. The
   demo ships a small part catalogue, not a small assembly model. Test: an
   assembly command accepts any list of parts that fit the frame's slots,
   and adding a second hopper changes capacity without a new recipe.
6. **Tools are tiny machines.** A pick is a head on a handle, where the
   handle is the frame; a drill is a head on a frame with optional hoppers.
   Tools and placed machines share one assembly system, differing by frame
   kind (held or planted). Test: pick and drill are built by the same
   command path and their stats come from the same per-part rules.
7. **The drill is a throughput upgrade, not a hardness unlock.** For the
   demo, a drill mines the same deposits hands can, only faster; the step
   factor and hardness ladder beyond rung zero stay parked. Test: a drill on
   a deposit with hardness above the hand limit does nothing.
8. **Head hardness sets mining speed, for picks and drills alike.** Speed
   reads the head material's effective hardness (grade-scaled), so a sorted
   grade A head is visibly faster than a grade C head of the same species.
   Test: same species, higher grade head, more ore per tick.
9. **The basic drill has a tiny internal buffer and stalls when full.**
   Hopper parts add capacity. Players take ore from the drill as from the
   smelter today. Test: a drill with no hopper stops at its buffer cap and
   emits an event; one hopper raises the cap.
10. **Stacking parts costs mass; frames have a strength budget.** Each part's
    mass comes from its material's density; a frame's budget comes from its
    material's strength. Power is deferred and will be a second budget later.
    Test: two drills identical except for a denser head have different total
    mass; a frame of a stronger species carries more.
11. **Anything can be assembled; placement is the test.** The sim never
    refuses an assembly for being overweight. On placement (or first use, for
    a held tool), if total mass exceeds the frame's budget the machine
    breaks immediately, emits an event, and returns a reduced set of its
    parts to the player. Test: overweight design placed → no building, a
    break event, and fewer parts back than went in; a design within budget
    places and runs.
12. **Hand tools wear out; placed machines do not, for now.** A pick has a
    durability pool drained per swing, derived from the head material's
    strength, and breaks at zero. Drill wear is parked for later. Test: a
    pick's remaining durability drops each mining cycle and the player
    returns to bare hands when it reaches zero; a drill's state has no wear.
13. **Purity is a world "core quality" constant plus a seeded random
    spread.** Core quality is a single tuning constant shared by all worlds
    until the galaxy layer assigns it per planet. Raising it shifts the
    whole world toward higher purity without removing variance. This
    replaces the plain roll noted in ADR 0001. Test: raising the constant
    raises the mean deposit purity of a fixed seed while deposits still vary.

## Open questions

- Which sheet properties beyond hardness, strength and density do parts read
  in the demo, if any (heat tolerance for a burner head, say)?
- What fraction of parts come back on a break, and is it per part or a
  roll? Must be deterministic either way.
- Durability numbers: how many swings a grade B head of middling strength
  should last so a pick feels worth making but not permanent.
- Does the hopper's own material matter (density only, or capacity too)?
- The gear's hardness gate and the `requires` field on recipes: the
  discussion note argued requirements belong on the schematic; this note's
  assembly model makes gears an ordinary part. Decide whether gears survive
  as a part kind in the demo at all.
- How the Godot client presents the part catalogue and the frame budget so
  a player can predict a break before placing (sim exposes mass and budget;
  the client decides how to show them).
- Godot export in CI: export templates, signing, and whether the client
  bundles a relay for the host or the host runs the Rust relay separately.

## Suggested next steps

1. Fold decision 13 into worldgen: add a core-quality tuning constant to the
   purity roll, update ADR 0001 (or write ADR 0002) and the golden hash.
2. Design the assembly data model in the sim: part kinds, slots, materials,
   contribution rules, mass and frame budget, with unit tests and no fixed
   recipes. Write it as an ADR before coding.
3. Add assemble, equip and place-assembly commands; break-on-placement with
   partial return and an event; `sim-cli` commands and an inspector panel for
   assemblies and events.
4. Build the pick (head plus handle, hardness speed, strength durability) and
   the drill (head plus frame plus hoppers, buffer and stall) on that model;
   extend `first_plate.rs` into a full demo play-through test.
5. Bump save and protocol versions, update the determinism hash, verify a
   relay session with three `sim-cli` peers.
6. Start the Godot client as a relay peer: join, snapshot, map, movement,
   then the part menu and placement, reading everything from the sim.
7. Add Godot Mac and Windows exports to `.github/workflows/build.yml` and
   hand the artifacts to friends.
