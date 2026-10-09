#!/bin/bash
# EVERY .gd FILE IS COMPILED, INCLUDING THE ONES NOTHING INSTANTIATES.
#
# The client suite is a strong guard for code something loads and a useless one
# for code nothing does. A probe in `tools/` is loaded by a person running it
# against a relay, which is to say: not in CI, not before a release, and not
# until the moment it is needed. GODOT ALSO EXITS 0 ON A PARSE ERROR, so a file
# that cannot compile at all costs nothing to ship -- that is how a parse error
# in `main.gd` once sat behind a green 42-test suite, and how a `const` taking a
# `PackedStringArray` (not a constant expression) took the whole HUD down while
# `--check-only` was the only thing that would have said so.
#
# `project.godot` promotes a few GDScript warnings to errors, so this also catches
# unreachable code and discarded expressions. It found a real one the day it was
# written: eight lines of `main.gd` that set the world/tick/hash line sat after a
# `return`, so that line never updated on a running client, and 79 passing tests
# had no opinion about it.
#
#   GODOT=/path/to/Godot tools/check_every_script.sh
#
# Exit 0 means every file compiles. The exit code is this script's, not Godot's:
# Godot's is 0 either way, which is the whole reason this exists.
#
# IT WALKS TWO ROOTS, AND THE SECOND ONE IS A SHIPPED FAILURE, NOT A PRECAUTION
# (asked for twice by Marlow). This script used to `find .` from `client/`, so
# "every .gd file" meant every .gd file INSIDE the Godot project: 110 of the
# repo's 113. The other three live in `sim-game/art/`, they `extends SceneTree`,
# and they import the project's own `class_name` libraries from outside it --
# which is exactly what makes them break when a client API changes. On
# 2026-10-08 a narrowed `part_layout` signature left `art/pack_icon_layout.gd`
# calling the old one while all 110 client scripts compiled green through this
# gate. Two red CI runs and three sheets to redraw found it; this gate could
# have, and did not, because the file was not in its tree.
#
# WHY THE ROOTS ARE NAMED IN THE COUNT RATHER THAN SUMMED. "113 compile" cannot
# tell "110 + 3" from "113 + 0": if the art glob ever matches nothing -- the
# directory moves, the files are renamed, somebody runs this from a tarball --
# the number barely moves and the gate quietly stops gating. So each root is
# counted separately, named in the success line and named on every failure, and
# A ROOT MATCHING ZERO FILES IS EXIT 2, NO VERDICT. A second root that silently
# matches nothing is worse than no second root: it reads as covered.
#
# COMPILE-ONLY, AND THAT IS MARLOW'S CONDITION, NOT AN ACCIDENT. `--check-only`
# parses and type-checks and never reaches `_init()`, so these three -- one of
# which joins a relay and one of which writes layout files -- are compiled here
# without being run. Measured: both `../art/x.gd` and an absolute path resolve
# (the relative form becomes `res://../art/x.gd`); the absolute path is used
# because it does not rest on `res://` being allowed to escape the project.
set -u

if [ -z "${GODOT:-}" ]; then
  echo "set GODOT to the engine binary, e.g. GODOT=/Applications/Godot.app/Contents/MacOS/Godot" >&2
  exit 2
fi

cd "$(dirname "$0")/.." || exit 2

# THE PROJECT MUST BE IMPORTED FIRST, AND THAT IS NOT A CONVENIENCE CHECK.
# A `class_name` is only a global identifier once the import has written
# `.godot/global_script_class_cache.cfg`; without it every file naming `AssayHud`
# fails to parse and this script reports 16 broken files that are all fine. That
# is exactly what happened the first time it ran in CI -- it passed here, where
# `.godot/` already existed, and failed on a fresh runner. Saying so beats
# reporting nonsense.
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "no .godot/global_script_class_cache.cfg: run '\$GODOT --headless --import'" >&2
  echo "first (twice -- the first import of a project with a GDExtension crashes" >&2
  echo "on exit in Godot's own doc generation, having written a complete cache)." >&2
  exit 2
fi

checked=0
failed=0
# Per-root tallies, in the order the roots are walked, for the summary line.
counts=""

# `client` is the Godot project itself; `art` is the Blender-pipeline directory
# one level up, whose .gd files import the project's classes from outside it.
for root in client art; do
  case "$root" in
    client) dir="." ;;
    art) dir="../art" ;;
  esac

  if [ ! -d "$dir" ]; then
    echo "root '$root' ($dir) is not a directory: run this from the repo's own tree" >&2
    exit 2
  fi

  # Sorted so the output is the same on every machine, and `-print0`-free because
  # none of these paths have spaces and `find | while` would lose the counters to a
  # subshell.
  found=0
  for file in $(find "$dir" -name '*.gd' -not -path '*/.godot/*' | sort); do
    found=$((found + 1))
    checked=$((checked + 1))
    # ABSOLUTE, because a `--script` path is resolved against the project root
    # and `../art/x.gd` only works by escaping `res://`. See the header.
    abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
    # Captured, not piped: a pipeline's exit status is the last command's, and
    # there is no exit status here worth having anyway.
    out=$("$GODOT" --headless --check-only --script "$abs" 2>&1)
    if printf '%s' "$out" | grep -qE 'SCRIPT ERROR|Parse Error'; then
      failed=$((failed + 1))
      # THE ROOT IS NAMED HERE TOO. A bare `../art/pack_icon_layout.gd` in a CI
      # log reads as a stray path; `art:` says which of this gate's two trees
      # is red, which is the first question anybody asks.
      echo "=== $root: $file"
      printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Parse Error' | sed 's/^/    /'
    fi
  done

  # A ROOT THAT MATCHES NOTHING IS NO VERDICT, NOT A PASS. The whole reason the
  # roots are counted apart is that a silent zero here is indistinguishable from
  # coverage in a single total.
  if [ "$found" -eq 0 ]; then
    echo "root '$root' ($dir) matched no .gd files; this gate's coverage is not what it claims" >&2
    exit 2
  fi
  counts="${counts:+$counts, }$found in $root"
done

if [ "$failed" -gt 0 ]; then
  echo "$failed of $checked GDScript files do not compile ($counts)" >&2
  exit 1
fi
echo "$checked GDScript files compile, warnings-as-errors included ($counts)"
