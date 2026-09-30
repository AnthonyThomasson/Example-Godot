#!/usr/bin/env python3
"""Send one command to the running game's dev command server and print its reply.

The Godot MCP can launch/kill the game and read its stdout, but cannot open a socket into it,
so this is how the agent drives a live instance. The in-game server (scenes/general/command_server.gd)
listens on 127.0.0.1 and speaks a line-delimited text protocol.

Usage:
    python3 tools/gcmd.py "tp 600 300"
    python3 tools/gcmd.py pos
    python3 tools/gcmd.py --port 9080 'scene().get_node("Player").speed'

Port resolution: --port, else $GODOT_CMD_PORT, else 9080 (matches application/debug/command_port).
"""
import argparse
import os
import socket
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description="Drive the running Godot game via its command server.")
    parser.add_argument("command", nargs="+", help="Command to send (quote it if it has spaces).")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.environ.get("GODOT_CMD_PORT", "9080")))
    parser.add_argument("--timeout", type=float, default=2.0)
    args = parser.parse_args()

    line = " ".join(args.command).strip() + "\n"
    try:
        with socket.create_connection((args.host, args.port), timeout=args.timeout) as sock:
            sock.sendall(line.encode("utf-8"))
            sock.settimeout(args.timeout)
            reply = sock.recv(65536).decode("utf-8", "replace")
    except (ConnectionRefusedError, OSError) as err:
        print(f"gcmd: cannot reach command server at {args.host}:{args.port} ({err})", file=sys.stderr)
        print("Is the game running, and is application/debug/command_port set?", file=sys.stderr)
        return 1
    sys.stdout.write(reply if reply.endswith("\n") else reply + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
