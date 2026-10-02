#!/bin/bash
# DOES REJOINING UNDER AN EXISTING ACCOUNT LAND ON THAT PLAYER?
#
# Maren's condition on the board demo (ASSA-7, 2026-10-02): the setup asks the
# board to join a relay under an account a probe already played, and find the
# bench that probe filled. The relay's code says a returning account gets its
# known PlayerId (`sim-relay/src/main.rs:256`), but the demo breaks in two ways
# that reading cannot rule out, so this runs it:
#
#   1. REJOIN IDENTITY. Second connection under the same account must get the
#      SAME PlayerId and the inventory that player was left holding. If a
#      rejoin instead took a fresh slot, the board would open an empty bench.
#   2. THE ALREADY-CONNECTED REFUSAL. The same file refuses an account that is
#      currently online. If the probe holds the account open, the board is
#      REFUSED rather than welcomed -- so the probe must disconnect first, and
#      this proves which it is rather than assuming.
#
# Nothing here touches the founders' world: scratch port, scratch R2TS_SAVES_DIR,
# its own seed. Run from sim-game/.
set -u

PORT="${PORT:-7891}"
SEED="${SEED:-777010}"
ACCOUNT="${ACCOUNT:-board}"
OUT=/tmp/limpet-rejoin
rm -rf "$OUT"; mkdir -p "$OUT"
export R2TS_SAVES_DIR="$OUT/saves"
mkdir -p "$R2TS_SAVES_DIR"

RELAY=target/debug/sim-relay
CLI=target/debug/sim-cli

"$RELAY" "$SEED" --port "$PORT" --fresh > "$OUT/relay.log" 2>&1 &
RELAY_PID=$!
trap 'kill $RELAY_PID 2>/dev/null' EXIT
sleep 3

say() { printf '%s\n' "$@"; }

# --- 1. First session: the account walks somewhere distinctive. --------------
# Position is world state owned by a PlayerId, so "am I still standing where I
# left off" is the cleanest proof that the slot came back -- it needs no deposit
# under the player's feet the way `mine` would.
( say "who" "goto 60 40"; sleep 12; say "who" "quit" ) \
  | "$CLI" --connect "localhost:$PORT" --name "$ACCOUNT" > "$OUT/first.log" 2>&1
sleep 2

# --- 2. Rejoin after a clean disconnect: same account, same name. ------------
( say "who" "inv"; sleep 3; say "quit" ) \
  | "$CLI" --connect "localhost:$PORT" --name "$ACCOUNT" > "$OUT/rejoin.log" 2>&1
sleep 2

# --- 3. A DIFFERENT account must NOT land on that player. -------------------
( say "who"; sleep 3; say "quit" ) \
  | "$CLI" --connect "localhost:$PORT" --name "someone-else" > "$OUT/other.log" 2>&1
sleep 2

# --- 4. Two at once under one account: the second must be REFUSED. ----------
# The holder keeps the account online by holding its own stdin open, which is
# the state the demo would really be in if the probe never disconnected.
( say "who"; sleep 14; say "quit" ) \
  | "$CLI" --connect "localhost:$PORT" --name "$ACCOUNT" > "$OUT/holder.log" 2>&1 &
HOLD=$!
sleep 5
( say "who"; sleep 3; say "quit" ) \
  | "$CLI" --connect "localhost:$PORT" --name "$ACCOUNT" > "$OUT/double.log" 2>&1
wait $HOLD 2>/dev/null
sleep 1

kill $RELAY_PID 2>/dev/null
sleep 1
echo "=== accounts.json ==="
cat "$R2TS_SAVES_DIR/world-$SEED.accounts.json" 2>/dev/null
echo "=== DONE ==="
