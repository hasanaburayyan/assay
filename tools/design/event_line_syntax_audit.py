#!/usr/bin/env python3
"""Which sim sentences name a sim-cli command? (ASSA-67, Maren 2026-10-02)

`debug::event_line` is the one function whose output the Godot client renders
verbatim (`AssaySim.event_lines` -> `main.gd:_remember_events`), and it is also
where rejections are worded. A command name in there tells a player at a window
to type something they cannot type.

The TABLE functions also carry syntax and that is fine: `species_table`,
`building_table`, `part_table`, `built_table` are CLI-only surfaces.

    python3 tools/design/event_line_syntax_audit.py        # from sim-game/

Exits non-zero if event_line names any command, so it can become a guard.
"""
import re, sys, pathlib

CMDS = set("""new load save pause resume speed tick goto move mine craft place
insert take pickup assay rename grant make assemble built equip unequip plant
stop where inv map players species deposits recipes parts buildings at events
status help quit""".split())
CLI_ONLY = {"species_table", "building_table", "part_table", "built_table", "recipe_table"}

def audit(path):
    src = pathlib.Path(path).read_text().splitlines()
    fn, owner = None, []
    for line in src:
        m = re.match(r"\s*(?:pub )?fn (\w+)", line)
        if m:
            fn = m.group(1)
            owner.append(fn)
        else:
            owner.append(fn)
    bad = []
    for i, line in enumerate(src):
        s = line.strip()
        if s.startswith("//") or '"' not in line:
            continue              # doc comments are never shown to a player
        for m in re.finditer(r"`([a-z]+)[^`]*`", line):
            if m.group(1) in CMDS and owner[i] not in CLI_ONLY:
                bad.append((owner[i] or "?", i + 1, m.group(0)))
    return bad

if __name__ == "__main__":
    bad = audit("sim/src/debug.rs")
    for fn, ln, tok in bad:
        print(f"{fn:<22} debug.rs:{ln:<6} {tok}")
    print(f"\n{len(bad)} command name(s) in player-facing sentences, "
          f"{len({(f, l) for f, l, _ in bad})} distinct lines")
    sys.exit(1 if bad else 0)
