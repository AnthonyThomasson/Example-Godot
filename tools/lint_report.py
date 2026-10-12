#!/usr/bin/env python3
"""Turn the log of tools/lint_scripts.tscn into a per-file list of GDScript warnings and errors.

  python3 tools/lint_report.py LOG [--quiet]

Exit 1 when any script has a warning or error (or the lint never finished), 0 when clean. The engine prints a
warning without its file or line, so the file comes from the `LINT> <path>` markers the scene prints (see
lint_scripts.gd) and the lines are only candidates: the lines of that file which name the variable in the message,
or, for an integer division, the exact `/` (found by recompiling the script once per `/`, see lint_scripts.gd;
needs $GODOT, else the lines which divide). The editor's Debugger > Errors tab shows the exact line of the rest.
"""
import os
import re
import subprocess
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
HEADERS = ("SCRIPT ERROR:", "USER SCRIPT ERROR:", "ERROR:", "WARNING:", "SCRIPT WARNING:")
NOISE = ("Debugger Break", "Enter \"help\"", "*Frame", "at:", "LINT")
NAMED = re.compile(r'"(\w+)"')
MAX_CANDIDATES = 8


def entries(text: str):
    """Yield (path, message) for everything the engine printed after each `LINT> path` marker; (None, why) if
    the lint did not run to the end."""
    path = None
    started = done = False
    for raw in text.split("\n"):
        line = ANSI.sub("", raw.rstrip("\r")).strip()
        if line.startswith("debug> "):
            line = line[7:]
        if line.startswith("LINT-PASS2"):
            started = True
        elif line.startswith("LINT-DONE"):
            done = True
            break
        elif not started:
            continue
        elif line.startswith("LINT> "):
            path = line[6:]
        elif path and line.startswith(HEADERS) and not line.startswith(NOISE):
            msg = next(line[len(h):].strip() for h in HEADERS if line.startswith(h))
            yield path, msg.strip("'")
    if not done:
        yield None, "the lint did not finish (script crash or engine failure); see the log"


def candidates(path: str, msg: str) -> list[int]:
    """1-based lines of `path` that may hold the warning in `msg` (best effort, see the module docstring)."""
    try:
        with open(path.replace("res://", ""), encoding="utf-8") as f:
            lines = f.read().split("\n")
    except OSError:
        return []
    code = [re.sub(r"#.*", "", re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '""', l)) for l in lines]
    if "Integer division" in msg:
        return [i + 1 for i, l in enumerate(code) if re.search(r"/(?!/)", l)][:MAX_CANDIDATES]
    named = NAMED.search(msg)
    if named:
        name = re.escape(named.group(1))
        decl = re.compile(rf"\bvar {name}\b|\bfor {name}\b|\bfunc\b.*[(,]\s*{name}\b|\bconst {name}\b|[(,]\s*{name}\s*[:=,)]")
        found = [i + 1 for i, l in enumerate(code) if decl.search(l)]
        return (found or [i + 1 for i, l in enumerate(code) if re.search(rf"\b{name}\b", l)])[:MAX_CANDIDATES]
    return []


def division_sites(paths: list[str]) -> dict[str, list[tuple[int, int]]]:
    """Exact (line, column) of every integer division in each of `paths` ({} when Godot cannot be run)."""
    godot = os.environ.get("GODOT")
    if not godot or not paths:
        return {}
    run = subprocess.run([godot, "--headless", "--debug", "--path", ".", "res://tools/lint_scripts.tscn", "--",
                          "--divisions=" + ",".join(paths)], stdin=subprocess.DEVNULL, capture_output=True, text=True)
    sites: dict[str, list[tuple[int, int]]] = {}
    path = label = None
    counts: dict[str, int] = {}
    for raw in (run.stdout + run.stderr).split("\n"):
        line = ANSI.sub("", raw).strip()
        if line.startswith("LINT> "):
            path = line[6:]
            counts = {}
        elif line.startswith("LINT@ "):
            label = line[6:]
            counts[label] = 0
        elif label is not None and "Integer division" in line and line.startswith("ERROR:"):
            counts[label] += 1
        elif line.startswith("LINT-DONE") and path:
            base = counts.get("base", 0)
            for key, n in counts.items():
                if key != "base" and n < base:
                    row, col = key.split()
                    sites.setdefault(path, []).append((int(row), int(col)))
    return sites


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        return 2
    quiet = "--quiet" in sys.argv
    with open(args[0], encoding="utf-8", errors="replace") as f:
        text = f.read()
    by_file: dict[str, list[str]] = {}
    for path, msg in entries(text):
        by_file.setdefault(path or "(lint)", []).append(msg)
    if not by_file:
        if not quiet:
            print("PASS: no GDScript warnings or errors")
        return 0
    total = sum(len(v) for v in by_file.values())
    divided = division_sites([p for p, m in by_file.items() if any("Integer division" in x for x in m)])
    for path, msgs in by_file.items():
        print(f"{path}  ({len(msgs)})")
        for msg in dict.fromkeys(msgs):
            n = msgs.count(msg)
            if "Integer division" in msg and path in divided:
                where = "  [line:col " + ", ".join(f"{r}:{c}" for r, c in divided[path]) + "]"
            else:
                lines = candidates(path, msg) if path != "(lint)" else []
                where = f"  [candidate lines {', '.join(map(str, lines))}]" if lines else ""
            print(f"  {msg}{f'  x{n}' if n > 1 else ''}{where}")
    print(f"FAIL: {total} GDScript warning(s)/error(s) in {len(by_file)} file(s) (log: {args[0]})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
