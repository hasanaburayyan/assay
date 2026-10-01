# 0002. Deposit purity comes from a world core quality plus a seeded spread

- Status: Proposed
- Date: 2026-10-01
- Source: decision 13 of `docs/design-notes/2026-10-01-minimal-demo-loop.md`
  (board design session); answers the question left open by
  [0001](0001-generated-minerals-with-grades.md) point 5

## Context

ADR 0001 point 5 **withdrew** "purity rises with distance from spawn" and
left purity's source open; worldgen has since rolled it flat
(`rng.range(1, 101)`), with the two starter chunks rolling from
`STARTER_MIN_PURITY` up instead. A flat roll makes every world the same on
average, so there is no way to say "this planet is rich" — which the planned
galaxy layer needs, and which is the point of the name *Assay*. The sim must
stay deterministic and renderer-free, so whatever replaces the flat roll has
to be a pure function of the seed with no new state on `World`.

The alternative on the table was putting a per-world quality value on
`World` (or `WorldConfig`) now. That was rejected for this milestone: it
moves the saved layout, so it costs a `SAVE_VERSION` bump and a migration to
buy a knob nothing can yet set per planet.

## Decision

1. A deposit's purity is a **core quality** baseline plus a **seeded
   spread**, clamped to 1–100. The spread is symmetric, so core quality is
   the world's *mean* purity and not merely its floor.
2. Core quality is **one tuning constant shared by every world**
   (`tuning::CORE_QUALITY`, default 50) until the galaxy layer assigns it
   per planet. It is **not** stored on `World`, so this ADR moves neither
   `SAVE_VERSION` nor `PROTOCOL_VERSION`.
3. `worldgen::deposit_in_chunk` takes core quality as an **argument**, and
   every caller passes the constant. The galaxy layer's eventual per-planet
   value is then a change at the call site, not a rewrite of the roll.
4. The spread is `tuning::PURITY_SPREAD` (default 45) either side of the
   baseline: 5–95 at the default core quality, so all three grades still
   occur in one world.
5. The purity roll consumes **exactly one `rng.range` call** on every path.
   Worldgen is a pure function of `(seed, chunk)` and peers must walk the
   same stream; a branch consuming a different number of rolls would desync
   two clients that disagreed only about a tuning constant.
6. The starter chunks' `STARTER_MIN_PURITY` becomes a **floor applied after
   the roll**, not a separate range. The starter ladder needs a guarantee,
   not a distribution, and a floor holds it wherever core quality is set.
7. This rules out any spatial trend in purity, re-confirming 0001 point 5:
   purity does not vary with distance, biome or chunk position, only with
   the world's baseline and the seed.

Testable: raising the constant raises the mean deposit purity of a fixed
seed while deposits still vary (`raising_core_quality_raises_mean_purity_without_flattening_it`);
starter deposits stay at or above the floor even at core quality 1
(`starter_deposits_keep_their_floor_at_any_core_quality`); `deposit` rows in
the inspector show a spread of purities and grades in any one world.

## Consequences

- The **golden determinism hash changes** (`bb0c61da64d0f008` →
  `20b7b4fc57975213`): the roll draws different numbers from the same
  stream. `SAVE_VERSION` (10) and `PROTOCOL_VERSION` (4) are unchanged,
  because no saved or wire shape moves.
- Worlds become tunable in one number, and "a rich planet" becomes
  expressible before the galaxy layer exists.
- Clamping compresses the spread near either end: at core quality 95 a
  deposit can only roll 50–100. This is intended — a rich world has no poor
  ore — but it means the knob is not linear in the mean at the extremes, and
  a test asserting a *shifted distribution* rather than a *rising mean*
  would be wrong.
- `CLAUDE.md` and `GAME.md` still say purity's source is undecided and
  should be corrected when this ADR is accepted.
- Explicitly left open: whether core quality is itself generated per planet
  (the galaxy layer), whether players can read it, and whether grade
  thresholds (40/70) should move now that the attainable range is narrower
  than 1–100.

## Note on status

This is `Proposed`, not `Accepted`, because `docs/adr/README.md` reserves
acceptance for the founders. The decision it records was already made by the
board in decision 13 of the design note above; only the status line is
waiting.
