#!/usr/bin/env python3
"""`cache_blind.py` STILL ANSWERS THE QUESTION IT WAS BUILT FOR (ASSA-375).

    python3 client/tools/check_cache_blind.py

Stdlib only, no Godot, no network, under a second.

WHY A SILENT TOOL NEEDS A GATE OF ITS OWN. `cache_blind.py`'s product is its silence: nobody will
look at `_refresh_*` by hand again once a clean run exists. ASSA-320 is what that costs when the
instrument quietly stops working -- the paint-order pin's loop was renamed, `rfind` returned -1, and
a week of rulings rested on a guard that was false by construction and green. So this holds the tool
to the two cases it was commissioned for (Marlow, ASSA-353: *"build it against two knowns or nobody
can trust its silence"*), plus the three properties that make its classes mean anything.

**WHAT IS REAL AND WHAT IS A REPLICA, SAID HERE RATHER THAN IMPLIED.**

  Known A, ASSA-353 -- `_refresh_actions` keyed without the building standing on the target tile --
  is checked against THIS CHECKOUT'S OWN `client/scripts/`, because that is where it lives. It is
  asserted as NAMED, never as broken: the fix (`building_here` in the key, on `emp/marlow-assa353`)
  moves it from CANDIDATE to BY IDENTITY and both are a pass. **Silence is the failure**, and this
  check is the only thing standing between a future refactor of the walk and a quiet zero.

  Known B, Marlow's `_refresh_machine_menu` -- the key carrying the pack but not the slots -- has
  **no commit anywhere in which the defect exists**: he found it while writing the rows and put
  `_slot_shape(it)` in the key in the same commit (`ac15257`, `emp/marlow-assa351`). So his case is
  checked as a REPLICA written out below, in both arms. The real function is checked only for the
  thing that can be checked on the tree: that the tool finds its guard and reads its whole key,
  which runs onto a second line.

  Property 3 is the honest half: on that replica the two arms report THE SAME THING. The blind term
  enters through the sim (`_sim.insert_offers`), and no static reading of a key can say whether
  `_slot_shape(it)` summarises it. **The tool names Marlow's function and cannot price his fix**,
  and that limit is pinned here as an assertion so that nobody later credits it with the power.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import cache_blind  # noqa: E402

SCRIPTS = HERE.parent / "scripts"

# **THE REPLICA OF MARLOW'S CASE.** Trimmed to the shape under test and no more: a key over the
# pack, a reading taken off the sim before the guard, and rows built from that reading inside it.
MENU_ARMS = {
    "slots-out-of-the-key (his defect, reconstructed)":
        'var signature := "%d/%s" % [_menu_at, _pack_shape(stacks)]',
    "slots-in-the-key (what he shipped)":
        'var signature := "%d/%s/%s" % [_menu_at, _pack_shape(stacks), _slot_shape(it)]',
    # His own formatting: the key runs onto a second line, which is where a one-line read loses the
    # term he added. Asserted on the replica because today's `main.gd` happens to fit on one line,
    # so the same assertion against the tree would pass without the joining working at all.
    "slots-in-the-key, wrapped onto a second line":
        'var signature := "%d/%s/%s" % [_menu_at, _pack_shape(stacks),\n\t\t\t_slot_shape(it)]',
}
MENU = """extends Node

var _menu_at := -1
var _menu_showing := ""
var _menu_rows: VBoxContainer = null
var _sim = null
var _client = null


func _refresh_machine_menu() -> void:
\tvar facts := _sim.tile_at(_menu_tile)
\tvar it: Dictionary = facts.get("building")
\tvar stacks := _sim.inventory_of(_client.player_id)
\tvar offers := _sim.insert_offers(_client.player_id, _menu_at)
\t%s
\tif signature != _menu_showing:
\t\t_menu_showing = signature
\t\t_rebuild_machine_menu_rows(offers)


func _rebuild_machine_menu_rows(rows: Array) -> void:
\t_clear(_menu_rows)
\tfor row in rows:
\t\t_menu_rows.add_child(_button(String(row.get("label", ""))))
"""

# **THE CLASSIFIER'S TWO ARMS, which is ASSA-353's own shape at eight lines.** The drawn sentence is
# nested INSIDE the call to the surface it is added to, because that is where the first cut of the
# walk went blind: it skipped sink LINES, and every drawn thing in this client is inside one.
IDENT_ARMS = {
    "id-not-in-the-key": "",
    "id-in-the-key": "/%s",
}
IDENTITY = """extends Node

var _row_showing := ""
var _rows: VBoxContainer = null
var _sim = null


func _refresh_row() -> void:
\tvar target := _target_tile()
\tvar facts := _sim.tile_at(target)
\tvar standing = facts.get("building")
\tvar building_here := -1
\tif standing != null:
\t\tbuilding_here = int(standing["id"])
\tvar signature := "%%s%s" %% [target%s]
\tif signature == _row_showing:
\t\treturn
\t_row_showing = signature
\t_rows.add_child(_note(_line(facts)))


func _line(tile_facts: Dictionary) -> String:
\treturn String(tile_facts.get("building"))
"""


# **A SLOT THE FILE EMPTIES AND REFILLS.** `_cache` is handed to a helper that writes into it and
# is never dotted in the region, so nothing but the `= {}` says it is furniture. `main.gd` has three
# of these (`_halt_lines`, `_running_lines`, `_menu_slot_rows`) and they were four of the first ten
# candidates -- a report that is mostly furniture is a report nobody reads.
EMPTIED = """extends Node

var _showing := ""
var _cache := {}
var _menu_at := -1
var _sim = null


func _refresh() -> void:
\tvar k := "%s" % [_sim.tick()]
\tif k == _showing:
\t\treturn
\t_showing = k
\t_fill(_cache)
\t_cache[1] = _sim.status()
\t_cache[2] = _menu_at


func _fill(into: Dictionary) -> void:
\tinto[0] = 1


func _reset() -> void:
\t_cache = {}


func _choose(id: int) -> void:
\t_menu_at = id
"""


def run(text: str, name: str = "probe.gd") -> dict:
    """The tool's own answer on one file, as data."""
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp) / name
        p.write_text(text)
        found = cache_blind.analyse([p])
    if len(found) != 1:
        fail("the replica %s has %d guarded functions, expected exactly 1" % (name, len(found)))
    return found[0]


FAILURES = []


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print("FAIL  %s" % msg)


def ok(msg: str) -> None:
    print("ok    %s" % msg)


def main() -> int:
    if not SCRIPTS.is_dir():
        print("NO VERDICT: no %s" % SCRIPTS, file=sys.stderr)
        return 2

    # ---- 1. THE INSTRUMENT IS LOOKING AT SOMETHING ----------------------------------------------
    live = cache_blind.analyse(sorted(SCRIPTS.glob("*.gd")))
    by_func = {f["func"]: f for f in live}
    if len(live) < 8:
        fail("the walk found %d guarded functions in client/scripts; a parse that finds (almost) "
             "none is a broken instrument, not a clean repo" % len(live))
    else:
        ok("%d guarded functions found in client/scripts" % len(live))

    # ---- 2. KNOWN A: ASSA-353, ON THE REAL TREE --------------------------------------------------
    a = by_func.get("_refresh_actions")
    if a is None:
        fail("_refresh_actions has no key/guard pair any more: either the function was rewritten or "
             "the guard finder is broken. ASSA-353 lived in it; read the function before editing "
             "this line")
    else:
        named = dict(a["candidates"])
        named.update({k: v[0] for k, v in a["identity"].items()})
        where = named.get("facts.building")
        if where is None:
            fail("_refresh_actions draws `facts.building` through AssayHud.target_line and the walk "
                 "did not name it. That IS ASSA-353 (the clause froze at whatever stood on the tile "
                 "when it was last chosen); a silent run here means the walk stopped crossing the "
                 "call or stopped reading inside `add_child(...)`")
        elif not any("target_line" in w for w in where):
            fail("`facts.building` was named but not through AssayHud.target_line (%s): the one-hop "
                 "walk is what finds this family, so provenance through the helper is the claim"
                 % where)
        else:
            cls = "BY IDENTITY" if "facts.building" in a["identity"] else "CANDIDATE"
            ok("ASSA-353 named on the live tree: _refresh_actions -> facts.building [%s] via "
               "AssayHud.target_line" % cls)

    # ---- 3. KNOWN B: THE REAL FUNCTION, AND BOTH ARMS OF THE REPLICA -----------------------------
    m = by_func.get("_refresh_machine_menu")
    if m is None:
        fail("_refresh_machine_menu has no key/guard pair any more (Marlow's known); read the "
             "function before editing this line")
    elif "_slot_shape" not in m["key"]:
        fail("the key read off _refresh_machine_menu does not hold `_slot_shape`: that term is on "
             "the SECOND line of a wrapped expression, so this is the statement-joining breaking, "
             "and a key read half-way is a coverage set that silently over-reports. Key was: %s"
             % m["key"])
    else:
        ok("_refresh_machine_menu's key read whole across its wrapped lines")

    arms = {}
    for label, key in MENU_ARMS.items():
        f = run(MENU % key, "menu.gd")
        if "_slot_shape" in key and "_slot_shape" not in f["key"]:
            fail("the replica's key (%s) was read as `%s`: the statement-joining is broken, so a "
                 "key that wraps is read half-way and the coverage set silently over-reports"
                 % (label, f["key"]))
        arms.setdefault(sorted(f["candidates"]).__str__(), []).append(label)
        arms[label] = sorted(f["candidates"])
        if "offers" not in f["candidates"]:
            fail("the replica of Marlow's menu (%s) does not name `offers`, the reading taken off "
                 "the sim before the guard and drawn inside it. His function is the second known; "
                 "a walk that cannot see it is a broken instrument" % label)
        else:
            ok("Marlow's known named on the replica (%s): offers" % label)
    pair = [arms[label] for label in MENU_ARMS]
    if len(set(str(x) for x in pair)) != 1:
        fail("the two arms of Marlow's replica now differ (%s vs %s). That is a BETTER tool than "
             "the one this check was written for -- but say so on purpose: property 3 below asserts "
             "the opposite, and one of the two statements is now a lie" % (pair[0], pair[1]))
    else:
        ok("PINNED BLINDNESS: both arms of Marlow's replica report %s. The slots enter through "
           "`_sim.insert_offers`, and no reading of a key can price that statically -- the tool "
           "names his function and cannot see his fix" % pair[0])

    # ---- 4. THE CLASSIFIER DISCRIMINATES, AND IN THE RIGHT DIRECTION -----------------------------
    seen = {}
    for label, extra in IDENT_ARMS.items():
        f = run(IDENTITY % (extra, ", building_here" if extra else ""), "row.gd")
        seen[label] = f
    out = seen["id-not-in-the-key"]
    fixed = seen["id-in-the-key"]
    if "facts.building" not in out["candidates"]:
        fail("with the building's id OUT of the key, `facts.building` is not a CANDIDATE (%s): the "
             "defect arm of the classifier is dead" % sorted(out["candidates"]))
    elif "facts.building" not in fixed["identity"]:
        fail("with the building's id IN the key, `facts.building` is not BY IDENTITY (%s / %s): the "
             "chase from `building_here` back to `facts.get(\"building\")` is broken, so the tool "
             "can no longer tell a fixed function from a defective one"
             % (sorted(fixed["candidates"]), sorted(fixed["identity"])))
    elif "facts.building" in fixed["candidates"]:
        fail("the fixed arm reports `facts.building` as a CANDIDATE as well: a tool that calls a "
             "fix a defect will be ignored within a week")
    else:
        ok("the classifier tells the two arms apart: CANDIDATE without the id in the key, "
           "BY IDENTITY with it (`key holds facts.building.id`)")

    # ---- 5. A DRAWN THING NESTED INSIDE A SURFACE IS STILL READ ----------------------------------
    if "facts.building" not in out["candidates"]:
        pass  # already failed above
    elif not any("_line" in w for w in out["candidates"]["facts.building"]):
        fail("`facts.building` was found, but not through the helper inside `_rows.add_child(...)`. "
             "The first cut of this walk SKIPPED sink lines and so could not see ASSA-353 at all; "
             "if that ever comes back, this is the assertion that says so")
    else:
        ok("a value nested inside a surface's own call is still read (`_rows.add_child(_note(" +
           "_line(facts)))`)")

    # ---- 6. THE SURFACE FILTER IS ALIVE BUT NOT GREEDY -------------------------------------------
    if "_rows" in out["candidates"] or "_rows" in out["identity"]:
        fail("`_rows`, a container this file only ever writes into, is reported as an input: the "
             "surface filter is dead and every report will be mostly furniture")
    elif "_sim.tile_at" in out["candidates"] or "_sim" not in str(out["sinks"]):
        ok("the surface filter quietens the container and not the sim")
    else:
        ok("the surface filter quietens the container")

    # ---- 7. A SLOT THE FILE EMPTIES IS FURNITURE, AND A SENTINEL IS NOT -------------------------
    emptied = run(EMPTIED, "emptied.gd")
    if "_cache" in emptied["candidates"]:
        fail("`_cache`, a dictionary this file resets with `= {}` and refills through a helper, is "
             "reported as an input: three of main.gd's `_refresh_*` carry one of these and they "
             "were four of the first ten candidates. A report that is mostly furniture is ignored")
    elif "_sim.status" not in emptied["candidates"]:
        fail("`_sim.status`, read in the region and NOT in the key (which holds `_sim.tick`), is "
             "not reported (%s): either the emptied-slot filter is greedy or two reads through one "
             "member are being flattened into one" % sorted(emptied["candidates"]))
    elif "_menu_at" not in emptied["candidates"]:
        fail("`_menu_at`, a member a signal WRITES (`_menu_at = id`) and the region reads, is not "
             "reported (%s): the emptied-slot rule has gone greedy over every assignment, which "
             "silences exactly the inputs this tool exists to find" % sorted(emptied["candidates"]))
    else:
        ok("a slot the file empties is furniture; the sim read and the signal-written member "
           "beside it are not")

    print()
    if FAILURES:
        print("%d FAILURE(S)" % len(FAILURES))
        return 1
    print("cache_blind.py answers both knowns and keeps its three properties.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
