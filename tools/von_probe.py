#!/usr/bin/env python3
"""Probe whether Von makes INFORMED decisions from the context the AI gives it.

Each scenario is one level of the AI's decision tree — the exact state text, question and options
Von would see — plus the pick(s) a sensible player would make. The probe POSTs it to a running Von
server (`von serve`), checks Von's top pick, and can ABLATE a fact (drop one phrase at a time, from
the state and the options) to show which facts actually move the pick: a fact whose removal never
changes anything is not being used, so reword it or drop it.

What it taught us (see the perception sub-domain's wording rules): Von is a classifier that matches
option text against the state, so an option must state the SITUATION it is right for in the state's
own phrases, with no negations ("no cover" reads as "cover") and no action labels.

Scenarios live in tools/von_scenarios/*.json:

    {
      "name": "wounded and exposed: fall back",
      "state": "...",                       # the state text (as perception would write it)
      "question": "...",                    # the level's question
      "options": { "id": "description", ... },
      "expect": ["retreat"],                # pass when Von's top pick is one of these
      "top_k": 1,                           # optional: pass when an expected id is within the top k
      "ablate": ["You are badly wounded."]  # optional: substrings removed one at a time
    }

Capture real levels from a running game (every level of each NPC's last decision walk, with the
state and question Von actually saw) as scenario stubs to edit into clear-cut cases:

    python3 tools/gcmd.py ai > /tmp/ai.json && python3 tools/von_probe.py --capture /tmp/ai.json

Examples:
    python3 tools/von_probe.py                       # run every scenario
    python3 tools/von_probe.py --ablate              # also run each scenario's ablations
    python3 tools/von_probe.py tools/von_scenarios/flank_open_side.json -v
"""
import argparse
import glob
import json
import os
import re
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = os.path.join(HERE, "von_scenarios")


def ask(url: str, model: str, state: str, question: str, options: dict, timeout: float) -> dict:
    """POST one `choice` question; return Von's answer ({choice, probabilities, confidence})."""
    body = json.dumps({
        "model": model,
        "state": state,
        "questions": {"pick": {"type": "choice", "instructions": question, "criteria": options}},
    }).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))["answers"]["pick"]


def ranked(answer: dict) -> list:
    """Option ids by descending probability."""
    probs = answer.get("probabilities", {})
    return sorted(probs, key=lambda k: probs[k], reverse=True)


def passes(answer: dict, expect: list, top_k: int) -> bool:
    return any(e in ranked(answer)[:top_k] for e in expect)


def fmt_probs(answer: dict, limit: int = 6) -> str:
    probs = answer.get("probabilities", {})
    return ", ".join(f"{k}={probs[k]:.2f}" for k in ranked(answer)[:limit])


def run_scenario(path: str, args) -> bool:
    with open(path) as f:
        sc = json.load(f)
    name = sc.get("name", os.path.basename(path))
    expect = sc.get("expect", [])
    top_k = int(sc.get("top_k", 1))
    try:
        answer = ask(args.url, args.model, sc["state"], sc["question"], sc["options"], args.timeout)
    except (urllib.error.URLError, OSError) as err:
        print(f"ERROR  {name}: cannot reach Von at {args.url} ({err})")
        return False
    ok = passes(answer, expect, top_k) if expect else True
    verdict = "PASS" if ok else "FAIL"
    if not expect:
        verdict = "INFO"
    print(f"{verdict}  {name}: pick={answer.get('choice')} expect={expect or '-'} conf={answer.get('confidence', 0):.2f}")
    if args.verbose or not ok:
        print(f"       {fmt_probs(answer)}")
    if args.ablate:
        for cut in sc.get("ablate", []):
            # A fact may live in the state or in an option's text; remove it wherever it appears.
            if cut not in sc["state"] and not any(cut in d for d in sc["options"].values()):
                print(f"       ablate {cut!r}: not found")
                continue
            state = sc["state"].replace(cut, "").strip()
            options = {k: d.replace(cut, "").strip() for k, d in sc["options"].items()}
            cut_answer = ask(args.url, args.model, state, sc["question"], options, args.timeout)
            moved = cut_answer.get("choice") != answer.get("choice")
            delta = cut_answer.get("probabilities", {}).get(answer.get("choice"), 0.0) - \
                answer.get("probabilities", {}).get(answer.get("choice"), 0.0)
            print(f"       ablate {cut[:60]!r}: pick={cut_answer.get('choice')} "
                  f"{'CHANGED' if moved else 'same'} (p[{answer.get('choice')}] {delta:+.2f})")
    return ok


def capture(path: str, out_dir: str) -> int:
    """Write every Von-asked level of every NPC's last decision walk as a scenario stub."""
    with open(path) as f:
        text = f.read()
    start = text.find("[")
    npcs = json.loads(text[start:]) if start >= 0 else []
    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for npc in npcs:
        for level in npc.get("decision", {}).get("levels", []):
            if level.get("auto") or "state" not in level:
                continue
            slug = re.sub(r"[^a-z0-9]+", "_", f"{npc.get('npc', 'npc')}_{level['node']}".lower()).strip("_")
            dest = os.path.join(out_dir, f"captured_{slug}.json")
            with open(dest, "w") as f:
                json.dump({
                    "name": f"captured {npc.get('npc')} @ {level['node']} (Von picked {level.get('pick')})",
                    "state": level["state"],
                    "question": level["question"],
                    "options": level["offered"],
                    "expect": [],
                    "ablate": [],
                }, f, indent=2, ensure_ascii=False)
            written += 1
            print(f"wrote {dest}")
    print(f"{written} level(s) captured")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe Von's decisions against expected picks.")
    parser.add_argument("scenarios", nargs="*", help="Scenario files (default: tools/von_scenarios/*.json).")
    parser.add_argument("--url", default=os.environ.get("VON_URL", "http://127.0.0.1:8000/v1/systemone"))
    parser.add_argument("--model", default="von-1.2.0")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--ablate", action="store_true", help="Also run each scenario's ablations.")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show probabilities for every scenario.")
    parser.add_argument("--capture", metavar="AI_JSON", help="Turn a `gcmd.py ai` dump into scenario stubs.")
    parser.add_argument("--out", default=DEFAULT_DIR, help="Where --capture writes stubs.")
    args = parser.parse_args()

    if args.capture:
        return capture(args.capture, args.out)
    files = args.scenarios or sorted(glob.glob(os.path.join(DEFAULT_DIR, "*.json")))
    if not files:
        print("no scenarios found", file=sys.stderr)
        return 1
    results = [run_scenario(p, args) for p in files]
    failed = results.count(False)
    print(f"=== {len(results) - failed}/{len(results)} passed ===")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
