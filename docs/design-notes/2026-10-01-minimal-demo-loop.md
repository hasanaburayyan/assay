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

## What the loop actually costs, measured (Maren, 2026-10-02)

Decision 2's test — "the whole demo loop can be played to completion with
`--plain`" — now has a number. Played end to end on the pinned friend seed
14247 (`sim-cli --plain`, `pause` + `tick`): spawn to an equipped pick is
**326 ticks, about 33 seconds at the relay's 10 ticks/s**, and the pick comes
out UNCERTAIN, which is the verdict the seed was pinned to show.

Where that time goes is lopsided, and it is worth knowing before anyone
optimises the wrong surface:

| stage | ticks | share |
|---|---|---|
| smelter refining 8 ore at 20 ticks each | 160 | **49%** |
| walking to a hand-lightable fuel and back | 36 | 11% |
| hand mining (two deposits) | 40 | 12% |
| `craft smelter` — the only hand craft in the demo | 20 | 6% |
| place, insert, take, `make`×3, assemble, equip | ~10 | 3% |

Three things follow. **The waiting in this demo is a building's, not the
player's**; the longest action a player's own hands perform is 20 ticks, two
seconds. **`MakePart` is instant** — it takes the material and adds the part
in the same tick (`step.rs`), so there is no part-crafting progress for any
host to show, and part sizes are a material cost, never a duration.
**The walk is structural, not incidental**: the spawn material's heat
tolerance usually exceeds the hand spark, so the first fire needs a second
species fetched from elsewhere. Worldgen guarantees one exists; the player is
not told which, which is ASSA-58.

### What a drill costs and what it buys (Maren, 2026-10-02)

The milestone is named "parts, picks, drills" and the pick is the half that
has been measured. Here is the other half, over 500 worlds, for a drill built
from the best starter species a world affords, at grade B
(`sim/tests/maren_drill_payback.rs`):

| hoppers | survives placement | unattended run before it stalls |
|---|---|---|
| 0 | 76.4% of worlds | 13 ticks (1.3 s) |
| 1 | 67.8% | 80 ticks (8.0 s) |
| 2 | 61.8% | 146 ticks (14.6 s) |
| 3 | 51.8% | 213 ticks (21.3 s) |
| 4 | 44.6% | 280 ticks (28.0 s) |

A one-hopper drill out-mines bare hands in **87.4%** of worlds (2.67 ticks per
unit against the hands' 4), and its parts cost **160 ticks of smelter time** —
the same 49% of the demo clock the table above shows refining already takes,
before the ore to feed it.

**Read it as a design rather than a tuning complaint, because that is what it
is.** Every hopper buys runtime and spends survival, about seven points of it,
and that trade is the drill's whole decision. What the numbers say is that a
drill is **not** a walk-away machine in the demo: at best it runs 28 seconds
and typically eight, so its output is gated by how often a player walks back,
never by its speed. That is the shape of the game before belts exist, and the
stall is already a named state rather than silence.

**No tuning change is ruled here, and the reason is worth recording so nobody
re-opens it on feel.** The obvious lever — the planted frame's own buffer —
costs no mass, so raising it would buy runtime for free and flatten the one
decision the drill has. A full drill is not starvation: 60 ore in eight
seconds is roughly four times what the whole demo loop consumes. What would
change my mind is a player who cannot tell a stalled drill from a broken one;
that is a message problem, not a capacity one.

### What fills the twenty minutes (Maren, 2026-10-03)

This note's own summary says friends "play for twenty minutes or so", and the
loop measured above is 326 ticks — 33 seconds. The other 19.5 minutes had never
been read off anything. Measured on the pinned seed, in the world a session
really builds — `sim_net::SESSION_CHUNKS`, 6x4 chunks, 96x64 tiles, 13 deposits
(`shared/assay/maren_twenty_minutes_session_world_2026-10-03.rs`, seed 14247).
**The first version of this section used `WorldConfig::default()`, which is 8x8
chunks: 64 chunks against 24, so every total in it was for a world no friend
will ever play. `first_pick.rs` warns about that exact trap in a comment and I
walked into it anyway. The figures below replace those.**

| what | number |
|---|---|
| ore in the world, all kinds | 11,632 units |
| hand-minable | 8,722 units |
| of that, inside a 20-tile walk | 2,143 units |
| ore nothing in that world can break | 2,910 units (25.0% by volume) |
| bare hands to clear every minable deposit | 20,244 ticks ≈ 33.7 min |
| bare hands on the ore within 20 tiles | 3,336 ticks ≈ 5.6 min |
| one smelter to refine all of it | 174,440 ticks ≈ 290.7 min |
| a pick · a one-hopper drill | 3 · 8 refined = 60 · 160 smelter ticks |

**What the demo asks for is tens of units, and the nearest ore is thousands.**
The whole loop — a smelter (5 ore), a pick (3 refined) and a one-hopper drill
(8 refined) — costs **16 units at grade C**, or about **100** if you insist on
grade A everywhere, because the ladder is 9 grade-C ore per grade-A unit.
Against that, 2,143 units sit inside a 20-tile walk and each single deposit
holds 687 to 1,184. So the twenty minutes are not gated by material, by
distance or by the clock — **they are gated by the number of things worth
building, which is a pick, a drill, and however many hoppers you dare.**

**One pacing fact that is real, though, and is not a scarcity.** Mining
*continuously* would strip the ore within a 20-tile walk in 5.6 minutes and the
entire world in 33.7, so a player who treats this like an idle game runs out of
nearby rock inside a session. Nothing in the demo asks for that — the loop needs
16 units — but it is the number to know before anyone adds a reason to mine in
bulk. Belts would make it binding; nothing today does.

**Which makes the assembly verdict the demo's content rather than one of its
features.** What a player does after the first pick is re-run that one
decision: a different species, a sorted grade, one more hopper, SAFE against
UNCERTAIN, and the occasional design that breaks on placement and hands half
its parts back. The UI work in flight is therefore aimed at the right surface,
and "more feedback while mining" is not what the next hour buys.

**Two levers nobody should pull on feel.** First, the smelter is only a
bottleneck while you own one, and a second costs five ore and 20 ticks by hand;
working that out is the first lesson a factory game has to teach, so it must
not be hinted and its rate must not be softened. Second, the grade ladder is
cheaper by hand than at the fire: nine grade-C ore become one grade-A refined
for four hand sorts (80 ticks) plus one 20-tick refine, where refining first
and resmelting costs **340 ticks of the one machine everything else queues
behind** — seventeen times the smelter work for the same ore. Hand crafting runs
while you walk or mine, so the sorting route is close to free. `resmelt` is the
recovery path for refined you already hold, not a rung on the ladder.

### Assaying is free while you mine (Maren, 2026-10-03)

The 326-tick loop above never assays, and reading `ASSAY_TICKS = 30` makes an
assay look like ten seconds of standing still — three per cent of the demo
spent on nothing. It is not. `Player` holds `mining`, `crafting` and
`assaying` as three independent fields, and no system clears one when another
starts. Measured rather than read
(`shared/assay/maren_assay_while_mining_2026-10-03.rs`, seed 14247): `Mine` and
`Assay` submitted on the same deposit in the same tick both survive, the assay
completes on schedule, and **seven ore arrive while it runs** — one per
four-tick cycle at grade C, exactly what mining alone would have yielded.
Mining and hand crafting coexist the same way. Three at once is not
demonstrated, only the two pairs; nothing in `step.rs` couples any of them.

**So the price of assaying is zero in the case that matters**, because the
thing you must stand on to assay is the thing you came to mine. That reframes
the UNCERTAIN verdict the part panel leads with: it is an invitation whose cost
is not time but *knowing it is happening*. Nothing on screen says an assay is
running (ASSA-95), so what limits the demo's conversion from "UNCERTAIN" to "go
and assay it" is visibility, not price. The concurrency is a property worth a
guard when that item lands, not an accident to tidy up: an `Assay` that quietly
cancelled your mining would turn a free action into a tax on the mechanic the
game is named after.

### Resolved: gears do not survive in the demo

The open question below asked whether gears survive as a part kind. They do
not, and the answer is stronger than "not a part kind": **nothing in the game
consumes a gear.** The part catalogue is head, handle, frame and hopper, all
made from refined; `ItemKind::Gear` appears only as a recipe *output* and in
tests. No recipe takes one, no part takes one, the client never names one.

That is not harmless, because a gear costs **2 refined** — the same as a
handle, two thirds of a pick, and 40 ticks of smelter time, which the table
above shows is the demo's scarcest resource. `recipes` advertises it anyway.

**Ruling: the gear recipe stays in the sim and stops being an unmarked
invitation.** Deleting it would throw away work the alloys note still wants
and would move the golden hash for nothing; hiding it would make absence the
cue again. The recipe table says plainly that nothing uses a gear — and
*without* "yet", because no accepted decision promises one, and ASSA-43 is
exactly what it costs to put a promise in a sentence that no decision backs.

## Open questions

Five of these were answered while the demo was built and the list did not say
so. **A spec that still asks a question the code has settled is a trap** — this
is the newest note, so a reader takes its questions as live and reopens a
decision ADR 0003 already made. Each is struck through below with the answer
and the line of code that holds it, re-read on `main` today rather than
recalled (Maren, 2026-10-02).

- ~~Which sheet properties beyond hardness, strength and density do parts read
  in the demo, if any (heat tolerance for a burner head, say)?~~ **None.**
  `PART_SPECS` (`assembly.rs`) reads exactly three: density → mass on every
  part, hardness → speed on the head alone, strength → durability on the head
  and budget on a frame. Heat tolerance, reactivity and conductivity are
  invisible to parts, which is why a burner head is a later idea and not a
  missing feature.
- ~~What fraction of parts come back on a break, and is it per part or a
  roll? Must be deterministic either way.~~ **Per part, a 50% roll**, plus one
  part that is always lost: the heaviest that is not the frame
  (`part_always_lost`, ADR 0003 A1). Determinism is handled by rolling once
  per part in part order **on every path, including the always-lost one**, so
  the rng stream advances the same on every peer. **Still a working default,
  not a board answer** — `BREAK_RETURN_PERCENT` says so in its own comment;
  the CEO set it to unblock and the board has not spoken. Changing it is one
  line.
- ~~Durability numbers: how many swings a grade B head of middling strength
  should last so a pick feels worth making but not permanent.~~ **120 swings**
  at a grade-B strength-50 head: pool = head size × effective strength ×
  `PICK_DURABILITY_PER_STRENGTH` (60, raised from 10 in ADR 0003 A2), drained
  `PICK_WEAR_PER_SWING` (20) per swing. The raise was forced by arithmetic,
  not feel: hands mine every deposit a pick can, so a pick buys only time, and
  at 20 swings it could not repay the 60 ticks of smelting its 3 refined cost.
- ~~Does the hopper's own material matter (density only, or capacity too)?~~
  **Density only.** Capacity is flat from the kind — `HOPPER_CAPACITY` 50 per
  hopper on top of the planted frame's buffer of 10 — so hopper species is one
  legible choice: make it light. Mass, not a slot count, is what stops you
  stacking hoppers.
- ~~The gear's hardness gate and the `requires` field on recipes: the
  discussion note argued requirements belong on the schematic; this note's
  assembly model makes gears an ordinary part. Decide whether gears survive
  as a part kind in the demo at all.~~ **Answered 2026-10-02 — see "Resolved:
  gears do not survive in the demo" above.** Note while checking this: the
  `requires` field is non-empty for the **gear recipe and nothing else** —
  the other four are `&[]`, and the smelter's heat gate is enforced in
  `step.rs`, not through `requires`. So the field has exactly one user and
  it is the unused recipe. Whoever retires gears retires `requires` with
  them; neither is load-bearing for anything else in the demo.
- ~~How the Godot client presents the part catalogue and the frame budget so
  a player can predict a break before placing (sim exposes mass and budget;
  the client decides how to show them).~~ **Built (ASSA-37), and the rule is
  that the client renders the verdict and never computes it**: a design row
  leads with SAFE / UNCERTAIN / WILL BREAK from the sim, shows mass against
  budget, and placement is never disabled — a player may place something that
  will break. While the sheet is rough both terms read as bands, which is why
  UNCERTAIN is the demo's advertisement for assaying and must not be dressed
  as danger. **What is still open is taste, not design**: whether that panel
  reads as a design or as a debug strip is Decision #38, with the board.
- ~~Godot export in CI: export templates, signing, and whether the client
  bundles a relay for the host or the host runs the Rust relay separately.~~
  **Settled by what shipped (ASSA-9):** CI exports Mac and Windows bundles,
  each zip carries `sim-cli`, `sim-relay` **and** the client, so **the host
  runs the Rust relay separately** and nothing is bundled into the client.
  Templates are anonymous downloads and signing is ad-hoc. The half that is
  genuinely open is not export at all — it is how a friend outside the host's
  machine reaches that relay, which is Decision #40, with the board.

## Suggested next steps

**All seven are built.** They became ASSA-3 through ASSA-9, one item per step,
all in board review; the live milestone is ASSA-2. The step that is done but
not *proven* is the last one: the artifacts exist and a human has opened the
window (Decision #34), but nobody outside this machine has played one, which
is what Decision #40 is for. Read the list below as the record of how the
demo was built, not as work waiting to start.

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
