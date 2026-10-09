#!/usr/bin/env python3
"""THINGS DRAWN BEHIND A CACHE KEY THE KEY CANNOT SEE MOVE (ASSA-375).

    python3 client/tools/cache_blind.py                      # client/scripts/*.gd
    python3 client/tools/cache_blind.py <file.gd> [...]       # or named files
    python3 client/tools/cache_blind.py --json <file> ...

Static. No Godot, no window, no sim, stdlib only, under a second.

WHAT IT LOOKS FOR, AND WHY IT IS A TOOL AND NOT A TEST. A `_refresh_*` builds a cache key, returns
early (or skips its rebuild) when the key has not moved, and then draws something out of an input
the key does not carry. ASSA-353 was that: `_refresh_actions` keyed on five terms, none of them the
building standing on the target tile, and `AssayHud.target_line` thirty-five lines below named that
building -- so the clause froze at whatever stood there when the tile was last chosen. Marlow hit the
same shape in `_refresh_machine_menu` hours later.

**A TEST FINDS ONE INSTANCE AND NOTHING FINDS THE FAMILY**, because the defect is an ABSENCE: there
is no state in which a green assertion would have been red, so no test fails and no mutation reddens
anything. The family is visible only by comparing what a function DRAWS against what its key HOLDS,
which is a reading of the file.

THREE CLASSES, because a flat list of every identifier in a 120-line region is not readable:

  CANDIDATE    the gated region draws from this input and the key says nothing about it.
  BY IDENTITY  the key holds a SUB-FIELD of it -- almost always an `id`. Deliberate by this repo's
               own rule (`_refresh_actions`' docstring: *"the signature holds only the building's
               ID, never its status"*), because a status that moves every tick would rebuild the row
               four times a second and free the button under the cursor. Listed, never a candidate.
  SINK         an output node: every mention in the region is a method call whose return value is
               thrown away (`_actions.add_child(...)`) or a property written (`_menu_name.text =`).
               Where the drawing goes, not what it is drawn from.

**A CANDIDATE IS NOT A DEFECT.** It is a line to read. Three of the five candidates on the first
honest run were fine, and the reasons were all different (see `check_cache_blind.py`).

WHAT IT CANNOT SEE, so that a silent run is readable rather than reassuring:

  1. **A TERM THAT ENTERS THROUGH THE SIM.** If the key holds `_sim.tile_at(t)` and the region draws
     `_sim.insert_offers(p, t)`, nothing static can say whether the first summarises the second --
     both are reads of world state through a method. This is exactly Marlow's `_refresh_machine_menu`
     case, and it is why that known is NAMED by this tool and its fix is INVISIBLE to it. Pinned as
     a test in `check_cache_blind.py` so nobody later credits the tool with a power it lacks.
  2. **A MISSING READ.** A row that SHOULD depend on something and never reads it at all is a design
     defect, not a cache defect, and this tool is blind to it by construction.
  3. **HELPERS PAST ONE HOP.** The walk crosses one call -- same-file `func`s and `ClassName.func`
     where the class is a `class_name` in the same root. A helper's helper is not followed.
  4. **A KEY BUILT IN A LOOP** or assembled over several statements that are not one expression.
  5. **A MEMBER MOVED BY A SIGNAL.** The region may read a member that only a callback writes; the
     key may be right to leave it out or not, and that is a question about the signal.
  6. **ONE GUARD PER FUNCTION.** The first key/guard pair in a function is the one judged.

THE GUARD SHAPES IT KNOWS. Both are in `main.gd` today:

  early-return   `var k := ...` / `if k == _showing: return`         gated region = the rest
  gated-rebuild  `var k := ...` / `if k != _showing:` / `_showing = k` / `rebuild(...)`
                                                                     gated region = the if body
"""

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent / "scripts"

# GDScript words that are not inputs. `self` is not an input either: it is this object.
KEYWORDS = {
    "if", "elif", "else", "for", "in", "while", "match", "break", "continue", "return", "pass",
    "var", "const", "func", "static", "class", "class_name", "extends", "enum", "signal", "await",
    "and", "or", "not", "is", "as", "true", "false", "null", "self", "super", "void", "int",
    "float", "bool", "String", "StringName", "Array", "Dictionary", "Variant", "range", "print",
    "push_error", "push_warning", "assert", "str", "len", "min", "max", "abs", "clamp", "round",
    "floor", "ceil", "typeof", "is_instance_valid", "PackedStringArray", "PackedInt32Array",
    "Callable", "Signal", "Vector2", "Vector2i", "Vector3", "Color", "Rect2", "Rect2i", "NodePath",
    "signature", "breakpoint", "when", "float_is_equal_approx",
}

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
GET_FIELD = re.compile(r"\b([A-Za-z_]\w*)\s*\.\s*get\(\s*[\"'](\w+)[\"']")
IDX_FIELD = re.compile(r"\b([A-Za-z_]\w*)\s*\[\s*[\"'](\w+)[\"']\s*\]")
FUNC_DEF = re.compile(r"^(static\s+)?func\s+([A-Za-z_]\w*)\s*\((.*)$")
VAR_DECL = re.compile(r"\bvar\s+([A-Za-z_]\w*)")
FOR_DECL = re.compile(r"^for\s+([A-Za-z_]\w*)\s+in\b")
CLASS_NAME = re.compile(r"^class_name\s+([A-Za-z_]\w*)")
CMP = re.compile(r"^if\s+(.+?)\s*(==|!=)\s*(.+?)\s*:\s*$")
CALL = re.compile(r"\b([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)\s*\(")


def strip_comment(line: str) -> str:
    """Drop a trailing `#` comment, honouring quotes. A `#` inside a string is not a comment."""
    out = []
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                out.append(line[i:i + 2])
                i += 2
                continue
            if c == quote:
                quote = None
            out.append(c)
        else:
            if c == "#":
                break
            if c in "\"'":
                quote = c
            out.append(c)
        i += 1
    return "".join(out)


def indent_of(line: str) -> int:
    n = 0
    for c in line:
        if c == "\t":
            n += 1
        elif c == " ":
            n += 1  # mixed indentation would be a compile error; count it anyway
        else:
            break
    return n


class Script:
    """One .gd file, split into file-scope members and functions. Comments already gone."""

    def __init__(self, path: Path, text: str):
        self.path = path
        self.raw = text.splitlines()
        self.code = [strip_comment(ln) for ln in self.raw]
        self.class_name = None
        self.members = set()
        self.consts = set()
        self.funcs = {}
        self._scan()

    def _scan(self):
        for ln in self.code:
            m = CLASS_NAME.match(ln.strip())
            if m:
                self.class_name = m.group(1)
            if indent_of(ln) == 0:
                s = ln.strip()
                if s.startswith("var ") or s.startswith("@onready var "):
                    d = VAR_DECL.search(s)
                    if d:
                        self.members.add(d.group(1))
                elif s.startswith("const "):
                    c = re.search(r"\bconst\s+([A-Za-z_]\w*)", s)
                    if c:
                        self.consts.add(c.group(1))
                elif s.startswith("enum "):
                    e = re.search(r"\benum\s+([A-Za-z_]\w*)", s)
                    if e:
                        self.consts.add(e.group(1))
        i = 0
        while i < len(self.code):
            m = FUNC_DEF.match(self.code[i])
            if m and indent_of(self.code[i]) == 0:
                name = m.group(2)
                params = self._params(i)
                start = i + 1
                j = start
                while j < len(self.code):
                    ln = self.code[j]
                    if ln.strip() and indent_of(ln) == 0:
                        break
                    j += 1
                self.funcs[name] = {
                    "name": name, "line": i + 1, "body": (start, j), "params": params,
                }
                i = j
                continue
            i += 1

    def _params(self, i: int) -> list:
        """The parameter names of the func starting on line i, across a wrapped signature."""
        text = self.code[i]
        while text.count("(") > text.count(")") and i + 1 < len(self.code):
            i += 1
            text += " " + self.code[i].strip()
        inner = text[text.find("(") + 1:]
        depth = 0
        cut = len(inner)
        for k, c in enumerate(inner):
            if c in "([{":
                depth += 1
            elif c in ")]}":
                if depth == 0:
                    cut = k
                    break
                depth -= 1
        names = []
        for part in split_top(inner[:cut]):
            d = re.match(r"\s*([A-Za-z_]\w*)", part)
            if d:
                names.append(d.group(1))
        return names


def split_top(text: str) -> list:
    """Split on commas that are not inside brackets, quotes or a lambda's body."""
    parts, depth, quote, cur = [], 0, None, []
    for c in text:
        if quote:
            cur.append(c)
            if c == quote:
                quote = None
            continue
        if c in "\"'":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(c)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return parts


def fields_in(text: str) -> set:
    return {(m.group(1), m.group(2)) for m in GET_FIELD.finditer(text)} | \
           {(m.group(1), m.group(2)) for m in IDX_FIELD.finditer(text)}


def joined(script: Script, n: int, hi: int) -> str:
    """The statement starting on line n, across the lines it wraps onto.

    **A KEY WRAPS AND THE TAIL OF IT IS STILL THE KEY.** `_refresh_machine_menu`'s key runs to a
    second line; reading one line of it dropped `_slot_shape(it)` -- the exact term Marlow added --
    out of what the tool believed the key held.
    """
    s = script.code[n].strip()
    while n + 1 < hi and (s.endswith("\\") or
                          s.count("(") + s.count("[") > s.count(")") + s.count("]")):
        n += 1
        s = s.rstrip("\\") + " " + script.code[n].strip()
    return s


def locals_before(script: Script, lo: int, hi: int) -> dict:
    """name -> list of RHS texts assigned in [lo, hi)."""
    out = {}
    for n in range(lo, hi):
        s = joined(script, n, hi)
        d = VAR_DECL.search(s)
        f = FOR_DECL.match(s)
        if f:
            out.setdefault(f.group(1), []).append(s[s.find(" in ") + 4:])
            continue
        if d:
            name = d.group(1)
            rhs = s.split("=", 1)[1] if "=" in s else ""
            out.setdefault(name, []).append(rhs)
            continue
        a = re.match(r"^([A-Za-z_]\w*)\s*=\s*(.+)$", s)
        if a and a.group(1) in out:
            out[a.group(1)].append(a.group(2))
    return out


def find_guard(script: Script, fn: dict):
    """The first key/guard pair in this function, or None."""
    lo, hi = fn["body"]
    assigned = locals_before(script, lo, hi)
    for n in range(lo, hi):
        s = script.code[n].strip()
        m = CMP.match(s)
        if not m:
            continue
        left, op, right = m.group(1).strip(), m.group(2), m.group(3).strip()
        key_var = mem = None
        for a, b in ((left, right), (right, left)):
            if a in assigned and (b in script.members):
                key_var, mem = a, b
        if key_var is None:
            continue
        body_indent = indent_of(script.code[n]) + 1
        end = n + 1
        while end < hi and (not script.code[end].strip() or indent_of(script.code[end]) >= body_indent):
            end += 1
        block = [script.code[k] for k in range(n + 1, end)]
        has_return = any(b.strip() == "return" for b in block)
        sets_member = any(re.match(r"^%s\s*=" % re.escape(mem), b.strip()) for b in block)
        if op == "==" and has_return:
            shape, region = "early-return", (end, hi)
        elif op == "!=" and sets_member:
            shape, region = "gated-rebuild", (n + 1, end)
        else:
            continue
        key_text = " ; ".join(t.strip() for t in assigned[key_var])
        return {
            "guard_line": n + 1, "shape": shape, "key_var": key_var, "member": mem,
            "key_text": key_text, "region": region, "assigned": assigned,
        }
    return None


WRITE_CALL = re.compile(r"^([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)\s*\(.*\)\s*$")
WRITE_PROP = re.compile(r"^([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)\s*=[^=]")
CHAIN = re.compile(r"\b([A-Za-z_]\w*)(\s*\.\s*[A-Za-z_]\w*)?")
AFTER_GET = re.compile(r"^\s*\(\s*[\"'](\w+)[\"']")
AFTER_IDX = re.compile(r"^\s*\[\s*[\"'](\w+)[\"']\s*\]")


def refs(script: Script, text: str) -> set:
    """Every `(base, suffix)` an expression reads, one level deep.

    **THE SUFFIX IS WHAT KEEPS A KEY HONEST.** `_sim.inventory_of(..)` in the key does NOT cover
    `_sim.tile_at(..)` in the region -- two reads of different world state through one member -- and
    `facts.get("building")` in the key does not cover `facts.get("deposit")`. Flattening both to
    `_sim` and `facts` is how a tool like this goes quietly blind.
    """
    out = set()
    for m in CHAIN.finditer(text):
        base = m.group(1)
        if base in KEYWORDS or base in script.consts:
            continue
        suffix = ""
        part = (m.group(2) or "").replace(".", "").strip()
        rest = text[m.end():]
        if part == "get":
            g = AFTER_GET.match(rest)
            suffix = "." + g.group(1) if g else ".get"
        elif part:
            suffix = "." + part
        else:
            g = AFTER_IDX.match(rest)
            if g:
                suffix = "." + g.group(1)
        out.add((base, suffix))
    return out


def is_sample(script: Script, rhs: str) -> bool:
    """Does this right-hand side take a reading, rather than re-shape one in hand?"""
    for m in CALL.finditer(rhs):
        callee = m.group(1)
        if callee in script.funcs:
            return True
        if "." in callee and callee.split(".")[0] in script.members:
            return True
    return False


def resolve(script: Script, assigned: dict, base: str, depth: int = 0, seen=None) -> set:
    """Where a local came from, as dotted paths. `building_here` <- `int(b["id"])` <- `b` <-
    `standing` <- `facts.get("building")` resolves to `facts.building.id`, which is what makes the
    ASSA-353 fix legible to this tool as the key holding an IDENTITY."""
    seen = seen or set()
    if base not in assigned or base in seen or depth > 4:
        return {base}
    # **A SAMPLED VALUE IS ATOMIC, AND STOPPING THERE IS THE POINT.** `facts := _sim.tile_at(t)` is
    # a reading taken off the world; chasing THROUGH it produced paths like `_sim.running.building`
    # and lost the one that matters, `facts.building`. A local whose value comes out of a call to a
    # member or to a function in this file is where the chase ends.
    if any(is_sample(script, rhs) for rhs in assigned[base]):
        return {base}
    seen = seen | {base}
    out = {base}  # the name itself is in the key too, not only what it was built from
    for rhs in assigned[base]:
        for b2, s2 in refs(script, rhs):
            if b2 in script.funcs or b2 == base:
                continue
            for p in resolve(script, assigned, b2, depth + 1, seen):
                out.add(p + s2)
    return out or {base}


def expand_key(script: Script, guard: dict) -> set:
    """What the key HOLDS, as dotted paths."""
    covered = {guard["key_var"], guard["member"]}
    for base, suffix in refs(script, guard["key_text"]):
        if base in script.funcs:
            continue
        for p in resolve(script, guard["assigned"], base):
            covered.add(p + suffix)
    return covered


def sink_receivers(script: Script, lo: int, hi: int) -> dict:
    """Identifiers that the region WRITES INTO: a statement-level call whose return value is thrown
    away, or a property written. A container you add children to is an output for the whole region,
    so `_clear(_actions)` on the next line is an output too.

    **THIS CLASSIFIES THE IDENTIFIER, NEVER THE LINE, AND THE DIFFERENCE IS THE WHOLE TOOL.** The
    first cut skipped sink LINES, which blinded the walk to ASSA-353 itself: the drawn sentence is
    `_actions.add_child(_note(AssayHud.target_line(..., facts)))`, so the input is nested inside the
    call to the sink. A tripwire tighter than its claim.
    """
    out = {}
    for n in range(lo, hi):
        s = joined(script, n, hi)
        m = WRITE_CALL.match(s) or WRITE_PROP.match(s)
        if m and m.group(1) in script.members:
            out.setdefault(m.group(1), []).append(n + 1)
            out.setdefault("%s.%s" % (m.group(1), m.group(2)), []).append(n + 1)
    return out


def surfaces(script: Script) -> set:
    """Members this FILE writes into anywhere: a drawing surface, not an input.

    Read off the file rather than guessed from the name or the declared type. `_build_picker` is a
    `VBoxContainer` the build screen hands to `_clear()` and `_show_section()`, so it arrives in the
    walk looking like an input; `_build_picker.name = BUILD_PICKER` three thousand lines away is the
    file saying what it is. Only the BARE member is quietened: `_sim.running` stays a candidate even
    though `_client.submit(...)` makes `_client` a surface by this rule, because a METHOD read is a
    reading of state and not a place to put a child.
    """
    found = set()
    for n in range(len(script.code)):
        s = script.code[n].strip()
        m = WRITE_CALL.match(s) or WRITE_PROP.match(s)
        if m and m.group(1) in script.members:
            found.add(m.group(1))
        # **AND A MEMBER THE FILE EMPTIES IS A SLOT THE FILE REFILLS.** `_halt_lines = null`,
        # `_menu_slot_rows = {}`: a container this file tears down and rebuilds, which arrives in
        # the walk looking like an input because the rebuild helper reads it back. Only the EMPTY
        # literals count -- `_menu_at = -1` is a sentinel on a real input and stays a candidate.
        e = re.match(r"^(_[A-Za-z0-9_]*)\s*=\s*(null|\{\}|\[\]|\"\")\s*$", s)
        if e and e.group(1) in script.members:
            found.add(e.group(1))
    return found


def hop(script: Script, roots: dict, call: str, args: list, out: dict, note: str):
    """One level into a called helper: its member reads, and the fields it reads off the arguments
    it was handed. `AssayHud.target_line(target, _targeted, facts)` is where ASSA-353's identifier
    was actually read, so the walk has to cross the call."""
    owner, name = script, call
    if "." in call:
        cls, name = call.split(".", 1)
        owner = roots.get(cls)
        if owner is None:
            return
    fn = owner.funcs.get(name)
    if fn is None:
        return
    lo, hi = fn["body"]
    text = "\n".join(owner.code[lo:hi])
    inner = locals_before(owner, lo, hi)
    drains = set(sink_receivers(owner, lo, hi)) | surfaces(owner)
    for base, suffix in refs(owner, text):
        if base in owner.members and base not in inner and (base + suffix) not in drains:
            out.setdefault(base + suffix, []).append("%s via %s()" % (note, call))
    bound = {}
    for k, p in enumerate(fn["params"]):
        if k < len(args):
            base = re.match(r"\s*([A-Za-z_]\w*)\s*$", args[k])
            if base:
                bound[p] = base.group(1)
    for base, field in fields_in(text):
        if base in bound:
            out.setdefault("%s.%s" % (bound[base], field), []).append(
                "%s via %s() -> %s.get(\"%s\")" % (note, call, base, field))


def walk(script: Script, roots: dict, fn: dict, guard: dict) -> dict:
    """Every input the gated region draws from, with where it was read."""
    lo, hi = guard["region"]
    inner = locals_before(script, lo, hi)
    reads = {}
    sinks = sink_receivers(script, lo, hi)
    for surface in surfaces(script):
        sinks.setdefault(surface, [])
    for n in range(lo, hi):
        s = joined(script, n, hi)
        if not s:
            continue
        where = n + 1
        # The cache slot itself is not an input: it is where the key is kept.
        if re.match(r"^%s\s*=" % re.escape(guard["member"]), s):
            continue
        # **A LAMBDA'S BODY IS NOT DRAWN, IT IS PRESSED.** `_button("Mine", func() -> void: _act(..))`
        # runs `_act` when somebody clicks, long after this region, so hopping into it reported
        # `_client.submit` as a thing the row draws. What a closure CAPTURES can freeze the same way
        # a cache key can (main.gd says so itself beside `_menu_showing`), and that is a different
        # family this tool does not judge.
        s = re.split(r"\bfunc\s*\(", s)[0]
        if not s.strip():
            continue
        for base, suffix in refs(script, s):
            if base in inner or base in script.funcs or base in roots or base == script.class_name:
                continue
            if base not in script.members and base not in fn["params"] \
                    and base not in guard["assigned"]:
                continue
            reads.setdefault(base + suffix, []).append("read at %d" % where)
        for m in CALL.finditer(s):
            call = m.group(1)
            rest = s[m.end() - 1:]
            depth, cut = 0, len(rest)
            for k, c in enumerate(rest):
                if c in "([{":
                    depth += 1
                elif c in ")]}":
                    depth -= 1
                    if depth == 0:
                        cut = k
                        break
            hop(script, roots, call, split_top(rest[1:cut]), reads, "line %d" % where)
    return {"reads": reads, "sinks": sinks}


def classify(covered: set, reads: dict, sinks: dict) -> dict:
    """CANDIDATE: nothing in the key about it. BY IDENTITY: the key holds a sub-field of it.
    Anything whose base the region writes into is an output, however it is mentioned."""
    out = {"candidate": {}, "identity": {}}
    for name, wheres in sorted(reads.items()):
        if name in covered:
            continue
        base = name.split(".")[0]
        if base in covered or name in sinks or (name == base and base in sinks):
            continue
        deeper = sorted(c for c in covered if c.startswith(name + "."))
        if deeper:
            out["identity"][name] = (wheres, deeper)
        else:
            out["candidate"][name] = wheres
    return out


def analyse(paths: list) -> list:
    roots = {}
    scripts = []
    search = {p.resolve() for p in paths}
    # Every `class_name` in the script root is loaded too, whether or not it is under judgement:
    # that is what lets the walk cross `AssayHud.target_line`.
    # The pool is the judged files' OWN directories, never this checkout's `client/scripts`: a copy
    # of an older `main.gd` must hop into the `hud.gd` it shipped with, or the walk would read
    # today's helper and answer about a file that never existed.
    pool = set(search)
    for p in search:
        for pat in ("*.gd", "*.gd.fixture"):
            pool |= {q.resolve() for q in p.parent.glob(pat)}
    for p in sorted(pool):
        try:
            s = Script(p, p.read_text())
        except OSError:
            continue
        if s.class_name:
            roots[s.class_name] = s
        scripts.append(s)
    found = []
    for s in scripts:
        if s.path.resolve() not in search:
            continue
        for name, fn in sorted(s.funcs.items(), key=lambda kv: kv[1]["line"]):
            guard = find_guard(s, fn)
            if guard is None:
                continue
            covered = expand_key(s, guard) | {guard["key_var"], guard["member"]}
            seen = walk(s, roots, fn, guard)
            cls = classify(covered, seen["reads"], seen["sinks"])
            found.append({
                "file": str(s.path), "func": name, "func_line": fn["line"],
                "guard_line": guard["guard_line"], "shape": guard["shape"],
                "member": guard["member"], "key": guard["key_text"],
                "region": [guard["region"][0] + 1, guard["region"][1]],
                "covered": sorted(covered),
                "candidates": cls["candidate"], "identity": cls["identity"],
                "sinks": {k: v for k, v in sorted(seen["sinks"].items())},
            })
    return found


NOT_LOOKED_AT = """
WHAT THIS RUN DID NOT LOOK AT (`cache_blind.py`'s docstring has the long form):
  1. a term that enters through the sim -- two different `_sim` methods cannot be compared statically
  2. a missing read: a drawn thing that depends on something it never reads at all
  3. helpers past ONE hop, and helpers reached through a Callable or a signal
  4. a key built in a loop, or assembled over several statements
  5. a member only a signal writes
  6. the SECOND guard in a function: the first key/guard pair is the one judged
"""


def main(argv: list) -> int:
    as_json = "--json" in argv
    args = [a for a in argv if not a.startswith("--")]
    paths = [Path(a) for a in args] or sorted(SCRIPTS.glob("*.gd"))
    missing = [p for p in paths if not p.is_file()]
    if missing:
        print("NO VERDICT: no such file: %s" % ", ".join(str(m) for m in missing), file=sys.stderr)
        return 2
    found = analyse(paths)
    if as_json:
        print(json.dumps(found, indent=2, sort_keys=True))
        return 0
    print("CACHE-BLIND WALK (ASSA-375) -- %d guarded function(s) over %d file(s)"
          % (len(found), len(paths)))
    total = 0
    for f in found:
        print("\n%s:%d  %s   [%s]" % (f["file"], f["guard_line"], f["func"], f["shape"]))
        print("  key      %s" % f["key"])
        print("  against  %s" % f["member"])
        print("  gated    lines %d..%d" % (f["region"][0], f["region"][1]))
        for name, wheres in sorted(f["candidates"].items()):
            total += 1
            print("  CANDIDATE    %-28s %s" % (name, "; ".join(wheres[:3])))
        for name, (wheres, deeper) in sorted(f["identity"].items()):
            print("  BY IDENTITY  %-28s key holds %s  (%s)"
                  % (name, ", ".join(deeper), "; ".join(wheres[:2])))
        if f["sinks"]:
            print("  SINK         %s" % ", ".join("%s (%d)" % (k, len(v))
                                                  for k, v in f["sinks"].items()))
    print("\n%d CANDIDATE(S). A candidate is not a defect: read the line." % total)
    print(NOT_LOOKED_AT)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
