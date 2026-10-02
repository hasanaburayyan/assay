#!/bin/bash
# DOES A CLIENT BUILT FROM DIFFERENT RULES ACTUALLY GET REFUSED? (ASSA-40)
#
# Marlow built the rules-identity handshake and said plainly that they could not
# run it: there is no Godot on their machine, so `protocol.gd`'s `rules_id()` and
# the refusal it produces were CI-verified only. The whole point of the work is a
# refusal that names both identities, and nobody had seen one. This produces one.
#
# HOW A MISMATCH IS MANUFACTURED. `sim::RULES_ID` is `env!("SIM_RULES_ID")`, which
# `build.rs` computes by hashing every `.rs` file under `sim/src`. So ANY edit to a
# sim source changes it -- a comment is enough, and a comment is the honest way to
# do it because it proves the identity tracks the source bytes rather than
# behaviour. The relay keeps the old id because it is not rebuilt.
#
# Scratch port, scratch saves. It never touches 7777 (the founders' world-42) or
# 7803 (the board's demo relay, Nerite's).
set -u

PORT="${PORT:-7811}"
SEED="${SEED:-777055}"
GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
MARKER=sim/src/_rules_identity_probe_marker.rs
OUT=/tmp/limpet-rules
rm -rf "$OUT"; mkdir -p "$OUT"
export R2TS_SAVES_DIR="$OUT/saves"
mkdir -p "$R2TS_SAVES_DIR"

cleanup() {
  rm -f "$MARKER"
  kill "${RELAY_PID:-0}" 2>/dev/null
}
trap cleanup EXIT

if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "FAIL  port $PORT is busy; pick another."; exit 1
fi

join() {  # $1 = label
  ( cd client && "$GODOT" --headless --path . --script res://tools/join_probe.gd \
      -- "localhost:$PORT" limpet ) > "$OUT/$1.log" 2>&1
  echo "  exit=$?"
  grep -iE "JOIN PROBE OK|refused|rules" "$OUT/$1.log" | head -4
}

echo "=== relay on $PORT, seed $SEED (rules as built now) ==="
nohup target/debug/sim-relay "$SEED" --port "$PORT" --fresh > "$OUT/relay.log" 2>&1 &
RELAY_PID=$!
sleep 4
kill -0 "$RELAY_PID" 2>/dev/null || { echo "FAIL relay died"; cat "$OUT/relay.log"; exit 1; }
grep -iE "rules" "$OUT/relay.log" | head -2

echo "=== 1. MATCHED client must JOIN ==="
join matched

echo "=== 2. now change a sim source byte, rebuild ONLY the client ==="
printf '// Touched by tools/rules_refusal_check.sh to move SIM_RULES_ID. Deleted on exit.\n' > "$MARKER"
make -C .. client-lib 2>&1 | tail -1

echo "=== 3. MISMATCHED client must be REFUSED, naming both ids ==="
join mismatched

echo "=== 4. put it back, rebuild, must JOIN again ==="
rm -f "$MARKER"
make -C .. client-lib 2>&1 | tail -1
join restored

echo "=== relay's own view ==="
tail -8 "$OUT/relay.log"
echo "=== DONE ==="
