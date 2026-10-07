---
name: domain-ai-decision
description: Deep implementation detail for the AI DECISION sub-domain (scenes/ai/decision/) — the external-model boundary. The round-trip to the local Von "System One" server: the act-centric protocol (two `choice` questions in one request — WHAT to do, and, only if holding, WHERE), argmax/top-pick selection, the decided/failed signals, and the dev-only server launcher. Use when editing scenes/ai/decision/ or working on the Von request/response, the choice questions, how a pick is chosen, the server-down fallback, or auto-starting/reusing the Von server. Complements the light `domain-ai` overview and the `architecture` skill (cross-domain interfaces).
---

# AI · Decision sub-domain (`scenes/ai/decision/`)

The THINK half: the only place the AI talks to the outside model. Von is a stateless single-shot
ranker, so this sub-domain holds no reasoning — it formats the request, POSTs it, and reports the top
pick. The decision context it sends is BUILT by the perception sub-domain; the chosen ids are
INTERPRETED by the behaviour sub-domain. This folder is purely the round-trip + the dev server.

Files:
- `decision_client.gd` — the Von HTTP client (a `Node` owning its `HTTPRequest`).
- `decision_server_launcher.gd` — dev-only `von serve` launcher (a node in `main.tscn`).

## `decision_client.gd`

Configured once by the controller: `configure(server_url, model, timeout)`.

- `request(ctx, npc_name) -> bool` — POST the perception context `{ state_text, acts, moves }` as two
  `choice` questions in one request to `/v1/systemone`:
  - `act` — "What should you do right now?" over the act menu (the real choice).
  - `move` — "If you are just holding, which place should you go to?" over the move menu; the
    behaviour consults the move pick **only** when the chosen act is `hold`.
  It keeps the menus only to validate the pick, and returns whether the request started.
- `is_pending() -> bool` — true while a request is in flight (the controller issues no new decision
  until it completes).
- `signal decided(act_id, move_id)` — emitted with Von's TOP pick for each question. The pick is the
  argmax `choice` when that id is one of this tick's offered options, else the highest-probability
  offered id (ids not offered this tick are ignored, so a stale/foreign id can never be chosen).
  Von's distributions are flat (low confidence), so taking the top pick — not sampling — keeps the NPC
  decisive and goal-coherent instead of jittering.
- `signal failed()` — emitted when a request can't start, the server is unreachable, or the response
  is malformed. The controller wires this to the behaviour's steady-stance `fallback()`, and prints a
  "holding steady" line. The adopted decision log line (`<NPC> (Von) act=… move=… intent=…`) is
  printed by the controller after it hands the pick to the behaviour.

## `decision_server_launcher.gd`

Development convenience: starts a local `von serve` when the game runs **from the editor** (never in
exported builds) and stops it on exit. Uses `von_path` (defaults to the `application/von/server_path`
project setting; blank = don't auto-start). A server already answering on `port` is **reused** and
left running — including one orphaned by a hard-killed previous run — decided by probing `port` up to
`probe_attempts` times. Output is appended to `user://von_server.log` and echoed as `[von] …` lines.
Every NPC shares the one server (its port must match the clients' `server_url`).

Note: `mcp__godot__stop_project` hard-kills Godot, so `_exit_tree` doesn't run and the Von server it
spawned is orphaned on port 8000 — `pkill -f "von serve"` clears it.
