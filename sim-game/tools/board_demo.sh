#!/bin/bash
# THE BOARD'S TWO MINUTES, SET UP SO THEY SPEND NONE OF IT ON SETUP.
#
# Decision #38 asks the board to open the Godot client and judge whether the
# PART MENU reads as a design or as a debug string. The menu lists the designs
# the JOINED PLAYER owns, so on a fresh world it honestly says "nothing built
# yet" -- which would spend their two minutes on a blank. This script leaves a
# world standing where the bench is already full, on the player their own client
# will land on.
#
# WHY THE ACCOUNT NAME IS `hasanaburayyan` AND NOT `board`: the client prefills
# its name box from `OS.get_environment("USER")` (`main.gd:107`), so that is the
# account their app will send unless they retype it. Measured, not assumed
# (`tools/rejoin_check.sh`): a returning account lands on its own PlayerId with
# its state intact, and ANY OTHER NAME gets a fresh player at spawn with an
# empty bench. So the probe plays under the name their client will use.
#
# AND THE PROBE MUST DISCONNECT BEFORE THEY JOIN. The relay refuses an account
# that is already online ("dev:<name> is already connected"), so a probe left
# holding the account would turn their two minutes into a refusal. The session
# probe exits on its own; this script waits for it.
#
# NOT PORT 7777: that port has been serving `sim-relay 42` for 30 hours -- the
# founders' ongoing test world. This probe mines, smelts and plants a machine
# that breaks apart, and none of that belongs in their world.
set -u

PORT="${PORT:-7801}"
SEED="${SEED:-777042}"
ACCOUNT="${ACCOUNT:-hasanaburayyan}"
TICKS="${TICKS:-400}"
GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
# OVERRIDABLE, AND IT HAS TO BE. This was a hardcoded `/tmp/limpet-demo` followed by `rm -rf`, which
# is fine exactly once: the moment a bench built by this script is LIVE and someone runs it again to
# try a second seed, the second run deletes the saves directory out from under the first run's
# relay -- while the board is being asked to open it (Decision #38). The port guard below stops two
# relays sharing a port; nothing stopped two runs sharing a directory. I nearly did it to Nerite's
# 7803 bench; a different PORT needs a different OUT, so pass both.
OUT="${OUT:-/tmp/limpet-demo}"
if [ -e "$OUT" ] && [ "${OUT_FORCE:-0}" != "1" ] && pgrep -f "sim-relay .* --port" >/dev/null 2>&1 \
    && lsof +D "$OUT" >/dev/null 2>&1; then
  echo "FAIL  something is still holding files in $OUT -- most likely a relay this script"
  echo "      started earlier and that someone is using. Pass OUT=<dir> for a separate run,"
  echo "      or OUT_FORCE=1 if you are certain."
  exit 1
fi
rm -rf "$OUT"; mkdir -p "$OUT"
export R2TS_SAVES_DIR="$OUT/saves"
mkdir -p "$R2TS_SAVES_DIR"

if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "FAIL  port $PORT is already serving something; pick another."
  exit 1
fi

echo "=== relay: seed $SEED on port $PORT, saves in $R2TS_SAVES_DIR ==="
nohup target/debug/sim-relay "$SEED" --port "$PORT" --fresh \
  > "$OUT/relay.log" 2>&1 &
RELAY_PID=$!
echo "relay pid $RELAY_PID"
sleep 4
if ! kill -0 "$RELAY_PID" 2>/dev/null; then
  echo "FAIL  relay died on start:"; cat "$OUT/relay.log"; exit 1
fi

# --- The probe plays the whole demo loop under the board's own account. -------
# `demo`, NOT `session`: a session SPENDS the designs (equip + plant) and leaves the player mining,
# so a world built that way is empty by the time anyone opens it. Measured: rejoined 5,600 ticks
# later to `tool: null`, no assemblies and 856 ore. `demo` stops the player and leaves the drill on
# the bench, which is the state that survives the relay's clock.
echo "=== demo probe as '$ACCOUNT' (up to $TICKS ticks) ==="
( cd client && "$GODOT" --headless --path . \
    --script res://tools/lockstep_probe.gd \
    -- "localhost:$PORT" "$ACCOUNT" "$TICKS" demo ) \
  > "$OUT/session.log" 2>&1
echo "probe exit=$?"
grep -E "session:|demo:|LOCKSTEP PROBE OK|FAIL" "$OUT/session.log" | tail -30

# --- The account must now be OFFLINE, or the board gets refused. -------------
sleep 3
echo "=== relay tail ==="
tail -6 "$OUT/relay.log"
echo "=== accounts ==="
cat "$R2TS_SAVES_DIR/world-$SEED.accounts.json" 2>/dev/null
echo "=== RELAY STILL UP: pid $RELAY_PID on port $PORT ==="
lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && echo "listening OK" || echo "NOT LISTENING"

# --- WHICH CLIENT CAN JOIN THIS BENCH. ---------------------------------------
# A bench outlives the commit that built it, and a client from any other commit
# is REFUSED: `RULES_ID` is an FNV over every `.rs` under `sim/src`, so a
# one-word change to a sim sentence moves it (ASSA-40). That is correct -- the
# alternative is two peers quietly playing different games -- but it means
# "download a recent build" is never the instruction. It has to be THIS commit.
#
# This bit the live #38 bench. It was rebuilt at 15:30 UTC from a commit that
# five merges then overtook, and its own log shows it refusing a client an hour
# later. The relay knew exactly what it wanted; nobody was writing it down, so
# the answer lived in a shared doc that went stale instead.
#
# So the bench carries its own joining card now, and the rules id is read out of
# the RELAY'S OWN FIRST LINE rather than computed here -- a second opinion about
# which rules this process is running is exactly the thing that would drift.
RULES_LINE=$(grep -m1 '^Rules ' "$OUT/relay.log" 2>/dev/null || echo "Rules UNKNOWN")
REPO=$(dirname "$0")/..
COMMIT=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo UNKNOWN)
DIRTY=""
git -C "$REPO" diff --quiet 2>/dev/null || DIRTY=" (built with uncommitted changes)"
{
  echo "# How to join this bench"
  echo
  echo "Built $(date -u '+%Y-%m-%d %H:%M UTC') · seed $SEED · port $PORT · account \`$ACCOUNT\`"
  echo
  echo "- Host box: \`localhost:$PORT\` on this machine; the relay's start line lists the LAN address."
  echo "- Name box: leave it alone. It prefills from \$USER, and \`$ACCOUNT\` owns the bench. Any"
  echo "  other name lands you on a fresh player with an empty one."
  echo
  echo "## The client must come from THIS commit"
  echo
  echo "    commit  $COMMIT$DIRTY"
  echo "    $RULES_LINE"
  echo
  echo "Not \"a recent build\" -- the same commit. A mismatched client is refused on join, and the"
  echo "refusal names the rules id it needs. Take \`assay-macos\` / \`assay-windows\` from the CI run"
  echo "for that commit, or build locally from it."
  echo
  echo "If this file is older than the bench you are looking at, the bench was restarted without it"
  echo "and nothing here is trustworthy."
} > "$OUT/JOIN.md"
echo "=== JOIN CARD: $OUT/JOIN.md ==="
echo "    commit  $COMMIT$DIRTY"
echo "    $RULES_LINE"
# Only when there IS an `origin/main` to compare against: a failed lookup must
# not become a warning, or this reports a stale bench on any clone that has not
# fetched.
if [ "$COMMIT" != "UNKNOWN" ] \
   && git -C "$REPO" rev-parse --verify --quiet origin/main >/dev/null 2>&1 \
   && ! git -C "$REPO" merge-base --is-ancestor origin/main "$COMMIT" 2>/dev/null; then
  echo "    NOTE: this commit is behind origin/main, so anyone downloading the NEWEST CI"
  echo "          artifact will be refused by this bench. Rebuild from current main if the"
  echo "          people joining will be using CI builds."
fi
echo "=== DONE ==="
