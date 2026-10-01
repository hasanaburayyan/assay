# Architecture decision records

An ADR is a short, numbered file that records one decision the founders have
made about Assay: what was decided, why, and what it rules out. ADRs exist so
agents and new contributors can build against settled decisions without
re-reading transcripts or relitigating in chat.

## How they relate to other documents

- `docs/design-notes/` are the raw output of spoken design sessions. They
  capture decisions, open questions and next steps as they were said.
- `docs/adr/` distils the decisions from those notes (and from code review,
  planning, or anywhere else) into one record per decision. A design note
  may spawn zero, one or several ADRs.
- `sim-game/design/*.md` are proposals for discussion. They are never
  authoritative on their own; a proposal becomes binding only when an ADR
  accepts it.
- `CLAUDE.md` and `sim-game/GAME.md` summarise the current state. When they
  and an accepted ADR disagree, the ADR wins and the summary should be fixed.

## Rules

- One decision per file. Number sequentially: `NNNN-short-slug.md`.
- Status is one of `Proposed`, `Accepted`, `Superseded by NNNN`,
  `Withdrawn`. Only the founders move an ADR to `Accepted`.
- Never edit the decision text of an accepted ADR. To change a decision,
  write a new ADR that supersedes it and update the old one's status line.
- Each decision should be testable: say what a test or inspector command
  would show if it holds.
- Keep it under a page. Link the design note or proposal it came from.
- Agents implementing a feature must read the ADRs in the index below that
  touch it, and must not contradict an accepted ADR without flagging it.

## Index

| ADR | Status | Title |
|---|---|---|
| [0001](0001-generated-minerals-with-grades.md) | Accepted | Generated mineral species with purity grades |
| [0002](0002-purity-from-world-core-quality.md) | Proposed | Deposit purity comes from a world core quality plus a seeded spread |
