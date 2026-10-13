#!/usr/bin/env python3
"""Whole-codebase detectors for the `m-audit-everything` skill (advisory lists, always exits 0).

  python3 tools/audit_scan.py [deps|dead|signals|facts|events|all]

  deps     unit -> unit edge matrix by class_name use in code (comments and string literals are ignored;
           scenes/ai/<sub>/ is its own unit; main.gd is the composition root and skipped), then the same
           matrix for `preload` / `load` paths and scene `ext_resource` paths. Every edge must be a vital
           interface in the `architecture` skill.
  dead     functions nothing references and declarations (const/var/signal/enum) nothing reads —
           any non-comment token anywhere in scenes/ tests/ tools/ addons/ counts as a reference; then the
           scene symbols referenced only from tests/ or tools/, and the test and tool declarations nothing
           references. Matching is by token, so a same-named member of another class hides a dead one.
  signals  every signal with its emit sites and its listeners (connect / await / .tscn wiring).
  facts    keys the decision snapshot writes into `facts` that no tree node, entry rule, test or tool
           gates on (and whether the skills/docs describe them as available vocabulary).
  events   every EventBus topic posted, how many listeners handle it, and each payload key it writes with
           how many reads it has outside the posting files (production vs. tests/tools).

Reads files only (no Godot needed). A hit is a lead: dynamic dispatch (duck-typed controllers,
gcmd `Expression` eval, scene-wired signals) can hide a real use, so confirm by hand.
"""
import collections
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)

SOURCE_DIRS = ("scenes", "tests", "tools", "addons")
SOURCE_EXT = (".gd", ".tscn", ".tres", ".py", ".sh", ".json")
LIFECYCLE = {
    "_ready", "_process", "_physics_process", "_draw", "_init", "_input", "_exit_tree", "_enter_tree",
    "_unhandled_input", "_unhandled_key_input", "_gui_input", "_notification", "_integrate_forces",
    "_to_string", "_get", "_set", "_get_configuration_warnings",
}
AUTOLOADS = {"Keybinds": "general", "Despawner": "general", "EventBus": "general", "Sound": "audio"}


def strip_comment(line: str) -> str:
    """The line without its trailing `#` comment (a `#` inside a string is kept)."""
    quote = None
    for i, c in enumerate(line):
        if quote:
            if c == quote and line[i - 1] != "\\":
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "#":
            return line[:i]
    return line


def strip_strings(line: str) -> str:
    """The line with the contents of its string literals removed (the quotes stay): a class name inside a string is text."""
    out = []
    quote = None
    for i, c in enumerate(line):
        if quote:
            if c == quote and line[i - 1] != "\\":
                quote = None
                out.append(c)
        else:
            if c in "\"'":
                quote = c
            out.append(c)
    return "".join(out)


def read(path: str) -> str:
    text = Path(path).read_text(errors="ignore")
    if path.endswith(".gd"):
        text = "\n".join(strip_comment(l) for l in text.split("\n"))
    return text


def source_files() -> list:
    return [os.path.join(d, f) for r in SOURCE_DIRS if os.path.isdir(r)
            for d, _, fs in os.walk(r) for f in fs if f.endswith(SOURCE_EXT)]


def scene_scripts() -> list:
    return [p for p in source_files() if p.endswith(".gd") and p.startswith("scenes")]


def unit_of(path: str) -> str:
    """The audit unit a scene script belongs to: a domain, or an ai sub-domain."""
    p = path.split("/")
    if len(p) == 2:
        return "main"
    if p[1] == "ai":
        return "ai/" + p[2] if len(p) >= 4 else "ai/core"
    return p[1]


def deps() -> None:
    print("== Cross-unit dependencies by class_name (main.gd skipped) ==")
    scripts = scene_scripts()
    owner = dict(AUTOLOADS)
    for f in scripts:
        for l in Path(f).read_text(errors="ignore").split("\n"):
            m = re.match(r"\s*class_name\s+(\w+)", l)
            if m:
                owner[m.group(1)] = unit_of(f)
    pattern = re.compile(r"\b(" + "|".join(sorted(owner, key=len, reverse=True)) + r")\b")
    edges = collections.defaultdict(collections.Counter)
    for f in scripts:
        u = unit_of(f)
        if u == "main":
            continue
        for l in read(f).split("\n"):
            for m in pattern.finditer(strip_strings(l)):
                t = owner[m.group(1)]
                if t != u:
                    edges[(u, t)][m.group(1)] += 1
    for (u, t), syms in sorted(edges.items()):
        top = ", ".join(f"{k}x{n}" for k, n in syms.most_common(10))
        print(f"  {u:14s} -> {t:14s} {sum(syms.values()):4d}  {top}")
    ai_edges = [k for k in edges if k[0].startswith("ai/") and k[1].startswith("ai/")]
    print(f"\n  ai sub-domain -> sub-domain class_name edges: {len(ai_edges)}"
          f"{'  <-- check isolation' if ai_edges else '  (the orchestrator wires them by preload)'}")
    print("\n== Cross-unit dependencies by path (preload / load / scene ext_resource; main skipped) ==")
    by_path = collections.defaultdict(collections.Counter)
    for f in source_files():
        if not f.startswith("scenes") or not f.endswith((".gd", ".tscn")):
            continue
        u = unit_of(f)
        if u == "main":
            continue
        body = read(f) if f.endswith(".gd") else Path(f).read_text(errors="ignore")
        for m in re.finditer(r"res://(scenes/[\w/]+\.(?:gd|tscn))", body):
            t = unit_of(m.group(1))
            if t != u:
                by_path[(u, t)][os.path.basename(m.group(1))] += 1
    if not by_path:
        print("  (none)")
    for (u, t), files in sorted(by_path.items()):
        top = ", ".join(f"{k}x{n}" for k, n in files.most_common(10))
        print(f"  {u:14s} -> {t:14s} {sum(files.values()):4d}  {top}")


def dead() -> None:
    files = source_files()
    text = {p: read(p) for p in files}
    alltext = "\n".join(text.values())
    tokens = collections.Counter(re.findall(r"[A-Za-z_]\w*", alltext))
    # Declarations are counted once per name: a regex per symbol over the whole corpus takes a minute.
    func_declared = collections.Counter(re.findall(r"^[ \t]*(?:static )?func ([A-Za-z_]\w*)", alltext, re.M))
    print("== Functions nothing references ==")
    found = False
    for p in scene_scripts():
        for m in re.finditer(r"^[ \t]*(?:static )?func ([A-Za-z_]\w*)", text[p], re.M):
            fn = m.group(1)
            if fn in LIFECYCLE:
                continue
            if tokens[fn] <= func_declared[fn]:
                print(f"  {p}:{text[p][:m.start()].count(chr(10)) + 1}  {fn}")
                found = True
    if not found:
        print("  (none)")
    print("\n== Declarations nothing reads ==")
    decl = r"^[ \t]*(?:@export\w*(?:\([^)]*\))?[ \t]+)?(?:const|var|signal|enum)[ \t]+"
    var_declared = collections.Counter(re.findall(decl + r"([A-Za-z_]\w*)", alltext, re.M))
    found = False
    for p in scene_scripts():
        for m in re.finditer("(" + decl + r")([A-Za-z_]\w*)", text[p], re.M):
            name = m.group(2)
            if tokens[name] <= var_declared[name]:
                print(f"  {p}:{text[p][:m.start()].count(chr(10)) + 1}  {name}")
                found = True
    if not found:
        print("  (none)")
    # The two passes below look at class members only (column 0: a local is always read by its own function), with
    # the declarations counted once per corpus (a regex per symbol over the whole corpus is too slow).
    sym = r"^(?:(?:static )?func[ \t]+|(?:@export\w*(?:\([^)]*\))?[ \t]+)?(?:const|var|signal|enum)[ \t]+)([A-Za-z_]\w*)"
    prod_text = "\n".join(t for q, t in text.items() if not q.startswith(("tests", "tools")))
    prod = collections.Counter(re.findall(r"[A-Za-z_]\w*", prod_text))
    declared_prod = collections.Counter(re.findall(sym, prod_text, re.M))
    declared = collections.Counter(re.findall(sym, alltext, re.M))
    print("\n== Scene symbols referenced only from tests/ or tools/ (scenes/testing/ serves them, so it is skipped) ==")
    found = False
    for p in scene_scripts():
        if p.startswith("scenes/testing/"):
            continue
        for m in re.finditer(sym, text[p], re.M):
            name = m.group(1)
            if name in LIFECYCLE or name.startswith("_"):
                continue
            if prod[name] <= declared_prod[name] < tokens[name]:
                print(f"  {p}:{text[p][:m.start()].count(chr(10)) + 1}  {name}  (test/tool refs: {tokens[name] - declared_prod[name]})")
                found = True
    if not found:
        print("  (none)")
    print("\n== Test and tool declarations nothing references ==")
    hooks = LIFECYCLE | {"describe", "configure", "run", "_initialize"}
    found = False
    for p in files:
        if not p.endswith(".gd") or not p.startswith(("tests", "tools")):
            continue
        for m in re.finditer(sym, text[p], re.M):
            name = m.group(1)
            if name not in hooks and tokens[name] <= declared[name]:
                print(f"  {p}:{text[p][:m.start()].count(chr(10)) + 1}  {name}")
                found = True
    if not found:
        print("  (none)")


def signals() -> None:
    print("== Signals: emit sites and listeners ==")
    files = [p for p in source_files() if p.endswith((".gd", ".tscn"))]
    text = {p: read(p) for p in files}
    for p in scene_scripts():
        for m in re.finditer(r"^[ \t]*signal[ \t]+(\w+)", text[p], re.M):
            s = m.group(1)
            emits = listeners = 0
            for u in text.values():
                emits += len(re.findall(r"\b" + s + r"\.emit\b|emit_signal\(\s*&?\"" + s + "\"", u))
                listeners += len(re.findall(
                    r"\b" + s + r"\.connect\b|\.connect\(\s*&?\"" + s + r"\"|await\s+[\w.$]*\b" + s
                    + r"\b|signal=\"" + s + "\"", u))
            flag = ("  <-- no listener" if listeners == 0 else "") + ("  <-- never emitted" if emits == 0 else "")
            line = text[p][:m.start()].count("\n") + 1
            print(f"  {p}:{line:<4} {s:<22} emit={emits} listeners={listeners}{flag}")


def facts() -> None:
    print("== Snapshot facts nothing gates on ==")
    snap = "scenes/ai/perception/agent_snapshot.gd"
    body = re.search(r"var facts := \{(.*?)\n\t\}", read(snap), re.S)
    keys = re.findall(r"\"([a-z_]+)\"\s*:", body.group(1)) if body else []
    code = "\n".join(read(p) for p in source_files() if p != snap)
    docs = "\n".join(Path(q).read_text(errors="ignore") for r in (".claude", "docs") if os.path.isdir(r)
                     for q in Path(r).rglob("*.md"))
    ungated = [k for k in keys if not re.search(r"\"!?" + k + "\"|&\"!?" + k + "\"", code)]
    for k in ungated:
        where = "documented as available" if re.search(r"`" + k + "`", docs) else "not documented either"
        print(f"  {k:<18} {where}")
    if not ungated:
        print("  (every fact is gated on somewhere)")
    print(f"  ({len(keys)} facts written by {snap}; 'gated' = a tree `requires`, entry rule, test or tool names it)")


def events() -> None:
    print("== EventBus topics: listeners, and each payload key's readers outside the posting files ==")
    text = {p: read(p) for p in source_files() if p.endswith(".gd")}
    prod = {p: t for p, t in text.items() if p.startswith("scenes")}
    posts = collections.defaultdict(dict)  # topic -> key -> the files that post it
    for p, t in prod.items():
        for m in re.finditer(r"EventBus\.post\(\s*&\"(\w+)\"\s*,\s*\{(.*?)\}\s*\)", t, re.S):
            for k in re.findall(r"\"(\w+)\"\s*:", m.group(2)):
                posts[m.group(1)].setdefault(k, set()).add(p)
    listeners = [p for p, t in prod.items() if "EventBus.posted" in t]
    for topic in sorted(posts):
        handled = sum(1 for p in listeners if re.search(r"&\"" + topic + r"\"", prod[p]))
        print(f"  &\"{topic}\"  listeners={handled}" + ("  <-- no listener" if handled == 0 else ""))
        for k, writers in sorted(posts[topic].items()):
            pat = re.compile(r"(?:\.get\(\s*|\[\s*)&?\"" + k + r"\"")
            reads = sum(len(pat.findall(t)) for p, t in text.items() if p not in writers and p.startswith("scenes"))
            tests = sum(len(pat.findall(t)) for p, t in text.items() if p not in writers and not p.startswith("scenes"))
            flag = "" if reads else ("  <-- read only by tests/tools" if tests else "  <-- nothing reads it")
            print(f"      {k:<14} reads={reads} tests={tests}{flag}")
    print("  (a generic key such as `position` is counted wherever that name is read; judge each)")


COMMANDS = {"deps": deps, "dead": dead, "signals": signals, "facts": facts, "events": events}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which != "all" and which not in COMMANDS:
        sys.exit(f"usage: audit_scan.py [{'|'.join(COMMANDS)}|all]")
    for name, fn in COMMANDS.items():
        if which in ("all", name):
            fn()
            print()
