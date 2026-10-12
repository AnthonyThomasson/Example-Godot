#!/usr/bin/env python3
"""Whole-codebase detectors for the `m-audit-everything` skill (advisory lists, always exits 0).

  python3 tools/audit_scan.py [deps|dead|signals|facts|all]

  deps     unit -> unit edge matrix by class_name use (scenes/ai/<sub>/ is its own unit; main.gd is
           the composition root and skipped). Every edge must be a vital interface in the
           `architecture` skill.
  dead     functions nothing references and declarations (const/var/signal/enum) nothing reads —
           any non-comment token anywhere in scenes/ tests/ tools/ addons/ counts as a reference.
  signals  every signal with its emit sites and its listeners (connect / await / .tscn wiring).
  facts    keys the decision snapshot writes into `facts` that no tree node, entry rule, test or tool
           gates on (and whether the skills/docs describe them as available vocabulary).

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
            for m in pattern.finditer(l):
                t = owner[m.group(1)]
                if t != u:
                    edges[(u, t)][m.group(1)] += 1
    for (u, t), syms in sorted(edges.items()):
        top = ", ".join(f"{k}x{n}" for k, n in syms.most_common(10))
        print(f"  {u:14s} -> {t:14s} {sum(syms.values()):4d}  {top}")
    ai_edges = [k for k in edges if k[0].startswith("ai/") and k[1].startswith("ai/")]
    print(f"\n  ai sub-domain -> sub-domain class_name edges: {len(ai_edges)}"
          f"{'  <-- check isolation' if ai_edges else '  (the orchestrator wires them by preload)'}")


def dead() -> None:
    files = source_files()
    text = {p: read(p) for p in files}
    alltext = "\n".join(text.values())
    tokens = collections.Counter(re.findall(r"[A-Za-z_]\w*", alltext))
    print("== Functions nothing references ==")
    found = False
    for p in scene_scripts():
        for m in re.finditer(r"^[ \t]*(?:static )?func ([A-Za-z_]\w*)", text[p], re.M):
            fn = m.group(1)
            if fn in LIFECYCLE:
                continue
            decls = len(re.findall(r"^[ \t]*(?:static )?func " + fn + r"\b", alltext, re.M))
            if tokens[fn] <= decls:
                print(f"  {p}:{text[p][:m.start()].count(chr(10)) + 1}  {fn}")
                found = True
    if not found:
        print("  (none)")
    print("\n== Declarations nothing reads ==")
    decl = r"^[ \t]*(?:@export\w*(?:\([^)]*\))?[ \t]+)?(?:const|var|signal|enum)[ \t]+"
    found = False
    for p in scene_scripts():
        for m in re.finditer("(" + decl + r")([A-Za-z_]\w*)", text[p], re.M):
            name = m.group(2)
            decls = len(re.findall(decl + name + r"\b", alltext, re.M))
            if tokens[name] <= decls:
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


COMMANDS = {"deps": deps, "dead": dead, "signals": signals, "facts": facts}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which != "all" and which not in COMMANDS:
        sys.exit(f"usage: audit_scan.py [{'|'.join(COMMANDS)}|all]")
    for name, fn in COMMANDS.items():
        if which in ("all", name):
            fn()
            print()
