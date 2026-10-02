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
set -u

if [ -z "${GODOT:-}" ]; then
  echo "set GODOT to the engine binary, e.g. GODOT=/Applications/Godot.app/Contents/MacOS/Godot" >&2
  exit 2
fi

cd "$(dirname "$0")/.." || exit 2

checked=0
failed=0
# Sorted so the output is the same on every machine, and `-print0`-free because
# none of these paths have spaces and `find | while` would lose the counters to a
# subshell.
for file in $(find . -name '*.gd' -not -path './.godot/*' | sort); do
  checked=$((checked + 1))
  # Captured, not piped: a pipeline's exit status is the last command's, and
  # there is no exit status here worth having anyway.
  out=$("$GODOT" --headless --check-only --script "$file" 2>&1)
  if printf '%s' "$out" | grep -qE 'SCRIPT ERROR|Parse Error'; then
    failed=$((failed + 1))
    echo "=== $file"
    printf '%s\n' "$out" | grep -E 'SCRIPT ERROR|Parse Error' | sed 's/^/    /'
  fi
done

if [ "$failed" -gt 0 ]; then
  echo "$failed of $checked GDScript files do not compile" >&2
  exit 1
fi
echo "$checked GDScript files compile, warnings-as-errors included"
