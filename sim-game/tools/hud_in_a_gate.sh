#!/bin/bash
# DOES THE HUD READ A REAL WORLD, IN A GATE? (ASSA-238)
#
#   GODOT=/path/to/godot tools/hud_in_a_gate.sh [seed] [ticks]
#
# `client/tools/hud_probe.gd` asks whether what the HUD would PUT ON SCREEN comes
# out of the world it joined and is true of it. It has existed since ASSA-116 and
# had ZERO references in `.github/workflows/build.yml`: every number it ever
# produced came off one Mac, by hand. A probe that only runs when somebody
# remembers it is not a guard, it is a tool.
#
# This script is the part that was missing: it stands up a relay, runs the probe
# against it, and cleans up, with every failure mode saying WHICH HALF broke.
# It lives here rather than inline in the workflow so the CI step and a developer
# run are the same code -- the mutation proof below was run locally first, and a
# step whose only copy is in YAML cannot be.
#
# THREE WAYS A CHILD RELAY FLAKES, which are this item's three boxes:
#
#  1. THE PORT. `--port 0` makes the KERNEL choose and the relay prints
#     `LISTENING <addr>:<port>`, which is parsed below. It cannot collide with a
#     parallel job, a leftover process or another developer's relay, because a
#     port the OS hands out is one nothing else holds -- that is stronger than
#     picking a number nobody is using today (7777 is the founders' world-42 and
#     7803 was the board's demo relay; `tools/rules_refusal_check.sh` picks 7811
#     and then has to ask `lsof`, which a runner may not even have).
#
#  2. THE ZOMBIE. The relay is killed from an EXIT trap, so cleanup runs whether
#     the probe passed, failed, or this script died in between -- and the trap
#     escalates: TERM, up to 5s, then KILL, and it SAYS if it had to force it.
#     A relay still holding a port after this script returns is itself a finding.
#
#  3. A RELAY THAT NEVER COMES UP. The wait below is bounded and ends with a
#     sentence naming THE RELAY, never a HUD assertion. The difference matters:
#     the probe's own fallback ("no welcome within 10s") reads like a client bug
#     and would send the next person to read `net_client.gd`. An early exit is
#     noticed too, with `kill -0`, instead of waiting out the full timeout for a
#     process that is already gone.
#
# HEADLESS IS HONEST HERE, and that is not true of every probe (ASSA-173).
# Everything `hud_probe.gd` reports is TEXT from `AssayHud` -- tile lines, sheet
# bands, design rows, event lines -- which is CONTENT-derived and identical with
# and without a window. A probe that measures anything off the VIEWPORT (a clip,
# a fold, a scroll share) reads 0 headless and must not be wired up this way.
#
# THE VERDICT IS THE MARKER, NEVER THE EXIT CODE: Godot exits 0 on a parse error,
# on a failed script and on this probe's own FAIL. So `HUD PROBE OK`, which the
# probe prints last and only on success, is the thing grepped -- out of a FILE,
# because the exit status after a pipe is the pipe's.
#
# Exit codes follow the art checks: 0 green, 1 a real finding, 2 NO VERDICT
# (something it needs is not where it expects), which fails a job rather than
# passing quietly.
set -u

cd "$(dirname "$0")/.." || exit 2            # sim-game

SEED="${1:-14247}"
TICKS="${2:-25}"
NAME="${NAME:-ci-hud}"
GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
RELAY="${RELAY:-target/release/sim-relay}"
# Generous on purpose: this is the ceiling for "the relay is never coming up", not
# a performance bar. A cold debug binary on a loaded box has taken seconds; 30
# means a timeout is a real failure rather than a slow runner.
RELAY_TIMEOUT="${RELAY_TIMEOUT:-30}"

if [ ! -x "$GODOT" ]; then
  echo "NO VERDICT: no Godot at $GODOT (set GODOT=)"; exit 2
fi
if [ ! -x "$RELAY" ]; then
  echo "NO VERDICT: no relay binary at $RELAY (cargo build -p sim-relay --release)"; exit 2
fi
if [ ! -f client/tools/hud_probe.gd ]; then
  echo "NO VERDICT: client/tools/hud_probe.gd is not where this script expects it"; exit 2
fi

OUT="$(mktemp -d "${TMPDIR:-/tmp}/hud-in-a-gate.XXXXXX")" || exit 2
# ITS OWN SAVES DIRECTORY, because the relay autosaves every 20 ticks and maps
# accounts into `world-<seed>.accounts.json`. Run straight out of `target/`, a
# relay writes those beside the executable; this keeps a gate from leaving files
# in a tree whose later steps diff themselves, and makes every run see player 0.
export R2TS_SAVES_DIR="$OUT/saves"
mkdir -p "$R2TS_SAVES_DIR"

RELAY_PID=""
cleanup() {
  if [ -n "$RELAY_PID" ] && kill -0 "$RELAY_PID" 2>/dev/null; then
    kill -TERM "$RELAY_PID" 2>/dev/null
    for _ in $(seq 1 50); do
      kill -0 "$RELAY_PID" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$RELAY_PID" 2>/dev/null; then
      echo "  cleanup: relay $RELAY_PID ignored TERM for 5s, sending KILL"
      kill -KILL "$RELAY_PID" 2>/dev/null
      sleep 0.2
    fi
  fi
  if [ -n "$RELAY_PID" ] && kill -0 "$RELAY_PID" 2>/dev/null; then
    echo "FAIL  relay $RELAY_PID survived TERM and KILL; it is still holding its port"
  fi
  rm -rf "$OUT"
}
trap cleanup EXIT

echo "=== relay: seed $SEED, kernel-assigned port, 127.0.0.1 only ==="
"$RELAY" "$SEED" --port 0 --bind 127.0.0.1 --fresh > "$OUT/relay.log" 2>&1 &
RELAY_PID=$!
# DISOWNED SO THE SHELL DOES NOT ANNOUNCE THE KILL. Without this, bash prints
# `Terminated: 15 "$RELAY" ...` when the trap reaps it -- AFTER the verdict line,
# so a green run ends on something that reads like a crash. `kill -0` and `kill`
# work on the pid either way; only the job-table entry goes.
disown "$RELAY_PID" 2>/dev/null

PORT=""
WAITED=0
while [ "$WAITED" -lt "$((RELAY_TIMEOUT * 10))" ]; do
  PORT="$(sed -n 's/^LISTENING 127\.0\.0\.1://p' "$OUT/relay.log" | head -1)"
  [ -n "$PORT" ] && break
  if ! kill -0 "$RELAY_PID" 2>/dev/null; then
    echo "FAIL  THE RELAY EXITED before it listened, so nothing here is about the HUD."
    echo "      $RELAY $SEED --port 0 --bind 127.0.0.1 --fresh"
    sed -e 's/^/      /' "$OUT/relay.log"
    exit 1
  fi
  sleep 0.1
  WAITED=$((WAITED + 1))
done

if [ -z "$PORT" ]; then
  echo "FAIL  THE RELAY NEVER LISTENED within ${RELAY_TIMEOUT}s, so nothing here is about the HUD."
  echo "      It is alive (pid $RELAY_PID) and has not printed 'LISTENING <addr>:<port>'."
  sed -e 's/^/      /' "$OUT/relay.log"
  exit 1
fi
echo "  listening on 127.0.0.1:$PORT after $((WAITED / 10)).$((WAITED % 10))s (pid $RELAY_PID)"

echo "=== probe: hud_probe.gd, $TICKS bundles, as $NAME ==="
STARTED="$SECONDS"
(cd client && "$GODOT" --headless --path . --script res://tools/hud_probe.gd \
    -- "127.0.0.1:$PORT" "$NAME" "$TICKS") > "$OUT/hud.log" 2>&1
GODOT_EXIT="$?"

# The marker, out of the file. Not the exit code, and not through a pipe.
if ! grep -q '^HUD PROBE OK' "$OUT/hud.log"; then
  echo "FAIL  the probe did not print HUD PROBE OK (godot exited $GODOT_EXIT, which means nothing)."
  echo "--- hud_probe.gd ---"
  sed -e 's/^/  /' "$OUT/hud.log"
  # THE RELAY'S VIEW IS HALF THE EVIDENCE: it logs the join, every command it
  # ordered and the part, so "refused" and "never arrived" are told apart here.
  echo "--- the relay's side of it ---"
  sed -e 's/^/  /' "$OUT/relay.log"
  exit 1
fi

sed -e 's/^/  /' "$OUT/hud.log"
echo "HUD IN A GATE OK · seed $SEED · $TICKS bundles · port $PORT · $((SECONDS - STARTED))s in the probe"
exit 0
