#!/usr/bin/env python3
"""Report what the game tests do not cover yet (a to-do list, not a gate; always exits 0).

  python3 tools/test_coverage.py

Three views, all read from files (no Godot needed):
  1. Domains: each scenes/<domain>/ with its test count (tests/<domain>/**/*_test.gd) — 0 = untested.
  2. Switches: rows of scenes/testing/test_switches.gd that no test turns on/off with s.switch(...).
  3. Interfaces: `Class.method` names in the `architecture` skill's "vital interfaces" section that
     never appear in tests/ or scenes/testing/ (a heuristic: a call by name counts as covered).
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
tests = sorted((ROOT / "tests").rglob("*_test.gd"))
test_text = {t: t.read_text() for t in tests if "_harness" not in t.parts}
harness_text = "\n".join(p.read_text() for p in (ROOT / "scenes" / "testing").glob("*.gd"))
all_test_text = "\n".join(test_text.values())

print("== Domains ==")
for d in sorted(p.name for p in (ROOT / "scenes").iterdir() if p.is_dir()):
    n = sum(1 for t in test_text if t.relative_to(ROOT / "tests").parts[0] == d)
    print(f"  {d:<12} {n} test(s){'   <-- none' if n == 0 and d != 'testing' else ''}")

print("\n== Switches never used by a test ==")
switches = re.findall(r'&"([a-z_]+\.[a-z_]+)":\s*\{', (ROOT / "scenes/testing/test_switches.gd").read_text())
unused = [s for s in switches if f'&"{s}"' not in all_test_text]
print("  " + (", ".join(unused) if unused else "(all used)"))

print("\n== Interfaces never called by a test ==")
arch = (ROOT / ".claude/skills/architecture/SKILL.md").read_text()
section = arch.split("## The vital interfaces", 1)[1].split("### Dependency graph", 1)[0]
# A public member only: `Keybinds._ready` is named in the skill as what Main does NOT call.
names = sorted(set(re.findall(r"`([A-Z][A-Za-z]+\.[a-z][a-z_]*)\b", section)))
missing = []
for full in names:
    cls, method = full.split(".")
    if not re.search(rf"\b{cls}\.{method}\b|\.{method}\(", all_test_text + harness_text):
        missing.append(full)
print("  " + (", ".join(missing) if missing else "(all referenced)"))
print(f"\n{len(tests)} test file(s); {len(names)} interface names checked.")
