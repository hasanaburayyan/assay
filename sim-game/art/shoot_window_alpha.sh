#!/bin/bash
# TAKE THE SHOT SET `art/window_alpha.py` READS (ASSA-181). Run from `sim-game/`.
#
#   art/shoot_window_alpha.sh control [SEED] [TICKS] [HOPPERS]   # the known-alpha control
#   art/shoot_window_alpha.sh SHEET   [SEED] [TICKS] [HOPPERS]   # one real sheet's alpha field
#
#   art/shoot_window_alpha.sh control                # -> /tmp/wa181/control, prints a verdict
#   art/shoot_window_alpha.sh ore 777042 800 4       # -> /tmp/wa181/ore, bg.png + black.png
#
# WHY A SCRIPT AND NOT A PARAGRAPH. Each run swaps a sheet in `client/assets/sprites/`, which is
# TRACKED art inside the Godot project, and a window shot needs a GUI Godot (~90 s each). Doing
# that by hand is how you end up measuring one sheet and shipping another: on 2026-10-02 a stale
# `--pack` silently reverted a ruled grade-A glint from a cache I did not know I had. So the swap,
# the restore and the PROOF of the restore live in one file, and the proof is `git status` rather
# than my word.
#
# THREE SHOTS FOR THE CONTROL, TWO FOR A FIELD, and nothing else changes between them:
#   bg      the sheet BLANKED (alpha 0, same size)          -> the background, exactly
#   black   the sheet's RGB zeroed, alpha kept              -> K = bg*(1-a)
#   shot    the control's authored RGB, same alpha          -> tests the unblended colour too
# The real sheets go back at the end even if a shot fails (`trap`), because a tree left holding a
# magenta player is worse than no measurement.
set -e
MODE="${1:?usage: art/shoot_window_alpha.sh control|SHEETNAME [seed] [ticks] [hoppers]}"
SEED="${2:-777042}"
TICKS="${3:-800}"
HOPPERS="${4:-4}"

CL="$(cd "$(dirname "$0")/../client" && pwd)"
REPO="$(cd "$CL/../.." && pwd)"
GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
OUT="${OUT:-/tmp/wa181}"
SPR="$CL/assets/sprites"

# WHICH SHEET IS SWAPPED. The control borrows the PLAYER sheet, and that is deliberate: the
# player is what burned three of the four masks that made this item (its idle frame is not
# identical across two Godot runs), it is the one sheet drawn at `Color.WHITE`
# (`scene_view.gd:519`) so an authored RGB comes back unmultiplied, and it is always on screen.
SHEET="$MODE"
[ "$MODE" = "control" ] && SHEET="player"
SRC="$SPR/$SHEET.png"
[ -f "$SRC" ] || { echo "NO VERDICT: $SRC is not there"; exit 2; }

DIR="$OUT/$MODE"
mkdir -p "$DIR"

# THE BACKUP COMES FROM `HEAD`, NOT FROM THE WORKING TREE, AND THAT IS A BUG NERITE FOUND BY
# BEING BITTEN BY IT (ASSA-181 QA, 2026-10-04). Their first run was cut off with the probe sheet
# still installed; the second run then copied THAT as `REAL_player.png`, "restored" it, and the
# control ran on a contaminated sheet and printed RED on a tool that was fine. A backup taken
# from a tree this script is itself in the habit of dirtying is not a backup.
#
# AND IF THE TREE IS ALREADY DIRTY HERE, THE ANSWER IS TO STOP. A modified sheet is either
# somebody's unmerged art or the wreckage of a killed run, and nothing on this machine can tell
# me which -- so restoring from HEAD would risk deleting real work and restoring from the tree is
# the bug above. Refusing is the only option that cannot destroy something.
REL="sim-game/client/assets/sprites/$SHEET.png"
if [ -n "$(git -C "$REPO" status --porcelain -- "$REL")" ]; then
  echo "NO VERDICT: $REL differs from HEAD before this run even starts."
  echo "  Either it is art you have not committed, or a previous run of this script was killed"
  echo "  with a probe sheet installed. I cannot tell which, and guessing wrong deletes your work."
  echo "  Commit it, or \`git checkout HEAD -- $REL\`, then run this again."
  exit 2
fi
git -C "$REPO" show "HEAD:$REL" > "$DIR/REAL_$SHEET.png" \
  || { echo "NO VERDICT: cannot read $REL out of HEAD"; exit 2; }

restore () {
  cp "$DIR/REAL_$SHEET.png" "$SRC"
  echo "--- git status for the sprites (MUST LIST NOTHING) ---"
  git -C "$REPO" status --short -- sim-game/client/assets/sprites/
}
# INT and TERM as well as EXIT: an EXIT trap alone does not fire when the run is killed, which is
# exactly how the sheet got left swapped in the first place.
trap restore EXIT INT TERM

shoot () {            # $1 label   $2 the sheet to install
  [ -f "$2" ] || { echo "NO VERDICT: probe sheet $2 was not written"; exit 2; }
  mkdir -p "$DIR/$1"
  cp "$2" "$SRC"
  cd "$CL"
  # TWICE, on purpose: the first `--import` after `.godot/` is gone crashes on exit having
  # already written a complete cache (a Godot bug named in sim-game/CLAUDE.md). CI does the same.
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  "$GODOT" --path . --script res://tools/window_shot.gd -- "$DIR/$1" "$SEED" "$TICKS" "$HOPPERS" \
      > "$DIR/$1.log" 2>&1 || true
  [ -f "$DIR/$1/02-play.png" ] || { echo "NO VERDICT: no 02-play.png; see $DIR/$1.log"; exit 2; }
  cp "$DIR/$1/02-play.png" "$DIR/$1.png"
  echo "  $1: $(ls -1 "$DIR/$1"/*.png 2>/dev/null | wc -l | tr -d ' ') shots"
}

cd "$REPO/sim-game"
if [ "$MODE" = "control" ]; then
  python3 art/window_alpha.py bands --out "$DIR" --w 512 --h 2048 --band 8
  echo "shooting the control, seed $SEED tick $TICKS:"
  shoot bg     "$DIR/bands_blank.png"
  shoot black  "$DIR/bands_black.png"
  shoot shot   "$DIR/bands_rgb.png"
  cd "$REPO/sim-game"
  python3 art/window_alpha.py control --dir "$DIR"
else
  python3 art/window_alpha.py variants --sheet "$DIR/REAL_$SHEET.png" --out "$DIR"
  echo "shooting $SHEET's alpha field, seed $SEED tick $TICKS:"
  shoot bg    "$DIR/variant_blank.png"
  shoot black "$DIR/variant_black.png"
  cd "$REPO/sim-game"
  python3 art/window_alpha.py field --bg "$DIR/bg.png" --black "$DIR/black.png" \
      --png "$DIR/alpha.png"
fi
