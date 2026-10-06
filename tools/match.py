#!/usr/bin/env python3
"""Run and score 2-AI spectator matches (defender vs invader) against a running game.

The game must already be running in spectator mode with its dev command server up (see
scenes/general/command_server.gd, port from application/debug/command_port, default 9080). This
driver reuses that server's line protocol:

    restart [seed]   reload for a fresh matchup (optional seed pins the house layout)
    match            one parseable status line for both combatants + verdict + elapsed

For each round it restarts, optionally applies per-side overrides (arbitrary GDScript evaluated
against the scene, e.g. to retune a controller's goal/flags), polls `match` until a side wins or
the round times out, and finally prints a win-count summary across rounds.

Examples:
    python3 tools/match.py --rounds 5
    python3 tools/match.py --rounds 3 --seed 42 --timeout 60
    python3 tools/match.py --rounds 4 \\
        --defender 'scene().get_node("Defender/GoalController").goal = "hide and ambush"' \\
        --invader  'scene().get_node("Invader/GoalController").pursue_hostiles = true'

This talks to the same socket as tools/gcmd.py; keep that file as the single-command entry point.
"""
import argparse
import socket
import sys
import time


def send(host: str, port: int, line: str, timeout: float = 2.0) -> str:
    """Send one command line and return the server's reply (stripped)."""
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.sendall((line.strip() + "\n").encode("utf-8"))
        sock.settimeout(timeout)
        return sock.recv(65536).decode("utf-8", "replace").strip()


def parse_verdict(status: str) -> str:
    """Pull the verdict token out of a `match` status line ('none' while ongoing)."""
    for token in status.split("|"):
        token = token.strip()
        if token.startswith("verdict="):
            return token[len("verdict="):].split()[0]
    return "none"


def run_round(host: str, port: int, index: int, seed, overrides, timeout: float, poll: float) -> str:
    """Restart, apply overrides, then poll until decided or timed out. Returns the verdict."""
    restart = "restart" if seed is None else f"restart {seed + index}"
    send(host, port, restart)
    time.sleep(1.0)  # let the reloaded scene build the house + spawn both NPCs before we poke them
    for expr in overrides:
        reply = send(host, port, expr)
        print(f"  override: {expr}  -> {reply}")
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        last = send(host, port, "match")
        verdict = parse_verdict(last)
        if verdict not in ("none", "draw"):
            print(f"  round {index + 1}: {last}")
            return verdict
        if verdict == "draw":
            print(f"  round {index + 1}: {last}")
            return "draw"
        time.sleep(poll)
    print(f"  round {index + 1}: TIMEOUT  {last}")
    return "timeout"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rounds", type=int, default=3, help="Number of matches to run (default 3).")
    parser.add_argument("--seed", type=int, default=None, help="Base layout seed; round N uses seed+N (default random).")
    parser.add_argument("--timeout", type=float, default=60.0, help="Max seconds per round before it's a timeout.")
    parser.add_argument("--poll", type=float, default=1.0, help="Seconds between status polls.")
    parser.add_argument("--defender", action="append", default=[], help="GDScript applied after restart (repeatable).")
    parser.add_argument("--invader", action="append", default=[], help="GDScript applied after restart (repeatable).")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9080)
    args = parser.parse_args()

    overrides = args.defender + args.invader
    try:
        send(args.host, args.port, "help")  # fail fast if the game/server isn't up
    except OSError as err:
        print(f"match: cannot reach command server at {args.host}:{args.port} ({err})", file=sys.stderr)
        print("Is the game running in spectator mode with application/debug/command_port set?", file=sys.stderr)
        return 1

    tally: dict[str, int] = {}
    for i in range(args.rounds):
        verdict = run_round(args.host, args.port, i, args.seed, overrides, args.timeout, args.poll)
        tally[verdict] = tally.get(verdict, 0) + 1

    print("\n=== summary over %d rounds ===" % args.rounds)
    for name in sorted(tally, key=lambda k: -tally[k]):
        print(f"  {name}: {tally[name]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
